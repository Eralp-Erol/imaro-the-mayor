extends GdUnitTestSuite
## Açılış ısınması (ViewWarmup): saf poz planı, atlama kararı ve rig ile gerçek akış (kamera dar bantları gezer, sonra
## BİREBİR geri yüklenir; girdi geri açılır; bitişte `finished`). Dummy renderer: çizim maliyeti ölçülmez (pencereli
## ölçüm: production/log/2026-10-29-demo-kare-suresi.md ve onu izleyen rapor); burada yalnız ısınma yolunun çağrıldığı
## ve durumu bozmadığı doğrulanır.

const PlayableScript := preload("res://src/game/playable.gd")

var _world: WorldData


func before() -> void:
	_world = WorldTestSupport.coarse(WorldTestSupport.control())


func _ground() -> Callable:
	return func(x: float, z: float) -> float: return maxf(_world.height_at(x, z), _world.sea_level)


func _rig() -> CameraRig:
	var rig: CameraRig = auto_free(CameraRig.new())
	rig.input_profile = DesktopInputProfile.new()
	rig.smoothing_enabled = false
	var root: Node3D = auto_free(Node3D.new())
	add_child(root)
	rig.view_root = root
	add_child(rig)
	rig.set_world(_world, _ground())
	rig.apply_preset("core")
	return rig


func _start() -> CameraState:
	return CameraPresets.core(_world, CameraEnvelope.load_default())


# --- Saf plan ---

func test_plan_starts_at_start_and_covers_every_narrow_band_near_to_far() -> void:
	var env := CameraEnvelope.load_default()
	var start := _start()
	var poses := ViewWarmup.plan(env, start)
	assert_int(poses.size()).is_equal(env.bands.size())  # başlangıç + metro dışı her bant
	assert_float(poses[0].distance).is_equal(start.distance)
	var bands: Array[StringName] = []
	for i in range(1, poses.size()):
		bands.append(env.band_of(poses[i].distance))
		assert_float(poses[i].focus_x).is_equal(start.focus_x)  # aynı dünya noktası
		assert_float(poses[i].focus_z).is_equal(start.focus_z)
		assert_float(poses[i].heading_deg).is_equal(start.heading_deg)
	assert_array(bands).is_equal([&"street", &"neighborhood", &"district"])
	assert_bool(poses[1].distance < poses[2].distance and poses[2].distance < poses[3].distance).is_true()


func test_plan_street_pose_is_just_above_the_envelope_minimum() -> void:
	var env := CameraEnvelope.load_default()
	var poses := ViewWarmup.plan(env, _start())
	assert_float(poses[1].distance).is_equal_approx(env.d_min_m * ViewWarmup.STREET_FACTOR, 0.001)
	assert_float(poses[1].distance).is_greater(env.d_min_m)


func test_plan_does_not_mutate_the_start_state() -> void:
	var start := _start()
	var before_distance := start.distance
	ViewWarmup.plan(CameraEnvelope.load_default(), start)
	assert_float(start.distance).is_equal(before_distance)


func test_plan_without_bands_is_only_the_start() -> void:
	var env := CameraEnvelope.new()
	assert_int(ViewWarmup.plan(env, _start()).size()).is_equal(1)
	assert_int(ViewWarmup.plan(null, _start()).size()).is_equal(1)


# --- Atlama kararı (playable) ---

func test_warmup_runs_on_the_player_path_and_is_skipped_for_headless_and_dev_args() -> void:
	assert_bool(PlayableScript.warmup_enabled({"demo": true}, false)).is_true()
	assert_bool(PlayableScript.warmup_enabled({}, false)).is_true()
	assert_bool(PlayableScript.warmup_enabled({"demo": true}, true)).is_false()  # başsız: çizim yok
	for key in PlayableScript.WARMUP_SKIP_ARGS:
		assert_bool(PlayableScript.warmup_enabled({"demo": true, key: true}, false)).override_failure_message(
				"--%s ısınmayı atlamalı" % key).is_false()


# --- Rig ile gerçek akış ---

func test_warmup_visits_the_narrow_bands_then_restores_the_exact_pose() -> void:
	var rig := _rig()
	rig.on_pan(Vector2(40.0, -25.0))  # başlangıç "ham" preset olmasın
	var before_target := rig.target_state()
	var before_current := rig.current_state()
	var before_desired := rig.desired_pitch_deg()
	var bands: Array[StringName] = []
	rig.scale_band_changed.connect(func(b: StringName) -> void: bands.append(b))
	var warm: ViewWarmup = auto_free(ViewWarmup.new())
	add_child(warm)
	var done := [false]
	var seen := {}  # `finished` sonrası düğüm kendini siler: sayaçlar sinyal anında okunur
	warm.finished.connect(func() -> void:
		done[0] = true
		seen["poses"] = warm.poses_done
		seen["frames"] = warm.frames_held_total
		seen["active"] = warm.is_active())
	warm.begin(rig)
	assert_bool(warm.is_active()).is_true()
	assert_bool(rig.is_processing_unhandled_input()).is_false()  # örtü sürerken kamera girdisi kapalı
	var guard := 0
	while not done[0] and guard < 200:
		await get_tree().process_frame
		guard += 1
	assert_bool(done[0]).is_true()
	assert_bool(bool(seen["active"])).is_false()
	# dar bantların hepsi görüldü (street, neighborhood, district), sonunda başlangıç bandına dönüldü
	for b in [&"street", &"neighborhood", &"district"]:
		assert_bool(bands.has(b)).override_failure_message("ısınma %s bandını gezmedi" % b).is_true()
	assert_int(int(seen["poses"])).is_equal(4)
	assert_int(int(seen["frames"])).is_greater_equal(4 * ViewWarmup.HOLD_FRAMES)
	assert_bool(rig.is_processing_unhandled_input()).is_true()
	# poz BİREBİR geri döndü (oyuncu başlangıcı değişmedi)
	var after_target := rig.target_state()
	var after_current := rig.current_state()
	assert_bool(after_target.is_close_to(before_target, 0.0001, 0.0001)).is_true()
	assert_bool(after_current.is_close_to(before_current, 0.0001, 0.0001)).is_true()
	assert_float(rig.desired_pitch_deg()).is_equal(before_desired)
	assert_float(rig.distance()).is_equal_approx(before_current.distance, 0.0001)


func test_warmup_waits_for_busy_work_but_never_longer_than_the_cap() -> void:
	var rig := _rig()
	var warm: ViewWarmup = auto_free(ViewWarmup.new())
	add_child(warm)
	var done := [false]
	var seen := {}
	warm.finished.connect(func() -> void:
		done[0] = true
		seen["frames"] = warm.frames_held_total)
	warm.begin(rig, func() -> bool: return true)  # iş hiç bitmiyor
	var guard := 0
	while not done[0] and guard < 400:
		await get_tree().process_frame
		guard += 1
	assert_bool(done[0]).is_true()  # sınır sonsuz beklemeyi engeller
	assert_int(int(seen["frames"])).is_equal(4 * ViewWarmup.MAX_HOLD_FRAMES)  # tavana kadar bekledi, fazlasını değil


func test_rig_pose_snapshot_round_trips_without_touching_the_preset_name() -> void:
	var rig := _rig()
	var snap := rig.pose_snapshot()
	var name_before := rig.preset_name
	rig.apply_preset("street:20200,18700")
	assert_float(rig.distance()).is_less(500.0)
	rig.restore_pose(snap)
	assert_float(rig.distance()).is_equal_approx((snap["current"] as CameraState).distance, 0.0001)
	assert_float(rig.desired_pitch_deg()).is_equal(float(snap["desired_pitch"]))
	assert_that(name_before).is_equal(&"core")
