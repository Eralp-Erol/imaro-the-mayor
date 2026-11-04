extends GdUnitTestSuite
## T-064 ölçüt 2, 3, 4, 5 · K1 kadraj kuralı: dört köşe ışını sınır - kenar payı içinde kalır (özellik testi),
## çözüm sırası eğim -> uzaklık -> odak, pan uzaklığı değiştirmez, zoom-out kenarda durur, rotate kenarda eğimi
## yükseltir, üç girdi yolu (tekerlek, trackpad pinch, dokunmatik pinch) aynı zarfa çarpar, yumuşatılmış ara pozlar da
## K1'li. Olumsuz kontroller: K1 kapalı (legacy) zarfta aynı durumlar dünya kenarını kadraja sokar (test duyarlı).

const VIEWPORT := Vector2(1600.0, 900.0)
const ASPECTS: Array[float] = [16.0 / 9.0, 4.0 / 3.0, 21.0 / 9.0]
const SEED_COUNT := 10000
const CENTER_SEEDS := 1500

var _env: CameraEnvelope
var _legacy: CameraEnvelope
var _bounds: Rect2 = Rect2(0.0, 0.0, 40000.0, 40000.0)
var _world: WorldData


func before() -> void:
	_env = CameraEnvelope.load_default()
	_legacy = CameraEnvelope.legacy()
	_world = WorldTestSupport.coarse(WorldTestSupport.control())


func _flat(_x: float, _z: float) -> float:
	return 0.0


func _state(x: float, z: float, distance: float, pitch: float, heading: float) -> CameraState:
	var s := CameraState.new()
	s.focus_x = x
	s.focus_z = z
	s.distance = distance
	s.pitch_deg = pitch
	s.heading_deg = heading
	return s


func _rig(profile: InputProfile) -> CameraRig:
	var rig: CameraRig = auto_free(CameraRig.new())
	rig.input_profile = profile
	rig.viewport_size_override = VIEWPORT
	rig.smoothing_enabled = false
	add_child(rig)
	rig.set_world(_world, func(x: float, z: float) -> float: return maxf(_world.height_at(x, z), _world.sea_level))
	return rig


func _inside(rig: CameraRig, s: CameraState) -> bool:
	return rig.envelope.footprint_ok(s, VIEWPORT.x / VIEWPORT.y, rig.ground_height, _world.bounds(), _world.sea_level)


## Doğu kenar payı sınırından `inset_m` içeride, güney-orta odak.
func _edge_state(rig: CameraRig, inset_m: float, distance: float, pitch: float, heading: float) -> CameraState:
	var inner := rig.envelope.inner_rect(_world.bounds())
	return _state(inner.end.x - inset_m, inner.get_center().y, distance, pitch, heading)


# --- Ölçüt 2: özellik testi ---

func test_k1_property_four_corners_stay_inside_bounds_minus_margin_for_three_aspects_and_10k_seeds() -> void:
	var inner := _env.inner_rect(_bounds)
	var rng := RandomNumberGenerator.new()
	rng.seed = 6401
	var changed := 0
	for i in SEED_COUNT:
		var aspect: float = ASPECTS[i % ASPECTS.size()]
		var d := exp(rng.randf_range(log(_env.k1_min_distance_m), log(_env.d_max_m)))
		var s := _state(rng.randf_range(-2000.0, 42000.0), rng.randf_range(-2000.0, 42000.0), d,
				rng.randf_range(0.0, 90.0), rng.randf_range(0.0, 360.0))
		var out := _env.resolve(s, aspect, Callable(), _bounds)
		assert_bool(out.is_valid()).is_true()
		assert_bool(_env.footprint_ok(out, aspect, Callable(), _bounds)) \
				.override_failure_message("K1 ihlali tohum %d aspect %.2f: d=%.0f p=%.1f" % [i, aspect, d, out.pitch_deg]).is_true()
		var pts := _env.footprint_points(out, aspect, Callable())
		for p in pts:
			assert_bool(inner.has_point(p)).is_true()
		assert_float(out.distance).is_between(_env.d_min_m, _env.d_max_m)
		assert_float(out.pitch_deg).is_between(_env.pitch_min_deg(out.distance) - 1.0e-9, _env.pitch_max_deg + 1.0e-9)
		assert_bool(inner.has_point(Vector2(out.focus_x, out.focus_z))).is_true()
		if not out.is_close_to(s, 0.001, 0.001):
			changed += 1
	assert_int(changed).is_greater(SEED_COUNT / 4)  # kural gerçekten çalışıyor (girdilerin çoğu zaten geçerli değil)


func test_k1_property_also_holds_over_hilly_ground_where_the_eye_clearance_is_active() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 6402
	var inner := _env.inner_rect(_bounds)
	for i in CENTER_SEEDS:
		var aspect: float = ASPECTS[i % ASPECTS.size()]
		var d := exp(rng.randf_range(log(_env.k1_min_distance_m), log(_env.d_max_m)))
		var s := _state(rng.randf_range(0.0, 40000.0), rng.randf_range(0.0, 40000.0), d, rng.randf_range(10.0, 90.0),
				rng.randf_range(0.0, 360.0))
		var out := _env.resolve(s, aspect, CameraTestSupport.hills, _bounds)
		assert_bool(_env.footprint_ok(out, aspect, CameraTestSupport.hills, _bounds)).is_true()
		assert_bool(inner.has_point(Vector2(out.focus_x, out.focus_z))).is_true()


func test_resolve_is_deterministic_same_input_gives_bit_identical_output() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 6403
	for i in 300:
		var s := _state(rng.randf_range(0.0, 40000.0), rng.randf_range(0.0, 40000.0),
				exp(rng.randf_range(log(60.0), log(40000.0))), rng.randf_range(0.0, 90.0), rng.randf_range(0.0, 360.0))
		var aspect: float = ASPECTS[i % ASPECTS.size()]
		var mode: StringName = CameraEnvelope.MODE_PAN if i % 2 == 0 else CameraEnvelope.MODE_DEFAULT
		var a := _env.resolve(s, aspect, CameraTestSupport.hills, _bounds, mode)
		var b := _env.resolve(s.copy(), aspect, CameraTestSupport.hills, _bounds, mode)
		assert_dict(a.to_dict()).is_equal(b.to_dict())
		# Çözülmüş durum sabit noktadır (idempotent): ikinci çözüm değiştirmez.
		var c := _env.resolve(a, aspect, CameraTestSupport.hills, _bounds, mode)
		assert_dict(a.to_dict()).is_equal(c.to_dict())


func test_a_90km_8deg_request_is_clamped_to_the_envelope_negative() -> void:
	var s := _state(20000.0, 20000.0, 90000.0, 8.0, 0.0)
	var out := _env.resolve(s, CameraEnvelope.DEFAULT_ASPECT, Callable(), _bounds)
	assert_float(out.distance).is_equal_approx(_env.d_max_m, 0.001)
	assert_float(out.pitch_deg).is_greater_equal(_env.pitch_min_deg(_env.d_max_m))
	assert_bool(_env.footprint_ok(out, CameraEnvelope.DEFAULT_ASPECT, Callable(), _bounds)).is_true()
	var near := _env.resolve(_state(20000.0, 20000.0, 1.0, 1.0, 0.0), CameraEnvelope.DEFAULT_ASPECT, Callable(), _bounds)
	assert_float(near.distance).is_equal(_env.d_min_m)
	assert_float(near.pitch_deg).is_equal(_env.pitch_min_deg(_env.d_min_m))
	# Legacy zarf aynı isteği kenetlemez (K1 yok): test iki zarfı ayırt eder.
	var old := _legacy.resolve(s, CameraEnvelope.DEFAULT_ASPECT, Callable(), _bounds)
	assert_float(old.distance).is_equal(90000.0)


func test_an_unsolvable_edge_anchor_at_the_ceiling_falls_through_to_the_distance_step() -> void:
	# Dünyanın kenar bölgesi çapası (veriden: çapası merkeze en uzak bölge), d_max: eğim tek başına çözemez.
	var center := _world.origin + _world.size * 0.5
	var far_region: WorldRegion = _world.regions[0]
	for r in _world.regions:
		if (r.anchor - center).length() > (far_region.anchor - center).length():
			far_region = r
	var s := _state(far_region.anchor.x, far_region.anchor.y, _env.d_max_m, 40.0, 0.0)
	var wide := CameraEnvelope.DEFAULT_ASPECT
	assert_float(_env.required_pitch(s, wide, Callable(), _world.bounds())).is_less(0.0)  # eğim adımı çözümsüz
	var out := _env.resolve(s, wide, Callable(), _world.bounds())
	assert_bool(_env.footprint_ok(out, wide, Callable(), _world.bounds())).is_true()
	assert_float(out.distance).is_less(_env.d_max_m)  # uzaklık adımı devrede
	assert_float(out.distance).is_greater_equal(_env.k1_min_distance_m)
	assert_float(Vector2(out.focus_x, out.focus_z).distance_to(far_region.anchor)).is_less(0.01)  # odak yerinde kaldı
	# Pan modunda aynı durumda uzaklık değişmez: odak merkeze kayar.
	var panned := _env.resolve(s, wide, Callable(), _world.bounds(), CameraEnvelope.MODE_PAN)
	assert_float(panned.distance).is_equal(s.distance)
	assert_bool(_env.footprint_ok(panned, wide, Callable(), _world.bounds())).is_true()
	assert_float(Vector2(panned.focus_x, panned.focus_z).distance_to(center)).is_less(
			Vector2(s.focus_x, s.focus_z).distance_to(center))


func test_the_four_world_edges_never_enter_the_frame_from_any_edge_focus_and_heading() -> void:
	var inner := _env.inner_rect(_bounds)
	var stops := [0.0, 0.25, 0.5, 0.75, 1.0]
	var checked := 0
	for edge in 4:
		for t in stops:
			var f := Vector2.ZERO
			match edge:
				0: f = Vector2(inner.position.x, inner.position.y + inner.size.y * t)
				1: f = Vector2(inner.end.x, inner.position.y + inner.size.y * t)
				2: f = Vector2(inner.position.x + inner.size.x * t, inner.position.y)
				_: f = Vector2(inner.position.x + inner.size.x * t, inner.end.y)
			for heading in range(0, 360, 45):
				for d in [_env.k1_min_distance_m, 2500.0, 4000.0, 18000.0]:
					for aspect in ASPECTS:
						var out := _env.resolve(_state(f.x, f.y, d, 25.0, float(heading)), aspect, Callable(), _bounds)
						for p in _env.footprint_points(out, aspect, Callable()):
							assert_bool(_bounds.has_point(p)).is_true()  # dünya kutusunun DIŞINA bakış yok
							assert_bool(inner.has_point(p)).is_true()
						checked += 1
	assert_int(checked).is_equal(4 * 5 * 8 * 4 * 3)
	# Olumsuz kontrol: legacy zarfta (K1 yok) aynı durumların bir kısmı kutunun dışına bakar.
	var outside := 0
	for heading in range(0, 360, 45):
		var raw := _state(inner.end.x, inner.get_center().y, 18000.0, 40.0, float(heading))
		var old := _legacy.resolve(raw, CameraEnvelope.DEFAULT_ASPECT, Callable(), _bounds)
		for p in _legacy.footprint_points(old, CameraEnvelope.DEFAULT_ASPECT, Callable()):
			if not is_finite(p.x) or not _bounds.has_point(p):
				outside += 1
	assert_int(outside).is_greater(0)


func test_the_street_band_clamps_only_the_focus_and_leaves_pitch_and_distance_alone() -> void:
	var s := _state(-500.0, 45000.0, 200.0, 21.0, 70.0)
	var out := _env.resolve(s, CameraEnvelope.DEFAULT_ASPECT, Callable(), _bounds)
	var inner := _env.inner_rect(_bounds)
	assert_float(out.distance).is_equal(200.0)
	assert_float(out.pitch_deg).is_equal(21.0)
	assert_float(out.focus_x).is_equal(inner.position.x)
	assert_float(out.focus_z).is_equal(inner.end.y)


func test_street_and_neighborhood_allow_a_near_horizontal_pitch_at_the_edge_but_k1_takes_over_at_its_entry() -> void:
	var inner := _env.inner_rect(_bounds)
	var floor_deg := _env.pitch_min_deg(_env.d_min_m)
	assert_float(floor_deg).is_less_equal(3.5)  # ~3 derece erişilebilir
	for d in [60.0, 300.0, 600.0]:
		for aspect in ASPECTS:
			# Doğu kenar payı sınırında odak, doğuya bakış, en alçak eğim: K1 DEVREDE DEĞİL (ufuk görünür, kenar pusu).
			var s := _state(inner.end.x, inner.get_center().y, d, 0.0, 90.0)
			var out := _env.resolve(s, aspect, Callable(), _bounds)
			assert_float(out.pitch_deg).is_equal_approx(floor_deg, 0.0001)
			assert_float(out.distance).is_equal(d)
			assert_float(out.focus_x).is_equal(inner.end.x)
	# Olumsuz (duyarlılık): K1 girişinde ve üstünde aynı kadraj ufku/dünya kenarını kadraja sokamaz.
	for d in [_env.k1_min_distance_m, 3000.0, 9000.0]:
		for aspect in ASPECTS:
			var s := _state(inner.end.x, inner.get_center().y, d, 0.0, 90.0)
			var out := _env.resolve(s, aspect, Callable(), _bounds)
			assert_bool(_env.footprint_ok(out, aspect, Callable(), _bounds)).is_true()
			assert_float(out.pitch_deg).is_greater(_env.pitch_min_deg(_env.d_min_m) + 15.0)
			for p in _env.footprint_points(out, aspect, Callable()):
				assert_bool(inner.has_point(p)).is_true()


# --- Ölçüt 3: pan, zoom-out, rotate, üç girdi yolu ---

func test_pan_toward_the_edge_never_changes_the_distance_and_the_focus_stops() -> void:
	var rig := _rig(DesktopInputProfile.new())
	rig.apply_preset("district:%s" % _world.regions[0].code)
	var d0 := rig.target_state().distance
	var inner := rig.envelope.inner_rect(_world.bounds())
	var pitch0 := rig.target_state().pitch_deg
	for i in 80:
		rig.on_pan(Vector2(-300.0, 0.0))  # içerik sola kayar = odak doğuya
		assert_float(rig.target_state().distance).is_equal(d0)  # pan uzaklığı DEĞİŞTİRMEZ
		assert_bool(_inside(rig, rig.target_state())).is_true()
	var s := rig.target_state()
	assert_float(s.focus_x).is_less_equal(inner.end.x + 0.001)  # odak durur
	assert_float(s.pitch_deg).is_greater(pitch0 - 0.001)  # eğim yükselerek K1'i korudu (ya da zaten yeterliydi)
	# Klavye (held) pan'ı da aynı kural: doğuya basılı tut.
	var key := InputEventKey.new()
	key.physical_keycode = KEY_D
	key.keycode = KEY_D
	key.pressed = true
	rig._unhandled_input(key)
	for i in 60:
		rig._process(0.1)
		assert_float(rig.target_state().distance).is_equal(d0)
		assert_bool(_inside(rig, rig.target_state())).is_true()
	assert_float(rig.target_state().focus_x).is_less_equal(inner.end.x + 0.001)


func test_pan_pitch_rises_toward_the_edge_and_a_pure_pitch_free_pan_would_break_k1_so_the_test_is_sensitive() -> void:
	var rig := _rig(DesktopInputProfile.new())
	rig.apply_state(_state(30000.0, 20000.0, 9000.0, 30.0, 90.0), true)  # doğuya bakıyor, kenara yakın
	var s0 := rig.target_state()
	assert_bool(_inside(rig, s0)).is_true()
	for i in 40:
		rig.on_pan(Vector2(-250.0, 0.0))
	var s1 := rig.target_state()
	assert_float(s1.pitch_deg).is_greater(s0.pitch_deg + 5.0)  # kenara doğru gidince eğim yükseldi
	assert_float(s1.distance).is_equal(s0.distance)
	# Olumsuz: aynı odak, ESKİ eğimle K1'i bozardı.
	var naive := s1.copy()
	naive.pitch_deg = s0.pitch_deg
	assert_bool(_inside(rig, naive)).is_false()


func test_zoom_out_at_the_edge_stops_before_the_ceiling_and_stays_k1() -> void:
	var rig := _rig(DesktopInputProfile.new())
	rig.apply_state(_edge_state(rig, 3000.0, 1500.0, 30.0, 90.0), true)
	var last := rig.target_state().distance
	var start_d := last
	var unchanged := 0
	for i in 120:
		rig.on_zoom(1.0 / 1.1, VIEWPORT * 0.5)
		var d := rig.target_state().distance
		assert_float(d).is_less_equal(rig.envelope.d_max_m + 0.001)
		assert_bool(_inside(rig, rig.target_state())).is_true()
		unchanged = unchanged + 1 if absf(d - last) < 1.0 else 0
		last = d
	assert_int(unchanged).is_greater(10)  # kenarda zoom-out DURDU
	assert_float(last).is_greater(start_d)  # ilerleyebildiği kadar uzaklaştı
	assert_float(last).is_less(rig.envelope.d_max_m * 0.5)  # tavana değil K1'e takıldı
	# Olumsuz: merkezde aynı zoom-out tavana kadar gider (kenar etkisi gerçek).
	var mid := _rig(DesktopInputProfile.new())
	mid.apply_preset("district:%s" % _world.regions[0].code)
	for i in 120:
		mid.on_zoom(1.0 / 1.1, VIEWPORT * 0.5)
	assert_float(mid.target_state().distance).is_greater(last)


func test_rotate_at_the_edge_raises_the_pitch_when_the_view_turns_outward() -> void:
	var rig := _rig(DesktopInputProfile.new())
	var inward := _edge_state(rig, 3000.0, 2500.0, 30.0, 270.0)  # batıya (içe) bakıyor
	rig.apply_state(inward, true)
	var p_in := rig.target_state().pitch_deg
	assert_bool(_inside(rig, rig.target_state())).is_true()
	rig.on_rotate(PI, VIEWPORT * 0.5)  # yön ~tersine: doğuya (dışa) bakar
	var s := rig.target_state()
	assert_bool(_inside(rig, s)).is_true()
	assert_float(s.distance).is_equal_approx(2500.0, 0.001)  # döndürme uzaklığı değiştirmez; eğim yükselir
	assert_float(s.pitch_deg).is_greater(p_in + 3.0)  # kenarda döndürünce eğim yükselir


func test_wheel_trackpad_pinch_and_touch_pinch_hit_the_same_envelope() -> void:
	var finals: Array[float] = []
	for path in ["wheel", "magnify", "touch"]:
		var profile: InputProfile = TouchInputProfile.new() if path == "touch" else DesktopInputProfile.new()
		var rig := _rig(profile)
		rig.apply_state(_edge_state(rig, 3000.0, 1200.0, 30.0, 90.0), true)
		var d_start := rig.target_state().distance
		for i in 150:
			match path:
				"wheel":
					var e := InputEventMouseButton.new()
					e.button_index = MOUSE_BUTTON_WHEEL_DOWN  # uzaklaş
					e.pressed = true
					e.position = VIEWPORT * 0.5
					rig._unhandled_input(e)
				"magnify":
					var g := InputEventMagnifyGesture.new()
					g.position = VIEWPORT * 0.5
					g.factor = 0.85
					rig._unhandled_input(g)
				"touch":
					rig._unhandled_input(_touch(0, true, Vector2(700.0, 450.0)))
					rig._unhandled_input(_touch(1, true, Vector2(900.0, 450.0)))
					rig._unhandled_input(_drag(1, Vector2(850.0, 450.0), Vector2(-50.0, 0.0)))  # kıstır = uzaklaş
					rig._unhandled_input(_touch(1, false, Vector2(850.0, 450.0)))
					rig._unhandled_input(_touch(0, false, Vector2(700.0, 450.0)))
		var d := rig.target_state().distance
		assert_float(d).override_failure_message("%s: tavan aşıldı" % path).is_less_equal(rig.envelope.d_max_m + 0.001)
		assert_float(d).override_failure_message("%s: hiç uzaklaşmadı" % path).is_greater(d_start)
		assert_bool(_inside(rig, rig.target_state())).override_failure_message(path).is_true()
		finals.append(d)
	# Tekerlek ve trackpad pinch aynı anchor'la AYNI K1 sınırına yaslanır. Dokunmatik kıstırma ayrıca merkez kaymasını pan
	# olarak sürer (parmak ortası hareket eder) -> odak kayar, sınır farklıdır; ama o da zarfı ve K1'i aşmaz.
	assert_float(finals[0] / finals[1]).override_failure_message("yol sonuçları %s" % str(finals)).is_between(0.99, 1.01)
	for d in finals:
		assert_float(d).is_less(_env.d_max_m * 0.6)  # üçü de tavanın çok altında durdu (K1 kenar sınırı)


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


# --- Ölçüt 4: yumuşatılmış ara pozlar ---

func _smooth_transition(rig: CameraRig, goal: CameraState) -> Dictionary:
	## Hedefe yumuşatma uçuşu: kare kare K1 ihlali (rig) ve ham (zarfsız) yolun ihlali sayılır.
	var raw := rig.current_state()
	rig.apply_state(goal, false)
	var goal_resolved := rig.target_state()
	var rig_violations := 0
	var raw_violations := 0
	for f in 240:
		rig._smooth(1.0 / 60.0)
		if not _inside(rig, rig.current_state()):
			rig_violations += 1
		var cur := rig.current_state()
		assert_float(cur.distance).is_between(rig.envelope.d_min_m, rig.envelope.d_max_m + 0.001)
		raw.approach(goal_resolved, 1.0 - exp(-rig.smoothing_rate / 60.0))
		if not _inside(rig, raw):
			raw_violations += 1
	assert_bool(rig.current_state().is_close_to(rig.target_state(), 1.0, 0.2)).is_true()  # varış hedefte
	return {"rig": rig_violations, "raw": raw_violations}


func test_smoothed_intermediate_poses_are_k1_frame_by_frame_district_to_district_and_ceiling_to_edge() -> void:
	var rig := _rig(DesktopInputProfile.new())
	rig.smoothing_enabled = true
	var first: StringName = _world.regions[0].code
	var last: StringName = _world.regions[_world.regions.size() - 1].code
	# 1) İlk ilçe -> son ilçe (veri: D1 -> D5).
	rig.apply_preset("district:%s" % first)
	var goal: CameraState = CameraPresets.resolve("district:%s" % last, _world, rig.ground_height, rig.envelope)["state"]
	var d1_d5 := _smooth_transition(rig, goal)
	assert_int(d1_d5["rig"]).override_failure_message("ilçe geçişinde K1 dışı kare").is_equal(0)
	# 2) Tavandan (merkez, d_max) doğu kenarına yakın, yakın bir kadraja: ham doğrusal ara pozlar K1'i bozar, rig bozmaz.
	rig.apply_preset("core")
	var edge := _edge_state(rig, 2000.0, 4000.0, 35.0, 90.0)
	var core_edge := _smooth_transition(rig, edge)
	assert_int(core_edge["rig"]).override_failure_message("tavan->kenar geçişinde K1 dışı kare").is_equal(0)
	assert_int(d1_d5["raw"] + core_edge["raw"]) \
			.override_failure_message("ham ara pozlar hiç K1'i bozmadı: test duyarsız").is_greater(0)


# --- Home ---

func test_home_key_returns_to_the_start_view_and_without_a_start_district_it_is_core() -> void:
	var rig := _rig(DesktopInputProfile.new())
	var code: StringName = _world.regions[1].code
	rig.home_district = code
	rig.apply_preset("street:port")
	var key := InputEventKey.new()
	key.physical_keycode = KEY_HOME
	key.keycode = KEY_HOME
	key.pressed = true
	rig._unhandled_input(key)
	assert_str(String(rig.preset_name)).is_equal("district")
	assert_float(rig.focus_xz().distance_to(_world.region_by_code(code).anchor)).is_less(1.0)
	rig.home_district = &""
	rig.apply_preset("street:port")
	rig._unhandled_input(key)
	assert_str(String(rig.preset_name)).is_equal("core")
	assert_float(rig.target_state().distance).is_equal_approx(rig.envelope.d_max_m, 0.01)
	# Dokunmatik profilde de aynı eylem (HUD düğmesi / harici klavye).
	var touch_rig := _rig(TouchInputProfile.new())
	touch_rig.apply_preset("street:port")
	touch_rig.input_profile.camera_home_requested.emit()
	assert_str(String(touch_rig.preset_name)).is_equal("core")


func test_scale_band_signal_fires_once_per_real_crossing_and_never_for_a_5_percent_wobble() -> void:
	var rig := _rig(DesktopInputProfile.new())
	rig.apply_preset("district:%s" % _world.regions[0].code)
	var events: Array[StringName] = []
	rig.scale_band_changed.connect(func(b: StringName) -> void: events.append(b))
	var base := rig.target_state()
	for d in [1600.0, 1500.0 * 0.95, 1500.0 * 1.05, 1500.0 * 0.96, 1500.0 * 1.04]:
		var s := base.copy()
		s.distance = d
		rig.apply_state(s, true)
	assert_int(events.size()).is_less_equal(1)  # sınırda ±%5 salınım: en çok ilk giriş olayı
	events.clear()
	var s2 := base.copy()
	s2.distance = 400.0
	rig.apply_state(s2, true)
	assert_int(events.size()).is_equal(1)  # gerçek geçiş: tek olay
	assert_str(String(events[0])).is_equal("neighborhood")
	assert_str(String(rig.scale_band)).is_equal("neighborhood")
