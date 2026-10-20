# gdlint:disable=max-public-methods
extends GdUnitTestSuite
## T-001 ölçüt 3 · Dünya-kanon testleri: Ismeral topolojisi (WLD-02, WLD-03, WLD-05, TEK-03).
## Testler TOPOLOJİ ve göreli konum sınar, kesin koordinat sınamaz (koordinatlar AÇIK, F02/F04). Her değişmezin
## OLUMSUZ karşılığı vardır: bilerek bozulmuş kontrol verisi bellekte üretilir ve testin KIRMIZI verdiği doğrulanır.
## Körfez testindeki "batıya açılan, üç yanı karayla çevrili" kanon kelimesi değil, Referans B'nin OY yorumudur.

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
	var world := _mutate(func(c: Dictionary) -> void:
		WorldTestSupport.region_entry(c, "D2")["anchor_km"] = [33.0, 5.5])
	assert_bool(_violations_contain(WorldInvariants.check_region_layout(world), "D2 körfeze değmiyor")).is_true()


func test_region_negative_d3_east_of_d4_is_rejected() -> void:
	var world := _mutate(func(c: Dictionary) -> void:
		WorldTestSupport.region_entry(c, "D3")["anchor_km"] = [30.0, 9.0]
		WorldTestSupport.region_entry(c, "D4")["anchor_km"] = [14.0, 5.0])
	assert_bool(_violations_contain(WorldInvariants.check_region_layout(world), "D3 (x=")).is_true()


func test_region_negative_d4_on_the_coast_is_not_inland() -> void:
	var world := _mutate(func(c: Dictionary) -> void:
		WorldTestSupport.region_entry(c, "D4")["anchor_km"] = [26.0, 18.5]
		WorldTestSupport.region_entry(c, "D4")["radius_km"] = [8.0, 2.0])
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


func test_d1_d6_negative_merged_regions_are_rejected() -> void:
	# D6 çapası D1 burnunun içine taşınır: iki bölge aynı mahalleye dönüşür (WLD-05 ihlali).
	var world := _mutate(func(c: Dictionary) -> void:
		var d6 := WorldTestSupport.region_entry(c, "D6")
		d6["anchor_km"] = [20.6, 20.6]
		d6["radius_km"] = [2.0, 1.8])
	var violations := WorldInvariants.check_d1_d6_opposite_shores(world)
	assert_bool(_violations_contain(violations, "WLD-05")).override_failure_message(str(violations)).is_true()


func test_d1_d6_negative_without_a_bay_there_is_no_water_between() -> void:
	var world := _mutate(func(c: Dictionary) -> void: WorldTestSupport.straighten_coast(c))
	var violations := WorldInvariants.check_d1_d6_opposite_shores(world)
	assert_bool(_violations_contain(violations, "aynı körfez kıyısında")).is_true()


func test_d1_d6_negative_land_bridge_removes_the_water_between() -> void:
	var world := _mutate(func(c: Dictionary) -> void:
		# D1 burnunun ucundan D6 kıyısına bir kara köprüsü (körfezi doldurma senaryosu).
		(c["coast"]["islands"] as Array).append({
			"id": "TEST_BRIDGE", "peak_m": 8, "t0_tags": [],
			"outline_km": [[20.6, 21.0], [21.6, 21.0], [22.6, 21.0], [22.6, 23.0], [22.6, 25.6], [21.6, 25.8],
				[20.6, 25.6], [20.6, 23.0]]}))
	var violations := WorldInvariants.check_d1_d6_opposite_shores(world)
	assert_bool(_violations_contain(violations, "kara dolambacı")).override_failure_message(str(violations)).is_true()


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
	var world := _mutate(func(c: Dictionary) -> void:
		var island := WorldTestSupport.island_entry(c, "I5")
		var center := Vector2.ZERO
		for p: Array in island["outline_km"]:
			center += Vector2(p[0], p[1])
		center /= island["outline_km"].size()
		WorldTestSupport.site_entry(c, "t0_port")["pos_km"] = [center.x, center.y])
	var violations := WorldInvariants.check_t0_port_on_mainland_west_of_d4(world)
	assert_bool(_violations_contain(violations, "adada olamaz")).override_failure_message(str(violations)).is_true()


func test_port_negative_east_of_d4_is_rejected() -> void:
	var world := _mutate(func(c: Dictionary) -> void:
		WorldTestSupport.site_entry(c, "t0_port")["pos_km"] = [29.0, 12.0])
	var violations := WorldInvariants.check_t0_port_on_mainland_west_of_d4(world)
	assert_bool(_violations_contain(violations, "D4'ün batısında")).is_true()


func test_port_negative_in_the_sea_is_rejected() -> void:
	var world := _mutate(func(c: Dictionary) -> void:
		WorldTestSupport.site_entry(c, "t0_port")["pos_km"] = [2.0, 8.0])
	assert_bool(_violations_contain(WorldInvariants.check_t0_port_on_mainland_west_of_d4(world), "suda")).is_true()


func test_port_negative_missing_site_is_rejected() -> void:
	var world := _mutate(func(c: Dictionary) -> void: c["sites"]["sites"] = [])
	var violations := WorldInvariants.check_t0_port_on_mainland_west_of_d4(world)
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
		WorldTestSupport.island_entry(c, "I2")["t0_tags"] = ["natural", "port"])
	assert_bool(_violations_contain(WorldInvariants.check_islands_have_no_t0_port_or_industry(world), "'port'")).is_true()


func test_island_negative_industry_site_on_an_island_is_rejected() -> void:
	var world := _mutate(func(c: Dictionary) -> void:
		(c["sites"]["sites"] as Array).append({"id": "bad_industry", "kind": "first_industry", "pos_km": [8.2, 32.6]}))
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


# --- Ham API ---

func test_world_data_api_answers_basic_questions_consistently() -> void:
	var port := _world.port_site
	assert_bool(_world.contains(port.position.x, port.position.y)).is_true()
	assert_bool(_world.contains(-1.0, 0.0)).is_false()
	assert_bool(_world.is_water(0.0, 20000.0)).is_true()  # batı kenarı açık deniz
	assert_float(_world.depth_at(0.0, 20000.0)).is_greater(20.0)  # açık deniz derin
	assert_float(_world.depth_at(port.position.x, port.position.y)).is_equal(0.0)
	assert_int(_world.region_at(port.position.x, port.position.y)).is_equal(_world.region_by_code(&"D3").id)
	assert_str(str(_world.region_code_at(port.position.x, port.position.y))).is_equal("D3")
	# Örnek noktasında bilineer yükseklik örnek değerine eşit.
	var idx := 200 * _world.width + 150
	var p := _world.cell_to_world(150, 200)
	assert_float(_world.height_at(p.x, p.y)).is_equal_approx(_world.heights[idx], 0.0001)
	assert_float(_world.slope_degrees_at(p.x, p.y)).is_between(0.0, 90.0)
