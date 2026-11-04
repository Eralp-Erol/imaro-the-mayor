extends SceneTree
## QA T-040: gerçek Ismeral dünyasında uçtan uca döngü (a,b,c,d,f,g,h) + uç durumlar. Çıktı: QA_* satırları.

const QW := preload("qa_world.gd")
const ISOLATE := {"decision": {"review_enabled": 0}}

var fails := 0


func check(ok: bool, label: String) -> void:
	print("QA_CHECK %s %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		fails += 1


func _initialize() -> void:
	var b := QW.base()
	var t0: Dictionary = b["t0"]
	# ---- (a)(b)(c)(d)(f)(g) izole koşu ----
	var h: PoliticsHandle = QW.handle(ISOLATE)
	var f: SimFacadeImpl = h.facade
	var proj: SimBuildingProjector = QW.projector(f)
	f.advance(2)
	var region := &"D1"
	var cands := _free(f, proj, region, 12, t0)
	var mixed := cands.slice(0, 8)
	var commercial := cands.slice(8, 12)
	var before := f.economy_outcome()
	var r1 := f.submit_command(SimCommand.zoning_propose(mixed, &"zone.mixed"))
	print("QA_A submit mixed %s status=%s reason=%s apply_tick=%d" % [str(mixed), r1.status, r1.reason_key, r1.apply_tick])
	check(r1.status == CommandResult.STATUS_QUEUED, "a: zoning.propose -> queued")
	var r2 := f.submit_command(SimCommand.zoning_propose(commercial, &"zone.commercial"))
	print("QA_A submit commercial status=%s" % r2.status)
	# Uç durumlar (komut doğrulaması)
	var e_empty := f.submit_command(SimCommand.zoning_propose(PackedInt64Array(), &"zone.mixed"))
	var e_missing := f.submit_command(SimCommand.zoning_propose(PackedInt64Array([987654321]), &"zone.mixed"))
	var e_dup := f.submit_command(SimCommand.zoning_propose(PackedInt64Array([mixed[0]]), &"zone.mixed"))
	var e_badzone := f.submit_command(SimCommand.zoning_propose(PackedInt64Array([cands[0]]), &"zone.nonsense"))
	var t0_ids := PackedInt64Array()
	for pid in t0:
		if t0_ids.size() < 6 and _view(f, pid).region_code == region:
			t0_ids.append(pid)
	var e_t0 := f.submit_command(SimCommand.zoning_propose(t0_ids, &"zone.mixed"))
	print("QA_EDGE empty=%s/%s missing=%s/%s duplicate_pending=%s/%s bad_zone=%s/%s t0_built=%s/%s t0_dev=%s" % [
			e_empty.status, e_empty.reason_key, e_missing.status, e_missing.reason_key, e_dup.status, e_dup.reason_key,
			e_badzone.status, e_badzone.reason_key, e_t0.status, e_t0.reason_key, _view(f, t0_ids[0]).development])
	check(e_empty.is_rejected(), "edge: empty parcel list rejected")
	check(e_missing.is_rejected(), "edge: unknown parcel rejected")
	check(e_badzone.is_rejected(), "edge: unknown zone rejected")
	# Gün gün izle
	var hist := {}
	for pid in mixed + commercial + t0_ids:
		hist[int(pid)] = []
	var rows_by_stage_ok := true
	var stage_violation := ""
	var events_cursor := f.last_event_seq()
	var reacted := 0
	var declined_codes := {}
	for day in 150:
		f.advance(1)
		proj.sync()
		for v in f.parcel_views(mixed + commercial + t0_ids):
			var arr: Array = hist[v.id]
			var tag := "%s:%d" % [v.development, v.progress_pm]
			if arr.is_empty() or arr[arr.size() - 1][1] != tag:
				arr.append([f.current_tick(), tag, v.developed_by_sim, String(v.use), v.units])
			var has_rows := M2RowsHelper.count(proj, v.id) > 0
			var should := v.developed_by_sim and v.development in [ParcelView.DEVELOPMENT_UNDER_CONSTRUCTION,
					ParcelView.DEVELOPMENT_BUILT, ParcelView.DEVELOPMENT_STALLED] and not proj.unplaced().has(v.id)
			if has_rows != should:
				rows_by_stage_ok = false
				stage_violation = "day %d parcel %d dev=%s by_sim=%s rows=%s" % [f.current_tick(), v.id, v.development,
						v.developed_by_sim, has_rows]
			if t0.has(v.id) and has_rows:
				rows_by_stage_ok = false
				stage_violation = "T0 parcel %d has sim rows" % v.id
		for e in f.events_since(events_cursor, 100000):
			events_cursor = e.seq
			if e.kind == SimEvent.KIND_GROUP_REACTED:
				reacted += 1
			if e.message_key == &"event.investor.declined":
				for s in e.subjects:
					var pid := s.substr(7).to_int()
					if hist.has(pid):
						declined_codes[pid] = e.args.get("code")
		if day == 40:
			_hud_check(f, mixed, before, region, "day40")
	for pid in hist:
		print("QA_STAGES parcel=%d %s" % [pid, str(hist[pid])])
	check(rows_by_stage_ok, "d: rows exist iff developed_by_sim & uc/built/stalled; none for T0 (%s)" % stage_violation)
	# (c) aşama sırası
	var approved := 0
	var declined := 0
	for pid in mixed + commercial:
		var seq: Array = hist[int(pid)]
		var prev_rank := -1
		var prev_prog := -1
		var mono := true
		for item in seq:
			var parts: PackedStringArray = String(item[1]).split(":")
			var rank := ["vacant", "planned", "under_construction", "built"].find(parts[0])
			var prog := int(parts[1])
			if rank < prev_rank or (rank == prev_rank and prog < prev_prog):
				mono = false
			if parts[0] == "planned" and prog != 0:
				mono = false
			if parts[0] == "built" and prog != 1000:
				mono = false
			prev_rank = rank
			prev_prog = prog
		check(mono, "c: parcel %d stage/progress monotone & consistent" % pid)
		var pv := _view(f, int(pid))   # QA 2. tur: v1.2 karar alanları (latest_investor_decision kaldırıldı)
		if pv.decision != ParcelView.DECISION_NONE:
			if pv.decision == ParcelView.DECISION_APPROVED:
				approved += 1
			else:
				declined += 1
				var cause := M2ResultModel.cause_of_code(pv.decision_code)
				print("QA_B declined parcel=%d ui_cause=%s sim_code=%s view_code=%s rid=%d" % [pid, cause,
						declined_codes.get(int(pid), "?"), pv.decision_code, pv.decision_reason_id])
	print("QA_B approved=%d declined=%d (of %d proposals)" % [approved, declined, mixed.size() + commercial.size()])
	check(approved >= 1 and declined >= 1, "b: both approved and declined arise from sim rules")
	var snap := f.snapshot()
	var dirs := {}
	for g in snap.group_reactions:
		if g.reaction != GroupReactionView.REACTION_NEUTRAL:
			dirs[String(g.reaction)] = int(dirs.get(String(g.reaction), 0)) + 1
		print("QA_G group=%s reaction=%s stance=%d intensity=%d causes=%s reasons=%d" % [g.group.id, g.reaction,
				g.stance, g.intensity, str(g.cause_refs.slice(0, 3)), g.reason_ids.size()])
	print("QA_G group.reacted events=%d" % reacted)
	check(reacted >= 1, "g: >=1 group.reacted event")
	_hud_check(f, mixed, before, region, "day152")
	# T0 parsellerine imar: çift yapı?
	var t0_dev := 0
	for v in f.parcel_views(t0_ids):
		if v.developed_by_sim:
			t0_dev += 1
	check(t0_dev == 0 and _rows_on(proj, t0_ids) == 0, "d: zoning on T0 stock parcels -> no sim development/double rows (by_sim=%d)" % t0_dev)
	# ---- (h) determinizm + kayıt ----
	_determinism(mixed, commercial)
	print("QA_DONE fails=%d" % fails)
	quit(1 if fails > 0 else 0)


func _hud_check(f: SimFacade, tracked: PackedInt64Array, base: EconomyOutcomeView, region: StringName, tag: String) -> void:
	var m := M2ResultModel.build(f, tracked, base, 2, 2)
	var now := f.economy_outcome()
	var rb := base.region(m.region_code)
	var rn := now.region(m.region_code)
	var manual := {
		"sim_residential_units": rn.sim_residential_units - rb.sim_residential_units,
		"sim_commercial_units": rn.sim_commercial_units - rb.sim_commercial_units,
		"housed_households": rn.housed_households - rb.housed_households,
		"investments_approved": now.investments_approved - base.investments_approved,
		"investments_declined": now.investments_declined - base.investments_declined,
		"projects_completed": now.projects_completed - base.projects_completed,
		"rent_income": now.rent_income - base.rent_income}
	var ok := true
	var line := ""
	for r in m.metrics + m.counters:
		var exp: int = manual.get(String(r.key), -999999)
		line += " %s=%d(manual %d)" % [r.key, r.delta, exp]
		if r.delta != exp:
			ok = false
	print("QA_F %s region=%s%s pipeline=%d/%d municipal_available=%s key=%s" % [tag, m.region_code, line,
			m.pipeline_residential, m.pipeline_commercial, m.municipal_available, m.municipal_reason_key])
	check(ok, "f: HUD model deltas == manual subtraction (%s)" % tag)
	check(not m.municipal_available, "f: municipal revenue honest not-built (%s)" % tag)


func _determinism(mixed: PackedInt64Array, commercial: PackedInt64Array) -> void:
	var runs := []
	for k in 2:
		var h: PoliticsHandle = QW.handle()   # VARSAYILAN (otonom) rejim
		var f: SimFacadeImpl = h.facade
		var p: SimBuildingProjector = QW.projector(f)
		f.advance(2)
		f.submit_command(SimCommand.zoning_propose(mixed, &"zone.mixed"))
		f.submit_command(SimCommand.zoning_propose(commercial, &"zone.commercial"))
		var mid := PackedByteArray()
		var mid_rows := ""
		for day in 70:
			f.advance(1)
			for i in 4:
				p.step(1200)
			if day == 30:
				mid = f.export_save()
		while p.busy():
			p.step(1200)
		p.sync(true)
		runs.append({"hash": f.state_hash(), "rows": p.columns().state_hash(), "n": p.columns().count, "mid": mid,
				"facade": f, "proj": p})
	print("QA_H run1 hash=%s rows=%s n=%d | run2 hash=%s rows=%s n=%d" % [runs[0]["hash"], runs[0]["rows"],
			runs[0]["n"], runs[1]["hash"], runs[1]["rows"], runs[1]["n"]])
	check(runs[0]["hash"] == runs[1]["hash"] and runs[0]["rows"] == runs[1]["rows"], "h: same seed+commands -> same state_hash & rows")
	# Kayıt ortası yükle -> aynı devam
	var h2: PoliticsHandle = QW.handle()
	var f2: SimFacadeImpl = h2.facade
	var p2: SimBuildingProjector = QW.projector(f2)
	var res := f2.import_save(runs[0]["mid"])
	var uc := 0
	for v in f2.parcel_views(mixed):
		if v.development == ParcelView.DEVELOPMENT_UNDER_CONSTRUCTION or v.development == ParcelView.DEVELOPMENT_PLANNED:
			uc += 1
	print("QA_H loaded ok=%s tick=%d inflight_tracked=%d" % [res.ok, f2.current_tick(), uc])
	var remaining: int = (runs[0]["facade"] as SimFacadeImpl).current_tick() - f2.current_tick()
	for day in remaining:
		f2.advance(1)
		for i in 4:
			p2.step(1200)
	while p2.busy():
		p2.step(1200)
	p2.sync(true)
	print("QA_H resumed hash=%s rows=%s n=%d" % [f2.state_hash(), p2.columns().state_hash(), p2.columns().count])
	check(f2.state_hash() == runs[0]["hash"], "h: save mid-construction -> load -> continue == uninterrupted state_hash")
	check(p2.columns().state_hash() == runs[0]["rows"], "h: save/load -> same building rows")
	# Farklı seed -> farklı hash (seed kullanılıyor mu?)
	var h3: PoliticsHandle = QW.handle({}, 777)
	h3.facade.advance(30)
	check(h3.facade.state_hash() != runs[0]["hash"], "h: different seed -> different hash")


func _view(f: SimFacade, pid: int) -> ParcelView:
	return f.parcel_views(PackedInt64Array([pid]))[0]


func _rows_on(proj: SimBuildingProjector, ids: PackedInt64Array) -> int:
	var n := 0
	for pid in ids:
		n += M2RowsHelper.count(proj, int(pid))
	return n


func _free(f: SimFacade, proj: SimBuildingProjector, region: StringName, n: int, t0: Dictionary) -> PackedInt64Array:
	var out := PackedInt64Array()
	var ids := f.parcel_ids(region)
	var sorted := Array(ids)
	sorted.sort()
	var batch := PackedInt64Array()
	for pid in sorted:
		if t0.has(int(pid)):
			continue
		if not proj.placer().can_place(int(pid), &"residential", 3):
			continue
		var v := _view(f, int(pid))
		if v.development != ParcelView.DEVELOPMENT_VACANT or v.pending_zone != &"":
			continue
		out.append(int(pid))
		if out.size() >= n:
			break
	return out


class M2RowsHelper:
	static func count(proj: SimBuildingProjector, pid: int) -> int:
		var cols := proj.columns()
		var c := 0
		for i in cols.count:
			if cols.parcel_id[i] == pid:
				c += 1
		return c
