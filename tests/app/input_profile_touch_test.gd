extends GdUnitTestSuite
## T-007 · TouchInputProfile: dokunma olayları -> ortak oyuncu fiilleri (tek parmak pan/seç/uzun bas, iki parmak
## zoom/döndür). Sentetik olaylar. Gerçek iPad parmak davranışı DOĞRULANMADI (T-008 cihaz testi).

class Recorder:
	extends RefCounted
	var events: Array = []

	func attach(p: InputProfile) -> void:
		p.select_requested.connect(func(pos: Vector2) -> void: events.append(["select", pos]))
		p.context_requested.connect(func(pos: Vector2) -> void: events.append(["context", pos]))
		p.pan_requested.connect(func(d: Vector2) -> void: events.append(["pan", d]))
		p.zoom_requested.connect(func(f: float, a: Vector2) -> void: events.append(["zoom", f, a]))
		p.rotate_requested.connect(func(r: float, a: Vector2) -> void: events.append(["rotate", r, a]))

	func count(kind: String) -> int:
		return events.filter(func(e: Array) -> bool: return e[0] == kind).size()


var _p: TouchInputProfile
var _r: Recorder


func before_test() -> void:
	_p = TouchInputProfile.new()
	_r = Recorder.new()
	_r.attach(_p)


func _touch(index: int, pressed: bool, pos: Vector2, canceled := false) -> InputEventScreenTouch:
	var e := InputEventScreenTouch.new()
	e.index = index
	e.pressed = pressed
	e.position = pos
	e.canceled = canceled
	return e


func _drag(index: int, pos: Vector2) -> InputEventScreenDrag:
	var e := InputEventScreenDrag.new()
	e.index = index
	e.position = pos
	return e


func test_tap_selects_on_release() -> void:
	_p.handle_event(_touch(0, true, Vector2(100, 100)))
	_p.handle_event(_drag(0, Vector2(103, 101)))  # eşik içi titreme
	_p.handle_event(_touch(0, false, Vector2(103, 101)))
	assert_array(_r.events).is_equal([["select", Vector2(103, 101)]])


func test_single_finger_drag_pans_content_with_finger_and_does_not_select() -> void:
	_p.handle_event(_touch(0, true, Vector2(100, 100)))
	_p.handle_event(_drag(0, Vector2(130, 100)))  # eşik aşıldı: 30 px birikmiş
	_p.handle_event(_drag(0, Vector2(140, 110)))
	_p.handle_event(_touch(0, false, Vector2(140, 110)))
	assert_array(_r.events).is_equal([["pan", Vector2(30, 0)], ["pan", Vector2(10, 10)]])
	assert_int(_r.count("select")).is_equal(0)


func test_long_press_requests_context_once_via_process_time_and_does_not_select() -> void:
	_p.handle_event(_touch(0, true, Vector2(200, 50)))
	_p.process(0.3)
	assert_array(_r.events).is_empty()
	_p.process(0.3)  # toplam 0.6 sn >= 0.5
	_p.process(1.0)  # ikinci kez tetiklenmez
	_p.handle_event(_drag(0, Vector2(260, 50)))  # uzun basma sonrası sürükleme pan olmaz
	_p.handle_event(_touch(0, false, Vector2(260, 50)))
	assert_array(_r.events).is_equal([["context", Vector2(200, 50)]])


func test_moving_finger_cancels_long_press() -> void:
	_p.handle_event(_touch(0, true, Vector2(200, 50)))
	_p.process(0.3)
	_p.handle_event(_drag(0, Vector2(240, 50)))
	_p.process(1.0)
	_p.handle_event(_touch(0, false, Vector2(240, 50)))
	assert_int(_r.count("context")).is_equal(0)
	assert_int(_r.count("pan")).is_equal(1)


func test_pinch_zooms_around_midpoint_without_rotating() -> void:
	_p.handle_event(_touch(0, true, Vector2(100, 200)))
	_p.handle_event(_touch(1, true, Vector2(200, 200)))
	_p.handle_event(_drag(1, Vector2(300, 200)))  # mesafe 100 -> 200
	assert_int(_r.count("zoom")).is_equal(1)
	var z: Array = _r.events.filter(func(e: Array) -> bool: return e[0] == "zoom")[0]
	assert_float(z[1]).is_equal_approx(2.0, 0.0001)
	assert_vector(z[2]).is_equal(Vector2(200, 200))  # orta nokta
	assert_int(_r.count("rotate")).is_equal(0)


func test_twist_rotates_clockwise_only_after_threshold() -> void:
	_p.handle_event(_touch(0, true, Vector2(100, 200)))
	_p.handle_event(_touch(1, true, Vector2(200, 200)))
	# 2 derece: eşik altı (6 derece) -> dönüş yok
	var small := Vector2(100, 0).rotated(deg_to_rad(2.0))
	_p.handle_event(_drag(1, Vector2(100, 200) + small))
	assert_int(_r.count("rotate")).is_equal(0)
	# toplam 30 derece, saat yönü (ekranda y aşağı: pozitif açı saat yönü)
	var big := Vector2(100, 0).rotated(deg_to_rad(30.0))
	_p.handle_event(_drag(1, Vector2(100, 200) + big))
	var total := 0.0
	for e: Array in _r.events:
		if e[0] == "rotate":
			total += e[1]
	assert_float(total).is_greater(0.0)
	assert_float(total).is_equal_approx(deg_to_rad(30.0) - _p.rotate_threshold_rad, 0.001)


func test_two_finger_translation_pans_by_midpoint_shift() -> void:
	_p.handle_event(_touch(0, true, Vector2(100, 100)))
	_p.handle_event(_touch(1, true, Vector2(200, 100)))
	_p.handle_event(_drag(0, Vector2(120, 100)))  # yalnız bir parmak 20 px: orta nokta 10 px
	var pans: Array = _r.events.filter(func(e: Array) -> bool: return e[0] == "pan")
	assert_int(pans.size()).is_equal(1)
	assert_vector(pans[0][1]).is_equal(Vector2(10, 0))


func test_second_finger_blocks_select_and_later_single_finger_pan_until_all_up() -> void:
	_p.handle_event(_touch(0, true, Vector2(100, 100)))
	_p.handle_event(_touch(1, true, Vector2(200, 100)))
	_p.handle_event(_touch(1, false, Vector2(200, 100)))  # ikinci parmak kalktı
	_r.events.clear()
	_p.handle_event(_drag(0, Vector2(400, 400)))  # kalan parmağın büyük hareketi zıplama yaratmamalı
	_p.handle_event(_touch(0, false, Vector2(400, 400)))
	assert_array(_r.events).is_empty()  # ne pan ne select
	# Yeni jest normal çalışır.
	_p.handle_event(_touch(0, true, Vector2(10, 10)))
	_p.handle_event(_touch(0, false, Vector2(10, 10)))
	assert_array(_r.events).is_equal([["select", Vector2(10, 10)]])


func test_canceled_touch_aborts_gesture_without_select() -> void:
	_p.handle_event(_touch(0, true, Vector2(50, 50)))
	_p.handle_event(_touch(0, false, Vector2(50, 50), true))
	assert_array(_r.events).is_empty()
	assert_int(_p.mode()).is_equal(TouchInputProfile.Mode.IDLE)


func test_untracked_release_and_drag_are_ignored_for_ui_consumed_touches() -> void:
	assert_bool(_p.handle_event(_touch(3, false, Vector2(1, 1)))).is_false()
	assert_bool(_p.handle_event(_drag(3, Vector2(100, 100)))).is_false()
	assert_array(_r.events).is_empty()


func test_mouse_and_trackpad_events_are_ignored_to_avoid_double_firing_with_emulated_mouse() -> void:
	var b := InputEventMouseButton.new()
	b.button_index = MOUSE_BUTTON_LEFT
	b.pressed = true
	b.position = Vector2(10, 10)
	var m := InputEventMouseMotion.new()
	m.position = Vector2(60, 60)
	m.relative = Vector2(50, 50)
	var g := InputEventMagnifyGesture.new()
	g.factor = 2.0
	assert_bool(_p.handle_event(b)).is_false()
	assert_bool(_p.handle_event(m)).is_false()
	assert_bool(_p.handle_event(g)).is_false()
	assert_array(_r.events).is_empty()


func test_reset_on_focus_loss_clears_fingers_and_long_press_timer() -> void:
	_p.handle_event(_touch(0, true, Vector2(100, 100)))
	_p.handle_event(_touch(1, true, Vector2(200, 100)))
	_p.reset()
	_p.process(5.0)
	_p.handle_event(_drag(0, Vector2(500, 500)))
	_p.handle_event(_touch(1, false, Vector2(200, 100)))
	assert_array(_r.events).is_empty()
	assert_int(_p.mode()).is_equal(TouchInputProfile.Mode.IDLE)


func test_keyboard_shortcuts_work_on_touch_profile_for_external_keyboards() -> void:
	var fired: Array[String] = []
	_p.pause_toggle_requested.connect(func() -> void: fired.append("pause"))
	var k := InputEventKey.new()
	k.physical_keycode = KEY_SPACE
	k.keycode = KEY_SPACE
	k.pressed = true
	assert_bool(_p.handle_event(k)).is_true()
	assert_array(fired).is_equal(["pause"])
