extends GdUnitTestSuite
## T-042b OYUN KATMANI (D-011, CAN-03, WLD-01) · `PlayableExpropriation`: ağın parsel kümesi değişince T0 yapıları
## görünümden süzülür / geri gelir. Gerçek `WorldNetwork` (kamulaştırmalı yol, geri alma), gerçek `BuildingView`; sim
## yok
## (sim yan etkileri `playable_expropriation_game_test`te gerçek sahneyle). Başsız.

const DX := 160.0
const DZ := 100.0
const ORIGIN := Vector2(500.0, 500.0)
const LOCAL := WorldRoadEdge.CLASS_LOCAL
const THROUGH: Array = [Vector2(580, 500), Vector2(580, 600)]

var _net_world: WorldData
var _view_world: WorldData
var _kit: BuildingKit


func before() -> void:
	_net_world = NetworkTestSupport.flat_world(3000.0)
	_view_world = BuildingTestSupport.flat_world(8000.0, 100.0, Rect2(), 15.0)
	_kit = BuildingTestSupport.kit()


## Gerçek kamulaştırma kipinde ızgara ağı + her parselin merkezinde bir T0 yapısı + T0 görünümü + takipçi.
func _fixture() -> Dictionary:
	var net := NetworkTestSupport.grid_network(_net_world, 3, 3, DX, DZ, ORIGIN, 7, NetworkTestSupport.KEEP_PARCELS)
	var module := _kit.module_index(BuildingTestSupport.MID_A)
	var ids: Array = net.parcels.keys()
	ids.sort()
	var rows: Array = []
	for pid: int in ids:
		var c := (net.parcels[pid] as WorldParcel).centroid
		rows.append({"m": module, "x": c.x, "z": c.y, "parcel": pid})
	var cols := BuildingTestSupport.columns(rows)
	var view: BuildingView = auto_free(BuildingView.new())
	add_child(view)
	var cfg := BuildingViewConfig.new()
	cfg.use_threads = false
	view.setup(_view_world, _kit, cfg)
	view.set_columns(cols, 1)
	var occupied := {}
	for pid: int in ids:
		occupied[pid] = true
	var follow := PlayableExpropriation.create(net, cols, view, occupied)
	return {"net": net, "cols": cols, "view": view, "occupied": occupied, "follow": follow, "ids": ids}


func _rules() -> RoadDraftRules:
	var r := RoadDraftRules.new()
	r.crossing_parcels = RoadDraftRules.CROSSING_ALLOW
	return r


func _take(net: WorldNetwork) -> PackedInt32Array:
	var rep := net.add_road_expropriating(PackedVector2Array(THROUGH), LOCAL)
	assert_bool(rep["ok"]).override_failure_message(str(rep)).is_true()
	var removed := PackedInt32Array()
	for pid in rep["removed_parcels"]:
		removed.append(int(pid))
	return removed


func _signature(view: BuildingView, cols: BuildingColumns) -> String:
	var parts: Array[String] = []
	for k in view.cell_keys():
		var data := view.cell_summary(k)
		var at: Array[String] = []
		for i in data.kept:
			at.append("%d@%.0f,%.0f" % [cols.parcel_id[i], cols.x[i], cols.z[i]])
		at.sort()
		parts.append("%s:%s" % [str(k), ";".join(at)])
	return "|".join(parts)


func test_taken_parcels_lose_their_t0_buildings_and_undo_brings_them_back() -> void:
	var fx := _fixture()
	var net: WorldNetwork = fx["net"]
	var view: BuildingView = fx["view"]
	var follow: PlayableExpropriation = fx["follow"]
	var cols: BuildingColumns = fx["cols"]
	var total := cols.count
	var before := _signature(view, cols)
	var centroids := {}
	for pid in RoadDraftCheck.taken_parcels(net, PackedVector2Array(THROUGH), LOCAL):
		var c := net.parcel(int(pid)).centroid
		centroids[int(pid)] = c
		assert_int(net.parcel_id_at(c.x, c.y)).is_equal(int(pid))   # alınmadan önce seçilebilir
	var removed := _take(net)
	assert_int(removed.size()).is_greater(0)
	follow.settle()
	assert_int(follow.taken_count()).is_equal(removed.size())
	assert_int(view.building_count()).is_equal(total - removed.size())
	for pid in removed:
		assert_bool(follow.is_hidden(pid)).is_true()
		assert_bool((fx["occupied"] as Dictionary).has(pid)).is_false()   # denetçi/imar "yapı var mı"
		assert_bool(net.parcels.has(pid)).is_false()
	assert_str(_signature(view, cols)).is_not_equal(before)
	# Alınan parselin eski yerinde seçim onu bulamaz (dünya parseli yok): oyun yolu null'a hazır.
	for pid: int in centroids:
		assert_int(net.parcel_id_at((centroids[pid] as Vector2).x, (centroids[pid] as Vector2).y)).is_not_equal(pid)
		assert_object(net.parcel(pid)).is_null()
	net.undo_last_op()
	follow.settle()
	assert_int(follow.taken_count()).is_equal(0)
	assert_int(view.building_count()).is_equal(total)
	assert_str(_signature(view, cols)).is_equal(before)
	for pid in removed:
		assert_bool((fx["occupied"] as Dictionary).has(pid)).is_true()


func test_only_the_expected_cell_and_super_chunk_are_rebuilt() -> void:
	var fx := _fixture()
	var net: WorldNetwork = fx["net"]
	var view: BuildingView = fx["view"]
	var follow: PlayableExpropriation = fx["follow"]
	var cells_before := view.cell_keys()
	var nodes_before := {}
	for k in cells_before:
		nodes_before[k] = view.cell_node(k)
	_take(net)
	var rebuilt: Array[Vector2i] = []
	view.cells_rebuilt.connect(func(keys: Array) -> void: rebuilt.append_array(keys))
	follow.settle()
	# Ağ 3 km'lik dünyada: tüm yapılar tek 1 km'lik hücrede; en az bir hücre kuruldu ve kurulanlar etkilenen hücreler.
	assert_int(rebuilt.size()).is_greater(0)
	for k in view.cell_keys():
		if not rebuilt.has(k):
			assert_object(view.cell_node(k)).is_same(nodes_before[k])


func test_a_change_log_gap_falls_back_to_a_full_reconcile_with_the_same_result() -> void:
	var fx := _fixture()
	var net: WorldNetwork = fx["net"]
	var view: BuildingView = fx["view"]
	var follow: PlayableExpropriation = fx["follow"]
	var removed := _take(net)
	net.change_log.clear()   # günlük eksik (yükleme/uzun boşluk)
	assert_bool(net.change_log_covers(0)).is_false()
	var rep := follow.reconcile()
	assert_bool(rep["full"]).is_true()
	assert_int(rep["hidden"]).is_equal(removed.size())
	while follow.busy():
		follow.poll(1000000)
	assert_int(view.building_count()).is_equal((fx["cols"] as BuildingColumns).count - removed.size())


func test_selection_ring_is_cleared_when_its_parcel_is_taken() -> void:
	var fx := _fixture()
	var net: WorldNetwork = fx["net"]
	var removed_preview: PackedInt64Array = RoadDraftCheck.taken_parcels(net, PackedVector2Array(THROUGH), LOCAL)
	assert_int(removed_preview.size()).is_greater(0)
	var victim := int(removed_preview[0])
	var ring: ParcelSelectionRing = auto_free(ParcelSelectionRing.new())
	add_child(ring)
	ring.select(net.parcel(victim))
	assert_int(ring.parcel_id()).is_equal(victim)
	var follow := PlayableExpropriation.create(net, fx["cols"], fx["view"], fx["occupied"], null,
			func() -> Object: return ring)
	_take(net)
	follow.settle()
	assert_int(ring.parcel_id()).is_equal(-1)


func test_protected_ids_come_from_the_heritage_landmark_and_civic_flags() -> void:
	var cols := BuildingColumns.new()
	var module := _kit.module_index(BuildingTestSupport.MID_A)
	cols.add(5, module, 1.0, 1.0, 0.0, 3, 0, 0, 0, 128, BuildingColumns.FLAG_HERITAGE, BuildingColumns.ERA_OLD)
	cols.add(3, module, 2.0, 2.0, 0.0, 3, 0, 0, 0, 128, BuildingColumns.FLAG_CIVIC, BuildingColumns.ERA_MID)
	cols.add(9, module, 3.0, 3.0, 0.0, 3, 0, 0, 0, 128, BuildingColumns.FLAG_LANDMARK, BuildingColumns.ERA_OLD)
	cols.add(4, module, 4.0, 4.0, 0.0, 3, 0, 0, 0, 128, BuildingColumns.FLAG_INDUSTRY | BuildingColumns.FLAG_GROUND_SHOP,
			BuildingColumns.ERA_MID)
	cols.add(3, module, 5.0, 5.0, 0.0, 3, 0, 0, 0, 128, 0, BuildingColumns.ERA_MID)
	assert_array(Array(PlayableExpropriation.protected_ids(cols))).is_equal([3, 5, 9])
	assert_int(PlayableExpropriation.protected_ids(null).size()).is_equal(0)


func test_attach_port_installs_the_real_bridge_and_the_protected_set() -> void:
	var fx := _fixture()
	var net: WorldNetwork = fx["net"]
	var cols := BuildingColumns.new()
	cols.add(7, 0, 1.0, 1.0, 0.0, 3, 0, 0, 0, 128, BuildingColumns.FLAG_HERITAGE, BuildingColumns.ERA_OLD)
	var rules := RoadDraftRules.load_path(PlayableRoads.NETWORK_PATH)
	var ctx := PublicWorksContext.create(net, rules, PublicWorksConfig.load_default())
	assert_object(ctx).is_not_null()
	PlayableExpropriation.attach_port(ctx, net, rules, cols)
	assert_object(ctx.expropriation).is_instanceof(NetworkExpropriationPort)
	assert_bool(ctx.protected_ids.has(7)).is_true()
