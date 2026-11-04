extends GdUnitTestSuite
## T-050 · LifeView: örnekler hücre başına MultiMesh, menzil dışı hücre HİÇ kurulmaz (uzaktan görünmez), sayılar
## yerleşim katmanıyla (sim verisi) birebir, hareket gölgelendirici saatiyle sürülür (CPU'da kare başı örnek
## yazımı yok), sim hızı 0 iken saat durur. Sahne bağlantısı: `LifeHost` `playable.tscn` içinde ayrı düğüm
## (playable.gd 1000 satır sınırı).

const DX := 160.0
const DZ := 100.0
const ORIGIN := Vector2(500.0, 500.0)

var _world: WorldData


func before() -> void:
	_world = NetworkTestSupport.flat_world(3000.0)


func _ground(_x: float, _z: float) -> float:
	return 10.0


func _quiet_gate() -> LibraryGate:
	var g := LibraryGate.new()
	g.report_errors = false
	g.load_game_tables(PackedStringArray(LibraryGate.LIFE_TABLE_PATHS), LibraryGate.CATALOG_PATH)
	return g


func _view(units: Vector3i, profile: StringName = &"desktop") -> Dictionary:
	var net := NetworkTestSupport.grid_network(_world, 3, 3, DX, DZ, ORIGIN)
	var cfg := LifeConfig.load_default(profile)
	var act := LifeEdgeActivity.create(net, cfg)
	for pid: int in net.parcels:
		act.set_parcel(pid, units)
	var assets := LifeAssets.load_default(_quiet_gate())
	assert_bool(assets.ok()).is_true()
	var view := LifeView.new()
	add_child(view)
	auto_free(view)
	view.setup(cfg, assets, act, 7, _ground)
	return {"view": view, "act": act, "cfg": cfg}


func _expected_counts(act: LifeEdgeActivity, cfg: LifeConfig) -> Vector2i:
	var cars := 0
	var people := 0
	var assets := LifeAssets.load_default(_quiet_gate())
	for cell: Vector2i in act.cells():
		var res := LifeLayout.build_cell(act, cell, 7, cfg.density(), _ground, assets.car_rows, LifeLayout.sidewalk_table())
		var c := res["counts"] as PackedInt32Array
		cars += c[LifeLayout.KIND_CAR]
		people += c[LifeLayout.KIND_NEUTRAL] + c[LifeLayout.KIND_BROAD]
	return Vector2i(cars, people)


func _count_multimesh_instances(view: LifeView) -> Dictionary:
	var out := {"cars": 0, "human_l0": 0, "human_l1": 0, "mmi": 0}
	for cell_node in view.get_children():
		for mmi in cell_node.get_children():
			var m := mmi as MultiMeshInstance3D
			out["mmi"] += 1
			if m.name == "Cars":
				out["cars"] += m.multimesh.instance_count
			elif String(m.name).ends_with("L0"):
				out["human_l0"] += m.multimesh.instance_count
			elif String(m.name).ends_with("L1"):
				out["human_l1"] += m.multimesh.instance_count
			assert_int(m.cast_shadow).is_equal(GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
			assert_float(m.visibility_range_end).is_greater(0.0)
	return out


func test_nearby_cells_are_built_with_exactly_the_layout_counts() -> void:
	var made := _view(Vector3i(6, 2, 0))
	var view: LifeView = made["view"]
	view.track_camera(Vector3.ZERO, ORIGIN + Vector2(DX * 1.5, DZ * 1.5))
	view.settle()
	var expect := _expected_counts(made["act"], made["cfg"])
	assert_int(expect.x).is_greater(0)
	assert_int(view.stats["cars"]).is_equal(expect.x)
	assert_int(view.stats["people"]).is_equal(expect.y)
	var n := _count_multimesh_instances(view)
	assert_int(n["cars"]).is_equal(expect.x)
	# İnsan her LOD katmanında aynı örnek listesini taşır (gölgelendirici menzile göre çökertir).
	assert_int(n["human_l0"]).is_equal(expect.y)
	assert_int(n["human_l1"]).is_equal(expect.y)
	assert_int(view.stats["mmi"]).is_equal(n["mmi"])


func test_cells_beyond_range_are_never_built() -> void:
	var made := _view(Vector3i(6, 2, 0))
	var view: LifeView = made["view"]
	view.track_camera(Vector3.ZERO, Vector2(2900.0, 2900.0))   # en yakın hücre >= menzil + kenar payı uzakta
	view.settle()
	assert_int(view.stats["cars"]).is_equal(0)
	assert_int(view.stats["people"]).is_equal(0)
	assert_int(view.get_child_count()).is_equal(0)


func test_no_sim_activity_builds_nothing() -> void:
	var made := _view(Vector3i.ZERO)
	var view: LifeView = made["view"]
	view.track_camera(Vector3.ZERO, ORIGIN + Vector2(DX, DZ))
	view.settle()
	assert_int(view.stats["cars"] + view.stats["people"]).is_equal(0)


func test_touch_profile_is_sparser_than_desktop() -> void:
	var d := _view(Vector3i(8, 4, 0), &"desktop")
	var t := _view(Vector3i(8, 4, 0), &"touch")
	for made: Dictionary in [d, t]:
		(made["view"] as LifeView).track_camera(Vector3.ZERO, ORIGIN + Vector2(DX * 1.5, DZ * 1.5))
		(made["view"] as LifeView).settle()
	assert_int(t["view"].stats["cars"]).is_less(d["view"].stats["cars"])
	assert_int(t["view"].stats["people"]).is_less(d["view"].stats["people"])


func test_motion_is_driven_by_the_shader_clock_and_stops_when_the_sim_is_paused() -> void:
	var made := _view(Vector3i(6, 2, 0))
	var view: LifeView = made["view"]
	view.set_time_fixed(5.0)
	assert_float(view.time_seconds()).is_equal(5.0)
	view.set_running(true)
	view._process(0.5)
	assert_float(view.time_seconds()).is_equal_approx(5.5, 0.0001)
	view.set_running(false)
	view._process(2.0)
	assert_float(view.time_seconds()).is_equal_approx(5.5, 0.0001)
	var mat: ShaderMaterial = view._mat_car
	assert_float(float(mat.get_shader_parameter("life_t"))).is_equal_approx(5.5, 0.0001)


func test_dirty_cell_is_rebuilt_when_sim_data_changes_and_old_nodes_are_freed() -> void:
	var made := _view(Vector3i(3, 0, 0))
	var view: LifeView = made["view"]
	var act: LifeEdgeActivity = made["act"]
	view.track_camera(Vector3.ZERO, ORIGIN + Vector2(DX * 1.5, DZ * 1.5))
	view.settle()
	var before_cars: int = view.stats["cars"]
	for pid: int in act.net.parcels:
		act.set_parcel(pid, Vector3i(9, 6, 0))
	view.settle()
	assert_int(view.stats["cars"]).is_greater(before_cars)
	await get_tree().process_frame
	assert_int(view.get_child_count()).is_equal(act.cells().size() - _empty_cells(view, act))


func _empty_cells(view: LifeView, act: LifeEdgeActivity) -> int:
	var empty := 0
	for cell: Vector2i in act.cells():
		if view.get_node_or_null("LifeCell_%d_%d" % [cell.x, cell.y]) == null:
			empty += 1
	return empty


func test_playable_scene_hosts_life_as_a_separate_child_node() -> void:
	var state := (load("res://scenes/game/playable.tscn") as PackedScene).get_state()
	var found := false
	for i in state.get_node_count():
		if state.get_node_name(i) == &"Life":
			found = true
			assert_str(String(state.get_node_type(i))).is_equal("Node")
			assert_str(str(state.get_node_property_value(i, 0))).contains("life_host")
	assert_bool(found).override_failure_message("playable.tscn içinde Life düğümü yok").is_true()
	var lines := FileAccess.get_file_as_string("res://src/game/playable.gd").split("\n").size()
	assert_int(lines).override_failure_message("playable.gd 1000 satır sınırını aştı (%d)" % lines).is_less_equal(1001)
