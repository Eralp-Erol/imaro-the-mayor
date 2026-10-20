extends GdUnitTestSuite
## T-003 ölçüt 2-3, 6 · Arazi üstünde kalma, yakın/uzak düzlem derinlik çözünürlüğü, origin rebasing hassasiyeti (saf).

const CTS = preload("res://tests/view/camera_test_support.gd")

# --- Arazi üstünde kalma ---

func test_eye_never_goes_below_the_terrain_over_all_scales_and_pitches() -> void:
	var g := CTS.hills
	var rng := RandomNumberGenerator.new()
	rng.seed = 1467
	for i in 400:
		var s := CameraState.new()
		s.focus_x = rng.randf_range(-3000.0, 3000.0)
		s.focus_z = rng.randf_range(-3000.0, 3000.0)
		s.distance = exp(rng.randf_range(log(CameraMath.MIN_DISTANCE_M), log(90000.0)))
		s.pitch_deg = rng.randf_range(CameraMath.MIN_PITCH_DEG, CameraMath.MAX_PITCH_DEG)
		s.heading_deg = rng.randf_range(0.0, 360.0)
		CameraMath.reseat(s, g)
		var eye := CameraMath.eye_world(s, g)
		var floor_y := float(g.call(eye.x, eye.z)) + CameraMath.clearance_m(s.distance)
		assert_float(eye.y).is_greater_equal(floor_y - 0.001)


func test_without_the_clearance_clamp_a_low_hillside_camera_would_be_underground() -> void:
	# Olumsuz varyant: ham yörünge gözü (kenetsiz) bu durumda zemin altındadır; testin ölçtüğü şey gerçek.
	var g := func(x: float, _z: float) -> float: return maxf(0.0, x * 0.5)  # 26 derece yamaç
	var s := CameraState.new()
	s.focus_x = 400.0
	s.distance = 60.0
	s.pitch_deg = 10.0
	s.heading_deg = 270.0  # batıya (yokuş aşağı) bakıyor: göz odağın doğusunda, yani yokuş yukarıda
	CameraMath.reseat(s, g)
	var raw := CameraMath.eye_offset(s)
	var raw_y := s.focus_y + raw.y
	var ground_at_raw := float(g.call(s.focus_x + raw.x, s.focus_z + raw.z))
	var clamped := CameraMath.eye_world(s, g)
	assert_float(raw_y).is_less(ground_at_raw)  # ham göz zemin içinde
	assert_float(clamped.y).is_greater(float(g.call(clamped.x, clamped.z)))

# --- Yakın/uzak düzlem ---

func test_near_far_scale_with_distance_and_keep_depth_resolution_small_where_it_matters() -> void:
	for d in [CameraMath.MIN_DISTANCE_M, 100.0, 1000.0, 10000.0, 58000.0, 90000.0]:
		var nf := CameraMath.near_far(d)
		assert_float(nf.x).is_between(CameraMath.NEAR_MIN_M, CameraMath.NEAR_MAX_M)
		assert_float(nf.y).is_greater(nf.x * 100.0)
		# Odak uzaklığında derinlik çözünürlüğü, uzaklığın 1e-5'inden iyi (24 bit): odak çevresinde z-fighting yok.
		assert_float(CameraMath.depth_resolution_m(nf.x, nf.y, d) / d).is_less(1.0e-5)
		# Uzaklığın 3 katında bile 1e-4'ün altında.
		assert_float(CameraMath.depth_resolution_m(nf.x, nf.y, d * 3.0) / (d * 3.0)).is_less(1.0e-4)


func test_a_fixed_tiny_near_plane_would_fail_the_depth_budget_at_metro_scale() -> void:
	# Olumsuz varyant: sabit near=0.5 + far=120 km (metro) -> odakta çözünürlük uzaklığın 1e-5'ini aşar.
	assert_float(CameraMath.depth_resolution_m(0.5, 120000.0, 58000.0) / 58000.0).is_greater(1.0e-5)

# --- Origin rebasing ---

func test_float32_rounding_is_identity_on_representable_and_lossy_otherwise() -> void:
	assert_float(CameraMath.f32(0.5)).is_equal(0.5)
	assert_float(CameraMath.f32(38123.456789)).is_not_equal(38123.456789)


func test_rebasing_reduces_float32_position_error_at_street_scale_far_from_the_world_origin() -> void:
	# Kamera/yüzey dünya x = 38123.456789 m (metro doğu ucu). Rebasing'siz: iki konum da 32-bit'e yuvarlanır.
	var cam := 38123.456789
	var point := cam + 12.3456789  # 12 m önündeki nokta
	var unrebased := CameraMath.f32(point) - CameraMath.f32(cam)
	var origin := 38144.0  # 512'nin katı: 32-bit'te tam
	var rebased := CameraMath.f32(point - origin) - CameraMath.f32(cam - origin)
	var truth := point - cam
	assert_float(absf(rebased - truth)).is_less(absf(unrebased - truth) * 0.2)
	assert_float(absf(rebased - truth)).is_less(0.0001)  # 0,1 mm
	assert_float(absf(unrebased - truth)).is_greater(0.0005)  # rebasing'siz kayıp ölçülür büyüklükte


func test_snapped_origin_is_exactly_representable_in_float32() -> void:
	for x in [0.0, 512.0, 38144.0, -20480.0, 49999.0]:
		var snapped_x := CameraMath.snap_origin(x)
		assert_float(CameraMath.f32(snapped_x)).is_equal(snapped_x)
		assert_float(fmod(snapped_x, CameraMath.REBASE_GRID_M)).is_equal(0.0)
		assert_float(absf(snapped_x - x)).is_less_equal(CameraMath.REBASE_GRID_M * 0.5 + 0.001)
