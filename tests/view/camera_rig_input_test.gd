extends GdUnitTestSuite
## T-003 ölçüt 1, 5, 6 · CameraRig girdisi YALNIZ InputProfile üzerinden: masaüstü (sürükle pan, tekerlek zoom, orta tuş
## döndürme, klavye) ve dokunmatik (tek parmak pan, iki parmak kıstır/bük) AYNI fiillerle aynı rig'i sürer.
## Sentetik olaylar: gerçek fare/trackpad/dokunma denemesi DEĞİLDİR (elle denenir, rapora yazılır).

const CTS = preload("res://tests/view/camera_test_support.gd")
const VIEWPORT := Vector2(1600.0, 900.0)

var _world: WorldData


func before() -> void:
	_world = WorldTestSupport.coarse(WorldTestSupport.control())


func _rig(profile: InputProfile, spec: String = "district:D4") -> CameraRig:
	var rig: CameraRig = auto_free(CameraRig.new())
	rig.input_profile = profile
	rig.viewport_size_override = VIEWPORT
	rig.smoothing_enabled = false
	add_child(rig)
	rig.set_world(_world, func(x: float, z: float) -> float: return maxf(_world.height_at(x, z), _world.sea_level))
	rig.apply_preset(spec)
	return rig


func _button(index: MouseButton, pressed: bool, pos: Vector2) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = index
	e.pressed = pressed
	e.position = pos
	return e


func _motion(pos: Vector2, rel: Vector2) -> InputEventMouseMotion:
	var e := InputEventMouseMotion.new()
	e.position = pos
	e.relative = rel
	return e


func _key(code: Key, pressed: bool) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = pressed
	return e


func _touch(index: int, pressed: bool, pos: Vector2) -> InputEventScreenTouch:
	var e := InputEventScreenTouch.new()
	e.index = index
	e.pressed = pressed
	e.position = pos
	return e


func _drag(index: int, pos: Vector2, rel: Vector2) -> InputEventScreenDrag:
	var e := InputEventScreenDrag.new()
	e.index = index
	e.position = pos
	e.relative = rel
	return e


func _ground_under(rig: CameraRig, px: Vector2) -> Dictionary:
	return CameraMath.grab_point(rig.current_state(), px, VIEWPORT, rig.ground_height)


# --- Masaüstü ---

func test_desktop_left_drag_pans_so_the_grabbed_ground_follows_the_cursor() -> void:
	var rig := _rig(DesktopInputProfile.new())
	var start := Vector2(900.0, 500.0)
	var grabbed := _ground_under(rig, start)
	rig._unhandled_input(_button(MOUSE_BUTTON_LEFT, true, start))
	var pos := start
	for i in 6:
		var next := pos + Vector2(40.0, -25.0)
		rig._unhandled_input(_motion(next, next - pos))
		pos = next
	var now := _ground_under(rig, pos)
	assert_float(CTS.gap(grabbed, now)).is_less(15.0)  # 6 km'lik görünümde ~15 m: içerik imleçte
	assert_float(rig.focus_xz().distance_to(Vector2(rig.target_state().focus_x, rig.target_state().focus_z))).is_less(0.01)


func test_desktop_wheel_zooms_to_the_cursor_point() -> void:
	var rig := _rig(DesktopInputProfile.new())
	var px := Vector2(1300.0, 250.0)
	var before_ground := _ground_under(rig, px)
	var d0 := rig.distance()
	rig._unhandled_input(_button(MOUSE_BUTTON_WHEEL_UP, true, px))
	assert_float(rig.distance()).is_less(d0)
	assert_float(CTS.gap(before_ground, _ground_under(rig, px))).is_less(d0 * 0.001)
	rig._unhandled_input(_button(MOUSE_BUTTON_WHEEL_DOWN, true, px))
	rig._unhandled_input(_button(MOUSE_BUTTON_WHEEL_DOWN, true, px))
	assert_float(rig.distance()).is_greater(d0)


func test_desktop_magnify_gesture_zooms_in_and_out() -> void:
	var rig := _rig(DesktopInputProfile.new())
	var d0 := rig.distance()
	var pinch := InputEventMagnifyGesture.new()
	pinch.position = Vector2(700.0, 400.0)
	pinch.factor = 1.5
	rig._unhandled_input(pinch)
	assert_float(rig.distance()).is_equal_approx(d0 / 1.5, d0 * 0.02)


func test_desktop_middle_drag_rotates_clockwise_for_positive_motion() -> void:
	var rig := _rig(DesktopInputProfile.new())
	var h0 := rig.current_state().heading_deg
	rig._unhandled_input(_button(MOUSE_BUTTON_MIDDLE, true, Vector2(800.0, 450.0)))
	rig._unhandled_input(_motion(Vector2(900.0, 450.0), Vector2(100.0, 0.0)))
	var turned := CameraState.angle_delta_deg(h0, rig.current_state().heading_deg)
	assert_float(turned).is_equal_approx(-rad_to_deg(100.0 * 0.008), 0.01)  # sahne saat yönü = yön azalır


func test_held_keys_pan_rotate_and_zoom_through_the_profile_axes() -> void:
	var rig := _rig(DesktopInputProfile.new(), "metro")
	var s0 := rig.current_state()
	rig._unhandled_input(_key(KEY_W, true))
	rig._process(0.1)
	var s1 := rig.current_state()
	var fwd := CameraMath.forward(s0.heading_deg, 0.0)
	var moved := Vector2(s1.focus_x - s0.focus_x, s1.focus_z - s0.focus_z)
	assert_float(moved.length()).is_equal_approx(s0.distance * 0.55 * 0.1, 1.0)
	assert_float(moved.normalized().dot(Vector2(fwd.x, fwd.z))).is_greater(0.99)  # W = ileri
	rig._unhandled_input(_key(KEY_W, false))
	rig._unhandled_input(_key(KEY_E, true))
	rig._process(0.5)
	assert_float(CameraState.angle_delta_deg(s1.heading_deg, rig.current_state().heading_deg)).is_less(-20.0)
	rig._unhandled_input(_key(KEY_E, false))
	rig._unhandled_input(_key(KEY_PAGEUP, true))
	rig._process(0.5)
	assert_float(rig.distance()).is_less(s1.distance * 0.7)  # 2,5^0,5 = 1,58x
	rig._unhandled_input(_key(KEY_PAGEUP, false))
	var steady := rig.current_state()
	rig._process(0.5)  # tuşlar bırakıldı: hareket yok
	assert_bool(rig.current_state().is_close_to(steady, 0.001)).is_true()


func test_temporary_tilt_keys_clamp_the_pitch() -> void:
	var rig := _rig(DesktopInputProfile.new())
	rig._unhandled_input(_key(KEY_R, true))
	rig._process(10.0)
	assert_float(rig.current_state().pitch_deg).is_equal(CameraMath.MAX_PITCH_DEG)
	rig._unhandled_input(_key(KEY_R, false))
	rig._unhandled_input(_key(KEY_F, true))
	rig._process(10.0)
	assert_float(rig.current_state().pitch_deg).is_equal(CameraMath.MIN_PITCH_DEG)


func test_rig_does_not_consume_input_before_the_ui() -> void:
	var rig := _rig(DesktopInputProfile.new())
	# UI dünyadan önce (ADR-0004): girdi yalnız _unhandled_input'ta; _input / _gui_input yok.
	assert_bool(rig.has_method("_input")).is_false()
	assert_bool(rig.has_method("_unhandled_input")).is_true()


# --- Dokunmatik (aynı rig, aynı fiiller) ---

func test_touch_one_finger_drag_pans_the_same_way_as_the_mouse() -> void:
	var rig := _rig(TouchInputProfile.new())
	var start := Vector2(900.0, 500.0)
	var grabbed := _ground_under(rig, start)
	rig._unhandled_input(_touch(0, true, start))
	var pos := start
	for i in 6:
		var next := pos + Vector2(40.0, -25.0)
		rig._unhandled_input(_drag(0, next, next - pos))
		pos = next
	assert_float(CTS.gap(grabbed, _ground_under(rig, pos))).is_less(15.0)


func test_touch_two_finger_pinch_zooms_and_twist_rotates() -> void:
	var rig := _rig(TouchInputProfile.new())
	var d0 := rig.distance()
	var h0 := rig.current_state().heading_deg
	rig._unhandled_input(_touch(0, true, Vector2(700.0, 450.0)))
	rig._unhandled_input(_touch(1, true, Vector2(900.0, 450.0)))
	rig._unhandled_input(_drag(1, Vector2(1100.0, 450.0), Vector2(200.0, 0.0)))  # ayrılma: yakınlaş
	assert_float(rig.distance()).is_less(d0 * 0.8)
	# Bükme: 2. parmak ilk parmak etrafında saat yönünde döner (ekranda aşağı) -> sahne saat yönünde -> yön azalır.
	rig._unhandled_input(_drag(1, Vector2(1000.0, 650.0), Vector2(-100.0, 200.0)))
	assert_float(CameraState.angle_delta_deg(h0, rig.current_state().heading_deg)).is_less(-5.0)


func test_each_profile_ignores_the_other_devices_events() -> void:
	var desktop := _rig(DesktopInputProfile.new())
	var d0 := desktop.current_state()
	desktop._unhandled_input(_touch(0, true, Vector2(900.0, 500.0)))
	desktop._unhandled_input(_drag(0, Vector2(1000.0, 500.0), Vector2(100.0, 0.0)))
	assert_bool(desktop.current_state().is_close_to(d0, 0.001)).is_true()
	var touch := _rig(TouchInputProfile.new())
	var t0 := touch.current_state()
	touch._unhandled_input(_button(MOUSE_BUTTON_WHEEL_UP, true, Vector2(800.0, 450.0)))
	touch._unhandled_input(_button(MOUSE_BUTTON_LEFT, true, Vector2(800.0, 450.0)))
	touch._unhandled_input(_motion(Vector2(900.0, 450.0), Vector2(100.0, 0.0)))
	assert_bool(touch.current_state().is_close_to(t0, 0.001)).is_true()


func test_focus_loss_resets_held_keys_so_the_camera_does_not_run_away() -> void:
	var rig := _rig(DesktopInputProfile.new(), "metro")
	rig._unhandled_input(_key(KEY_D, true))
	rig._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	var s0 := rig.current_state()
	rig._process(0.5)
	assert_bool(rig.current_state().is_close_to(s0, 0.001)).is_true()
