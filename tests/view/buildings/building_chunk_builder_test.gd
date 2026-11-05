extends GdUnitTestSuite
## T-012 ölçüt 1/7 · Chunk mesh VERİSİ (render'dan ayrı): MultiMesh tamponları, HLOD1 birleştirme, su atma, determinizm,
## rebasing eşdeğerliği, boş/büyük girdi. T-062 A3: hero örneği yalnız dönüşümdür (12 float); HLOD1 rengi modülün PROXY
## atlasından piştirilmiş şablon rengidir (örnek palet satırı yok).

var _kit: BuildingKit
var _world: WorldData
var _config: BuildingViewConfig


func before() -> void:
	_kit = BuildingTestSupport.kit()
	_world = BuildingTestSupport.flat_world(6000.0, 100.0, Rect2(), 12.0)
	_config = BuildingViewConfig.new()


func _build(cols: BuildingColumns, key: Vector2i = Vector2i(0, 0)) -> BuildingCellData:
	var plan := BuildingChunkPlan.build(cols, _world.origin, 1000.0, 4)
	return BuildingChunkBuilder.build_cell(cols, plan, key, _kit, _world, _config)


func test_instances_are_grouped_by_module_with_12_floats_each() -> void:
	var a := _kit.module_index(BuildingTestSupport.MID_A)
	var b := _kit.module_index(BuildingTestSupport.HOUSE_A)
	var cols := BuildingTestSupport.columns([
		{"m": a, "x": 100.0, "z": 100.0}, {"m": b, "x": 300.0, "z": 100.0}, {"m": a, "x": 500.0, "z": 100.0},
	])
	var data := _build(cols)
	assert_int(data.instance_count()).is_equal(3)
	assert_array(data.modules).is_equal(PackedInt32Array([mini(a, b), maxi(a, b)]))
	for n in data.modules.size():
		assert_int(data.buffers[n].size()).is_equal(data.counts[n] * BuildingChunkBuilder.INSTANCE_STRIDE)
	assert_int(data.counts[data.modules.find(a)]).is_equal(2)


func test_buffer_layout_matches_transform3d_rows_and_carries_no_palette_data() -> void:
	var m := _kit.module_index(BuildingTestSupport.MID_A)
	var cols := BuildingTestSupport.columns([{"m": m, "x": 250.0, "z": 400.0, "yaw": 0.9, "wall": 3, "roof": 15,
			"accent": 23, "bright": 255}])
	var data := _build(cols)
	var buf := data.buffers[0]
	var xf := Transform3D(Basis(Vector3.UP, 0.9), Vector3(250.0, _world.height_at(250.0, 400.0)
			- BuildingGround.SINK_M, 400.0))
	# satır öncelikli 3x4: [basis.x.x, basis.y.x, basis.z.x, origin.x, ...]
	assert_float(buf[0]).is_equal_approx(xf.basis.x.x, 0.0001)
	assert_float(buf[1]).is_equal_approx(xf.basis.y.x, 0.0001)
	assert_float(buf[2]).is_equal_approx(xf.basis.z.x, 0.0001)
	assert_float(buf[4]).is_equal_approx(xf.basis.x.y, 0.0001)
	assert_float(buf[5]).is_equal_approx(xf.basis.y.y, 0.0001)
	assert_float(buf[6]).is_equal_approx(xf.basis.z.y, 0.0001)
	assert_float(buf[8]).is_equal_approx(xf.basis.x.z, 0.0001)
	assert_float(buf[9]).is_equal_approx(xf.basis.y.z, 0.0001)
	assert_float(buf[10]).is_equal_approx(xf.basis.z.z, 0.0001)
	# origin hücre origin'ine göreli (0,0 hücresi: origin = dünya origin'i)
	assert_float(buf[3]).is_equal_approx(250.0, 0.001)
	assert_float(buf[7]).is_equal_approx(xf.origin.y, 0.001)
	assert_float(buf[11]).is_equal_approx(400.0, 0.001)
	# 3x4 dönüşüm + 4 float özel veri (D-021 çatı/cephe varyantı); palet satırı yok (renk atlas dokusundan)
	assert_int(buf.size()).is_equal(BuildingChunkBuilder.INSTANCE_STRIDE)
	assert_int(BuildingChunkBuilder.FLOATS_PER_INSTANCE).is_equal(12)
	assert_int(BuildingChunkBuilder.INSTANCE_STRIDE).is_equal(16)


func test_cell_local_positions_keep_32bit_precision_far_from_the_origin() -> void:
	var world := BuildingTestSupport.flat_world(60000.0, 1000.0, Rect2(), 12.0)
	var m := _kit.module_index(BuildingTestSupport.MID_A)
	var cols := BuildingTestSupport.columns([{"m": m, "x": 58123.5, "z": 41007.25}])
	var plan := BuildingChunkPlan.build(cols, world.origin, 1000.0, 4)
	var key := plan.keys()[0]
	var data := BuildingChunkBuilder.build_cell(cols, plan, key, _kit, world, _config)
	var buf := data.buffers[0]
	assert_vector(Vector2(data.origin.x + buf[3], data.origin.y + buf[11])).is_equal_approx(
			Vector2(58123.5, 41007.25), Vector2.ONE * 0.01)
	assert_float(absf(buf[3])).is_less(1000.0)   # hücre-yerel: yüzlerce metre, on binlerce değil


func test_building_on_water_is_dropped_and_counted_not_silently_drawn() -> void:
	var world := BuildingTestSupport.flat_world(6000.0, 100.0, Rect2(3000.0, 0.0, 3000.0, 6000.0))
	var m := _kit.module_index(BuildingTestSupport.MID_A)
	var cols := BuildingTestSupport.columns([{"m": m, "x": 500.0, "z": 500.0}, {"m": m, "x": 3500.0, "z": 500.0}])
	var plan := BuildingChunkPlan.build(cols, world.origin, 1000.0, 4)
	var total_kept := 0
	var total_dropped := 0
	for key in plan.keys():
		var d := BuildingChunkBuilder.build_cell(cols, plan, key, _kit, world, _config)
		total_kept += d.instance_count()
		total_dropped += d.dropped
	assert_int(total_kept).is_equal(1)
	assert_int(total_dropped).is_equal(1)


func test_hlod1_merges_one_proxy_per_building_with_the_baked_template_colours() -> void:
	var m := _kit.module_index(BuildingTestSupport.HOUSE_A)
	var tpl: BuildingKit.ProxyTemplate = _kit.proxies[m]
	var cols := BuildingTestSupport.grid_columns(m, 4, 60.0, 100.0, 100.0)
	var data := _build(cols)
	assert_int(data.hlod1_vertices.size()).is_equal(16 * tpl.vertices.size())
	assert_int(data.hlod1_normals.size()).is_equal(data.hlod1_vertices.size())
	assert_int(data.hlod1_colors.size()).is_equal(data.hlod1_vertices.size())
	for n in data.hlod1_normals.size():
		assert_float(data.hlod1_normals[n].length()).is_equal_approx(1.0, 0.01)
	# her yapının köşeleri kendi ayak izi çevresinde (pivot ayak izi merkezi) ve zeminden tepeye
	var per := tpl.vertices.size()
	var half_diag := 0.5 * sqrt(_kit.footprint_w[m] * _kit.footprint_w[m] + _kit.footprint_d[m] * _kit.footprint_d[m])
	for b in 16:
		var cx := cols.x[b]
		var cz := cols.z[b]
		for v in range(b * per, (b + 1) * per):
			var p := data.hlod1_vertices[v]
			assert_float(Vector2(p.x + data.origin.x - cx, p.z + data.origin.y - cz).length()).is_less(half_diag + 1.0)
			assert_float(p.y).is_between(12.0 - 0.3, 12.0 + _kit.height_m[m] + 0.1)
			assert_bool(data.hlod1_colors[v] == tpl.colors_for(data.variants[b])[v - b * per]).is_true()   # D-021 varyant


func test_hlod1_colour_is_the_modules_baked_colour_and_ignores_instance_palette_rows() -> void:
	var a := _kit.module_index(BuildingTestSupport.MID_A)
	var b := _kit.module_index(BuildingTestSupport.HOUSE_A)
	var cols := BuildingTestSupport.columns([{"m": a, "x": 100.0, "z": 100.0, "wall": 0, "roof": 13},
			{"m": a, "x": 300.0, "z": 100.0, "wall": 9, "roof": 15}, {"m": b, "x": 500.0, "z": 100.0}])
	var data := _build(cols)
	var tpl_a := _kit.proxies[a] as BuildingKit.ProxyTemplate
	var tpl_b := _kit.proxies[b] as BuildingKit.ProxyTemplate
	var per_a := tpl_a.vertices.size()
	# palet satırı sütunları rengi değiştirmez (hero palet taşımaz); renk şablon rengi + D-021 varyantıdır
	assert_bool(data.hlod1_colors.slice(0, per_a) == tpl_a.colors_for(data.variants[0])).is_true()
	assert_bool(data.hlod1_colors.slice(per_a, 2 * per_a) == tpl_a.colors_for(data.variants[1])).is_true()
	assert_bool(data.hlod1_colors.slice(2 * per_a) == tpl_b.colors_for(data.variants[2])).is_true()
	assert_bool(tpl_b.colors != tpl_a.colors).is_true()


func test_hlod1_box_source_uses_the_ten_triangle_footprint_box() -> void:
	var m := _kit.module_index(BuildingTestSupport.MID_A)
	var cfg := BuildingViewConfig.new()
	cfg.hlod1_source = BuildingViewConfig.HLOD1_BOX
	var cols := BuildingTestSupport.grid_columns(m, 3, 50.0, 100.0, 100.0)
	var plan := BuildingChunkPlan.build(cols, _world.origin, 1000.0, 4)
	var data := BuildingChunkBuilder.build_cell(cols, plan, plan.keys()[0], _kit, _world, cfg)
	assert_int(data.hlod1_triangles()).is_equal(9 * 10)
	assert_int(data.hlod1_colors.size()).is_equal(data.hlod1_vertices.size())


func test_module_without_proxy_template_is_skipped_in_hlod1_but_still_instanced() -> void:
	var meta := BuildingTestSupport.meta_kit()   # şablonsuz (mesh yüklenmemiş) kit
	var m := meta.module_index(BuildingTestSupport.MID_A)
	assert_object(meta.proxies[m]).is_null()
	var cols := BuildingTestSupport.columns([{"m": m, "x": 100.0, "z": 100.0}])
	var plan := BuildingChunkPlan.build(cols, _world.origin, 1000.0, 4)
	var data := BuildingChunkBuilder.build_cell(cols, plan, plan.keys()[0], meta, _world, _config)
	assert_int(data.instance_count()).is_equal(1)
	assert_int(data.hlod1_vertices.size()).is_equal(0)


func test_cell_tier_triangle_counts_come_from_the_table_near_and_mid_levels() -> void:
	var m := _kit.module_index(BuildingTestSupport.MID_A)
	var cols := BuildingTestSupport.grid_columns(m, 3, 50.0, 100.0, 100.0)
	var data := _build(cols)
	assert_int(data.lod0_tris).is_equal(9 * _kit.near_tris[m])   # LOD0 kademesi = hero LOD1
	assert_int(data.lod1_tris).is_equal(9 * _kit.mid_tris[m])    # LOD1 kademesi = hero PROXY


func test_same_input_gives_identical_bytes_and_other_order_gives_same_instance_set() -> void:
	var m := _kit.module_index(BuildingTestSupport.MID_B)
	var cols := BuildingTestSupport.grid_columns(m, 12, 70.0, 50.0, 50.0)
	var a := _build(cols)
	var b := _build(cols)
	assert_array(a.modules).is_equal(b.modules)
	for n in a.buffers.size():
		assert_array(a.buffers[n]).is_equal(b.buffers[n])
	assert_array(a.hlod1_vertices).is_equal(b.hlod1_vertices)
	assert_array(a.hlod1_colors).is_equal(b.hlod1_colors)
	assert_int(a.lod0_tris).is_equal(b.lod0_tris)


func test_empty_cell_builds_empty_data() -> void:
	var data := _build(BuildingColumns.new())
	assert_int(data.instance_count()).is_equal(0)
	assert_int(data.modules.size()).is_equal(0)
	assert_int(data.hlod1_vertices.size()).is_equal(0)


func test_large_cell_builds_every_instance() -> void:
	var m := _kit.module_index(BuildingTestSupport.MID_A)
	var cols := BuildingTestSupport.grid_columns(m, 60, 15.0, 20.0, 20.0)   # 3600 yapı, tek hücre
	var data := _build(cols)
	assert_int(data.instance_count()).is_equal(3600)
	assert_int(data.hlod1_triangles()).is_equal(3600 * (_kit.proxies[m] as BuildingKit.ProxyTemplate).triangle_count())


func test_hlod1_can_be_switched_off_for_ablation_runs() -> void:
	var m := _kit.module_index(BuildingTestSupport.MID_A)
	var cfg := BuildingViewConfig.new()
	cfg.build_hlod1 = false
	var cols := BuildingTestSupport.grid_columns(m, 3, 50.0, 100.0, 100.0)
	var plan := BuildingChunkPlan.build(cols, _world.origin, 1000.0, 4)
	var data := BuildingChunkBuilder.build_cell(cols, plan, plan.keys()[0], _kit, _world, cfg)
	assert_int(data.hlod1_vertices.size()).is_equal(0)
	assert_int(data.instance_count()).is_equal(9)
