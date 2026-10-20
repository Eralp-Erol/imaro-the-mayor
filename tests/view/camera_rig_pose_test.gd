extends GdUnitTestSuite
## T-003 ölçüt 2, 3, 4, 6 · CameraRig pozu: gerçek Camera3D boru hattı, arazi üstünde kalma, yumuşatma (kare hızından
## bağımsız), origin rebasing eşdeğerliği (aynı dünya noktası -> aynı piksel), preset'ler ve kapılı zoom ayarı.
## Dummy renderer: AABB/çizim doğrulanamaz (capture ile bakılır); kamera matematiği ve dönüşümler burada sınanır.

var _world: WorldData
var _markers: Node3D
var _marker_world: Vector3


func before() -> void:
	_world = WorldTestSupport.coarse(WorldTestSupport.control())


func _ground() -> Callable:
	return func(x: float, z: float) -> float: return maxf(_world.height_at(x, z), _world.sea_level)


func _rig(spec: String, with_view_root: bool = true) -> CameraRig:
	var rig: CameraRig = auto_free(CameraRig.new())
	rig.input_profile = DesktopInputProfile.new()
	rig.smoothing_enabled = false
	if with_view_root:
		_markers = auto_free(Node3D.new())
		add_child(_markers)
		rig.view_root = _markers
	add_child(rig)
	rig.set_world(_world, _ground())
	rig.apply_preset(spec)
	return rig


# --- Poz ---

func test_camera_node_looks_at_the_focus_through_the_real_camera_pipeline() -> void:
	var rig := _rig("district:D4")
	var s := rig.current_state()
	var screen := rig.world_to_screen(s.focus_x, s.focus_y, s.focus_z)
	var size := rig.get_viewport().get_visible_rect().size
	assert_float(screen.distance_to(size * 0.5)).is_less(1.0)  # odak ekranın tam ortasında
	# Saf matematik ile Camera3D aynı pikseli verir (iki bağımsız uygulama).
	var other := Vector3(s.focus_x + 900.0, s.focus_y, s.focus_z - 400.0)
	var by_math := CameraMath.project(s, other.x, other.y, other.z, size)
	assert_float(rig.world_to_screen(other.x, other.y, other.z).distance_to(by_math)).is_less(0.5)


func test_near_and_far_follow_the_distance_and_cover_the_horizon_from_street_level() -> void:
	var metro := _rig("metro")
	var nf_metro := CameraMath.near_far(metro.distance())
	assert_float(metro.camera.near).is_equal_approx(nf_metro.x, 0.001)
	var street := _rig("street:port")
	assert_float(street.camera.near).is_less(2.0)
	assert_float(street.camera.far).is_greater(55000.0)  # sokaktan metro ufku görünür kalır


func test_camera_stays_above_the_terrain_while_flying_metro_to_street_and_back() -> void:
	var rig := _rig("metro")
	var g := _ground()
	var px := Vector2(900.0, 380.0)
	var lowest := INF
	for i in 160:
		rig.on_zoom(1.1, px)
		rig.snap_to_target()
		var local := rig.camera.global_position
		var world_x := local.x + rig.rebase_origin.x
		var world_z := local.z + rig.rebase_origin.y
		lowest = minf(lowest, local.y - float(g.call(world_x, world_z)))
	assert_float(rig.distance()).is_less(40.0)
	assert_float(lowest).is_greater(CameraMath.CLEARANCE_MIN_M - 0.05)
	for i in 160:
		rig.on_zoom(1.0 / 1.1, px)
		rig.snap_to_target()
	assert_float(rig.distance()).is_greater(50000.0)


func test_street_scale_hillside_camera_is_lifted_when_the_raw_orbit_eye_would_be_underground() -> void:
	var rig := _rig("street:D5")  # D5: yamaçlar
	var s := rig.current_state()
	s.pitch_deg = CameraMath.MIN_PITCH_DEG
	s.distance = CameraMath.MIN_DISTANCE_M
	for h in range(0, 360, 20):
		s.heading_deg = float(h)
		rig.apply_state(s, true)
		var eye := rig.camera.global_position + Vector3(rig.rebase_origin.x, 0.0, rig.rebase_origin.y)
		assert_float(eye.y).is_greater_equal(float(_ground().call(eye.x, eye.z)) + CameraMath.CLEARANCE_MIN_M - 0.05)


# --- Yumuşatma ---

func test_smoothing_converges_to_the_target_and_is_frame_rate_independent() -> void:
	var a := _rig("district:D4")
	var b := _rig("district:D4")
	a.smoothing_enabled = true
	b.smoothing_enabled = true
	a.on_zoom(2.0, Vector2(500.0, 300.0))
	b.on_zoom(2.0, Vector2(500.0, 300.0))
	assert_float(a.distance()).is_greater(a.target_state().distance * 1.5)  # henüz varmadı
	for i in 15:
		a._smooth(1.0 / 30.0)  # yarım saniye 30 fps
	for i in 60:
		b._smooth(1.0 / 120.0)  # yarım saniye 120 fps
	assert_float(a.distance()).is_equal_approx(b.distance(), a.distance() * 0.002)
	for i in 120:
		a._smooth(1.0 / 60.0)
	assert_bool(a.current_state().is_close_to(a.target_state(), 0.01)).is_true()  # yakınsadı


func test_zoom_anchor_stays_under_the_cursor_through_the_smoothing_flight() -> void:
	var rig := _rig("district:D4")
	rig.smoothing_enabled = true
	var px := Vector2(1250.0, 300.0)
	var size := rig.get_viewport().get_visible_rect().size
	var anchor := CameraMath.grab_point(rig.current_state(), px * size / Vector2(1600.0, 900.0), size, _ground())
	rig.on_zoom(1.15, px * size / Vector2(1600.0, 900.0))
	var worst := 0.0
	for i in 40:
		rig._smooth(1.0 / 60.0)
		var seen := CameraMath.project(rig.current_state(), anchor["x"], anchor["y"], anchor["z"], size)
		worst = maxf(worst, seen.distance_to(px * size / Vector2(1600.0, 900.0)))
	assert_float(worst).is_less(8.0)  # tek tekerlek adımı boyunca imleç noktası <8 piksel kayar (dalga geçişi)


# --- Origin rebasing ---

func test_same_world_point_has_the_same_screen_position_before_and_after_rebasing() -> void:
	var rig := _rig("street:port")
	var s := rig.current_state()
	var mark := _add_marker(Vector3(s.focus_x + 12.0, s.focus_y + 1.0, s.focus_z - 7.0))
	var before_px := rig.world_to_screen(_marker_world.x, _marker_world.y, _marker_world.z)
	var before_cam := rig.camera.unproject_position(mark.global_position)
	var origin_before := rig.rebase_origin
	rig.set_rebase_origin(origin_before + Vector2(3584.0, -1024.0))
	var after_px := rig.world_to_screen(_marker_world.x, _marker_world.y, _marker_world.z)
	var after_cam := rig.camera.unproject_position(mark.global_position)
	assert_bool(rig.rebase_origin != origin_before).is_true()
	assert_float(after_px.distance_to(before_px)).is_less(0.01)
	assert_float(after_cam.distance_to(before_cam)).is_less(0.01)
	assert_float(after_cam.distance_to(after_px)).is_less(0.01)  # içerik de, kamera da kaydı
	assert_float(rig.view_root.position.x).is_equal(-rig.rebase_origin.x)


func test_camera_only_shift_without_moving_the_content_would_jump_so_the_test_is_sensitive() -> void:
	var rig := _rig("street:port")
	var s := rig.current_state()
	var mark := _add_marker(Vector3(s.focus_x + 12.0, s.focus_y + 1.0, s.focus_z - 7.0))
	var before_px := rig.camera.unproject_position(mark.global_position)
	rig.rebase_origin = rig.rebase_origin + Vector2(2048.0, 0.0)  # YANLIŞ: view_root kaydırılmadan
	rig._place_camera()
	var wrong_px := rig.camera.unproject_position(mark.global_position)
	assert_bool(is_nan(wrong_px.x) or wrong_px.distance_to(before_px) > 50.0).is_true()


func test_rebasing_triggers_only_after_the_focus_travels_and_never_moves_the_picture() -> void:
	var rig := _rig("street:port")
	var s := rig.current_state()
	var mark := _add_marker(Vector3(s.focus_x + 20.0, s.focus_y, s.focus_z + 20.0))
	var count := rig.rebase_count
	var origin := rig.rebase_origin
	var step := CameraState.new()
	step = rig.current_state()
	step.focus_x += 300.0  # eşik altı
	rig.apply_state(step, true)
	assert_int(rig.rebase_count).is_equal(count)
	assert_bool(rig.rebase_origin == origin).is_true()
	var px_near := rig.world_to_screen(_marker_world.x, _marker_world.y, _marker_world.z)
	step = rig.current_state()
	step.focus_x += 2500.0  # eşik üstü
	rig.apply_state(step, true)
	assert_int(rig.rebase_count).is_equal(count + 1)
	assert_float(fmod(rig.rebase_origin.x, CameraMath.REBASE_GRID_M)).is_equal(0.0)
	# Aynı dünya noktası (artık görüş dışı olabilir) hâlâ aynı yerel koordinatla hesaplanır: global = dünya - origin.
	assert_float(mark.global_position.x).is_equal_approx(_marker_world.x - rig.rebase_origin.x, 0.001)
	assert_float(px_near.x).is_not_equal(INF)


func test_zoom_flight_from_metro_to_street_keeps_the_cursor_point_fixed_across_every_rebase() -> void:
	var rig := _rig("metro")
	var size := rig.get_viewport().get_visible_rect().size
	var px := size * Vector2(0.78, 0.33)  # merkezden uzak bir imleç noktası
	var anchor := rig.screen_to_ground(px)
	assert_bool(anchor["ok"]).is_true()
	var worst := 0.0
	var steps := 0
	while rig.distance() > 60.0 and steps < 200:
		rig.on_zoom(1.1, px)
		var seen := rig.world_to_screen(anchor["x"], anchor["y"], anchor["z"])
		worst = maxf(worst, seen.distance_to(px))
		steps += 1
	assert_float(rig.distance()).is_less_equal(60.0)
	assert_int(rig.rebase_count).is_greater(2)  # uçuş sırasında origin birkaç kez yeniden oturdu
	assert_float(worst).is_less(1.0)  # hiçbir adımda (rebasing dahil) imleç noktası 1 pikselden fazla kaymadı


func test_without_a_view_root_rebasing_stays_off_and_origin_is_zero() -> void:
	var rig := _rig("metro", false)
	var s := rig.current_state()
	s.focus_x += 9000.0
	rig.apply_state(s, true)
	assert_int(rig.rebase_count).is_equal(0)
	assert_bool(rig.rebase_origin == Vector2.ZERO).is_true()


# --- Preset'ler ---

func test_presets_apply_to_the_rig_and_bad_ones_fall_back_to_metro_with_an_error() -> void:
	var rig := _rig("metro")
	assert_bool(rig.apply_preset("district:D2")).is_true()
	assert_str(String(rig.preset_name)).is_equal("district")
	var d2 := _world.region_by_code(&"D2")
	assert_float(rig.focus_xz().distance_to(d2.anchor)).is_less(0.5)
	assert_bool(rig.apply_preset("street:port")).is_true()
	assert_float(rig.distance()).is_less(200.0)
	assert_bool(rig.apply_preset("district:D99")).is_false()  # push_error beklenir; çökme yok
	assert_str(String(rig.preset_name)).is_equal("metro")
	assert_float(rig.distance()).is_greater(50000.0)


# --- Kapılı zoom ayarı (UX Q-011 AÇIK) ---

func test_continuous_zoom_is_the_default_and_gated_zoom_lands_on_the_gates() -> void:
	var rig := _rig("metro")
	assert_bool(rig.continuous_zoom).is_true()
	var d0 := rig.distance()
	rig.on_zoom(1.1, Vector2(800.0, 450.0))
	assert_float(rig.target_state().distance).is_equal_approx(d0 / 1.1, 100.0)  # sürekli adım: kapıya oturmaz
	var gated := _rig("metro")
	gated.continuous_zoom = false
	var seen: Array[float] = []
	for i in 6:
		gated.on_zoom(1.1, Vector2(800.0, 450.0))
		seen.append(gated.target_state().distance)
	for d in seen:
		var on_gate := false
		for g in CameraRig.ZOOM_GATES_M:
			on_gate = on_gate or absf(d - g) < g * 0.1  # anchor korunur: kapıya ±%10 (arazi, merkez ışın isabeti)
		assert_bool(on_gate).override_failure_message("mesafe %s bir kapıda değil" % d).is_true()
	assert_float(seen[0]).is_greater(seen[seen.size() - 1])


func test_garbage_zoom_pan_rotate_values_leave_the_rig_valid() -> void:
	var rig := _rig("district:D4")
	var before_state := rig.target_state()
	rig.on_zoom(NAN, Vector2(800.0, 450.0))
	rig.on_zoom(-1.0, Vector2(800.0, 450.0))
	rig.on_rotate(INF, Vector2(800.0, 450.0))
	rig.on_pan(Vector2(NAN, 5.0))
	rig.tilt(NAN)
	assert_bool(rig.target_state().is_valid()).is_true()
	assert_bool(rig.target_state().is_close_to(before_state, 0.001)).is_true()
	rig.apply_state(CameraState.new(), true)  # geçerli ama dünya dışı: kenetlenir
	assert_bool(_world.bounds().has_point(rig.focus_xz())).is_true()


func _add_marker(world_pos: Vector3) -> Node3D:
	var m: Node3D = auto_free(Node3D.new())
	_markers.add_child(m)
	m.position = world_pos  # view_root altında: dünya konumu (rebasing view_root'ta)
	_marker_world = world_pos
	return m
