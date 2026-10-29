extends GdUnitTestSuite
## T-064 sahip düzeltmesi · İSTENEN eğim ile FİİLİ eğim ayrıdır (ADR-0007 Ek 2026-10-29) ve eğim kalıcı bir girdiyle
## kontrol edilir (`camera_tilt`: R/F, Option+sürükle, orta tuş, Option+iki parmak kaydırma, üç parmak dikey).
## Sentetik olaylar: gerçek trackpad/iPad hissi DOĞRULANMADI (elle denenir, rapora yazılır).

const VIEWPORT := Vector2(1600.0, 900.0)
const CENTER := Vector2(800.0, 450.0)

var _world: WorldData


func before() -> void:
	_world = WorldTestSupport.coarse(WorldTestSupport.control())


func _rig(profile: InputProfile, spec: String = "district:D1", smoothing: bool = false) -> CameraRig:
	var rig: CameraRig = auto_free(CameraRig.new())
	rig.input_profile = profile
	rig.viewport_size_override = VIEWPORT
	rig.smoothing_enabled = smoothing
	add_child(rig)
	rig.set_world(_world, func(x: float, z: float) -> float: return maxf(_world.height_at(x, z), _world.sea_level))
	rig.apply_preset(spec)
	return rig


## Doğu kenarına yakın, alçak tercihli (30 derece) görünüm (yön 0): uzaklaşınca K1 eğimi zorlar.
func _edge_rig(smoothing: bool = false) -> CameraRig:
	var rig := _rig(DesktopInputProfile.new(), "core", smoothing)
	var inner := rig.envelope.inner_rect(_world.bounds())
	var s := rig.target_state()
	s.focus_x = inner.end.x - 3000.0
	s.focus_z = inner.get_center().y
	s.heading_deg = 0.0
	s.pitch_deg = 30.0
	s.distance = 2500.0
	rig.apply_state(s, true)
	return rig


func _zoom_steps(rig: CameraRig, factor: float, steps: int) -> void:
	for i in steps:
		rig.on_zoom(factor, CENTER)


func _k1_ok(rig: CameraRig, s: CameraState) -> bool:
	return rig.envelope.footprint_ok(s, VIEWPORT.x / VIEWPORT.y, rig.ground_height, _world.bounds(), _world.sea_level)


func _frames(rig: CameraRig, count: int) -> void:
	for i in count:
		rig._process(1.0 / 60.0)


func _button(index: MouseButton, pressed: bool, pos: Vector2, alt: bool = false) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = index
	e.pressed = pressed
	e.position = pos
	e.alt_pressed = alt
	return e


func _motion(pos: Vector2, rel: Vector2, alt: bool = false) -> InputEventMouseMotion:
	var e := InputEventMouseMotion.new()
	e.position = pos
	e.relative = rel
	e.alt_pressed = alt
	return e


func _key(code: Key, pressed: bool) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = pressed
	return e


func _pan_gesture(delta: Vector2, alt: bool) -> InputEventPanGesture:
	var e := InputEventPanGesture.new()
	e.position = CENTER
	e.delta = delta
	e.alt_pressed = alt
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


# --- (1) K1 yükseltir, zoom-in tercihe geri indirir ---

func test_zoom_out_to_the_limit_raises_the_pitch_and_zooming_back_in_returns_to_the_preferred_pitch() -> void:
	var rig := _edge_rig()
	var preferred := rig.desired_pitch_deg()
	assert_float(preferred).is_equal(30.0)
	_zoom_steps(rig, 0.9, 40)
	var far := rig.target_state()
	assert_float(far.pitch_deg).override_failure_message("K1 uç noktada eğimi yükseltmedi (test duyarsız)") \
			.is_greater(preferred + 30.0)
	assert_bool(_k1_ok(rig, far)).is_true()
	assert_float(rig.desired_pitch_deg()).is_equal(preferred)  # K1 tercihi DEĞİŞTİRMEZ
	_zoom_steps(rig, 1.1, 60)
	var near := rig.target_state()
	assert_float(near.distance).is_equal_approx(rig.envelope.d_min_m, 0.01)
	assert_float(near.pitch_deg).is_equal_approx(preferred, 0.01)  # eski açıya dönülür
	assert_float(rig.desired_pitch_deg()).is_equal(preferred)


func test_zoom_in_lowers_the_pitch_monotonically_and_smoothed_poses_stay_k1_without_jumps() -> void:
	var rig := _edge_rig(true)
	_zoom_steps(rig, 0.9, 40)
	rig.snap_to_target()
	var preferred := rig.desired_pitch_deg()
	var prev := rig.current_state().pitch_deg
	assert_float(prev).is_greater(preferred + 30.0)
	var biggest_step := 0.0
	for i in 40:
		rig.on_zoom(1.1, CENTER)
		for f in 4:
			rig._process(1.0 / 60.0)
			var s := rig.current_state()
			assert_bool(_k1_ok(rig, s)).override_failure_message("ara poz K1 dışı (%d/%d)" % [i, f]).is_true()
			assert_float(s.pitch_deg - prev).override_failure_message("zoom-in eğimi YÜKSELTTİ").is_less(0.5)
			biggest_step = maxf(biggest_step, prev - s.pitch_deg)
			prev = s.pitch_deg
	assert_float(biggest_step).override_failure_message("eğim geri dönüşünde sıçrama").is_less(8.0)
	_frames(rig, 120)
	assert_float(rig.current_state().pitch_deg).is_equal_approx(preferred, 0.05)


# --- (2) tercih yalnız oyuncu eğiminden değişir ---

func test_user_tilt_updates_the_preference_and_zoom_pan_rotate_do_not_change_it() -> void:
	var rig := _rig(DesktopInputProfile.new())
	var p0 := rig.desired_pitch_deg()
	rig.tilt(10.0)
	assert_float(rig.desired_pitch_deg()).is_equal_approx(p0 + 10.0, 0.001)
	assert_float(rig.target_state().pitch_deg).is_equal_approx(p0 + 10.0, 0.001)
	var preferred := rig.desired_pitch_deg()
	_zoom_steps(rig, 1.1, 5)
	_zoom_steps(rig, 0.9, 5)
	rig.on_pan(Vector2(80.0, -40.0))
	rig.on_rotate(0.4, CENTER)
	assert_float(rig.desired_pitch_deg()).is_equal(preferred)
	assert_float(rig.target_state().pitch_deg).is_equal_approx(preferred, 0.001)  # K1 gerektirmedi: eğim aynı


func test_tilting_while_k1_forces_the_pitch_steeper_starts_from_the_visible_pitch_flatter_keeps_the_view() -> void:
	var rig := _edge_rig()
	_zoom_steps(rig, 0.9, 4)
	var forced := rig.target_state().pitch_deg
	assert_float(forced).override_failure_message("K1 zorlamadı (test duyarsız)").is_greater(35.0)
	assert_float(forced).is_less(80.0)
	rig.tilt(-3.0)  # K1 zaten alt sınırda: görünen eğim DEĞİŞMEZ, K1 bozulmaz, tercih düşer
	assert_float(rig.target_state().pitch_deg).is_equal_approx(forced, 0.05)
	assert_bool(_k1_ok(rig, rig.target_state())).is_true()
	assert_float(rig.desired_pitch_deg()).is_equal_approx(27.0, 0.001)
	rig.tilt(3.0)  # dikleştirme GÖRÜNEN eğimden başlar: anında karşılık
	assert_float(rig.target_state().pitch_deg).is_equal_approx(forced + 3.0, 0.05)
	assert_float(rig.desired_pitch_deg()).is_equal_approx(forced + 3.0, 0.05)


# --- (3) K1 dünya kenarı garantisi ---

func test_k1_world_edge_guarantee_holds_with_a_flat_preference_from_every_edge_and_heading() -> void:
	var rig := _rig(DesktopInputProfile.new(), "core")
	var inner := rig.envelope.inner_rect(_world.bounds())
	var focuses: Array[Vector2] = [
		Vector2(inner.position.x, inner.get_center().y), Vector2(inner.end.x, inner.get_center().y),
		Vector2(inner.get_center().x, inner.position.y), Vector2(inner.get_center().x, inner.end.y),
		inner.position, inner.end,
	]
	for focus in focuses:
		for heading in [0.0, 90.0, 180.0, 270.0]:
			var s := rig.target_state()
			s.focus_x = focus.x
			s.focus_z = focus.y
			s.heading_deg = heading
			s.pitch_deg = 0.0  # en alçak tercih
			s.distance = rig.envelope.d_max_m
			rig.apply_state(s, true)
			rig.tilt(-90.0)  # tercih zarf tabanına iner
			for step in 4:
				_zoom_steps(rig, 0.8, 6)
				var t := rig.target_state()
				assert_bool(_k1_ok(rig, t)).override_failure_message("zoom-out %s %s" % [focus, heading]).is_true()
				for p in rig.envelope.footprint_points(t, VIEWPORT.x / VIEWPORT.y, rig.ground_height, _world.sea_level):
					assert_bool(inner.has_point(p)).override_failure_message("kenar kadraja girdi %s" % p).is_true()
			_zoom_steps(rig, 1.25, 30)
			assert_bool(_k1_ok(rig, rig.target_state())).is_true()
			rig.on_rotate(1.3, CENTER)
			rig.on_pan(Vector2(300.0, 200.0))
			assert_bool(_k1_ok(rig, rig.target_state())).is_true()


# --- (4) tavan ve eğim sınırları ---

func test_tilt_never_exceeds_the_envelope_pitch_range_or_the_distance_ceiling() -> void:
	var rig := _rig(DesktopInputProfile.new(), "street:port")
	rig.tilt(10000.0)
	assert_float(rig.desired_pitch_deg()).is_equal(rig.envelope.pitch_max_deg)
	assert_float(rig.target_state().pitch_deg).is_equal(rig.envelope.pitch_max_deg)
	rig.tilt(-10000.0)
	var floor_deg := rig.envelope.pitch_min_deg(rig.target_state().distance)
	assert_float(rig.desired_pitch_deg()).is_equal(rig.envelope.pitch_min_deg(rig.envelope.d_min_m))  # tercih tabanı
	assert_float(rig.target_state().pitch_deg).is_equal(floor_deg)  # fiili: bu uzaklığın tabanı
	rig.tilt(NAN)
	rig.tilt(INF)
	assert_float(rig.target_state().pitch_deg).is_equal(floor_deg)
	_zoom_steps(rig, 0.5, 60)  # tavan: d_max aşılmaz, eğim daima [pitch_min(d), pitch_max]
	var s := rig.target_state()
	assert_float(s.distance).is_less_equal(rig.envelope.d_max_m)
	assert_float(s.pitch_deg).is_greater_equal(rig.envelope.pitch_min_deg(s.distance))
	assert_float(s.pitch_deg).is_less_equal(rig.envelope.pitch_max_deg)
	assert_bool(_k1_ok(rig, s)).is_true()


# --- (5) Home ---

func test_home_resets_the_preference_to_the_starting_pitch() -> void:
	var rig := _rig(DesktopInputProfile.new(), "district:D1")
	rig.home_district = &"D1"
	assert_bool(rig.go_home()).is_true()
	var start := rig.desired_pitch_deg()
	var start_visible := rig.target_state().pitch_deg
	rig.tilt(35.0)
	_zoom_steps(rig, 0.9, 20)
	assert_float(rig.desired_pitch_deg()).is_not_equal(start)
	rig.go_home()
	assert_float(rig.desired_pitch_deg()).is_equal(start)
	assert_float(rig.target_state().pitch_deg).is_equal_approx(start_visible, 0.001)


func test_home_to_a_k1_forced_start_keeps_the_raw_pitch_as_preference_so_zoom_in_comes_back_down() -> void:
	var rig := _rig(DesktopInputProfile.new(), "core")
	rig.go_home()  # home_district boş: core, d_max
	var raw := rig.desired_pitch_deg()
	assert_float(raw).is_equal_approx(rig.envelope.pitch_min_deg(rig.envelope.d_max_m), 0.001)
	assert_float(rig.target_state().pitch_deg).is_greater(raw + 1.0)  # K1 çözülmüş
	_zoom_steps(rig, 1.1, 80)
	assert_float(rig.target_state().pitch_deg).is_equal_approx(raw, 0.01)


# --- (6) giriş eşlemeleri ---

func test_option_drag_tilts_and_rotates_without_panning_or_zooming() -> void:
	var rig := _rig(DesktopInputProfile.new())
	var s0 := rig.target_state()
	rig._unhandled_input(_button(MOUSE_BUTTON_LEFT, true, CENTER, true))
	rig._unhandled_input(_motion(CENTER + Vector2(0.0, 40.0), Vector2(0.0, 40.0), true))
	var down := rig.target_state()
	assert_float(down.pitch_deg - s0.pitch_deg).is_equal_approx(40.0 * InputProfile.TILT_DEG_PER_PX, 0.001)  # aşağı = dik
	assert_float(down.heading_deg).is_equal(s0.heading_deg)  # dikey hareket döndürmez
	assert_float(Vector2(down.focus_x - s0.focus_x, down.focus_z - s0.focus_z).length()).is_less(0.01)  # pan yok
	assert_float(down.distance).is_equal(s0.distance)  # zoom yok
	rig._unhandled_input(_motion(CENTER + Vector2(0.0, 10.0), Vector2(0.0, -30.0), true))
	assert_float(rig.target_state().pitch_deg).is_less(down.pitch_deg)
	var level := rig.target_state()
	rig._unhandled_input(_motion(CENTER + Vector2(100.0, -20.0), Vector2(100.0, 0.0), true))
	assert_float(absf(CameraState.angle_delta_deg(level.heading_deg, rig.target_state().heading_deg))).is_greater(1.0)
	assert_float(rig.target_state().pitch_deg).is_equal(level.pitch_deg)  # yatay hareket eğmez
	assert_float(rig.target_state().distance).is_equal(s0.distance)
	rig._unhandled_input(_button(MOUSE_BUTTON_LEFT, false, CENTER, false))
	assert_float(rig.desired_pitch_deg()).is_equal_approx(rig.target_state().pitch_deg, 0.001)


func test_plain_left_drag_still_pans_and_does_not_tilt() -> void:
	var rig := _rig(DesktopInputProfile.new())
	var p0 := rig.desired_pitch_deg()
	var s0 := rig.target_state()
	rig._unhandled_input(_button(MOUSE_BUTTON_LEFT, true, CENTER))
	rig._unhandled_input(_motion(CENTER + Vector2(60.0, 60.0), Vector2(60.0, 60.0)))
	rig._unhandled_input(_motion(CENTER + Vector2(80.0, 120.0), Vector2(20.0, 60.0)))
	assert_float(rig.desired_pitch_deg()).is_equal(p0)
	assert_float(Vector2(rig.target_state().focus_x - s0.focus_x, rig.target_state().focus_z - s0.focus_z).length()) \
			.is_greater(1.0)


func test_middle_drag_vertical_tilts_and_horizontal_rotates() -> void:
	var rig := _rig(DesktopInputProfile.new())
	var s0 := rig.target_state()
	rig._unhandled_input(_button(MOUSE_BUTTON_MIDDLE, true, CENTER))
	rig._unhandled_input(_motion(CENTER + Vector2(50.0, 30.0), Vector2(50.0, 30.0)))
	var s1 := rig.target_state()
	assert_float(s1.pitch_deg - s0.pitch_deg).is_equal_approx(30.0 * InputProfile.TILT_DEG_PER_PX, 0.001)
	assert_float(absf(CameraState.angle_delta_deg(s0.heading_deg, s1.heading_deg))).is_greater(1.0)
	assert_float(s1.distance).is_equal(s0.distance)


func test_keys_r_and_f_tilt_through_the_profile_and_survive_zoom() -> void:
	var rig := _rig(DesktopInputProfile.new())
	var p0 := rig.desired_pitch_deg()
	rig._unhandled_input(_key(KEY_R, true))
	rig._process(0.25)
	rig._unhandled_input(_key(KEY_R, false))
	assert_float(rig.desired_pitch_deg()).is_equal_approx(p0 + CameraRig.TILT_DEG_PER_S * 0.25, 0.01)
	var steeper := rig.desired_pitch_deg()
	rig._unhandled_input(_key(KEY_F, true))
	rig._process(0.1)
	rig._unhandled_input(_key(KEY_F, false))
	assert_float(rig.desired_pitch_deg()).is_equal_approx(steeper - CameraRig.TILT_DEG_PER_S * 0.1, 0.01)
	var after_f := rig.desired_pitch_deg()
	_zoom_steps(rig, 0.95, 4)
	assert_float(rig.desired_pitch_deg()).is_equal(after_f)


func test_trackpad_two_finger_scroll_pans_and_with_option_it_orbits() -> void:
	var rig := _rig(DesktopInputProfile.new())
	var s0 := rig.target_state()
	rig._unhandled_input(_pan_gesture(Vector2(0.0, -3.0), false))  # kaydırma: pan, eğim yok
	var panned := rig.target_state()
	assert_float(panned.pitch_deg).is_equal(s0.pitch_deg)
	assert_float(Vector2(panned.focus_x - s0.focus_x, panned.focus_z - s0.focus_z).length()).is_greater(1.0)
	# Parmaklar aşağı (PanGesture delta.y < 0, pan eşlemesiyle aynı işaret) + Option: dikleşir; odak/uzaklık sabit.
	rig._unhandled_input(_pan_gesture(Vector2(0.0, -3.0), true))
	var tilted := rig.target_state()
	assert_float(tilted.pitch_deg).is_greater(panned.pitch_deg)
	assert_float(tilted.focus_x).is_equal(panned.focus_x)
	assert_float(tilted.distance).is_equal(panned.distance)
	rig._unhandled_input(_pan_gesture(Vector2(0.0, 3.0), true))
	assert_float(rig.target_state().pitch_deg).is_less(tilted.pitch_deg)


func test_touch_three_finger_vertical_drag_tilts_without_pan_zoom_or_rotate() -> void:
	var rig := _rig(TouchInputProfile.new())
	var s0 := rig.target_state()
	rig._unhandled_input(_touch(0, true, Vector2(600.0, 400.0)))
	rig._unhandled_input(_touch(1, true, Vector2(800.0, 400.0)))
	rig._unhandled_input(_touch(2, true, Vector2(1000.0, 400.0)))
	for i in 3:
		for idx in 3:
			var x := 600.0 + 200.0 * idx
			rig._unhandled_input(_drag(idx, Vector2(x, 400.0 + 30.0 * (i + 1)), Vector2(0.0, 30.0)))
	var s1 := rig.target_state()
	assert_float(s1.pitch_deg - s0.pitch_deg).is_equal_approx(90.0 * InputProfile.TILT_DEG_PER_PX, 0.01)  # aşağı = dik
	assert_float(s1.distance).is_equal(s0.distance)
	assert_float(s1.focus_x).is_equal(s0.focus_x)
	assert_float(s1.heading_deg).is_equal(s0.heading_deg)
	# Üçüncü parmak kalkınca iki parmak jesti sıçramasız devam eder (eğim değişmez).
	rig._unhandled_input(_touch(2, false, Vector2(1000.0, 490.0)))
	rig._unhandled_input(_drag(1, Vector2(800.0, 500.0), Vector2(0.0, 10.0)))
	assert_float(rig.target_state().pitch_deg).is_equal(s1.pitch_deg)


func test_touch_two_finger_gestures_do_not_tilt() -> void:
	var rig := _rig(TouchInputProfile.new())
	var p0 := rig.desired_pitch_deg()
	rig._unhandled_input(_touch(0, true, Vector2(700.0, 450.0)))
	rig._unhandled_input(_touch(1, true, Vector2(900.0, 450.0)))
	rig._unhandled_input(_drag(0, Vector2(700.0, 550.0), Vector2(0.0, 100.0)))
	rig._unhandled_input(_drag(1, Vector2(900.0, 550.0), Vector2(0.0, 100.0)))
	assert_float(rig.desired_pitch_deg()).is_equal(p0)
