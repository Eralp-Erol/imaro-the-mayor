extends SceneTree
## QA T-040 2. tur (B-001 kalıntısı, gerçek playable.tscn, VARSAYILAN rejim, pencereli): öneri anındaki tick'te (T) otonom
## olarak reddedilmiş boş bir parsel seçilir ve oyuncu yolu (seçili parsel + gerçek Z tuşu olayı -> _submit_demo ->
## track_parcels) ile imar önerisi verilir. Yatırımcı öneriyi henüz DEĞERLENDİRMEDİ; panel ne diyor?
## Oyun argümanları -- sonrası (ör. --preset=district:D1). --qa-out=<png> --qa-days=N

const QW := preload("qa_world.gd")


func _initialize() -> void:
	var out := ""
	var days := 30
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--qa-out="):
			out = a.split("=")[1]
		if a.begins_with("--qa-days="):
			days = int(a.split("=")[1])
	var scene: Node = load("res://scenes/game/playable.tscn").instantiate()
	root.add_child(scene)
	for i in 5:
		await process_frame
	var f: SimFacade = scene.get("_facade")
	f.set_speed(SimFacade.SPEED_PAUSED)
	f.advance(days)
	var settlement: SettlementResult = scene.get("_settlement")
	var t0 := {}
	for pid in settlement.columns.occupied_parcels():
		t0[int(pid)] = true
	var tick := f.current_tick()
	var pick := -1
	var feed := f.parcel_changes_since(tick - 1)
	for v in f.parcel_views(feed.ids):
		if t0.has(v.id) or v.development != ParcelView.DEVELOPMENT_VACANT or v.pending_zone != &"":
			continue
		if v.decision == ParcelView.DECISION_DECLINED and v.decision_tick == tick:
			pick = v.id
			break
	print("QA2_SAME tick=%d pick=%d" % [tick, pick])
	if pick < 0:
		quit(2)
		return
	var before := f.parcel_views(PackedInt64Array([pick]))[0]
	var reasons_before := 0
	for rec in f.reasons_for(before.ref()):
		if rec.decision_key == &"decision.investor.develop":
			reasons_before += 1
	scene.set("_selected_parcel_id", pick)
	var ev := InputEventKey.new()
	ev.keycode = KEY_Z
	ev.physical_keycode = KEY_Z
	ev.pressed = true
	root.push_input(ev)
	var ev2 := ev.duplicate()
	ev2.pressed = false
	root.push_input(ev2)
	for i in 5:
		await process_frame
	var res: M2Results = scene.get("_m2_results")
	if res.results_panel() == null:
		res.open()
	for i in 20:
		await process_frame
	var texts := PackedStringArray()
	_collect(res.results_panel(), texts)
	var v := f.parcel_views(PackedInt64Array([pick]))[0]
	var reasons_after := 0
	for rec in f.reasons_for(v.ref()):
		if rec.decision_key == &"decision.investor.develop":
			reasons_after += 1
	print("QA2_SAME after tick=%d tracked=%s proposed_tick=%d parcel decision=%s code=%s dtick=%d pending=%s develop_reasons before=%d after=%d" % [
			f.current_tick(), res.tracked, res.proposed_tick, v.decision, v.decision_code, v.decision_tick, v.pending_zone,
			reasons_before, reasons_after])
	print("QA2_SAME panel_text=%s" % " | ".join(texts))
	if out != "":
		var img := root.get_texture().get_image()
		img.save_png(out)
		print("QA2_SAME shot=%s" % out)
	quit(0)


func _collect(n: Node, out: PackedStringArray) -> void:
	if n == null:
		return
	if n is CanvasItem and not (n as CanvasItem).is_visible_in_tree():
		return
	if n is Label and (n as Label).text != "":
		out.append((n as Label).text.replace("\n", " "))
	elif n is Button and (n as Button).text != "":
		out.append("[%s]" % (n as Button).text)
	for c in n.get_children():
		_collect(c, out)
