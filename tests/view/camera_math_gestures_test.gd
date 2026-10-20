extends GdUnitTestSuite
## T-003 ölçüt 1, 6 · Fiiller (saf): zoom-to-cursor anchor, sürekli zoom, içerik-izleyen pan, anchor etrafında döndürme.
## Naif algoritma ihlali ölçülerek testin duyarlılığı gösterilir (olumsuz varyant).

const CTS = preload("res://tests/view/camera_test_support.gd")

# --- Zoom-to-cursor ---

func test_zoom_keeps_the_ground_point_under_the_cursor_fixed() -> void:
	var g := CTS.hills
	for factor in [1.25, 0.8, 3.0, 0.4]:
		for px in CTS.PIXELS:
			var s := CTS.make_state(g)
			var before := CTS.under(s, px, g)
			var z := CameraMath.zoom_at(s, factor, px, CTS.VIEWPORT, g)
			var after := CTS.under(z, px, g)
			var shift := CTS.gap(before, after)
			assert_float(shift).is_less(0.1)  # 0,1 m: arazi bilineer kırılması, anchor yerinde
			assert_float(absf(z.distance - s.distance)).is_greater(1.0)  # gerçekten zoom yaptı


func test_naive_center_zoom_moves_the_cursor_point_so_the_anchor_test_is_sensitive() -> void:
	var g := CTS.hills
	var s := CTS.make_state(g)
	var px := Vector2(1400.0, 200.0)
	var before := CTS.under(s, px, g)
	var naive := s.copy()
	naive.distance = s.distance / 2.0  # yalnız uzaklık: odak sabit (imleç anchor'u yok)
	var after := CTS.under(naive, px, g)
	var shift := CTS.gap(before, after)
	assert_float(shift).is_greater(50.0)


func test_zoom_in_moves_continuously_across_metro_to_street_scales_without_gates() -> void:
	var g := CTS.flat
	var s := CTS.make_state(g, 0.0, 0.0, 58000.0, 50.0, 0.0)
	var last := s.distance
	var steps := 0
	while s.distance > CameraMath.MIN_DISTANCE_M + 0.001 and steps < 400:
		s = CameraMath.zoom_at(s, 1.1, CTS.VIEWPORT * 0.5 + Vector2(120.0, -80.0), CTS.VIEWPORT, g)
		assert_float(s.distance).is_less_equal(last + 1.0e-6)
		assert_float(last / s.distance).is_less(1.2)  # her adım ~%10: ölçek kapısı/sıçrama yok
		last = s.distance
		steps += 1
	assert_float(s.distance).is_equal_approx(CameraMath.MIN_DISTANCE_M, 0.01)
	assert_int(steps).is_between(80, 140)  # 58 km -> 25 m, ~%10 adımlarla


func test_zoom_respects_distance_limits_and_ignores_garbage_factors() -> void:
	var g := CTS.flat
	var s := CTS.make_state(g, 0.0, 0.0, 80000.0, 50.0, 0.0)
	var out := CameraMath.zoom_at(s, 0.1, CTS.VIEWPORT * 0.5, CTS.VIEWPORT, g)
	assert_float(out.distance).is_less_equal(CameraMath.MAX_DISTANCE_M)
	var near := CTS.make_state(g, 0.0, 0.0, CameraMath.MIN_DISTANCE_M, 50.0, 0.0)
	var zoomed := CameraMath.zoom_at(near, 4.0, CTS.VIEWPORT * 0.5, CTS.VIEWPORT, g)
	assert_float(zoomed.distance).is_greater_equal(CameraMath.MIN_DISTANCE_M - 0.001)
	for bad in [0.0, -2.0, NAN, INF]:
		var same := CameraMath.zoom_at(s, bad, CTS.VIEWPORT * 0.5, CTS.VIEWPORT, g)
		assert_bool(same.is_close_to(s)).is_true()


func test_zoom_over_sky_falls_back_without_nan() -> void:
	var g := CTS.hills
	var s := CTS.make_state(g, 1000.0, -500.0, 800.0, 10.0, 30.0)  # alçak eğim: üst ışınlar gökyüzüne gider
	var sky := Vector2(800.0, 2.0)
	assert_bool(CTS.under(s, sky, g)["ok"]).is_false()  # gökyüzü: ne zemin ne düzlem kesişimi
	var out := CameraMath.zoom_at(s, 1.3, sky, CTS.VIEWPORT, g)
	assert_bool(out.is_valid()).is_true()

# --- Pan (içerik imleci/parmağı izler) ---

func test_pan_makes_the_grabbed_ground_point_follow_the_cursor() -> void:
	var g := CTS.hills
	var s := CTS.make_state(g)
	var from_px := Vector2(900.0, 500.0)
	var to_px := Vector2(1100.0, 380.0)
	var grabbed := CTS.under(s, from_px, g)
	var moved := CameraMath.pan_grab(s, from_px, to_px, CTS.VIEWPORT, g)
	var now := CTS.under(moved, to_px, g)
	assert_float(CTS.gap(grabbed, now)).is_less(1.0)
	# Odak gerçekten kaydı (kıpırdamayan bir pan bu testi geçmemeli).
	assert_float(Vector2(moved.focus_x - s.focus_x, moved.focus_z - s.focus_z).length()).is_greater(20.0)


func test_pan_without_movement_is_identity_and_grabbing_the_sky_does_not_explode() -> void:
	var g := CTS.hills
	var s := CTS.make_state(g)
	var same := CameraMath.pan_grab(s, CTS.VIEWPORT * 0.5, CTS.VIEWPORT * 0.5, CTS.VIEWPORT, g)
	assert_bool(same.is_close_to(s, 0.001)).is_true()
	var tilted := CTS.make_state(g, 1000.0, -500.0, 800.0, 9.0, 30.0)
	var out := CameraMath.pan_grab(tilted, Vector2(800.0, 1.0), Vector2(900.0, 40.0), CTS.VIEWPORT, g)
	assert_bool(out.is_valid()).is_true()


func test_pan_is_clamped_to_world_bounds() -> void:
	var g := CTS.flat
	var s := CTS.make_state(g, 0.0, 0.0, 5000.0, 50.0, 0.0)
	var bounds := Rect2(-1000.0, -1000.0, 2000.0, 2000.0)
	var out := CameraMath.pan_grab(s, Vector2(100.0, 450.0), Vector2(1500.0, 450.0), CTS.VIEWPORT, g, bounds)
	assert_bool(bounds.has_point(Vector2(out.focus_x, out.focus_z))).is_true()
	var unbounded := CameraMath.pan_grab(s, Vector2(100.0, 450.0), Vector2(1500.0, 450.0), CTS.VIEWPORT, g)
	assert_float(absf(unbounded.focus_x)).is_greater(1000.0)  # sınır olmasaydı dışarı çıkardı

# --- Döndürme ---

func test_rotate_keeps_the_anchor_point_under_the_cursor() -> void:
	var g := CTS.flat
	for px in CTS.PIXELS:
		var s := CTS.make_state(g)
		var before := CTS.under(s, px, g)
		var r := CameraMath.rotate_about(s, 0.7, px, CTS.VIEWPORT, g)
		var after := CTS.under(r, px, g)
		assert_float(CTS.gap(before, after)) \
				.is_less(0.05)
		assert_float(CameraState.angle_delta_deg(s.heading_deg, r.heading_deg)).is_equal_approx(-rad_to_deg(0.7), 0.001)


func test_positive_rotation_turns_the_scene_clockwise_on_screen() -> void:
	# Sözleşme (InputProfile): pozitif = sahne ekranda SAAT YÖNÜNDE döner. Anchor'un doğusundaki nokta (kuzeye
	# bakarken ekranın sağı) saat yönünde dönerse ekranda AŞAĞI gider (anchor etrafında sağdan alta).
	var g := CTS.flat
	var s := CTS.make_state(g, 0.0, 0.0, 3000.0, 60.0, 0.0)
	var anchor_px := CTS.VIEWPORT * 0.5
	var east := Vector3(300.0, 0.0, 0.0)
	var p0 := CameraMath.project(s, east.x, 0.0, east.z, CTS.VIEWPORT)
	var r := CameraMath.rotate_about(s, 0.3, anchor_px, CTS.VIEWPORT, g)
	var p1 := CameraMath.project(r, east.x, 0.0, east.z, CTS.VIEWPORT)
	assert_float(p1.y).is_greater(p0.y + 1.0)
	var back := CameraMath.rotate_about(s, -0.3, anchor_px, CTS.VIEWPORT, g)
	assert_float(CameraMath.project(back, east.x, 0.0, east.z, CTS.VIEWPORT).y).is_less(p0.y - 1.0)


func test_rotate_ignores_garbage() -> void:
	var g := CTS.flat
	var s := CTS.make_state(g)
	for bad in [NAN, INF, 0.0]:
		assert_bool(CameraMath.rotate_about(s, bad, CTS.VIEWPORT * 0.5, CTS.VIEWPORT, g).is_close_to(s)).is_true()
