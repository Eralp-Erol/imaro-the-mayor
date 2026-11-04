extends SceneTree
## T-042b DÜNYA adımı · GERÇEK Ismeral ölçümü (başsız; duvar saati yalnız ölçümdür, makineye bağlıdır, kabul kararı
## değildir).
## Kurulum `t043b_real_world_probe.gd` ile aynı (gerçek dünya + ağ + T0 yerleşimi + PlayableEconomy/PlayablePolitics +
## yol
## komutları), ek olarak GERÇEK kamulaştırma bağdaştırıcısı (`NetworkExpropriationPort`) takılır, yetki alanı AÇIK
## (D1/D6 dahil).
## Çıktılar:
##   REGION  : bölge başına rastgele dokunuş (yola oturan, 60-250 m): DÜZ ret oranı (kapalı kip) ve KAMULAŞTIRMA kipi
## ret oranı,
##             alınan parsel sayısı dağılımı, parselli bloktan geçen yolların payı.
##   ROAD    : seçili yollarda `add_road` düz (öncesi) / kamulaştırmalı (sonrası) ms, kırılım (taken / planarize /
##             extract_local / eşleme+kurma+silme), geri alma ms, graf özeti ms, bileşen sorgusu ms.
##   TICK    : sim ile gerçek yol: `validate_command`, `submit_command`, kamulaştırmalı yol tick'i, geri alma tick'i,
## sonraki
##             düz tick (ms) ve olay/durum özeti.
## Çalıştır: tools/godot.sh --headless --path . --script res://tests/sim/perf/t042b_real_expropriation_probe.gd -- \
##             [--samples=300] [--roads=10] [--region=D1] [--ticks=D1:0,D6:0 (bölge:alınan-sayısı sırası)]
## [--margin=3.0]

const DATA_DIR := "res://data/world/ismeral"
const NETWORK_PATH := "res://data/world/ismeral/network.json"
const SETTLEMENT_PATH := "res://data/world/ismeral/settlement.json"
const WARM_DAYS := 30
const REGIONS: Array[String] = ["D1", "D2", "D3", "D4", "D5", "D6"]

var _args: Dictionary = {}
var _net: WorldNetwork
var _world: WorldData
var _open_rules: RoadDraftRules
var _closed_rules: RoadDraftRules
var _port: NetworkExpropriationPort


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	_args = _parse(OS.get_cmdline_user_args())
	var t_setup := Time.get_ticks_usec()
	var control := WorldControlData.load_dir(DATA_DIR)
	var world_seed := int(control["world"]["default_seed"])
	_world = WorldGenerator.generate(control, world_seed, {})
	var net_control: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(NETWORK_PATH))
	_net = NetworkGenerator.generate(_world, net_control, world_seed)
	_open_rules = RoadDraftRules.from_control(net_control)
	_open_rules.jurisdiction_regions = []  # D1/D6 dahil tüm bölgeler (gönderilen kural yalnız D2)
	_closed_rules = RoadDraftRules.from_control(net_control)
	_closed_rules.jurisdiction_regions = []
	_closed_rules.crossing_parcels = RoadDraftRules.CROSSING_REJECT
	if _args.has("margin"):  # deney: koridor payı (m)
		_net.rules.expropriation_margin_m = float(_args["margin"])
	_port = NetworkExpropriationPort.new(_net, _open_rules)
	print("PROBE world setup_ms=%.0f counts=%s port_available=%s mode=%s margin=%.1f" % [
			(Time.get_ticks_usec() - t_setup) / 1000.0, str(_net.counts()), str(_port.available()),
			String(_open_rules.crossing_parcels), _net.rules.expropriation_margin_m])
	var samples := int(_args.get("samples", "300"))
	var by_region := _edges_by_region()
	var through: Dictionary = {}
	for code in REGIONS:
		through[code] = _region_stats(code, by_region.get(code, []), samples, world_seed)
	_road_timing(through, int(_args.get("roads", "10")), String(_args.get("region", "D1")))
	for spec in String(_args.get("ticks", "D1:0,D6:0")).split(","):
		var kv := spec.split(":")
		if kv.size() < 2:
			continue
		_tick_probe(world_seed, through, kv[0], int(kv[1]))
	quit(0)


func _edges_by_region() -> Dictionary:
	var out := {}
	var ids: Array = _net.edges.keys()
	ids.sort()
	for eid: int in ids:
		var e: WorldRoadEdge = _net.edges[eid]
		if e.mode() != WorldNetwork.MODE_ROAD or e.road_class == WorldRoadEdge.CLASS_FERRY:
			continue
		var code := String(_net.rules.region_code_at(_world, (_net.node_pos(e.a) + _net.node_pos(e.b)) * 0.5))
		if not out.has(code):
			out[code] = []
		out[code].append(eid)
	return out


func _random_touch(rng: RandomNumberGenerator, list: Array) -> PackedVector2Array:
	var e: WorldRoadEdge = _net.edges[list[rng.randi() % list.size()]]
	var a := _net.node_pos(e.a).lerp(_net.node_pos(e.b), rng.randf())
	return PackedVector2Array([a, a + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(60.0, 250.0)])


## Bölge başına: düz (kapalı) ret oranı, kamulaştırma kipi ret oranı, alınan sayısı dağılımı. Dönüş: geçiş yolu
## adayları.
func _region_stats(code: String, list: Array, samples: int, world_seed: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = NetworkRules.stream_seed(world_seed, "t042b_world_probe:" + code)
	var plain_ok := 0
	var plain_cross := 0
	var mode_ok := 0
	var with_taken := 0
	var taken_counts: Array[int] = []
	var reasons := {}
	var out: Array = []
	var diverge := 0
	if list.is_empty():
		return out
	for n in samples:
		var pts := _random_touch(rng, list)
		var plain := RoadDraftCheck.check(_net, pts, WorldRoadEdge.CLASS_LOCAL, _closed_rules)
		var cm := PackedInt64Array()
		for p in plain["points"]:
			cm.append(roundi(p.x * 100.0))
			cm.append(roundi(p.y * 100.0))
		var mode := _port.check(cm, WorldRoadEdge.CLASS_LOCAL, false)
		if bool(plain["ok"]):
			plain_ok += 1
		elif plain["reason"] == RoadDraftCheck.REASON_CROSSES_PARCELS:
			plain_cross += 1
		if bool(mode["ok"]):
			mode_ok += 1
			var taken: PackedInt64Array = mode["taken"]
			if not taken.is_empty():
				with_taken += 1
				taken_counts.append(taken.size())
				out.append({"pts": mode["points"], "cm": cm, "taken": taken.size(), "len": mode["length_m"], "code": code})
			if bool(plain["ok"]) and not taken.is_empty():
				diverge += 1
		else:
			reasons[String(mode["reason"])] = int(reasons.get(String(mode["reason"]), 0)) + 1
			if bool(plain["ok"]):
				diverge += 1
	taken_counts.sort()
	var rtxt := []
	var rkeys: Array = reasons.keys()
	rkeys.sort()
	for rk: String in rkeys:
		rtxt.append("%s %.1f%%" % [rk, 100.0 * float(reasons[rk]) / samples])
	var med := str(taken_counts[taken_counts.size() / 2]) if not taken_counts.is_empty() else "-"
	var p90 := str(taken_counts[int(taken_counts.size() * 0.9)]) if not taken_counts.is_empty() else "-"
	var top := str(taken_counts[taken_counts.size() - 1]) if not taken_counts.is_empty() else "-"
	print("REGION %s | örnek %d | düz kip geçerli %.1f%% (crosses_parcels %.1f%%) | kamulaştırma kipi geçerli %.1f%% | "
			% [code, samples, 100.0 * plain_ok / samples, 100.0 * plain_cross / samples, 100.0 * mode_ok / samples]
			+ "parsel alan yol %.1f%% | alınan medyan %s p90 %s max %s | kip ret nedenleri: %s | "
			% [100.0 * with_taken / samples, med, p90, top, ", ".join(rtxt)]
			+ "düz geçerli ama koridor payı parsel alıyor ya da kip reddediyor: %d" % diverge)
	return out


func _road_timing(through: Dictionary, roads: int, region: String) -> void:
	var cands: Array = through.get(region, [])
	if cands.is_empty():
		print("ROAD aday yok (%s)" % region)
		return
	var rows: Array = []
	var take_ms: Array[float] = []
	var plain_ms: Array[float] = []
	var x_ms: Array[float] = []
	var undo_ms: Array[float] = []
	var plan_ms: Array[float] = []
	var extract_ms: Array[float] = []
	var refresh_ms: Array[float] = []
	var done := 0
	var base_graph := _net.graph_hash()
	var base_parcels := _net.parcels.size()
	for c: Dictionary in cands:
		if done >= roads:
			break
		var pts: PackedVector2Array = c["pts"]
		# öncesi: düz add_road (aynı yol; parselleri almaz, yalnız ölçüm için) ve geri alma
		var t0 := Time.get_ticks_usec()
		var plain := _net.add_road(pts, WorldRoadEdge.CLASS_LOCAL)
		plain_ms.append((Time.get_ticks_usec() - t0) / 1000.0)
		if not bool(plain["ok"]):
			continue
		_net.undo_last_op()
		# sonrası: kamulaştırmalı
		t0 = Time.get_ticks_usec()
		var taken := RoadDraftCheck.taken_parcels(_net, pts, WorldRoadEdge.CLASS_LOCAL)
		take_ms.append((Time.get_ticks_usec() - t0) / 1000.0)
		t0 = Time.get_ticks_usec()
		var rep := _net.add_road_expropriating(pts, WorldRoadEdge.CLASS_LOCAL)
		x_ms.append((Time.get_ticks_usec() - t0) / 1000.0)
		var removed := PackedInt64Array(rep["removed_parcels"])
		var ok := bool(rep["ok"]) and (rep["added_parcels"] as Array).is_empty() and removed == taken
		t0 = Time.get_ticks_usec()
		_net.undo_last_op()
		undo_ms.append((Time.get_ticks_usec() - t0) / 1000.0)
		if not ok or _net.graph_hash() != base_graph or _net.parcels.size() != base_parcels:
			print("ROAD İHLAL: %s" % str(pts))
		# kırılım: aynı işlemi adım adım (WorldNetwork._apply_op kopyası; yalnız ölçüm)
		var br := _breakdown(pts)
		plan_ms.append(br["plan"])
		extract_ms.append(br["extract"])
		refresh_ms.append(br["refresh"])
		rows.append([c["len"], taken.size(), snappedf(x_ms[x_ms.size() - 1], 0.1)])
		done += 1
	t_report("ROAD add_road düz (öncesi, ms)", plain_ms)
	t_report("ROAD add_road_expropriating (sonrası, ms)", x_ms)
	t_report("ROAD   taken_parcels (ms)", take_ms)
	t_report("ROAD   _op_add_road (alınan + planarize, ms)", plan_ms)
	t_report("ROAD   extract_local (ms)", extract_ms)
	t_report("ROAD   _refresh_after_op (eşleme+kurma+silme, ms)", refresh_ms)
	t_report("ROAD undo_last_op (ms)", undo_ms)
	var t1 := Time.get_ticks_usec()
	_net.add_road_expropriating(cands[0]["pts"], WorldRoadEdge.CLASS_LOCAL)
	var t_graph := Time.get_ticks_usec()
	var gh := _net.graph_hash()
	var graph_ms := (Time.get_ticks_usec() - t_graph) / 1000.0
	var t_comp := Time.get_ticks_usec()
	_net.components(WorldNetwork.MODE_ROAD)
	var comp_ms := (Time.get_ticks_usec() - t_comp) / 1000.0
	var t_check := Time.get_ticks_usec()
	var next_check := _port.check(cands[cands.size() - 1]["cm"], WorldRoadEdge.CLASS_LOCAL, false)
	var check_ms := (Time.get_ticks_usec() - t_check) / 1000.0
	var exact := gh == _net.graph_hash_full()
	_net.undo_last_op()
	print("ROAD ardından: graph_hash %.2f ms (tam hesapla aynı: %s), components %.2f ms, port.check %.2f ms (ok=%s), "
			% [graph_ms, str(exact), comp_ms, check_ms, str(next_check["ok"])]
			+ "yol+özet toplam %.1f ms" % ((Time.get_ticks_usec() - t1) / 1000.0))
	print("ROAD satırlar [uzunluk m, alınan, ms]: %s" % str(rows))


## `WorldNetwork._apply_op` adımlarının kopyası (ölçüm): _op_add_road, _refresh_after_op (extract_local ayrıca), geri
## alma.
func _breakdown(pts: PackedVector2Array) -> Dictionary:
	var net := _net
	var op := NetworkExpropriation.road_op(net, pts, WorldRoadEdge.CLASS_LOCAL, -1.0)
	var report := net._new_report()
	var journal := NetworkOpJournal.begin(net, op)
	net._journal = journal
	var t0 := Time.get_ticks_usec()
	net._op_add_road(op, report)
	var plan := (Time.get_ticks_usec() - t0) / 1000.0
	var seeds := PackedInt32Array()
	var seen := {}
	for nid: int in journal.touched_nodes():
		if net.adjacency.has(nid):
			for eid in net.adjacency[nid]:
				if not seen.has(eid):
					seen[eid] = true
					seeds.append(eid)
	for eid: int in journal.changed_edge_ids:
		if net.edges.has(eid) and not seen.has(eid):
			seen[eid] = true
			seeds.append(eid)
	seeds.sort()
	var t1 := Time.get_ticks_usec()
	NetworkBlocks.extract_local(net, seeds)
	var extract := (Time.get_ticks_usec() - t1) / 1000.0
	var t2 := Time.get_ticks_usec()
	var refreshed := net._refresh_after_op(journal)
	var refresh := (Time.get_ticks_usec() - t2) / 1000.0
	net._journal = null
	net.delta.ops.append(op)
	var change := NetworkChange.from_journal(net, journal, NetworkChange.KIND_APPLY, refreshed)
	journal.change = change
	net._undo_stack.append(journal)
	net.undo_last_op()
	return {"plan": plan, "extract": extract, "refresh": refresh - extract}


func t_report(label: String, values: Array[float]) -> void:
	var sorted := values.duplicate()
	sorted.sort()
	if sorted.is_empty():
		print("%s: -" % label)
		return
	print("%s: n=%d min %.2f | medyan %.2f | max %.2f" % [label, sorted.size(), sorted[0], sorted[sorted.size() / 2],
			sorted[sorted.size() - 1]])


func _tick_probe(world_seed: int, through: Dictionary, region: String, rank: int) -> void:
	var cands: Array = through.get(region, [])
	if cands.is_empty() or rank >= cands.size():
		print("TICK aday yok")
		return
	# En çok parsel alan yol önce (D1/D6 yoğun çekirdek): rank'a göre
	var sorted_cands := cands.duplicate()
	sorted_cands.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return int(x["taken"]) > int(y["taken"]))
	var cand: Dictionary = sorted_cands[rank]
	var rules: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SETTLEMENT_PATH))
	var loaded := SettlementTable.load_game_table()
	var settlement := T0Settlement.generate_detailed(_world, _net, loaded["table"], world_seed, rules)
	var views: Array[ParcelView] = []
	for wp: WorldParcel in _net.parcels.values():
		if wp.region_code == &"":
			continue
		var v := ParcelView.new()
		v.id = wp.id
		v.region_code = wp.region_code
		v.center = wp.centroid
		v.area_m2 = int(wp.area)
		v.zone = &"zone.residential"
		views.append(v)
	var source := ListParcelSource.create(&"ismeral", views)
	var stock := PlayableStock.from_columns(settlement.columns)
	var cfg := PlayableEconomy.config_for(views, stock, {})
	var handle := PoliticsBootstrap.create(world_seed, source, cfg, stock, null, PlayablePolitics.config())
	var facade := handle.facade as SimFacadeImpl
	var ctx := PublicWorksContext.create(_net, _open_rules, PublicWorksConfig.load_default())
	var timed := _TimedPort.new(_net, _open_rules)
	ctx.set_expropriation(timed)
	var attached := facade.attach_public_works(ctx)
	PlayableBudget.attach(facade, attached)
	for _d in WARM_DAYS:
		facade.advance(1)
	var cm: PackedInt64Array = cand["cm"]
	var out := {"region": cand["code"], "road_len_m": snappedf(float(cand["len"]), 0.1), "world_taken": cand["taken"],
			"parcels": views.size(), "stock_parcels": stock.parcel_ids().size(), "attached": attached}
	var t0 := Time.get_ticks_usec()
	var preview := facade.validate_command(SimCommand.public_work_road(cm, RoadDrawTool.ROAD_CLASS, true))
	out["validate_ms"] = snappedf((Time.get_ticks_usec() - t0) / 1000.0, 0.01)
	out["rank"] = rank
	out["validate_status"] = String(preview.status)
	out["validate_reason"] = String(preview.reason_key)
	t0 = Time.get_ticks_usec()
	var plain_try := facade.validate_command(SimCommand.public_work_road(cm, RoadDrawTool.ROAD_CLASS, false))
	out["plain_validate_ms"] = snappedf((Time.get_ticks_usec() - t0) / 1000.0, 0.01)
	out["plain_validate_reason"] = String(plain_try.reason_key)
	t0 = Time.get_ticks_usec()
	var res := facade.submit_command(SimCommand.public_work_road(cm, RoadDrawTool.ROAD_CLASS, true))
	out["submit_ms"] = snappedf((Time.get_ticks_usec() - t0) / 1000.0, 0.01)
	out["submit_status"] = String(res.status)
	var graph_before := _net.graph_hash()
	var state_before := facade.state_hash()
	timed.commit_ms = 0.0
	timed.check_ms = 0.0
	t0 = Time.get_ticks_usec()
	facade.advance(1)
	out["expropriating_road_tick_ms"] = snappedf((Time.get_ticks_usec() - t0) / 1000.0, 0.01)
	out["tick_part_world_commit_ms"] = snappedf(timed.commit_ms, 0.01)
	out["tick_part_check_ms"] = snappedf(timed.check_ms, 0.01)
	t0 = Time.get_ticks_usec()
	_net.graph_hash()
	out["graph_hash_clean_ms"] = snappedf((Time.get_ticks_usec() - t0) / 1000.0, 0.01)
	var works := facade.public_works()
	out["works"] = works.size()
	out["taken_in_sim"] = works[0].taken_parcel_ids.size() if not works.is_empty() else -1
	out["world_parcels_after"] = _net.parcels.size()
	facade.advance(1)
	var t1 := Time.get_ticks_usec()
	facade.advance(1)
	out["next_plain_tick_ms"] = snappedf((Time.get_ticks_usec() - t1) / 1000.0, 0.01)
	facade.submit_command(SimCommand.public_work_undo_last())
	t0 = Time.get_ticks_usec()
	facade.advance(1)
	out["undo_tick_ms"] = snappedf((Time.get_ticks_usec() - t0) / 1000.0, 0.01)
	out["undo_graph_restored"] = _net.graph_hash() == graph_before
	out["undo_works"] = facade.public_works().size()
	out["state_hash_changed_after_undo"] = facade.state_hash() != state_before
	print("TICK ", JSON.stringify(out))


## Köprü çağrı sürelerini toplar (tick kırılımı için).
class _TimedPort:
	extends NetworkExpropriationPort
	var commit_ms: float = 0.0
	var check_ms: float = 0.0

	func check(points_cm: PackedInt64Array, road_class: StringName, busy: bool) -> Dictionary:
		var t0 := Time.get_ticks_usec()
		var out := super.check(points_cm, road_class, busy)
		check_ms += (Time.get_ticks_usec() - t0) / 1000.0
		return out

	func commit(checked: Dictionary, road_class: StringName) -> Dictionary:
		var t0 := Time.get_ticks_usec()
		var out := super.commit(checked, road_class)
		commit_ms += (Time.get_ticks_usec() - t0) / 1000.0
		return out


func _parse(args: PackedStringArray) -> Dictionary:
	var out := {}
	for a in args:
		if a.begins_with("--"):
			var kv := a.trim_prefix("--").split("=", true, 1)
			out[kv[0]] = kv[1] if kv.size() > 1 else "1"
	return out
