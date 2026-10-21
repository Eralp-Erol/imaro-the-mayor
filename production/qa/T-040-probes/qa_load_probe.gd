extends SceneTree
## QA T-040 (i): varsayılan otonom rejimde (gerçek Ismeral, PlayableEconomy) projector'ın kare benzetimli bütçeli
## çalışması, tam taramayla karşılaştırma. Argümanlar (-- sonrası): days=N fpd=K (gün başına kare) every=E

const QW := preload("qa_world.gd")


var _batch := {}


func _arg(name: String, def: int) -> int:
	for a in OS.get_cmdline_user_args():
		if a.begins_with(name + "="):
			return int(a.split("=")[1])
	return def


func _initialize() -> void:
	var days := _arg("days", 150)
	var fpd := _arg("fpd", 4)
	var every := _arg("every", 10)
	var t_setup := Time.get_ticks_msec()
	var latent := _arg("latent", 0)
	var patch := {}
	if latent > 0:
		var b := QW.base()
		var stock: ExistingStockSource = b["stock"]
		var region_of := {}
		for v: ParcelView in b["views"]:
			region_of[v.id] = v.region_code
		var res := {}
		for id in stock.parcel_ids():
			var code: StringName = region_of.get(int(id), &"")
			if code != &"" and stock.use_of(int(id)) == &"residential":
				res[code] = int(res.get(code, 0)) + stock.units_of(int(id))
		var ov := {}
		var base_cfg := PlayableEconomy.config_for(b["views"], stock, {})
		for code in res:
			ov[String(code)] = {"initial_households": 100 + int(res[code]) * latent / 1000}
			if _arg("infra2", 0) == 1:
				ov[String(code)]["infra_capacity_units"] = int(res[code]) * 4 + 100000
		patch = {"regions": {"overrides": ov}}
		print("QA_LOAD latent_pm=%d (QA yük yaması; oynanabilir değeri 250)" % latent)
	var h: PoliticsHandle = QW.handle(patch)
	var f: SimFacade = h.facade
	var proj: SimBuildingProjector = QW.projector(f)
	print("QA_LOAD setup_ms=%d parcels=%d t0=%d fpd=%d" % [Time.get_ticks_msec() - t_setup, f.parcel_ids().size(),
			(QW.base()["t0"] as Dictionary).size(), fpd])
	var batch := _arg("batch", 0)
	if batch > 0:
		f.advance(2)
		var t0d: Dictionary = QW.base()["t0"]
		var ids := Array(f.parcel_ids())
		ids.sort()
		var pick := PackedInt64Array()
		var stride := maxi(1, ids.size() / (batch * 3))
		var k := 0
		while k < ids.size() and pick.size() < batch:
			var pid := int(ids[k])
			k += stride
			if t0d.has(pid) or not proj.placer().can_place(pid, &"residential", 3):
				continue
			pick.append(pid)
		var r := f.submit_command(SimCommand.zoning_propose(pick, &"zone.mixed"))
		for pid in pick:
			_batch[int(pid)] = true
		print("QA_LOAD batch=%d status=%s" % [pick.size(), r.status])
	var batch_set := {}
	if batch > 0:
		pass
	var first_truth := {}
	var first_shown := {}
	var first_built_truth := {}
	var first_built_shown := {}
	var seen_version := 0
	var last_appr := 0
	var last_decl := 0
	var max_uc := 0
	var max_dec_day := 0
	var dec_sum := 0
	var transient_worst := 0
	for day in range(1, days + 1):
		f.advance(1)
		# Kare benzetimi (playable._process): tick'li kare iş yapmaz (kuyruk > 6 değilse); sonraki kareler tek iş.
		for frame in fpd:
			var tick_frame := frame == 0
			if tick_frame and proj.backlog_ticks() <= 6:
				continue
			if proj.version() != seen_version:
				seen_version = proj.version()   # set_columns karesi
			else:
				proj.step(1200)
		var eo := f.economy_outcome()
		if eo.available:
			var d := (eo.investments_approved - last_appr) + (eo.investments_declined - last_decl)
			if last_appr + last_decl > 0 or day > 2:
				max_dec_day = maxi(max_dec_day, d)
				dec_sum += d
			last_appr = eo.investments_approved
			last_decl = eo.investments_declined
		if day % every == 0 or day == days:
			var tr := QW.truth(f, proj.placer())
			for pid: int in tr["build"]:
				if not first_truth.has(pid):
					first_truth[pid] = day
				if tr["build"][pid] == "built" and not first_built_truth.has(pid):
					first_built_truth[pid] = day
			for pid in proj.parcel_ids():
				if not first_shown.has(int(pid)):
					first_shown[int(pid)] = day
				if String(proj._shown[int(pid)]["key"]).begins_with("built|") and not first_built_shown.has(int(pid)):
					first_built_shown[int(pid)] = day
			max_uc = maxi(max_uc, int(tr["uc"]))
			var cmp := _compare(proj, tr["build"])
			transient_worst = maxi(transient_worst, cmp["missing"] + cmp["extra"] + cmp["stage"])
			print("QA_LOAD day=%d first_ret_seq=%d last_seq=%d approved=%d declined=%d completed=%d uc=%d built=%d stalled=%d planned=%d unplaceable=%d shown=%d missing=%d extra=%d stage_mismatch=%d backlog=%d busy=%s audits=%d unresolved=%d step_max_ms=%.2f" % [
					day, f.first_retained_event_seq(), f.last_event_seq(), eo.investments_approved,
					eo.investments_declined, eo.projects_completed, tr["uc"], tr["built"], tr["stalled"], tr["planned"],
					tr["unplaceable"], proj.parcel_ids().size(), cmp["missing"], cmp["extra"], cmp["stage"],
					proj.backlog_ticks(), proj.busy(), int(proj.stats["full_scans"]),
					int(proj.stats["unresolved_missing"]), float(proj.stats["step_ms_max"])])
	var lags := []
	var never := 0
	var worst := []
	for pid: int in first_truth:
		if first_shown.has(pid):
			lags.append(maxi(0, int(first_shown[pid]) - int(first_truth[pid])))
			if int(first_shown[pid]) - int(first_truth[pid]) > 10:
				worst.append([pid, first_truth[pid], first_shown[pid]])
		else:
			never += 1
			worst.append([pid, first_truth[pid], -1])
	var plags := []
	var pnever := 0
	for pid: int in first_truth:
		if _batch.has(pid):
			if first_shown.has(pid):
				plags.append(int(first_shown[pid]) - int(first_truth[pid]))
			else:
				pnever += 1
	plags.sort()
	print("QA_LOAD_LAG player-batch: n=%d max=%s never=%d all=%s" % [plags.size(), str(plags[plags.size() - 1]) if not plags.is_empty() else "-", pnever, str(plags)])
	lags.sort()
	var blags := []
	for pid: int in first_built_truth:
		if first_built_shown.has(pid):
			blags.append(maxi(0, int(first_built_shown[pid]) - int(first_built_truth[pid])))
	blags.sort()
	print("QA_LOAD_LAG appear: n=%d p50=%s p95=%s max=%s never_during_run=%d worst=%s" % [lags.size(),
			str(lags[lags.size() / 2]) if not lags.is_empty() else "-",
			str(lags[int(lags.size() * 0.95)]) if not lags.is_empty() else "-",
			str(lags[lags.size() - 1]) if not lags.is_empty() else "-", never, str(worst.slice(0, 12))])
	print("QA_LOAD_LAG built-stage: n=%d p50=%s p95=%s max=%s" % [blags.size(),
			str(blags[blags.size() / 2]) if not blags.is_empty() else "-",
			str(blags[int(blags.size() * 0.95)]) if not blags.is_empty() else "-",
			str(blags[blags.size() - 1]) if not blags.is_empty() else "-"])
	# Kuyruğu boşalt (sim ilerlemeden): kalıcı kayıp mı geçici gecikme mi?
	var steps := 0
	while proj.busy() and steps < 200000:
		proj.step(1200)
		steps += 1
	var tr2 := QW.truth(f, proj.placer())
	var c2 := _compare(proj, tr2["build"])
	print("QA_LOAD_T0 t0_by_sim=%d t0_stages=%s shown_t0=%d" % [tr2["t0_by_sim"], str(tr2["t0_stage"]), _shown_t0(proj)])
	print("QA_LOAD_DRAINED steps=%d missing=%d extra=%d stage_mismatch=%d sample_missing=%s unresolved=%d" % [
			steps, c2["missing"], c2["extra"], c2["stage"], str(c2["sample"]), int(proj.stats["unresolved_missing"])])
	proj.sync(true)
	var c3 := _compare(proj, tr2["build"])
	var fresh: SimBuildingProjector = QW.projector(f)
	fresh.sync(true)
	var c4 := _compare(fresh, tr2["build"])
	print("QA_LOAD_EXACT missing=%d extra=%d stage=%d | fresh missing=%d extra=%d stage=%d | hash_equal=%s rows=%d fresh_rows=%d" % [
			c3["missing"], c3["extra"], c3["stage"], c4["missing"], c4["extra"], c4["stage"],
			proj.columns().state_hash() == fresh.columns().state_hash(), proj.columns().count, fresh.columns().count])
	print("QA_LOAD_SUMMARY days=%d max_decisions_per_day=%d avg_decisions_per_day=%.1f max_concurrent_uc=%d transient_worst=%d unplaced=%d" % [
			days, max_dec_day, float(dec_sum) / maxi(days - 2, 1), max_uc, transient_worst, proj.unplaced().size()])
	quit(0)


func _shown_t0(proj: SimBuildingProjector) -> int:
	var t0: Dictionary = QW.base()["t0"]
	var n := 0
	for pid in proj.parcel_ids():
		if t0.has(int(pid)):
			n += 1
	return n


func _compare(proj: SimBuildingProjector, truth: Dictionary) -> Dictionary:
	var shown := {}
	for pid in proj.parcel_ids():
		shown[int(pid)] = true
	var missing := 0
	var extra := 0
	var stage := 0
	var sample := []
	for pid: int in truth:
		if not shown.has(pid):
			missing += 1
			if sample.size() < 5:
				sample.append(pid)
		else:
			var key: String = proj._shown[pid]["key"]
			if not key.begins_with(String(truth[pid]) + "|"):
				stage += 1
	for pid: int in shown:
		if not truth.has(pid):
			extra += 1
	return {"missing": missing, "extra": extra, "stage": stage, "sample": sample}
