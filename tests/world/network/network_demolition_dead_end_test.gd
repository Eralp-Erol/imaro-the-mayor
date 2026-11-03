extends GdUnitTestSuite
## Çok parçalı çıkmaz yolun yıkımı (ADR-0005 Ek J takip a, d; CAN-04, D-014 §1, T-042b seçenek A). Ek J'nin KOD
## OKUMASI hipotezi: ağa bağlı uçtan çizilmiş iki+ kenarlı çıkmaz yolda `DemolitionPlan.next_edge` en küçük kimlikli
## (ağa BAĞLI) kenarı önce silince kuyruk ada kalır, yüz `holed` olur, parseller düşer ve yıkım yanıltıcı
## `demolition_changes_parcels` ile reddedilir. ÖLÇÜM (2026-11-01): bu test dosyasındaki ön koşulla (en küçük kimlikli
## kenar yaprak DEĞİL) ve rastgele çıkmaz yollarla (iki çizim yönü; tek seferlik 3.646 deneme + aşağıdaki 424) hipotez
## ÜRETİLEMEDİ: ada kalan yüz, imzası ve köşe anahtarı aynı kaldığı için eski bloğa eşlenir (`kind` korunur, parseller
## yerinde) ve yıkım temiz biter. Bu testler o davranışın KORUMASIDIR (kırmızı değil; yeşil kalmalı).
## `DemolitionPlan.next_edge` bu yüzden DEĞİŞMEDİ.
## B-016 (2026-11-03): kendini kesip halka kapatan taslakta ara yıkımın kopuk halkası dış yüzü delikli yapar.
## Havuzdaki dış parseller artık korunur; halka içi dış yüze taşınmaz. Sabit vakalar + rastgele tarama bunu kapsar.
## Ayrıca (d, B-015): yıkılan yolun boş şeridine aynı yolu yeniden çizmenin dünya tarafı (havuzlu, sıfır alınan).

const DX := 160.0
const DZ := 100.0
const ORIGIN := Vector2(500.0, 500.0)
const LOCAL := WorldRoadEdge.CLASS_LOCAL
const SEEDS := 250
## Kuzey yoldan (y=500) bloğun içine giren, dirsekli iki parçalı çıkmaz; yön ve ucun bağlı/boşta olması aşağıda.
const FROM_NETWORK: Array = [Vector2(580, 500), Vector2(580, 545), Vector2(615, 575)]
const FROM_FREE_END: Array = [Vector2(615, 575), Vector2(580, 545), Vector2(580, 500)]
## Dört noktalı (üç kenarlı) çıkmaz; ilk noktası batı yolunda.
const LONG_SPUR: Array = [Vector2(500, 560), Vector2(540, 560), Vector2(570, 585), Vector2(600, 585)]
## İki ucundan ağa bağlı geçiş yolu (yaprağı yok: eski sıra, en küçük kimlik, korunur).
const THROUGH: Array = [Vector2(580, 500), Vector2(580, 600)]
## B-016: sabit tohum taramasından kaydedilen kendini kesen halkalar (9103, 9122).
const LOOPS: Array = [
	[Vector2(915.28, 600), Vector2(839.30, 571.47), Vector2(953.83, 567.67), Vector2(852.44, 583.52)],
	[Vector2(820, 564.02), Vector2(752.38, 516.70), Vector2(800.54, 516.19), Vector2(708.54, 558.27)],
	[Vector2(520, 500), Vector2(520, 590), Vector2(650, 515), Vector2(505, 515)]]

var _world: WorldData


func before() -> void:
	_world = NetworkTestSupport.flat_world(3000.0)


func _grid() -> WorldNetwork:
	var net := NetworkTestSupport.grid_network(_world, 3, 3, DX, DZ, ORIGIN, 7, NetworkTestSupport.KEEP_PARCELS)
	net.local_refresh_enabled = true
	return net


func _delta_edge_ids(net: WorldNetwork) -> Array[int]:
	var out: Array[int] = []
	for id: int in net.edges:
		if (net.edges[id] as WorldRoadEdge).layer == WorldRoadEdge.LAYER_DELTA:
			out.append(id)
	out.sort()
	return out


## Kenarın iki ucundan biri derece 1 mi (yaprak)?
func _is_leaf(net: WorldNetwork, id: int) -> bool:
	var e: WorldRoadEdge = net.edges[id]
	return (net.adjacency[e.a] as PackedInt32Array).size() == 1 or (net.adjacency[e.b] as PackedInt32Array).size() == 1


## Yolu kamulaştırarak çizer, yıkım planını çalıştırır; ön koşulu (en az iki kenar; istenirse EN KÜÇÜK kimlikli kenar
## yaprak DEĞİL) denetler. Dönüş: ağ, plan sonucu ve taban özetleri.
func _draw_and_demolish(pts: Array, smallest_id_must_be_connected: bool) -> Dictionary:
	var net := _grid()
	var base_graph := net.graph_hash()
	var base_state := net.state_hash()
	var base_parcels := net.parcels.keys()
	var drawn := net.add_road_expropriating(PackedVector2Array(pts), LOCAL)
	assert_bool(drawn["ok"]).override_failure_message(str(drawn["error"])).is_true()
	var ids := _delta_edge_ids(net)
	assert_int(ids.size()).is_greater(1)
	if smallest_id_must_be_connected:
		assert_bool(_is_leaf(net, ids[0])).override_failure_message("ön koşul: en küçük kimlik ağa bağlı").is_false()
	var run := DemolitionPlan.run(net, net.peek_last_op(), true)
	return {"net": net, "run": run, "ids": ids, "base_graph": base_graph, "base_state": base_state,
			"base_parcels": base_parcels, "taken": drawn["removed_parcels"]}


func _assert_clean_demolition(res: Dictionary) -> void:
	var net: WorldNetwork = res["net"]
	var run: Dictionary = res["run"]
	assert_bool(run["ok"]).override_failure_message(str(run["error"])).is_true()
	assert_int(run["added_parcels"]).is_equal(0)
	assert_int(run["removed_parcels"]).is_equal(0)
	assert_array(_delta_edge_ids(net)).is_empty()  # düğüm temizliği iki kenarı birleştirebilir; op sayısı şart değil
	assert_str(net.graph_hash()).is_equal(res["base_graph"])  # taban grafı geri geldi, ada yok
	assert_array(NetworkInvariants.check_graph_integrity(net)).is_empty()
	assert_array(NetworkInvariants.check_parcels(net)).is_empty()
	for pid in res["taken"]:  # alınan parsel dünyaya geri DÖNMEZ
		assert_bool(net.parcels.has(pid)).is_false()
	for pid: int in net.parcels:  # yeni parsel kimliği yok
		assert_bool((res["base_parcels"] as Array).has(pid)).is_true()
	assert_int(DemolitionPlan.rollback(net, run["ops"])).is_equal(0)  # yıkımı ve çizimi geri al: tabana bit-eşit
	assert_bool(net.undo_last_op()["ok"]).is_true()
	assert_str(net.state_hash()).is_equal(res["base_state"])


func test_two_edge_dead_end_drawn_from_the_connected_end_demolishes_cleanly() -> void:
	var res := _draw_and_demolish(FROM_NETWORK, true)
	assert_int((res["taken"] as Array).size()).is_greater(0)  # gerçekten kamulaştırmalı yol
	_assert_clean_demolition(res)


func test_two_edge_dead_end_drawn_from_the_free_end_demolishes_cleanly() -> void:
	_assert_clean_demolition(_draw_and_demolish(FROM_FREE_END, false))


func test_three_edge_dead_end_attached_at_its_first_point_demolishes_cleanly() -> void:
	_assert_clean_demolition(_draw_and_demolish(LONG_SPUR, true))


func test_self_crossing_loops_demolish_in_both_directions_and_refresh_modes() -> void:
	for points: Array in LOOPS:
		for reversed in [false, true]:
			for local in [false, true]:
				var pts := points.duplicate()
				if reversed:
					pts.reverse()
				var net := _grid()
				net.local_refresh_enabled = local
				var base_state := net.state_hash()
				var base_graph := net.graph_hash()
				var base_parcels := net.parcels.keys()
				var drawn := net.add_road_expropriating(PackedVector2Array(pts), LOCAL)
				assert_bool(drawn["ok"]).is_true()
				var ids := _delta_edge_ids(net)
				var run := DemolitionPlan.run(net, net.peek_last_op(), true)
				_assert_loop_replay(net, local)
				_assert_clean_demolition({"net": net, "run": run, "ids": ids, "base_state": base_state,
					"base_graph": base_graph, "base_parcels": base_parcels, "taken": drawn["removed_parcels"]})


## Her kayıt adımı tekrar oynatılır: kopuk halkanın iç parsellerini dış yüz sahiplenemez.
func _assert_loop_replay(net: WorldNetwork, local: bool) -> void:
	var replay := _grid()
	replay.local_refresh_enabled = local
	for op in net.delta.ops:
		var delta := NetworkDelta.new()
		delta.base_hash = replay.base_hash
		delta.ops.append(op.duplicate(true))
		assert_bool(replay.apply_delta(delta)["ok"]).is_true()
		assert_array(NetworkInvariants.check_parcels(replay)).is_empty()
		for pid: int in replay.parcels:
			var parcel: WorldParcel = replay.parcels[pid]
			var owner: WorldBlock = replay.blocks[parcel.block_id]
			for bid: int in replay.blocks:
				var other: WorldBlock = replay.blocks[bid]
				if NetworkGeometry.signed_area(other.outline) < NetworkGeometry.signed_area(owner.outline) - 0.01:
					assert_bool(NetworkGeometry.point_in_polygon(parcel.centroid, other.outline)) \
						.override_failure_message("iç yüzün parseli dış bloğa taşındı: %d" % pid).is_false()
	assert_str(replay.state_hash()).is_equal(net.state_hash())


func test_through_road_without_leaves_keeps_the_smallest_id_first_order() -> void:
	var net := _grid()
	assert_bool(net.add_road_expropriating(PackedVector2Array(THROUGH), LOCAL)["ok"]).is_true()
	var ids := _delta_edge_ids(net)
	assert_bool(_is_leaf(net, ids[0])).is_false()
	assert_int(DemolitionPlan.next_edge(net, PackedVector2Array(THROUGH), LOCAL)).is_equal(ids[0])


## Rastgele çıkmaz yol: bir blok seçilir, ilk nokta o bloğun çevresindeki yolda, kalanlar bloğun İÇİNDE (kenardan >= 12
## m); B-016 koruması için kendini kesebilir. Dönüş: nokta listesi ([] = üretilemedi).
func _random_dead_end(rng: RandomNumberGenerator) -> Array:
	var col := rng.randi() % 3
	var row := rng.randi() % 3
	var x0 := ORIGIN.x + col * DX
	var y0 := ORIGIN.y + row * DZ
	var start := Vector2.ZERO
	match rng.randi() % 4:
		0:
			start = Vector2(x0 + rng.randf_range(20.0, DX - 20.0), y0)
		1:
			start = Vector2(x0 + rng.randf_range(20.0, DX - 20.0), y0 + DZ)
		2:
			start = Vector2(x0, y0 + rng.randf_range(15.0, DZ - 15.0))
		_:
			start = Vector2(x0 + DX, y0 + rng.randf_range(15.0, DZ - 15.0))
	var pts: Array = [start]
	for _i in 2 + rng.randi() % 2:
		pts.append(Vector2(x0 + rng.randf_range(12.0, DX - 12.0), y0 + rng.randf_range(12.0, DZ - 12.0)))
	for i in pts.size() - 1:  # çok kısa parça yok
		if (pts[i] as Vector2).distance_to(pts[i + 1]) < 12.0:
			return []
	return pts


func test_random_dead_ends_demolish_without_touching_the_parcel_set_in_both_draw_directions() -> void:
	var open_rules := RoadDraftRules.new()
	open_rules.crossing_parcels = RoadDraftRules.CROSSING_ALLOW
	var failures := PackedStringArray()
	var tried := 0
	var leaf_not_first := 0
	var looped := 0
	for s in SEEDS:
		var rng := RandomNumberGenerator.new()
		rng.seed = 9100 + s
		var pts := _random_dead_end(rng)
		if pts.is_empty():
			continue
		for reversed in [false, true]:
			var drawn_pts: Array = pts.duplicate()
			if reversed:
				drawn_pts.reverse()
			var net := _grid()
			var checked := RoadDraftCheck.check(net, PackedVector2Array(drawn_pts), LOCAL, open_rules)
			if not bool(checked["ok"]):
				continue
			var base_state := net.state_hash()
			if not bool(net.add_road_expropriating(checked["points"], LOCAL)["ok"]):
				continue
			var ids := _delta_edge_ids(net)
			if ids.size() < 2:
				continue  # halkalı ve blok bölen taslaklar da sınanır (B-016)
			tried += 1
			if drawn_pts.size() == 4 and Geometry2D.segment_intersects_segment(
					drawn_pts[0], drawn_pts[1], drawn_pts[2], drawn_pts[3]) != null:
				looped += 1
			if not _is_leaf(net, ids[0]):
				leaf_not_first += 1
			var run := DemolitionPlan.run(net, net.peek_last_op(), false)
			var tag := "tohum %d ters=%s %s" % [s, reversed, str(drawn_pts)]
			if not bool(run["ok"]):
				failures.append("%s: %s +%d -%d" % [tag, run["error"], run["added_parcels"], run["removed_parcels"]])
				continue
			DemolitionPlan.rollback(net, run["ops"])
			net.undo_last_op()
			if net.state_hash() != base_state:
				failures.append("%s: geri alma tabana bit-eşit dönmedi" % tag)
	print("DEAD_END_PROPERTY tried=%d connected_edge_first=%d looped=%d failures=%d" %
			[tried, leaf_not_first, looped, failures.size()])
	assert_int(tried).is_greater(SEEDS / 2)
	assert_int(looped).is_greater(0)
	assert_int(leaf_not_first).is_greater(tried / 4)  # sıra riski gerçekten sınanıyor (çizim yönü karışık)
	assert_array(failures).is_empty()


## Yıkılan kamulaştırmalı yolun boş şeridini döndürür: [ağ, şerit]. Şerit gerçekten boştur (`taken_parcels` = 0).
func _freed_strip() -> Array:
	var net := _grid()
	var strip := PackedVector2Array(THROUGH)
	var drawn := net.add_road_expropriating(strip, LOCAL)
	assert_bool(drawn["ok"]).is_true()
	assert_int((drawn["removed_parcels"] as Array).size()).is_greater(0)
	var run := DemolitionPlan.run(net, net.peek_last_op(), false)
	assert_bool(run["ok"]).is_true()
	assert_int(NetworkExpropriation.taken_parcels(net, strip, net.rules.width_of(LOCAL)).size()).is_equal(0)
	return [net, strip]


## (d) B-015 (ADR-0005 Ek J takip d): yıkılan kamulaştırmalı yolun boş şeridine aynı yol yeniden çizilir. Alınan
## parsel yok, ama birleşen blok parselli olduğu için DÜZ denetim `crosses_parcels` verir (doğru: düz `add_road`
## havuzsuz). Sim akışı bu durumda yolu HAVUZLU (sıfır alınan) kurar: kimlikler ve nesneler korunur, yeni numara
## harcanmaz, geri alma bit-eşit.
func test_redrawing_over_a_freed_strip_builds_pooled_with_zero_taken_and_keeps_every_parcel() -> void:
	var freed := _freed_strip()
	var net: WorldNetwork = freed[0]
	var strip: PackedVector2Array = freed[1]
	var allow := RoadDraftRules.new()
	allow.crossing_parcels = RoadDraftRules.CROSSING_ALLOW
	assert_bool(RoadDraftCheck.check(net, strip, LOCAL, allow)["ok"]).is_true()
	var plain := RoadDraftCheck.check(net, strip, LOCAL, RoadDraftRules.new())
	assert_str(String(plain["reason"])).is_equal(String(RoadDraftCheck.REASON_CROSSES_PARCELS))
	var parcels := net.parcels.duplicate()
	var counter: int = NetworkRestore.counters(net)["parcel"]
	var state_before := net.state_hash()
	var redraw := net.add_road_expropriating(strip, LOCAL)
	assert_bool(redraw["ok"]).override_failure_message(str(redraw["error"])).is_true()
	assert_int((redraw["added_parcels"] as Array).size()).is_equal(0)
	assert_int((redraw["removed_parcels"] as Array).size()).is_equal(0)
	assert_array(net.parcels.keys()).contains_exactly_in_any_order(parcels.keys())
	for pid: int in parcels:
		assert_object(net.parcels[pid]).is_same(parcels[pid])
	assert_int(NetworkRestore.counters(net)["parcel"]).is_equal(counter)
	assert_array(NetworkInvariants.check_graph_integrity(net)).is_empty()
	assert_array(NetworkInvariants.check_parcels(net)).is_empty()
	assert_bool(net.undo_last_op()["ok"]).is_true()
	assert_str(net.state_hash()).is_equal(state_before)


## Kök neden kanıtı: AYNI şeride düz `add_road` (havuzsuz) bloğu baştan parseller; parsel kümesi değişir. Bu yüzden düz
## yol havuzlanmaz, havuzlu kurma yalnız kamulaştırma onayıyla (sıfır alınan da dahil) yapılır.
func test_plain_add_road_over_a_freed_strip_changes_the_parcel_set_which_is_why_it_is_not_pooled() -> void:
	var freed := _freed_strip()
	var net: WorldNetwork = freed[0]
	var before := net.parcels.keys()
	var plain := net.add_road(freed[1], LOCAL)
	assert_bool(plain["ok"]).is_true()
	var changed := not (plain["added_parcels"] as Array).is_empty() \
			or not (plain["removed_parcels"] as Array).is_empty() or net.parcels.keys() != before
	assert_bool(changed).override_failure_message("düz yol parsel kümesini değiştirmedi").is_true()
