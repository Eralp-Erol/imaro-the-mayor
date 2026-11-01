# gdlint:disable=max-line-length
extends SceneTree
## 2026-10-31 · GERÇEK Ismeral D2 KAMULAŞTIRMALI YOL + HALK TEPKİSİ ölçümü (H2). Kurulum `t043b_real_world_probe.gd` /
## `t042b_real_expropriation_probe.gd` ile aynı (gerçek dünya + ağ + T0 yerleşimi + PlayableEconomy + PlayablePolitics
## [`data/game/playable_*.json`] + yol komutları + gösterge bütçe); ek olarak GERÇEK kamulaştırma bağdaştırıcısı
## (`NetworkExpropriationPort`) ve T0 miras/landmark/sivil yapılarının korunan kümesi takılır. (`playable.gd`/`playable_roads.gd`
## bu bağı HENÜZ kurmuyor; `--no-port` oynanabilirin bugünkü halini ölçer.) Salt ölçüm: oyun/sim kodu değişmez.
## Çalıştır (tek koşu = tek süreç):
##   tools/godot.sh --headless --path . --script res://tests/sim/perf/expropriation_reaction_real_probe.gd -- \
##       --list [--pool=150]                       (D2'de aday yolların yıkım/hane dağılımı; `EXPROP_LIST `)
##   ... -- --pick=q10|q50|q90|max [--days=400] [--undo-at=N] [--sim-seed=N] [--no-port] [--no-road] [--no-local]
## --no-local: mahalle ölçekli okumayı (`reactions.local.enabled`) kapatır = 2026-10-31 öncesi davranış (önce/sonra tablosu).
## --pick: adayları yerinden edilen haneye göre sıralar, dilimi seçer (`--idx=K` ile doğrudan sıra); --undo-at: yoldan N gün
## sonra `public_work.undo_last`; --no-road: yol yok (tepki gürültüsü için taban çizgisi). Çıktı: `EXPROP_REAL ` + JSON.

const DATA_DIR := "res://data/world/ismeral"
const NETWORK_PATH := "res://data/world/ismeral/network.json"
const SETTLEMENT_PATH := "res://data/world/ismeral/settlement.json"
const WARM_DAYS := 30
const SAMPLE_DAYS: Array[int] = [1, 7, 14, 30, 60, 100, 150, 200, 300, 400]
const REGION := "D2"

var _args: Dictionary = {}


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	_args = _parse(OS.get_cmdline_user_args())
	var days := int(_args.get("days", "400"))
	var control := WorldControlData.load_dir(DATA_DIR)
	var world_seed := int(control["world"]["default_seed"])
	var sim_seed := int(_args.get("sim-seed", str(world_seed)))
	var world := WorldGenerator.generate(control, world_seed, {})
	var net_control: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(NETWORK_PATH))
	var rules: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SETTLEMENT_PATH))
	var net := NetworkGenerator.generate(world, net_control, world_seed)
	var loaded := SettlementTable.load_game_table()
	var settlement := T0Settlement.generate_detailed(world, net, loaded["table"], world_seed, rules)
	var views := _views(net)
	var source := ListParcelSource.create(&"ismeral", views)
	var stock := PlayableStock.from_columns(settlement.columns)
	var cfg := PlayableEconomy.config_for(views, stock, {"decision": {"priority_review_enabled": 1}})
	var pol_cfg := PlayablePolitics.config()
	# DENEY (sayaç-olgusal; gönderilen veri DEĞİL): --cf-min-share=N kesim pay eşiği (pm), --cf-agenda-min=N gündem eşiği (pm)
	if _args.has("cf-min-share"):
		pol_cfg.blocs["min_share"] = int(_args["cf-min-share"])
	if _args.has("cf-agenda-min"):
		pol_cfg.reactions["agenda"]["min_displacement_pm"] = int(_args["cf-agenda-min"])
		pol_cfg.reactions["agenda"]["full_displacement_pm"] = maxi(int(_args["cf-agenda-min"]) * 5, 1)
	if _args.has("no-local"):
		pol_cfg.reactions["local"]["enabled"] = false
	var handle := PoliticsBootstrap.create(sim_seed, source, cfg, stock, null, pol_cfg)
	if handle == null:
		push_error("probe: sim kurulamadı")
		quit(2)
		return
	var facade := handle.facade as SimFacadeImpl
	var road_rules := RoadDraftRules.load_path(NETWORK_PATH)
	var ctx := PublicWorksContext.create(net, road_rules, PublicWorksConfig.load_default())
	var port_attached := false
	var protected_n := 0
	if not _args.has("no-port"):
		var port := NetworkExpropriationPort.new(net, road_rules)
		ctx.set_expropriation(port)
		port_attached = port.available()
		var prot := PackedInt64Array()
		var seen := {}
		var cols := settlement.columns
		for i in cols.count:
			if (int(cols.flags[i]) & (BuildingColumns.FLAG_HERITAGE | BuildingColumns.FLAG_LANDMARK | BuildingColumns.FLAG_CIVIC)) != 0:
				var pid := int(cols.parcel_id[i])
				if not seen.has(pid):
					seen[pid] = true
					prot.append(pid)
		ctx.set_protected(prot)
		protected_n = prot.size()
	var attached := facade.attach_public_works(ctx)
	PlayableBudget.attach(facade, attached)
	var projector := SimBuildingProjector.create(facade, settlement, SimBuildingMapping.load_default(), world_seed)
	var pump := SimBuildingPump.create(projector) if projector != null else null
	var rec := _Rec.new()
	rec.facade = facade
	rec.pump = pump
	rec.cfg = cfg
	for _d in WARM_DAYS:
		rec.step()
	var head := {"world_seed": world_seed, "sim_seed": sim_seed, "port_available": port_attached, "protected_parcels": protected_n,
		"roads_attached": attached, "parcels": views.size(), "t0_stock_parcels": stock.parcel_ids().size(),
		"d2_before": rec.region_row(), "jurisdiction": (road_rules.jurisdiction_regions as Array).map(func(c: StringName) -> String: return String(c)),
		"crossing_mode": String(road_rules.crossing_parcels),
		"blend": pol_cfg.blocs.get("blend_mode", "?"), "min_share": pol_cfg.blocs.get("min_share", -1),
		"reaction_agenda_cfg": pol_cfg.reactions.get("agenda", {}),
		"reaction_window": pol_cfg.blocs.get("reaction_window", -1)}
	var cands: Array = []
	if not _args.has("pts"):
		cands = _candidates(net, world, road_rules, facade, world_seed, int(_args.get("pool", "150")))
	var list_rows: Array = []
	for c: Dictionary in cands:
		list_rows.append([c["len"], c["taken"], c["built"], c["hh"], c["near_hh"], c["near_parcels"]])
	if _args.has("list"):
		var ds: Array = cands.map(func(c: Dictionary) -> int: return int(c["hh"]))
		ds.sort()
		var bs: Array = cands.map(func(c: Dictionary) -> int: return int(c["built"]))
		bs.sort()
		var nn: Array = cands.map(func(c: Dictionary) -> int: return int(c["near_hh"]))
		nn.sort()
		var out := {"head": head, "n_valid": cands.size(), "pool": int(_args.get("pool", "150")),
			"displaced_hh": _q(ds), "built_parcels": _q(bs), "nearby_hh": _q(nn),
			"rows_len_taken_built_hh_nearhh_nearparcels": list_rows}
		# oynanabilirin bugünkü hali (köprü yok) için aynı yolun düz doğrulaması ayrıca `--no-port` ile
		print("EXPROP_LIST ", JSON.stringify(out))
		quit(0)
		return
	if _args.has("pts"):  # doğrudan çizgi (x1,z1,x2,z2 metre): köprüsüz oynanabilir halin aynı yolla sınanması için
		var v := str(_args["pts"]).split(",")
		var chk := RoadDraftCheck.check(net, PackedVector2Array([Vector2(float(v[0]), float(v[1])),
				Vector2(float(v[2]), float(v[3]))]), RoadDrawTool.ROAD_CLASS, road_rules)
		var pcm := PackedInt64Array()
		var pp: PackedVector2Array = chk.get("points", PackedVector2Array())
		for p in pp:
			pcm.append(roundi(p.x * 100.0))
			pcm.append(roundi(p.y * 100.0))
		cands = [{"pts": str(pp), "cm": pcm, "len": float(chk.get("length_m", 0.0)), "order": 0, "taken": 0, "built": 0, "hh": 0,
			"near_hh": 0, "near_parcels": 0}]
	if cands.is_empty():
		push_error("probe: aday yok")
		quit(2)
		return
	var sorted_c := cands.duplicate()
	sorted_c.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
		if int(x["hh"]) != int(y["hh"]):
			return int(x["hh"]) < int(y["hh"])
		return int(x["order"]) < int(y["order"]))
	var idx := _pick_index(sorted_c.size())
	if str(_args.get("pick", "")) == "max":
		idx = sorted_c.size() - 1
	var cand: Dictionary = sorted_c[idx]
	var out := {"head": head, "pick": str(_args.get("pick", "idx")), "idx": idx, "of": sorted_c.size(),
		"road": {"len_m": snappedf(float(cand["len"]), 0.1), "taken": cand["taken"], "built": cand["built"],
			"households_preview": cand["hh"], "nearby_hh_preview": cand["near_hh"], "nearby_parcels_preview": cand["near_parcels"],
			"pts": cand["pts"]}}
	var cm: PackedInt64Array = cand["cm"]
	# oyuncunun bugünkü yolu (köprü yok / var): düz doğrulama ret nedeni + gösterilen argümanlar
	var plain := facade.validate_command(SimCommand.public_work_road(cm, RoadDrawTool.ROAD_CLASS, false))
	out["plain_validate"] = {"status": String(plain.status), "reason": String(plain.reason_key),
		"arg_keys": plain.args.keys().map(func(k: Variant) -> String: return str(k)), "taken_parcels": int(plain.args.get("taken_parcels", 0)),
		"displaced_households": int(plain.args.get("displaced_households", 0))}
	if _args.has("no-port") or _args.has("no-road"):
		pass
	var undo_at := int(_args.get("undo-at", "-1"))
	var t_road := -1
	var road_res := ""
	var road_reason := ""
	if not _args.has("no-road"):
		var rr := facade.submit_command(SimCommand.public_work_road(cm, RoadDrawTool.ROAD_CLASS, not _args.has("no-port")))
		road_res = String(rr.status)
		road_reason = String(rr.reason_key)
		t_road = facade.current_tick()
	out["road_submit"] = {"status": road_res, "reason": road_reason, "tick": t_road}
	rec.t_road = t_road
	var undo_tick := -1
	for d in days:
		if undo_at >= 0 and d == undo_at and t_road >= 0:
			var ur := facade.submit_command(SimCommand.public_work_undo_last())
			out["undo_submit"] = {"status": String(ur.status), "reason": String(ur.reason_key), "day": d}
			undo_tick = facade.current_tick()
		rec.step()
		var rel := d + 1
		if SAMPLE_DAYS.has(rel):
			rec.sample(rel, t_road)
	out["undo_tick"] = undo_tick
	out["d2_after"] = rec.region_row()
	out["events"] = rec.report(t_road, days)
	out["groups_end"] = rec.groups_end()
	out["samples"] = rec.samples
	out["works_end"] = facade.public_works().size()
	out["network_parcels_end"] = net.parcels.size()
	out["state_hash"] = facade.state_hash()
	print("EXPROP_REAL ", JSON.stringify(out))
	quit(0)


func _pick_index(n: int) -> int:
	if _args.has("idx"):
		return clampi(int(_args["idx"]), 0, n - 1)
	var pick := str(_args.get("pick", "q50"))
	match pick:
		"q10":
			return n / 10
		"q90":
			return mini(n - 1, n * 9 / 10)
		_:
			return n / 2


func _q(sorted: Array) -> Dictionary:
	if sorted.is_empty():
		return {}
	var n := sorted.size()
	return {"min": sorted[0], "p10": sorted[n / 10], "p25": sorted[n / 4], "median": sorted[n / 2], "p75": sorted[n * 3 / 4],
		"p90": sorted[mini(n - 1, n * 9 / 10)], "max": sorted[n - 1]}


## D2 kenarlarından rastgele dokunuşlar (60-250 m); köprü kipinde geçerli ve parsel alan olanlar, sim önizlemesiyle (yıkılan
## bina, yerinden edilen hane, yakın hane).
func _candidates(net: WorldNetwork, world: WorldData, rules: RoadDraftRules, facade: SimFacadeImpl, world_seed: int,
		pool: int) -> Array:
	var world_rules := net.rules
	var ids: Array = net.edges.keys()
	ids.sort()
	var in_region: Array = []
	for eid: int in ids:
		var e: WorldRoadEdge = net.edges[eid]
		if e.mode() != WorldNetwork.MODE_ROAD or e.road_class == WorldRoadEdge.CLASS_FERRY:
			continue
		var mid := (net.node_pos(e.a) + net.node_pos(e.b)) * 0.5
		if String(world_rules.region_code_at(world, mid)) == REGION:
			in_region.append(eid)
	var rng := RandomNumberGenerator.new()
	rng.seed = NetworkRules.stream_seed(world_seed, "h2_probe")
	var out: Array = []
	for n in pool:
		var e: WorldRoadEdge = net.edges[in_region[rng.randi() % in_region.size()]]
		var a := net.node_pos(e.a).lerp(net.node_pos(e.b), rng.randf())
		var b := a + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(60.0, 250.0)
		var pts := PackedVector2Array([a, b])
		var plain := RoadDraftCheck.check(net, pts, RoadDrawTool.ROAD_CLASS, rules)
		var cm := PackedInt64Array()
		for p: Vector2 in (plain["points"] as PackedVector2Array):
			cm.append(roundi(p.x * 100.0))
			cm.append(roundi(p.y * 100.0))
		var v := facade.validate_command(SimCommand.public_work_road(cm, RoadDrawTool.ROAD_CLASS, true))
		if v.status != CommandResult.STATUS_VALID or int(v.args.get("taken_parcels", 0)) <= 0:
			continue
		out.append({"pts": str(plain["points"]), "cm": cm, "len": float(plain["length_m"]), "order": n,
			"taken": int(v.args.get("taken_parcels", 0)), "built": int(v.args.get("taken_built_parcels", 0)),
			"hh": int(v.args.get("displaced_households", 0)), "near_hh": int(v.args.get("nearby_households", 0)),
			"near_parcels": int(v.args.get("nearby_parcels", 0))})
	return out


func _views(net: WorldNetwork) -> Array[ParcelView]:
	var out: Array[ParcelView] = []
	var src: Variant = net.parcels
	var items: Array = src.values() if src is Dictionary else Array(src)
	for item in items:
		var wp := item as WorldParcel
		if wp == null or wp.region_code == &"":
			continue
		var v := ParcelView.new()
		v.id = wp.id
		v.region_code = wp.region_code
		v.center = wp.centroid
		v.area_m2 = int(wp.area)
		v.zone = &"zone.residential"
		out.append(v)
	return out


func _parse(args: PackedStringArray) -> Dictionary:
	var out := {}
	for a in args:
		if a.begins_with("--"):
			var kv := a.trim_prefix("--").split("=", true, 1)
			out[kv[0]] = kv[1] if kv.size() > 1 else "1"
	return out


## Olay / gündem / kesim durumu toplayıcı.
class _Rec:
	extends RefCounted
	var facade: SimFacadeImpl = null
	var pump: SimBuildingPump = null
	var cfg: EconomyConfig = null
	var t_road: int = -1
	var counts: Dictionary = {}
	var reacted: Array = []           # group.reacted olayları [tick, topic, intensity, subjects]
	var agenda_events: Array = []     # politics.agenda_opened / resolved olayları
	var expropriated: Array = []      # event.road.expropriated / restored olayları
	var strip_by_day: Dictionary = {}
	var strip_total: int = 0
	var strip_by_prio: Dictionary = {0: 0, 1: 0, 2: 0}
	var declines_hidden: int = 0
	var agenda_seen: Dictionary = {}  # item_id -> özet
	var open_by_day: Dictionary = {}  # tick -> aynı anda açık gündem öğesi sayısı (her gün)
	var first_pe01_chain: Array = []  # ilk PE-01 öğesinin neden zinciri (gerekçe kayıtları: karar, etkenler)
	var samples: Array = []
	var events_per_day: Dictionary = {}
	var _seq: int = 0

	func step() -> void:
		facade.advance(1)
		if pump != null:
			pump.frame(true, Callable(self, "_noop"))
			pump.frame(false, Callable(self, "_noop"))
		var tick := facade.current_tick()
		for e in facade.events_since(_seq):
			_seq = maxi(_seq, e.seq)
			var kind := String(e.kind)
			var key := String(e.message_key)
			counts[key] = int(counts.get(key, 0)) + 1
			var subj: Array = []
			for s in e.subjects:
				subj.append(String(s))
			if kind == "group.reacted":
				reacted.append([e.tick, str(e.args.get("topic", "")), int(e.args.get("intensity", 0)), str(e.args.get("reaction", "")),
					subj.slice(0, 4)])
			elif kind.begins_with("politics.agenda"):
				agenda_events.append([e.tick, kind, key, str(e.args.get("template", e.args.get("topic", ""))), subj.slice(0, 4)])
			elif key.begins_with("event.road."):
				expropriated.append([e.tick, key, SimContract.to_args(e.args), subj.size()])
			if NotificationStrip.is_unplanned_decline(e):
				declines_hidden += 1
			else:
				strip_total += 1
				var pr := NotificationStrip.priority(e)
				strip_by_prio[pr] = int(strip_by_prio[pr]) + 1
				strip_by_day[e.tick] = int(strip_by_day.get(e.tick, 0)) + 1
		var open_now := facade.agenda_items()
		open_by_day[tick] = open_now.size()
		for it in open_now:
			if not agenda_seen.has(it.item_id):
				if String(it.template_id) == "PE-01" and first_pe01_chain.is_empty():
					first_pe01_chain = _chain(Array(it.reason_ids))
				agenda_seen[it.item_id] = {"id": it.item_id, "template": String(it.template_id), "opened": it.opened_tick,
					"deadline": it.deadline_tick, "delivery": String(it.delivery), "region": String(it.region_code),
					"title_key": String(it.title_key), "args": SimContract.to_args(it.args),
					"cause_refs": Array(it.cause_refs).slice(0, 4).map(func(s: Variant) -> String: return str(s)),
					"seen_tick": tick, "reason_ids": Array(it.reason_ids).size(), "status_first": String(it.status)}
			agenda_seen[it.item_id]["status_last"] = String(it.status)
			agenda_seen[it.item_id]["last_tick"] = tick

	func _noop(_c: Variant, _v: Variant) -> void:
		pass

	## Neden zinciri: gerekçe kimlikleri + ebeveynleri (en çok 2 düzey) -> [karar, etkenler [ad, değer, ağırlık], özneler].
	func _chain(ids: Array) -> Array:
		var out: Array = []
		var seen := {}
		var queue: Array = ids.duplicate()
		while not queue.is_empty() and out.size() < 8:
			var id := int(queue.pop_front())
			if seen.has(id) or id < 1:
				continue
			seen[id] = true
			var rec: Dictionary = facade.game_state().reasons.by_id(id)
			if rec.is_empty():
				continue
			var factors: Array = []
			for f: Dictionary in rec.get("factors", []):
				factors.append([String(f["name"]), int(f["value"]), int(f.get("weight", 0))])
			out.append({"id": id, "decision": str(rec.get("decision", "")), "factors": factors,
				"subjects": Array(rec.get("subjects", PackedStringArray())).slice(0, 6).map(func(x: Variant) -> String: return str(x))})
			for pid: Variant in rec.get("parent_ids", PackedInt64Array()):
				queue.append(int(pid))
		return out

	func open_stats() -> Dictionary:
		var most := 0
		var days_open := 0
		for t: int in open_by_day:
			most = maxi(most, int(open_by_day[t]))
			days_open += 1 if int(open_by_day[t]) > 0 else 0
		return {"max_open_at_once": most, "days_with_open_item": days_open}

	func region_row() -> Dictionary:
		for row in EconomyQuery.region_stats(facade.game_state(), cfg):
			if String(row["code"]) == "D2":
				return {"latent_hh": int(row["latent_hh"]), "housed_hh": int(row["housed_hh"]), "res_built": int(row["res_built"]),
					"com_built": int(row["com_built"]), "infra_load": int(row["infra_load"]), "infra_cap": int(row["infra_cap"]),
					"infra_load_pm": int(row["infra_load_pm"])}
		return {}

	func sample(day: int, _t_ref: int) -> void:
		var state := facade.game_state()
		var blocs := {}
		if PoliticsState.is_initialized(state):
			var pol: Dictionary = PoliticsState.data(state)
			for key in PoliticsState.bloc_keys(state):
				var b: Dictionary = pol["blocs"][key]
				var ev: Dictionary = b["eval"]
				var sig: Dictionary = b["signals"]
				blocs[key] = {"exposure": b["exposure"], "size": int(b["size"]), "hot": str(b.get("hot_region", "")),
					"G": int(b["G"]), "S": int(b["S"]), "reaction": str(ev["reaction"]), "tier": str(ev["tier"]),
					"housing_cost_grievance": int(ActorStore.actor_ref(state, key)["state"].get("grievances", {}).get("housing_cost", 0)),
					"intensity": int(ev["intensity"]), "displacement": int(sig.get("displacement", 0)),
					"proximity": int(sig.get("proximity", 0)), "infra_stress": int(sig.get("infra_stress", 0))}
		var reg_sig := {}
		if PublicWorksState.has_reactions(state):
			var latent := int(region_row().get("latent_hh", 1))
			for code in ["D1", "D2", "D3", "D4", "D5", "D6"]:
				reg_sig[code] = [
					BlocSignals.reaction_pm(PublicWorksState.reaction_rows(state, "displaced", code), state.tick, 360,
						maxi(latent if code == "D2" else 1, 1), BlocSignals.SCALE),
					BlocSignals.reaction_pm(PublicWorksState.reaction_rows(state, "nearby", code), state.tick, 360,
						maxi(latent if code == "D2" else 1, 1), 1)]
		samples.append({"day": day, "tick": facade.current_tick(), "blocs": blocs, "region_signal_pm_D2": reg_sig.get("D2", []), "open_agenda": facade.agenda_items().size(),
			"region": region_row()})

	func groups_end() -> Array:
		var out: Array = []
		for g in facade.snapshot().group_reactions:
			out.append({"group": str(g.group.ref()) if g.group != null else "", "region": String(g.region_code),
				"reaction": String(g.reaction), "intensity": g.intensity, "stance_delta": g.stance_delta,
				"cause_refs": Array(g.cause_refs).slice(0, 4).map(func(s: Variant) -> String: return str(s)), "tick": g.tick})
		return out

	func report(t_ref: int, days: int) -> Dictionary:
		var rel := func(t: int) -> int: return t - t_ref
		var first_react := -1
		var react_days := {}
		for r: Array in reacted:
			react_days[int(r[0])] = true
			if first_react < 0 and int(r[0]) >= t_ref:
				first_react = int(r[0])
		var agenda_rows: Array = agenda_seen.values()
		agenda_rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["id"]) < int(b["id"]))
		var per_template := {}
		var first_pe01 := -1
		for it: Dictionary in agenda_rows:
			per_template[it["template"]] = int(per_template.get(it["template"], 0)) + 1
			if it["template"] == "PE-01" and first_pe01 < 0:
				first_pe01 = int(it["opened"])
		var strip_days := strip_by_day.size()
		var strip_max := 0
		for k in strip_by_day:
			strip_max = maxi(strip_max, int(strip_by_day[k]))
		return {
			"t_road": t_ref, "end_tick": facade.current_tick(), "counts": counts,
			"road_events": expropriated,
			"agenda_items": agenda_rows,
			"agenda_per_template": per_template,
			"first_pe01_opened_tick": first_pe01, "first_pe01_rel_days": (first_pe01 - t_ref) if first_pe01 >= 0 and t_ref >= 0 else -1,
			"agenda_total_items": agenda_rows.size(), "open_stats": open_stats(), "first_pe01_chain": first_pe01_chain,
			"reaction_local": PoliticsState.data(facade.game_state()).get("reaction_local", {}),
			"media_published": int(PoliticsState.data(facade.game_state())["media"]["published"]),
			"agenda_events_n": agenda_events.size(),
			"agenda_events_first40": agenda_events.slice(0, 40).map(func(a: Array) -> Array: return [rel.call(int(a[0]))] + a.slice(1)),
			"group_reacted_n": reacted.size(), "group_reacted_days": react_days.size(),
			"first_group_reacted_rel_days": (first_react - t_ref) if first_react >= 0 and t_ref >= 0 else -1,
			"group_reacted_first40": reacted.slice(0, 40).map(func(a: Array) -> Array: return [rel.call(int(a[0]))] + a.slice(1)),
			"strip_eligible_total": strip_total, "strip_eligible_days": strip_days, "strip_eligible_max_per_day": strip_max,
			"strip_by_priority": strip_by_prio, "strip_unplanned_declines_hidden": declines_hidden,
			"strip_per_day_over_run": snappedf(float(strip_total) / maxf(days, 1), 0.001),
		}
