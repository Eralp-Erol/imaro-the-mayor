extends SceneTree
## Bağımsız QA (iPad çekmecesi, D-021): GERÇEK `playable.tscn` (gerçek SimFacade, gerçek dünya + T0) üstünde dokunmatik
## profilde (`--imaro-input-profile=touch` kullanıcı argümanı) pencereli akış: Yol çiz -> iki dokunuş -> "Kamulaştırarak
## geç" -> "Yıkımı onayla" -> tick -> bildirim şeridi (B-081 satırı) -> imar -> sonuç -> gündem. Her aşamada ekran
## görüntüsü + ölçüm satırları (`DPROBE_*`). Ürün koduna yazmaz. Düğmeler fare tıklamasıyla, dünya dokunuşları gerçek
## `InputEventScreenTouch` ile basılır (`expropriation_game_probe.gd` ile aynı yöntem; gerçek parmak DEĞİL).
##
## tools/godot.sh --path . --resolution 1024x768 --script res://tools/godot/drawer_real_probe.gd -- \
##     --shots=<dizin> --prefix=land --imaro-input-profile=touch [--portrait-note]

const Support := preload("res://tests/game/expropriation_game_support.gd")
const SCENE := "res://scenes/game/playable.tscn"
const DT := 0.016667

var _args: Dictionary = {}
var _scene: Node = null
var _shots_dir: String = ""
var _prefix: String = "d"
var _windowed: bool = false


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	_args = _parse(OS.get_cmdline_user_args())
	_shots_dir = str(_args.get("shots", ""))
	_prefix = str(_args.get("prefix", "d"))
	_windowed = DisplayServer.get_name() != "headless"
	if not _shots_dir.is_empty():
		DirAccess.make_dir_recursive_absolute(_shots_dir)
	_scene = (load(SCENE) as PackedScene).instantiate()
	root.add_child(_scene)
	await process_frame
	await process_frame
	_scene.set_process(false)
	var facade: SimFacadeImpl = _scene._facade as SimFacadeImpl
	var hud: HudRoot = _scene._hud
	print("DPROBE_SETUP window=%s touch=%s drawer_ok=%s" % [str(root.size), str(hud.ctx.is_touch()),
			str(hud.ctx != null)])
	for _i in 30:
		await _frame()
	await _wait_vegetation()
	facade.set_speed(SimFacade.SPEED_PAUSED)
	facade.advance(2)
	var cand := Support.find_candidate(_scene, facade, &"D2", int(_args.get("seed", "7")), 400, 3)
	if cand.is_empty():
		print("DPROBE_FAIL no candidate")
		quit(3)
		return
	print("DPROBE_CANDIDATE ", JSON.stringify(cand["info"]))
	var a: Vector2 = cand["a"]
	var b: Vector2 = cand["b"]
	await _focus_on(a, b, float(_args.get("distance", "230")))
	_dump_toolbar("start")
	await _shot("0-start")

	# --- yol çiz ------------------------------------------------------------------------------------------------------
	var ctrl: RoadDrawController = _scene._pr.ctrl
	var tool: RoadDrawTool = ctrl.tool
	var btn := hud.toolbar.tool_button(ModeToolbar.TOOL_ROAD_DRAW)
	print("DPROBE_ROAD_BUTTON present=%s" % str(btn != null))
	if btn == null:
		quit(4)
		return
	await _click(btn.get_global_rect().get_center())
	for _i in 6:
		await _frame()
	_report("road_open", hud, tool)
	await _recenter_in_free_map((a + b) * 0.5)
	_report("road_recentered", hud, tool)
	await _shot("1-road-open")
	var sa := _screen(a)
	var sb := _screen(b)
	print("DPROBE_ENDS a=%s b=%s in_free(a)=%s in_free(b)=%s" % [str(sa), str(sb),
			str(hud.free_map_rect().has_point(sa)), str(hud.free_map_rect().has_point(sb))])
	await _tap(sa)
	for _i in 3:
		await _frame()
	_report("after_tap_a", hud, tool)
	await _tap(sb)
	for _i in 6:
		await _frame()
	_report("after_tap_b", hud, tool)
	_dump_buttons("review", hud)
	_overlay_report("review", ctrl, sa, sb)
	await _shot("2-review-half")

	# harita dokunuşu çekmece açıkken: B'yi biraz kaydır
	var b2 := b + (b - a).normalized().orthogonal() * 12.0
	var end_before := tool.end
	await _tap(_screen(b2))
	for _i in 4:
		await _frame()
	print("DPROBE_MAPTAP_WHILE_OPEN moved_end=%s end=%s -> %s step=%d" % [str(tool.end.distance_to(end_before) > 0.5),
			str(end_before), str(tool.end), tool.step])
	# çekmece gövdesine dokunuş (ScreenTouch) dünyaya sızmamalı
	var panel_c := hud.panel.get_global_rect().get_center()
	var end_b := tool.end
	await _tap(panel_c)
	for _i in 3:
		await _frame()
	var leaked := tool.end.distance_to(end_b) > 0.5 or tool.step != RoadDrawTool.Step.REVIEW
	print("DPROBE_PANELTAP leaked=%s step=%d" % [str(leaked), tool.step])
	await _tap(sb)
	for _i in 4:
		await _frame()

	var accept := Support.find_button(_scene._hud, UiText.t(&"expropriation.accept"))
	print("DPROBE_ACCEPT present=%s" % str(accept != null))
	if accept == null:
		_dump_buttons("no-accept", hud)
		await _shot("3-no-accept")
		quit(5)
		return
	print("DPROBE_ACCEPT rect=%s panel=%s viewport=%s" % [str(accept.get_global_rect()), str(hud.panel.get_global_rect()),
			str(root.size)])
	await _click(accept.get_global_rect().get_center())
	for _i in 6:
		await _frame()
	_report("after_accept", hud, tool)
	_dump_buttons("confirm-card", hud)
	_overlay_report("confirm", ctrl, sa, sb)
	await _shot("3-confirm-half")
	# onay kartı açıkken harita dokunuşu
	var e0 := tool.end
	await _tap(_screen(b + (b - a).normalized().orthogonal() * 8.0))
	for _i in 4:
		await _frame()
	print("DPROBE_MAPTAP_ON_CONFIRM moved_end=%s expropriate=%s demolishes=%s step=%d" % [
			str(tool.end.distance_to(e0) > 0.5), str(tool.expropriate), str(tool.demolishes()), tool.step])
	await _tap(sb)
	for _i in 4:
		await _frame()
	if not tool.expropriate:
		var acc2 := Support.find_button(_scene._hud, UiText.t(&"expropriation.accept"))
		if acc2 != null:
			await _click(acc2.get_global_rect().get_center())
			for _i in 4:
				await _frame()
	var confirm := Support.find_button(_scene._hud, UiText.t(&"expropriation.confirm"))
	print("DPROBE_CONFIRM present=%s" % str(confirm != null))
	if confirm == null:
		quit(6)
		return
	await _click(confirm.get_global_rect().get_center())
	await _frame()
	print("DPROBE_AFTER_CONFIRM step=%d" % tool.step)
	facade.advance(1)
	for _i in 60:
		await _frame()
	_report("after_tick", hud, tool)
	await _shot("4-built-half")

	# --- B-081 bildirim satırı: yıkım sonrası ticklerle -----------------------------------------------------------------
	var found := false
	for day in 40:
		hud.refresh()
		if (hud.strip as NotificationStrip).trust_text() != "":
			found = true
			print("DPROBE_TRUST day=%d text=%s" % [day, (hud.strip as NotificationStrip).trust_text()])
			break
		facade.advance(1)
		for _i in 3:
			await _frame()
	print("DPROBE_TRUST_FOUND %s rows=%s" % [str(found), str((hud.strip as NotificationStrip).row_texts())])
	_dump_strip(hud)
	await _shot("5-strip-drawer-open")
	ctrl.deactivate()
	for _i in 8:
		await _frame()
	_dump_strip(hud)
	await _shot("6-strip-only")
	# B-081 satırı YALNIZ başına (öteki satırlar temizlenince): sarma + çekmece açıkken sığma
	hud.strip.clear()
	for _i in 6:
		await _frame()
	print("DPROBE_TRUST_ALONE (strip.clear sonrası, çekmece kapalı)")
	_dump_strip(hud)
	await _shot("6b-trust-alone")
	ctrl.activate()
	for _i in 8:
		await _frame()
	print("DPROBE_TRUST_ALONE (çekmece YARI açık)")
	_dump_strip(hud)
	await _shot("6c-trust-alone-drawer-half")
	ctrl.deactivate()
	for _i in 6:
		await _frame()

	# --- imar -----------------------------------------------------------------------------------------------------------
	var zone := hud.toolbar.tool_button(ModeToolbar.TOOL_ZONE)
	print("DPROBE_ZONE_BUTTON present=%s" % str(zone != null))
	if zone == null:
		hud.toolbar.select_mode(ModeToolbar.MODE_PLAN)
		await _frame()
		zone = hud.toolbar.tool_button(ModeToolbar.TOOL_ZONE)
	if zone != null:
		await _click(zone.get_global_rect().get_center())
		for _i in 6:
			await _frame()
		_report("zone_open", hud, tool)
		_dump_buttons("zone", hud)
		await _shot("7-zone-open")
	# bir boş/yapılı parsele dokun: seç
	var pick := _pick_parcel_screen(a, b)
	print("DPROBE_PICK screen=%s" % str(pick))
	if pick != Vector2.ZERO:
		await _tap(pick)
		for _i in 8:
			await _frame()
		_report("zone_after_pick", hud, tool)
		_dump_buttons("zone-picked", hud)
		await _shot("8-zone-picked")
	# büyük plan (>= 10 parsel) -> meclis: dokunuşla 9 parsel daha, "Konut", "Planı sun"
	var taps := 0
	var picked := {}
	for sp in _parcel_screens_in_free_map(a, b, 14):
		if taps >= 11:
			break
		await _tap(sp)
		for _i in 2:
			await _frame()
		taps += 1
	var zp: ZoningFlowPanel = _scene._decisions.zoning_panel()
	print("DPROBE_ZONE_PARCELS count=%d taps=%d" % [_scene._decisions.zoning.parcel_ids.size(), taps])
	var use_btn := Support.find_button(_scene._hud, "Konut")
	if use_btn != null:
		await _click(use_btn.get_global_rect().get_center())
		for _i in 4:
			await _frame()
	_dump_buttons("zone-big", hud)
	await _shot("8b-zone-big-plan")
	var send_btn := Support.find_button(_scene._hud, UiText.t(&"zoning.submit"))
	if send_btn == null:
		send_btn = Support.find_button(_scene._hud, UiText.t(&"zoning.submit_direct"))
	print("DPROBE_SEND present=%s disabled=%s council_required=%s" % [str(send_btn != null),
			str(send_btn != null and send_btn.disabled), str(_scene._decisions.zoning.council_required())])
	if send_btn != null and not send_btn.disabled:
		await _click(send_btn.get_global_rect().get_center())
		for _i in 6:
			await _frame()
		_report("zone_sent", hud, tool)
		_dump_buttons("zone-sent", hud)
		await _shot("8c-zone-sent")
		for day in 30:
			facade.advance(1)
			for _i in 2:
				await _frame()
		hud.refresh()
		print("DPROBE_AFTER_PLAN days=30 council_votes=%s" % str(hud.snapshot().council.votes.size()
				if hud.snapshot().council != null and "votes" in hud.snapshot().council else -1))
	# sonuç
	var res := hud.toolbar.tool_button(ModeToolbar.TOOL_RESULTS)
	print("DPROBE_RESULTS_BUTTON present=%s" % str(res != null))
	if res != null:
		print("DPROBE_RESULTS_CLICK rect=%s panel_before=%s mode=%s tool=%s" % [str(res.get_global_rect()),
				String(hud.panel_id()), String(hud.toolbar.current_mode), String(hud.toolbar.current_tool)])
		var tool_trace: Array[String] = []
		hud.tool_selected.connect(func(t: StringName) -> void: tool_trace.append(String(t)))
		await _click(res.get_global_rect().get_center())
		for _i in 8:
			await _frame()
		print("DPROBE_RESULTS_TRACE panel=%s tool_events=%s" % [String(hud.panel_id()), str(tool_trace)])
		if hud.panel_id() != &"m2_results":
			print("DPROBE_RESULTS_RETRY (ilk tıklama sonuç panelini açmadı)")
			await _click(res.get_global_rect().get_center())
			for _i in 8:
				await _frame()
			print("DPROBE_RESULTS_TRACE2 panel=%s tool_events=%s" % [String(hud.panel_id()), str(tool_trace)])
		_report("results", hud, tool)
		_dump_buttons("results", hud)
		await _shot("9-results")
	# gündem rozeti
	var badge: Control = hud.top_bar.agenda
	print("DPROBE_AGENDA_BADGE visible=%s" % str(badge.visible))
	hud.agenda_requested.emit()
	for _i in 8:
		await _frame()
	_report("agenda", hud, tool)
	_dump_buttons("agenda", hud)
	await _shot("10-agenda")
	_scene._decisions.open_council()
	for _i in 8:
		await _frame()
	_report("council_programmatic", hud, tool)
	_dump_buttons("council", hud)
	await _shot("10a-council-programmatic")
	_scene._decisions.open_budget()
	for _i in 8:
		await _frame()
	_report("budget_programmatic", hud, tool)
	_dump_buttons("budget", hud)
	await _shot("10a2-budget-programmatic")
	hud.agenda_requested.emit()
	for _i in 6:
		await _frame()
	hud.set_drawer_state(DrawerModel.State.FULL)
	for _i in 6:
		await _frame()
	_report("agenda_full", hud, tool)
	_dump_buttons("agenda-full", hud)
	await _shot("10b-agenda-full")
	hud.set_drawer_state(DrawerModel.State.HALF)
	hud.close_panel_hard()
	for _i in 4:
		await _frame()
	var manage := hud.toolbar.mode_button(ModeToolbar.MODE_MANAGE)
	var manage_ok := manage != null and manage.is_visible_in_tree()
	print("DPROBE_MANAGE_BUTTON present=%s visible=%s" % [str(manage != null), str(manage_ok)])
	if manage != null and manage.is_visible_in_tree():
		await _click(manage.get_global_rect().get_center())
		for _i in 4:
			await _frame()
		_dump_toolbar("manage")
		await _shot("11-manage-mode")
		for tid in [ModeToolbar.TOOL_COUNCIL, ModeToolbar.TOOL_BUDGET, ModeToolbar.TOOL_AGENDA, ModeToolbar.TOOL_POLICY]:
			var tb := hud.toolbar.tool_button(tid)
			print("DPROBE_TOOL %s present=%s" % [String(tid), str(tb != null)])
			if tb != null:
				await _click(tb.get_global_rect().get_center())
				for _i in 8:
					await _frame()
				_report(String(tid), hud, tool)
				_dump_buttons(String(tid), hud)
				await _shot("12-%s" % String(tid).trim_prefix("tool."))
	quit(0)


func _pick_parcel_screen(a: Vector2, b: Vector2) -> Vector2:
	var net: WorldNetwork = _scene._net
	var mid := (a + b) * 0.5
	var best := Vector2.ZERO
	var best_d := INF
	for pid: int in net.parcels:
		var c: Vector2 = net.parcels[pid].centroid
		var d := c.distance_to(mid)
		if d < best_d and d > 25.0 and net.parcel_id_at(c.x, c.y) == pid:
			var s := _screen(c)
			if (_scene._hud as HudRoot).free_map_rect().has_point(s):
				best_d = d
				best = s
	return best


func _parcel_screens_in_free_map(a: Vector2, b: Vector2, want: int) -> Array[Vector2]:
	var net: WorldNetwork = _scene._net
	var hud: HudRoot = _scene._hud
	var mid := (a + b) * 0.5
	var cands: Array[Vector3] = []
	for pid: int in net.parcels:
		var c: Vector2 = net.parcels[pid].centroid
		if net.parcel_id_at(c.x, c.y) != pid:
			continue
		var d := c.distance_to(mid)
		if d > 160.0:
			continue
		var sc := _screen(c)
		if hud.free_map_rect().grow(-20.0).has_point(sc):
			cands.append(Vector3(d, sc.x, sc.y))
	cands.sort_custom(func(p: Vector3, q: Vector3) -> bool: return p.x < q.x)
	var out: Array[Vector2] = []
	for v in cands:
		out.append(Vector2(v.y, v.z))
		if out.size() >= want:
			break
	return out


func _report(tag: String, hud: HudRoot, tool: RoadDrawTool) -> void:
	var win := Vector2(root.size)
	var free := hud.free_map_rect()
	var pr := hud.panel.get_global_rect() if hud.is_panel_open() else Rect2()
	print(("DPROBE_STATE %s panel=%s drawer_active=%s drawer_state=%d step=%d free=%s free_frac=%.2f "
			+ "panel_frac=%.2f panel=%s") % [
			tag, String(hud.panel_id()), str(hud.is_drawer_active()), hud.drawer_state, tool.step, str(free),
			free.get_area() / (win.x * win.y), pr.get_area() / (win.x * win.y), str(pr)])


func _dump_toolbar(tag: String) -> void:
	var hud: HudRoot = _scene._hud
	var names: Array[String] = []
	for btn in hud.toolbar.all_buttons():
		names.append("%s[%s]" % [btn.text, str(btn.get_global_rect())])
	print("DPROBE_TOOLBAR %s rows=%d %s" % [tag, hud.toolbar.rows(), " ".join(names)])


func _dump_buttons(tag: String, hud: HudRoot) -> void:
	var out: Array[String] = []
	_collect_buttons(hud.panel, out)
	print("DPROBE_PANEL_BUTTONS %s %s" % [tag, " | ".join(out)])


func _collect_buttons(n: Node, out: Array[String]) -> void:
	if n is Button and (n as Button).is_visible_in_tree():
		var c := n as Button
		var r := c.get_global_rect()
		var screen_ok := Rect2(Vector2.ZERO, Vector2(root.size)).encloses(r)
		var hud: HudRoot = _scene._hud
		var in_panel := hud.panel.get_global_rect().grow(1.0).encloses(r)
		out.append("%s@%s%s" % [c.text.left(28), str(r.position.round()) + str(r.size.round()),
				"" if screen_ok and in_panel else (" OFFSCREEN" if not screen_ok else " BELOW_FOLD")])
	for ch in n.get_children():
		_collect_buttons(ch, out)


func _overlay_report(tag: String, ctrl: RoadDrawController, sa: Vector2, sb: Vector2) -> void:
	var tip := Rect2(ctrl.tip.position, ctrl.tip.size) if ctrl.tip.visible else Rect2()
	var chip := ctrl.chip.get_global_rect() if ctrl.chip.visible else Rect2()
	print(("DPROBE_OVERLAY %s tip_visible=%s tip=%s chip_visible=%s chip=%s tip_x_chip=%s tip_has_A=%s "
			+ "tip_has_B=%s chip_has_B=%s") % [
			tag, str(ctrl.tip.visible), str(tip), str(ctrl.chip.visible), str(chip),
			str(tip.intersects(chip) if ctrl.tip.visible and ctrl.chip.visible else false),
			str(tip.has_point(sa)), str(tip.has_point(sb)), str(chip.has_point(sb))])


func _dump_strip(hud: HudRoot) -> void:
	var strip: NotificationStrip = hud.strip
	print("DPROBE_STRIP_STATE trust_members=%s trust_row_exists=%s trust_row_visible=%s max_h=%.0f children=%d" % [
			str(strip.get("_trust_members")), str(strip.get("_trust_row") != null),
			str(strip.get("_trust_row") != null and (strip.get("_trust_row") as Control).visible),
			float(strip.get("_max_height")), strip.get_child_count()])
	var parts: Array[String] = []
	for row in strip.get_children():
		var c := row as Control
		if c != null and c.visible:
			var lbls: Array[String] = []
			_collect_labels(c, lbls)
			parts.append("%s size=%s lines=%s" % [str(c.get_global_rect()), str(c.size), " / ".join(lbls)])
	print("DPROBE_STRIP strip_rect=%s max_h=%s rows=%d :: %s" % [str(strip.get_global_rect()),
			str(hud.layout.notifications_max_h), parts.size(), " || ".join(parts)])


func _collect_labels(n: Node, out: Array[String]) -> void:
	if n is Label and (n as Label).visible:
		var l := n as Label
		out.append("'%s' lines=%d wrap=%d h=%.0f" % [l.text.left(70), l.get_line_count(), l.autowrap_mode, l.size.y])
	for ch in n.get_children():
		_collect_labels(ch, out)


func _frame(dt: float = DT) -> void:
	_scene._process(dt)
	await process_frame


func _screen(world_xz: Vector2) -> Vector2:
	return Support.screen_of(_scene, world_xz)


func _focus_on(a: Vector2, b: Vector2, distance: float) -> void:
	var cam: CameraRig = _scene._camera
	var st := cam.target_state()
	var mid := (a + b) * 0.5
	st.focus_x = mid.x
	st.focus_z = mid.y
	st.distance = distance
	cam.apply_state(st, true)
	for _i in 6:
		await _frame()


## Odağı, yolun orta noktası serbest harita dikdörtgeninin ortasına düşecek biçimde kaydırır (oyuncunun kaydırması).
func _recenter_in_free_map(mid: Vector2) -> void:
	var cam: CameraRig = _scene._camera
	var hud: HudRoot = _scene._hud
	var want := hud.free_map_rect().get_center()
	for _it in 3:
		var st := cam.target_state()
		var s0 := _screen(mid)
		st.focus_x += 20.0
		cam.apply_state(st, true)
		await _frame()
		var sx := (_screen(mid) - s0) / 20.0
		st.focus_x -= 20.0
		st.focus_z += 20.0
		cam.apply_state(st, true)
		await _frame()
		var sz := (_screen(mid) - s0) / 20.0
		st.focus_z -= 20.0
		cam.apply_state(st, true)
		await _frame()
		var d := want - s0
		var det := sx.x * sz.y - sz.x * sx.y
		if absf(det) < 0.0001:
			return
		st = cam.target_state()
		st.focus_x += (d.x * sz.y - sz.x * d.y) / det
		st.focus_z += (sx.x * d.y - d.x * sx.y) / det
		cam.apply_state(st, true)
		for _i in 3:
			await _frame()


func _tap(pos: Vector2) -> void:
	for pressed in [true, false]:
		var e := InputEventScreenTouch.new()
		e.index = 0
		e.pressed = pressed
		e.position = pos
		root.push_input(e)
		await _frame()


func _click(pos: Vector2) -> void:
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = pressed
		e.position = pos
		e.global_position = pos
		root.push_input(e)
		await _frame()


func _wait_vegetation() -> void:
	var veg: VegetationView = _scene.get("_vegetation")
	if veg == null:
		return
	var t0 := Time.get_ticks_msec()
	while veg.layout == null and Time.get_ticks_msec() - t0 < 240000:
		await _frame()
	for _i in 40:
		await _frame()
	var n := 0
	while n < 600 and (int(veg.stats.get("queued", 0)) != 0 or int(veg.stats.get("blob_jobs", 0)) != 0):
		await _frame()
		n += 1
	print("DPROBE_VEG ready=%s wait_ms=%d" % [str(veg.layout != null), Time.get_ticks_msec() - t0])


func _shot(name: String) -> void:
	if _shots_dir.is_empty() or not _windowed:
		return
	for _i in 4:
		await _frame()
	var path := "%s/%s-%s.png" % [_shots_dir, _prefix, name]
	root.get_viewport().get_texture().get_image().save_png(path)
	print("DPROBE_SHOT ", path)


func _parse(args: PackedStringArray) -> Dictionary:
	var out := {}
	for a in args:
		if a.begins_with("--"):
			var kv := a.trim_prefix("--").split("=", true, 1)
			out[kv[0]] = kv[1] if kv.size() > 1 else "1"
	return out
