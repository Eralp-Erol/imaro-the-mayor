extends GdUnitTestSuite
## T-042 adım 3 (ölçüt 5, WLD-01) · Oyuncu yolunun 3B'ye yansıması: ağ delta'sı (uygulama ve geri alma) yalnız
## etkilenen yol chunk'larını yeniden kurar; sonuç tam yeniden kurmayla BİT-EŞİT; günlük eksikse tam kurma; arka plan
## işi sürerken dünya "meşgul" sayılır. Sentetik iki bölgeli dünya + el yapımı ızgara (gerçek Ismeral ağı değil).
## Ağ: x çizgileri 1100..1900, z çizgileri 1100..1400; chunk 400 m -> ızgara chunk x 2..4, z 2..3.

const P := preload("res://tests/sim/public_works/public_works_support.gd")
const CHUNK_M := 400.0
## Izgara üst kenarının orta noktasından kuzeye açık araziye 100 m (kenarı böler).
const SPLIT_FROM := Vector2(1180.0, 1100.0)
const SPLIT_TO := Vector2(1180.0, 1000.0)
## Izgara köşesinden batıya 100 m (kenarı bölmez, düğüme yapışır).
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


func _view() -> RoadView:
	var view: RoadView = auto_free(RoadView.new())
	add_child(view)
	view.build(_net, _style)
	return view


func _apply(a: Vector2, b: Vector2) -> Dictionary:
	var result := RoadDraftCheck.apply(_net, PackedVector2Array([a, b]), &"local", _rules)
	assert_bool(bool(result["applied"])).override_failure_message(str(result)).is_true()
	return result


## Chunk düğümünün tüm mesh köşelerinin özeti (iki LOD).
func _chunk_hash(view: RoadView, key: Vector2i) -> String:
	var node := view.chunk_node(key)
	if node == null:
		return ""
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	for child in node.get_children():
		var mesh := (child as MeshInstance3D).mesh
		var arrays := mesh.surface_get_arrays(0)
		ctx.update((arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).to_byte_array())
		ctx.update((arrays[Mesh.ARRAY_COLOR] as PackedColorArray).to_byte_array())
	return ctx.finish().hex_encode()


func _all_hashes(view: RoadView) -> Dictionary:
	var out := {}
	for key in view.plan().keys():
		out[key] = _chunk_hash(view, key)
	return out


func test_applying_a_road_rebuilds_only_the_affected_chunks_and_equals_a_full_rebuild() -> void:
	var view := _view()
	var sync := RoadEditSync.create(_net, view)
	var far_key := Vector2i(4, 3)
	var far_before := view.chunk_node(far_key)
	var near_before := view.chunk_node(Vector2i(2, 2))
	assert_object(far_before).is_not_null()
	assert_object(near_before).is_not_null()
	assert_bool(sync.pending()).is_false()
	_apply(SPLIT_FROM, SPLIT_TO)
	assert_bool(sync.pending()).is_true()
	var report := sync.sync()
	assert_bool(report["full"]).is_false()
	var keys: Array[Vector2i] = report["keys"]
	assert_array(keys).contains([Vector2i(2, 2)])
	assert_array(keys).not_contains([far_key])
	assert_int(keys.size()).is_less(view.plan().keys().size())
	assert_bool(sync.pending()).is_false()
	# Etkilenmeyen uzak chunk AYNI düğümdür; etkilenen yeni düğümdür.
	assert_object(view.chunk_node(far_key)).is_same(far_before)
	assert_object(view.chunk_node(Vector2i(2, 2))).is_not_same(near_before)
	# Tam yeniden kurmayla bit-eşit (aynı ağ verisinden).
	var fresh := _view()
	assert_dict(_all_hashes(view)).is_equal(_all_hashes(fresh))
	assert_int(int(view.stats["strips"])).is_equal(int(fresh.stats["strips"]))
	assert_int(int(view.stats["near_triangles"])).is_equal(int(fresh.stats["near_triangles"]))


func test_incremental_plan_equals_a_full_plan_for_apply_and_undo() -> void:
	var view := _view()
	var plan := view.plan()
	var seen := _net.graph_version
	_apply(SPLIT_FROM, SPLIT_TO)
	plan.apply_changes(_net, _style, _net.changes_since(seen))
	_assert_plan_equal(plan, RoadChunkPlan.build(_net, _style))
	seen = _net.graph_version
	_apply(WEST_FROM, WEST_TO)
	plan.apply_changes(_net, _style, _net.changes_since(seen))
	_assert_plan_equal(plan, RoadChunkPlan.build(_net, _style))
	for i in 2:
		seen = _net.graph_version
		assert_bool(RoadDraftCheck.undo(_net)["ok"]).is_true()
		plan.apply_changes(_net, _style, _net.changes_since(seen))
		_assert_plan_equal(plan, RoadChunkPlan.build(_net, _style))


func _assert_plan_equal(got: RoadChunkPlan, want: RoadChunkPlan) -> void:
	assert_dict(got.cells).is_equal(want.cells)
	assert_dict(got.edge_keys).is_equal(want.edge_keys)
	assert_dict(got.junction_keys).is_equal(want.junction_keys)
	assert_dict(got.trims).is_equal(want.trims)
	assert_dict(got.arm_trims).is_equal(want.arm_trims)
	assert_dict(got.junctions).is_equal(want.junctions)
	assert_int(got.strip_count).is_equal(want.strip_count)


func test_undo_restores_the_base_view_bit_for_bit() -> void:
	var view := _view()
	var base := _all_hashes(view)
	var sync := RoadEditSync.create(_net, view)
	_apply(SPLIT_FROM, SPLIT_TO)
	sync.sync()
	assert_dict(_all_hashes(view)).is_not_equal(base)
	assert_bool(RoadDraftCheck.undo(_net)["ok"]).is_true()
	var report := sync.sync()
	assert_bool(report["full"]).is_false()
	assert_array(report["keys"]).contains([Vector2i(2, 2)])
	assert_dict(_all_hashes(view)).is_equal(base)


func test_a_chain_of_roads_then_undos_always_matches_a_fresh_view() -> void:
	var view := _view()
	var sync := RoadEditSync.create(_net, view)
	_apply(SPLIT_FROM, SPLIT_TO)
	sync.sync()
	_apply(WEST_FROM, WEST_TO)
	sync.sync()
	assert_dict(_all_hashes(view)).is_equal(_all_hashes(_view()))
	RoadDraftCheck.undo(_net)
	sync.sync()
	assert_dict(_all_hashes(view)).is_equal(_all_hashes(_view()))
	RoadDraftCheck.undo(_net)
	sync.sync()
	assert_dict(_all_hashes(view)).is_equal(_all_hashes(_view()))


func test_nothing_to_sync_does_nothing() -> void:
	var view := _view()
	var sync := RoadEditSync.create(_net, view)
	var node := view.chunk_node(Vector2i(2, 2))
	assert_dict(sync.sync()).is_empty()
	assert_dict(sync.poll()).is_empty()
	assert_bool(sync.begin_async()).is_false()
	assert_object(view.chunk_node(Vector2i(2, 2))).is_same(node)


func test_a_truncated_change_log_falls_back_to_a_full_rebuild() -> void:
	var view := _view()
	var sync := RoadEditSync.create(_net, view)
	_apply(SPLIT_FROM, SPLIT_TO)
	_net.change_log.clear()  # günlük araya giren değişimi taşımıyor
	assert_bool(_net.change_log_covers(0)).is_false()
	var report := sync.sync()
	assert_bool(report["full"]).is_true()
	assert_dict(_all_hashes(view)).is_equal(_all_hashes(_view()))


func test_background_job_marks_the_world_busy_until_the_chunks_are_installed() -> void:
	var view := _view()
	var sync := RoadEditSync.create(_net, view)
	assert_bool(sync.world_busy()).is_false()
	_apply(SPLIT_FROM, SPLIT_TO)
	assert_bool(sync.world_busy()).override_failure_message("ağ değişti ama iş başlamadı: meşgul olmalı").is_true()
	assert_bool(sync.begin_async()).is_true()
	assert_bool(sync.is_busy()).is_true()
	assert_bool(sync.world_busy()).is_true()
	assert_bool(sync.begin_async()).override_failure_message("ikinci iş başlamaz").is_false()
	var report := sync.wait()
	assert_bool(report.is_empty()).is_false()
	assert_bool(sync.world_busy()).is_false()
	assert_dict(_all_hashes(view)).is_equal(_all_hashes(_view()))


func _wait_worker(sync: RoadEditSync) -> void:
	while not WorkerThreadPool.is_task_completed(sync._task):
		OS.delay_msec(1)


## B-020 · Normal akışta ağ iş sürerken değişmez: sayaç 0, hata yok.
func test_an_untouched_net_during_the_background_job_is_not_flagged() -> void:
	var view := _view()
	var sync := RoadEditSync.create(_net, view)
	_apply(SPLIT_FROM, SPLIT_TO)
	assert_bool(sync.begin_async()).is_true()
	_wait_worker(sync)
	sync.wait()
	assert_int(sync.mutated_during_job).is_equal(0)
	assert_bool(sync.world_busy()).is_false()


## B-020 · Meşgulken ağa yazan kod (gerçek hata: yıkım kuru koşusu uygula + geri al) sessiz kalmaz: hata günlüğe düşer.
## İşçi bitmiş durumda değiştirilir (testte gerçek veri yarışı yaratmamak için); sürüm farkı yine görünür.
func test_a_net_write_while_the_job_is_busy_is_reported_not_swallowed() -> void:
	var view := _view()
	var sync := RoadEditSync.create(_net, view)
	_apply(SPLIT_FROM, SPLIT_TO)
	assert_bool(sync.begin_async()).is_true()
	var job_version := _net.graph_version
	_wait_worker(sync)
	_apply(WEST_FROM, WEST_TO)   # meşgulken ağ yazımı (sözleşme ihlali)
	var now_version := _net.graph_version
	assert_int(now_version).is_not_equal(job_version)
	await assert_error(func() -> void: sync.wait()) \
		.is_push_error(RoadEditSync.mutation_message(job_version, now_version))
	assert_int(sync.mutated_during_job).is_equal(1)
	assert_bool(sync.pending()).override_failure_message("değişim görünüme yansımalı: pending kalır").is_true()


func test_the_player_road_adds_triangles_and_undo_removes_them() -> void:
	var view := _view()
	var base_tris := int(view.stats["near_triangles"])
	var sync := RoadEditSync.create(_net, view)
	_apply(WEST_FROM, WEST_TO)
	sync.sync()
	assert_int(int(view.stats["near_triangles"])).is_greater(base_tris)
	RoadDraftCheck.undo(_net)
	sync.sync()
	assert_int(int(view.stats["near_triangles"])).is_equal(base_tris)
