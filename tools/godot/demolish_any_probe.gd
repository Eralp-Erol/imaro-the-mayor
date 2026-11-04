extends SceneTree
## "Her yolu yık" (D-014 §1) pencereli kare üreteci: gerçek `playable.tscn`, sim'e iki GERÇEK kamulaştırmalı yol komutu,
## sonra yol aracı (Y) -> "Başka yolu yık" listesi -> "Yol 1" satırı -> onay kartı. Yıkım yapılmaz ("Vazgeç").
## Pencereli: tools/godot.sh --path . --resolution 1600x900 --script res://tools/godot/demolish_any_probe.gd --
##   --shots=<dizin> [--prefix=ad] [--imaro-input-profile=touch]
## Çıktı satırları: DPROBE_*.

const Support := preload("res://tests/game/expropriation_game_support.gd")
const DT := 0.016667

var _args: Dictionary = {}
var _scene: Node = null


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		_args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var packed: PackedScene = load("res://scenes/game/playable.tscn")
	_scene = packed.instantiate()
	root.add_child(_scene)
	await process_frame
	await process_frame
	_scene.set_process(false)
	var facade: SimFacadeImpl = _scene._facade as SimFacadeImpl
	for _i in 30:
		await _frame()
	_scene._facade.set_speed(SimFacade.SPEED_PAUSED)
	var first := Support.find_candidate(_scene, facade, &"D2", 7, 400, 0)
	var second := Support.find_candidate(_scene, facade, &"D2", 23, 400, 0)
	for cand: Dictionary in [first, second]:
		if cand.is_empty():
			push_error("probe: aday yol yok")
			quit(3)
			return
		var res := facade.submit_command(SimCommand.public_work_road(cand["cm"], RoadDrawTool.ROAD_CLASS, true))
		print("DPROBE_ROAD status=%s reason=%s" % [String(res.status), String(res.reason_key)])
		facade.advance(1)
		for _i in 20:
			await _frame()
	var waited := 0
	while waited < 900 and (_scene._pr.follow.busy() or _scene._pr.sync.world_busy() or waited < 60):
		await _frame()
		waited += 1
	print("DPROBE_WAIT frames=%d busy=%s" % [waited, str(_scene._pr.sync.world_busy())])
	print("DPROBE_WORKS count=%d" % facade.public_works().size())
	var cam: CameraRig = _scene._camera
	var st := cam.target_state()
	var a: Vector2 = first["a"]
	var b: Vector2 = second["b"]
	st.focus_x = (a.x + b.x) * 0.5
	st.focus_z = (a.y + b.y) * 0.5
	st.distance = 260.0
	cam.apply_state(st, true)
	for _i in 10:
		await _frame()
	_key(KEY_Y)
	for _i in 40:
		await _frame()
	var waited_btn := 0
	while _find_prefix("Son yolu yık") == null and waited_btn < 900:   # sim "dünya hazırlanıyor" derken düğme yok
		await _frame()
		waited_btn += 1
	print("DPROBE_PANEL_READY frames=%d" % waited_btn)
	await _shot("1-panel")
	var toggle := _find_prefix("Başka yolu yık")
	# Panel plan ipucu taraması bitince yeniden çizilebilir (basış ile bırakış arasında düğme yenilenirse tık kaybolur):
	# düğme görünene kadar en çok 4 kez dene.
	for _try in 4:
		toggle = _find_prefix("Başka yolu yık")
		if toggle == null:
			break
		await _click(toggle.get_global_rect().get_center())
		for _i in 10:
			await _frame()
	await _shot("2-list")
	var row := _find_prefix("Yol 1:")
	if row == null:
		push_error("probe: Yol 1 satırı yok")
		quit(5)
		return
	print("DPROBE_ROW rect=%s" % str(row.get_global_rect()))
	await _click(row.get_global_rect().get_center())
	for _i in 4:
		await _frame()
	await _shot("3-confirm")
	var keep := _find_prefix(UiText.t(&"road.demolish_keep"))
	if keep != null:
		await _click(keep.get_global_rect().get_center())
	print("DPROBE_END works=%d" % facade.public_works().size())
	quit(0)


func _frame() -> void:
	_scene._process(DT)
	await process_frame


func _find_prefix(prefix: String) -> Button:
	var stack: Array[Node] = [_scene._hud]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		var btn := n as Button
		if btn != null and btn.is_visible_in_tree() and btn.text.begins_with(prefix):
			return btn
		stack.append_array(n.get_children())
	return null


func _click(pos: Vector2) -> void:
	var m := InputEventMouseMotion.new()
	m.position = pos
	m.global_position = pos
	root.push_input(m)
	await _frame()
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = pressed
		e.position = pos
		e.global_position = pos
		root.push_input(e)
		await _frame()


func _key(code: Key) -> void:
	for pressed in [true, false]:
		var e := InputEventKey.new()
		e.keycode = code
		e.pressed = pressed
		root.push_input(e)


func _shot(label: String) -> void:
	var dir := str(_args.get("shots", ""))
	if dir.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(dir)
	for _i in 4:
		await _frame()
	var path := "%s/%s-%s.png" % [dir, str(_args.get("prefix", "demolish-any")), label]
	root.get_viewport().get_texture().get_image().save_png(path)
	print("DPROBE_SHOT ", path)
