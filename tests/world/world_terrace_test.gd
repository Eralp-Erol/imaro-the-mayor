extends GdUnitTestSuite
## T-001 M1 · D5 yerleşim sekisi (settlement terrace; WLD-04, ÇALIŞMA MODELİ).
## Kanon: D5 'eğimli mahalleler, küçük merkez, orman/doğal alan' ve T0'da gerçek merkezi/konutu olan bölge.
## Seki D5'in körfeze/ovaya bakan alt yamacında yumuşatılmış
## yerleşilebilir alandır; masif doğuda/yukarıda sert kalır. Testler ÖLÇER; kesin koordinat sınamaz (seki merkezi bölge
## çapasından türetilir). Her değişmezin OLUMSUZ karşılığı vardır (seki kapalı/dik/yok/yanlış yerde → kırmızı).

## Tohumlar: varsayılan + iki ek (sekinin tohumdan bağımsız hedef eğimi tutması beklenir).
const SEEDS: Array[int] = [1467, 7, 9001]
## Ölçü eşikleri (sanat yönü ayarı; WorldInvariants eşiğinden bağımsız ikinci koruma).
const MAX_CORE_SLOPE_DEG := 8.0
const MIN_PEAK_M := 800.0
const MAX_RAMP_MEAN_SLOPE_DEG := 12.0
const MIN_CLIFF_FREE_RATIO := 0.6

var _world: WorldData


func before() -> void:
	_world = WorldTestSupport.default_world()


## Sekinin çekirdeğindeki (kıyı hücresi olmayan) kara örneklerinin eğimleri (derece).
func _core_slopes(world: WorldData, terrace: WorldTerrace) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for j in world.height:
		for i in world.width:
			var idx := j * world.width + i
			if world.land_mask[idx] == 1 and world.shore_distance[idx] >= 2.0 * world.cell_size \
					and terrace.in_core(world.cell_to_world(i, j)):
				out.append(WorldInvariants._cell_slope_deg(world, i, j))
	return out


## Çekirdek dışı, düzlem bandı içindeki (1 < u <= 1 + falloff) kara örneklerinin ort. eğimi.
func _ramp_mean_slope(world: WorldData, terrace: WorldTerrace) -> float:
	var sum := 0.0
	var n := 0
	for j in world.height:
		for i in world.width:
			var idx := j * world.width + i
			if world.land_mask[idx] == 0 or world.shore_distance[idx] < 2.0 * world.cell_size:
				continue
			var u := terrace.normalized_distance(world.cell_to_world(i, j))
			if u > 1.0 and u <= 1.0 + terrace.falloff:
				sum += WorldInvariants._cell_slope_deg(world, i, j)
				n += 1
	return sum / maxf(float(n), 1.0)


func _mean(values: PackedFloat32Array) -> float:
	var sum := 0.0
	for v in values:
		sum += v
	return sum / maxf(float(values.size()), 1.0)


func _max(values: PackedFloat32Array) -> float:
	var m := 0.0
	for v in values:
		m = maxf(m, v)
	return m


func _first_d5_terrace(world: WorldData) -> WorldTerrace:
	var list := world.terraces_of_region(&"D5")
	return null if list.is_empty() else list[0]


func _world_with(edit: Callable, world_seed: int = WorldTestSupport.DEFAULT_SEED, medium: bool = false) -> WorldData:
	var control := WorldTestSupport.control()
	edit.call(control)
	return WorldTestSupport.medium(control, world_seed) if medium else WorldTestSupport.coarse(control, world_seed)


# --- Veri ---

func test_terrace_data_is_declared_for_d5_with_working_model_status_noted() -> void:
	var control := WorldTestSupport.control()
	var entry := WorldTestSupport.terrace_entry(control, "D5")
	assert_bool(entry.is_empty()).is_false()
	assert_str(str(control["terrain"]["_notes"])).contains("ÇALIŞMA MODELİ (ÇM)")
	assert_str(str(entry["basis"])).contains("ÇM")
	assert_array(WorldControlData.validate(control)).is_empty()
	# Sabit koordinat değil: merkez bölge çapasından + normalize ofsetten türetilir.
	assert_bool(entry.has("offset_norm")).is_true()
	assert_bool(entry.has("center_km")).is_false()


func test_terrace_center_follows_the_region_anchor_not_a_hard_coded_point() -> void:
	var base := _world_with(func(_c: Dictionary) -> void: pass)
	var moved := _world_with(func(c: Dictionary) -> void:
		var d5 := WorldTestSupport.region_entry(c, "D5")
		d5["anchor_km"] = [float(d5["anchor_km"][0]) + 1.0, float(d5["anchor_km"][1]) + 0.5])
	var delta := _first_d5_terrace(moved).center - _first_d5_terrace(base).center
	assert_vector(delta).is_equal_approx(Vector2(1000.0, 500.0), Vector2(0.01, 0.01))


# --- Ölçüt: seki alanı eğimi ≤ eşik, her tohumda ---

func test_terrace_core_slope_is_gentle_for_every_seed() -> void:
	for world_seed in SEEDS:
		var world := WorldTestSupport.medium(WorldTestSupport.control(), world_seed)
		var terrace := _first_d5_terrace(world)
		assert_object(terrace).is_not_null()
		var slopes := _core_slopes(world, terrace)
		assert_int(slopes.size()).is_greater(30)
		assert_float(_max(slopes)).override_failure_message("tohum %d" % world_seed).is_less(MAX_CORE_SLOPE_DEG)
		assert_float(_mean(slopes)).is_less(MAX_CORE_SLOPE_DEG)
		assert_float(_mean(slopes)).is_less_equal(terrace.slope_deg + 1.0)  # hedef eğime yakın (mikro rölyef payı)


func test_terrace_is_at_least_two_to_three_km_across_and_on_the_mainland_in_d5() -> void:
	var terrace := _first_d5_terrace(_world)
	assert_float(terrace.radius.x * 2.0).is_between(2000.0, 4000.0)
	assert_float(terrace.radius.y * 2.0).is_between(2000.0, 4000.0)
	assert_int(_world.landmass_at(terrace.center.x, terrace.center.y)).is_equal(WorldData.LANDMASS_MAINLAND)
	assert_str(str(_world.region_code_at(terrace.center.x, terrace.center.y))).is_equal("D5")


# --- Ölçüt: D5 genel olarak hâlâ yamaç, masif zirvesi korunur, seki masifin ALTINDA ---

func test_d5_is_still_a_slope_region_and_massif_summit_is_preserved() -> void:
	for world_seed in SEEDS:
		var world := WorldTestSupport.medium(WorldTestSupport.control(), world_seed)
		var d5 := WorldInvariants.region_stats(world, &"D5")
		assert_float(d5["mean_height"]).override_failure_message("tohum %d" % world_seed) \
				.is_greater(WorldInvariants.D5_MIN_MEAN_HEIGHT_M)
		var region := world.region_by_code(&"D5")
		var peak := 0.0
		var peak_idx := -1
		for idx in world.heights.size():
			if world.region_ids[idx] == region.id and world.heights[idx] > peak:
				peak = world.heights[idx]
				peak_idx = idx
		assert_float(peak).override_failure_message("tohum %d" % world_seed).is_greater(MIN_PEAK_M)
		# Masif sekinin ARKASINDA: zirve sekiden belirgin yüksek ve kıyıdan daha uzak.
		var terrace := _first_d5_terrace(world)
		var core := _core_slopes(world, terrace)
		assert_int(core.size()).is_greater(0)
		assert_float(peak - d5["mean_height"]).is_greater(0.0)
		var terrace_shore := world.shore_distance[world.world_to_index(terrace.center.x, terrace.center.y)]
		assert_float(world.shore_distance[peak_idx]).is_greater(terrace_shore)


func test_terrace_sits_below_the_d5_mean_and_the_slope_beyond_it_rises() -> void:
	var terrace := _first_d5_terrace(_world)
	var core_h := _world.height_at(terrace.center.x, terrace.center.y)
	var d5 := WorldInvariants.region_stats(_world, &"D5")
	assert_float(core_h).is_less(d5["mean_height"])
	# Yukarı yönde (masife) sekinin ötesinde arazi yükselir.
	var beyond := terrace.center + terrace.uphill * terrace.radius.length() * (1.0 + terrace.falloff + 1.0)
	assert_float(_world.height_at(beyond.x, beyond.y)).is_greater(core_h + 50.0)


func test_transition_to_the_massif_is_a_gradual_ramp_not_a_cliff() -> void:
	for world_seed in SEEDS:
		var world := WorldTestSupport.medium(WorldTestSupport.control(), world_seed)
		var terrace := _first_d5_terrace(world)
		var ramp := _ramp_mean_slope(world, terrace)
		assert_float(ramp).override_failure_message("tohum %d" % world_seed).is_less(MAX_RAMP_MEAN_SLOPE_DEG)
		# Rampa seki içinden dik: çekirdek eğimi <= rampa ort. eğimi (sönüm tek yönlü artar).
		assert_float(_mean(_core_slopes(world, terrace))).is_less(ramp + 0.5)


func test_terrace_flattening_removes_ridge_and_relief_noise_smoothly() -> void:
	# Rölyef + sırt kapalı dünyayla karşılaştırınca seki çekirdeği AYNI düzlüğü verir; seki dışı ise dağ gibi kalır.
	var rough := WorldTestSupport.medium(WorldTestSupport.control())
	var calm_control := WorldTestSupport.control()
	calm_control["terrain"]["ridge"]["amplitude_m"] = 0.0
	calm_control["terrain"]["relief_noise"]["amplitude_m"] = 0.0
	var calm := WorldTestSupport.medium(calm_control)
	var t_rough := _first_d5_terrace(rough)
	var t_calm := _first_d5_terrace(calm)
	assert_float(absf(_mean(_core_slopes(rough, t_rough)) - _mean(_core_slopes(calm, t_calm)))).is_less(0.6)


# --- Değişmezler (check_all) ---

func test_check_all_is_green_with_terrace_on_three_seeds() -> void:
	for world_seed in SEEDS:
		var world := WorldTestSupport.coarse(WorldTestSupport.control(), world_seed)
		var violations := WorldInvariants.check_all(world)
		assert_array(violations).override_failure_message("tohum %d: %s" % [world_seed, violations]).is_empty()
	assert_array(WorldInvariants.check_settlement_terraces(_world)).is_empty()


# --- OLUMSUZ: bozulmuş veri → kırmızı ---

func test_terrace_negative_disabled_terrace_makes_the_slope_check_red() -> void:
	for world_seed in [1467, 7]:
		var world := _world_with(func(c: Dictionary) -> void:
			WorldTestSupport.terrace_entry(c, "D5")["enabled"] = false, world_seed, true)
		assert_int(world.terraces_of_region(&"D5").size()).is_equal(1)  # ayak izi listede
		var violations := WorldInvariants.check_settlement_terraces(world)
		assert_array(violations).override_failure_message("tohum %d" % world_seed).is_not_empty()
		assert_str(violations[0]).contains("eğimi")
		assert_array(WorldInvariants.check_all(world)).is_not_empty()


func test_terrace_negative_disabled_terrace_core_is_steep_as_before() -> void:
	var off := _world_with(func(c: Dictionary) -> void:
		WorldTestSupport.terrace_entry(c, "D5")["enabled"] = false, WorldTestSupport.DEFAULT_SEED, true)
	var slopes := _core_slopes(off, _first_d5_terrace(off))
	assert_float(_mean(slopes)).is_greater(MAX_CORE_SLOPE_DEG)


func test_terrace_negative_steep_target_slope_is_rejected() -> void:
	var world := _world_with(func(c: Dictionary) -> void:
		WorldTestSupport.terrace_entry(c, "D5")["slope_deg"] = 18.0, WorldTestSupport.DEFAULT_SEED, true)
	assert_array(WorldInvariants.check_settlement_terraces(world)).is_not_empty()


func test_terrace_negative_missing_terrace_for_d5_is_rejected() -> void:
	var world := _world_with(func(c: Dictionary) -> void:
		c["terrain"]["settlement_terraces"] = [])
	var violations := WorldInvariants.check_settlement_terraces(world)
	assert_int(violations.size()).is_equal(1)
	assert_str(violations[0]).contains("D5")


func test_terrace_negative_center_outside_d5_is_rejected() -> void:
	var world := _world_with(func(c: Dictionary) -> void:
		var d5 := WorldTestSupport.region_entry(c, "D5")
		var entry := WorldTestSupport.terrace_entry(c, "D5")
		# Koordinat sabitlemeden: D5 çapasının tam karşı yanına (iki yarıçap uzağa) taşı.
		entry["offset_norm"] = [-2.5, -2.5]
		assert_str(str(d5["code"])).is_equal("D5"))
	assert_array(WorldInvariants.check_settlement_terraces(world)).is_not_empty()


func test_terrace_negative_schema_errors_are_reported() -> void:
	var control := WorldTestSupport.control()
	WorldTestSupport.terrace_entry(control, "D5")["radius_km"] = [0.0, 1.0]
	assert_array(WorldControlData.validate(control)).is_not_empty()
	control = WorldTestSupport.control()
	WorldTestSupport.terrace_entry(control, "D5")["region"] = "D9"
	assert_array(WorldControlData.validate(control)).is_not_empty()
	control = WorldTestSupport.control()
	WorldTestSupport.terrace_entry(control, "D5")["slope_deg"] = 0.0
	assert_array(WorldControlData.validate(control)).is_not_empty()


func test_terrace_change_changes_the_world_hash() -> void:
	# Seki gerçekten üretimde kullanılıyor: kapatmak ve eğimini değiştirmek hash'i değiştirir.
	var base := _world_with(func(_c: Dictionary) -> void: pass)
	var off := _world_with(func(c: Dictionary) -> void:
		WorldTestSupport.terrace_entry(c, "D5")["enabled"] = false)
	var steeper := _world_with(func(c: Dictionary) -> void:
		WorldTestSupport.terrace_entry(c, "D5")["slope_deg"] = 6.0)
	assert_str(base.state_hash()).is_not_equal(off.state_hash())
	assert_str(base.state_hash()).is_not_equal(steeper.state_hash())
	assert_str(base.state_hash()).is_equal(_world_with(func(_c: Dictionary) -> void: pass).state_hash())


# --- Meşru veri düzenlemeleri yeşil kalır ---

func test_legitimate_terrace_edits_stay_green() -> void:
	var edits: Array[Callable] = [
		func(c: Dictionary) -> void:  # yarıçap küçült
			WorldTestSupport.terrace_entry(c, "D5")["radius_km"] = [1.1, 1.0],
		func(c: Dictionary) -> void:  # yarıçap büyüt
			WorldTestSupport.terrace_entry(c, "D5")["radius_km"] = [1.8, 1.4],
		func(c: Dictionary) -> void:  # merkez ofsetini kaydır
			WorldTestSupport.terrace_entry(c, "D5")["offset_norm"] = [-0.4, -0.3],
		func(c: Dictionary) -> void:  # hedef eğimi değiştir
			WorldTestSupport.terrace_entry(c, "D5")["slope_deg"] = 6.5,
		func(c: Dictionary) -> void:  # bölge çapasını kaydır; seki onunla gider
			var d5 := WorldTestSupport.region_entry(c, "D5")
			d5["anchor_km"] = [float(d5["anchor_km"][0]) + 0.6, float(d5["anchor_km"][1]) + 0.6],
	]
	for k in edits.size():
		var world := _world_with(edits[k], WorldTestSupport.DEFAULT_SEED, true)
		var violations := WorldInvariants.check_all(world)
		assert_array(violations).override_failure_message("düzenleme %d: %s" % [k, violations]).is_empty()


func test_second_terrace_for_another_region_uses_the_same_mechanism() -> void:
	# Genel mekanizma: D2-D6'dan her biri seki alabilir (bu görevde yalnız D5'e uygulanır). D4 ovasına seki eklemek
	# ikinci bir WorldTerrace üretir ve kendi eğim değişmezini taşır.
	var world := _world_with(func(c: Dictionary) -> void:
		(c["terrain"]["settlement_terraces"] as Array).append({
			"id": "TEST_D3_TERRACE", "region": "D3", "offset_norm": [0.0, 0.0], "radius_km": [1.2, 1.2],
			"slope_deg": 3.0}), WorldTestSupport.DEFAULT_SEED, true)
	assert_int(world.terraces.size()).is_equal(2)
	assert_int(world.terraces_of_region(&"D3").size()).is_equal(1)
	assert_array(WorldInvariants.check_settlement_terraces(world)).is_empty()
