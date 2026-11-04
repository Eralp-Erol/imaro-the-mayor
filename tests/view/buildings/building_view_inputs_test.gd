extends GdUnitTestSuite
## T-062 A3 · Sim -> görünüm girdileri (TEK-01/02/03, WLD-01): AYNI sim/yerleşim durumu -> AYNI görünüm girdileri
## (sütunlar -> hücre verisi baytları, HLOD1/HLOD2 geometrisi, çizilen modül kimlikleri). Görünüm sim'e yazmaz.
## Gerçek küçük dünya (tests/game/m2_render_support.gd): gerçek T0 yerleşimi + onaylı hero oyun tablosu.

var _kit: BuildingKit
var _world: WorldData
var _cols: BuildingColumns


func before() -> void:
	var fx := M2RenderSupport.fixture()
	_world = fx["world"]
	_cols = (fx["settlement"] as SettlementResult).columns
	_kit = BuildingTestSupport.kit()


func _view() -> BuildingView:
	var view: BuildingView = auto_free(BuildingView.new())
	add_child(view)
	var cfg := BuildingViewConfig.new()
	cfg.use_threads = false
	view.setup(_world, _kit, cfg)
	return view


func test_settlement_module_indices_resolve_to_the_same_kit_ids_as_the_placement_table() -> void:
	var rules := (M2RenderSupport.fixture()["settlement"] as SettlementResult).rules
	assert_int(rules.modules.size()).is_equal(_kit.count)
	for i in _kit.count:
		assert_str(rules.modules[i].id).is_equal(_kit.ids[i])
		assert_int(rules.modules[i].idx).is_equal(i)
	assert_int(_cols.count).is_greater(50)
	for i in _cols.count:
		assert_int(_cols.module_idx[i]).is_between(0, _kit.count - 1)


func test_t0_view_draws_only_approved_ids_and_the_same_columns_give_identical_cell_data() -> void:
	var a := _view()
	var b := _view()
	assert_bool(a.set_columns(_cols, 1)["ok"]).is_true()
	assert_bool(b.set_columns(_cols, 1)["ok"]).is_true()
	assert_int(int(a.stats["unapproved_ids"])).is_equal(0)
	var gate := BuildingTestSupport.gate()
	var drawn := a.drawn_module_ids()
	assert_int(drawn.size()).is_greater(3)
	for id in drawn:
		assert_bool(gate.is_approved(id)).is_true()
		assert_bool(id.begins_with("bld_hero_")).is_true()
	assert_array(Array(drawn)).is_equal(Array(b.drawn_module_ids()))
	assert_array(a.cell_keys()).is_equal(b.cell_keys())
	for key in a.cell_keys():
		var ca := a.cell_summary(key)
		var cb := b.cell_summary(key)
		assert_array(ca.kept).is_equal(cb.kept)
		assert_array(ca.base_y).is_equal(cb.base_y)
		assert_int(ca.lod0_tris).is_equal(cb.lod0_tris)
	for k in ["drawn", "mmi_nodes", "hlod1_nodes", "hlod1_tris_all", "hlod2_tris_all", "lod0_tris_all", "lod1_tris_all"]:
		assert_int(int(a.stats[k])).is_equal(int(b.stats[k]))


func test_chunk_builder_bytes_are_identical_for_identical_sim_state() -> void:
	var plan := BuildingChunkPlan.build(_cols, _world.origin, 1000.0, 4)
	var config := BuildingViewConfig.new()
	for key in plan.keys():
		var a := BuildingChunkBuilder.build_cell(_cols, plan, key, _kit, _world, config)
		var b := BuildingChunkBuilder.build_cell(_cols, plan, key, _kit, _world, config)
		assert_array(a.modules).is_equal(b.modules)
		for n in a.buffers.size():
			assert_bool(a.buffers[n] == b.buffers[n]).is_true()
		assert_bool(a.hlod1_vertices == b.hlod1_vertices).is_true()
		assert_bool(a.hlod1_colors == b.hlod1_colors).is_true()


func test_hero_instance_is_centred_on_its_footprint_the_mesh_pivot_needs_no_extra_offset() -> void:
	# Yerleşim ayak izi MERKEZİNİ (x, z) verir; pivot normalize mesh'le örnek dönüşümü tam o noktaya oturur.
	var m := _kit.module_index(BuildingTestSupport.CIVIC_A)   # pivot kayması en büyük ailelerden (cephe çizgisi pivotu)
	assert_float(absf(_kit.pivot_offset[m].z)).is_greater(1.0)
	var cols := BuildingTestSupport.columns([{"m": m, "x": 500.0, "z": 500.0, "yaw": 0.0}])
	var world := BuildingTestSupport.flat_world(2000.0, 100.0, Rect2(), 5.0)
	var plan := BuildingChunkPlan.build(cols, world.origin, 1000.0, 4)
	var data := BuildingChunkBuilder.build_cell(cols, plan, plan.keys()[0], _kit, world, BuildingViewConfig.new())
	var aabb := (_kit.tier_mesh(m, BuildingLod.Tier.LOD0) as ArrayMesh).get_aabb()
	var world_center := Vector2(data.origin.x + data.buffers[0][3] + aabb.get_center().x,
			data.origin.y + data.buffers[0][11] + aabb.get_center().z)
	assert_vector(world_center).is_equal_approx(Vector2(500.0, 500.0), Vector2.ONE * 0.1)
