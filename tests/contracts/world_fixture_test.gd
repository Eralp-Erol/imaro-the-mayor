extends GdUnitTestSuite
## T-023 ölçüt 4 · WorldFixture: küçük (8×8 km, 200 m) sentetik WorldData; deterministik; WorldData okuma sözleşmesinin
## (ADR-0005 §WorldData) değişmezlerini taşır; kanon/D-kodu içermez.

var _world: WorldData = null


func before() -> void:
	_world = WorldFixture.build()


func test_dimensions_and_bounds() -> void:
	assert_int(_world.width).is_equal(41)
	assert_int(_world.height).is_equal(41)
	assert_float(_world.cell_size).is_equal(200.0)
	assert_that(_world.bounds()).is_equal(Rect2(WorldFixture.ORIGIN, Vector2(8000.0, 8000.0)))
	assert_bool(_world.origin != Vector2.ZERO).override_failure_message("origin intentionally non-zero").is_true()
	assert_int(_world.heights.size()).is_equal(41 * 41)
	for arr: Variant in [_world.land_mask, _world.region_ids, _world.landmass_ids, _world.shore_distance]:
		assert_int(arr.size()).is_equal(41 * 41)


func test_same_seed_same_hash_different_seed_different_hash() -> void:
	var h := _world.state_hash()
	assert_int(h.length()).is_equal(64)
	assert_str(WorldFixture.build().state_hash()).is_equal(h)
	assert_str(WorldFixture.build(WorldFixture.DEFAULT_SEED + 1).state_hash()).is_not_equal(h)


func test_mask_matches_height_and_bilinear_coast() -> void:
	var land := 0
	for idx in _world.heights.size():
		var h := _world.heights[idx]
		if _world.land_mask[idx] == 1:
			land += 1
			assert_bool(h > _world.sea_level).is_true()
			assert_bool(_world.shore_distance[idx] > 0.0).is_true()
		else:
			assert_bool(h < _world.sea_level).is_true()
			assert_bool(_world.shore_distance[idx] < 0.0).is_true()
	assert_int(land).is_between(300, 41 * 41 - 300)
	var p := _world.cell_to_world(20, 20)
	assert_bool(_world.is_water(p.x, p.y)).is_equal(_world.land_mask[20 * 41 + 20] == 0)


func test_mainland_island_and_regions_exist() -> void:
	assert_int(_world.islands.size()).is_greater_equal(1)
	var isl := _world.islands[0]
	assert_int(isl.landmass_id).is_equal(2)
	assert_int(_world.landmass_at(isl.centroid.x, isl.centroid.y)).is_equal(2)
	var codes: Array = _world.regions.map(func(r: WorldRegion) -> String: return String(r.code))
	assert_array(codes).is_equal(["F1", "F2"])
	for r in _world.regions:
		assert_int(r.cell_count).is_greater(20)
		assert_str(String(_world.region_code_at(r.anchor.x, r.anchor.y))).is_equal(String(r.code))
		assert_int(_world.landmass_at(r.anchor.x, r.anchor.y)).is_equal(WorldData.LANDMASS_MAINLAND)


func test_fixture_carries_no_canon_region_codes() -> void:
	for code: StringName in [&"D1", &"D2", &"D3", &"D4", &"D5", &"D6"]:
		assert_object(_world.region_by_code(code)).is_null()
	for r in _world.regions:
		assert_str(r.display_name).is_empty()


func test_port_is_on_mainland_shore() -> void:
	var port := _world.port_site
	assert_object(port).is_not_null()
	assert_str(String(port.kind)).is_equal("port")
	assert_object(_world.site_by_id(WorldFixture.PORT_ID)).is_same(port)
	var idx := _world.world_to_index(port.position.x, port.position.y)
	assert_int(_world.landmass_ids[idx]).is_equal(WorldData.LANDMASS_MAINLAND)
	assert_float(_world.shore_distance[idx]).is_equal_approx(0.5 * _world.cell_size, 1.0)
	assert_bool(_world.is_water(port.position.x - _world.cell_size, port.position.y)).is_true()


func test_slope_and_height_queries_are_finite() -> void:
	var r := _world.regions[1]
	var slope := _world.slope_degrees_at(r.anchor.x, r.anchor.y)
	assert_bool(is_finite(slope) and slope >= 0.0 and slope < 90.0).is_true()
	var outside := _world.height_at(_world.origin.x - 5000.0, _world.origin.y - 5000.0)
	assert_float(outside).is_equal(_world.heights[0])
	assert_float(_world.depth_at(_world.origin.x, _world.origin.y)).is_greater(0.0)


func test_custom_resolution_scales_grid() -> void:
	var coarse := WorldFixture.build(WorldFixture.DEFAULT_SEED, 8000.0, 400.0)
	assert_int(coarse.width).is_equal(21)
	assert_int(coarse.islands.size()).is_greater_equal(1)
	assert_str(coarse.state_hash()).is_not_equal(_world.state_hash())
