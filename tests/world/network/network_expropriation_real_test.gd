extends GdUnitTestSuite
## T-042b dünya adımı · Kamulaştırma, GERÇEK Ismeral verisiyle (hafif ağ: kentsel ayak izleri x0,4) ve rastgele işlem
## zincirleri.
## Zincir: kamulaştırmalı + düz yol + aç/kapa karışık; her adımda removed == taken, added boş, artımlı graf özeti ==
## tam,
## bileşenler == yeniden oynatılan taze ağ, değişmezler; yerel == tam yenileme (ikiz ağ); yeniden oynatma bit-eşit; LIFO
## geri
## alma her ara durumu bit-eşit geri getirir.

const LOCAL := WorldRoadEdge.CLASS_LOCAL
const CHAIN_SEEDS := 3
const STEPS := 6

var _open_rules := RoadDraftRules.new()


func before() -> void:
	_open_rules.crossing_parcels = RoadDraftRules.CROSSING_ALLOW
	_open_rules.max_length_m = 300.0


## Kentsel parselli bloklardan, bloğun iki kenar orta noktasını bağlayan (geçiş) ya da bloğun içine giren (çıkmaz) yol.
func _candidate(net: WorldNetwork, rng: RandomNumberGenerator) -> PackedVector2Array:
	var ids: Array = []
	for bid: int in net.blocks:
		if not (net.blocks[bid] as WorldBlock).parcel_ids.is_empty():
			ids.append(bid)
	ids.sort()
	var block: WorldBlock = net.blocks[ids[rng.randi() % ids.size()]]
	var n := block.outline.size()
	var i := rng.randi() % n
	var a := block.outline[i].lerp(block.outline[(i + 1) % n], rng.randf_range(0.2, 0.8))
	if rng.randf() < 0.35:  # çıkmaz: bloğun içine
		return PackedVector2Array([a, a.lerp(NetworkGeometry.centroid(block.outline), rng.randf_range(0.4, 0.8))])
	var j := (i + 1 + rng.randi() % maxi(1, n - 1)) % n
	var b := block.outline[j].lerp(block.outline[(j + 1) % n], rng.randf_range(0.2, 0.8))
	return PackedVector2Array([a, b])


func _canonical(net: WorldNetwork) -> String:
	var rows: Array[String] = []
	for pid: int in net.parcels:
		var p: WorldParcel = net.parcels[pid]
		var parts: Array[String] = [str(pid), String(p.region_code), String(p.fabric), str(p.detail),
				(net.blocks[p.block_id] as WorldBlock).signature]
		for v in p.outline:
			parts.append("%.3f,%.3f" % [v.x, v.y])
		rows.append(",".join(parts))
	rows.sort()
	var blocks: Array[String] = []
	for b: WorldBlock in net.blocks.values():
		blocks.append("%s|%s|%d" % [b.signature, String(b.kind), b.parcel_ids.size()])
	blocks.sort()
	return "%s#%s#%s" % [net.graph_hash(), "\n".join(rows).md5_text(), "\n".join(blocks).md5_text()]


func test_random_chains_on_the_real_light_network() -> void:
	var failures := PackedStringArray()
	var net := NetworkTestSupport.fresh_light()
	var twin := NetworkTestSupport.fresh_light()
	twin.local_refresh_enabled = false
	var steps_done := 0
	var taken_total := 0
	var states: Array[String] = [net.state_hash()]
	var graphs: Array[String] = [net.graph_hash()]
	var parcel_sets: Array[String] = [RoadDraftCheck.parcel_set_hash(net)]
	for s in CHAIN_SEEDS:
		var rng := RandomNumberGenerator.new()
		rng.seed = 77 + s
		for step in STEPS:
			var pts := _candidate(net, rng)
			var checked := RoadDraftCheck.check(net, pts, LOCAL, _open_rules)
			if not bool(checked["ok"]):
				continue
			var tag := "zincir %d adım %d" % [s, step]
			var taken := RoadDraftCheck.taken_parcels(net, checked["points"], LOCAL)
			var count_before := net.parcels.size()
			var expropriate := rng.randf() < 0.85 or taken.is_empty()
			var report := net.add_road_expropriating(checked["points"], LOCAL) if expropriate \
					else net.add_road(checked["points"], LOCAL)
			if not bool(report["ok"]):
				failures.append("%s: uygulanamadı %s" % [tag, report["error"]])
				continue
			var twin_report := twin.add_road_expropriating(checked["points"], LOCAL) if expropriate \
					else twin.add_road(checked["points"], LOCAL)
			if expropriate:
				if not (report["added_parcels"] as Array).is_empty():
					failures.append("%s: added_parcels boş değil (%d)" % [tag, (report["added_parcels"] as Array).size()])
				if PackedInt64Array(report["removed_parcels"]) != taken:
					failures.append("%s: removed != taken (%d / %d)" % [tag,
							(report["removed_parcels"] as Array).size(), taken.size()])
				if net.parcels.size() != count_before - taken.size():
					failures.append("%s: parsel sayısı" % tag)
				taken_total += taken.size()
			steps_done += 1
			if _canonical(net) != _canonical(twin) or twin_report["removed_parcels"] != report["removed_parcels"]:
				failures.append("%s: yerel != tam yenileme" % tag)
			if net.graph_hash() != net.graph_hash_full():
				failures.append("%s: artımlı graf özeti != tam hesap" % tag)
			failures.append_array(_tagged(tag, NetworkInvariants.check_graph_integrity(net)))
			failures.append_array(_tagged(tag, NetworkInvariants.check_parcels(net)))
			states.append(net.state_hash())
			graphs.append(net.graph_hash())
			parcel_sets.append(RoadDraftCheck.parcel_set_hash(net))
	assert_array(failures).override_failure_message("\n".join(failures)).is_empty()
	assert_int(steps_done).is_greater(10)
	assert_int(taken_total).is_greater(0)
	# Yeniden oynatma: taban + delta (JSON gidiş-dönüşü) taze ağda bit-eşit; bileşenler ve graf özeti aynı.
	var fresh := NetworkTestSupport.fresh_light()
	var applied := fresh.apply_delta(NetworkDelta.from_dict(JSON.parse_string(JSON.stringify(net.delta.to_dict()))))
	assert_bool(applied["ok"]).override_failure_message(str(applied)).is_true()
	assert_str(fresh.state_hash()).is_equal(net.state_hash())
	assert_str(fresh.graph_hash()).is_equal(net.graph_hash())
	for mode in [WorldNetwork.MODE_ROAD, WorldNetwork.MODE_RAIL]:
		var a := net.components(mode)
		var b := fresh.components(mode)
		assert_int(a.size()).is_equal(b.size())
		for k in a.size():
			assert_array(Array(a[k])).is_equal(Array(b[k]))
	# Dönüş sırası önbelleği: önbellekli yerel yüz çıkarımı (tüm kenarlar tohum) tam çıkarımla aynı imzaları verir.
	var all_edges := PackedInt32Array(net.edges.keys())
	all_edges.sort()
	var cached: Array[String] = []
	for face in NetworkBlocks.extract_local(net, all_edges):
		cached.append(face["signature"])
	var fresh_faces: Array[String] = []
	for face in NetworkBlocks.extract(net):
		fresh_faces.append(face["signature"])
	cached.sort()
	fresh_faces.sort()
	assert_array(cached).is_equal(fresh_faces)
	# Tam yenileme artık hiçbir bloğu değiştirmez (bloklar graf ile tutarlı).
	var refreshed := net.refresh_blocks()
	for key in ["added_blocks", "removed_blocks", "added_parcels", "removed_parcels"]:
		assert_array(refreshed[key]).is_empty()
	# LIFO geri alma: her ara durum bit-eşit.
	var i := states.size() - 1
	while net.can_undo():
		assert_bool(net.undo_last_op()["ok"]).is_true()
		i -= 1
		assert_str(net.state_hash()).override_failure_message("geri alma adım %d" % i).is_equal(states[i])
		assert_str(net.graph_hash()).is_equal(graphs[i])
		assert_str(RoadDraftCheck.parcel_set_hash(net)).is_equal(parcel_sets[i])
		assert_str(net.graph_hash()).is_equal(net.graph_hash_full())
	assert_int(i).is_equal(0)
	assert_str(net.graph_hash()).is_equal(net.base_hash)
	assert_array(NetworkInvariants.check_parcels(net)).is_empty()


func test_real_data_switches_expropriation_on_and_plain_check_is_unchanged() -> void:
	var rules := RoadDraftRules.load_path()
	assert_str(String(rules.crossing_parcels)).is_equal("expropriate")
	assert_bool(rules.expropriation_enabled()).is_true()
	var net := NetworkTestSupport.light_network()
	assert_bool(net.rules.keep_parcels_on_delta).is_true()
	assert_float(net.rules.expropriation_margin_m).is_equal(3.0)
	assert_bool(NetworkExpropriationPort.new(net, rules).available()).is_true()
	# Düz denetim kamulaştırma kipinde de parselli bloktan geçen yolu reddeder (kapalı kip ile AYNI).
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var rejected := 0
	var closed := RoadDraftRules.load_path()
	closed.crossing_parcels = RoadDraftRules.CROSSING_REJECT
	closed.jurisdiction_regions = []
	rules.jurisdiction_regions = []
	for n in 40:
		var pts := _candidate(net, rng)
		var a := RoadDraftCheck.check(net, pts, LOCAL, rules)
		var b := RoadDraftCheck.check(net, pts, LOCAL, closed)
		assert_str(String(a["reason"])).is_equal(String(b["reason"]))
		assert_bool(a["ok"]).is_equal(b["ok"])
		if String(a["reason"]) == "crosses_parcels":
			rejected += 1
	assert_int(rejected).is_greater(0)


func _tagged(tag: String, problems: PackedStringArray) -> PackedStringArray:
	var out := PackedStringArray()
	for p in problems:
		out.append("%s: %s" % [tag, p])
	return out
