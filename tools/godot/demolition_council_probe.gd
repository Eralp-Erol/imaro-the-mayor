# gdlint:disable=max-line-length
extends SceneTree
## 2026-11-05 · Yıkım sonrası halk tepkisi / güven -> MECLİS OYLAMASI ölçümü, GERÇEK Ismeral D2 (düzeltme DEĞİL; src/sim'e
## dokunmaz). Aynı tohum, aynı 12 parsel, aynı imar türü; tek fark kamulaştırmalı yol (yıkım) ve onun yıkımı:
##   A = yol yok (taban)   B = kamulaştırmalı yol (binalar yıkılır, aileler yerinden olur)   C = B + yol 5. günde yıkılır
##   D = DOZ TESTİ: en çok hane yerinden eden `--stress-roads` (varsayılan 6) yol art arda (yalnız `--arms=...D` ile)
## `gap`: yoldan (A'da aynı süre sonra) imar teklifine kadar gün. Kurulum `qa_world_support.gd` (oyunun siyaset/ekonomi
## yapılandırması + GERÇEK kamulaştırma köprüsü). Gürültüsüz üye marjı = `CouncilEngine.forecast` ile aynı hesap
## (`draw: 0`); gerçek oy gürültülüdür. Çalıştır:
##   tools/godot.sh --headless --path . --script res://tools/godot/demolition_council_probe.gd -- \
##       [--arms=A,B,C] [--stress-roads=6] [--sim-seeds=1..] [--zones=zone.green,zone.residential,zone.mixed] [--gaps=2,25] [--pick=q90] [--plan-n=12] [--warm=30]
## Çıktı: `DC_SETUP`, `DC_RUN` (senaryo), `DC_DONE`.

const Support := preload("res://tests/sim/perf/qa_world_support.gd")
const REGION := "D2"
const NEAR_M := 150.0
const MAX_VOTE_DAYS := 30

var _args: Dictionary = {}
var _vacant: Array[ParcelView] = []


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		_args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var control := WorldControlData.load_dir(Support.DATA_DIR)
	var world_seed := int(_args.get("world-seed", str(int(control["world"]["default_seed"]))))
	var w := Support.build_world(world_seed)
	var occupied := {}
	for pid in w.settlement.columns.occupied_parcels():
		occupied[int(pid)] = true
	for v in w.views:
		if not occupied.has(v.id):
			_vacant.append(v)
	var seeds: PackedStringArray = str(_args.get("sim-seeds", "1,2,3,4,5,6")).split(",")
	var zones: PackedStringArray = str(_args.get("zones", "zone.green,zone.residential")).split(",")
	var gaps: PackedStringArray = str(_args.get("gaps", "2,25")).split(",")
	var warm := int(_args.get("warm", str(Support.WARM_DAYS)))
	var plan_n := int(_args.get("plan-n", "12"))
	# Yol adayı: tohumdan bağımsız bir kez (ilk simin önizlemesiyle)
	var s0 := Support.new_sim(w, int(seeds[0]))
	s0.step(warm)
	var tally := {}
	var cands := Support.region_candidates(w, s0, REGION, int(_args.get("pool", "150")), "t067_queue_probe", tally)
	cands = cands.filter(func(c: Dictionary) -> bool: return int(c["hh"]) > 0)
	cands.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
		if int(x["hh"]) != int(y["hh"]):
			return int(x["hh"]) < int(y["hh"])
		return int(x["order"]) < int(y["order"]))
	if cands.is_empty():
		push_error("aday yol yok")
		quit(3)
		return
	var cand: Dictionary = cands[_pick_index(cands.size(), str(_args.get("pick", "q90")))]
	var pts: PackedVector2Array = cand["pts"]
	var taken := {}
	for pid in RoadDraftCheck.taken_parcels(w.net, pts, RoadDrawTool.ROAD_CLASS):
		taken[int(pid)] = true
	var plan_ids := _nearest_vacant(pts, plan_n, taken)
	print("DC_SETUP ", JSON.stringify({"world_seed": world_seed, "seeds": seeds, "zones": zones, "gaps": gaps, "road": {"len_m": snappedf(float(cand["len"]), 0.1), "taken": cand["taken"],
		"built": cand["built"], "hh": cand["hh"], "near_hh": cand["near_hh"]}, "plan_parcels": plan_ids.size(), "candidates": cands.size()}))
	if plan_ids.size() < 10:
		push_error("plan parseli yetersiz: %d" % plan_ids.size())
		quit(4)
		return
	var stress: Array = []
	for k in int(_args.get("stress-roads", "6")):
		if cands.size() - 1 - k >= 0:
			stress.append((cands[cands.size() - 1 - k] as Dictionary)["cm"])
	var arms: PackedStringArray = str(_args.get("arms", "A,B,C")).split(",")
	for gap_s in gaps:
		var gap := int(gap_s)
		for zone_s in zones:
			for sd in seeds:
				for arm in arms:
					if (arm == "C" or arm == "D") and gap < 10:
						continue
					_scenario(w, int(sd), String(zone_s), arm, gap, warm, cand, plan_ids, stress)
	print("DC_DONE")
	quit(0)


func _pick_index(n: int, pick: String) -> int:
	match pick:
		"max":
			return n - 1
		"q90":
			return mini(n - 1, n * 9 / 10)
		"q50":
			return n / 2
	return clampi(int(pick), 0, n - 1)


func _scenario(w: Support.WorldCtx, seed_i: int, zone: String, arm: String, gap: int, warm: int, cand: Dictionary, plan_ids: PackedInt64Array, stress: Array) -> void:
	var s := Support.new_sim(w, seed_i)
	s.step(warm)
	var road_status := "-"
	var demolish_status := "-"
	if arm == "D":
		var ok_n := 0
		for cm: PackedInt64Array in stress:
			var dr := s.facade.submit_command(SimCommand.public_work_road(cm, RoadDrawTool.ROAD_CLASS, true))
			ok_n += 0 if dr.is_rejected() else 1
			s.step(1)
		road_status = "%d/%d kabul" % [ok_n, stress.size()]
		s.step(gap - stress.size())
	elif arm != "A":
		var rr := s.facade.submit_command(SimCommand.public_work_road(cand["cm"], RoadDrawTool.ROAD_CLASS, true))
		road_status = "%s %s" % [rr.status, rr.reason_key]
	if arm == "D":
		pass
	elif arm == "C":
		s.step(5)
		var works := s.facade.public_works()
		if not works.is_empty():
			var dr := s.facade.submit_command(SimCommand.public_work_demolish(works[works.size() - 1].command_id))
			demolish_status = "%s %s" % [dr.status, dr.reason_key]
		s.step(gap - 5)
	else:
		s.step(gap)
	var pre := _pre_state(s)
	var plan := s.facade.submit_command(SimCommand.zoning_propose(plan_ids, StringName(zone)))
	var first_fc := {}
	var last_fc := {}
	var votes: Array = []
	for _d in MAX_VOTE_DAYS:
		s.step(1)
		votes = PoliticsState.data(s.facade.game_state())["council"]["votes"]
		if votes.is_empty():
			continue
		var v: Dictionary = votes[votes.size() - 1]
		if v["status"] == "pending":
			var fc := _noise_free(s, v)
			if first_fc.is_empty():
				first_fc = fc
			last_fc = fc
		else:
			break
	var out := {"arm": arm, "zone": zone, "sim_seed": seed_i, "gap": gap, "road": road_status, "demolish": demolish_status, "plan": "%s %s" % [plan.status, plan.reason_key],
		"pre": pre, "events": {"group_reacted": s.group_reacted.size(), "counts": s.counts}}
	if votes.is_empty():
		out["vote"] = "none"
	else:
		var v: Dictionary = votes[votes.size() - 1]
		var why: Dictionary = v.get("why", {})
		var fac := {}
		for f: Dictionary in why.get("factors", []):
			fac[String(f["name"]).trim_prefix("reason.factor.")] = int(f["net"])
		var members: Array = []
		for pos: Dictionary in v["positions"]:
			var rec := s.facade.reason(int(pos["reason_id"]))
			var fr := {}
			if rec != null:
				for fx in rec.factors:
					fr[String(fx.name_key).trim_prefix("reason.factor.")] = fx.contribution()
			members.append({"m": String(pos["member"]), "pos": String(pos["position"]), "score": rec.score if rec != null else null, "thr": rec.threshold if rec != null else null, "contrib": fr})
		out["vote"] = {"status": String(v["status"]), "yes": v["yes"], "no": v["no"], "abstain": v["abstain"], "infra_load_pm": why.get("infra_load_pm", -1),
			"why_net": fac, "members": members, "opened": v["opened_tick"], "resolved": v["resolved_tick"]}
		out["forecast_first"] = first_fc
		out["forecast_last"] = last_fc
	print("DC_RUN ", JSON.stringify(out))
	# ağı taban grafına döndür
	var guard := 0
	while not w.net.delta.ops.is_empty() and guard < 12:
		var undone := s.ctx.undo_live_op()
		print("DC_UNDO arm=%s ok=%s %s ops_left=%d" % [arm, str(undone["ok"]), str(undone.get("error", "")), w.net.delta.ops.size()])
		if not bool(undone["ok"]):
			break
		guard += 1
	if w.net.graph_hash() != w.base_hash or not w.net.delta.ops.is_empty():
		push_error("ağ taban grafına dönmedi (arm %s seed %d)" % [arm, seed_i])
		print("DC_NET_NOT_RESTORED arm=%s seed=%d" % [arm, seed_i])


## Teklif öncesi: üye güveni/kızgınlığı + kesim G/S + D2 yük + yerinden edilenler.
func _pre_state(s: Support.SimCtx) -> Dictionary:
	var st := s.facade.game_state()
	var player := ActorStore.protagonist_key(st, s.handle.context.actors)
	var trust := {}
	for k in 5:
		var mk := "actor.council.%d" % (k + 1)
		if ActorStore.has_actor(st, mk):
			var rel := ActorStore.relation(st, s.handle.context.actors, mk, player)
			trust[mk] = {"trust": int(rel["trust"]), "resentment": int(rel["resentment"]), "obligation": int(rel["obligation"])}
	var blocs := {}
	var pol := PoliticsState.data(st)
	for bk: String in pol["blocs"]:
		var b: Dictionary = pol["blocs"][bk]
		blocs[bk] = {"G": int(b.get("G", 0)), "S": int(b.get("S", 0))}
	var displaced := 0
	for code: String in s.displaced_book():
		for row: Array in s.displaced_book()[code]:
			displaced += int(row[1])
	return {"tick": s.tick(), "council_relation": trust, "blocs": blocs, "d2_infra_load_pm": s.region_stat("D2", "infra_load_pm"), "displaced_hh_book": displaced}


## `CouncilEngine.forecast` ile aynı hesap (draw 0), üye marjları ve etken katkılarıyla.
func _noise_free(s: Support.SimCtx, vote: Dictionary) -> Dictionary:
	var st := s.facade.game_state()
	var ctx := s.handle.context
	var cfg: Dictionary = ctx.politics.council
	var table := ctx.actors.table(cfg["decision"])
	var player := ActorStore.protagonist_key(st, ctx.actors)
	var members: Array = []
	var yes := 0
	var no := 0
	var abstain := 0
	for position: Dictionary in vote["positions"]:
		var key := String(position["member"])
		var actor := ActorStore.actor_ref(st, key)
		var factors := CouncilEngine.member_factors(st, ctx, key, vote, player)
		var result := ActorDecision.decide(factors, table, {"traits": actor["traits"], "draw": 0, "noise_trait": ctx.actors.noise_trait, "previous_positive": false})
		if not result["ok"]:
			abstain += 1
			continue
		var contrib := {}
		for f: Dictionary in result["factors"]:
			var nm := String(f["name"]).trim_prefix("reason.factor.")
			contrib[nm] = SimContract.contribution(int(f["value"]), int(f["weight"]))
		members.append({"m": key, "margin": int(result["margin"]), "score": int(result["score"]), "contrib": contrib})
		if absi(int(result["margin"])) <= int(cfg["abstain_band"]):
			abstain += 1
		elif result["outcome"] == ReasonLog.OUTCOME_POSITIVE:
			yes += 1
		else:
			no += 1
	return {"tick": s.tick(), "yes": yes, "no": no, "abstain": abstain, "members": members}


func _nearest_vacant(pts: PackedVector2Array, count: int, exclude: Dictionary) -> PackedInt64Array:
	var scored: Array = []
	for v in _vacant:
		if exclude.has(v.id):
			continue
		var d := _dist_to_segment(v.center, pts[0], pts[pts.size() - 1])
		if d <= NEAR_M * 2.0:
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
