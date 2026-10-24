extends SceneTree
## QA T-040 2. tur (B-002): gerçek Ismeral + PlayableEconomy (VARSAYILAN otonom rejim), projector'ı playable ile AYNI
## kare kuralıyla (SimBuildingPump) sürer; görünüm kurulumu sahte (sayaç). Gerçek (kâhin) feed'den ve parcel_views'tan
## BAĞIMSIZ: ekonomi durum sütunları (EconomyState.data: stage/last_code/use/units) doğrudan okunur; çizilmesi gereken =
## T0 dışı, last_code=approved, stage in {inşaat, yapıldı, durmuş}, units>0, yerleşim planı var.
## Argümanlar (-- sonrası): days=N fpd=K batch=B load_at=D (0: yok; D gününde export_save+import_save, smoke gibi)
##   tail=T (kuyruk boşaltmadan önce son T günü ölçmeye devam)

const QW := preload("qa_world.gd")

var _view_builds := 0


func _arg(name: String, def: int) -> int:
	for a in OS.get_cmdline_user_args():
		if a.begins_with(name + "="):
			return int(a.split("=")[1])
	return def


func _apply_view(_cols: BuildingColumns, _version: int) -> void:
	_view_builds += 1


## Kâhin: pid -> [use, units, stage] (çizilmesi gerekenler; yerleşim planı ayrıca).
func _truth(impl: SimFacadeImpl, t0: Dictionary) -> Dictionary:
	var d := EconomyState.data(impl.game_state())
	var out := {}
	if d.is_empty():
		return out
	var ids: PackedInt64Array = d["parcel_ids"]
	var stage: PackedByteArray = d["stage"]
	var code: PackedByteArray = d["last_code"]
	var units: PackedInt32Array = d["units"]
	var use: PackedByteArray = d["use"]
	for i in ids.size():
		var s := stage[i]
		if code[i] != EconomyState.CODE_APPROVED or units[i] <= 0 or use[i] == EconomyConfig.USE_NONE:
			continue
		if s != EconomyState.STAGE_UNDER_CONSTRUCTION and s != EconomyState.STAGE_BUILT and s != EconomyState.STAGE_STALLED:
			continue
		if t0.has(int(ids[i])):
			continue
		out[int(ids[i])] = [EconomyState.use_name(use[i]), units[i], s]
	return out


func _initialize() -> void:
	var days := _arg("days", 160)
	var fpd := _arg("fpd", 4)
	var batch := _arg("batch", 0)
	var load_at := _arg("load_at", 0)
	var t0: Dictionary = QW.base()["t0"]
	var h: PoliticsHandle = QW.handle()
	var f: SimFacade = h.facade
	var impl := f as SimFacadeImpl
	var proj: SimBuildingProjector = QW.projector(f)
	var pump := SimBuildingPump.create(proj)
	var placer := proj.placer()
	f.advance(2)
	if batch > 0:
		var ids := Array(f.parcel_ids())
		ids.sort()
		var pick := PackedInt64Array()
		var stride := maxi(1, ids.size() / (batch * 3))
		var k := 0
		while k < ids.size() and pick.size() < batch:
			var pid := int(ids[k])
			k += stride
			if t0.has(pid) or not placer.can_place(pid, &"residential", 3):
				continue
			pick.append(pid)
		print("QA3_B002 batch=%d status=%s" % [pick.size(), f.submit_command(SimCommand.zoning_propose(pick, &"zone.mixed")).status])
	var first_truth := {}   # pid -> gün (çizilmesi gerektiği ilk gün)
	var first_shown := {}
	var exp_key := {}       # pid -> [beklenen anahtar, o anahtarın gerçek olduğu ilk gün]
	var stage_lags := []
	var frame_ms := []
	var max_uc := 0
	var unplaceable_truth := {}
	var load_day := -1
	var full_done_day := -1
	var last_appr := 0
	var last_decl := 0
	var max_dec := 0
	for day in range(1, days + 1):
		f.advance(1)
		var eo := f.economy_outcome()
		max_dec = maxi(max_dec, eo.investments_approved - last_appr + eo.investments_declined - last_decl)
		last_appr = eo.investments_approved
		last_decl = eo.investments_declined
		if load_at > 0 and day == load_at:
			var before := impl.state_hash()
			var lr := impl.import_save(impl.export_save())
			load_day = day
			print("QA3_B002 LOAD day=%d ok=%s hash_equal=%s epoch=%d" % [day, lr.ok, before == impl.state_hash(),
					f.parcel_changes_since(f.current_tick()).epoch])
		for frame in fpd:
			var t := Time.get_ticks_usec()
			var res := pump.frame(frame == 0, _apply_view)
			if bool(res.get("worked", false)):
				frame_ms.append((Time.get_ticks_usec() - t) / 1000.0)
		if load_day > 0 and full_done_day < 0 and not proj.busy() and int(proj.stats["full_syncs"]) >= 1:
			full_done_day = day
		# Kâhin ve karşılaştırma (her gün)
		var tr := _truth(impl, t0)
		var uc := 0
		var need_views := PackedInt64Array()
		for pid: int in tr:
			if int(tr[pid][2]) == EconomyState.STAGE_UNDER_CONSTRUCTION:
				uc += 1
			if not first_truth.has(pid):
				if placer.plan(pid, StringName(tr[pid][0]), int(tr[pid][1])) == null:
					unplaceable_truth[pid] = true
					continue
				first_truth[pid] = day
			if unplaceable_truth.has(pid):
				continue
			need_views.append(pid)
		max_uc = maxi(max_uc, uc)
		var shown := {}
		for pid in proj.parcel_ids():
			shown[int(pid)] = true
			if not first_shown.has(int(pid)):
				first_shown[int(pid)] = day
		# Kat kademesi gecikmesi: beklenen anahtar (gerçek ilerlemeden) vs görünen anahtar
		for v in f.parcel_views(need_views):
			var plan := placer.plan(v.id, v.use, v.units)
			var progress := ParcelView.PROGRESS_FULL if v.development == ParcelView.DEVELOPMENT_BUILT else v.progress_pm
			var key := "%s|%d|%s" % [v.use, v.units, placer.stage_key(plan, progress)]
			var prev: Array = exp_key.get(v.id, ["", day])
			if prev[0] != key:
				exp_key[v.id] = [key, day, false]
			var cur: Array = exp_key[v.id]
			if not bool(cur[2]) and shown.has(v.id) and String(proj._shown[v.id]["key"]) == key:
				cur[2] = true
				stage_lags.append(day - int(cur[1]))
		if day % 20 == 0 or day == days:
			var missing := 0
			for pid: int in first_truth:
				if not shown.has(pid):
					missing += 1
			var extra := 0
			for pid: int in shown:
				if not tr.has(pid):
					extra += 1
			print("QA3_B002 day=%d truth_drawable=%d shown=%d missing_now=%d extra_now=%d uc=%d backlog=%d full_active=%s full_syncs=%d unplaced=%d" % [
					day, first_truth.size(), shown.size(), missing, extra, uc, proj.backlog_ticks(), proj.busy(),
					int(proj.stats["full_syncs"]), proj.unplaced_count()])
	var lags := []
	var never := []
	for pid: int in first_truth:
		if first_shown.has(pid) and int(first_shown[pid]) >= int(first_truth[pid]):
			lags.append(int(first_shown[pid]) - int(first_truth[pid]))
		elif first_shown.has(pid):
			lags.append(0)
		else:
			never.append([pid, first_truth[pid]])
	lags.sort()
	stage_lags.sort()
	frame_ms.sort()
	var pending_stage := 0
	for pid: int in exp_key:
		if not bool(exp_key[pid][2]):
			pending_stage += 1
	print("QA3_B002_LAG appear n=%d p50=%s p95=%s max=%s never=%d never_sample=%s" % [lags.size(), _q(lags, 0.5), _q(lags, 0.95),
			_q(lags, 1.0), never.size(), str(never.slice(0, 8))])
	print("QA3_B002_LAG stage n=%d p50=%s p95=%s max=%s pending_at_end=%d" % [stage_lags.size(), _q(stage_lags, 0.5),
			_q(stage_lags, 0.95), _q(stage_lags, 1.0), pending_stage])
	print("QA3_B002_FRAME worked_frames=%d p50=%s p95=%s max=%s view_builds=%d pump=%s" % [frame_ms.size(), _q(frame_ms, 0.5),
			_q(frame_ms, 0.95), _q(frame_ms, 1.0), _view_builds, pump.stats])
	if load_day > 0:
		print("QA3_B002_LOAD load_day=%d full_sync_done_day=%s (days=%s)" % [load_day, full_done_day,
				str(full_done_day - load_day) if full_done_day > 0 else "NOT DONE"])
	# Boşalt (sim ilerlemeden) + tam karşılaştırma + sıfırdan projector
	var steps := 0
	while proj.busy() and steps < 200000:
		proj.step(1200)
		steps += 1
	var tr2 := _truth(impl, t0)
	var miss := 0
	var ext := 0
	for pid: int in tr2:
		if not unplaceable_truth.has(pid) and placer.plan(pid, StringName(tr2[pid][0]), int(tr2[pid][1])) != null \
				and not proj._shown.has(pid):
			miss += 1
	for pid: int in proj._shown:
		if not tr2.has(pid):
			ext += 1
	proj.sync(true)
	var fresh: SimBuildingProjector = QW.projector(f)
	fresh.sync(true)
	var unpl := proj.unplaced_count()
	print("QA3_B002_DRAINED steps=%d missing=%d extra=%d | exact==fresh hash=%s rows=%d/%d" % [steps, miss, ext,
			proj.columns().state_hash() == fresh.columns().state_hash(), proj.columns().count, fresh.columns().count])
	print("QA3_B002_UNPLACED unplaced=%d shown=%d ratio=%.3f reasons=%s truth_unplaceable=%d" % [unpl, proj.parcel_ids().size(),
			float(unpl) / maxi(unpl + proj.parcel_ids().size(), 1), proj.unplaced_reason_counts(), unplaceable_truth.size()])
	print("QA3_B002_SUMMARY days=%d fpd=%d max_dec_per_day=%d max_uc=%d" % [days, fpd, max_dec, max_uc])
	quit(0)


func _q(arr: Array, q: float) -> String:
	if arr.is_empty():
		return "-"
	var v: Variant = arr[mini(int(arr.size() * q), arr.size() - 1)]
	return ("%.2f" % v) if v is float else str(v)
