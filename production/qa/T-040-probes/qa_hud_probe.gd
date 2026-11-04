extends SceneTree
## QA T-040 (f): gerçek playable.tscn'yi (aynı dev argümanlarıyla) kurar, "Döngü sonucu" panelindeki METİNLERİ toplar ve
## sim'den bağımsız hesapla karşılaştırır. Argümanlar oyun argümanlarıdır (-- sonrası).

var fails := 0


func _initialize() -> void:
	var scene: Node = load("res://scenes/game/playable.tscn").instantiate()
	root.add_child(scene)
	for i in 30:
		await process_frame
	var f: SimFacade = scene.get("_facade")
	var res: M2Results = scene.get("_m2_results")
	var texts := PackedStringArray()
	var panel := res.results_panel()
	if panel == null:
		print("QA_HUD panel=null (açık değil)")
	else:
		_collect(panel, texts)
	print("QA_HUD tick=%d panel_text=%s" % [f.current_tick(), " | ".join(texts)])
	# Bağımsız hesap
	var eo := f.economy_outcome()
	var tracked: PackedInt64Array = res.tracked
	var pv := f.parcel_views(tracked.slice(0, 1))[0]
	var rd := eo.region(pv.region_code)
	print("QA_HUD sim parcel=%d dev=%s use=%s units=%d progress=%d zone=%s pending=%s" % [pv.id, pv.development, pv.use,
			pv.units, pv.progress_pm, pv.zone, pv.pending_zone])
	print("QA_HUD sim region=%s sim_res=%d sim_com=%d housed=%d households=%d pipe_res=%d pipe_com=%d" % [rd.region_code,
			rd.sim_residential_units, rd.sim_commercial_units, rd.housed_households, rd.households,
			rd.residential_pipeline, rd.commercial_pipeline])
	print("QA_HUD sim city approved=%d declined=%d completed=%d rent=%d municipal_avail=%s baseline=%s" % [
			eo.investments_approved, eo.investments_declined, eo.projects_completed, eo.rent_income,
			eo.municipal_revenue_available, res.baseline])
	var appr := 0
	var decl := 0
	var none := 0
	for v in f.parcel_views(tracked):
		var rec := M2ResultModel.latest_investor_decision(f, v.id)
		if rec == null:
			none += 1
		elif rec.outcome == ReasonRecord.OUTCOME_POSITIVE:
			appr += 1
		else:
			decl += 1
	print("QA_HUD tracked=%d approved=%d declined=%d none=%d" % [tracked.size(), appr, decl, none])
	var snap := f.snapshot()
	for g in snap.group_reactions:
		print("QA_HUD group=%d reaction=%s intensity=%d stance=%d" % [g.group.id, g.reaction, g.intensity, g.stance])
	quit(0)


func _collect(n: Node, out: PackedStringArray) -> void:
	if n is Label and (n as Label).visible and (n as Label).text != "":
		out.append((n as Label).text.replace("\n", " "))
	elif n is Button and (n as Button).text != "":
		out.append("[%s]" % (n as Button).text)
	for c in n.get_children():
		_collect(c, out)
