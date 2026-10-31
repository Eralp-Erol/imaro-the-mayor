extends GdUnitTestSuite
## T-042b dünya adımı · Kamulaştırmalı yol (plan §1 seçenek A, §3, §4 adım 1; CAN-04, D-009, D-011, WLD-01, TEK-01/02).
## Değişmezler: `added_parcels` boş, `removed_parcels` == `RoadDraftCheck.taken_parcels`; alınmayan parsellerin kimlik +
## çokgen
## + `owner_id`si aynı (aynı NESNE); geri al -> tüm durum (blok/parsel kimlikleri dahil) bit-eşit; yerel == tam
## yenileme;
## yeniden oynatma bit-eşit; artımlı graf özeti ve türev önbellekler tam hesapla aynı; kamulaştırma kapalıyken davranış
## aynı.

const PURE_SOURCES: Array[String] = [
	"res://src/world/network/network_expropriation.gd", "res://src/world/network/network_expropriation_port.gd",
]
const DX := 160.0
const DZ := 100.0
const COLS := 3
const ROWS := 3
const ORIGIN := Vector2(500.0, 500.0)
const LOCAL := WorldRoadEdge.CLASS_LOCAL
const SEEDS := 500
const THROUGH: Array = [Vector2(580, 500), Vector2(580, 600)]
const SPUR: Array = [Vector2(580, 500), Vector2(580, 560)]
const BETWEEN: Array = [Vector2(500, 550), Vector2(980, 550)]

var _world: WorldData
var _open_rules := RoadDraftRules.new()


func before() -> void:
	_world = NetworkTestSupport.flat_world(3000.0)
	_open_rules.crossing_parcels = RoadDraftRules.CROSSING_ALLOW


func _grid(local_refresh: bool = true) -> WorldNetwork:
	var net := NetworkTestSupport.grid_network(_world, COLS, ROWS, DX, DZ, ORIGIN, 7, NetworkTestSupport.KEEP_PARCELS)
	net.local_refresh_enabled = local_refresh
	for pid: int in net.parcels:  # mülkiyet yuvası: kalan parsellerin sahibi korunmalı
		(net.parcels[pid] as WorldParcel).owner_id = pid * 3 + 1
	return net


func _expropriate(net: WorldNetwork, pts: Array) -> Dictionary:
	return net.add_road_expropriating(PackedVector2Array(pts), LOCAL)


func _taken(net: WorldNetwork, pts: Array) -> PackedInt64Array:
	var checked := RoadDraftCheck.check(net, PackedVector2Array(pts), LOCAL, _open_rules)
	assert_bool(checked["ok"]).override_failure_message(str(checked)).is_true()
	return RoadDraftCheck.taken_parcels(net, checked["points"], LOCAL)


## Parsel nesnelerinin anlık görüntüsü: kimlik -> [nesne, çokgen, sahip, bölge, doku, ayrıntı].
func _snapshot(net: WorldNetwork) -> Dictionary:
	var out := {}
	for pid: int in net.parcels:
		var p: WorldParcel = net.parcels[pid]
		out[pid] = [p, p.outline.duplicate(), p.owner_id, p.region_code, p.fabric, p.detail]
	return out


## Kimlikten bağımsız ama PARSEL KİMLİKLİ kanonik özet: parsel kimliği -> (çokgen, bölge, doku, ayrıntı, sahip, cephe
## geometrisi)
## + bloğunun imzası; blok imza+tür+parsel sayısı çoklu kümesi; graf özeti.
func _canonical(net: WorldNetwork) -> String:
	var rows: Array[String] = []
	for pid: int in net.parcels:
		var p: WorldParcel = net.parcels[pid]
		var block: WorldBlock = net.blocks[p.block_id]
		var front: WorldRoadEdge = net.edges[p.frontage_edge]
		var parts: Array[String] = [str(pid), String(p.region_code), String(p.fabric), str(p.detail), str(p.owner_id),
				block.signature, "%.2f,%.2f|%.2f,%.2f" % [net.node_pos(front.a).x, net.node_pos(front.a).y,
				net.node_pos(front.b).x, net.node_pos(front.b).y]]
		for v in p.outline:
			parts.append("%.3f,%.3f" % [v.x, v.y])
		rows.append(",".join(parts))
	rows.sort()
	var blocks: Array[String] = []
	for b: WorldBlock in net.blocks.values():
		blocks.append("%s|%s|%d|%.3f" % [b.signature, String(b.kind), b.parcel_ids.size(), b.area])
	blocks.sort()
	return "%s#%s#%s" % [net.graph_hash(), "\n".join(rows).md5_text(), "\n".join(blocks).md5_text()]


## Kalan hiçbir parsel bir yol şeridine (yarı genişlik) taşmıyor.
func _overlaps_road(net: WorldNetwork) -> PackedStringArray:
	var out := PackedStringArray()
	for pid: int in net.parcels:
		var p: WorldParcel = net.parcels[pid]
		var box := NetworkGeometry.bounds(p.outline).grow(40.0)
		for eid in net.edge_ids_in_rect(box):
			var e: WorldRoadEdge = net.edges[eid]
			if not WorldRoadEdge.is_road_class(e.road_class):
				continue
			var d := NetworkGeometry.segment_polygon_distance(net.node_pos(e.a), net.node_pos(e.b), p.outline)
			if d < e.width * 0.5 - 0.05:
				out.append("parsel %d kenar %d şeridinde (%.2f m < %.2f)" % [pid, eid, d, e.width * 0.5])
	return out


## Cephe dizini (`edge_parcels`) parsellerle tutarlı mı ve içeriği (sıralı) nedir? Dizin durum özetine girmez; ayrıca
## sınanır.
func _edge_index(net: WorldNetwork, problems: PackedStringArray) -> String:
	var rows: Array[String] = []
	var listed := 0
	for eid: int in net.edges:
		var list := net.edge_parcels(eid)
		var ids: Array = Array(list)
		ids.sort()
		if not ids.is_empty():
			rows.append("%d:%s" % [eid, str(ids)])
		for pid in list:
			listed += 1
			if not net.parcels.has(pid) or (net.parcels[pid] as WorldParcel).frontage_edge != eid:
				problems.append("cephe dizini: kenar %d parsel %d tutarsız" % [eid, pid])
	if listed != net.parcels.size():
		problems.append("cephe dizini: %d kayıt, %d parsel" % [listed, net.parcels.size()])
	rows.sort()
	return "\n".join(rows).md5_text()


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


# ---------------------------------------------------------------- tek yol, açık beklentiler

func test_road_through_a_block_takes_only_the_corridor_parcels_and_creates_none() -> void:
	var net := _grid()
	var before_parcels := _snapshot(net)
	var taken := _taken(net, THROUGH)
	assert_int(taken.size()).is_greater(0)
	assert_int(taken.size()).is_less(before_parcels.size())
	var report := _expropriate(net, THROUGH)
	assert_bool(report["ok"]).override_failure_message(str(report["error"])).is_true()
	assert_array(report["added_parcels"]).is_empty()
	var removed := PackedInt64Array(report["removed_parcels"])
	assert_array(removed).is_equal(taken)
	assert_int(net.parcels.size()).is_equal(before_parcels.size() - taken.size())
	for pid: int in before_parcels:
		if taken.has(pid):
			assert_bool(net.parcels.has(pid)).is_false()
			continue
		var rec: Array = before_parcels[pid]
		var now: WorldParcel = net.parcel(pid)
		assert_object(now).is_same(rec[0])  # AYNI nesne: kimlik, çokgen, sahip, bölge, doku, ayrıntı korunur
		assert_array(now.outline).is_equal(rec[1])
		assert_int(now.owner_id).is_equal(int(rec[2]))
	assert_array(NetworkInvariants.check_graph_integrity(net)).is_empty()
	assert_array(NetworkInvariants.check_parcels(net)).is_empty()
	assert_array(_overlaps_road(net)).is_empty()
	var op := net.peek_last_op()
	assert_bool(op["expropriate"]).is_true()
	assert_array(op["taken"]).is_equal(Array(taken))
	var change := net.change_log[net.change_log.size() - 1]
	assert_array(Array(change.parcels_removed)).is_equal(Array(taken))
	assert_bool(change.parcels_added.is_empty()).is_true()


func test_dead_end_spur_keeps_the_block_and_retires_only_the_taken_parcels() -> void:
	var net := _grid()
	var blocks_before := net.blocks.size()
	var taken := _taken(net, SPUR)
	var report := _expropriate(net, SPUR)
	assert_bool(report["ok"]).is_true()
	assert_array(report["added_parcels"]).is_empty()
	assert_array(PackedInt64Array(report["removed_parcels"])).is_equal(taken)
	# Çıkmaz sokak bloğu bölmez: blok korunur, parseller tek tek alınır.
	assert_int(net.blocks.size()).is_equal(blocks_before)
	assert_array(NetworkInvariants.check_parcels(net)).is_empty()
	assert_array(_overlaps_road(net)).is_empty()
	assert_bool(net.undo_last_op()["ok"]).is_true()
	assert_array(NetworkInvariants.check_parcels(net)).is_empty()


func test_undo_restores_the_exact_state_ids_and_owner_slots() -> void:
	var net := _grid()
	var state := net.state_hash()
	var graph := net.graph_hash()
	var parcel_set := RoadDraftCheck.parcel_set_hash(net)
	var before_parcels := _snapshot(net)
	var taken := _taken(net, THROUGH)
	assert_bool(_expropriate(net, THROUGH)["ok"]).is_true()
	assert_str(net.graph_hash()).is_not_equal(graph)
	var undone := net.undo_last_op()
	assert_bool(undone["ok"]).is_true()
	assert_array(Array(undone["change"].parcels_added)).is_equal(Array(taken))  # geri gelenler = alınanlar
	assert_str(net.state_hash()).is_equal(state)
	assert_str(net.graph_hash()).is_equal(graph)
	assert_str(RoadDraftCheck.parcel_set_hash(net)).is_equal(parcel_set)
	for pid: int in before_parcels:
		assert_object(net.parcel(pid)).is_same((before_parcels[pid] as Array)[0])
	assert_array(NetworkInvariants.check_graph_integrity(net)).is_empty()
	assert_array(NetworkInvariants.check_parcels(net)).is_empty()
	# Geri alma sonrası tam yenileme hiçbir şeyi değiştirmez; aynı yol yeniden çizilirse aynı kimlikleri alır.
	var refreshed := net.refresh_blocks()
	for key in ["added_blocks", "removed_blocks", "added_parcels", "removed_parcels"]:
		assert_array(refreshed[key]).is_empty()
	var first_again := _expropriate(net, THROUGH)
	assert_array(PackedInt64Array(first_again["removed_parcels"])).is_equal(taken)


func test_local_and_full_refresh_agree_and_replay_is_bit_equal() -> void:
	var local := _grid(true)
	var full := _grid(false)
	for pts: Array in [THROUGH, BETWEEN, SPUR]:
		var a := _expropriate(local, pts)
		var b := _expropriate(full, pts)
		assert_bool(a["ok"]).override_failure_message(str(a["error"])).is_true()
		assert_bool(b["ok"]).is_true()
		assert_array(a["removed_parcels"]).is_equal(b["removed_parcels"])
		assert_array(a["added_parcels"]).is_equal(b["added_parcels"])
		assert_str(_canonical(local)).is_equal(_canonical(full))
		assert_str(local.graph_hash()).is_equal(full.graph_hash())
	# Kayıttan yeniden oynatma: taban + delta = aynı durum, blok/parsel kimlikleri dahil (bit-eşit).
	var replayed := _grid()
	var applied := replayed.apply_delta(NetworkDelta.from_dict(JSON.parse_string(JSON.stringify(local.delta.to_dict()))))
	assert_bool(applied["ok"]).override_failure_message(str(applied)).is_true()
	assert_str(replayed.state_hash()).is_equal(local.state_hash())
	assert_str(replayed.graph_hash()).is_equal(local.graph_hash())
	assert_str(replayed.graph_hash()).is_equal(replayed.graph_hash_full())


func test_replay_refuses_a_changed_taken_set_without_touching_the_net() -> void:
	var net := _grid()
	assert_bool(_expropriate(net, THROUGH)["ok"]).is_true()
	var op := net.peek_last_op()
	var other := _grid()
	var graph := other.graph_hash()
	var state := other.state_hash()
	(op["taken"] as Array).pop_back()
	var delta := NetworkDelta.new()
	delta.base_hash = other.base_hash
	delta.ops.append(op)
	var applied := other.apply_delta(delta)
	assert_bool(applied["ok"]).is_false()
	assert_str(str(applied["error"])).contains("network_mismatch")
	assert_str(other.graph_hash()).is_equal(graph)
	assert_str(other.state_hash()).is_equal(state)
	assert_int(other.delta.ops.size()).is_equal(0)


func test_lifo_chain_restores_every_intermediate_state_including_the_edge_index() -> void:
	var net := _grid()
	var problems := PackedStringArray()
	var states: Array[String] = [net.state_hash()]
	var indexes: Array[String] = [_edge_index(net, problems)]
	for pts: Array in [THROUGH, BETWEEN, SPUR]:
		assert_bool(_expropriate(net, pts)["ok"]).is_true()
		states.append(net.state_hash())
		indexes.append(_edge_index(net, problems))
		assert_array(NetworkInvariants.check_parcels(net)).is_empty()
	assert_int(net.delta.ops.size()).is_equal(3)
	var i := states.size() - 1
	while net.can_undo():
		assert_bool(net.undo_last_op()["ok"]).is_true()
		i -= 1
		assert_str(net.state_hash()).override_failure_message("adım %d" % i).is_equal(states[i])
		assert_str(_edge_index(net, problems)).override_failure_message("cephe dizini adım %d" % i).is_equal(indexes[i])
		assert_str(net.graph_hash()).is_equal(net.graph_hash_full())
	assert_array(problems).is_empty()


func test_margin_comes_from_data_and_widens_the_corridor() -> void:
	var tight := NetworkTestSupport.grid_network(_world, COLS, ROWS, DX, DZ, ORIGIN, 7,
			{"player_roads": {"keep_parcels": true, "expropriation_margin_m": 0.0}})
	var wide := NetworkTestSupport.grid_network(_world, COLS, ROWS, DX, DZ, ORIGIN, 7,
			{"player_roads": {"keep_parcels": true, "expropriation_margin_m": 12.0}})
	var default := _grid()
	assert_float(tight.rules.expropriation_margin_m).is_equal(0.0)
	assert_float(default.rules.expropriation_margin_m).is_equal(default.rules.snap_m)  # veri yoksa snap_m
	var pts := PackedVector2Array(THROUGH)
	var n_tight := RoadDraftCheck.taken_parcels(tight, pts, LOCAL).size()
	var n_default := RoadDraftCheck.taken_parcels(default, pts, LOCAL).size()
	var n_wide := RoadDraftCheck.taken_parcels(wide, pts, LOCAL).size()
	assert_int(n_tight).is_less_equal(n_default)
	assert_int(n_default).is_less(n_wide)


func test_flag_without_keep_parcels_is_refused() -> void:
	var net := NetworkTestSupport.grid_network(_world, COLS, ROWS, DX, DZ, ORIGIN, 7, {})
	var state := net.state_hash()
	var report := _expropriate(net, THROUGH)
	assert_bool(report["ok"]).is_false()
	assert_str(net.state_hash()).is_equal(state)
	assert_bool(net.can_undo()).is_false()


func test_plain_road_through_parcels_is_unchanged_when_expropriation_mode_is_on() -> void:
	var rules := RoadDraftRules.from_control({"player_roads": {"crossing_parcels": "expropriate"}})
	assert_bool(rules.expropriation_enabled()).is_true()
	var net := _grid()
	var plain := RoadDraftCheck.check(net, PackedVector2Array(THROUGH), LOCAL, rules)
	var closed := RoadDraftCheck.check(net, PackedVector2Array(THROUGH), LOCAL, RoadDraftRules.new())
	assert_str(String(plain["reason"])).is_equal("crosses_parcels")
	assert_str(StateHash.of(_without_rules(plain))).is_equal(StateHash.of(_without_rules(closed)))
	var open_land := RoadDraftCheck.check(net, PackedVector2Array([Vector2(500, 500), Vector2(500, 380)]), LOCAL, rules)
	assert_bool(open_land["ok"]).is_true()


func _without_rules(result: Dictionary) -> Dictionary:
	var copy := result.duplicate()
	var flat := PackedFloat64Array()
	for v in result["points"]:
		flat.append_array(PackedFloat64Array([v.x, v.y]))
	copy["points"] = Array(flat)
	copy["at"] = [result["at"].x, result["at"].y]
	return copy


# ---------------------------------------------------------------- bağdaştırıcı (sim köprüsü)

func test_port_check_commit_undo_replay_follow_the_bridge_contract() -> void:
	var net := _grid()
	var rules := RoadDraftRules.from_control({"player_roads": {"crossing_parcels": "expropriate"}})
	var port := NetworkExpropriationPort.new(net, rules)
	assert_bool(port.available()).is_true()
	var cm := PackedInt64Array([58000, 50000, 58000, 60000])
	var state := net.state_hash()
	var checked := port.check(cm, LOCAL, false)
	assert_bool(checked["ok"]).override_failure_message(str(checked)).is_true()
	assert_str(net.state_hash()).is_equal(state)  # check ağa dokunmaz
	var taken: PackedInt64Array = checked["taken"]
	assert_int(taken.size()).is_greater(0)
	assert_array(taken).is_equal(_taken(net, THROUGH))
	assert_bool(port.check(cm, LOCAL, true)["ok"]).is_false()  # meşgul
	var committed := port.commit(checked, LOCAL)
	assert_bool(committed["ok"]).override_failure_message(str(committed)).is_true()
	assert_array(committed["removed"]).is_equal(taken)
	assert_bool(net.peek_last_op()["expropriate"]).is_true()
	var saved_op := net.peek_last_op()
	var after := net.state_hash()
	assert_bool(port.undo()["ok"]).is_true()
	assert_str(net.state_hash()).is_equal(state)
	var replayed := port.replay(saved_op)
	assert_bool(replayed["ok"]).override_failure_message(str(replayed)).is_true()
	assert_array(replayed["removed"]).is_equal(taken)
	assert_str(net.state_hash()).is_equal(after)
	assert_bool(port.undo()["ok"]).is_true()
	assert_bool(port.undo()["ok"]).is_false()  # geri alınacak bir şey yok
	# Kayıttaki küme farklıysa: hata, ağ değişmez.
	(saved_op["taken"] as Array).pop_back()
	var refused := port.replay(saved_op)
	assert_bool(refused["ok"]).is_false()
	assert_str(net.state_hash()).is_equal(state)


func test_port_is_unavailable_unless_the_data_mode_is_expropriate() -> void:
	var net := _grid()
	for mode in ["reject", "allow"]:
		var port := NetworkExpropriationPort.new(net,
				RoadDraftRules.from_control({"player_roads": {"crossing_parcels": mode}}))
		assert_bool(port.available()).is_false()
		assert_str(String(port.check(PackedInt64Array([58000, 50000, 58000, 60000]), LOCAL, false)["reason"])) \
				.is_equal("expropriation_disabled")
	var plain_net := NetworkTestSupport.grid_network(_world, COLS, ROWS, DX, DZ, ORIGIN, 7, {})
	assert_bool(NetworkExpropriationPort.new(plain_net, RoadDraftRules.from_control(
			{"player_roads": {"crossing_parcels": "expropriate"}})).available()).is_false()


# ---------------------------------------------------------------- özellik testi (500 tohum)

func test_property_500_seeds_invariants() -> void:
	var failures := PackedStringArray()
	var applied := 0
	var through := 0
	var spur_only := 0
	for s in SEEDS:
		var rng := RandomNumberGenerator.new()
		rng.seed = 1000 + s
		var net := _grid(true)
		var pts := _random_road(rng)
		var checked := RoadDraftCheck.check(net, PackedVector2Array(pts), LOCAL, _open_rules)
		if not bool(checked["ok"]):
			continue
		var state := net.state_hash()
		var graph := net.graph_hash()
		var parcel_set := RoadDraftCheck.parcel_set_hash(net)
		var before_parcels := _snapshot(net)
		var blocks_before := net.blocks.size()
		var index_problems := PackedStringArray()
		var index_before := _edge_index(net, index_problems)
		var taken := RoadDraftCheck.taken_parcels(net, checked["points"], LOCAL)
		var report := net.add_road_expropriating(checked["points"], LOCAL)
		var tag := "tohum %d %s" % [s, str(pts)]
		if not bool(report["ok"]):
			failures.append("%s: uygulanamadı (%s)" % [tag, report["error"]])
			continue
		applied += 1
		if net.blocks.size() > blocks_before:
			through += 1
		else:
			spur_only += 1
		if not (report["added_parcels"] as Array).is_empty():
			failures.append("%s: added_parcels boş değil" % tag)
		if PackedInt64Array(report["removed_parcels"]) != taken:
			failures.append("%s: removed %s != taken %s" % [tag, str(report["removed_parcels"]), str(taken)])
		for pid: int in before_parcels:
			var rec: Array = before_parcels[pid]
			if taken.has(pid):
				if net.parcels.has(pid):
					failures.append("%s: alınan parsel %d duruyor" % [tag, pid])
			elif net.parcel(pid) != rec[0] or net.parcel(pid).outline != rec[1] or net.parcel(pid).owner_id != int(rec[2]):
				failures.append("%s: kalan parsel %d değişti/yok" % [tag, pid])
		if net.parcels.size() != before_parcels.size() - taken.size():
			failures.append("%s: parsel sayısı" % tag)
		failures.append_array(_tagged(tag, NetworkInvariants.check_graph_integrity(net)))
		failures.append_array(_tagged(tag, NetworkInvariants.check_parcels(net)))
		failures.append_array(_tagged(tag, _overlaps_road(net)))
		var index_after := _edge_index(net, index_problems)
		if net.graph_hash() != net.graph_hash_full():
			failures.append("%s: artımlı graf özeti tam hesaptan farklı" % tag)
		var after := net.state_hash()
		# yerel == tam yenileme
		var twin := _grid(false)
		var twin_report := twin.add_road_expropriating(checked["points"], LOCAL)
		if not bool(twin_report["ok"]) or _canonical(net) != _canonical(twin) \
				or twin_report["removed_parcels"] != report["removed_parcels"]:
			failures.append("%s: yerel != tam yenileme" % tag)
		if _edge_index(twin, index_problems) != index_after:
			failures.append("%s: cephe dizini yerel != tam" % tag)
		# tam yenileme artık hiçbir şeyi değiştirmez (bloklar graf ile tutarlı)
		var again := net.refresh_blocks()
		if not (again["added_blocks"] as Array).is_empty() or not (again["removed_blocks"] as Array).is_empty():
			failures.append("%s: sonradan tam yenileme blok değiştirdi" % tag)
		if net.state_hash() != after:
			failures.append("%s: sonradan tam yenileme durumu değiştirdi" % tag)
		var delta := NetworkDelta.from_dict(JSON.parse_string(JSON.stringify(net.delta.to_dict())))
		# geri al -> bit-eşit; JSON'dan yeniden oynat -> bit-eşit; tekrar geri al -> bit-eşit
		var undone := net.undo_last_op()
		if not bool(undone["ok"]) or net.state_hash() != state or net.graph_hash() != graph \
				or RoadDraftCheck.parcel_set_hash(net) != parcel_set:
			failures.append("%s: geri alma durumu geri getirmedi" % tag)
		else:
			for pid: int in before_parcels:
				if net.parcel(pid) != (before_parcels[pid] as Array)[0]:
					failures.append("%s: geri alma parsel nesnesini geri koymadı %d" % [tag, pid])
					break
			failures.append_array(_tagged(tag, NetworkInvariants.check_parcels(net)))
			var redo := net.apply_delta(delta)
			if not bool(redo["ok"]) or net.state_hash() != after:
				failures.append("%s: geri al + kayıttan yeniden oynat bit-eşit değil %s" % [tag, str(redo)])
			elif not bool(net.undo_last_op()["ok"]) or net.state_hash() != state:
				failures.append("%s: ikinci geri alma bit-eşit değil" % tag)
		if net.graph_hash() != net.graph_hash_full():
			failures.append("%s: geri alma sonrası artımlı graf özeti tam hesaptan farklı" % tag)
		if _edge_index(net, index_problems) != index_before:
			failures.append("%s: geri alma cephe dizinini geri getirmedi" % tag)
		failures.append_array(_tagged(tag, index_problems))
		if failures.size() > 12:
			break
	assert_array(failures).override_failure_message("\n".join(failures)).is_empty()
	assert_int(applied).is_greater(150)  # test anlamlı: yeterince geçerli rastgele yol
	assert_int(through).is_greater(30)
	assert_int(spur_only).is_greater(10)


func _tagged(tag: String, problems: PackedStringArray) -> PackedStringArray:
	var out := PackedStringArray()
	for p in problems:
		out.append("%s: %s" % [tag, p])
	return out


func test_expropriation_sources_have_no_forbidden_apis() -> void:
	for path in PURE_SOURCES:
		assert_str(FileAccess.get_file_as_string(path)).is_not_empty()
		assert_array(WorldTestSupport.forbidden_api_hits(path)).override_failure_message(path).is_empty()
