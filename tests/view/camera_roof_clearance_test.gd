extends GdUnitTestSuite
## ADR-0007 Ek c (art-director T-062 madde 3) · bina farkında göz açıklığı: göz, çevresindeki 15 m içindeki en yüksek
## çatının en az 2 m üstünde kalır; çatı yokken/uzakta/ölçek dışında değişmez; kaldırma kare başı sıçramaz;
## istenen eğim,
## fiili eğim ve odak/uzaklık aynı kalır. Sayılar `data/view/camera_envelope.json`'dan okunur.

const FLAT_WORLD_M := 8000.0

var _env: CameraEnvelope


func before() -> void:
	_env = CameraEnvelope.load_default()


func _ground() -> Callable:
	return CameraTestSupport.flat


## Bir çatı: merkez (x, z), yarı boyutlar 5 m, yaw 0, tepe `top` (dünya y).
func _roofs(entries: Array) -> RoofClearance:
	var xs := PackedFloat32Array()
	var zs := PackedFloat32Array()
	var yaws := PackedFloat32Array()
	var hws := PackedFloat32Array()
	var hds := PackedFloat32Array()
	var tops := PackedFloat32Array()
	for e: Dictionary in entries:
		xs.append(float(e["x"]))
		zs.append(float(e["z"]))
		yaws.append(float(e.get("yaw", 0.0)))
		hws.append(float(e.get("hw", 5.0)))
		hds.append(float(e.get("hd", 5.0)))
		tops.append(float(e["top"]))
	var out := RoofClearance.new()
	out.set_roofs(xs, zs, yaws, hws, hds, tops)
	return out


func _rig(roofs: RoofClearance, smoothing: bool = false) -> CameraRig:
	var rig: CameraRig = auto_free(CameraRig.new())
	rig.input_profile = DesktopInputProfile.new()
	rig.smoothing_enabled = smoothing
	rig.viewport_size_override = CameraTestSupport.VIEWPORT
	add_child(rig)
	rig.set_world(null, _ground())
	rig.roof_clearance = roofs
	return rig


## Sokak göz hizası: odak (0, 0), kuzeye bakar (-z); göz odağın GÜNEYİNDE (+z) `distance` kadar geride, ~3 m yüksekte.
func _street_state(distance: float = 60.0, focus_z: float = 0.0, pitch: float = 3.0) -> CameraState:
	var s := CameraState.new()
	s.focus_x = 0.0
	s.focus_z = focus_z
	s.distance = distance
	s.pitch_deg = pitch
	s.heading_deg = 0.0
	return s


func _raw_eye(rig: CameraRig) -> Vector3:
	return CameraMath.eye_world(rig.current_state(), _ground())


# --- Ana kural ---

func test_the_eye_clears_the_highest_roof_within_the_radius_by_the_margin() -> void:
	var rig := _rig(_roofs([{"x": 0.0, "z": 50.0, "top": 20.0}]))
	rig.apply_state(_street_state(), true)
	var raw := _raw_eye(rig)
	assert_float(raw.y).is_less(10.0)  # ön koşul: ham göz çatının çok altında (yatay bakış)
	var roof := 20.0
	assert_float(rig.camera.global_position.y).is_greater_equal(roof + _env.roof_margin_m - 0.001)
	assert_float(rig.camera.global_position.y).is_greater_equal(roof + _env.roof_margin_m - 0.001)
	assert_float(rig.eye_lift_m()).is_greater(10.0)
	# Yalnız y itilir: x/z ham göz ile aynı.
	assert_float(rig.camera.global_position.x - rig.rebase_origin.x).is_equal_approx(raw.x - rig.rebase_origin.x, 0.001)


func test_the_tallest_of_several_roofs_inside_the_radius_decides_and_roofs_beyond_it_do_not() -> void:
	var near := {"x": 0.0, "z": 55.0, "top": 12.0}
	var tall := {"x": 8.0, "z": 62.0, "top": 31.0}
	var beyond := {"x": 0.0, "z": 59.9 - _env.roof_radius_m - 5.0 - 5.0 - 1.0, "top": 90.0}
	var rig := _rig(_roofs([near, tall, beyond]))
	rig.apply_state(_street_state(), true)
	assert_float(rig.camera.global_position.y).is_equal_approx(31.0 + _env.roof_margin_m, 0.01)


func test_a_roof_whose_footprint_edge_is_just_outside_the_radius_is_ignored_and_just_inside_counts() -> void:
	var probe := _rig(_roofs([]))
	probe.apply_state(_street_state(), true)
	var eye_z := _raw_eye(probe).z
	# Kuzey kenarı gözden (radius + 0,5) ve (radius - 0,5) uzakta: merkez = göz - kenar - yarı derinlik.
	var outside := _roofs([{"x": 0.0, "z": eye_z - (_env.roof_radius_m + 0.5) - 5.0, "top": 40.0}])
	var inside := _roofs([{"x": 0.0, "z": eye_z - (_env.roof_radius_m - 0.5) - 5.0, "top": 40.0}])
	var rig_out := _rig(outside)
	rig_out.apply_state(_street_state(), true)
	assert_float(rig_out.eye_lift_m()).is_equal(0.0)
	var rig_in := _rig(inside)
	rig_in.apply_state(_street_state(), true)
	assert_float(rig_in.camera.global_position.y).is_greater_equal(40.0 + _env.roof_margin_m - 0.001)


func test_without_roofs_the_pose_is_exactly_the_terrain_only_pose() -> void:
	var with_empty := _rig(_roofs([]))
	var without := _rig(null)
	var far_roof := _rig(_roofs([{"x": 900.0, "z": 900.0, "top": 80.0}]))
	for rig in [with_empty, without, far_roof]:
		(rig as CameraRig).apply_state(_street_state(), true)
	for rig in [with_empty, far_roof]:
		assert_float((rig as CameraRig).eye_lift_m()).is_equal(0.0)
		assert_vector((rig as CameraRig).camera.global_transform.origin).is_equal(without.camera.global_transform.origin)
	assert_float(without.camera.global_position.y).is_equal_approx(_raw_eye(without).y, 1.0e-6)


func test_a_high_eye_that_already_clears_the_roof_is_left_alone() -> void:
	var rig := _rig(_roofs([{"x": 0.0, "z": 0.0, "top": 12.0}]))
	var s := _street_state(120.0, 0.0, 40.0)  # 40 derece: göz ~77 m yukarıda
	rig.apply_state(s, true)
	assert_float(rig.eye_lift_m()).is_equal(0.0)


# --- Yalnız yakın bantlarda ---

func test_the_effect_is_full_through_the_active_band_fades_and_is_gone_beyond() -> void:
	var tall := 5000.0
	var lifts: Array[float] = []
	for d in [_env.roof_active_below_m, (_env.roof_active_below_m + _env.roof_fade_to_m) * 0.5, _env.roof_fade_to_m]:
		var rig := _rig(null)
		var state := _street_state(d)
		rig.apply_state(state, true)
		var eye := CameraMath.eye_world(rig.current_state(), _ground())
		rig.roof_clearance = _roofs([{"x": eye.x, "z": eye.z, "top": tall}])
		rig.snap_to_target()
		lifts.append(rig.eye_lift_m())
	var full_goal := tall + _env.roof_margin_m
	assert_float(lifts[0]).is_greater(full_goal * 0.99 - 700.0)  # tam ağırlık (ham göz yükseğinin altında kalan pay)
	assert_float(lifts[1]).is_greater(0.0)
	assert_float(lifts[1]).is_less(lifts[0])
	assert_float(lifts[2]).is_equal(0.0)


func test_the_weight_curve_comes_from_the_data_and_the_legacy_envelope_has_no_effect() -> void:
	assert_float(_env.roof_weight(_env.roof_active_below_m)).is_equal(1.0)
	assert_float(_env.roof_weight(_env.roof_fade_to_m)).is_equal(0.0)
	assert_float(_env.roof_radius_m).is_equal(15.0)  # sahip/art-director talebi (çalışma değeri)
	assert_float(_env.roof_margin_m).is_equal(2.0)
	var legacy := CameraEnvelope.legacy()
	assert_array(Array(legacy.errors)).is_empty()
	assert_float(legacy.roof_weight(100.0)).is_equal(0.0)
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CameraEnvelope.DATA_PATH))
	var bad: Dictionary = (raw["player"] as Dictionary).duplicate(true)
	(bad["eye_roof_clearance"] as Dictionary)["fade_to_m"] = 100.0
	assert_bool(CameraEnvelope.validate(bad).is_empty()).is_false()


# --- Eğim ve zarf bozulmaz ---

func test_the_desired_pitch_the_actual_pitch_distance_and_focus_do_not_change() -> void:
	var lifted := _rig(_roofs([{"x": 0.0, "z": 50.0, "top": 25.0}]))
	var plain := _rig(null)
	for rig in [lifted, plain]:
		(rig as CameraRig).apply_state(_street_state(), true)
		(rig as CameraRig).tilt(-5.0)  # 3 derece tabanında kal
	assert_float(lifted.eye_lift_m()).is_greater(5.0)
	assert_float(lifted.desired_pitch_deg()).is_equal(plain.desired_pitch_deg())
	var a := lifted.target_state()
	var b := plain.target_state()
	assert_float(a.pitch_deg).is_equal(b.pitch_deg)
	assert_float(a.distance).is_equal(b.distance)
	assert_float(a.focus_x).is_equal(b.focus_x)
	assert_float(a.focus_z).is_equal(b.focus_z)
	assert_float(lifted.current_state().pitch_deg).is_equal(plain.current_state().pitch_deg)
	# Kamera DÖNÜŞÜ aynı (eğim değişmedi): yalnız konum yükseldi.
	assert_bool(lifted.camera.global_transform.basis.is_equal_approx(plain.camera.global_transform.basis)).is_true()


# --- Sıçramasızlık ---

func test_the_lift_ramps_without_a_per_frame_jump_while_the_camera_approaches_and_leaves_a_tall_roof() -> void:
	var rig := _rig(_roofs([{"x": 0.0, "z": -250.0, "top": 30.0}]), true)
	rig.apply_state(_street_state(60.0, -150.0), true)  # henüz 15 m dışında
	assert_float(rig.eye_lift_m()).is_equal(0.0)
	var dt := 1.0 / 60.0
	var prev := 0.0
	var max_step := 0.0
	var peak := 0.0
	# Odağı çatıya doğru yürüt (20 m/s), çatının yanından geç, sonra uzaklaş.
	var target := _street_state(60.0, -150.0)
	for frame in 900:
		target.focus_z -= 20.0 * dt * (1.0 if frame < 450 else -1.0)
		rig.apply_state(target, false)
		rig._process(dt)
		max_step = maxf(max_step, absf(rig.eye_lift_m() - prev))
		peak = maxf(peak, rig.eye_lift_m())
		prev = rig.eye_lift_m()
	var gap := 30.0 + _env.roof_margin_m
	assert_float(peak).is_greater(gap * 0.5)  # kaldırma gerçekten devreye girdi
	var one_frame := 1.0 - exp(-_env.roof_smooth_rate_per_s * dt)
	assert_float(max_step).override_failure_message("kare başı sıçrama %.3f m" % max_step).is_less_equal(
			gap * one_frame + 0.01)


func test_the_jump_check_is_sensitive_unsmoothed_lift_steps_the_whole_gap_in_one_frame() -> void:
	var rig := _rig(_roofs([{"x": 0.0, "z": -250.0, "top": 30.0}]), false)
	rig.apply_state(_street_state(60.0, -150.0), true)
	var target := _street_state(60.0, -290.0)
	rig.apply_state(target, false)
	rig._process(1.0 / 60.0)
	assert_float(rig.eye_lift_m()).is_greater(20.0)  # tek karede tam boşluk


func test_a_resting_camera_settles_to_the_roof_plus_margin_and_back_to_zero() -> void:
	var rig := _rig(_roofs([{"x": 0.0, "z": 50.0, "top": 22.0}]), true)
	rig.apply_state(_street_state(60.0, 500.0), true)
	assert_float(rig.eye_lift_m()).is_equal(0.0)
	rig.apply_state(_street_state(), false)
	for i in 600:
		rig._process(1.0 / 60.0)
	assert_float(rig.camera.global_position.y).is_greater_equal(22.0 + _env.roof_margin_m - 0.001)
	rig.apply_state(_street_state(60.0, 500.0), false)
	for i in 600:
		rig._process(1.0 / 60.0)
	assert_float(rig.eye_lift_m()).is_equal(0.0)


# --- Sağlayıcı ---

func test_the_rig_finds_a_building_view_provider_through_the_group_when_none_is_injected() -> void:
	var world := BuildingTestSupport.flat_world(FLAT_WORLD_M, 100.0, Rect2(), 10.0)
	var kit := BuildingTestSupport.kit()
	var view: BuildingView = auto_free(BuildingView.new())
	add_child(view)
	var cfg := BuildingViewConfig.new()
	cfg.use_threads = false
	view.setup(world, kit, cfg)
	var m := kit.module_index(BuildingTestSupport.MID_A)
	var report := view.set_columns(BuildingTestSupport.columns([{"m": m, "x": 1000.0, "z": 950.0, "parcel": 1}]), 1)
	assert_bool(report["ok"]).is_true()
	var rig: CameraRig = auto_free(CameraRig.new())
	rig.input_profile = DesktopInputProfile.new()
	rig.smoothing_enabled = false
	rig.viewport_size_override = CameraTestSupport.VIEWPORT
	add_child(rig)
	rig.set_world(null, _ground())
	var s := _street_state(60.0, 0.0)
	s.focus_x = 1000.0
	s.focus_z = 960.0 - 59.9
	rig.apply_state(s, true)
	rig._process(0.6)  # sağlayıcı araması (0,5 sn) ve bir ilerletme
	assert_object(rig.roof_clearance).is_same(view.roof_clearance())
	rig._process(0.1)
	var roof_top := view.roof_clearance().max_roof_y(1000.0, 950.0, 1.0)
	assert_float(roof_top).is_equal_approx(10.0 + kit.height_m[m], 0.01)
	assert_float(rig.camera.global_position.y).is_greater_equal(roof_top + _env.roof_margin_m - 0.001)


func test_the_roof_index_matches_a_brute_force_scan_over_rotated_footprints() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 62
	var entries: Array = []
	for i in 400:
		entries.append({"x": rng.randf_range(-200.0, 200.0), "z": rng.randf_range(-200.0, 200.0),
				"yaw": rng.randf_range(0.0, TAU), "hw": rng.randf_range(3.0, 14.0), "hd": rng.randf_range(3.0, 12.0),
				"top": rng.randf_range(5.0, 40.0)})
	var roofs := _roofs(entries)
	for q in 60:
		var x := rng.randf_range(-220.0, 220.0)
		var z := rng.randf_range(-220.0, 220.0)
		var expected := RoofClearance.NO_ROOF
		for e: Dictionary in entries:
			var d := Vector2(x - float(e["x"]), z - float(e["z"]))
			var yaw := float(e["yaw"])
			var lx := d.x * cos(yaw) - d.y * sin(yaw)
			var lz := d.x * sin(yaw) + d.y * cos(yaw)
			var o := Vector2(maxf(absf(lx) - float(e["hw"]), 0.0), maxf(absf(lz) - float(e["hd"]), 0.0))
			if o.length() <= 15.0 and float(e["top"]) > expected:
				expected = float(e["top"])
		assert_float(roofs.max_roof_y(x, z, 15.0)).is_equal_approx(expected, 0.001)


func test_the_same_columns_give_the_same_roof_heights_twice() -> void:
	var world := BuildingTestSupport.flat_world(FLAT_WORLD_M, 100.0, Rect2(), 10.0)
	var kit := BuildingTestSupport.kit()
	var cols := BuildingTestSupport.grid_columns(kit.module_index(BuildingTestSupport.MID_A), 8, 40.0, 500.0, 500.0)
	var a := RoofClearance.new()
	var b := RoofClearance.new()
	a.set_from_columns(world, cols, kit)
	b.set_from_columns(world, cols, kit)
	assert_int(a.count).is_equal(cols.count)
	for q in 20:
		var x := 480.0 + q * 17.0
		assert_float(a.max_roof_y(x, 560.0, 15.0)).is_equal(b.max_roof_y(x, 560.0, 15.0))
