extends SceneTree
## QA T-040 2. tur (B-001, gerçek playable.tscn, VARSAYILAN rejim): "Döngü sonucu" panelinin GÖRÜNEN metni toplanır ve
## sim değerlerinden BAĞIMSIZ kurulan beklenen metinle birebir karşılaştırılır. Gerekçe "budandı" iddiası gerekçe
## günlüğünün kendisiyle (reasons_for/reason) doğrulanır. Oyun argümanları -- sonrası.

const DEVELOP := &"decision.investor.develop"

var fails := 0


func _check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("QA2_HUD FAIL ", what)


func _initialize() -> void:
	var scene: Node = load("res://scenes/game/playable.tscn").instantiate()
	root.add_child(scene)
	for i in 30:
		await process_frame
	await _verify(scene, "initial")
	var rewind := 0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--qa-rewind="):
			rewind = int(a.split("=")[1])
	if rewind > 0:
		var impl := scene.get("_facade") as SimFacadeImpl
		var bytes := impl.export_save()
		var t_save := impl.current_tick()
		impl.advance(rewind)
		for i in 10:
			await process_frame
		await _verify(scene, "advanced+%d" % rewind)
		var lr := impl.import_save(bytes)
		print("QA2_HUD rewind import ok=%s tick %d -> %d (panel open=%s)" % [lr.ok, t_save + rewind, impl.current_tick(),
				(scene.get("_m2_results") as M2Results).is_open()])
		for i in 10:
			await process_frame
		await _verify(scene, "after-load")
		var proj: SimBuildingProjector = scene.get("_projector")
		var n := 0
		while (proj.full_sync_active() or proj.busy()) and n < 3000:
			await process_frame
			n += 1
		_projector_truth(scene, n)
	print("QA2_HUD DONE fails=%d" % fails)
	quit(1 if fails > 0 else 0)


func _verify(scene: Node, tag: String) -> void:
	var f: SimFacade = scene.get("_facade")
	var res: M2Results = scene.get("_m2_results")
	var panel := res.results_panel()
	var texts := PackedStringArray()
	if panel != null:
		_collect(panel, texts)
	var joined := " | ".join(texts)
	print("QA2_HUD [%s] tick=" % tag + "%d proposed_tick=%d panel_text=%s" % [f.current_tick(), res.proposed_tick, joined])
	_check(panel != null, "panel açık değil")
	var tracked: PackedInt64Array = res.tracked
	var views := f.parcel_views(tracked)
	var appr := 0
	var decl := 0
	var wait := 0
	var primary: ParcelView = null
	for v in views:
		var post := v.decision != ParcelView.DECISION_NONE and v.decision_tick > res.proposed_tick
		if post and primary == null:
			primary = v
		if not post:
			wait += 1
		elif v.decision == ParcelView.DECISION_APPROVED:
			appr += 1
		else:
			decl += 1
		# Gerekçe gerçeği: reason_id>0 ise kayıt var ve aynı karar; 0 ise günlükte bu karar kaydı GERÇEKTEN yok.
		if v.decision != ParcelView.DECISION_NONE:
			var found := 0
			for rec in f.reasons_for(v.ref()):
				if rec.decision_key == DEVELOP and rec.tick == v.decision_tick:
					found = rec.id
			if v.decision_reason_id > 0:
				var r := f.reason(v.decision_reason_id)
				_check(r != null and r.tick == v.decision_tick and r.decision_key == DEVELOP,
						"p%d reason_id %d kayıtla tutarsız" % [v.id, v.decision_reason_id])
			else:
				_check(found == 0, "p%d 'budandı' ama günlükte kayıt %d var" % [v.id, found])
		print("QA2_HUD parcel=%d dev=%s by_sim=%s use=%s units=%d progress=%d decision=%s code=%s dtick=%d rid=%d" % [v.id,
				v.development, v.developed_by_sim, v.use, v.units, v.progress_pm, v.decision, v.decision_code, v.decision_tick,
				v.decision_reason_id])
		if v.developed_by_sim:
			_check(v.decision == ParcelView.DECISION_APPROVED, "p%d sim-geliştirilmiş ama karar %s" % [v.id, v.decision])
	if primary == null and not views.is_empty():
		primary = views[0]
	var exp := PackedStringArray()
	exp.append(UiText.t(&"m2.others", {"n": tracked.size(), "approved": appr, "declined": decl, "waiting": wait}))
	if primary != null:
		exp.append(UiText.humanize(String(primary.ref())))
		var post := primary.decision != ParcelView.DECISION_NONE and primary.decision_tick > res.proposed_tick
		if not post:
			exp.append(UiText.t(&"m2.investor.none") if primary.decision == ParcelView.DECISION_NONE else UiText.t(&"m2.investor.prior"))
		else:
			var date := UiText.tick_date(primary.decision_tick)
			exp.append(UiText.t(&"m2.investor.approved" if primary.decision == ParcelView.DECISION_APPROVED else &"m2.investor.declined",
					{"date": date}))
			if primary.decision_reason_id > 0:
				exp.append("[%s]" % UiText.t(&"m2.why"))
			else:
				exp.append(UiText.t(&"m2.investor.pruned"))
		if primary.development != ParcelView.DEVELOPMENT_VACANT and primary.use != ParcelView.USE_NONE:
			exp.append(UiText.t(&"m2.stage.line", {"stage": UiText.t(M2ResultModel.stage_key(primary.development)),
					"use": UiText.t(StringName("zoning.use.%s" % primary.use)), "units": primary.units}))
			exp.append(UiText.t(&"format.percent", {"value": UiText.number(primary.progress_pm / 10)}))
	for e in exp:
		_check(texts.has(e), "beklenen metin YOK: '%s'" % e)
	# Olmaması gerekenler
	if primary != null and primary.decision_reason_id > 0:
		_check(not texts.has(UiText.t(&"m2.investor.pruned")), "kayıt varken 'budandı' yazıyor")
	if primary != null and primary.decision != ParcelView.DECISION_NONE:
		_check(not texts.has(UiText.t(&"m2.investor.none")), "karar varken 'Henüz karar yok'")
	var eo := f.economy_outcome()
	var base: EconomyOutcomeView = res.baseline
	var city := eo.delta_since(base)
	for key in ["investments_approved", "investments_declined", "projects_completed"]:
		var val := int(city.get(key, 0))
		var s := ("+" if val > 0 else "") + UiText.number(val)
		_check(texts.has(s), "şehir sayacı %s=%s panelde yok" % [key, s])
	print("QA2_HUD expected=%s" % [" | ".join(exp)])
	print("QA2_HUD city_delta approved=%d declined=%d completed=%d rent=%d first_event_seq=%d" % [int(city.get("investments_approved", 0)),
			int(city.get("investments_declined", 0)), int(city.get("projects_completed", 0)), int(city.get("rent_income", 0)),
			f.first_retained_event_seq()])


func _projector_truth(scene: Node, frames_waited: int) -> void:
	var f: SimFacade = scene.get("_facade")
	var impl := f as SimFacadeImpl
	var proj: SimBuildingProjector = scene.get("_projector")
	var settlement: SettlementResult = scene.get("_settlement")
	var t0 := {}
	for pid in settlement.columns.occupied_parcels():
		t0[int(pid)] = true
	var d := EconomyState.data(impl.game_state())
	var ids: PackedInt64Array = d["parcel_ids"]
	var truth := {}
	for k in ids.size():
		var s: int = (d["stage"] as PackedByteArray)[k]
		if t0.has(int(ids[k])) or (d["last_code"] as PackedByteArray)[k] != EconomyState.CODE_APPROVED:
			continue
		if s != EconomyState.STAGE_UNDER_CONSTRUCTION and s != EconomyState.STAGE_BUILT and s != EconomyState.STAGE_STALLED:
			continue
		if proj.placer().plan(int(ids[k]), EconomyState.use_name((d["use"] as PackedByteArray)[k]), (d["units"] as PackedInt32Array)[k]) == null:
			continue
		truth[int(ids[k])] = true
	var shown := {}
	for pid in proj.parcel_ids():
		shown[int(pid)] = true
	var missing := 0
	for pid: int in truth:
		if not shown.has(pid):
			missing += 1
	var extra := 0
	for pid: int in shown:
		if not truth.has(pid):
			extra += 1
	_check(missing == 0 and extra == 0, "geri sarma sonrası projector missing=%d extra=%d" % [missing, extra])
	print("QA2_HUD rewind projector frames_waited=%d tick=%d truth=%d shown=%d missing=%d extra=%d full_syncs=%d" % [frames_waited, f.current_tick(), truth.size(), shown.size(), missing, extra, int(proj.stats["full_syncs"])])


func _collect(n: Node, out: PackedStringArray) -> void:
	if n is CanvasItem and not (n as CanvasItem).is_visible_in_tree():
		return
	if n is Label and (n as Label).text != "":
		out.append((n as Label).text.replace("\n", " "))
	elif n is Button and (n as Button).text != "":
		out.append("[%s]" % (n as Button).text)
	for c in n.get_children():
		_collect(c, out)
