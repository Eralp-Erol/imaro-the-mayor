extends GdUnitTestSuite
## T-028 ölçüt 3 · doğruluk: haritadaki her değer WorldData/WorldNetwork/T0Settlement'ten TÜRER; işaret sayıları veriyle
## eşit, geometri dünya yüksekliğiyle uyumlu. Olumsuz varyantlar bellekte bozulmuş girdiyle.

var _m: TopologyModel


func before() -> void:
	_m = TopologyTestSupport.full_model()


func test_marker_counts_equal_the_data() -> void:
	assert_int(_m.regions.size()).is_equal(_m.world.regions.size())
	assert_int(_m.regions.size()).is_equal(6)
	assert_int(_m.islands.size()).is_equal(_m.world.islands.size())
	assert_int(_m.sites.size()).is_equal(_m.world.sites.size())
	for i in _m.islands.size():
		assert_str(String(_m.islands[i].id)).is_equal(String(_m.world.islands[i].id))
	for i in _m.regions.size():
		assert_str(String(_m.regions[i].code)).is_equal(String(_m.world.regions[i].code))
	var port_count := 0
	for s in _m.world.sites:
		port_count += 1 if s.kind == &"port" else 0
	var marked := 0
	for s in _m.sites:
		marked += 1 if s.kind == &"port" else 0
	assert_int(marked).is_equal(port_count)
	assert_object(_m.site_mark(&"first_industry")).is_not_null()


func test_only_orven_has_a_name() -> void:
	for r in _m.regions:
		if r.code == &"D2":
			assert_str(r.display_name).is_equal("Orven")
		else:
			assert_str(r.display_name).is_empty()


func test_coast_chains_are_on_the_sea_level_and_island_loops_match_the_data() -> void:
	var island_loops := 0
	var kinds := {}
	for c in _m.coast_chains:
		kinds[c["kind"]] = true
		for p: Vector2 in c["points"]:
			assert_float(absf(_m.world.height_at(p.x, p.y) - _m.world.sea_level)).is_less(0.01)
		if c["kind"] == &"island":
			island_loops += 1
	assert_int(island_loops).is_equal(_m.islands.size())
	assert_bool(kinds.has(&"gulf")).is_true()
	assert_bool(kinds.has(&"open")).is_true()


func test_gulf_and_label_positions_are_where_they_claim() -> void:
	assert_bool(_m.has_gulf).is_true()
	assert_bool(_m.world.is_water(_m.gulf_label_pos.x, _m.gulf_label_pos.y)).is_true()
	assert_bool(_m.world.is_water(_m.open_sea_label_pos.x, _m.open_sea_label_pos.y)).is_true()
	assert_int(_m.world.landmass_at(_m.mainland_label_pos.x, _m.mainland_label_pos.y)).is_equal(
			WorldData.LANDMASS_MAINLAND)
	var gulf_mask: PackedByteArray = _m.bay["mask"]
	assert_int(gulf_mask[_m.world.world_to_index(_m.gulf_label_pos.x, _m.gulf_label_pos.y)]).is_equal(1)


func test_port_and_first_industry_are_on_the_mainland_and_no_island_has_port_tags() -> void:
	assert_array(_m.sites_off_mainland).is_empty()
	assert_array(_m.islands_with_forbidden_tags).is_empty()
	var port := _m.site_mark(&"port")
	assert_bool(port.on_mainland).is_true()
	assert_float(port.shore_m).is_equal(_m.world.shore_distance[_m.world.world_to_index(port.position.x, port.position.y)])
	assert_int(int(_m.yard["count"])).is_greater(0)


func test_contours_lie_at_their_levels_and_shares_sum_to_one() -> void:
	assert_int(_m.contours.size()).is_greater(0)
	var levels := {}
	for c in _m.contours:
		levels[c["level_m"]] = true
		for p: Vector2 in c["points"]:
			assert_float(absf(_m.world.height_at(p.x, p.y) - (_m.world.sea_level + float(c["level_m"])))).is_less(0.01)
	assert_int(levels.size()).is_equal(TopologyModel.CONTOUR_LEVELS_M.size())
	var s := float(_m.land_stats["plain_share"]) + float(_m.land_stats["slope_share"]) + float(
			_m.land_stats["ridge_share"])
	assert_float(s).is_equal_approx(1.0, 1.0e-6)
	assert_float(float(_m.land_stats["plain_share"])).is_between(0.05, 0.95)


func test_density_grid_sums_to_the_settlement_building_count() -> void:
	var total := 0
	for c in _m.density_counts:
		total += c
	assert_int(total).is_equal(_m.result.columns.count)
	assert_int(_m.building_total).is_equal(_m.result.columns.count)
	var in_regions := 0
	for r in _m.regions:
		in_regions += r.buildings
	assert_int(in_regions).is_less_equal(_m.building_total)
	assert_int(in_regions).is_greater(_m.building_total / 2)


func test_density_reflects_a_compact_core_with_real_smaller_centres() -> void:
	var d1 := _m.region_mark(&"D1")
	var d6 := _m.region_mark(&"D6")
	var d4 := _m.region_mark(&"D4")
	assert_float(d1.buildings_per_km2).is_greater(d4.buildings_per_km2)
	assert_float(d6.buildings_per_km2).is_greater(d4.buildings_per_km2)
	for code in [&"D2", &"D3", &"D4", &"D5"]:
		assert_int(_m.region_mark(code).buildings).override_failure_message(String(code)).is_greater(0)
	assert_float(TopologyTexts.core_building_share(_m)).is_between(0.2, 0.9)


func test_network_segments_match_the_network() -> void:
	var total := 0
	for cls in WorldRoadEdge.ALL_CLASSES:
		var n: int = _m.network_edge_counts[cls]
		total += n
		assert_int((_m.network_segments[cls] as PackedVector2Array).size()).is_equal(n * 2)
	assert_int(total).is_equal(_m.net.edges.size())
	assert_int(int(_m.network_edge_counts[&"ferry"])).is_greater(0)
	assert_int(int(_m.network_edge_counts[&"rail"])).is_greater(0)
	# ilk feribot kenarının uç noktaları ağ düğüm konumlarıdır
	for eid in _m.net.edges:
		var e: WorldRoadEdge = _m.net.edges[eid]
		if e.road_class == &"ferry":
			var segs: PackedVector2Array = _m.network_segments[&"ferry"]
			assert_vector(segs[0]).is_equal(_m.net.node_pos(e.a))
			assert_vector(segs[1]).is_equal(_m.net.node_pos(e.b))
			break


func test_d1_d6_water_gap_is_real_water() -> void:
	assert_bool(_m.gap["valid"]).is_true()
	var water_gap: float = _m.gap["water_gap_m"]
	assert_float(water_gap).is_between(WorldInvariants.MIN_D1_D6_SEPARATION_M, WorldInvariants.MAX_D1_D6_CROSSING_M)
	assert_float(float(_m.gap["water_fraction"])).is_greater(0.9)
	assert_float((_m.gap["a"] as Vector2).distance_to(_m.gap["b"])).is_equal_approx(water_gap, 0.5)
	assert_float(float(_m.gap["ferry_length_m"])).is_greater_equal(water_gap)


func test_negative_missing_pieces_leave_layers_empty() -> void:
	var bare := TopologyModel.build(_m.world, null, null)
	assert_int(bare.building_total).is_equal(0)
	assert_int(bare.density_counts.size() - bare.density_counts.count(0)).is_equal(0)
	assert_int(int(bare.network_edge_counts[&"arterial"])).is_equal(0)
	assert_int(int(bare.yard["count"])).is_equal(0)
	var flat := TopologyModel.build(NetworkTestSupport.flat_world(2000.0, 100.0), null, null)
	assert_bool(flat.gap["valid"]).is_false()


func test_negative_port_on_an_island_is_reported() -> void:
	var control := WorldTestSupport.control()
	var island: Dictionary = WorldTestSupport.first_island_entry(control)
	var c := WorldTestSupport.outline_center_km(island)
	for site: Dictionary in control["sites"]["sites"]:
		if site["kind"] == "port":
			site["pos_km"] = [c.x, c.y]
	var world := WorldTestSupport.coarse(control)
	var bad := TopologyModel.build(world, null, null)
	assert_array(bad.sites_off_mainland).is_not_empty()


func test_stamp_constant_carries_the_unapproved_notice() -> void:
	assert_str(TopologyModel.STAMP).contains("ÇALIŞMA VERİSİ")
	assert_str(TopologyModel.STAMP).contains("ONAYSIZ")
	assert_str(TopologyModel.STAMP).contains("Q-015")
	assert_str(TopologyModel.STAMP).contains("koordinatlar kilitli değil")
