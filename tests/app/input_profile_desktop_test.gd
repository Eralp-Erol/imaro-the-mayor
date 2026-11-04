extends GdUnitTestSuite
## T-007 · DesktopInputProfile: fare/klavye/trackpad olayları -> ortak oyuncu fiilleri. Sentetik olaylar, sahne yok.
## Gerçek trackpad işaret/ölçekleri DOĞRULANMADI (cihaz); burada sözleşme ve çift tetik/yok sayma kuralları sınanır.

class Recorder:
	extends RefCounted
	var events: Array = []

	func attach(p: InputProfile) -> void:
		p.select_requested.connect(func(pos: Vector2) -> void: events.append(["select", pos]))
		p.context_requested.connect(func(pos: Vector2) -> void: events.append(["context", pos]))
		p.pan_requested.connect(func(d: Vector2) -> void: events.append(["pan", d]))
		p.zoom_requested.connect(func(f: float, a: Vector2) -> void: events.append(["zoom", f, a]))
		p.rotate_requested.connect(func(r: float, a: Vector2) -> void: events.append(["rotate", r, a]))
		p.pause_toggle_requested.connect(func() -> void: events.append(["pause"]))
		p.speed_step_requested.connect(func(d: int) -> void: events.append(["speed", d]))
		p.cancel_requested.connect(func() -> void: events.append(["cancel"]))

	func kinds() -> Array:
		return events.map(func(e: Array) -> String: return e[0])


var _p: DesktopInputProfile
var _r: Recorder


func before_test() -> void:
	_p = DesktopInputProfile.new()
	_r = Recorder.new()
	_r.attach(_p)


func _button(index: MouseButton, pressed: bool, pos: Vector2, ctrl := false) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = index
	e.pressed = pressed
	e.position = pos
	e.ctrl_pressed = ctrl
	return e


func _motion(pos: Vector2, rel := Vector2.ZERO) -> InputEventMouseMotion:
	var e := InputEventMouseMotion.new()
	e.position = pos
	e.relative = rel
	return e


func _key(code: Key, pressed := true, echo := false, meta := false) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = pressed
	e.echo = echo
	e.meta_pressed = meta
	return e


func test_click_without_movement_selects_at_release_position() -> void:
	assert_bool(_p.handle_event(_button(MOUSE_BUTTON_LEFT, true, Vector2(100, 100)))).is_true()
	assert_bool(_p.handle_event(_button(MOUSE_BUTTON_LEFT, false, Vector2(101, 100)))).is_true()
	assert_array(_r.events).is_equal([["select", Vector2(101, 100)]])


func test_drag_beyond_slop_pans_and_never_selects() -> void:
	_p.handle_event(_button(MOUSE_BUTTON_LEFT, true, Vector2(100, 100)))
	_p.handle_event(_motion(Vector2(104, 100)))  # eşik içinde: olay yok
	assert_array(_r.events).is_empty()
	_p.handle_event(_motion(Vector2(120, 100)))  # eşik aşıldı: birikmiş 20 px bir kerede
	_p.handle_event(_motion(Vector2(130, 110)))
	_p.handle_event(_button(MOUSE_BUTTON_LEFT, false, Vector2(130, 110)))
	assert_array(_r.events).is_equal([["pan", Vector2(20, 0)], ["pan", Vector2(10, 10)]])
	assert_array(_r.kinds()).not_contains(["select"])


func test_right_click_and_ctrl_click_request_context() -> void:
	_p.handle_event(_button(MOUSE_BUTTON_RIGHT, true, Vector2(5, 6)))
	_p.handle_event(_button(MOUSE_BUTTON_RIGHT, false, Vector2(5, 6)))
	_p.handle_event(_button(MOUSE_BUTTON_LEFT, true, Vector2(7, 8), true))
	_p.handle_event(_button(MOUSE_BUTTON_LEFT, false, Vector2(7, 8), true))
	assert_array(_r.events).is_equal([["context", Vector2(5, 6)], ["context", Vector2(7, 8)]])


func test_wheel_zooms_around_cursor_and_directions_are_inverse() -> void:
	_p.handle_event(_button(MOUSE_BUTTON_WHEEL_UP, true, Vector2(300, 200)))
	_p.handle_event(_button(MOUSE_BUTTON_WHEEL_DOWN, true, Vector2(300, 200)))
	assert_float(_r.events[0][1]).is_greater(1.0)
	assert_float(_r.events[1][1]).is_less(1.0)
	assert_float(_r.events[0][1] * _r.events[1][1]).is_equal_approx(1.0, 0.0001)
	assert_vector(_r.events[0][2]).is_equal(Vector2(300, 200))
	# Bırakma olayı (pressed=false) ikinci kez zoom üretmez.
	_p.handle_event(_button(MOUSE_BUTTON_WHEEL_UP, false, Vector2(300, 200)))
	assert_int(_r.events.size()).is_equal(2)


func test_middle_drag_rotates_clockwise_for_rightward_motion() -> void:
	_p.handle_event(_button(MOUSE_BUTTON_MIDDLE, true, Vector2(50, 50)))
	_p.handle_event(_motion(Vector2(70, 50), Vector2(20, 0)))
	_p.handle_event(_button(MOUSE_BUTTON_MIDDLE, false, Vector2(70, 50)))
	_p.handle_event(_motion(Vector2(90, 50), Vector2(20, 0)))  # bırakıldıktan sonra hareket: olay yok
	assert_int(_r.events.size()).is_equal(1)
	assert_float(_r.events[0][1]).is_greater(0.0)


func test_trackpad_magnify_and_two_finger_scroll() -> void:
	var m := InputEventMagnifyGesture.new()
	m.factor = 1.25
	m.position = Vector2(10, 20)
	var g := InputEventPanGesture.new()
	g.delta = Vector2(0, 1)
	assert_bool(_p.handle_event(m)).is_true()
	assert_bool(_p.handle_event(g)).is_true()
	assert_array(_r.events[0]).is_equal(["zoom", 1.25, Vector2(10, 20)])
	assert_float(_r.events[1][1].y).is_less(0.0)  # varsayılan: içerik kaydırma deltasının tersine
	_p.invert_trackpad_pan = true
	_p.handle_event(g)
	assert_float(_r.events[2][1].y).is_greater(0.0)


func test_keyboard_axes_follow_held_state_and_release() -> void:
	_p.handle_event(_key(KEY_W))
	_p.handle_event(_key(KEY_D))
	assert_vector(_p.held_pan_axis()).is_equal(Vector2(1, -1).normalized())
	_p.handle_event(_key(KEY_W, false))
	assert_vector(_p.held_pan_axis()).is_equal(Vector2(1, 0))
	_p.handle_event(_key(KEY_LEFT))
	assert_vector(_p.held_pan_axis()).is_equal(Vector2.ZERO)  # sağ + sol birbirini götürür
	_p.handle_event(_key(KEY_E))
	_p.handle_event(_key(KEY_PAGEUP))
	assert_float(_p.held_rotate_axis()).is_equal(1.0)
	assert_float(_p.held_zoom_axis()).is_equal(1.0)
	_p.handle_event(_key(KEY_Q))
	assert_float(_p.held_rotate_axis()).is_equal(0.0)


func test_one_shot_keys() -> void:
	_p.handle_event(_key(KEY_SPACE))
	_p.handle_event(_key(KEY_ESCAPE))
	_p.handle_event(_key(KEY_EQUAL))
	_p.handle_event(_key(KEY_MINUS))
	_p.handle_event(_key(KEY_KP_ADD))
	assert_array(_r.events).is_equal([["pause"], ["cancel"], ["speed", 1], ["speed", -1], ["speed", 1]])


func test_key_echo_and_command_modifier_do_not_fire_or_hold() -> void:
	_p.handle_event(_key(KEY_SPACE, true, true))  # otomatik tekrar: duraklatmayı tekrarlamaz
	assert_array(_r.events).is_empty()
	assert_bool(_p.handle_event(_key(KEY_S, true, false, true))).is_false()  # Cmd+S uygulama kısayolu
	assert_vector(_p.held_pan_axis()).is_equal(Vector2.ZERO)
	assert_bool(_p.handle_event(_key(KEY_SPACE, true, false, true))).is_false()
	assert_array(_r.events).is_empty()


func test_reset_clears_held_keys_and_cancels_drag_so_focus_loss_cannot_stick() -> void:
	_p.handle_event(_key(KEY_A))
	_p.handle_event(_button(MOUSE_BUTTON_LEFT, true, Vector2(10, 10)))
	_p.handle_event(_motion(Vector2(40, 10)))
	_p.reset()
	assert_vector(_p.held_pan_axis()).is_equal(Vector2.ZERO)
	_r.events.clear()
	_p.handle_event(_motion(Vector2(80, 10)))  # sürükleme artık yok
	_p.handle_event(_button(MOUSE_BUTTON_LEFT, false, Vector2(80, 10)))  # basışsız bırakma: select yok
	assert_array(_r.events).is_empty()


func test_release_or_motion_without_tracked_press_is_ignored_for_ui_consumed_presses() -> void:
	# UI basışı tükettiyse `_unhandled_input` yalnız sonraki olayları görür; bunlar fiil üretmemeli.
	assert_bool(_p.handle_event(_button(MOUSE_BUTTON_LEFT, false, Vector2(10, 10)))).is_false()
	assert_bool(_p.handle_event(_motion(Vector2(50, 50), Vector2(40, 40)))).is_false()
	assert_array(_r.events).is_empty()


func test_touch_events_are_ignored_by_the_desktop_profile() -> void:
	var t := InputEventScreenTouch.new()
	t.pressed = true
	t.position = Vector2(10, 10)
	var d := InputEventScreenDrag.new()
	d.position = Vector2(50, 50)
	d.relative = Vector2(40, 40)
	assert_bool(_p.handle_event(t)).is_false()
	assert_bool(_p.handle_event(d)).is_false()
	assert_array(_r.events).is_empty()


func test_factory_creates_known_profiles_and_rejects_unknown() -> void:
	assert_object(InputProfile.create(&"desktop")).is_instanceof(DesktopInputProfile)
	assert_object(InputProfile.create(&"touch")).is_instanceof(TouchInputProfile)
	assert_object(InputProfile.create(&"gamepad")).is_null()
	assert_object(InputProfile.create(&"")).is_null()
