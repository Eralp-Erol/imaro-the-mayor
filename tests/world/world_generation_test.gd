# gdlint:disable=max-public-methods
extends GdUnitTestSuite
## T-001 ölçüt 1–2 · Veri yükleme + tohumlu deterministik üreteç (TEK-01/02, WLD-01, TEK-03).
## Aynı kontrol verisi + aynı tohum → aynı hash; farklı tohum → farklı hash; hücre boyutu coğrafyayı değiştirmez.

const SOURCE_FILES: Array[String] = [
	"res://src/world/world_generator.gd", "res://src/world/world_grid.gd",
	"res://src/world/world_data.gd", "res://src/world/world_invariants.gd",
	"res://src/world/world_control_data.gd", "res://src/world/world_terrace.gd",
]

## Rölyef ölçüleri (sanat yönü ayarı; kanon değil).
const MIN_HIGHEST_SUMMIT_M := 800.0
const MIN_D5_MEAN_SLOPE_DEG := 10.0
const MAX_D4_MEAN_SLOPE_DEG := 3.0
const MIN_STEEP_MAINLAND_FRACTION := 0.10  # eğimi > 15° olan ana kara oranı

var _default_world: WorldData


func before() -> void:
	# Varsayılan çözünürlük (veri dosyasındaki hücre boyutu) bir kez üretilir.
	_default_world = WorldTestSupport.default_world()


# --- Ölçüt 1: veri dosyaları ---

func test_control_data_files_load_and_pass_schema() -> void:
	var control := WorldTestSupport.control()
	assert_int(control.size()).is_equal(WorldControlData.FILES.size())
	assert_array(WorldControlData.validate(control)).is_empty()


func test_every_data_file_carries_the_canon_direction_header() -> void:
	var control := WorldTestSupport.control()
	for file_name in WorldControlData.FILES:
		var header: String = control[file_name]["_header"]
		assert_str(header).contains("02_ismeral_t0_vs_mature_SELECTED.jpg")
		assert_str(header).contains("(F04 Referans B) ONAYLANMIŞ YÖN yorumu; koordinatlar kilitli değil (F02, F04)")


func test_header_missing_makes_validation_fail() -> void:
	var control := WorldTestSupport.control()
	control["coast"]["_header"] = "kanon dayanağı yok"
	assert_array(WorldControlData.validate(control)).is_not_empty()


func test_only_d2_carries_a_name_orven() -> void:
	var control := WorldTestSupport.control()
	for entry: Dictionary in control["regions"]["regions"]:
		if entry["code"] == "D2":
			assert_str(entry["name"]).is_equal("Orven")
		else:
			assert_str(entry["name"]).is_empty()


func test_naming_a_second_region_is_rejected_by_validation() -> void:
	var control := WorldTestSupport.control()
	WorldTestSupport.region_entry(control, "D3")["name"] = "Limanyaka"
	var errors := WorldControlData.validate(control)
	assert_bool(errors.size() > 0 and "CAN-01" in errors[0]).is_true()


func test_data_directory_has_no_banned_names() -> void:
	# Eski POC adı ve gerçek yer adları veride görünmemeli (CAN-01, D-001).
	var banned := ["Ilgın", "Ilgin", "Konak", "Karşıyaka", "Bornova", "Bayraklı", "Kordon", "Kadifekale"]
	for file_name in WorldControlData.FILES:
		var text := FileAccess.get_file_as_string("%s/%s.json" % [WorldTestSupport.DATA_DIR, file_name])
		for word in banned:
			assert_bool(text.contains(word)).override_failure_message("%s.json içinde '%s'" % [file_name, word]).is_false()


# --- Ölçüt 2: determinizm ---

func test_same_seed_same_hash_at_default_resolution() -> void:
	var again := WorldGenerator.generate(WorldTestSupport.control(), WorldTestSupport.DEFAULT_SEED)
	assert_str(again.state_hash()).is_equal(_default_world.state_hash())
	assert_bool(again.heights == _default_world.heights).is_true()
	assert_bool(again.land_mask == _default_world.land_mask).is_true()
	assert_bool(again.region_ids == _default_world.region_ids).is_true()


func test_hash_is_a_sha256_hex_string() -> void:
	var h := _default_world.state_hash()
	assert_int(h.length()).is_equal(64)
	assert_bool(h.to_lower() == h and h.hex_decode().size() == 32).is_true()


func test_different_seed_different_hash() -> void:
	var control := WorldTestSupport.control()
	var a := WorldTestSupport.coarse(control, 1)
	var b := WorldTestSupport.coarse(control, 2)
	var a2 := WorldTestSupport.coarse(control, 1)
	assert_str(a.state_hash()).is_equal(a2.state_hash())
	assert_str(a.state_hash()).is_not_equal(b.state_hash())
	# Tohum gerçekten kullanılıyor: yükseklik ve kıyı kırıntısı (maske) değişir.
	assert_bool(a.heights == b.heights).is_false()
	assert_bool(a.land_mask == b.land_mask).is_false()


func test_seed_changes_detail_but_not_topology() -> void:
	# WLD-09: topolojik sabitler tohuma bağlı değil; her tohumda tüm dünya değişmezleri sağlanır.
	for world_seed in [3, 77, 123456789012]:
		var world := WorldTestSupport.coarse(WorldTestSupport.control(), world_seed)
		var violations := WorldInvariants.check_all(world)
		assert_array(violations).override_failure_message("tohum %d: %s" % [world_seed, violations]).is_empty()


func test_control_data_change_changes_hash() -> void:
	# Kontrol verisi gerçekten kullanılıyor (olumsuz: veri değişince hash aynı kalamaz).
	var base := WorldTestSupport.control()
	var changed := WorldTestSupport.control()
	changed["terrain"]["massifs"][0]["peak_m"] = float(changed["terrain"]["massifs"][0]["peak_m"]) + 400.0
	assert_str(WorldTestSupport.coarse(base).state_hash()).is_not_equal(WorldTestSupport.coarse(changed).state_hash())


func test_cell_size_is_part_of_the_hash() -> void:
	var control := WorldTestSupport.control()
	var a := WorldGenerator.generate(control, 5, {"cell_size_m": 500.0})
	var b := WorldGenerator.generate(control, 5, {"cell_size_m": 400.0})
	assert_str(a.state_hash()).is_not_equal(b.state_hash())


func test_same_geography_at_every_resolution() -> void:
	# WLD-01/TEK-03: farklı hücre boyutu aynı coğrafyayı örnekler (ayrı kıyı çizgisi yok): ortak örneklerde kara/su
	# maskesi birebir aynı, kara yüksekliği yakın.
	var control := WorldTestSupport.control()
	var coarse := WorldGenerator.generate(control, 9, {"cell_size_m": 500.0})
	var fine := WorldGenerator.generate(control, 9, {"cell_size_m": 250.0})
	var mismatched := 0
	var land_diff_sum := 0.0
	var land_n := 0
	for j in coarse.height:
		for i in coarse.width:
			var c := j * coarse.width + i
			var f := (2 * j) * fine.width + 2 * i
			if coarse.land_mask[c] != fine.land_mask[f]:
				mismatched += 1
			elif coarse.land_mask[c] == 1:
				land_diff_sum += absf(coarse.heights[c] - fine.heights[f])
				land_n += 1
	assert_int(mismatched).is_equal(0)
	assert_float(land_diff_sum / land_n).is_less(6.0)


func test_resolution_mismatch_would_be_detected() -> void:
	# Olumsuz: farklı kıyı verisiyle üretilen dünyanın maskesi aynı çözünürlükte bile farklıdır.
	var control := WorldTestSupport.control()
	var shifted := WorldTestSupport.control()
	WorldTestSupport.straighten_coast(shifted)
	var a := WorldTestSupport.coarse(control, 9)
	var b := WorldTestSupport.coarse(shifted, 9)
	assert_bool(a.land_mask == b.land_mask).is_false()


# --- Üretim çıktısının biçimi ---

func test_default_world_dimensions_and_rasters() -> void:
	var w := _default_world
	assert_vector(w.size).is_equal(Vector2(40000.0, 40000.0))
	assert_float(w.cell_size).is_equal(100.0)
	assert_int(w.width).is_equal(401)
	assert_int(w.height).is_equal(401)
	assert_int(w.heights.size()).is_equal(401 * 401)
	assert_int(w.land_mask.size()).is_equal(401 * 401)
	assert_int(w.region_ids.size()).is_equal(401 * 401)


func test_default_world_has_land_water_and_all_regions() -> void:
	var w := _default_world
	var land := 0
	for v in w.land_mask:
		land += v
	var fraction := float(land) / w.land_mask.size()
	# Su da kara da anlamlı pay taşır (boş deniz/boş kara değil).
	assert_float(fraction).is_between(0.45, 0.9)
	assert_int(w.regions.size()).is_equal(6)
	for r in w.regions:
		assert_int(r.cell_count).is_greater(100)


func test_floats_are_finite_and_land_is_above_sea() -> void:
	var w := _default_world
	var non_finite := 0
	for h in w.heights:
		if not is_finite(h):
			non_finite += 1
	assert_int(non_finite).is_equal(0)
	assert_array(WorldInvariants.check_mask_height_consistency(w)).is_empty()


# --- Rölyef: dağ gibi okunan masifler, düz plato olmayan adalar (sanat yönü ölçümü; eşikler ayar, kanon değil) ---

@warning_ignore("integer_division")
func _steep_mainland_fraction(world: WorldData) -> float:
	var steep := 0
	var n := 0
	for idx in world.heights.size():
		if world.landmass_ids[idx] == WorldData.LANDMASS_MAINLAND:
			n += 1
			if WorldInvariants._cell_slope_deg(world, idx % world.width, idx / world.width) > 15.0:
				steep += 1
	return float(steep) / maxf(n, 1.0)


func test_massifs_read_as_mountains_high_summits_and_steep_flanks() -> void:
	var w := _default_world
	var highest := 0.0
	for h in w.heights:
		highest = maxf(highest, h)
	assert_float(highest).is_greater(MIN_HIGHEST_SUMMIT_M)
	assert_float(WorldInvariants.region_stats(w, &"D5")["mean_slope_deg"]).is_greater(MIN_D5_MEAN_SLOPE_DEG)
	assert_float(_steep_mainland_fraction(w)).is_greater(MIN_STEEP_MAINLAND_FRACTION)
	# D4 ovası yine belirgin düz (WLD-02): rölyef artışı ovayı bozmaz.
	assert_float(WorldInvariants.region_stats(w, &"D4")["mean_slope_deg"]).is_less(MAX_D4_MEAN_SLOPE_DEG)


func test_relief_negative_flat_relief_data_fails_the_mountain_measure() -> void:
	# Olumsuz: sırt ve yumuşak gürültü kapatılınca dağ ölçüleri kırmızı (ölçü gerçekten kırılabilir).
	var control := WorldTestSupport.control()
	control["terrain"]["ridge"]["amplitude_m"] = 0.0
	control["terrain"]["relief_noise"]["amplitude_m"] = 0.0
	var flat := WorldTestSupport.medium(control)
	assert_float(WorldInvariants.region_stats(flat, &"D5")["mean_slope_deg"]).is_less(MIN_D5_MEAN_SLOPE_DEG)
	assert_float(_steep_mainland_fraction(flat)).is_less(MIN_STEEP_MAINLAND_FRACTION)


@warning_ignore("integer_division")
## Ada başına {tepe, çeyrek-dilim yükseklik}: yükseklik dağılımının tepesi ve %25'lik dilimi (m, deniz seviyesi üstü).
func _island_height_profile(world: WorldData) -> Dictionary:
	var by_landmass := {}
	for idx in world.heights.size():
		var lm := world.landmass_ids[idx]
		if lm > WorldData.LANDMASS_MAINLAND:
			if not by_landmass.has(lm):
				by_landmass[lm] = []
			(by_landmass[lm] as Array).append(world.heights[idx] - world.sea_level)
	var out := {}
	for lm in by_landmass:
		var values: Array = by_landmass[lm]
		values.sort()
		out[lm] = {"max": float(values[values.size() - 1]), "q25": float(values[values.size() / 4]), "n": values.size()}
	return out


@warning_ignore("integer_division")
func test_islands_are_hills_not_flat_plateaus_and_differ_from_each_other() -> void:
	var profile := _island_height_profile(_default_world)
	assert_int(profile.size()).is_equal(_default_world.islands.size())
	var maxima := {}
	for lm in profile:
		var p: Dictionary = profile[lm]
		# Tepe, ada gövdesinin alt çeyreğinden belirgin yüksek: plato değil (en az 3 m ve tepe/çeyrek oranı > 2).
		assert_float(p["max"] - p["q25"]).is_greater(3.0)
		assert_float(p["max"]).is_greater(2.0 * p["q25"])
		maxima[snappedf(p["max"], 1.0)] = true
	# Adalar birbirinin aynısı değil: tepe yükseklikleri çeşitli.
	assert_int(maxima.size()).is_greater(_default_world.islands.size() / 2)


func test_island_negative_flat_island_data_is_detected_as_plateau() -> void:
	# Olumsuz: tepe 0.5 m'ye indirilirse ada düz plato olur ve ölçüt kırmızı verir.
	var control := WorldTestSupport.control()
	for island: Dictionary in control["coast"]["islands"]:
		island["peak_m"] = 0.5
	var profile := _island_height_profile(WorldTestSupport.medium(control))
	for lm in profile:
		assert_float(profile[lm]["max"] - profile[lm]["q25"]).is_less(3.0)


# --- Saflık (TEK-01/02) ---

func test_generator_sources_have_no_forbidden_apis() -> void:
	for path in SOURCE_FILES:
		assert_str(FileAccess.get_file_as_string(path)).is_not_empty()
		assert_array(WorldTestSupport.forbidden_api_hits(path)).override_failure_message(path).is_empty()


func test_forbidden_api_scan_can_fail() -> void:
	# Olumsuz: tarayıcı gerçekten yakalıyor (self-test; sahte yeşil olmasın).
	var tmp := "user://world_purity_probe.gd"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	f.store_string("func x() -> float:\n\treturn randf() + Time.get_ticks_msec()\n")
	f.close()
	assert_int(WorldTestSupport.forbidden_api_hits(tmp).size()).is_equal(2)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp))
