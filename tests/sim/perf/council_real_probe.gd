# gdlint:disable=max-line-length
extends SceneTree
## 2026-10-31 · GERÇEK Ismeral D2 MECLİS ölçümü (H1): yol çiz -> imar planı öner; plan meclis eşiğini (10 parsel / 40
## birim) aşarsa meclise gider. Kurulum `t043b_real_world_probe.gd` ile AYNI (gerçek dünya + ağ + T0 yerleşimi +
## PlayableEconomy + PlayablePolitics [`data/game/playable_*.json`] + yol komutları + gösterge bütçe + SimBuildingProjector).
## Salt ölçüm: oyun/sim kodu değişmez, kabul kararı yok. Duvar saati yazılmaz.
## Çalıştır (tek koşu = tek süreç):
##   tools/godot.sh --headless --path . --script res://tests/sim/perf/council_real_probe.gd -- \
##       [--rank=0|1] [--plan-n=12] [--sim-seed=N] [--days=400] [--retry=none|same|small] [--small-n=9] [--no-road]
## --rank: aday yol (0 = 108 m, 1 = 248 m; `t043b_real_world_probe --list`); --plan-n: tek teklifteki parsel sayısı (yola
## en yakın boş parseller); --retry: meclis ret ederse ertesi gün 2. teklif (same = aynı parseller, small = ilk
## `small-n` parsel); --no-road: yol çizmeden yalnız plan (kontrol).
## Çıktı: `COUNCIL_REAL ` + JSON satırı.

const DATA_DIR := "res://data/world/ismeral"
const NETWORK_PATH := "res://data/world/ismeral/network.json"
const SETTLEMENT_PATH := "res://data/world/ismeral/settlement.json"
const CANDIDATES := 600
const NEAR_M := 150.0
const WARM_DAYS := 30  # `--warm=N` ile geçersiz kılınabilir (aynı teklif farklı günde = farklı oy gürültüsü)
const MIN_VACANT := 6

var _args: Dictionary = {}


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	_args = _parse(OS.get_cmdline_user_args())
	var rank := int(_args.get("rank", "0"))
	var plan_n := int(_args.get("plan-n", "12"))
	var days := int(_args.get("days", "400"))
	var retry := str(_args.get("retry", "none"))
	var small_n := int(_args.get("small-n", "9"))
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
	var handle := PoliticsBootstrap.create(sim_seed, source, cfg, stock, null, pol_cfg)
	if handle == null:
		push_error("probe: sim kurulamadı")
		quit(2)
		return
	var facade := handle.facade as SimFacadeImpl
	var road_rules := RoadDraftRules.load_path(NETWORK_PATH)
	var ctx := PublicWorksContext.create(net, road_rules, PublicWorksConfig.load_default())
	var attached := facade.attach_public_works(ctx)
	var budget := PlayableBudget.attach(facade, attached)
	var projector := SimBuildingProjector.create(facade, settlement, SimBuildingMapping.load_default(), world_seed)
	var pump := SimBuildingPump.create(projector) if projector != null else null
	var occupied := {}
	for pid in stock.parcel_ids():
		occupied[int(pid)] = true
	var vacant: Array[ParcelView] = []
	for v in views:
		if not occupied.has(v.id):
			vacant.append(v)
	var cands := _candidates(net, road_rules, vacant, world_seed)
	if cands.is_empty() or rank >= cands.size():
		push_error("probe: aday yok")
		quit(2)
		return
	var cand: Dictionary = cands[rank]
	var pts: PackedVector2Array = cand["pts"]
	var near_ids := _nearest_vacant(vacant, pts, plan_n)
	var cm := PackedInt64Array()
	for p in pts:
		cm.append(roundi(p.x * 100.0))
		cm.append(roundi(p.y * 100.0))
	var out := {
		"world_seed": world_seed, "sim_seed": sim_seed, "rank": rank, "road_len_m": snappedf(float(cand["len"]), 0.1),
		"region": String(cand["region"]), "plan_n": near_ids.size(), "budget_attached": budget, "roads_attached": attached,
		"requires_council_zoning": bool(pol_cfg.council["requires_council"].get("zoning.propose", false)),
		"plan_council_min_parcels": int(pol_cfg.council.get("plan_council_min_parcels", 0)),
		"plan_council_min_units": int(pol_cfg.council.get("plan_council_min_units", 0)),
		"session_days": int(pol_cfg.council["session_days"]), "min_lead_days": int(pol_cfg.council["min_lead_days"]),
		"friction_days": int(pol_cfg.council["friction_days"]), "tie_result": String(pol_cfg.council["tie_result"]),
		"members": (pol_cfg.council["members"] as Array).size(),
	}
	var rec := _Rec.new()
	rec.facade = facade
	rec.pump = pump
	rec.cfg = cfg
	rec.region = String(cand["region"])
	var warm := int(_args.get("warm", str(WARM_DAYS)))
	var zone := StringName(str(_args.get("zone", "zone.mixed")))
	var density := int(_args.get("density", "-1"))
	out["warm_days"] = warm
	out["zone"] = String(zone)
	out["density_pm"] = density
	for _d in warm:
		rec.step()
	out["load_pm_before"] = rec.d2_load_pm()
	var preview := facade.plan_preview(near_ids, zone, density)
	out["preview"] = {"ok": preview.ok, "total_units": preview.total_units, "total_infra_units": preview.total_infra_units,
		"council_required": preview.council_required, "council_min_parcels": preview.council_min_parcels,
		"council_min_units": preview.council_min_units, "parcels": preview.parcels.size(), "capacity": preview.regions}
	# ZORLANMIŞ ret (doğal değil): --hostile = meclis üyelerinin "büyüme/koruma" duruşu +1000 (plan_council_test `_stance(false)`
	# ile aynı yöntem); gerçek verinin doğal oyu `COUNCIL_REAL` doğal koşularındadır.
	var members_keys: Array = []
	var orig_stance := {}
	if _args.has("hostile"):
		for k in 5:
			var mk := "actor.council.%d" % (k + 1)
			if ActorStore.has_actor(handle.state(), mk):
				members_keys.append(mk)
				var st: Dictionary = ActorStore.actor_ref(handle.state(), mk)["stance"]
				orig_stance[mk] = int(st.get("growth_vs_preservation", 0))
				st["growth_vs_preservation"] = 1000
		out["hostile_members"] = members_keys
		out["orig_stance"] = orig_stance
	var t_start := facade.current_tick()
	out["tick_start"] = t_start
	if not _args.has("no-road"):
		var rr := facade.submit_command(SimCommand.public_work_road(cm, RoadDrawTool.ROAD_CLASS))
		out["road_status"] = String(rr.status)
		out["road_reason"] = String(rr.reason_key)
		out["tick_road_sent"] = facade.current_tick()
		rec.step()
	var pr := facade.submit_command(_propose(near_ids, zone, density))
	out["plan_status"] = String(pr.status)
	out["plan_reason"] = String(pr.reason_key)
	var t_plan := facade.current_tick()
	out["tick_plan_sent"] = t_plan
	var forecast := {}
	var retried := false
	var retry_info := {}
	for _d in days:
		rec.step()
		if forecast.is_empty() and rec.first("event.council.vote_opened") >= 0:
			for k: String in facade.snapshot().extensions:
				if k.begins_with("x.sim.council.forecast."):
					forecast[k.trim_prefix("x.sim.council.forecast.")] = facade.snapshot().extensions[k]
		if retry != "none" and not retried and rec.first("event.zoning.plan_rejected") >= 0:
			retried = true
			var ids2 := near_ids
			if retry == "small":
				ids2 = near_ids.slice(0, small_n)
			if retry == "same-calm":  # duruşlar özgün değerlerine döner (yeniden teklif farklı oy alabilir mi?)
				for mk: String in members_keys:
					ActorStore.actor_ref(handle.state(), mk)["stance"]["growth_vs_preservation"] = int(orig_stance[mk])
			var pre2 := facade.plan_preview(ids2, zone, density)
			var v2 := facade.validate_command(_propose(ids2, zone, density))
			var s2 := facade.submit_command(_propose(ids2, zone, density))
			retry_info = {"tick": facade.current_tick(), "mode": retry, "parcels": ids2.size(),
				"preview_units": pre2.total_units, "council_required": pre2.council_required,
				"validate": String(v2.status), "validate_reason": String(v2.reason_key),
				"submit": String(s2.status), "submit_reason": String(s2.reason_key)}
	out["retry"] = retry_info
	out["forecast_at_open"] = forecast
	out["snapshot_votes_end"] = _snap_votes(facade)
	out["notification_strip"] = rec.strip_rows
	out["politics_events"] = rec.pol_events
	out["agenda_items_seen"] = rec.agenda_seen.values()
	out["events"] = rec.summary(t_start, t_plan)
	out["votes_at_resolve"] = rec.dumps
	out["votes_end"] = rec.votes_report(facade, handle)
	out["load_pm_series"] = rec.load_series
	out["plan_states_end"] = _plan_states(facade, near_ids)
	var snap_council := facade.snapshot().council
	out["snapshot_council_votes"] = snap_council.votes.size() if snap_council != null and "votes" in snap_council else -1
	out["agenda_items_end"] = facade.agenda_items().size()
	out["end_tick"] = facade.current_tick()
	out["state_hash"] = facade.state_hash()
	print("COUNCIL_REAL ", JSON.stringify(out))
	quit(0)


## `density` >= 0 ise komuta yazılır (UI yoğunluk seçeneği); aksi halde imar varsayılanı.
func _propose(ids: PackedInt64Array, zone: StringName, density: int) -> SimCommand:
	if density < 0:
		return SimCommand.zoning_propose(ids, zone)
	return SimCommand.make(SimCommand.KIND_ZONING_PROPOSE, {"parcel_ids": ids, "land_use": zone, "density": density})


## Oyuncunun görebileceği oylama satırları (SimSnapshot.council): kimlik, durum, oy sayıları, gerekçe sayısı.
func _snap_votes(facade: SimFacadeImpl) -> Array:
	var out: Array = []
	var c := facade.snapshot().council
	if c == null:
		return out
	for v: CouncilVoteView in c.votes:
		out.append({"id": v.vote_id, "status": String(v.status), "yes": v.yes, "no": v.no, "abstain": v.abstain,
			"opened": v.opened_tick, "closes": v.closes_tick, "title_key": String(v.title_key), "reasons": v.reason_ids.size()})
	return out


func _plan_states(facade: SimFacadeImpl, ids: PackedInt64Array) -> Dictionary:
	var by_state := {}
	var sample := {}
	for id in ids:
		var ps := facade.plan_state(int(id))
		by_state[String(ps.state)] = int(by_state.get(String(ps.state), 0)) + 1
		if not sample.has(String(ps.state)):
			sample[String(ps.state)] = {"vote_ref": String(ps.vote_ref), "rejected_tick": ps.rejected_tick,
				"rejected_command_id": ps.rejected_command_id, "zone": String(ps.zone), "pending_zone": String(ps.pending_zone),
				"due_tick": ps.due_tick}
	return {"count_by_state": by_state, "sample": sample}


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


func _candidates(net: WorldNetwork, rules: RoadDraftRules, vacant: Array[ParcelView], world_seed: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = NetworkRules.stream_seed(world_seed, "t043b_real_probe")
	var ids: Array = net.edges.keys()
	ids.sort()
	var out: Array = []
	for n in CANDIDATES:
		var e: WorldRoadEdge = net.edges[ids[rng.randi() % ids.size()]]
		var a := net.node_pos(e.a).lerp(net.node_pos(e.b), rng.randf())
		var b := a + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(60.0, 250.0)
		var res := RoadDraftCheck.check(net, PackedVector2Array([a, b]), RoadDrawTool.ROAD_CLASS, rules)
		if not bool(res["ok"]):
			continue
		var count := 0
		for v in vacant:
			if _dist_to_segment(v.center, a, b) <= NEAR_M:
				count += 1
		if count < MIN_VACANT:
			continue
		out.append({"pts": res["points"], "count": count, "len": res["length_m"], "region": _region_at(vacant, a),
				"order": n})
	out.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
		if int(x["count"]) != int(y["count"]):
			return int(x["count"]) > int(y["count"])
		return int(x["order"]) < int(y["order"]))
	return out


func _region_at(vacant: Array[ParcelView], p: Vector2) -> StringName:
	var best := &""
	var best_d := INF
	for v in vacant:
		var d := v.center.distance_squared_to(p)
		if d < best_d:
			best_d = d
			best = v.region_code
	return best


func _nearest_vacant(vacant: Array[ParcelView], pts: PackedVector2Array, count: int) -> PackedInt64Array:
	var scored: Array = []
	for v in vacant:
		var d := _dist_to_segment(v.center, pts[0], pts[pts.size() - 1])
		if d <= NEAR_M:
			scored.append([d, v.id])
	scored.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0] or (x[0] == y[0] and x[1] < y[1]))
	var out := PackedInt64Array()
	for k in mini(count, scored.size()):
		out.append(int(scored[k][1]))
	return out


func _dist_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var len2 := ab.length_squared()
	var t := 0.0 if len2 <= 0.0 else clampf((p - a).dot(ab) / len2, 0.0, 1.0)
	return p.distance_to(a + ab * t)


func _parse(args: PackedStringArray) -> Dictionary:
	var out := {}
	for a in args:
		if a.begins_with("--"):
			var kv := a.trim_prefix("--").split("=", true, 1)
			out[kv[0]] = kv[1] if kv.size() > 1 else "1"
	return out


## Olay ve bölge yükü toplayıcı.
class _Rec:
	extends RefCounted
	const TRACK := ["event.council.vote_opened", "event.council.vote_passed", "event.council.vote_failed",
		"event.zoning.applied", "event.zoning.plan_rejected", "event.road.built", "event.construction.started",
		"event.construction.completed", "event.zoning.proposed"]
	var facade: SimFacadeImpl = null
	var pump: SimBuildingPump = null
	var cfg: EconomyConfig = null
	var region: String = ""
	var load_series: Array = []
	var by_key: Dictionary = {}
	var counts: Dictionary = {}
	var kinds: Dictionary = {}
	var dumps: Array = []
	var strip_rows: Array = []
	var pol_events: Array = []
	var agenda_seen: Dictionary = {}
	var _seq: int = 0

	func step() -> void:
		facade.advance(1)
		if pump != null:
			pump.frame(true, Callable(self, "_noop"))
			pump.frame(false, Callable(self, "_noop"))
		for e in facade.events_since(_seq):
			_seq = maxi(_seq, e.seq)
			var key := String(e.message_key)
			counts[key] = int(counts.get(key, 0)) + 1
			kinds[String(e.kind)] = int(kinds.get(String(e.kind), 0)) + 1
			if String(e.kind).begins_with("politics.") or String(e.kind) == "group.reacted" or key == "event.media.published":
				pol_events.append([e.tick, String(e.kind), key, str(e.args.get("template", e.args.get("topic", ""))),
					Array(e.subjects).slice(0, 3).map(func(x: Variant) -> String: return str(x))])
			if key.begins_with("event.council.") or key.begins_with("event.zoning."):
				if not NotificationStrip.is_unplanned_decline(e) and strip_rows.size() < 40:
					strip_rows.append([e.tick, key, NotificationStrip.priority(e)])
			if TRACK.has(key):
				if not by_key.has(key):
					by_key[key] = []
				var subj: Array = []
				for s in e.subjects:
					subj.append(String(s))
				(by_key[key] as Array).append({"t": e.tick, "s": subj.slice(0, 3), "n": e.subjects.size(),
						"a": SimContract.to_args(e.args) if not e.args.is_empty() else {}})
		for it in facade.agenda_items():
			if not agenda_seen.has(it.item_id):
				agenda_seen[it.item_id] = {"id": it.item_id, "template": String(it.template_id), "opened": it.opened_tick,
					"deadline": it.deadline_tick, "delivery": String(it.delivery), "title_key": String(it.title_key),
					"region": String(it.region_code), "cause_refs": Array(it.cause_refs).slice(0, 4).map(
						func(x: Variant) -> String: return str(x))}
			agenda_seen[it.item_id]["status_last"] = String(it.status)
			agenda_seen[it.item_id]["last_tick"] = facade.current_tick()
		if (counts.get("event.council.vote_passed", 0) + counts.get("event.council.vote_failed", 0)) > dumps.size():
			# gerekçe halkası sınırlıdır (~3400 yatırımcı kaydı/400 gün): oy gerekçelerini çözüldüğü AN oku
			var rep := votes_report(facade, null)
			var load_now := d2_load_pm()
			for v: Dictionary in rep:
				if v["resolved"] == facade.current_tick():
					v["d2_load_pm_at_resolve"] = load_now
					dumps.append(v)
		if facade.current_tick() % 10 == 0:
			load_series.append([facade.current_tick(), d2_load_pm()])

	func _noop(_c: Variant, _v: Variant) -> void:
		pass

	func d2_load_pm() -> int:
		for row in EconomyQuery.region_stats(facade.game_state(), cfg):
			if String(row["code"]) == region:
				return int(row["infra_load_pm"])
		return -1

	func first(key: String) -> int:
		var list: Array = by_key.get(key, [])
		return int(list[0]["t"]) if not list.is_empty() else -1

	func ticks_of(key: String) -> Array:
		var out: Array = []
		for item: Dictionary in by_key.get(key, []):
			out.append(int(item["t"]))
		return out

	## Olay özeti: mutlak tick'ler + plan gönderiminden (t_plan) göreli günler.
	func summary(t_start: int, t_plan: int) -> Dictionary:
		var out := {"counts_all_keys": counts, "kinds": kinds}
		for key: String in TRACK:
			var list: Array = by_key.get(key, [])
			var abs_ticks: Array = []
			for item: Dictionary in list:
				abs_ticks.append(int(item["t"]))
			out[key] = {"n": list.size(), "abs_first12": abs_ticks.slice(0, 12),
				"rel_plan_first12": abs_ticks.slice(0, 12).map(func(t: int) -> int: return t - t_plan)}
		out["t_start"] = t_start
		out["t_plan"] = t_plan
		# plan parsellerinde (event.zoning.applied özneleri) / genel inşaat sayıları
		out["construction_started_total"] = (by_key.get("event.construction.started", []) as Array).size()
		out["construction_completed_total"] = (by_key.get("event.construction.completed", []) as Array).size()
		out["vote_events"] = {"opened": by_key.get("event.council.vote_opened", []),
			"passed": by_key.get("event.council.vote_passed", []), "failed": by_key.get("event.council.vote_failed", []),
			"plan_rejected": _brief(by_key.get("event.zoning.plan_rejected", [])),
			"applied": _brief(by_key.get("event.zoning.applied", []))}
		return out

	func _brief(list: Array) -> Array:
		var out: Array = []
		for item: Dictionary in list:
			out.append({"t": item["t"], "n": item["n"], "a": item["a"]})
		return out

	## Oylama kayıtları (durumdan): kimlik, açılış/kapanış, sonuç, oylar, üye gerekçe faktörleri, `route`.
	func votes_report(f: SimFacadeImpl, _handle: PoliticsHandle) -> Array:
		var out: Array = []
		var votes: Array = PoliticsState.data(f.game_state()).get("council", {}).get("votes", [])
		for vote: Dictionary in votes:
			var members: Array = []
			for pos: Dictionary in vote["positions"]:
				var row := {"member": String(pos["member"]), "pos": String(pos["position"])}
				var rid := int(pos["reason_id"])
				if rid > 0:
					var rr := f.reason(rid)
					if rr != null:
						row["score"] = rr.score
						row["threshold"] = rr.threshold
						var fac := {}
						for fx in rr.factors:
							fac[String(fx.name_key)] = [fx.value, fx.weight, fx.contribution()]
						row["factors"] = fac
				members.append(row)
			out.append({"id": vote["id"], "kind": vote["kind"], "opened": vote["opened_tick"], "closes": vote["closes_tick"],
				"resolved": vote["resolved_tick"], "status": vote["status"], "yes": vote["yes"], "no": vote["no"],
				"abstain": vote["abstain"], "applied": vote["applied"], "parcels": (vote["proposal"]["parcel_ids"] as Array).size(),
				"route": vote["proposal"].get("route", {}), "context_regions": vote["context"].get("regions", []),
				"members": members})
		return out
