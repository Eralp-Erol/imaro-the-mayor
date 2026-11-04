extends SceneTree
## T-042 adım 1 ölçümü, GERÇEK Ismeral dünyası (tohum = world.json default_seed = 1467, hücre 100 m), BAŞSIZ:
##   tools/godot.sh --headless --path . --script res://experiments/t042-road-probe/probe.gd -- [--edges=120] [--random=600]
## (a) tek yol eklemede blok yenileme süresi (yerel / tam / geri alma, ms), (b) bölge başına açık arazi payı ve geçerli çizim
## adayı oranı, (c) v0 aracının ret nedenleri dağılımı (özellikle yoğun çekirdek D1/D6).
## Tek kullanımlık ölçüm betiği (üretim kodu değildir). Zaman: Time (araç); ağ kodu saf kalır.

const DATA_DIR := "res://data/world/ismeral"
const ANGLES := 8
const LENGTHS: Array[float] = [80.0, 150.0]

var _net: WorldNetwork
var _world: WorldData
var _rules_open: RoadDraftRules
var _rules_d2: RoadDraftRules


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	var edges_per_region := 120
	var random_per_region := 600
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--edges="):
			edges_per_region = int(arg.trim_prefix("--edges="))
		elif arg.begins_with("--random="):
			random_per_region = int(arg.trim_prefix("--random="))
	var control := WorldControlData.load_dir(DATA_DIR)
	var world_seed := int(control["world"]["default_seed"])
	_world = WorldGenerator.generate(control, world_seed, {})
	var net_control: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("%s/network.json" % DATA_DIR))
	_net = NetworkGenerator.generate(_world, net_control, world_seed)
	_rules_d2 = RoadDraftRules.from_control(net_control)
	_rules_open = RoadDraftRules.from_control(net_control)
	_rules_open.jurisdiction_regions = []
	print("PROBE seed=%d cell_m=%.0f counts=%s" % [world_seed, _world.cell_size, str(_net.counts())])
	print("PROBE rules=%s" % JSON.stringify(_rules_d2.to_dict()))
	_probe_land_share()
	_probe_candidates(edges_per_region, random_per_region)
	_probe_timing()
	quit(0)


# ---------------------------------------------------------------- (b) açık arazi payı
func _probe_land_share() -> void:
	var step := 100.0
	var rows := {}
	var cell_km2 := step * step / 1.0e6
	var y := _world.origin.y + step * 0.5
	while y < _world.origin.y + _world.size.y:
		var x := _world.origin.x + step * 0.5
		while x < _world.origin.x + _world.size.x:
			if not _world.is_water(x, y) and _world.landmass_at(x, y) == WorldData.LANDMASS_MAINLAND:
				var code := String(_net.rules.region_code_at(_world, Vector2(x, y)))
				var row: Dictionary = rows.get(code, {"land": 0, "parcelized": 0, "open_in_block": 0, "outside_net": 0,
						"open_near_road": 0, "open_usable": 0})
				row["land"] += 1
				var block := _net.block_at(x, y)
				var open := false
				if block == null:
					row["outside_net"] += 1
					open = true
				elif not block.parcel_ids.is_empty():
					row["parcelized"] += 1
				else:
					row["open_in_block"] += 1
					open = true
				if open and not _net.edges_near(x, y, 150.0).is_empty():
					row["open_near_road"] += 1
					if _world.slope_degrees_at(x, y) <= _rules_open.max_slope_deg:
						row["open_usable"] += 1
				rows[code] = row
			x += step
		y += step
	var codes: Array = rows.keys()
	codes.sort()
	print("PROBE_B bölge | kara km2 | parselli blok % | blok içi parselsiz % | ağ dışı (blok yok) % | açık + yola<=150m % | + eğim uygun %")
	for code: String in codes:
		var r: Dictionary = rows[code]
		var n := float(r["land"])
		print("PROBE_B %s | %.1f | %.1f | %.1f | %.1f | %.1f | %.1f" % [code, n * cell_km2, 100.0 * r["parcelized"] / n,
				100.0 * r["open_in_block"] / n, 100.0 * r["outside_net"] / n, 100.0 * r["open_near_road"] / n,
				100.0 * r["open_usable"] / n])


# ---------------------------------------------------------------- (b) aday sayısı, (c) ret nedenleri
func _probe_candidates(edges_per_region: int, random_per_region: int) -> void:
	var by_region := {}
	var eids: Array = _net.edges.keys()
	eids.sort()
	for eid: int in eids:
		var e: WorldRoadEdge = _net.edges[eid]
		if e.mode() != WorldNetwork.MODE_ROAD or e.road_class == WorldRoadEdge.CLASS_FERRY:
			continue
		var mid := (_net.node_pos(e.a) + _net.node_pos(e.b)) * 0.5
		var code := String(_net.rules.region_code_at(_world, mid))
		if not by_region.has(code):
			by_region[code] = []
		by_region[code].append(eid)
	var codes: Array = by_region.keys()
	codes.sort()
	var timing_us := 0
	var timing_n := 0
	print("PROBE_C region | kenar | örnek kenar | kenarın >=1 geçerli çıkışı % | rastgele aday | geçerli % | ret dağılımı (rastgele, tüm bölgeler serbest)")
	for code: String in codes:
		var list: Array = by_region[code]
		var rng := RandomNumberGenerator.new()
		rng.seed = NetworkRules.stream_seed(1467, "t042probe:" + code)
		# 1) kenar başına çıkış: kenar ortasından 8 yön x 2 uzunluk
		var sampled := 0
		var with_exit := 0
		var stride := maxi(1, list.size() / edges_per_region)
		var i := 0
		while i < list.size() and sampled < edges_per_region:
			var e: WorldRoadEdge = _net.edges[list[i]]
			var mid := (_net.node_pos(e.a) + _net.node_pos(e.b)) * 0.5
			var dir := (_net.node_pos(e.b) - _net.node_pos(e.a)).normalized()
			var found := false
			for k in ANGLES:
				if found:
					break
				var ang := dir.angle() + (float(k) + 0.5) * TAU / ANGLES
				for length in LENGTHS:
					var t0 := Time.get_ticks_usec()
					var res := RoadDraftCheck.check(_net, PackedVector2Array([mid, mid + Vector2.from_angle(ang) * length]),
							WorldRoadEdge.CLASS_LOCAL, _rules_open)
					timing_us += Time.get_ticks_usec() - t0
					timing_n += 1
					if bool(res["ok"]):
						found = true
						break
			sampled += 1
			with_exit += 1 if found else 0
			i += stride
		# 2) rastgele dokunuş: rastgele kenar, rastgele nokta, rastgele yön/uzunluk (40..300 m)
		var valid := 0
		var reasons := {}
		for n in random_per_region:
			var e2: WorldRoadEdge = _net.edges[list[rng.randi() % list.size()]]
			var a := _net.node_pos(e2.a).lerp(_net.node_pos(e2.b), rng.randf())
			var b := a + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(40.0, 300.0)
			var t1 := Time.get_ticks_usec()
			var res2 := RoadDraftCheck.check(_net, PackedVector2Array([a, b]), WorldRoadEdge.CLASS_LOCAL, _rules_open)
			timing_us += Time.get_ticks_usec() - t1
			timing_n += 1
			if bool(res2["ok"]):
				valid += 1
			else:
				reasons[String(res2["reason"])] = int(reasons.get(String(res2["reason"]), 0)) + 1
		var rtxt := []
		var rkeys: Array = reasons.keys()
		rkeys.sort()
		for rk: String in rkeys:
			rtxt.append("%s %.0f%%" % [rk, 100.0 * float(reasons[rk]) / random_per_region])
		print("PROBE_C %s | %d | %d | %.0f | %d | %.1f | %s" % [code, list.size(), sampled, 100.0 * with_exit / maxf(1.0, sampled),
				random_per_region, 100.0 * valid / random_per_region, ", ".join(rtxt)])
	# (c3) Serbest dokunuş: bölge içinde rastgele kara noktası (yola oturmayan), 40..200 m
	print("PROBE_C3 serbest dokunuş (A yola oturmuyor), bölge | örnek | geçerli % | ret dağılımı")
	for code: String in codes:
		var rng3 := RandomNumberGenerator.new()
		rng3.seed = NetworkRules.stream_seed(1467, "t042probe:free:" + code)
		var ok3 := 0
		var n3 := 0
		var reasons3 := {}
		var guard := 0
		while n3 < 400 and guard < 200000:
			guard += 1
			var a4 := _world.origin + Vector2(rng3.randf() * _world.size.x, rng3.randf() * _world.size.y)
			if _world.is_water(a4.x, a4.y) or String(_net.rules.region_code_at(_world, a4)) != code \
					or _world.landmass_at(a4.x, a4.y) != WorldData.LANDMASS_MAINLAND:
				continue
			var b4 := a4 + Vector2.from_angle(rng3.randf() * TAU) * rng3.randf_range(40.0, 200.0)
			var res4 := RoadDraftCheck.check(_net, PackedVector2Array([a4, b4]), WorldRoadEdge.CLASS_LOCAL, _rules_open)
			n3 += 1
			if bool(res4["ok"]):
				ok3 += 1
			else:
				reasons3[String(res4["reason"])] = int(reasons3.get(String(res4["reason"]), 0)) + 1
		var parts3 := []
		var k3: Array = reasons3.keys()
		k3.sort()
		for rk: String in k3:
			parts3.append("%s %.0f%%" % [rk, 100.0 * float(reasons3[rk]) / maxf(1.0, n3)])
		print("PROBE_C3 %s | %d | %.1f | %s" % [code, n3, 100.0 * ok3 / maxf(1.0, n3), ", ".join(parts3)])
	print("PROBE_C check_ms_avg=%.2f over %d checks" % [timing_us / 1000.0 / maxf(1.0, timing_n), timing_n])
	# (c) Başlangıç test alanı D2, gönderilen kuralla (yetki alanı yalnız D2)
	var d2: Array = by_region.get("D2", [])
	var rng2 := RandomNumberGenerator.new()
	rng2.seed = NetworkRules.stream_seed(1467, "t042probe:shipped")
	var ok_n := 0
	var reasons2 := {}
	var total := 600
	for n in total:
		var e3: WorldRoadEdge = _net.edges[d2[rng2.randi() % d2.size()]]
		var a3 := _net.node_pos(e3.a).lerp(_net.node_pos(e3.b), rng2.randf())
		var b3 := a3 + Vector2.from_angle(rng2.randf() * TAU) * rng2.randf_range(40.0, 300.0)
		var res3 := RoadDraftCheck.check(_net, PackedVector2Array([a3, b3]), WorldRoadEdge.CLASS_LOCAL, _rules_d2)
		if bool(res3["ok"]):
			ok_n += 1
		else:
			reasons2[String(res3["reason"])] = int(reasons2.get(String(res3["reason"]), 0)) + 1
	var parts2 := []
	var k2: Array = reasons2.keys()
	k2.sort()
	for rk: String in k2:
		parts2.append("%s %.0f%%" % [rk, 100.0 * float(reasons2[rk]) / total])
	print("PROBE_C2 D2 (gönderilen kural, yetki=D2) rastgele dokunuş %d: geçerli %.1f%% | %s" % [total, 100.0 * ok_n / total, ", ".join(parts2)])


# ---------------------------------------------------------------- (a) süre
func _probe_timing() -> void:
	var d2_nodes: Array = []
	var nids: Array = _net.nodes.keys()
	nids.sort()
	for nid: int in nids:
		if String(_net.rules.region_code_at(_world, _net.node_pos(nid))) == "D2":
			d2_nodes.append(nid)
	var rng := RandomNumberGenerator.new()
	rng.seed = NetworkRules.stream_seed(1467, "t042probe:timing")
	var local_ms: Array[float] = []
	var full_ms: Array[float] = []
	var undo_ms: Array[float] = []
	var graph_ms: Array[float] = []
	var parcels_ok := true
	var tried := 0
	var parcel_hash := RoadDraftCheck.parcel_set_hash(_net)
	var base_graph := _net.graph_hash()
	while local_ms.size() < 5 and tried < 3000:
		tried += 1
		var e: WorldRoadEdge = _net.edges[_net.edges.keys()[rng.randi() % _net.edges.size()]]
		var a := _net.node_pos(e.a).lerp(_net.node_pos(e.b), rng.randf())
		var b := a + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(80.0, 300.0)
		var pts := PackedVector2Array([a, b])
		var res := RoadDraftCheck.check(_net, pts, WorldRoadEdge.CLASS_LOCAL, _rules_open)
		if not bool(res["ok"]):
			continue
		for mode in [true, false]:
			_net.local_refresh_enabled = mode
			var t0 := Time.get_ticks_usec()
			var rep := _net.add_road(res["points"], WorldRoadEdge.CLASS_LOCAL)
			var dt := (Time.get_ticks_usec() - t0) / 1000.0
			if not (rep["added_parcels"] as Array).is_empty() or not (rep["removed_parcels"] as Array).is_empty():
				parcels_ok = false
			(local_ms if mode else full_ms).append(dt)
			var t1 := Time.get_ticks_usec()
			_net.undo_last_op()
			if mode:
				undo_ms.append((Time.get_ticks_usec() - t1) / 1000.0)
		var t2 := Time.get_ticks_usec()
		var gh := _net.graph_hash()
		graph_ms.append((Time.get_ticks_usec() - t2) / 1000.0)
		if gh != base_graph or RoadDraftCheck.parcel_set_hash(_net) != parcel_hash:
			parcels_ok = false
	_net.local_refresh_enabled = true
	print("PROBE_A tek yol ekleme (add_road toplam, ms) yerel: %s | tam yenileme: %s | geri alma: %s | graph_hash: %s | parsel/graf korundu: %s (%d aday denendi)" % [
			_fmt(local_ms), _fmt(full_ms), _fmt(undo_ms), _fmt(graph_ms), str(parcels_ok), tried])
	var cnt := 0
	var t3 := Time.get_ticks_usec()
	cnt = NetworkBlocks.component_count(_net)
	print("PROBE_A component_count_ms=%.1f (n=%d) refresh_blocks_full_ms=%.1f" % [(Time.get_ticks_usec() - t3) / 1000.0, cnt,
			_time_full()])


func _time_full() -> float:
	var t0 := Time.get_ticks_usec()
	_net.refresh_blocks()
	return (Time.get_ticks_usec() - t0) / 1000.0


func _fmt(values: Array[float]) -> String:
	var parts := []
	for v in values:
		parts.append("%.1f" % v)
	return "[" + ", ".join(parts) + "]"
