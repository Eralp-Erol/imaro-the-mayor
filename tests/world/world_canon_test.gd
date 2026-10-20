# gdlint:disable=max-public-methods
extends GdUnitTestSuite
## T-001 ölçüt 3 · Dünya-kanon testleri: Ismeral topolojisi (WLD-02, WLD-03, WLD-05, TEK-03).
## Testler TOPOLOJİ ve göreli konum sınar, kesin koordinat sınamaz (koordinatlar AÇIK, F02/F04). Her değişmezin
## OLUMSUZ karşılığı vardır: bilerek bozulmuş kontrol verisi bellekte üretilir ve testin KIRMIZI verdiği doğrulanır.
## Körfez testindeki "batıya açılan, üç yanı karayla çevrili" kanon kelimesi değil, Referans B'nin OY yorumudur.
## Testler kanon olmayan çıkarımlara (D1 kuzey/D6 güney, ada kimliği/sayısı, sabit koordinat) BAĞLANMAZ: bozulmuş
## varyantlar veriden türetilir ve meşru veri düzenlemeleri (çapa takası, liman kayması, ada ekle/sil) yeşil kalır.

var _world: WorldData
var _bay: Dictionary


func before() -> void:
	_world = WorldTestSupport.default_world()
	_bay = WorldInvariants.analyze_bay(_world)


func _violations_contain(violations: PackedStringArray, needle: String) -> bool:
	for v in violations:
		if v.contains(needle):
			return true
	return false


func _mutate(mutation: Callable) -> WorldData:
	var control := WorldTestSupport.control()
	mutation.call(control)
	return WorldTestSupport.coarse(control)


## İki bölgenin çapa ve yarıçaplarını takas eder (meşru düzenleme VEYA ihlal üretimi için; çağıran bilir).
func _swap_regions(control: Dictionary, code_a: String, code_b: String) -> void:
	var a := WorldTestSupport.region_entry(control, code_a)
	var b := WorldTestSupport.region_entry(control, code_b)
	for key in ["anchor_km", "radius_km"]:
		var tmp: Variant = a[key]
		a[key] = b[key]
		b[key] = tmp


# --- Tüm değişmezler sağlıklı veride boş ---

func test_all_world_invariants_hold_for_ismeral_t0_data() -> void:
	var violations := WorldInvariants.check_all(_world)
	assert_array(violations).override_failure_message("ihlaller: %s" % [violations]).is_empty()


func test_all_world_invariants_hold_at_coarser_resolutions_too() -> void:
	# Aynı coğrafya her ölçekte (WLD-01): 250 m ve 400 m hücrede de aynı topoloji.
	assert_array(WorldInvariants.check_all(WorldTestSupport.medium(WorldTestSupport.control()))).is_empty()
	assert_array(WorldInvariants.check_all(WorldTestSupport.coarse(WorldTestSupport.control()))).is_empty()


# --- Maske/yükseklik tutarlılığı ---

func test_mask_and_heights_agree_negative_when_a_land_sample_is_sunk() -> void:
	var broken := WorldTestSupport.coarse(WorldTestSupport.control())
	var land_idx := broken.land_mask.find(1)
	broken.heights[land_idx] = broken.sea_level - 3.0
	assert_bool(_violations_contain(WorldInvariants.check_mask_height_consistency(broken), "kara")).is_true()
	var water_idx := broken.land_mask.find(0)
	var broken2 := WorldTestSupport.coarse(WorldTestSupport.control())
	broken2.heights[water_idx] = broken2.sea_level + 3.0
	assert_bool(_violations_contain(WorldInvariants.check_mask_height_consistency(broken2), "su")).is_true()


# --- Körfez topolojisi (OY yorumu: batıya açılan, üç yanı karayla çevrili su kütlesi) ---

func test_bay_is_a_large_water_body_open_to_the_west_and_closed_on_three_sides() -> void:
	assert_array(WorldInvariants.check_bay_topology(_world, _bay)).is_empty()
	assert_float(_bay["area_km2"]).is_greater(WorldInvariants.MIN_BAY_AREA_KM2)
	assert_float(_bay["mouth_west_fraction"]).is_greater_equal(0.8)
	assert_int(_bay["mouth_east_count"]).is_equal(0)
	assert_int(_bay["north_cells"]).is_greater(WorldInvariants.MIN_COAST_CELLS)
	assert_int(_bay["south_cells"]).is_greater(WorldInvariants.MIN_COAST_CELLS)
	assert_int(_bay["east_cells"]).is_greater(WorldInvariants.MIN_COAST_CELLS)


func test_bay_negative_flattened_coast_has_no_bay() -> void:
	var world := _mutate(func(c: Dictionary) -> void: WorldTestSupport.straighten_coast(c))
	var violations := WorldInvariants.check_bay_topology(world)
	assert_bool(_violations_contain(violations, "körfez yok/dolmuş")).override_failure_message(str(violations)).is_true()


func test_bay_negative_mirrored_coast_opens_to_the_east() -> void:
	var world := _mutate(func(c: Dictionary) -> void: WorldTestSupport.mirror_coast_x(c))
	var violations := WorldInvariants.check_bay_topology(world)
	assert_bool(_violations_contain(violations, "batıya açılmıyor")).override_failure_message(str(violations)).is_true()


func test_bay_negative_sealed_mouth_makes_a_lake() -> void:
	var world := _mutate(func(c: Dictionary) -> void: WorldTestSupport.seal_bay_mouth(c))
	var violations := WorldInvariants.check_bay_topology(world)
	assert_bool(_violations_contain(violations, "kapalı göl")).override_failure_message(str(violations)).is_true()


# --- D1–D6 yerleşimi ---

func test_regions_d1_to_d6_exist_with_relative_positions_and_d2_touches_the_bay() -> void:
	assert_array(WorldInvariants.check_region_layout(_world, _bay)).is_empty()
	for code in WorldControlData.REGION_CODES:
		assert_object(_world.region_by_code(StringName(code))).is_not_null()
	assert_int(WorldInvariants.bay_shore_cells(_world, _bay, &"D2").size()).is_greater(WorldInvariants.MIN_COAST_CELLS)


func test_region_negative_d2_moved_inland_no_longer_touches_the_bay() -> void:
	# D2, D4'ün iç (kuzey) kenarına taşınır: körfezden uzak iç kesim (veriden türetilmiş: sabit koordinat yok).
	var world := _mutate(func(c: Dictionary) -> void:
		var d4 := WorldTestSupport.region_entry(c, "D4")
		WorldTestSupport.region_entry(c, "D2")["anchor_km"] = [
			float(d4["anchor_km"][0]), float(d4["anchor_km"][1]) - float(d4["radius_km"][1])])
	assert_bool(_violations_contain(WorldInvariants.check_region_layout(world), "D2 körfeze değmiyor")).is_true()


func test_region_negative_d3_east_of_d4_is_rejected() -> void:
	# D3 ve D4 çapa/yarıçapları takas edilir: D3 D4'ün doğusuna düşer.
	var world := _mutate(func(c: Dictionary) -> void: _swap_regions(c, "D3", "D4"))
	assert_bool(_violations_contain(WorldInvariants.check_region_layout(world), "D3 (x=")).is_true()


func test_region_negative_d4_on_the_coast_is_not_inland() -> void:
	# D4, körfez kıyısındaki D2 çapasına ve ince bir banda taşınır: kıyıda, iç kesim değil.
	var world := _mutate(func(c: Dictionary) -> void:
		var d4 := WorldTestSupport.region_entry(c, "D4")
		d4["anchor_km"] = WorldTestSupport.region_entry(c, "D2")["anchor_km"].duplicate()
		d4["radius_km"] = [8.0, 2.0])
	assert_bool(_violations_contain(WorldInvariants.check_region_layout(world), "D4 iç kesimde")).is_true()


func test_d4_is_inland_and_east_of_d3() -> void:
	var d3 := _world.region_by_code(&"D3")
	var d4 := _world.region_by_code(&"D4")
	assert_float(d4.centroid.x).is_greater(d3.centroid.x)
	assert_float(WorldInvariants.mean_shore_distance(_world, &"D4")).is_greater(WorldInvariants.D4_MIN_INLAND_M)


# --- WLD-05: D1 ve D6 karşı kıyılarda, aralarında su ---

func test_d1_and_d6_face_each_other_across_water() -> void:
	assert_array(WorldInvariants.check_d1_d6_opposite_shores(_world, _bay)).is_empty()
	# Bağımsız ölçüm: iki bölgenin çapaları arasındaki doğru parçası çoğunlukla su.
	var d1 := _world.region_by_code(&"D1")
	var d6 := _world.region_by_code(&"D6")
	var a := d1.centroid
	var b := d6.centroid
	var water_samples := 0
	var steps := 40
	for k in steps + 1:
		var p := a.lerp(b, float(k) / steps)
		if _world.is_water(p.x, p.y):
			water_samples += 1
	assert_int(water_samples).is_greater(int(0.15 * steps))
	assert_float(a.distance_to(b)).is_less(WorldInvariants.MAX_D1_D6_CROSSING_M * 2.0)


@warning_ignore("integer_division")
func test_d1_d6_negative_merged_regions_are_rejected() -> void:
	# D6, D1'in körfez kıyısındaki bir noktaya küçük bir daire olarak yerleştirilir: iki bölge aynı kıyıda bitişir ve
	# tek mahalleye dönüşür (WLD-05). Konum D1'in kendi kıyı hücresinden türetilir (sabit koordinat yok).
	var shore := WorldInvariants.bay_shore_cells(_world, _bay, &"D1")
	var idx := shore[shore.size() / 2]
	var at := _world.cell_to_world(idx % _world.width, idx / _world.width) / 1000.0
	var world := _mutate(func(c: Dictionary) -> void:
		var d6 := WorldTestSupport.region_entry(c, "D6")
		d6["anchor_km"] = [at.x, at.y]
		d6["radius_km"] = [3.0, 3.0])
	var violations := WorldInvariants.check_d1_d6_opposite_shores(world)
	assert_bool(_violations_contain(violations, "WLD-05")).override_failure_message(str(violations)).is_true()


func test_d1_d6_negative_without_a_bay_there_is_no_water_between() -> void:
	var world := _mutate(func(c: Dictionary) -> void: WorldTestSupport.straighten_coast(c))
	var violations := WorldInvariants.check_d1_d6_opposite_shores(world)
	assert_bool(_violations_contain(violations, "aynı körfez kıyısında")).is_true()


func test_d1_d6_negative_land_bridge_removes_the_water_between() -> void:
	# D1 ve D6 ağırlık merkezleri arasına kalın bir kara köprüsü (körfezi doldurma senaryosu); konum veriden türetilir.
	var a := WorldTestSupport.region_centroid_km(_world, &"D1")
	var b := WorldTestSupport.region_centroid_km(_world, &"D6")
	var world := _mutate(func(c: Dictionary) -> void:
		(c["coast"]["islands"] as Array).append({
			"id": "TEST_BRIDGE", "peak_m": 8, "t0_tags": [],
			"outline_km": WorldTestSupport.strip_outline_km(a, b, 1.2)}))
	var violations := WorldInvariants.check_d1_d6_opposite_shores(world)
	assert_bool(_violations_contain(violations, "kara dolambacı")).override_failure_message(str(violations)).is_true()


func test_d1_d6_relation_is_axis_independent_swapping_their_anchors_stays_green() -> void:
	# D1 kuzey/D6 güney kanon değil (veri notu: düzenlenebilir ÇIKARIM): çapalar takas edilince tüm değişmezler yeşil.
	var world := _mutate(func(c: Dictionary) -> void: _swap_regions(c, "D1", "D6"))
	var violations := WorldInvariants.check_all(world)
	assert_array(violations).override_failure_message(str(violations)).is_empty()
	var d1 := world.region_by_code(&"D1")
	var d6 := world.region_by_code(&"D6")
	assert_float(d1.centroid.y).is_greater(d6.centroid.y)  # gerçekten takas edildi (D1 artık güneyde)


# --- WLD-03: T0 liman sahası ana karada, D4'ün batısında, adada değil ---

func test_t0_port_is_on_the_mainland_coast_west_of_d4_and_on_no_island() -> void:
	assert_array(WorldInvariants.check_t0_port_on_mainland_west_of_d4(_world)).is_empty()
	var port := _world.port_site
	assert_object(port).is_not_null()
	assert_int(_world.landmass_at(port.position.x, port.position.y)).is_equal(WorldData.LANDMASS_MAINLAND)
	assert_bool(_world.is_water(port.position.x, port.position.y)).is_false()
	assert_float(port.position.x).is_less(_world.region_by_code(&"D4").centroid.x)
	for island in _world.islands:
		assert_int(island.landmass_id).is_not_equal(_world.landmass_at(port.position.x, port.position.y))


func test_port_negative_on_an_island_is_rejected() -> void:
	# Liman, verideki İLK adanın ortasına taşınır (ada kimliği/sayısı kilitli değil).
	var world := _mutate(func(c: Dictionary) -> void:
		var center := WorldTestSupport.outline_center_km(WorldTestSupport.first_island_entry(c))
		WorldTestSupport.site_entry(c, "t0_port")["pos_km"] = [center.x, center.y])
	var violations := WorldInvariants.check_t0_port_on_mainland_west_of_d4(world)
	assert_bool(_violations_contain(violations, "adada olamaz")).override_failure_message(str(violations)).is_true()


func test_port_negative_east_of_d4_is_rejected() -> void:
	var world := _mutate(func(c: Dictionary) -> void:
		WorldTestSupport.site_entry(c, "t0_port")["pos_km"] = _just_east_of_d4_km(c))
	var violations := WorldInvariants.check_t0_port_on_mainland_west_of_d4(world)
	assert_bool(_violations_contain(violations, "D4'ün batısında")).override_failure_message(str(violations)).is_true()


func test_port_negative_in_the_sea_is_rejected() -> void:
	# Limanın kuzey-güney konumu korunur, batı harita kenarına (açık denize) alınır.
	var world := _mutate(func(c: Dictionary) -> void:
		var site := WorldTestSupport.site_entry(c, "t0_port")
		site["pos_km"] = [0.5, site["pos_km"][1]])
	assert_bool(_violations_contain(WorldInvariants.check_t0_port_on_mainland_west_of_d4(world), "suda")).is_true()


## D4'ün doğu ucunun 1 km doğusunda, D4 çapasının enleminde bir nokta (km): kontrol verisinden türetilir.
func _just_east_of_d4_km(control: Dictionary) -> Array:
	var d4 := WorldTestSupport.region_entry(control, "D4")
	return [float(d4["anchor_km"][0]) + float(d4["radius_km"][0]) + 1.0, float(d4["anchor_km"][1])]


func test_port_negative_missing_site_is_rejected() -> void:
	var world := _mutate(func(c: Dictionary) -> void: c["sites"]["sites"] = [])
	var violations := WorldInvariants.check_t0_port_on_mainland_west_of_d4(world)
	assert_bool(_violations_contain(violations, "tanımlı değil")).is_true()


# --- WLD-03: T0 ilk ana sanayi de ana karada ve D4'ün batısında ---

func test_t0_first_industry_is_on_the_mainland_west_of_d4() -> void:
	assert_array(WorldInvariants.check_t0_first_industry_on_mainland_west_of_d4(_world)).is_empty()
	var site := _world.site_by_id(&"t0_first_industry")
	assert_object(site).is_not_null()
	assert_int(_world.landmass_at(site.position.x, site.position.y)).is_equal(WorldData.LANDMASS_MAINLAND)
	assert_float(site.position.x).is_less(_world.region_by_code(&"D4").centroid.x)


func test_first_industry_negative_east_of_d4_is_rejected() -> void:
	var world := _mutate(func(c: Dictionary) -> void:
		WorldTestSupport.site_entry(c, "t0_first_industry")["pos_km"] = _just_east_of_d4_km(c))
	var violations := WorldInvariants.check_t0_first_industry_on_mainland_west_of_d4(world)
	assert_bool(_violations_contain(violations, "D4'ün batısında değil")).override_failure_message(
			str(violations)).is_true()
	# Yalnız sanayi taşındı: liman kuralı etkilenmez (kurallar birbirinden bağımsız).
	assert_array(WorldInvariants.check_t0_port_on_mainland_west_of_d4(world)).is_empty()
	assert_bool(WorldInvariants.check_all(world).is_empty()).is_false()


func test_first_industry_negative_on_an_island_is_rejected() -> void:
	var world := _mutate(func(c: Dictionary) -> void:
		var center := WorldTestSupport.outline_center_km(WorldTestSupport.first_island_entry(c))
		WorldTestSupport.site_entry(c, "t0_first_industry")["pos_km"] = [center.x, center.y])
	var violations := WorldInvariants.check_t0_first_industry_on_mainland_west_of_d4(world)
	assert_bool(_violations_contain(violations, "adada olamaz")).override_failure_message(str(violations)).is_true()


func test_first_industry_negative_missing_site_is_rejected() -> void:
	var world := _mutate(func(c: Dictionary) -> void:
		var kept: Array = []
		for site: Dictionary in c["sites"]["sites"]:
			if site["kind"] != "first_industry":
				kept.append(site)
		c["sites"]["sites"] = kept)
	var violations := WorldInvariants.check_t0_first_industry_on_mainland_west_of_d4(world)
	assert_bool(_violations_contain(violations, "tanımlı değil")).is_true()


# --- WLD-03: adalar var, T0'da liman/sanayi etiketi yok ---

func test_islands_exist_and_carry_no_t0_port_or_industry() -> void:
	assert_array(WorldInvariants.check_islands_have_no_t0_port_or_industry(_world)).is_empty()
	assert_int(_world.islands.size()).is_greater_equal(1)
	for island in _world.islands:
		assert_int(island.landmass_id).is_greater(WorldData.LANDMASS_MAINLAND)
		assert_float(island.area_m2).is_greater(0.0)
		for tag in WorldInvariants.FORBIDDEN_ISLAND_TAGS:
			assert_bool(tag in island.t0_tags).is_false()


func test_island_negative_port_tag_is_rejected() -> void:
	var world := _mutate(func(c: Dictionary) -> void:
		WorldTestSupport.first_island_entry(c)["t0_tags"] = ["natural", "port"])
	assert_bool(_violations_contain(WorldInvariants.check_islands_have_no_t0_port_or_industry(world), "'port'")).is_true()


func test_island_negative_industry_site_on_an_island_is_rejected() -> void:
	var world := _mutate(func(c: Dictionary) -> void:
		var center := WorldTestSupport.outline_center_km(WorldTestSupport.first_island_entry(c))
		(c["sites"]["sites"] as Array).append({"id": "bad_industry", "kind": "industry", "pos_km": [center.x, center.y]}))
	var violations := WorldInvariants.check_islands_have_no_t0_port_or_industry(world)
	assert_bool(_violations_contain(violations, "bad_industry")).is_true()


func test_island_negative_no_islands_is_rejected() -> void:
	var world := _mutate(func(c: Dictionary) -> void: c["coast"]["islands"] = [])
	var violations := WorldInvariants.check_islands_have_no_t0_port_or_industry(world)
	assert_bool(_violations_contain(violations, "en az 1 ada")).is_true()


func test_island_negative_island_merged_into_the_mainland_is_not_an_island() -> void:
	var world := _mutate(func(c: Dictionary) -> void: WorldTestSupport.seal_bay_mouth(c))
	var violations := WorldInvariants.check_islands_have_no_t0_port_or_industry(world)
	assert_bool(_violations_contain(violations, "TEST_BARRIER")).is_true()


# --- WLD-02: D4 iç ovası D5 yamaçlarından belirgin düz/alçak ---

func test_d4_plain_is_clearly_flatter_and_lower_than_d5_slopes() -> void:
	assert_array(WorldInvariants.check_d4_plain_vs_d5_slopes(_world)).is_empty()
	var d4 := WorldInvariants.region_stats(_world, &"D4")
	var d5 := WorldInvariants.region_stats(_world, &"D5")
	assert_float(d4["mean_height"]).is_less(d5["mean_height"] * WorldInvariants.D4_VS_D5_MAX_HEIGHT_RATIO)
	assert_float(d4["mean_slope_deg"]).is_less(d5["mean_slope_deg"] * WorldInvariants.D4_VS_D5_MAX_SLOPE_RATIO)


func test_plain_negative_swapped_d4_and_d5_is_rejected() -> void:
	var world := _mutate(func(c: Dictionary) -> void:
		var d4 := WorldTestSupport.region_entry(c, "D4")
		var d5 := WorldTestSupport.region_entry(c, "D5")
		var anchor: Array = d4["anchor_km"]
		var radius: Array = d4["radius_km"]
		d4["anchor_km"] = d5["anchor_km"]
		d4["radius_km"] = d5["radius_km"]
		d5["anchor_km"] = anchor
		d5["radius_km"] = radius)
	assert_array(WorldInvariants.check_d4_plain_vs_d5_slopes(world)).is_not_empty()


func test_plain_negative_flattened_mountains_make_d5_no_slope() -> void:
	var world := _mutate(func(c: Dictionary) -> void:
		for massif: Dictionary in c["terrain"]["massifs"]:
			massif["peak_m"] = 0.0
		c["terrain"]["relief_noise"]["amplitude_m"] = 4.0)
	assert_bool(_violations_contain(WorldInvariants.check_d4_plain_vs_d5_slopes(world), "D5")).is_true()


# --- Meşru veri düzenlemeleri yeşil kalır (koordinatlar/ada sayısı kilitli değil) ---

func test_legitimate_port_shift_of_400_m_stays_green() -> void:
	for shift in [Vector2(0.4, 0.0), Vector2(-0.4, 0.0), Vector2(0.0, 0.4), Vector2(0.0, -0.4)]:
		var world := _mutate(func(c: Dictionary) -> void:
			var site := WorldTestSupport.site_entry(c, "t0_port")
			site["pos_km"] = [float(site["pos_km"][0]) + shift.x, float(site["pos_km"][1]) + shift.y])
		var violations := WorldInvariants.check_all(world)
		assert_array(violations).override_failure_message("kayma %s: %s" % [shift, violations]).is_empty()


func test_legitimate_island_removal_and_addition_stay_green() -> void:
	# İlk dört ada silinir (I1–I4 kimliğine bağlı test yok); kalan adalar + yeni bir ada eklenir.
	var removed := _mutate(func(c: Dictionary) -> void:
		var islands: Array = c["coast"]["islands"]
		for _k in mini(4, islands.size() - 1):
			islands.remove_at(0))
	assert_array(WorldInvariants.check_all(removed)).is_empty()
	assert_int(removed.islands.size()).is_greater_equal(1)
	var added := _mutate(func(c: Dictionary) -> void:
		var size_km: Array = c["world"]["size_km"]
		var at := Vector2(1.6, float(size_km[1]) * 0.15)
		(c["coast"]["islands"] as Array).append({
			"id": "NEW_ISLAND", "peak_m": 20, "t0_tags": ["natural"],
			"outline_km": WorldTestSupport.strip_outline_km(at, at + Vector2(0.9, 0.5), 0.35)}))
	assert_array(WorldInvariants.check_all(added)).is_empty()
	assert_int(added.islands.size()).is_equal(WorldTestSupport.coarse(WorldTestSupport.control()).islands.size() + 1)


func test_single_island_data_is_enough() -> void:
	var world := _mutate(func(c: Dictionary) -> void:
		var islands: Array = c["coast"]["islands"]
		while islands.size() > 1:
			islands.pop_back())
	assert_array(WorldInvariants.check_all(world)).is_empty()
	assert_int(world.islands.size()).is_equal(1)


# --- Batimetri: iç körfez açık denizden SIĞ veya eşit, "çukur" değil ---

func test_inner_bay_is_not_deeper_than_open_sea_at_equal_shore_distance() -> void:
	assert_array(WorldInvariants.check_inner_bay_not_deeper_than_open_sea(_world, _bay)).is_empty()
	var bay_mask: PackedByteArray = _bay["mask"]
	var bay_sum := 0.0
	var bay_n := 0
	var open_sum := 0.0
	var open_n := 0
	for idx in bay_mask.size():
		if _world.land_mask[idx] == 1:
			continue
		var depth := _world.sea_level - _world.heights[idx]
		if bay_mask[idx] == 1:
			bay_sum += depth
			bay_n += 1
		else:
			open_sum += depth
			open_n += 1
	assert_float(bay_sum / bay_n).is_less(open_sum / open_n)


func test_bathymetry_negative_a_pit_shaped_bay_is_rejected() -> void:
	# İç körfez derinliği açık denizinkinin 2.2 katına çıkarılır: "çukur" kırmızı verir.
	var world := _mutate(func(c: Dictionary) -> void:
		c["terrain"]["bathymetry"]["enclosed_shelf"]["inner_factor"] = 2.2)
	var violations := WorldInvariants.check_inner_bay_not_deeper_than_open_sea(world)
	assert_bool(_violations_contain(violations, "çukur")).override_failure_message(str(violations)).is_true()


func test_bathymetry_depth_still_grows_with_distance_from_shore() -> void:
	# Derinlik kıyı uzaklığına bağlı: kıyıdan uzaklaştıkça (kutu ortalaması) azalmaz.
	var prev_mean := 0.0
	for bin in 6:
		var sum := 0.0
		var n := 0
		for idx in _world.heights.size():
			if _world.land_mask[idx] == 0 and int(absf(_world.shore_distance[idx]) / 1000.0) == bin:
				sum += _world.sea_level - _world.heights[idx]
				n += 1
		assert_int(n).is_greater(0)
		assert_float(sum / n).is_greater_equal(prev_mean)
		prev_mean = sum / n


# --- Ham API ---

@warning_ignore("integer_division")
func test_world_data_api_answers_basic_questions_consistently() -> void:
	# Konumlar WorldData'dan türetilir: sabit hücre/koordinat veya liman bölgesi varsayımı yok.
	assert_bool(_world.contains(_world.origin.x, _world.origin.y)).is_true()
	assert_bool(_world.contains(_world.origin.x - 1.0, _world.origin.y)).is_false()
	var water_idx := _world.land_mask.find(0)
	assert_int(water_idx).is_greater_equal(0)
	var wp := _world.cell_to_world(water_idx % _world.width, water_idx / _world.width)
	assert_bool(_world.is_water(wp.x, wp.y)).is_true()
	assert_float(_world.depth_at(wp.x, wp.y)).is_greater(0.0)
	assert_int(_world.landmass_at(wp.x, wp.y)).is_equal(WorldData.LANDMASS_WATER)
	assert_int(_world.region_at(wp.x, wp.y)).is_equal(WorldData.REGION_NONE)
	var d1 := _world.region_by_code(&"D1")
	var land_idx := _world.region_ids.find(d1.id)
	assert_int(land_idx).is_greater_equal(0)
	var lp := _world.cell_to_world(land_idx % _world.width, land_idx / _world.width)
	assert_bool(_world.is_water(lp.x, lp.y)).is_false()
	assert_float(_world.depth_at(lp.x, lp.y)).is_equal(0.0)
	assert_int(_world.region_at(lp.x, lp.y)).is_equal(d1.id)
	assert_str(str(_world.region_code_at(lp.x, lp.y))).is_equal("D1")
	# Örnek noktasında bilineer yükseklik örnek değerine eşit (harita ortasındaki hücre).
	var ci := _world.width / 3
	var cj := _world.height / 2
	var idx := cj * _world.width + ci
	var p := _world.cell_to_world(ci, cj)
	assert_float(_world.height_at(p.x, p.y)).is_equal_approx(_world.heights[idx], 0.0001)
	assert_float(_world.slope_degrees_at(p.x, p.y)).is_between(0.0, 90.0)
