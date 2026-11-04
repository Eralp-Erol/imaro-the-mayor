extends SceneTree
## B-015 UI ucu: kamulaştırmalı yol -> onay -> yıkma -> AYNI şeride yeniden çiz -> sıfır parsellik teklif metni.
## Gerçek `playable.tscn`, gerçek viewport girdisi (fare). Pencereli: tools/godot.sh --path . --resolution 1600x900
## --script res://tools/godot/zero_parcel_probe.gd -- --shots=<klasör>. Çıktı satırları: ZPROBE_*.

const Support := preload("res://tests/game/expropriation_game_support.gd")
const SCENE := "res://scenes/game/playable.tscn"

var _scene: Node = null
var _shots := ""


func _initialize() -> void:
	run.call_deferred()


func _frames(n: int) -> void:
	for _i in n:
		await process_frame


func _click(pos: Vector2) -> void:
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = pressed
		e.position = pos
		e.global_position = pos
		root.push_input(e)
		await process_frame


func _move(pos: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = pos
	e.global_position = pos
	root.push_input(e)


func _key(code: Key) -> void:
	for pressed in [true, false]:
		var e := InputEventKey.new()
		e.keycode = code
		e.pressed = pressed
		root.push_input(e)


func _shot(name: String) -> void:
	await _frames(6)
	if _shots.is_empty():
		return
	var path := "%s/%s.png" % [_shots, name]
	root.get_viewport().get_texture().get_image().save_png(path)
	print("ZPROBE_SHOT ", path)


func _draw(a: Vector2, b: Vector2) -> void:
	if not _scene._pr.ctrl.is_active():
		_key(KEY_Y)
		await _frames(4)
	await _click(Support.screen_of(_scene, a))
	for k in 5:
		_move(Support.screen_of(_scene, a.lerp(b, float(k + 1) / 5.0)))
		await _frames(2)
	await _click(Support.screen_of(_scene, b))
	await _frames(4)


func _texts(node: Node, out: Array) -> void:
	if node is Label and (node as Label).is_visible_in_tree():
		out.append((node as Label).text)
	elif node is Button and (node as Button).is_visible_in_tree():
		out.append("[%s]" % (node as Button).text)
	for c in node.get_children():
		_texts(c, out)


func _report(tag: String, tool: RoadDrawTool) -> void:
	var out: Array = []
	_texts(_scene._hud, out)
	print("ZPROBE_STATE %s step=%d valid=%s expropriate=%s offer=%s verdict=%s taken=%s can_confirm=%s" % [tag, tool.step,
			str(tool.is_valid()), str(tool.expropriate), str(not tool.offer().is_empty()),
			String(tool.verdict.reason_key) if tool.verdict != null else "-",
			str(tool.verdict.args.get("taken_parcels", "yok")) if tool.verdict != null else "-", str(tool.can_confirm())])
	print("ZPROBE_TEXT %s %s" % [tag, JSON.stringify(out)])


func _press(text: String) -> bool:
	var btn := Support.find_button(_scene._hud, text)
	if btn == null or btn.disabled:
		return false
	await _click(btn.get_global_rect().get_center())
	await _frames(4)
	return true


func run() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			_shots = a.trim_prefix("--shots=")
	if not _shots.is_empty():
		DirAccess.make_dir_recursive_absolute(_shots)
	if DisplayServer.get_name() == "headless":
		root.size = Vector2i(1600, 900)
	_scene = (load(SCENE) as PackedScene).instantiate()
	root.add_child(_scene)
	await _frames(3)
	var facade := _scene._facade as SimFacadeImpl
	facade.set_speed(SimFacade.SPEED_PAUSED)
	facade.advance(2)
	await _frames(40)
	var cand := Support.find_candidate(_scene, facade)
	if cand.is_empty():
		push_error("aday yok")
		quit(3)
		return
	var a: Vector2 = cand["a"]
	var b: Vector2 = cand["b"]
	var cam: CameraRig = _scene._camera
	var st := cam.target_state()
	st.focus_x = (a.x + b.x) * 0.5
	st.focus_z = (a.y + b.y) * 0.5
	st.distance = 230.0
	cam.apply_state(st, true)
	await _frames(8)
	var tool: RoadDrawTool = _scene._pr.ctrl.tool
	await _draw(a, b)
	await _shot("0-first-offer")
	await _press(UiText.t(&"expropriation.accept"))
	await _press(UiText.t(&"expropriation.confirm"))
	facade.advance(1)
	await _frames(30)
	print("ZPROBE_WORKS after_first=%d" % facade.public_works().size())
	facade.submit_command(SimCommand.public_work_demolish(facade.public_works()[0].command_id))
	facade.advance(1)
	await _frames(60)
	print("ZPROBE_WORKS after_demolish=%d" % facade.public_works().size())
	await _draw(a, b)
	_report("redraw", tool)
	await _shot("1-redraw-review")
	var accepted: bool = await _press(UiText.t(&"expropriation.accept"))
	if not accepted:
		accepted = await _press(UiText.t(&"expropriation.empty_accept"))
	print("ZPROBE_ACCEPTED %s" % str(accepted))
	_report("accepted", tool)
	await _shot("2-redraw-accepted")
	var built: bool = await _press(UiText.t(&"road.confirm"))
	print("ZPROBE_CONFIRMED %s" % str(built))
	facade.advance(1)
	await _frames(30)
	print("ZPROBE_WORKS after_redraw=%d" % facade.public_works().size())
	await _shot("3-after-redraw")
	quit(0)
