extends GdUnitTestSuite
## T-003 ölçüt 1-2, 6 · Kamera geometrisi (saf, başsız): yörünge, ekran ışını/izdüşüm, zemine ışın.
## Her değişmez olumsuz varyantla da sınanır.

const CTS = preload("res://tests/view/camera_test_support.gd")


# --- Yörünge geometrisi ---

func test_heading_zero_looks_north_and_ninety_looks_east_with_pitch_down() -> void:
	var north := CameraMath.forward(0.0, 0.0)
	assert_float(north.z).is_equal_approx(-1.0, 1.0e-6)
	var east := CameraMath.forward(90.0, 0.0)
	assert_float(east.x).is_equal_approx(1.0, 1.0e-6)
	var down := CameraMath.forward(0.0, 90.0)
	assert_float(down.y).is_equal_approx(-1.0, 1.0e-6)


func test_camera_basis_is_orthonormal_right_handed_and_looks_along_forward() -> void:
	for h in [0.0, 37.0, 181.0, 300.0]:
		for p in [8.0, 45.0, 88.0]:
			var b := CameraMath.basis_for(h, p)
			assert_float(b.x.dot(b.y)).is_equal_approx(0.0, 1.0e-6)
			assert_float(b.y.dot(b.z)).is_equal_approx(0.0, 1.0e-6)
			assert_float(b.determinant()).is_equal_approx(1.0, 1.0e-6)
			assert_float((-b.z).distance_to(CameraMath.forward(h, p))).is_less(1.0e-6)
			assert_float(b.y.y).is_greater(0.0)  # yukarı vektörü yukarıda: kamera ters dönmez


func test_eye_sits_behind_the_focus_on_the_view_axis_at_the_given_distance() -> void:
	var s := CTS.make_state(CTS.flat, 0.0, 0.0, 1000.0, 30.0, 90.0)
	var off := CameraMath.eye_offset(s)
	assert_float(off.length()).is_equal_approx(1000.0, 1.0e-3)
	assert_float(off.x).is_less(0.0)  # doğuya bakıyor: göz batıda
	assert_float(off.y).is_equal_approx(500.0, 0.01)  # sin(30) * 1000


func test_distance_and_pitch_clamps_and_non_finite_input_is_rejected() -> void:
	assert_float(CameraMath.clamp_distance(1.0)).is_equal(CameraMath.MIN_DISTANCE_M)
	assert_float(CameraMath.clamp_distance(1.0e9)).is_equal(CameraMath.MAX_DISTANCE_M)
	assert_float(CameraMath.clamp_pitch_deg(0.0)).is_equal(CameraMath.MIN_PITCH_DEG)
	assert_float(CameraMath.clamp_pitch_deg(100.0)).is_equal(CameraMath.MAX_PITCH_DEG)
	assert_float(CameraMath.clamp_distance(NAN)).is_equal(CameraMath.MIN_DISTANCE_M)


func test_state_validity_rejects_nan_and_non_positive_distance() -> void:
	var s := CTS.make_state(CTS.flat)
	assert_bool(s.is_valid()).is_true()
	s.focus_x = NAN
	assert_bool(s.is_valid()).is_false()
	var t := CTS.make_state(CTS.flat)
	t.distance = 0.0
	assert_bool(t.is_valid()).is_false()


func test_state_approach_takes_the_shortest_way_around_the_heading_circle() -> void:
	var a := CTS.make_state(CTS.flat)
	a.heading_deg = 350.0
	var b := a.copy()
	b.heading_deg = 10.0
	a.approach(b, 0.5)
	assert_float(CameraState.angle_delta_deg(a.heading_deg, 0.0)).is_equal_approx(0.0, 1.0e-6)  # 0, 180 değil


# --- Ekran ışını / izdüşüm ---

func test_center_pixel_ray_is_the_view_axis_and_project_inverts_ray_dir() -> void:
	var s := CTS.make_state(CTS.flat)
	var center := CameraMath.ray_dir(s, CTS.VIEWPORT * 0.5, CTS.VIEWPORT)
	assert_float(center.distance_to(CameraMath.forward(s.heading_deg, s.pitch_deg))).is_less(1.0e-6)
	var eye := CameraMath.eye_offset(s)
	for px in CTS.PIXELS:
		var dir := CameraMath.ray_dir(s, px, CTS.VIEWPORT)
		var world := Vector3(s.focus_x, s.focus_y, s.focus_z) + eye + dir * 900.0
		var back := CameraMath.project(s, world.x, world.y, world.z, CTS.VIEWPORT)
		assert_float(back.distance_to(px)).is_less(0.01)


func test_point_behind_the_camera_does_not_project() -> void:
	var s := CTS.make_state(CTS.flat)
	var behind := Vector3(s.focus_x, s.focus_y, s.focus_z) + CameraMath.eye_offset(s) * 2.0
	assert_bool(is_nan(CameraMath.project(s, behind.x, behind.y, behind.z, CTS.VIEWPORT).x)).is_true()


# --- Zemine ışın ---

func test_ray_hits_terrain_surface_and_misses_when_looking_at_the_sky() -> void:
	var s := CTS.make_state(CTS.hills)
	for px in CTS.PIXELS:
		var hit := CTS.under(s, px, CTS.hills)
		assert_bool(hit["ok"]).is_true()
		assert_float(float(hit["y"])).is_equal_approx(CTS.hills.call(hit["x"], hit["z"]), 0.05)
	var eye := CameraMath.eye_world(s, CTS.hills)
	var miss := CameraMath.ray_ground_hit(eye.x, eye.y, eye.z, Vector3(0.0, 1.0, 0.0), CTS.hills, 50000.0)
	assert_bool(miss["hit"]).is_false()


func test_ray_starting_below_the_ground_reports_an_immediate_hit() -> void:
	var hit := CameraMath.ray_ground_hit(0.0, -5.0, 0.0, Vector3(0.0, 0.0, -1.0), CTS.flat, 1000.0)
	assert_bool(hit["hit"]).is_true()
	assert_float(float(hit["t"])).is_less(1.0e-3)
