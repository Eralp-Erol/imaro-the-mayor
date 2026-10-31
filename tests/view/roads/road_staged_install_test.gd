extends GdUnitTestSuite
## Yol onayı sonrası kare sivrilmesi düzeltmesi (WLD-01/TEK-03; görünüm yalnız temsil): dilimli kurulum (`begin_install`/
## `step_install`/`step_far`) SENKRON kurulumla BİT-EŞİT sonuç verir; dilim bütçesi mantık olarak denetlenir (sabit kare
## ya da duvar saati yok: bütçe 0 -> çağrı başına tam bir chunk). Sentetik ızgara ağı (gerçek Ismeral değil).

const P := preload("res://tests/sim/public_works/public_works_support.gd")
const CHUNK_M := 400.0
const SPLIT_FROM := Vector2(1180.0, 1100.0)
const SPLIT_TO := Vector2(1180.0, 1000.0)
const WEST_FROM := Vector2(1100.0, 1100.0)
const WEST_TO := Vector2(1000.0, 1100.0)

var _net: WorldNetwork
var _style: RoadStyle
var _rules: RoadDraftRules


func before_test() -> void:
	_net = P.network()
	_style = RoadStyle.load_default()
	_style.data["chunk_m"] = CHUNK_M
	_rules = RoadDraftRules.new()


func _view(far: bool = false, group_verts: int = 0) -> RoadView:
	var view: RoadView = auto_free(RoadView.new())
	view.build_far_mesh = far
	if group_verts > 0:
		view.far_group_verts = group_verts
	add_child(view)
	view.build(_net, _style)
	return view


func _apply(a: Vector2, b: Vector2) -> void:
	var result := RoadDraftCheck.apply(_net, PackedVector2Array([a, b]), &"local", _rules)
	assert_bool(bool(result["applied"])).override_failure_message(str(result)).is_true()


func _chunk_hash(view: RoadView, key: Vector2i) -> String:
	var node := view.chunk_node(key)
	if node == null:
		return ""
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	for child in node.get_children():
		var arrays := (child as MeshInstance3D).mesh.surface_get_arrays(0)
		ctx.update((arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).to_byte_array())
		ctx.update((arrays[Mesh.ARRAY_COLOR] as PackedColorArray).to_byte_array())
	return ctx.finish().hex_encode()


func _all_hashes(view: RoadView) -> Dictionary:
	var out := {}
	for key in view.plan().keys():
		out[key] = _chunk_hash(view, key)
	return out


## Uzak meshin TÜM yüzeylerinin köşe/renk/normal akışı (yüzey sınırlarından bağımsız bit özeti).
func _far_stream_hash(view: RoadView) -> String:
	var node := view.far_node()
	if node == null:
		return ""
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	for s in node.mesh.get_surface_count():
		var arrays := node.mesh.surface_get_arrays(s)
		verts.append_array(arrays[Mesh.ARRAY_VERTEX])
		normals.append_array(arrays[Mesh.ARRAY_NORMAL])
		colors.append_array(arrays[Mesh.ARRAY_COLOR])
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(verts.to_byte_array())
	ctx.update(normals.to_byte_array())
	ctx.update(colors.to_byte_array())
	return ctx.finish().hex_encode()


## Planı güncelleyip iş verisini hesaplar (RoadEditSync._prepare + worker adımı, senkron).
func _prepare(view: RoadView, seen: int) -> Dictionary:
	var plan := view.plan()
	var changes := _net.changes_since(seen)
	var touched := plan.apply_changes(_net, _style, changes)
	var keys := RoadEditSync.keys_for(changes, touched, plan)
	return {"keys": keys, "plan": plan, "meshes": view.compute_chunk_data(keys, plan)}


func test_zero_budget_installs_exactly_one_chunk_per_step_and_equals_the_sync_install() -> void:
	var staged := _view()
	var seen := _net.graph_version
	_apply(SPLIT_FROM, SPLIT_TO)
	_apply(WEST_FROM, WEST_TO)
	var job := _prepare(staged, seen)
	var keys: Array[Vector2i] = job["keys"]
	assert_int(keys.size()).override_failure_message("test en az iki chunk etkilemeli").is_greater(1)
	staged.begin_install(keys, job["plan"], job["meshes"])
	assert_bool(staged.install_pending()).is_true()
	var steps := 0
	while not staged.step_install(0):
		steps += 1
		assert_bool(staged.install_pending()).is_true()
		assert_int(steps).is_less(keys.size())
	assert_int(steps).override_failure_message("bütçe 0: her çağrı bir chunk").is_equal(keys.size() - 1)
	assert_bool(staged.install_pending()).is_false()
	var sync_view := _view()   # aynı (son) ağdan tam kurulum
	assert_dict(_all_hashes(staged)).is_equal(_all_hashes(sync_view))
	assert_int(int(staged.stats["near_triangles"])).is_equal(int(sync_view.stats["near_triangles"]))
	assert_int(int(staged.stats["last_rebuilt"])).is_equal(keys.size())


func test_a_large_budget_finishes_in_one_step_and_emits_chunks_rebuilt_once() -> void:
	var view := _view()
	var seen := _net.graph_version
	_apply(SPLIT_FROM, SPLIT_TO)
	var job := _prepare(view, seen)
	var emitted: Array = []
	view.chunks_rebuilt.connect(func(k: Array[Vector2i]) -> void: emitted.append(k.size()))
	view.begin_install(job["keys"], job["plan"], job["meshes"])
	assert_bool(view.step_install(1 << 40)).is_true()
	assert_array(emitted).is_equal([(job["keys"] as Array).size()])
	assert_bool(view.step_install(0)).override_failure_message("iş yoksa true").is_true()


func test_staged_far_mesh_has_the_same_vertex_stream_as_the_single_surface_far_mesh_in_several_surfaces() -> void:
	var view := _view(true, 200)   # küçük yüzey: birden çok yüzey
	var seen := _net.graph_version
	_apply(SPLIT_FROM, SPLIT_TO)
	_apply(WEST_FROM, WEST_TO)
	var job := _prepare(view, seen)
	view.begin_install(job["keys"], job["plan"], job["meshes"])
	assert_bool(view.step_install(1 << 40)).is_true()
	assert_bool(view.far_pending()).override_failure_message("kurulum bitince uzak mesh bekler").is_true()
	var old_far := view.far_node()
	var steps := 0
	while not view.step_far(0):
		steps += 1
		assert_object(view.far_node()).override_failure_message("bitene kadar eski uzak mesh kalır").is_same(old_far)
		assert_int(steps).is_less(1000)
	assert_bool(view.far_pending()).is_false()
	assert_int(steps).override_failure_message("birden çok dilim bekleniyordu").is_greater(0)
	assert_int(view.far_node().mesh.get_surface_count()).is_greater(1)
	# Referans: aynı ağ, tek yüzeyli senkron uzak mesh.
	var ref := _view(true)
	assert_int(ref.far_node().mesh.get_surface_count()).is_equal(1)
	assert_str(_far_stream_hash(view)).is_equal(_far_stream_hash(ref))
	assert_int(int(view.stats["far_triangles"])).is_equal(int(ref.stats["far_triangles"]))
	assert_int(int(view.stats["far_triangles"])).is_equal(int(view.stats["metro_triangles"]))


func test_a_new_install_restarts_a_far_mesh_job_in_progress_and_the_result_is_current() -> void:
	var view := _view(true, 200)
	var seen := _net.graph_version
	_apply(SPLIT_FROM, SPLIT_TO)
	var job := _prepare(view, seen)
	view.begin_install(job["keys"], job["plan"], job["meshes"])
	view.step_install(1 << 40)
	view.step_far(0)   # yarım kaldı
	seen = _net.graph_version
	_apply(WEST_FROM, WEST_TO)
	job = _prepare(view, seen)
	view.begin_install(job["keys"], job["plan"], job["meshes"])
	view.step_install(1 << 40)
	view.settle_far()
	assert_bool(view.far_pending()).is_false()
	assert_str(_far_stream_hash(view)).is_equal(_far_stream_hash(_view(true)))


func test_edit_sync_poll_with_zero_budget_spreads_the_install_and_world_stays_busy_until_done() -> void:
	var view := _view(true, 200)
	var sync := RoadEditSync.create(_net, view)
	_apply(SPLIT_FROM, SPLIT_TO)
	_apply(WEST_FROM, WEST_TO)
	assert_bool(sync.begin_async()).is_true()
	var report := {}
	var polls := 0
	while report.is_empty() and polls < 1000:
		report = sync.poll(0)
		polls += 1
		if report.is_empty():
			assert_bool(sync.world_busy()).override_failure_message("kurulum sürerken dünya meşgul").is_true()
		OS.delay_msec(1)
	assert_bool(report.is_empty()).is_false()
	assert_bool(sync.world_busy()).is_false()
	assert_bool(sync.is_busy()).is_false()
	# Rapor sonrası uzak mesh dilimleri: poll() her çağrıda bir dilim yürütür.
	var guard := 0
	while view.far_pending() and guard < 1000:
		sync.poll(0)
		guard += 1
	assert_bool(view.far_pending()).is_false()
	var fresh := _view(true)
	assert_dict(_all_hashes(view)).is_equal(_all_hashes(fresh))
	assert_str(_far_stream_hash(view)).is_equal(_far_stream_hash(fresh))


func test_edit_sync_wait_settles_everything_including_the_far_mesh() -> void:
	var view := _view(true, 200)
	var sync := RoadEditSync.create(_net, view)
	_apply(SPLIT_FROM, SPLIT_TO)
	assert_bool(sync.begin_async()).is_true()
	var report := sync.wait()
	assert_bool(report.is_empty()).is_false()
	assert_bool(view.far_pending()).is_false()
	assert_bool(sync.world_busy()).is_false()
	assert_str(_far_stream_hash(view)).is_equal(_far_stream_hash(_view(true)))


func test_corridor_refresh_is_deferred_by_one_frame_after_a_road_report() -> void:
	var pr := PlayableRoads.create(_net, null, null, Callable())
	assert_bool(pr.corridors_due()).is_false()
	pr.note_report({}, {}, 1)
	assert_bool(pr.corridors_due()).override_failure_message("rapor yoksa istek yok").is_false()
	pr.note_report({"ms": 1.0, "rebuilt": 1, "full": false}, {}, 1)
	assert_bool(pr.corridors_due()).override_failure_message("raporla aynı karede yapılmaz").is_false()
	assert_bool(pr.corridors_due()).override_failure_message("bir kare sonra yapılır").is_true()
	assert_bool(pr.corridors_due()).override_failure_message("yalnız bir kez").is_false()
