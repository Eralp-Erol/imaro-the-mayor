extends GdUnitTestSuite
## T-012 ölçüt 1/2/3/7 · BuildingView düğüm yapısı (başsız): chunk'lı MultiMesh + margin'li LOD aralıkları +
## HLOD1/HLOD2,
## WorldView altında rebasing eşdeğerliği, chunk-yerel yeniden kurulum, geçersiz girdinin reddi, gölge ayarı.
## (Dummy renderer: çizim/AABB doğrulanmaz; görüntü doğrulaması capture ile.)

var _kit: BuildingKit
var _world: WorldData


func before() -> void:
	_kit = BuildingTestSupport.kit()
	_world = BuildingTestSupport.flat_world(8000.0, 100.0, Rect2(), 15.0)


func _view(config: BuildingViewConfig = null) -> BuildingView:
	var view: BuildingView = auto_free(BuildingView.new())
	add_child(view)
	var cfg := config if config != null else BuildingViewConfig.new()
	cfg.use_threads = false
	view.setup(_world, _kit, cfg)
	return view


func _two_module_cols() -> BuildingColumns:
	var a := _kit.module_index("bld_res_mid_a")
	var b := _kit.module_index("bld_res_house_b")
	var rows: Array = []
	for i in 10:
		rows.append({"m": a, "x": 500.0 + i * 40.0, "z": 500.0, "parcel": 1 + i})
		rows.append({"m": b, "x": 500.0 + i * 40.0, "z": 540.0, "parcel": 100 + i})
	rows.append({"m": a, "x": 2600.0, "z": 500.0, "parcel": 300})   # başka hücre
	rows.append({"m": a, "x": 6100.0, "z": 6100.0, "parcel": 301})  # başka süper-chunk
	return BuildingTestSupport.columns(rows)


func test_set_columns_builds_cells_with_lod0_lod1_and_hlod1_per_cell() -> void:
	var view := _view()
	var report := view.set_columns(_two_module_cols(), 1)
	assert_bool(report["ok"]).is_true()
	assert_int(view.cell_keys().size()).is_equal(3)
	var cell := view.cell_node(Vector2i(0, 0))
	assert_object(cell).is_not_null()
	var l0 := 0
	var l1 := 0
	var h1 := 0
	for child in cell.get_children():
		if child is MultiMeshInstance3D:
			if child.name.begins_with("L0_"):
				l0 += 1
			elif child.name.begins_with("L1_"):
				l1 += 1
		elif child.name == "HLOD1":
			h1 += 1
	assert_int(l0).is_equal(2)   # iki modül
	assert_int(l1).is_equal(2)
	assert_int(h1).is_equal(1)
	assert_int(view.super_keys().size()).is_equal(2)
	assert_int(int(view.stats["drawn"])).is_equal(22)
	assert_int(int(view.stats["dropped_water"])).is_equal(0)


func test_multimesh_uses_custom_data_and_shared_kit_material() -> void:
	var view := _view()
	view.set_columns(_two_module_cols(), 1)
	var mmi: MultiMeshInstance3D = null
	for child in view.cell_node(Vector2i(0, 0)).get_children():
		if child is MultiMeshInstance3D:
			mmi = child
			break
	assert_object(mmi).is_not_null()
	assert_bool(mmi.multimesh.use_custom_data).is_true()
	assert_int(mmi.multimesh.transform_format).is_equal(MultiMesh.TRANSFORM_3D)
	assert_int(mmi.multimesh.instance_count).is_equal(10)
	var mat := mmi.material_override as ShaderMaterial
	assert_object(mat).is_not_null()
	assert_str(mat.resource_name).is_equal("mat_kit")


func test_visibility_ranges_overlap_per_tier_with_margins() -> void:
	var view := _view()
	view.set_columns(_two_module_cols(), 1)
	var lod := view.config.lod
	var cell := view.cell_node(Vector2i(0, 0))
	var ranges := {}
	for child in cell.get_children():
		var gi := child as GeometryInstance3D
		if child.name.begins_with("L0_"):
			ranges["l0"] = gi
		elif child.name.begins_with("L1_"):
			ranges["l1"] = gi
		elif child.name == "HLOD1":
			ranges["h1"] = gi
	var l0: GeometryInstance3D = ranges["l0"]
	var l1: GeometryInstance3D = ranges["l1"]
	var h1: GeometryInstance3D = ranges["h1"]
	assert_float(l0.visibility_range_end).is_equal(float(lod.range_for(BuildingLod.Tier.LOD0)["end"]))
	assert_float(l1.visibility_range_begin).is_less(l0.visibility_range_end)   # çakışma
	assert_float(h1.visibility_range_begin).is_less(l1.visibility_range_end)
	assert_float(l0.visibility_range_end_margin).is_greater(0.0)
	assert_float(l1.visibility_range_begin_margin).is_greater(0.0)
	var sup := view.super_node(view.super_keys()[0])
	assert_float(sup.visibility_range_begin).is_less(h1.visibility_range_end)
	assert_float(sup.visibility_range_end).is_equal(0.0)


func test_default_shadows_come_from_a_shadow_only_lod1_node_in_the_lod0_range_never_from_hlod() -> void:
	var view := _view()
	view.set_columns(_two_module_cols(), 1)
	var casters := 0
	for child in view.cell_node(Vector2i(0, 0)).get_children():
		var gi := child as GeometryInstance3D
		if child.name.begins_with("S1_"):
			casters += 1
			assert_int(gi.cast_shadow).is_equal(GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY)
			# gölge düşürme LOD0 menzilinde biter ("600 m ötesi LOD1'de kapalı")
			assert_float(gi.visibility_range_end).is_equal(
					float(view.config.lod.range_for(BuildingLod.Tier.LOD0)["end"]))
			assert_float(gi.visibility_range_begin).is_equal(0.0)
		else:
			assert_int(gi.cast_shadow).is_equal(GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	assert_int(casters).is_equal(2)   # modül başına bir
	assert_int(view.super_node(view.super_keys()[0]).cast_shadow).is_equal(
			GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)


func test_shadow_caster_shares_the_lod1_multimesh_so_it_costs_no_extra_memory() -> void:
	var view := _view()
	view.set_columns(_two_module_cols(), 1)
	var cell := view.cell_node(Vector2i(0, 0))
	var l1: MultiMeshInstance3D = null
	var s1: MultiMeshInstance3D = null
	for child in cell.get_children():
		if child.name.begins_with("L1_") and l1 == null:
			l1 = child
		elif child.name.begins_with("S1_") and s1 == null:
			s1 = child
	assert_object(s1.multimesh).is_same(l1.multimesh)


func test_lod0_can_be_the_shadow_caster_when_configured() -> void:
	var cfg := BuildingViewConfig.new()
	cfg.shadow_caster_lod = 0
	var view := _view(cfg)
	view.set_columns(_two_module_cols(), 1)
	for child in view.cell_node(Vector2i(0, 0)).get_children():
		var gi := child as GeometryInstance3D
		assert_bool(child.name.begins_with("S1_")).is_false()
		if child.name.begins_with("L0_"):
			assert_int(gi.cast_shadow).is_equal(GeometryInstance3D.SHADOW_CASTING_SETTING_ON)
		else:
			assert_int(gi.cast_shadow).is_equal(GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)


func test_shadows_can_be_disabled_globally() -> void:
	var cfg := BuildingViewConfig.new()
	cfg.cast_shadows = false
	var view := _view(cfg)
	view.set_columns(_two_module_cols(), 1)
	for child in view.cell_node(Vector2i(0, 0)).get_children():
		assert_bool(child.name.begins_with("S1_")).is_false()
		assert_int((child as GeometryInstance3D).cast_shadow).is_equal(GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)


func test_cell_nodes_sit_at_world_origin_so_rebasing_the_parent_moves_everything_equally() -> void:
	var root: Node3D = auto_free(Node3D.new())
	add_child(root)
	var view: BuildingView = BuildingView.new()
	root.add_child(view)
	var cfg := BuildingViewConfig.new()
	cfg.use_threads = false
	view.setup(_world, _kit, cfg)
	view.set_columns(_two_module_cols(), 1)
	var key := Vector2i(2, 0)
	var cell := view.cell_node(key)
	assert_vector(cell.position).is_equal(Vector3(2000.0, 0.0, 0.0))
	var before := cell.global_position
	root.position = Vector3(-1536.0, 0.0, -512.0)   # CameraRig.set_rebase_origin(…) ile aynı kayma
	assert_vector(cell.global_position).is_equal(before + root.position)
	# dünya konumu = view_root ofseti + hücre konumu: aynı yapı için rebasing öncesi/sonrası fark yalnız ofset
	var world_x := 2600.0
	var local_x: float = world_x - cell.position.x
	assert_float(root.position.x + cell.position.x + local_x).is_equal_approx(world_x - 1536.0, 0.001)


func test_changing_one_building_rebuilds_only_its_cell() -> void:
	var view := _view()
	var cols := _two_module_cols()
	view.set_columns(cols, 1)
	var untouched := view.cell_node(Vector2i(2, 0))
	var touched := view.cell_node(Vector2i(0, 0))
	var other := view.cell_node(Vector2i(6, 6))
	var edited := _two_module_cols()
	edited.wall_row[0] = 7
	var report := view.set_columns(edited, 2)
	assert_int(report["rebuilt"]).is_equal(1)
	assert_object(view.cell_node(Vector2i(2, 0))).is_same(untouched)
	assert_object(view.cell_node(Vector2i(6, 6))).is_same(other)
	assert_bool(is_instance_valid(touched) and touched.is_queued_for_deletion()).is_true()
	assert_object(view.cell_node(Vector2i(0, 0))).is_not_same(touched)
	assert_int(report["supers_rebuilt"]).is_equal(1)   # yalnız (0,0) hücresini içeren süper-chunk


func test_same_version_and_same_columns_is_a_noop() -> void:
	var view := _view()
	var cols := _two_module_cols()
	view.set_columns(cols, 5)
	var first := view.cell_node(Vector2i(0, 0))
	var report := view.set_columns(cols, 5)
	assert_bool(report["skipped"]).is_true()
	assert_object(view.cell_node(Vector2i(0, 0))).is_same(first)


func test_inserting_in_another_cell_keeps_unchanged_cells_and_rebinds_their_indices() -> void:
	var view := _view()
	view.set_columns(_two_module_cols(), 1)
	var a := _kit.module_index("bld_res_mid_a")
	var rows: Array = []
	rows.append({"m": a, "x": 4600.0, "z": 4600.0, "parcel": 999})   # en başa yeni hücre: tüm sütun indeksleri kayar
	var base := _two_module_cols()
	for i in base.count:
		rows.append({"m": base.module_idx[i], "x": base.x[i], "z": base.z[i], "yaw": base.yaw[i],
				"wall": base.wall_row[i], "roof": base.roof_row[i], "accent": base.accent_row[i],
				"bright": base.bright[i], "parcel": base.parcel_id[i]})
	var shifted := BuildingTestSupport.columns(rows)
	var report := view.set_columns(shifted, 2)
	assert_int(report["rebuilt"]).is_equal(1)   # yalnız yeni hücre
	assert_int(view.cell_keys().size()).is_equal(4)
	# HLOD2 yeniden kurulurken eski hücrelerin kept indeksleri yeni sütuna bağlı olmalı (kayma sonrası)
	var summary := view.cell_summary(Vector2i(0, 0))
	assert_int(summary.kept.size()).is_equal(20)
	for i in summary.kept:
		assert_vector(Vector2(view.plan().cell_of(shifted.x[i], shifted.z[i]))).is_equal(Vector2(0, 0))


func test_removing_all_buildings_removes_cells_and_super_chunks() -> void:
	var view := _view()
	view.set_columns(_two_module_cols(), 1)
	var report := view.set_columns(BuildingColumns.new(), 2)
	assert_bool(report["ok"]).is_true()
	assert_int(view.cell_keys().size()).is_equal(0)
	assert_int(view.super_keys().size()).is_equal(0)


func test_invalid_columns_are_rejected_and_the_previous_scene_stays() -> void:
	var view := _view()
	view.set_columns(_two_module_cols(), 1)
	var bad := _two_module_cols()
	bad.module_idx[0] = 9999
	var report := view.set_columns(bad, 2)
	assert_bool(report["ok"]).is_false()
	assert_array(report["errors"]).is_not_empty()
	assert_int(view.cell_keys().size()).is_equal(3)
	assert_int(view.building_count()).is_equal(22)


func test_set_columns_before_setup_fails_cleanly() -> void:
	var view: BuildingView = auto_free(BuildingView.new())
	add_child(view)
	var report := view.set_columns(_two_module_cols(), 1)
	assert_bool(report["ok"]).is_false()


func test_buildings_over_water_are_not_instanced() -> void:
	var world := BuildingTestSupport.flat_world(8000.0, 100.0, Rect2(4000.0, 0.0, 4000.0, 8000.0), 15.0)
	var view: BuildingView = auto_free(BuildingView.new())
	add_child(view)
	var cfg := BuildingViewConfig.new()
	cfg.use_threads = false
	view.setup(world, _kit, cfg)
	var a := _kit.module_index("bld_res_mid_a")
	var cols := BuildingTestSupport.columns([{"m": a, "x": 1000.0, "z": 1000.0}, {"m": a, "x": 5000.0, "z": 1000.0},
			{"m": a, "x": 3990.0, "z": 2000.0}])
	view.set_columns(cols, 1)
	assert_int(int(view.stats["drawn"])).is_equal(1)
	assert_int(int(view.stats["dropped_water"])).is_equal(2)
	assert_int(view.cell_keys().size()).is_equal(1)   # su üstü hücrelerde düğüm yok


func test_height_comes_from_the_world_data() -> void:
	var view := _view()
	assert_float(view.height_at(1234.0, 2345.0)).is_equal(_world.height_at(1234.0, 2345.0))


func test_threaded_and_sequential_builds_agree() -> void:
	var seq := _view()
	seq.set_columns(_two_module_cols(), 1)
	var cfg := BuildingViewConfig.new()
	var par: BuildingView = auto_free(BuildingView.new())
	add_child(par)
	par.setup(_world, _kit, cfg)   # use_threads varsayılan true
	par.set_columns(_two_module_cols(), 1)
	for key in ["drawn", "cells", "supers", "mmi_nodes", "hlod1_nodes", "lod0_tris_all", "lod1_tris_all"]:
		assert_int(int(par.stats[key])).is_equal(int(seq.stats[key]))
	assert_array(par.cell_keys()).is_equal(seq.cell_keys())
	assert_int(int(par.stats["hlod1_tris_all"])).is_equal(int(seq.stats["hlod1_tris_all"]))
	assert_int(int(par.stats["hlod2_tris_all"])).is_equal(int(seq.stats["hlod2_tris_all"]))
