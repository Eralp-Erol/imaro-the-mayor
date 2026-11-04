extends GdUnitTestSuite
## T-050 türev önbellekleri tam hesapla BİT-BİT aynıdır:
##  - NetworkRotationCache: düğüm dönüş sırası, ardıl yarım kenar tablosu, çapraz çarpım tablosu ve önbellekli yüz
##    yürüyüşü (extract_local) taze hesapla aynı; bayat kayıt kalmaz (tablo boyutu);
##  - NetworkComponents: components()/component_of() eski (DFS) algoritmayla aynı (liste, sıra, indeksler); yama yolu
##    gerçekten çalışır (sayaç), kopma/silme/kapatma tam hesaba düşer; GERİ ALMA önbelleği işlem öncesi kopyadan geri
##    koyar (tam hesap YOK, T-051) ve sonuç yine eski algoritmayla aynıdır (tüm op türleri, sorgusuz ardışık işlemler,
##    kopya sınırını aşan derin yığın).
## Her adım: yol ekle / geri al / aç-kapa / kenar sil karışık, yol + ray + feribot sınıfları, ayrık bileşenler.

const ORIGIN := Vector2(500.0, 500.0)
const DX := 160.0
const DZ := 100.0
const LOCAL := WorldRoadEdge.CLASS_LOCAL
const MODES: Array[StringName] = [WorldNetwork.MODE_ROAD, WorldNetwork.MODE_RAIL]

var _world: WorldData


func before() -> void:
	_world = NetworkTestSupport.flat_world(3000.0)


## 3x3 ızgara + ayrık yol parçası + ayrık ray hattı + ızgaraya bağlı feribot kenarı; mühürlü.
func _net(extra: Dictionary = {}) -> WorldNetwork:
	var net := NetworkTestSupport.empty_network(_world, 7, extra)
	for j in 4:
		net.author_polyline(PackedVector2Array([ORIGIN + Vector2(0, j * DZ), ORIGIN + Vector2(3 * DX, j * DZ)]), LOCAL)
	for i in 4:
		net.author_polyline(PackedVector2Array([ORIGIN + Vector2(i * DX, 0), ORIGIN + Vector2(i * DX, 3 * DZ)]), LOCAL)
	net.author_polyline(PackedVector2Array([Vector2(1400, 500), Vector2(1500, 500), Vector2(1500, 600)]), LOCAL)
	net.author_polyline(PackedVector2Array([Vector2(500, 1000), Vector2(980, 1000)]), WorldRoadEdge.CLASS_RAIL)
	net.author_polyline(PackedVector2Array([Vector2(980, 500), Vector2(1200, 500)]), WorldRoadEdge.CLASS_FERRY)
	net.seal_base()
	return net


# ---------------------------------------------------------------- referans hesaplar

## Eski (önbelleksiz) bileşen algoritması: kimliğe göre sıralı düğümlerden DFS.
func _ref_components(net: WorldNetwork, mode: StringName) -> Dictionary:
	var of := {}
	var list: Array[PackedInt32Array] = []
	var ids: Array = net.nodes.keys()
	ids.sort()
	for nid: int in ids:
		if of.has(nid) or not net._has_mode_edge(nid, mode):
			continue
		var comp_index := list.size()
		var members := PackedInt32Array()
		var stack: Array[int] = [nid]
		of[nid] = comp_index
		while not stack.is_empty():
			var cur: int = stack.pop_back()
			members.append(cur)
			for eid in net.adjacency[cur]:
				var e: WorldRoadEdge = net.edges[eid]
				if not e.open or e.mode() != mode:
					continue
				var other := e.other(cur)
				if not of.has(other):
					of[other] = comp_index
					stack.append(other)
		members.sort()
		list.append(members)
	return {"of": of, "list": list}


func _check_components(net: WorldNetwork, label: String) -> void:
	for mode in MODES:
		var ref := _ref_components(net, mode)
		var got := net.components(mode)
		assert_int(got.size()).override_failure_message("bileşen sayısı %s %s" % [mode, label]).is_equal(
				(ref["list"] as Array).size())
		for k in got.size():
			assert_bool(got[k] == (ref["list"] as Array)[k]).override_failure_message(
					"bileşen %d üyeleri %s %s" % [k, mode, label]).is_true()
		for nid: int in net.nodes:
			assert_int(net.component_of(nid, mode)).override_failure_message(
					"component_of(%d) %s %s" % [nid, mode, label]).is_equal(int((ref["of"] as Dictionary).get(nid, -1)))


func _check_rotations(net: WorldNetwork, label: String) -> void:
	var cache: NetworkRotationCache = net._hash_cache.rotations
	# Önce sorgu (geçersiz kılma sonucu), sonra tam doldurma ve tablo denetimi.
	for nid: int in net.nodes:
		var fresh := NetworkBlocks._rotation_of(net, nid)
		assert_bool(cache.rotation(net, nid) == fresh).override_failure_message(
				"dönüş sırası düğüm %d %s" % [nid, label]).is_true()
	assert_int(cache.rot.size()).override_failure_message("rot boyutu " + label).is_equal(net.nodes.size())
	var expected := 0
	for eid: int in net.edges:
		var e: WorldRoadEdge = net.edges[eid]
		if e.mode() == &"ferry":
			continue
		for dir in 2:
			var head := e.b if dir == 0 else e.a
			var around := NetworkBlocks._rotation_of(net, head)
			var k := around.find(eid)
			var next_eid := around[(k - 1 + around.size()) % around.size()]
			var next_edge: WorldRoadEdge = net.edges[next_eid]
			var want := next_eid * 2 + (0 if next_edge.a == head else 1)
			var h := eid * 2 + dir
			assert_int(int(cache._next.get(h, -1))).override_failure_message(
					"ardıl yarım kenar %d %s" % [h, label]).is_equal(want)
			var tail: Vector2 = net.node_pos(e.a if dir == 0 else e.b)
			var tip: Vector2 = net.node_pos(head)
			assert_float(float(cache._cross[h])).override_failure_message("çapraz %d %s" % [h, label]).is_equal(
					float(tail.x) * float(tip.y) - float(tip.x) * float(tail.y))
			expected += 1
	assert_int(cache._next.size()).override_failure_message("bayat ardıl kaydı " + label).is_equal(expected)
	assert_int(cache._cross.size()).override_failure_message("bayat çapraz kaydı " + label).is_equal(expected)


## Önbellekli extract_local, önbellek kapalıyken (taze hesap) aynı yüzleri verir.
func _check_walk(net: WorldNetwork, label: String) -> void:
	var seeds := PackedInt32Array()
	var ids: Array = net.edges.keys()
	ids.sort()
	for eid: int in ids:
		seeds.append(eid)
	var cached := NetworkBlocks.extract_local(net, seeds)
	var saved: NetworkHashCache = net._hash_cache
	net._hash_cache = null
	var fresh := NetworkBlocks.extract_local(net, seeds)
	net._hash_cache = saved
	assert_int(cached.size()).override_failure_message("yüz sayısı " + label).is_equal(fresh.size())
	for i in cached.size():
		for key: String in ["signature", "points", "edge_ids", "spurs", "area", "first_node"]:
			assert_bool(cached[i][key] == fresh[i][key]).override_failure_message(
					"yüz %d alan %s %s" % [i, key, label]).is_true()


func _check_all(net: WorldNetwork, label: String) -> void:
	_check_components(net, label)
	_check_rotations(net, label)
	_check_walk(net, label)


# ---------------------------------------------------------------- testler

func test_sealed_network_starts_warm_and_equal() -> void:
	var net := _net()
	assert_int((net._hash_cache.rotations as NetworkRotationCache).rot.size()).is_equal(net.nodes.size())
	_check_all(net, "taban")
	# Ayrık parçalar: yol (ızgara), yol (ayrık parça), ray: en az 2 yol + 1 ray bileşeni.
	assert_int(net.components(WorldNetwork.MODE_ROAD).size()).is_equal(2)
	assert_int(net.components(WorldNetwork.MODE_RAIL).size()).is_equal(1)


func test_scripted_sequence_matches_references() -> void:
	for extra: Dictionary in [{}, NetworkTestSupport.KEEP_PARCELS]:
		var net := _net(extra)
		var before_patched := NetworkComponents.patched
		var steps: Array = [
			[Vector2(580, 500), Vector2(580, 400)],          # çıkmaz sokak (yeni düğümler)
			[Vector2(660, 500), Vector2(660, 400), Vector2(820, 400), Vector2(820, 500)],  # halka
			[Vector2(580, 500), Vector2(580, 600)],          # kenar bölme
			[Vector2(980, 600), Vector2(1400, 500)],         # ayrık parçayı ızgaraya bağlar (bileşen birleşir)
		]
		for pts: Array in steps:
			assert_bool(net.add_road(PackedVector2Array(pts), LOCAL)["ok"]).is_true()
			_check_all(net, "yol %s" % str(pts))
		assert_int(net.components(WorldNetwork.MODE_ROAD).size()).is_equal(1)
		assert_bool(net.add_road(PackedVector2Array([Vector2(980, 1000), Vector2(980, 1100)]),
				WorldRoadEdge.CLASS_RAIL)["ok"]).is_true()
		_check_all(net, "ray")
		var spur: WorldRoadEdge = net.edges_near(580.0, 450.0, 3.0)[0]
		assert_bool(net.set_edge_open(spur.id, false)["ok"]).is_true()
		_check_all(net, "kapat")
		assert_bool(net.set_edge_open(spur.id, true)["ok"]).is_true()
		_check_all(net, "aç")
		assert_bool(net.remove_edge(spur.id)["ok"]).is_true()
		_check_all(net, "sil")
		var undone := 0
		while net.can_undo():
			assert_bool(net.undo_last_op()["ok"]).is_true()
			undone += 1
			_check_all(net, "geri al %d" % undone)
		assert_str(net.graph_hash()).is_equal(net.base_hash)
		assert_int(NetworkComponents.patched).override_failure_message("yama yolu hiç çalışmadı").is_greater(
				before_patched)


func test_seeded_random_sequences_match_references() -> void:
	var patched_before := NetworkComponents.patched
	for seed_value in [21, 22, 23, 24]:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		var net := _net()
		var classes: Array[StringName] = [LOCAL, WorldRoadEdge.CLASS_COLLECTOR, WorldRoadEdge.CLASS_RAIL, LOCAL]
		for step in 30:
			var pick := rng.randi_range(0, 9)
			if pick <= 4:
				var a := ORIGIN + Vector2(float(rng.randi_range(0, 14)) * 60.0, float(rng.randi_range(0, 9)) * 60.0)
				var b := a + Vector2(float(rng.randi_range(-4, 4)) * 40.0, float(rng.randi_range(-4, 4)) * 40.0)
				net.add_road(PackedVector2Array([a, b]), classes[rng.randi_range(0, 3)])
			elif pick <= 6:
				net.undo_last_op()
			elif pick == 7:
				var ids: Array = net.edges.keys()
				ids.sort()
				net.set_edge_open(ids[rng.randi_range(0, ids.size() - 1)], rng.randi_range(0, 1) == 1)
			else:
				var ids2: Array = net.edges.keys()
				ids2.sort()
				net.remove_edge(ids2[rng.randi_range(0, ids2.size() - 1)])
			_check_all(net, "tohum %d adım %d" % [seed_value, step])
	assert_int(NetworkComponents.patched).override_failure_message("yama yolu hiç çalışmadı").is_greater(patched_before)


func test_closing_a_bridge_edge_falls_back_to_full_rebuild_and_splits_the_component() -> void:
	# Olumsuz durum: köprü kenar kapanınca bileşen ikiye bölünür; yama bunu bilemez, tam hesaba düşmeli.
	var net := _net()
	assert_bool(net.add_road(PackedVector2Array([Vector2(980, 600), Vector2(1400, 500)]), LOCAL)["ok"]).is_true()
	assert_int(net.components(WorldNetwork.MODE_ROAD).size()).is_equal(1)
	var bridge: WorldRoadEdge = net.edges_near(1190.0, 550.0, 20.0)[0]
	var rebuilt_before := NetworkComponents.rebuilt
	assert_bool(net.set_edge_open(bridge.id, false)["ok"]).is_true()
	assert_int(net.components(WorldNetwork.MODE_ROAD).size()).is_equal(2)
	assert_int(NetworkComponents.rebuilt).is_greater(rebuilt_before)
	_check_all(net, "köprü kapalı")


func test_light_ismeral_network_sequences_match_references() -> void:
	var net := NetworkTestSupport.fresh_light()
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var ids: Array = net.edges.keys()
	ids.sort()
	_check_components(net, "taban")
	for step in 8:
		var e: WorldRoadEdge = net.edges[ids[rng.randi() % ids.size()]]
		var a := net.node_pos(e.a).lerp(net.node_pos(e.b), rng.randf())
		var b := a + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(60.0, 200.0)
		net.add_road(PackedVector2Array([a, b]), LOCAL)
		_check_components(net, "adım %d" % step)
		_check_walk(net, "adım %d" % step)
		if step % 3 == 2:
			net.undo_last_op()
			_check_components(net, "geri al %d" % step)
			_check_walk(net, "geri al %d" % step)


# ---------------------------------------------------------------- geri alma (T-051)

## Ardışık yol işlemleri: çıkmaz sokak, halka, kenar bölme, ayrık parçayı bağlama (geri alınca bileşen İKİYE bölünür).
func _undo_steps() -> Array:
	return [
		[Vector2(580, 500), Vector2(580, 400)],
		[Vector2(660, 500), Vector2(660, 400), Vector2(820, 400), Vector2(820, 500)],
		[Vector2(580, 500), Vector2(580, 600)],
		[Vector2(980, 600), Vector2(1400, 500)],
	]


func test_undo_restores_the_component_cache_without_a_full_rebuild() -> void:
	for query_between in [true, false]:
		var net := _net()
		_check_components(net, "taban")
		for pts: Array in _undo_steps():
			assert_bool(net.add_road(PackedVector2Array(pts), LOCAL)["ok"]).is_true()
			if query_between:
				_check_components(net, "yol %s" % str(pts))
		assert_int(net.components(WorldNetwork.MODE_ROAD).size()).is_equal(1)  # ayrık parça bağlandı
		var rebuilt_before := NetworkComponents.rebuilt
		var restored_before := NetworkComponents.restored
		var undone := 0
		while net.can_undo():
			assert_bool(net.undo_last_op()["ok"]).is_true()
			undone += 1
			_check_components(net, "geri al %d (arada sorgu %s)" % [undone, str(query_between)])
		assert_int(undone).is_equal(_undo_steps().size())
		assert_int(NetworkComponents.rebuilt).override_failure_message("geri alma tam hesaba düştü").is_equal(
				rebuilt_before)
		assert_int(NetworkComponents.restored - restored_before).is_equal(undone)
		assert_int(net.components(WorldNetwork.MODE_ROAD).size()).is_equal(2)  # köprü geri alınınca bölündü
		assert_str(net.graph_hash()).is_equal(net.base_hash)


func test_undo_of_open_close_and_remove_edge_restores_the_cache() -> void:
	var net := _net()
	assert_bool(net.add_road(PackedVector2Array([Vector2(980, 600), Vector2(1400, 500)]), LOCAL)["ok"]).is_true()
	_check_components(net, "bağlı")
	var bridge: WorldRoadEdge = net.edges_near(1190.0, 550.0, 20.0)[0]
	var spur_ids: Array = net.edges.keys()
	spur_ids.sort()
	assert_bool(net.set_edge_open(bridge.id, false)["ok"]).is_true()
	_check_components(net, "köprü kapalı")  # bileşen bölündü (tam hesap)
	assert_bool(net.remove_edge(int(spur_ids[3]))["ok"]).is_true()
	_check_components(net, "kenar silindi")
	var rebuilt_before := NetworkComponents.rebuilt
	var restored_before := NetworkComponents.restored
	assert_bool(net.undo_last_op()["ok"]).is_true()
	_check_components(net, "silme geri alındı")
	assert_bool(net.undo_last_op()["ok"]).is_true()
	_check_components(net, "kapatma geri alındı")
	assert_int(net.components(WorldNetwork.MODE_ROAD).size()).is_equal(1)
	assert_int(NetworkComponents.rebuilt).override_failure_message("geri alma tam hesaba düştü").is_equal(rebuilt_before)
	assert_int(NetworkComponents.restored - restored_before).is_equal(2)


func test_undo_deeper_than_the_snapshot_window_falls_back_but_stays_equal() -> void:
	var net := _net()
	_check_components(net, "taban")
	var count := NetworkComponents.UNDO_SNAPSHOTS + 4
	for k in count:
		var x := 540.0 + float(k) * 30.0
		assert_bool(net.add_road(PackedVector2Array([Vector2(x, 500), Vector2(x, 420)]), LOCAL)["ok"]).is_true()
		_check_components(net, "yol %d" % k)
	var restored_before := NetworkComponents.restored
	var undone := 0
	while net.can_undo():
		assert_bool(net.undo_last_op()["ok"]).is_true()
		undone += 1
		_check_components(net, "derin geri al %d" % undone)
	assert_int(undone).is_equal(count)
	# Yalnız son UNDO_SNAPSHOTS işlem kopyadan döner; daha eskiler tam hesapla (doğru ama yavaş).
	assert_int(NetworkComponents.restored - restored_before).is_equal(NetworkComponents.UNDO_SNAPSHOTS)
	assert_str(net.graph_hash()).is_equal(net.base_hash)


func test_redo_after_undo_gives_the_same_components_as_the_first_time() -> void:
	var net := _net()
	var pts := PackedVector2Array([Vector2(980, 600), Vector2(1400, 500)])
	assert_bool(net.add_road(pts, LOCAL)["ok"]).is_true()
	var first := net.components(WorldNetwork.MODE_ROAD).duplicate(true)
	assert_bool(net.undo_last_op()["ok"]).is_true()
	assert_bool(net.add_road(pts, LOCAL)["ok"]).is_true()
	var again := net.components(WorldNetwork.MODE_ROAD)
	assert_int(again.size()).is_equal(first.size())
	for k in first.size():
		assert_bool(again[k] == first[k]).is_true()
	_check_components(net, "yeniden çizim")
