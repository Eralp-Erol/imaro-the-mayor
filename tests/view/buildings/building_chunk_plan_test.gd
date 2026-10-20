extends GdUnitTestSuite
## T-012 ölçüt 1/7 · sütun -> chunk bölme: kenar durumları, süper-chunk, içerik özeti, değişen hücreler, determinizm.

var _kit: BuildingKit


func before() -> void:
	_kit = BuildingTestSupport.kit()


func _mid() -> int:
	return _kit.module_index("bld_res_mid_a")


func test_columns_split_into_1km_cells_and_every_row_lands_in_exactly_one_cell() -> void:
	var cols := BuildingTestSupport.grid_columns(_mid(), 30, 100.0, 10.0, 10.0)   # 3 km x 3 km
	var plan := BuildingChunkPlan.build(cols, Vector2.ZERO, 1000.0, 4)
	assert_int(plan.cells.size()).is_equal(9)
	var total := 0
	var seen := {}
	for key in plan.keys():
		for i in plan.indices(key):
			assert_bool(seen.has(i)).is_false()
			seen[i] = true
			assert_vector(Vector2(plan.cell_of(cols.x[i], cols.z[i]))).is_equal(Vector2(key))
			total += 1
	assert_int(total).is_equal(cols.count)


func test_cell_boundary_is_half_open_and_origin_aligned() -> void:
	var plan := BuildingChunkPlan.new()
	plan.origin = Vector2(500.0, -250.0)
	plan.cell_m = 1000.0
	assert_vector(Vector2(plan.cell_of(1499.99, -250.0))).is_equal(Vector2(0, 0))
	assert_vector(Vector2(plan.cell_of(1500.0, -250.0))).is_equal(Vector2(1, 0))
	assert_vector(Vector2(plan.cell_of(499.99, -251.0))).is_equal(Vector2(-1, -1))
	assert_vector(plan.cell_origin(Vector2i(2, -1))).is_equal(Vector2(2500.0, -1250.0))


func test_super_chunk_uses_floor_division_including_negative_cells() -> void:
	var plan := BuildingChunkPlan.new()
	plan.super_cells = 4
	assert_vector(Vector2(plan.super_of(Vector2i(0, 3)))).is_equal(Vector2(0, 0))
	assert_vector(Vector2(plan.super_of(Vector2i(4, 7)))).is_equal(Vector2(1, 1))
	assert_vector(Vector2(plan.super_of(Vector2i(-1, -4)))).is_equal(Vector2(-1, -1))
	assert_vector(Vector2(plan.super_of(Vector2i(-5, -8)))).is_equal(Vector2(-2, -2))


func test_empty_columns_make_an_empty_plan() -> void:
	var plan := BuildingChunkPlan.build(BuildingColumns.new(), Vector2.ZERO, 1000.0, 4)
	assert_int(plan.cells.size()).is_equal(0)
	assert_int(plan.keys().size()).is_equal(0)
	assert_int(plan.super_groups().size()).is_equal(0)


func test_keys_and_hashes_are_deterministic_and_sorted() -> void:
	var cols := BuildingTestSupport.grid_columns(_mid(), 20, 150.0, 5.0, 5.0)
	var a := BuildingChunkPlan.build(cols, Vector2.ZERO, 1000.0, 4)
	var b := BuildingChunkPlan.build(cols, Vector2.ZERO, 1000.0, 4)
	assert_array(a.keys()).is_equal(b.keys())
	assert_dict(a.cell_hashes(cols)).is_equal(b.cell_hashes(cols))
	var keys := a.keys()
	for n in range(1, keys.size()):
		assert_bool(keys[n - 1].x < keys[n].x or (keys[n - 1].x == keys[n].x and keys[n - 1].y < keys[n].y)).is_true()


func test_changing_one_building_changes_only_its_cell_hash() -> void:
	var cols := BuildingTestSupport.grid_columns(_mid(), 20, 150.0, 5.0, 5.0)
	var plan := BuildingChunkPlan.build(cols, Vector2.ZERO, 1000.0, 4)
	var before := plan.cell_hashes(cols)
	var edited := BuildingTestSupport.grid_columns(_mid(), 20, 150.0, 5.0, 5.0)
	edited.wall_row[0] = (edited.wall_row[0] + 1) % 13
	var plan2 := BuildingChunkPlan.build(edited, Vector2.ZERO, 1000.0, 4)
	var changed := BuildingChunkPlan.changed_cells(before, plan2.cell_hashes(edited))
	assert_int(changed.size()).is_equal(1)
	assert_vector(Vector2(changed[0])).is_equal(Vector2(plan.cell_of(cols.x[0], cols.z[0])))


func test_parcel_id_floors_and_flags_do_not_change_the_render_hash() -> void:
	var cols := BuildingTestSupport.grid_columns(_mid(), 4, 100.0, 5.0, 5.0)
	var plan := BuildingChunkPlan.build(cols, Vector2.ZERO, 1000.0, 4)
	var before := plan.cell_hashes(cols)
	cols.parcel_id[0] = 999999
	cols.floors[0] = 9
	cols.flags[0] = 255
	assert_dict(plan.cell_hashes(cols)).is_equal(before)


func test_moving_a_building_across_a_boundary_changes_both_cells() -> void:
	var cols := BuildingTestSupport.columns([{"m": _mid(), "x": 990.0, "z": 100.0}, {"m": _mid(), "x": 100.0, "z": 100.0}])
	var plan := BuildingChunkPlan.build(cols, Vector2.ZERO, 1000.0, 4)
	var before := plan.cell_hashes(cols)
	cols.x[0] = 1010.0
	var plan2 := BuildingChunkPlan.build(cols, Vector2.ZERO, 1000.0, 4)
	var changed := BuildingChunkPlan.changed_cells(before, plan2.cell_hashes(cols))
	assert_int(changed.size()).is_equal(2)   # eski hücre değişti (kaybetti), yeni hücre eklendi


func test_removed_cell_is_reported_as_changed() -> void:
	var a := BuildingTestSupport.columns([{"m": _mid(), "x": 100.0, "z": 100.0}, {"m": _mid(), "x": 2100.0, "z": 100.0}])
	var b := BuildingTestSupport.columns([{"m": _mid(), "x": 100.0, "z": 100.0}])
	var ha := BuildingChunkPlan.build(a, Vector2.ZERO, 1000.0, 4).cell_hashes(a)
	var hb := BuildingChunkPlan.build(b, Vector2.ZERO, 1000.0, 4).cell_hashes(b)
	var changed := BuildingChunkPlan.changed_cells(ha, hb)
	assert_int(changed.size()).is_equal(1)
	assert_vector(Vector2(changed[0])).is_equal(Vector2(2, 0))


func test_large_input_splits_in_reasonable_time_and_loses_nothing() -> void:
	var cols := BuildingTestSupport.grid_columns(_mid(), 200, 100.0, 0.0, 0.0)   # 40 000 yapı, 20 x 20 km
	var plan := BuildingChunkPlan.build(cols, Vector2.ZERO, 1000.0, 4)
	assert_int(plan.cells.size()).is_equal(400)
	var total := 0
	for key in plan.keys():
		total += plan.indices(key).size()
	assert_int(total).is_equal(40000)
	assert_int(plan.super_groups().size()).is_equal(25)
