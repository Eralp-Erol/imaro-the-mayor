extends SceneTree
## QA T-040 2. tur: yeni kodun uç durumları (gerçek Ismeral, varsayılan rejim).
## (1) imar komutu: olmayan parsel, aynı komutta çift kimlik, boş liste, sim-yapılmış parsel, T0 parseli, bilinmeyen imar
## (2) çok kısa feed penceresi (change_window_ticks=16) + projector 20 gün hiç çalışmaz -> TEK tam eşitleme, sonra feed
## (3) duraklatma: tick yokken pump iş yapmaz, sürüm değişmez.

const QW := preload("qa_world.gd")

var fails := 0


func _check(ok: bool, what: String) -> void:
	print("QA2_EDGE %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		fails += 1


func _truth_ids(f: SimFacade, t0: Dictionary, placer: SimBuildingPlacer) -> Dictionary:
	var d := EconomyState.data((f as SimFacadeImpl).game_state())
	var ids: PackedInt64Array = d["parcel_ids"]
	var out := {}
	for k in ids.size():
		var s: int = (d["stage"] as PackedByteArray)[k]
		if t0.has(int(ids[k])) or (d["last_code"] as PackedByteArray)[k] != EconomyState.CODE_APPROVED:
			continue
		if s != EconomyState.STAGE_UNDER_CONSTRUCTION and s != EconomyState.STAGE_BUILT and s != EconomyState.STAGE_STALLED:
			continue
		if placer.plan(int(ids[k]), EconomyState.use_name((d["use"] as PackedByteArray)[k]), (d["units"] as PackedInt32Array)[k]) == null:
			continue
		out[int(ids[k])] = true
	return out


func _same(a: Dictionary, proj: SimBuildingProjector) -> bool:
	var ids := proj.parcel_ids()
	if ids.size() != a.size():
		return false
	for pid in ids:
		if not a.has(int(pid)):
			return false
	return true


func _initialize() -> void:
	var t0: Dictionary = QW.base()["t0"]
	# --- (1) komutlar ---
	var h: PoliticsHandle = QW.handle()
	var f: SimFacade = h.facade
	var proj: SimBuildingProjector = QW.projector(f)
	f.advance(2)
	var fresh := PackedInt64Array()
	for pid in f.parcel_ids(&"D1"):
		if fresh.size() >= 4:
			break
		if not t0.has(int(pid)) and proj.placer().can_place(int(pid), &"residential", 3):
			fresh.append(int(pid))
	var t0_pid := -1
	for pid in f.parcel_ids(&"D1"):
		if t0.has(int(pid)):
			t0_pid = int(pid)
			break
	var r_missing := f.submit_command(SimCommand.zoning_propose(PackedInt64Array([99999999]), &"zone.mixed"))
	_check(r_missing.is_rejected(), "olmayan parsel -> %s %s" % [r_missing.status, r_missing.reason_key])
	var r_empty := f.submit_command(SimCommand.zoning_propose(PackedInt64Array(), &"zone.mixed"))
	_check(r_empty.is_rejected(), "boş liste -> %s %s" % [r_empty.status, r_empty.reason_key])
	var r_zone := f.submit_command(SimCommand.zoning_propose(PackedInt64Array([fresh[0]]), &"zone.casino_tower"))
	_check(r_zone.is_rejected(), "bilinmeyen imar -> %s %s" % [r_zone.status, r_zone.reason_key])
	var r_dup := f.submit_command(SimCommand.zoning_propose(PackedInt64Array([fresh[0], fresh[0], fresh[1]]), &"zone.mixed"))
	print("QA2_EDGE info çift kimlik -> %s %s" % [r_dup.status, r_dup.reason_key])
	var r_t0 := f.submit_command(SimCommand.zoning_propose(PackedInt64Array([t0_pid]), &"zone.mixed"))
	print("QA2_EDGE info T0 parseli %d -> %s %s" % [t0_pid, r_t0.status, r_t0.reason_key])
	f.submit_command(SimCommand.zoning_propose(fresh.slice(2), &"zone.mixed"))
	for day in 130:
		f.advance(1)
	proj.sync(true)
	var views := f.parcel_views(fresh)
	var built := PackedInt64Array()
	for v in views:
		print("QA2_EDGE info p%d dev=%s by_sim=%s decision=%s dtick=%d" % [v.id, v.development, v.developed_by_sim, v.decision, v.decision_tick])
		if v.development == ParcelView.DEVELOPMENT_BUILT and v.developed_by_sim:
			built.append(v.id)
	var tv := f.parcel_views(PackedInt64Array([t0_pid]))[0]
	_check(not tv.developed_by_sim and not proj.parcel_ids().has(t0_pid), "T0 parseline imar: sim yapısı/satır yok (dev=%s by_sim=%s)" % [tv.development, tv.developed_by_sim])
	var dup_count := 0
	for pid in proj.parcel_ids():
		if int(pid) == fresh[0]:
			dup_count += 1
	_check(dup_count <= 1, "çift kimlikli öneri: tek satır kümesi (görünen=%d)" % dup_count)
	if not built.is_empty():
		var b := int(built[0])
		var before := f.parcel_views(PackedInt64Array([b]))[0]
		var rows_before := proj.columns().state_hash()
		var r_built := f.submit_command(SimCommand.zoning_propose(PackedInt64Array([b]), &"zone.commercial"))
		f.advance(20)
		proj.sync(true)
		var after := f.parcel_views(PackedInt64Array([b]))[0]
		print("QA2_EDGE info yapılmış parsel %d imar -> %s; önce %s/%s/%d sonra %s/%s/%d zone=%s" % [b, r_built.status,
				before.development, before.decision, before.decision_tick, after.development, after.decision, after.decision_tick, after.zone])
		_check(after.development == ParcelView.DEVELOPMENT_BUILT and after.decision == ParcelView.DECISION_APPROVED and after.decision_tick == before.decision_tick,
				"yapılmış parsele imar: yapı ve 'yatırım yaptı' kararı korunur")
		_check(proj.parcel_ids().has(b), "yapılmış parsele imar: satır kalır")
		var m := M2ResultModel.build(f, PackedInt64Array([b]), null, -1, f.current_tick() - 20)
		print("QA2_EDGE info yapılmış parsel paneli: decision=%d before_proposal=%s recorded=%d" % [m.parcels[0].decision,
				m.parcels[0].before_proposal, m.parcels[0].recorded])
		_check(m.parcels[0].recorded == M2ResultModel.Decision.APPROVED, "yapılmış parsel: kayıtlı karar onay")
	# --- (2) kısa pencere ---
	var h2: PoliticsHandle = QW.handle({"decision": {"change_window_ticks": 16}})
	var f2: SimFacade = h2.facade
	var p2: SimBuildingProjector = QW.projector(f2)
	var pump := SimBuildingPump.create(p2)
	var noop := func(_c: BuildingColumns, _v: int) -> void: pass
	f2.advance(30)
	p2.sync()
	var fs0 := int(p2.stats["full_syncs"])
	for day in 40:
		f2.advance(1)
		for k in 4:
			pump.frame(k == 0, noop)
	while p2.busy():
		p2.step(5000)
	var fs1 := int(p2.stats["full_syncs"])
	_check(fs1 == fs0, "pencere içinde kalan normal akış tam eşitleme yapmaz (%d -> %d)" % [fs0, fs1])
	f2.advance(20)   # projector 20 gün hiç çalışmaz (> 16 pencere)
	var feed := f2.parcel_changes_since(70)
	_check(not feed.complete, "pencere dışı sorgu complete=false")
	while p2.busy():
		p2.step(5000)
	var fs2 := int(p2.stats["full_syncs"])
	_check(fs2 == fs1 + 1, "pencere aşımı -> TEK tam eşitleme (%d -> %d)" % [fs1, fs2])
	_check(_same(_truth_ids(f2, t0, p2.placer()), p2), "tam eşitleme sonrası görünen == kâhin")
	for day in 30:
		f2.advance(1)
		for k in 4:
			pump.frame(k == 0, noop)
	while p2.busy():
		p2.step(5000)
	_check(int(p2.stats["full_syncs"]) == fs2, "sonra yine yalnız feed (tam eşitleme %d)" % int(p2.stats["full_syncs"]))
	_check(_same(_truth_ids(f2, t0, p2.placer()), p2), "30 gün sonra görünen == kâhin")
	# --- (3) duraklatma ---
	var v0 := p2.version()
	var worked := 0
	for k in 200:
		if bool(pump.frame(false, noop).get("worked", false)):
			worked += 1
	_check(worked == 0 and p2.version() == v0, "duraklatmada 200 karede iş yok (worked=%d, sürüm %d->%d)" % [worked, v0, p2.version()])
	print("QA2_EDGE DONE fails=%d" % fails)
	quit(1 if fails > 0 else 0)
