extends GdUnitTestSuite
## Yol yıkımı parsel KİMLİĞİNİ korur (öneri 2026-11-01-parsel-kimligi-koruyan-yol-yikimi; CAN-04, D-014 §1, WLD-01,
## TEK-01/02, T-042b seçenek A: sim parsel kümesi sabit). Kamulaştırmalı yolun kenarları silinince birleşen blok
## BAŞTAN parsellenmez: kalan parseller aynı NESNE (kimlik, çokgen, `owner_id`) olarak yeni bloğa taşınır; alınmış
## parseller geri DÖNMEZ; yeni parsel doğmaz (`added_parcels` boş, parsel kimlik sayacı ilerlemez). Yerel == tam
## yenileme; geri alma zinciri tabana bit-eşit döner; yeniden oynatma bit-eşit. Anahtar kapalı dünyada (keep_parcels
## yok) eski davranış (yeniden parselleme) sürer; `DemolitionPlan` bunu güvenlik ağıyla reddeder.

const DX := 160.0
const DZ := 100.0
const COLS := 3
const ROWS := 3
const ORIGIN := Vector2(500.0, 500.0)
const LOCAL := WorldRoadEdge.CLASS_LOCAL
const SEEDS := 300
const THROUGH: Array = [Vector2(580, 500), Vector2(580, 600)]
const DIAGONAL: Array = [Vector2(500, 500), Vector2(660, 600)]
const SPUR: Array = [Vector2(580, 500), Vector2(580, 560)]

var _world: WorldData


func before() -> void:
	_world = NetworkTestSupport.flat_world(3000.0)


func _grid(local_refresh: bool = true, keep: bool = true) -> WorldNetwork:
	var net := NetworkTestSupport.grid_network(_world, COLS, ROWS, DX, DZ, ORIGIN, 7,
			NetworkTestSupport.KEEP_PARCELS if keep else {})
	net.local_refresh_enabled = local_refresh
	for pid: int in net.parcels:  # mülkiyet yuvası: kalan parsellerin sahibi korunmalı
		(net.parcels[pid] as WorldParcel).owner_id = pid * 3 + 1
	return net


func _expropriate(net: WorldNetwork, pts: Array) -> Dictionary:
	return net.add_road_expropriating(PackedVector2Array(pts), LOCAL)


func _delta_edge_ids(net: WorldNetwork) -> Array[int]:
	var out: Array[int] = []
	for id: int in net.edges:
		if (net.edges[id] as WorldRoadEdge).layer == WorldRoadEdge.LAYER_DELTA:
			out.append(id)
	out.sort()
	return out


## Parsel kimliği -> [nesne, çokgen, sahip]; yıkımdan önce/sonra aynı olmalı.
func _snapshot(net: WorldNetwork) -> Dictionary:
	var out := {}
	for pid: int in net.parcels:
		var p: WorldParcel = net.parcels[pid]
		out[pid] = [p, p.outline.duplicate(), p.owner_id]
	return out


## Blok/parsel yapısından kimlikten bağımsız özet (yerel == tam yenileme karşılaştırması). Blok kimliği YOK; parsel
## kimlikleri VAR (kimlik korunur).
func _canonical(net: WorldNetwork) -> String:
	var rows: Array[String] = []
	for pid: int in net.parcels:
		var p: WorldParcel = net.parcels[pid]
		var block: WorldBlock = net.blocks[p.block_id]
		var front: WorldRoadEdge = net.edges[p.frontage_edge]
		rows.append("%d|%d|%s|%.2f,%.2f|%.2f,%.2f" % [pid, p.owner_id, block.signature, net.node_pos(front.a).x,
				net.node_pos(front.a).y, net.node_pos(front.b).x, net.node_pos(front.b).y])
	rows.sort()
	var blocks: Array[String] = []
	for b: WorldBlock in net.blocks.values():
		blocks.append("%s|%s|%d" % [b.signature, String(b.kind), b.parcel_ids.size()])
	blocks.sort()
	return "%s#%s#%s" % [net.graph_hash(), "\n".join(rows).md5_text(), "\n".join(blocks).md5_text()]


## Bir yolu kenar kenar yıkar; her adımda parsel değişmezlerini denetler. Dönüş: {"problems", "removed_edges"}.
func _demolish(net: WorldNetwork, before: Dictionary, tag: String) -> Dictionary:
	var problems := PackedStringArray()
	var removed := 0
	var parcel_counter: int = NetworkRestore.counters(net)["parcel"]
	for guard in 64:
		var ids := _delta_edge_ids(net)
		if ids.is_empty():
			break
		var report := net.remove_edge(ids[0])
		if not bool(report["ok"]):
			problems.append("%s: kenar %d silinemedi (%s)" % [tag, ids[0], report["error"]])
			break
		removed += 1
		if not (report["added_parcels"] as Array).is_empty() or not (report["removed_parcels"] as Array).is_empty():
			problems.append("%s: yıkım parseli değiştirdi +%s -%s" % [tag, report["added_parcels"],
					report["removed_parcels"]])
		for pid: int in net.parcels:
			if not before.has(pid):
				problems.append("%s: yeni parsel kimliği %d" % [tag, pid])
			elif net.parcels[pid] != (before[pid] as Array)[0] \
					or (net.parcels[pid] as WorldParcel).owner_id != (before[pid] as Array)[2]:
				problems.append("%s: parsel %d değişti" % [tag, pid])
		for pid: int in before:
			if not net.parcels.has(pid):
				problems.append("%s: parsel %d kayboldu" % [tag, pid])
	if NetworkRestore.counters(net)["parcel"] != parcel_counter:
		problems.append("%s: parsel kimlik sayacı ilerledi" % tag)
	for p in NetworkInvariants.check_parcels(net):
		problems.append("%s: %s" % [tag, p])
	for p in NetworkInvariants.check_graph_integrity(net):
		problems.append("%s: %s" % [tag, p])
	return {"problems": problems, "removed_edges": removed}


func test_demolishing_a_road_through_a_block_keeps_every_remaining_parcel_as_the_same_object() -> void:
	var net := _grid()
	var graph := net.graph_hash()
	var added := _expropriate(net, THROUGH)
	assert_bool(added["ok"]).override_failure_message(str(added["error"])).is_true()
	var taken: Array = added["removed_parcels"]
	assert_int(taken.size()).is_greater(0)
	var after_road := _snapshot(net)
	var res := _demolish(net, after_road, "through")
	assert_array(res["problems"]).is_empty()
	assert_int(res["removed_edges"]).is_greater(0)
	assert_str(net.graph_hash()).is_equal(graph)  # taban grafı geri geldi
	assert_array(net.parcels.keys()).contains_exactly_in_any_order(after_road.keys())
	for pid in taken:  # alınan parsel dünyaya geri DÖNMEZ
		assert_bool(net.parcels.has(pid)).is_false()
	for b: WorldBlock in net.blocks.values():  # birleşen blok parselli blok olarak kaldı
		assert_bool(b.kind == WorldBlock.KIND_PARCELIZED or b.kind == WorldBlock.KIND_OPEN).is_true()


func test_demolition_is_reversible_to_the_exact_base_state_and_replays_bit_equal() -> void:
	var net := _grid()
	var base_state := net.state_hash()
	var base_parcels := net.parcels.size()
	assert_bool(_expropriate(net, DIAGONAL)["ok"]).is_true()
	var state_road := net.state_hash()
	var after_road := _snapshot(net)
	var res := _demolish(net, after_road, "diagonal")
	assert_array(res["problems"]).is_empty()
	var state_demolished := net.state_hash()
	var replayed := _grid()  # kayıt = taban + delta: aynı durum (blok/parsel kimlikleri dahil)
	var applied := replayed.apply_delta(NetworkDelta.from_dict(JSON.parse_string(JSON.stringify(net.delta.to_dict()))))
	assert_bool(applied["ok"]).override_failure_message(str(applied)).is_true()
	assert_str(replayed.state_hash()).is_equal(state_demolished)
	for _i in res["removed_edges"]:  # yıkımı geri al: yol sonrası durum bit-eşit
		assert_bool(net.undo_last_op()["ok"]).is_true()
	assert_str(net.state_hash()).is_equal(state_road)
	assert_bool(net.undo_last_op()["ok"]).is_true()  # yolu geri al: taban bit-eşit, alınanlar geri
	assert_str(net.state_hash()).is_equal(base_state)
	assert_int(net.parcels.size()).is_equal(base_parcels)


func test_local_and_full_refresh_agree_on_a_demolition() -> void:
	var local := _grid(true)
	var full := _grid(false)
	for pts: Array in [THROUGH, SPUR]:
		assert_bool(_expropriate(local, pts)["ok"]).is_true()
		assert_bool(_expropriate(full, pts)["ok"]).is_true()
	assert_str(_canonical(local)).is_equal(_canonical(full))
	var snap_local := _snapshot(local)
	var snap_full := _snapshot(full)
	assert_array(_demolish(local, snap_local, "local")["problems"]).is_empty()
	assert_array(_demolish(full, snap_full, "full")["problems"]).is_empty()
	assert_str(_canonical(local)).is_equal(_canonical(full))
	assert_str(local.state_hash()).is_equal(full.state_hash())


func test_without_keep_parcels_a_demolition_still_reparcels_so_the_plan_safety_net_applies() -> void:
	var net := _grid(true, false)  # anahtar kapalı dünya: yol parselleri yeniden üretir (eski davranış)
	var drawn := net.add_road(PackedVector2Array(THROUGH), LOCAL)
	assert_bool(drawn["ok"]).is_true()
	var op := net.peek_last_op()
	var run := DemolitionPlan.run(net, op, false)
	assert_bool(run["ok"]).is_false()  # güvenlik ağı: sim parsel kümesini değiştirecek yıkım reddedilir
	assert_bool(int(run["added_parcels"]) > 0 or int(run["removed_parcels"]) > 0).is_true()
	assert_int(DemolitionPlan.rollback(net, run["ops"])).is_equal(0)


func test_random_expropriating_roads_demolish_without_touching_the_parcel_set() -> void:
	var failures := PackedStringArray()
	var demolished := 0
	var through := 0
	var open_rules := RoadDraftRules.new()
	open_rules.crossing_parcels = RoadDraftRules.CROSSING_ALLOW
	for s in SEEDS:
		var rng := RandomNumberGenerator.new()
		rng.seed = 7000 + s
		var net := _grid(true)
		var pts := _random_road(rng)
		var checked := RoadDraftCheck.check(net, PackedVector2Array(pts), LOCAL, open_rules)
		if not bool(checked["ok"]):
			continue
		var base_state := net.state_hash()
		var blocks_before := net.blocks.size()
		var report := net.add_road_expropriating(checked["points"], LOCAL)
		if not bool(report["ok"]):
			continue
		if net.blocks.size() > blocks_before:
			through += 1
		var tag := "tohum %d %s" % [s, str(pts)]
		var res := _demolish(net, _snapshot(net), tag)
		failures.append_array(res["problems"])
		for _i in res["removed_edges"] + 1:
			if not bool(net.undo_last_op()["ok"]):
				failures.append("%s: geri alma başarısız" % tag)
		if net.state_hash() != base_state:
			failures.append("%s: geri alma tabana bit-eşit dönmedi" % tag)
		demolished += 1
	print("DEMOLITION_PROPERTY demolished=%d through=%d failures=%d" % [demolished, through, failures.size()])
	assert_int(demolished).is_greater(SEEDS / 4)
	assert_int(through).is_greater(5)
	assert_array(failures).is_empty()


func _random_road(rng: RandomNumberGenerator) -> Array:
	var pts: Array = [_on_road(rng)]
	if rng.randf() < 0.3:
		pts.append(ORIGIN + Vector2(rng.randf() * COLS * DX, rng.randf() * ROWS * DZ))
	pts.append(_on_road(rng) if rng.randf() < 0.6 else ORIGIN + Vector2(rng.randf() * COLS * DX, rng.randf() * ROWS * DZ))
	return pts


func _on_road(rng: RandomNumberGenerator) -> Vector2:
	if rng.randf() < 0.5:
		return ORIGIN + Vector2(rng.randf() * COLS * DX, float(rng.randi() % (ROWS + 1)) * DZ)
	return ORIGIN + Vector2(float(rng.randi() % (COLS + 1)) * DX, rng.randf() * ROWS * DZ)
