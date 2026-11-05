# gdlint:disable=max-line-length
extends SceneTree
## 2026-11-05 · T-067 bekleme listesi ÖLÇÜMÜ, GERÇEK Ismeral D2 (düzeltme DEĞİL; src/sim'e dokunmaz). Soru: yeniden iskân
## politikası AÇIKKEN, yol kamulaştırması sonrası "unplaced" aileler yatırımcının bitirdiği yeni konutla listeden ev
## alıyor mu; `max(res_built - latent_hh, 0)` sınırı listeyi pratikte boş mu bırakıyor?
## Kurulum `tests/sim/perf/qa_world_support.gd` (oyunun siyaset/ekonomi yapılandırması + yol yetki alanı + GERÇEK
## kamulaştırma köprüsü; oyunla aynı bağ). Politika `policy.set` komutuyla AÇILIR (oyuncunun gerçek eylemi).
## Çalıştır (kilit + nice ile; bkz. production/log/2026-11-05-bekleme-listesi-meclis-olcum.md):
##   tools/godot.sh --headless --path . --script res://tools/godot/resettlement_queue_probe.gd -- \
##       [--sim-seeds=3,7,11] [--picks=max,q90,q50] [--days=200] [--pool=150] [--warm=30] [--policy=on|off] [--world-seed=N]
##       [--fate=leave]   (KARŞI-OLGUSAL, gönderilen veri DEĞİL: hane kaderi `leave_region`; sınırın `max(res_built - latent_hh, 0)` ayağını sınar)
##       [--plan-zone=zone.residential --plan-n=8 --plan-batches=4 --plan-every=20]   (yoldan sonra yola en yakın boş parsellere imar
##        teklifleri; boşsa HİÇ imar yok = yatırımcı konut bitirmez, kuyruk beslenemez)
## Çıktı: `RQ_SETUP`, `RQ_RUN` (senaryo özeti), `RQ_OPP` (sınır analizi satırları), `RQ_SERIES` (zaman serisi), `RQ_DONE`.

const Support := preload("res://tests/sim/perf/qa_world_support.gd")
const REGION := "D2"
const SERIES_EVERY := 10
const OPP_LOG_MAX := 12

var _args: Dictionary = {}
var _vacant: Array[ParcelView] = []
var _plan_log: Array = []


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
	var seeds: PackedStringArray = str(_args.get("sim-seeds", "3,7,11")).split(",")
	var picks: PackedStringArray = str(_args.get("picks", "max,q90,q50")).split(",")
	var days := int(_args.get("days", "200"))
	var warm := int(_args.get("warm", str(Support.WARM_DAYS)))
	var policy_on := str(_args.get("policy", "on")) == "on"
	var pool := int(_args.get("pool", "150"))
	print("RQ_SETUP ", JSON.stringify({"world_seed": world_seed, "sim_seeds": seeds, "picks": picks, "days": days, "warm": warm,
		"policy_on": policy_on, "pool": pool, "fate": str(_args.get("fate", "data")), "jurisdiction": str(w.game_jurisdiction)}))
	var cands: Array = []
	for sd in seeds:
		var seed_i := int(sd)
		for pick in picks:
			var s := Support.new_sim(w, seed_i)
			if s == null:
				push_error("sim kurulamadı")
				quit(2)
				return
			s.step(warm)
			if cands.is_empty():
				var tally := {}
				cands = Support.region_candidates(w, s, REGION, pool, "t067_queue_probe", tally)
				cands = cands.filter(func(c: Dictionary) -> bool: return int(c["hh"]) > 0)
				cands.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
					if int(x["hh"]) != int(y["hh"]):
						return int(x["hh"]) < int(y["hh"])
					return int(x["order"]) < int(y["order"]))
				print("RQ_CANDS ", JSON.stringify({"n": cands.size(), "hh": cands.map(func(c: Dictionary) -> int: return int(c["hh"])), "tally": tally}))
				if cands.is_empty():
					push_error("aday yol yok")
					quit(3)
					return
			var cand: Dictionary = cands[_pick_index(cands.size(), pick)]
			_scenario(w, s, seed_i, pick, cand, days, policy_on)
			var restored := w.restore_net(s.ctx, 1)
			print("RQ_NET_RESTORED ", restored)
			if not restored:
				push_error("ağ taban grafına dönmedi; sonraki senaryolar geçersiz olabilir")
	print("RQ_DONE")
	quit(0)


func _pick_index(n: int, pick: String) -> int:
	match pick:
		"max":
			return n - 1
		"q90":
			return mini(n - 1, n * 9 / 10)
		"q50":
			return n / 2
		"q10":
			return n / 10
	return clampi(int(pick), 0, n - 1)


func _cols(s: Support.SimCtx) -> Dictionary:
	var r: Dictionary = EconomyState.data(s.facade.game_state())["regions"]
	return {"codes": r["codes"], "built": (r["res_built"] as PackedInt64Array).duplicate(), "latent": (r["latent_hh"] as PackedInt64Array).duplicate()}


func _records(s: Support.SimCtx) -> Dictionary:
	return PublicWorksState.resettlement_records(s.facade.game_state())


func _served_rows(s: Support.SimCtx) -> Array:
	var rows: Array = []
	for cid: int in _records(s):
		for row: Array in (_records(s)[cid] as Dictionary).get("served", []):
			rows.append(row.duplicate())
	return rows


func _scenario(w: Support.WorldCtx, s: Support.SimCtx, seed_i: int, pick: String, cand: Dictionary, days: int, policy_on: bool) -> void:
	if str(_args.get("fate", "")) == "leave":
		s.ctx.config.household_fate = ParcelExpropriation.FATE_LEAVE
	var pol_status := "skipped"
	if policy_on:
		var pr := s.facade.submit_command(SimCommand.policy_set(PolicyView.ID_RESETTLEMENT, true))
		pol_status = "%s %s" % [pr.status, pr.reason_key]
		s.step(1)
	var rr := s.facade.submit_command(SimCommand.public_work_road(cand["cm"], RoadDrawTool.ROAD_CLASS, true))
	var road_status := "%s %s" % [rr.status, rr.reason_key]
	s.step(1)
	var recs := _records(s)
	var first_record := {}
	for cid: int in recs:
		first_record = (recs[cid] as Dictionary).duplicate(true)
	var c0 := _cols(s)
	var codes: PackedStringArray = c0["codes"]
	var head := {"sim_seed": seed_i, "pick": pick, "road_len_m": snappedf(float(cand["len"]), 0.1), "preview_taken": cand["taken"], "preview_built": cand["built"],
		"preview_hh": cand["hh"], "policy_set": pol_status, "road": road_status, "t_road": s.tick(),
		"record0": {"unplaced": first_record.get("unplaced", -1), "rehoused": first_record.get("rehoused", -1), "partial": first_record.get("partial", -1),
			"unplaced_by": first_record.get("unplaced_by", {}), "displaced": first_record.get("displaced", first_record.get("households", -1))}}
	# Kurulu gün-0 durumu (bekleyen bölgeler)
	var wait0: Dictionary = ResettlementQueue.waiting_by_region(s.facade.game_state())
	var region0 := {}
	for code: String in wait0:
		var i := codes.find(code)
		region0[code] = {"waiting": wait0[code], "built": c0["built"][i], "latent": c0["latent"][i], "vacancy": maxi(c0["built"][i] - c0["latent"][i], 0)}
	head["waiting0"] = ResettlementQueue.waiting_total(s.facade.game_state())
	head["region0"] = region0
	head["city_vacancy0"] = _city_vacancy(c0)
	var plan_batches: Array = _plan_batches(w, cand)
	_plan_log = []
	var series: Array = []
	var served_seen := _served_rows(s).size()
	var fresh_total := 0
	var fresh_days := 0
	var opp_days := 0
	var pairs := 0
	var pairs_vac_zero := 0
	var pairs_vac_pos := 0
	var pairs_served := 0
	var served_events := 0
	var records_same_tick := 0  # her verilen ev satırı için aynı gün yazılan gerekçe kaydı (toplam; budanmadan sayılır)
	var served_hh := 0
	var opp_log: Array = []
	var first_serve_day := -1
	var waiting_min := ResettlementQueue.waiting_total(s.facade.game_state())
	for d in days:
		_submit_plans(s, plan_batches, d)
		var waiting_before := ResettlementQueue.waiting_total(s.facade.game_state())
		var before := _cols(s)
		s.step(1)
		var after := _cols(s)
		var rows := _served_rows(s)
		var new_rows := rows.slice(served_seen)
		served_seen = rows.size()
		var into := {}
		var from_latent := {}
		for row: Array in new_rows:
			into[String(row[2])] = int(into.get(String(row[2]), 0)) + int(row[3])
			if int(row[5]) == 1:
				from_latent[String(row[1])] = int(from_latent.get(String(row[1]), 0)) + int(row[3])
			served_hh += int(row[3])
		if not new_rows.is_empty():
			records_same_tick += s.facade.game_state().reasons.find({"decision": ResettlementQueue.DECISION, "from_tick": s.tick(), "to_tick": s.tick()}).size()
			served_events += new_rows.size()
			if first_serve_day < 0:
				first_serve_day = d + 1
		var any_fresh := false
		for r in codes.size():
			var fr: int = maxi(after["built"][r] - before["built"][r], 0)
			if fr > 0:
				any_fresh = true
				fresh_total += fr
			if fr > 0 and waiting_before > 0:
				var code := codes[r]
				var latent_pre: int = after["latent"][r] - int(into.get(code, 0)) + int(from_latent.get(code, 0))
				var vac_pre: int = maxi(after["built"][r] - latent_pre, 0)
				var seekers: int = maxi(latent_pre - before["built"][r], 0)
				pairs += 1
				if vac_pre <= 0:
					pairs_vac_zero += 1
				else:
					pairs_vac_pos += 1
				if int(into.get(code, 0)) > 0:
					pairs_served += 1
				if opp_log.size() < OPP_LOG_MAX:
					opp_log.append({"day": d + 1, "region": code, "fresh": fr, "latent_pre": latent_pre, "built_after": after["built"][r], "vacancy_pre": vac_pre,
						"seekers_pre": seekers, "limit_vacancy": mini(fr, vac_pre), "limit_seekers": mini(fr, seekers), "served_into": int(into.get(code, 0)),
						"waiting_before": waiting_before})
		if any_fresh:
			fresh_days += 1
			if waiting_before > 0:
				opp_days += 1
		var waiting_now := ResettlementQueue.waiting_total(s.facade.game_state())
		waiting_min = mini(waiting_min, waiting_now)
		if (d + 1) % SERIES_EVERY == 0 or d == 0:
			series.append({"day": d + 1, "waiting": waiting_now, "served": ResettlementQueue.served_total(s.facade.game_state()), "built_sum": _sum(after["built"]),
				"latent_sum": _sum(after["latent"]), "city_vacancy": _city_vacancy(after), "waiting_by_region": ResettlementQueue.waiting_by_region(s.facade.game_state())})
	var reasons: Array = s.facade.game_state().reasons.find({"decision": ResettlementQueue.DECISION})
	var pv: PolicyView = s.facade.policies()[0]
	var cN := _cols(s)
	var out := {"head": head, "days": days, "waiting_end": ResettlementQueue.waiting_total(s.facade.game_state()), "waiting_min": waiting_min,
		"served_end": ResettlementQueue.served_total(s.facade.game_state()), "served_hh_counted": served_hh, "served_events": served_events,
		"first_serve_day": first_serve_day, "decision_records_end": reasons.size(), "decision_records_written": records_same_tick, "policy_view": pv.to_dict(),
		"fresh_units_total_all_regions": fresh_total, "fresh_days": fresh_days, "opportunity_days_fresh_while_waiting": opp_days,
		"pairs_fresh_while_waiting": pairs, "pairs_vacancy_zero": pairs_vac_zero, "pairs_vacancy_positive": pairs_vac_pos, "pairs_served": pairs_served,
		"plans": _plan_log, "d2_end": {"built": cN["built"][codes.find(REGION)], "latent": cN["latent"][codes.find(REGION)]}, "city_vacancy_end": _city_vacancy(cN), "record_end": _records_brief(s), "state_hash": s.facade.state_hash()}
	print("RQ_RUN ", JSON.stringify(out))
	print("RQ_OPP ", JSON.stringify({"sim_seed": seed_i, "pick": pick, "rows": opp_log}))
	print("RQ_SERIES ", JSON.stringify({"sim_seed": seed_i, "pick": pick, "series": series}))


func _records_brief(s: Support.SimCtx) -> Array:
	var out: Array = []
	var recs := _records(s)
	for cid: int in recs:
		var r: Dictionary = recs[cid]
		out.append({"command_id": cid, "unplaced": r.get("unplaced", -1), "rehoused": r.get("rehoused", -1), "partial": r.get("partial", -1),
			"unplaced_by": r.get("unplaced_by", {}), "served_rows": r.get("served", [])})
	return out


func _sum(a: PackedInt64Array) -> int:
	var t := 0
	for v in a:
		t += v
	return t


func _city_vacancy(c: Dictionary) -> int:
	var b: PackedInt64Array = c["built"]
	var l: PackedInt64Array = c["latent"]
	var t := 0
	for i in b.size():
		t += maxi(b[i] - l[i], 0)
	return t


## Yola en yakın, yolun almadığı boş parseller, `plan-batches` ayrı teklif grubu (yoksa boş liste).
func _plan_batches(w: Support.WorldCtx, cand: Dictionary) -> Array:
	var out: Array = []
	var zone := str(_args.get("plan-zone", ""))
	if zone.is_empty():
		return out
	var pts: PackedVector2Array = cand["pts"]
	var taken := {}
	for pid in RoadDraftCheck.taken_parcels(w.net, pts, RoadDrawTool.ROAD_CLASS):
		taken[int(pid)] = true
	var scored: Array = []
	for v in _vacant:
		if taken.has(v.id):
			continue
		var d := _dist_to_segment(v.center, pts[0], pts[pts.size() - 1])
		scored.append([d, v.id])
	scored.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0] or (x[0] == y[0] and x[1] < y[1]))
	var n := int(_args.get("plan-n", "8"))
	var batches := int(_args.get("plan-batches", "4"))
	var every := int(_args.get("plan-every", "20"))
	for b in batches:
		var ids := PackedInt64Array()
		for k in n:
			var idx := b * n + k
			if idx < scored.size():
				ids.append(int(scored[idx][1]))
		out.append({"day": b * every, "ids": ids, "zone": zone})
	return out


func _submit_plans(s: Support.SimCtx, batches: Array, day: int) -> void:
	for b: Dictionary in batches:
		if int(b["day"]) != day:
			continue
		var r := s.facade.submit_command(SimCommand.zoning_propose(b["ids"], StringName(b["zone"])))
		_plan_log.append({"day": day, "n": (b["ids"] as PackedInt64Array).size(), "status": String(r.status), "reason": String(r.reason_key)})


func _dist_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var len2 := ab.length_squared()
	var t := 0.0 if len2 <= 0.0 else clampf((p - a).dot(ab) / len2, 0.0, 1.0)
	return p.distance_to(a + ab * t)
