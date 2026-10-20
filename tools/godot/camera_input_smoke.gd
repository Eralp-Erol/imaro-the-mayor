extends SceneTree
## T-003 ölçüt 5 · PENCERELİ girdi duman testi: gerçek Godot girdi boru hattı (Input.parse_input_event -> Viewport ->
## _input -> GUI -> _unhandled_input -> CameraRig -> InputProfile). Başsız testlerden FARKI: gerçek viewport
## yönlendirmesi ve "UI dünyadan önce" kuralı (bir Control olayı tüketince kamera kıpırdamaz) denenir.
## OS düzeyi fare/trackpad/dokunma DEĞİLDİR (donanım gerekir; elle denenir, rapora yazılır).
##   tools/godot.sh --path . --resolution 800x450 --script res://tools/godot/camera_input_smoke.gd -- [--cell=400]
##   ... -- --imaro-input-profile=touch  -> dokunmatik: tek parmak pan, iki parmak kıstır zoom + bük döndür.
## Çıktı: CAMERA_INPUT_SMOKE {json}; tüm kontroller geçerse çıkış 0, değilse 1.

const SCENE := "res://scenes/dev/world_preview.tscn"


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	var scene: Node = (load(SCENE) as PackedScene).instantiate()
	root.add_child(scene)
	await _frames(6)
	var rig: CameraRig = scene.camera()
	rig.smoothing_enabled = false
	var size := root.get_visible_rect().size
	var c := size * 0.5
	var report := {"viewport": [size.x, size.y], "profile": rig.input_profile.profile_name}
	var ok := true
	if rig.input_profile.profile_name == InputProfile.PROFILE_TOUCH:
		ok = await _run_touch(rig, c, report)
		report["pass"] = ok
		print("CAMERA_INPUT_SMOKE ", JSON.stringify(report))
		quit(0 if ok else 1)
		return

	# 1) Tekerlek zoom: imleç altındaki zemin noktası sabit.
	var cursor := c + Vector2(120.0, -60.0)
	_motion(cursor, Vector2.ZERO)
	await _frames(2)
	var d0 := rig.distance()
	var anchor := rig.screen_to_ground(cursor)
	for i in 3:
		_wheel(cursor, MOUSE_BUTTON_WHEEL_UP)
		await _frames(1)
	var anchor_after := rig.screen_to_ground(cursor)
	var drift := Vector3(anchor["x"] - anchor_after["x"], anchor["y"] - anchor_after["y"],
			anchor["z"] - anchor_after["z"]).length()
	report["zoom"] = {
		"d0": snappedf(d0, 0.1), "d1": snappedf(rig.distance(), 0.1), "anchor_drift_m": snappedf(drift, 0.01),
	}
	ok = ok and rig.distance() < d0 * 0.8 and drift < d0 * 0.002

	# 2) Sol sürükle pan: tutulan zemin noktası imleci izler.
	var from := c + Vector2(-80.0, 40.0)
	var grabbed := rig.screen_to_ground(from)
	_button(from, MOUSE_BUTTON_LEFT, true)
	var pos := from
	for i in 8:
		var nxt := pos + Vector2(18.0, -9.0)
		_motion(nxt, nxt - pos)
		pos = nxt
		await _frames(1)
	_button(pos, MOUSE_BUTTON_LEFT, false)
	await _frames(1)
	var held := rig.screen_to_ground(pos)
	var pan_err := Vector3(grabbed["x"] - held["x"], grabbed["y"] - held["y"], grabbed["z"] - held["z"]).length()
	report["pan"] = {"follow_error_m": snappedf(pan_err, 0.01), "cursor_travel_px": snappedf(from.distance_to(pos), 0.1)}
	ok = ok and pan_err < rig.distance() * 0.01

	# 3) Orta tuş sürükle: pozitif hareket = sahne saat yönünde = yön azalır.
	var h0 := rig.current_state().heading_deg
	_button(c, MOUSE_BUTTON_MIDDLE, true)
	_motion(c + Vector2(60.0, 0.0), Vector2(60.0, 0.0))
	_button(c + Vector2(60.0, 0.0), MOUSE_BUTTON_MIDDLE, false)
	await _frames(1)
	var turned := CameraState.angle_delta_deg(h0, rig.current_state().heading_deg)
	report["rotate"] = {"heading_delta_deg": snappedf(turned, 0.01)}
	ok = ok and turned < -20.0

	# 4) UI dünyadan önce: tüm ekranı kaplayan bir Button olayı tüketir, kamera kıpırdamaz.
	var layer := CanvasLayer.new()
	var button := Button.new()
	button.set_anchors_preset(Control.PRESET_FULL_RECT)
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(button)
	scene.add_child(layer)
	await _frames(2)
	var before_ui := rig.current_state()
	_wheel(cursor, MOUSE_BUTTON_WHEEL_UP)
	_button(c, MOUSE_BUTTON_LEFT, true)
	_motion(c + Vector2(40.0, 10.0), Vector2(40.0, 10.0))
	_button(c + Vector2(40.0, 10.0), MOUSE_BUTTON_LEFT, false)
	await _frames(2)
	var moved_under_ui := not rig.current_state().is_close_to(before_ui, 0.001)
	report["ui_first"] = {"camera_moved_under_ui": moved_under_ui}
	ok = ok and not moved_under_ui
	layer.queue_free()
	await _frames(2)

	# 5) UI kalkınca kamera yeniden yanıt verir.
	var d_free := rig.distance()
	_wheel(cursor, MOUSE_BUTTON_WHEEL_UP)
	await _frames(2)
	report["ui_released"] = {"zoomed_again": rig.distance() < d_free}
	ok = ok and rig.distance() < d_free

	report["pass"] = ok
	print("CAMERA_INPUT_SMOKE ", JSON.stringify(report))
	quit(0 if ok else 1)


## Dokunmatik: tek parmak sürükle = pan (tutulan zemin parmağı izler), iki parmak ayrılma = zoom, bükme = döndürme.
func _run_touch(rig: CameraRig, c: Vector2, report: Dictionary) -> bool:
	var from := c + Vector2(-60.0, 30.0)
	var grabbed := rig.screen_to_ground(from)
	_touch(0, from, true)
	var pos := from
	for i in 8:
		var nxt := pos + Vector2(15.0, -8.0)
		_drag(0, nxt, nxt - pos)
		pos = nxt
		await _frames(1)
	_touch(0, pos, false)
	await _frames(1)
	var held := rig.screen_to_ground(pos)
	var pan_err := Vector3(grabbed["x"] - held["x"], grabbed["y"] - held["y"], grabbed["z"] - held["z"]).length()
	report["touch_pan"] = {"follow_error_m": snappedf(pan_err, 0.01)}
	var d0 := rig.distance()
	var h0 := rig.current_state().heading_deg
	_touch(0, c + Vector2(-60.0, 0.0), true)
	_touch(1, c + Vector2(60.0, 0.0), true)
	await _frames(1)
	_drag(1, c + Vector2(140.0, 0.0), Vector2(80.0, 0.0))  # ayrılma: zoom in
	await _frames(1)
	var d1 := rig.distance()
	_drag(1, c + Vector2(110.0, 100.0), Vector2(-30.0, 100.0))  # bükme (saat yönü): sahne saat yönünde, yön azalır
	await _frames(1)
	_touch(1, c + Vector2(110.0, 100.0), false)
	_touch(0, c + Vector2(-60.0, 0.0), false)
	await _frames(1)
	var turned := CameraState.angle_delta_deg(h0, rig.current_state().heading_deg)
	report["touch_pinch"] = {"d0": snappedf(d0, 0.1), "d1": snappedf(d1, 0.1), "heading_delta_deg": snappedf(turned, 0.01)}
	return pan_err < rig.distance() * 0.01 and d1 < d0 * 0.8 and turned < -5.0


func _touch(index: int, pos: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = index
	e.position = pos
	e.pressed = pressed
	Input.parse_input_event(e)


func _drag(index: int, pos: Vector2, rel: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = index
	e.position = pos
	e.relative = rel
	Input.parse_input_event(e)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _motion(pos: Vector2, rel: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = pos
	e.global_position = pos
	e.relative = rel
	Input.parse_input_event(e)


func _button(pos: Vector2, index: MouseButton, pressed: bool) -> void:
	var e := InputEventMouseButton.new()
	e.position = pos
	e.global_position = pos
	e.button_index = index
	e.pressed = pressed
	Input.parse_input_event(e)


func _wheel(pos: Vector2, index: MouseButton) -> void:
	_button(pos, index, true)
	_button(pos, index, false)
