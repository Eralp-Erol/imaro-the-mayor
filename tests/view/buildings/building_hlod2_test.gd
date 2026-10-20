extends GdUnitTestSuite
## T-012 ölçüt 2/7 · HLOD2 kent kütleleri (kit spec §7.2 ret ölçütleri): slab yok (kendi yükseklik kademesi),
## baskın renk
## (ortalama değil), en yüksek %10 + landmark ayrı kutu, geometri geçerliliği, boş girdi, determinizm.

var _kit: BuildingKit
var _world: WorldData
var _config: BuildingViewConfig


func before() -> void:
	_kit = BuildingTestSupport.kit()
	_world = BuildingTestSupport.flat_world(6000.0, 100.0, Rect2(), 20.0)
	_config = BuildingViewConfig.new()


func _hlod(cols: BuildingColumns) -> Dictionary:
	var plan := BuildingChunkPlan.build(cols, _world.origin, 1000.0, 4)
	var cells: Array = []
	for key in plan.keys():
		cells.append(BuildingChunkBuilder.build_cell(cols, plan, key, _kit, _world, _config))
	return BuildingHlod2.build(cells, cols, _kit, _config, plan.super_origin(Vector2i(0, 0)))


func _box_count(result: Dictionary) -> int:
	return int(result["boxes"])


func test_empty_input_gives_no_mesh() -> void:
	assert_dict(_hlod(BuildingColumns.new())).is_empty()


func test_vertex_normal_colour_arrays_are_consistent_triangles() -> void:
	var cols := BuildingTestSupport.grid_columns(_kit.module_index("bld_res_mid_a"), 10, 30.0, 100.0, 100.0)
	var r := _hlod(cols)
	var v: PackedVector3Array = r["vertices"]
	assert_int(v.size() % 3).is_equal(0)
	assert_int((r["normals"] as PackedVector3Array).size()).is_equal(v.size())
	assert_int((r["colors"] as PackedColorArray).size()).is_equal(v.size())
	# her kutu 10 üçgen (4 yan x 2 + üst 2), tabanı açık
	assert_int(v.size() / 3).is_equal(_box_count(r) * 10)


func test_every_triangle_faces_outward_with_godot_clockwise_winding() -> void:
	var cols := BuildingTestSupport.grid_columns(_kit.module_index("bld_res_mid_a"), 6, 40.0, 100.0, 100.0)
	var r := _hlod(cols)
	var v: PackedVector3Array = r["vertices"]
	var n: PackedVector3Array = r["normals"]
	for t in range(0, v.size(), 3):
		var geo := (v[t + 1] - v[t]).cross(v[t + 2] - v[t])
		# Godot: ön yüz saat yönü -> (b-a)x(c-a) normalin TERSİ yönde
		assert_float(geo.dot(n[t])).is_less(0.0)


func test_each_mass_keeps_its_own_height_no_flat_slab() -> void:
	# alçak (res_house) ve yüksek (res_late) yapılar yan yana, aynı 64 m ızgarasında: ayrı kademede, ayrı kutuda
	var low := _kit.module_index("bld_res_house_a")
	var high := _kit.module_index("bld_res_late_a")
	var rows: Array = []
	for i in 12:
		rows.append({"m": low, "x": 100.0 + i * 8.0, "z": 100.0})
		rows.append({"m": high, "x": 100.0 + i * 8.0, "z": 130.0})
	var r := _hlod(BuildingTestSupport.columns(rows))
	var tops := {}
	var v: PackedVector3Array = r["vertices"]
	for p in v:
		if p.y > 17.0:   # zemin 20 m; kutu tabanı ~17 m (etek)
			tops[snappedf(p.y, 0.5)] = true
	assert_int(tops.size()).is_greater_equal(2)   # alçak ve yüksek kütle aynı tepeye düzleşmez


func test_mass_colour_is_one_of_the_member_rows_never_an_average() -> void:
	var m := _kit.module_index("bld_res_mid_a")
	# 5 yapı W1 (satır 0), 2 yapı W10 (satır 9): ortalama sıcak gri-kahve olurdu; küme ya W1 ya W10'dur
	var rows: Array = []
	for i in 7:
		rows.append({"m": m, "x": 100.0 + i * 3.0, "z": 100.0, "wall": 0 if i < 5 else 9, "roof": 13})
	var cols := BuildingTestSupport.columns(rows)
	for sample in [true, false]:
		var cfg := BuildingViewConfig.new()
		cfg.hlod2_keep_top_share = 0.0
		cfg.hlod2_sample_colors = sample
		var plan := BuildingChunkPlan.build(cols, _world.origin, 1000.0, 4)
		var cells: Array = [BuildingChunkBuilder.build_cell(cols, plan, plan.keys()[0], _kit, _world, cfg)]
		var r := BuildingHlod2.build(cells, cols, _kit, cfg, plan.super_origin(Vector2i(0, 0)))
		var allowed: Array[Color] = [_kit.shaded(0, 1.0), _kit.shaded(9, 1.0), _kit.shaded(13, 1.0)]
		for c in (r["colors"] as PackedColorArray):
			var ok := false
			for a in allowed:
				ok = ok or c.is_equal_approx(a)
			assert_bool(ok).is_true()


func test_dominant_mode_picks_the_area_dominant_row() -> void:
	var m := _kit.module_index("bld_res_mid_a")
	var rows: Array = []
	for i in 7:
		rows.append({"m": m, "x": 100.0 + i * 3.0, "z": 100.0, "wall": 0 if i < 5 else 9, "roof": 13})
	var cols := BuildingTestSupport.columns(rows)
	var cfg := BuildingViewConfig.new()
	cfg.hlod2_keep_top_share = 0.0
	cfg.hlod2_sample_colors = false
	var plan := BuildingChunkPlan.build(cols, _world.origin, 1000.0, 4)
	var cells: Array = [BuildingChunkBuilder.build_cell(cols, plan, plan.keys()[0], _kit, _world, cfg)]
	var r := BuildingHlod2.build(cells, cols, _kit, cfg, plan.super_origin(Vector2i(0, 0)))
	var saw_w1 := false
	for c in (r["colors"] as PackedColorArray):
		assert_bool(c.is_equal_approx(_kit.shaded(9, 1.0))).is_false()
		saw_w1 = saw_w1 or c.is_equal_approx(_kit.shaded(0, 1.0))
	assert_bool(saw_w1).is_true()


func test_sampled_colours_preserve_the_mix_across_clusters_not_one_grey() -> void:
	var m := _kit.module_index("bld_res_mid_a")
	var rows: Array = []
	for j in 12:
		for i in 12:
			rows.append({"m": m, "x": 100.0 + i * 30.0, "z": 100.0 + j * 30.0, "wall": (i * 5 + j) % 7, "roof": 13})
	var cols := BuildingTestSupport.columns(rows)
	var cfg := BuildingViewConfig.new()
	cfg.hlod2_keep_top_share = 0.0
	var plan := BuildingChunkPlan.build(cols, _world.origin, 1000.0, 4)
	var cells: Array = [BuildingChunkBuilder.build_cell(cols, plan, plan.keys()[0], _kit, _world, cfg)]
	var r := BuildingHlod2.build(cells, cols, _kit, cfg, plan.super_origin(Vector2i(0, 0)))
	var distinct := {}
	for c in (r["colors"] as PackedColorArray):
		distinct[c.to_html()] = true
	assert_int(distinct.size()).is_greater_equal(4)   # 7 duvar satırının çoğu görünür (tek ortalama renk değil)


func test_tallest_share_and_landmark_stay_as_separate_oriented_boxes() -> void:
	var m := _kit.module_index("bld_res_mid_a")
	var tower := _kit.module_index("bld_lmk_clocktower")
	var rows: Array = []
	for i in 40:
		rows.append({"m": m, "x": 100.0 + (i % 8) * 4.0, "z": 100.0 + (i / 8) * 4.0})
	rows.append({"m": tower, "x": 150.0, "z": 150.0})
	var cols := BuildingTestSupport.columns(rows)
	var with_top := _hlod(cols)
	var cfg := BuildingViewConfig.new()
	cfg.hlod2_keep_top_share = 0.0
	var plan := BuildingChunkPlan.build(cols, _world.origin, 1000.0, 4)
	var cells: Array = [BuildingChunkBuilder.build_cell(cols, plan, plan.keys()[0], _kit, _world, cfg)]
	var without_top := BuildingHlod2.build(cells, cols, _kit, cfg, plan.super_origin(Vector2i(0, 0)))
	# %10 + landmark ayrı kutu -> kutu sayısı artar; kule en az bir kutu olarak yükseklikle korunur
	assert_int(_box_count(with_top)).is_greater(_box_count(without_top))
	var tallest := 0.0
	for p: Vector3 in (without_top["vertices"] as PackedVector3Array):
		tallest = maxf(tallest, p.y)
	assert_float(tallest).is_greater(20.0 + _kit.height_m[tower] - 1.0 - 0.5)   # zemin 20 - 0,2 + 23 m


func test_clusters_are_far_fewer_than_buildings() -> void:
	var cols := BuildingTestSupport.grid_columns(_kit.module_index("bld_res_mid_a"), 40, 20.0, 100.0, 100.0)
	var r := _hlod(cols)
	assert_int(_box_count(r)).is_less(cols.count / 3)
	assert_int(_box_count(r)).is_greater(10)


func test_same_input_gives_identical_geometry() -> void:
	var cols := BuildingTestSupport.grid_columns(_kit.module_index("bld_res_late_a"), 15, 35.0, 100.0, 100.0)
	var a := _hlod(cols)
	var b := _hlod(cols)
	assert_array(a["vertices"]).is_equal(b["vertices"])
	assert_array(a["colors"]).is_equal(b["colors"])


func test_footprint_corners_follow_yaw() -> void:
	var c0 := BuildingHlod2.footprint_corners(100.0, 200.0, 0.0, 10.0, 6.0)
	assert_vector(c0[0]).is_equal_approx(Vector2(95.0, 197.0), Vector2.ONE * 0.001)
	var c90 := BuildingHlod2.footprint_corners(100.0, 200.0, PI * 0.5, 10.0, 6.0)
	# 90°: genişlik z eksenine yatar
	var zmin := minf(minf(c90[0].y, c90[1].y), minf(c90[2].y, c90[3].y))
	var zmax := maxf(maxf(c90[0].y, c90[1].y), maxf(c90[2].y, c90[3].y))
	assert_float(zmax - zmin).is_equal_approx(10.0, 0.001)


func test_sparse_mass_shrinks_toward_its_centre_so_ground_shows_through() -> void:
	var m := _kit.module_index("bld_res_house_a")
	# aynı 96 m hücrede iki küçük ev, uzak köşelerde: sınır kutusu ~80 m, kaplama çok düşük
	var cols := BuildingTestSupport.columns([{"m": m, "x": 110.0, "z": 110.0}, {"m": m, "x": 180.0, "z": 180.0}])
	var cfg := BuildingViewConfig.new()
	cfg.hlod2_keep_top_share = 0.0
	var plan := BuildingChunkPlan.build(cols, _world.origin, 1000.0, 4)
	var cells: Array = [BuildingChunkBuilder.build_cell(cols, plan, plan.keys()[0], _kit, _world, cfg)]
	var r := BuildingHlod2.build(cells, cols, _kit, cfg, plan.super_origin(Vector2i(0, 0)))
	var xmin := INF
	var xmax := -INF
	for p: Vector3 in (r["vertices"] as PackedVector3Array):
		xmin = minf(xmin, p.x)
		xmax = maxf(xmax, p.x)
	# ham sınır kutusu: 110-3.5 .. 180+3.5 = ~77 m; daralmış kutu belirgin biçimde küçük
	assert_float(xmax - xmin).is_less(70.0)
	assert_float(xmax - xmin).is_greater(BuildingHlod2.MIN_BOX_M)
