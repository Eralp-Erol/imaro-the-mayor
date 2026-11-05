# gdlint:disable=max-line-length
extends SceneTree
## 2026-11-05 · GRUP TEPKİSİ ölçümü, GERÇEK Ismeral D2 (düzeltme DEĞİL; src/sim'e dokunmaz). Soru (design-director M2 kapanış
## incelemesi): belediye kararından (kamulaştırmalı yol, yıkım, imar, politika) sonra >= 2 FARKLI grup (seçmen kesimi/kohort)
## tepki kaydı/olayı üretiyor mu; gerekçe kaydı (SIM-12) var mı; tepki karara BAĞLI mı (kararsız taban çizgisiyle)?
## Kurulum `tests/sim/perf/qa_world_support.gd` (oyunun siyaset/ekonomi yapılandırması, yetki alanı D2, GERÇEK kamulaştırma
## köprüsü). Senaryolar (aynı yol adayı + aynı 12 imar parseli, dünya tohumu başına):
##   base       karar YOK (taban çizgisi)            road     kamulaştırmalı yol (1. gün)
##   zone       yalnız imar (konut, 12 parsel)        road_zone yol + imar (3. gün)
##   policy     yeniden iskân politikası AÇ + yol + imar   demolish yol (1. gün) + yol yıkımı (8. gün)
##   zone_mixed yalnız imar (karma)
## Çalıştır (kilit + nice ile):
##   tools/godot.sh --headless --path . --script res://tools/godot/group_reaction_probe.gd -- \
##       [--world-seed=N] [--sim-seeds=1] [--days=200] [--scenarios=base,road,zone,road_zone,policy,demolish] [--pick=q90] [--plan-n=12]
## Çıktı: `GR_SETUP`, `GR_RUN` (senaryo özeti, JSON), `GR_DONE`.

const Support := preload("res://tests/sim/perf/qa_world_support.gd")
const REGION := "D2"
const NEAR_M := 150.0
const CHAIN_DEPTH := 6

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
	var seeds: PackedStringArray = str(_args.get("sim-seeds", "1")).split(",")
	var days := int(_args.get("days", "200"))
	var warm := int(_args.get("warm", str(Support.WARM_DAYS)))
	var names: PackedStringArray = str(_args.get("scenarios", "base,road,zone,road_zone,policy,demolish")).split(",")
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
	var plan_ids := _nearest_vacant(pts, int(_args.get("plan-n", "12")), taken)
	print("GR_SETUP ", JSON.stringify({"world_seed": world_seed, "sim_seeds": seeds, "days": days, "scenarios": names,
		"road": {"len_m": snappedf(float(cand["len"]), 0.1), "taken": cand["taken"], "built": cand["built"], "hh": cand["hh"], "near_hh": cand["near_hh"]},
		"plan_parcels": plan_ids.size(), "taken_ids": taken.keys(), "candidates": cands.size()}))
	if plan_ids.size() < 10:
		push_error("plan parseli yetersiz: %d" % plan_ids.size())
		quit(4)
		return
	for sd in seeds:
		for nm in names:
			_scenario(w, int(sd), String(nm), warm, days, cand, plan_ids, taken)
	print("GR_DONE")
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


func _scenario(w: Support.WorldCtx, seed_i: int, nm: String, warm: int, days: int, cand: Dictionary, plan_ids: PackedInt64Array, taken: Dictionary) -> void:
	var s := Support.new_sim(w, seed_i)
	s.step(warm)
	var decisions: Array = []  # {day, kind, status, command_id}
	var refs := {}  # kararın bağlı olduğu varlık referansları
	var work_cmd := -1
	var road_day := 1 if nm in ["road", "road_zone", "policy", "demolish"] else -1
	var zone_day := 3 if nm in ["road_zone", "policy"] else (1 if nm in ["zone", "zone_mixed"] else -1)
	var demolish_day := 8 if nm == "demolish" else -1
	var policy_day := 1 if nm == "policy" else -1
	var road_ok := true
	var ev_rows: Array = []  # group.reacted olayları (gerekçe zinciriyle)
	var per_group := {}  # kesim -> {max_i, nonneutral_days, first_tick, reaction_set, last_nonneutral_refs}
	var agenda_open: Dictionary = {}
	var bloc_trace: Array = []
	var pre_blocs := _bloc_gs(s)
	for d in range(1, days + 1):
		if d == policy_day:
			var pr := s.facade.submit_command(SimCommand.policy_set(PolicyView.ID_RESETTLEMENT, true))
			decisions.append({"day": d, "kind": "policy.set", "status": String(pr.status), "reason": String(pr.reason_key)})
		if d == road_day:
			var rr := s.facade.submit_command(SimCommand.public_work_road(cand["cm"], RoadDrawTool.ROAD_CLASS, true))
			decisions.append({"day": d, "kind": "road", "status": String(rr.status), "reason": String(rr.reason_key), "command_id": rr.command_id})
			road_ok = not rr.is_rejected()
			if road_ok:
				refs["command.%d" % rr.command_id] = "road"
				for pid: int in taken:
					refs["parcel.%d" % pid] = "road_taken"
		if d == zone_day:
			var zone := "zone.mixed" if nm == "zone_mixed" else "zone.residential"
			var zr := s.facade.submit_command(SimCommand.zoning_propose(plan_ids, StringName(zone)))
			decisions.append({"day": d, "kind": "zoning", "status": String(zr.status), "reason": String(zr.reason_key), "command_id": zr.command_id, "zone": zone, "parcels": plan_ids.size()})
			for pid in plan_ids:
				refs["parcel.%d" % pid] = "plan"
			refs["command.%d" % zr.command_id] = "zoning"
		if d == demolish_day and road_ok:
			var works := s.facade.public_works()
			if not works.is_empty():
				var dr := s.facade.submit_command(SimCommand.public_work_demolish(works[works.size() - 1].command_id))
				decisions.append({"day": d, "kind": "demolish", "status": String(dr.status), "reason": String(dr.reason_key), "command_id": dr.command_id})
				refs["command.%d" % dr.command_id] = "demolish"
		var seq0 := s.seen_event_seq
		s.step(1)
		for e in s.facade.events_since(seq0):
			if String(e.kind) != "group.reacted":
				continue
			ev_rows.append(_event_row(s, e))
		for g in PoliticsQuery.group_views(s.facade.game_state()):
			var gk := String(g.group.key) if g.group != null else "?"
			var pg: Dictionary = per_group.get(gk, {"max_i": 0, "nonneutral_days": 0, "first_tick": -1, "reactions": {}, "refs": []})
			if String(g.reaction) != "neutral" or g.intensity > 0:
				pg["nonneutral_days"] = int(pg["nonneutral_days"]) + 1
				if int(pg["first_tick"]) < 0:
					pg["first_tick"] = g.tick
				pg["max_i"] = maxi(int(pg["max_i"]), g.intensity)
				pg["reactions"][String(g.reaction)] = true
				pg["refs"] = Array(g.cause_refs)
			per_group[gk] = pg
		for it in s.facade.agenda_items():
			if not agenda_open.has(it.item_id):
				agenda_open[it.item_id] = {"template": String(it.template_id), "opened": it.opened_tick, "region": String(it.region_code), "cause_refs": Array(it.cause_refs).slice(0, 4), "reason_ids": Array(it.reason_ids).size()}
		if d % 20 == 0:
			bloc_trace.append({"day": d, "blocs": _bloc_gs(s)})
	# Özet
	var groups_out := {}
	var linked := {}
	for gk: String in per_group:
		var pg: Dictionary = per_group[gk]
		var is_linked := false
		for r: String in pg["refs"]:
			if refs.has(r):
				is_linked = true
		var ev_n := 0
		var ev_nonneutral := 0
		var ev_with_reason := 0
		var ev_consistent := 0
		for row: Dictionary in ev_rows:
			if row["group"] == gk:
				ev_n += 1
				if String(row["message"]) != "event.group.calmed":
					ev_nonneutral += 1
				if int(row["reason_n"]) > 0:
					ev_with_reason += 1
				if bool(row["consistent"]):
					ev_consistent += 1
		groups_out[gk] = {"max_intensity": pg["max_i"], "nonneutral_days": pg["nonneutral_days"], "first_tick": pg["first_tick"], "reactions": pg["reactions"].keys(),
			"refs_end": (pg["refs"] as Array).slice(0, 6), "refs_linked_to_decision": is_linked, "events": ev_n, "events_nonneutral": ev_nonneutral,
			"events_with_reason": ev_with_reason, "events_reason_consistent": ev_consistent}
		if is_linked and (int(pg["max_i"]) > 0 or ev_nonneutral > 0):
			linked[gk] = true
	var reacting: Array = []
	var reacting_events: Array = []
	for gk: String in groups_out:
		var go: Dictionary = groups_out[gk]
		var non_neutral: Array = (go["reactions"] as Array).filter(func(r: Variant) -> bool: return String(r) != "neutral")
		if int(go["max_intensity"]) > 0 or not non_neutral.is_empty():
			reacting.append(gk)
		if int(go["events_nonneutral"]) > 0:
			reacting_events.append(gk)
	var out := {"scenario": nm, "sim_seed": seed_i, "world_seed": w.world_seed, "days": days, "decisions": decisions, "road_ok": road_ok, "pre_blocs": pre_blocs, "end_blocs": _bloc_gs(s),
		"groups": groups_out, "groups_reacting_view": reacting, "groups_reacting_event": reacting_events, "groups_linked": linked.keys(),
		"group_events_total": ev_rows.size(), "group_events": ev_rows.slice(0, 24), "agenda": agenda_open.values(), "bloc_trace": bloc_trace,
		"counts": s.counts, "state_hash": s.facade.state_hash()}
	print("GR_RUN ", JSON.stringify(out))
	# ağı taban grafına döndür
	var guard := 0
	while not w.net.delta.ops.is_empty() and guard < 12:
		var undone := s.ctx.undo_live_op()
		if not bool(undone["ok"]):
			break
		guard += 1
	if w.net.graph_hash() != w.base_hash or not w.net.delta.ops.is_empty():
		push_error("ağ taban grafına dönmedi (%s seed %d)" % [nm, seed_i])
		print("GR_NET_NOT_RESTORED ", nm, " ", seed_i)


## `group.reacted` olayı + gerekçe kaydı ve ana zinciri (SIM-12).
func _event_row(s: Support.SimCtx, e: SimEvent) -> Dictionary:
	var chain: Array = []
	var consistent := true
	var reason_n := 0
	var outcome := ""
	var frontier: Array = Array(e.reason_ids)
	var depth := 0
	var seen := {}
	while not frontier.is_empty() and depth < CHAIN_DEPTH:
		var next: Array = []
		for rid in frontier:
			if seen.has(rid):
				continue
			seen[rid] = true
			var rec := s.facade.reason(int(rid))
			if rec == null:
				continue
			if depth == 0:
				reason_n += 1
				outcome = String(rec.outcome)
				consistent = consistent and rec.is_consistent()
			if not chain.has(String(rec.decision_key)):
				chain.append(String(rec.decision_key))
			next.append_array(Array(rec.parent_ids))
		frontier = next
		depth += 1
	return {"tick": e.tick, "group": String(e.actor.key) if e.actor != null else "?", "message": String(e.message_key), "topic": str(e.args.get("topic", "")),
		"intensity": int(e.args.get("intensity", 0)), "tier": str(e.args.get("tier", "")), "subjects": Array(e.subjects).slice(0, 4), "reason_n": reason_n,
		"outcome": outcome, "consistent": consistent, "chain": chain}


func _bloc_gs(s: Support.SimCtx) -> Dictionary:
	var out := {}
	var pol := PoliticsState.data(s.facade.game_state())
	for bk: String in pol["blocs"]:
		var b: Dictionary = pol["blocs"][bk]
		out[bk] = {"G": int(b.get("G", 0)), "S": int(b.get("S", 0)), "size": int(b.get("size", 0))}
	return out


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
