extends GdUnitTestSuite
## T-003 ölçüt 4, 6 · T-064 ölçüt 6-7 · Kamera preset'leri VERİDEN türer: core / district(kod) / street(nokta) /
## start_view + T-001 preset'leri (legacy zarfta değişmeden). `metro` emekli (açık hata); `metro_legacy_bench` yalnız
## legacy zarfta ve eski durumu birebir verir. Koordinat gömülü olsaydı veri değişince (ve fixture'da) testler kırılır.

var _world: WorldData
var _fixture: WorldData
var _legacy: CameraEnvelope


func before() -> void:
	_world = WorldTestSupport.coarse(WorldTestSupport.control())
	_fixture = WorldFixture.build()
	_legacy = CameraEnvelope.legacy()


func _ground(w: WorldData) -> Callable:
	return func(x: float, z: float) -> float: return maxf(w.height_at(x, z), w.sea_level)


func _k1_ok(env: CameraEnvelope, s: CameraState) -> bool:
	return env.footprint_ok(s, CameraEnvelope.DEFAULT_ASPECT, _ground(_world), _world.bounds(), _world.sea_level)


# --- core / metro (emekli) / metro_legacy_bench ---

func test_core_preset_is_the_world_center_at_the_envelope_ceiling_with_k1_pitch_and_scales_with_the_world() -> void:
	var env := CameraEnvelope.load_default()
	var r := CameraPresets.resolve("core", _world, _ground(_world))
	assert_bool(r["ok"]).is_true()
	var s: CameraState = r["state"]
	var center := _world.origin + _world.size * 0.5
	assert_float(Vector2(s.focus_x, s.focus_z).distance_to(center)).is_less(0.01)
	assert_float(s.distance).is_equal(env.d_max_m)
	assert_bool(_k1_ok(env, s)).is_true()
	assert_float(s.pitch_deg).is_greater_equal(env.pitch_min_deg(env.d_max_m))
	# Küçük fixture dünyasında K1 d_max'ta kenarı kadraja sokar -> çözümleyici uzaklığı/odağı değiştirir (dünyaya bağlı).
	var f: CameraState = CameraPresets.resolve("core", _fixture)["state"]
	assert_bool(env.footprint_ok(f, CameraEnvelope.DEFAULT_ASPECT, Callable(), _fixture.bounds())).is_true()
	assert_float(f.distance).is_less(s.distance)


func test_metro_is_retired_with_an_explicit_error_and_never_aliased() -> void:
	for spec in ["metro", "METRO", "metro:x"]:
		var r := CameraPresets.resolve(spec, _world)
		assert_bool(r["ok"]).is_false()
		assert_str(String(r["error"])).contains("metro kaldırıldı")
		assert_str(String(r["error"])).contains("core")
		assert_str(String(r["error"])).contains("metro_legacy_bench")
		assert_str(String(r["name"])).is_equal("core")  # sessiz takma ad yok: yedek core ve ok=false
	# Legacy zarfta da `metro` emekli (anlamı sessizce değişmez).
	assert_bool(CameraPresets.resolve("metro", _world, Callable(), _legacy)["ok"]).is_false()


func test_metro_legacy_bench_reproduces_the_old_metro_exactly_and_only_under_the_legacy_envelope() -> void:
	var r := CameraPresets.resolve("metro_legacy_bench", _world, _ground(_world), _legacy)
	assert_bool(r["ok"]).is_true()
	var s: CameraState = r["state"]
	var center := _world.origin + _world.size * 0.5
	assert_float(s.distance).is_equal_approx(_world.size.x * 1.45, 0.001)  # eski 58 km (40 km x 1,45)
	assert_float(s.pitch_deg).is_equal(50.0)
	assert_float(s.heading_deg).is_equal(0.0)
	assert_float(s.focus_x).is_equal_approx(center.x, 0.001)
	assert_float(s.focus_z).is_equal_approx(center.y + _world.size.y * 0.06, 0.001)
	assert_bool(r["adjusted"]).is_false()  # legacy zarf eski durumu değiştirmez
	# Olumsuz: oyuncu zarfında (bayraksız) açık hata ve 58 km'ye ulaşılamaz.
	var denied := CameraPresets.resolve("metro_legacy_bench", _world, _ground(_world))
	assert_bool(denied["ok"]).is_false()
	assert_str(String(denied["error"])).contains("--envelope=legacy")
	assert_float((denied["state"] as CameraState).distance).is_less_equal(CameraEnvelope.load_default().d_max_m)


func test_key_order_starts_with_core_and_the_five_keys_are_stable() -> void:
	assert_str(String(CameraPresets.KEY_ORDER[0])).is_equal("core")
	assert_int(CameraPresets.KEY_ORDER.size()).is_equal(5)
	assert_bool(CameraPresets.KEY_ORDER.has(&"metro")).is_false()
	assert_str(String(CameraPresets.FALLBACK)).is_equal("core")


# --- start_view ---

func test_start_view_is_the_district_view_for_a_given_code_and_core_when_the_value_is_missing_or_unknown() -> void:
	var code: StringName = _world.regions[0].code  # kodda ilçe kimliği yok: veriden
	var r := CameraPresets.start_view(_world, code, _ground(_world))
	assert_bool(r["ok"]).is_true()
	assert_str(String(r["name"])).is_equal("district")
	var d := CameraPresets.resolve("district:%s" % code, _world, _ground(_world))["state"] as CameraState
	assert_bool((r["state"] as CameraState).is_close_to(d, 0.001)).is_true()
	assert_float(Vector2(r["state"].focus_x, r["state"].focus_z).distance_to(_world.regions[0].anchor)).is_less(1.0)
	for none in [&"", &"  ", &"ZZ9"]:
		var fallback := CameraPresets.start_view(_world, none, _ground(_world))
		assert_bool(fallback["ok"]).is_true()
		assert_str(String(fallback["name"])).is_equal("core")


func test_start_view_follows_the_fixtures_own_codes_and_honours_the_envelope() -> void:
	var env := CameraEnvelope.load_default()
	var code: StringName = _fixture.regions[0].code
	var r := CameraPresets.start_view(_fixture, code, Callable(), env)
	assert_bool(r["ok"]).is_true()
	var s: CameraState = r["state"]
	assert_bool(env.footprint_ok(s, CameraEnvelope.DEFAULT_ASPECT, Callable(), _fixture.bounds())).is_true()
	assert_float(s.distance).is_between(env.d_min_m, env.d_max_m)


# --- district ---

func test_district_focuses_the_region_anchor_and_scales_with_region_radius() -> void:
	for code in [&"D1", &"D2", &"D4", &"D6"]:
		var r := CameraPresets.resolve("district:%s" % code, _world, _ground(_world))
		assert_bool(r["ok"]).is_true()
		var region := _world.region_by_code(code)
		var s: CameraState = r["state"]
		assert_float(Vector2(s.focus_x, s.focus_z).distance_to(region.anchor)).is_less(0.01)
		assert_float(s.distance).is_between(1000.0, 25000.0)
		# Ham preset yarıçapla ölçeklenir; zarf/K1 yalnız azaltabilir (kenar ilçelerinde).
		var raw := CameraPresets.district(_world, code)
		assert_float(raw.distance).is_greater_equal(maxf(region.radius.x, region.radius.y) * 2.0)
		assert_float(s.distance).is_less_equal(raw.distance + 0.001)


func test_district_accepts_parenthesis_form_and_lowercase_and_follows_moved_anchor() -> void:
	var a: CameraState = CameraPresets.resolve("district(d4)", _world)["state"]
	var moved := WorldTestSupport.coarse(WorldTestSupport.control())
	moved.region_by_code(&"D4").anchor += Vector2(2500.0, 1800.0)
	var b: CameraState = CameraPresets.resolve("district:D4", moved)["state"]
	var shift := Vector2(b.focus_x - a.focus_x, b.focus_z - a.focus_z)
	assert_float(shift.distance_to(Vector2(2500.0, 1800.0))).is_less(0.01)


func test_district_uses_the_fixtures_own_region_codes_not_hardcoded_d_codes() -> void:
	var ok := CameraPresets.resolve("district:F2", _fixture)
	assert_bool(ok["ok"]).is_true()
	var anchor := _fixture.region_by_code(&"F2").anchor
	# Ham preset odağı çapadır; çözülmüş odak yalnız K1 (küçük fixture'da kenar payı yakın) kaydırabilir: en çok
	# K1 girişindeki (k1_min) ayak izi yarıçapı kadar, ve sonuç K1'li.
	var raw := CameraPresets.district(_fixture, &"F2")
	assert_float(Vector2(raw.focus_x, raw.focus_z).distance_to(anchor)).is_less(0.01)
	var env := CameraEnvelope.load_default()
	assert_float(Vector2(ok["state"].focus_x, ok["state"].focus_z).distance_to(anchor)).is_less(
			env.k1_min_distance_m * 0.7)
	assert_bool(env.footprint_ok(ok["state"], CameraEnvelope.DEFAULT_ASPECT, Callable(), _fixture.bounds())).is_true()
	# Fixture'da D4 yok: sessiz uydurma yok, net hata + güvenli yedek (core).
	var bad := CameraPresets.resolve("district:D4", _fixture)
	assert_bool(bad["ok"]).is_false()
	assert_str(String(bad["error"])).contains("D4")
	assert_str(String(bad["name"])).is_equal("core")


func test_district_heading_looks_inward_from_the_anchor_towards_the_world_center() -> void:
	# ADR-0007 §Karar 5: yön İÇE (çapa -> dünya merkezi); K1 altında dışa bakış kenar ilçelerinde dik eğim ister.
	var center := _world.origin + _world.size * 0.5
	for code in [&"D2", &"D5"]:
		var s: CameraState = CameraPresets.district(_world, code)
		var fwd := CameraMath.forward(s.heading_deg, 0.0)
		var inward := (center - _world.region_by_code(code).anchor).normalized()
		assert_float(Vector2(fwd.x, fwd.z).dot(inward)).is_greater(0.99)
	# Olumsuz: eski dışa yön (merkez -> çapa) D2'de K1 için neredeyse tam dik eğim ister; içe bakış çok daha yatay kalır.
	var env := CameraEnvelope.load_default()
	var d2 := CameraPresets.district(_world, &"D2")
	var outward := d2.copy()
	outward.heading_deg = wrapf(d2.heading_deg + 180.0, 0.0, 360.0)
	var wide := CameraEnvelope.DEFAULT_ASPECT
	assert_float(env.required_pitch(d2, wide, Callable(), _world.bounds())).is_less(60.0)
	var p_out := env.required_pitch(outward, wide, Callable(), _world.bounds())
	assert_bool(p_out < 0.0 or p_out > 75.0).is_true()


# --- street ---

func test_street_focus_is_the_given_world_point_at_human_scale_on_the_ground() -> void:
	var p := Vector2(12500.0, 8300.0)
	var r := CameraPresets.resolve("street:12500,8300", _world, _ground(_world))
	assert_bool(r["ok"]).is_true()
	assert_bool(r["clamped"]).is_false()
	var s: CameraState = r["state"]
	assert_float(Vector2(s.focus_x, s.focus_z).distance_to(p)).is_less(0.01)
	assert_float(s.focus_y).is_equal_approx(maxf(_world.height_at(p.x, p.y), _world.sea_level), 0.01)
	assert_float(s.distance).is_less(200.0)
	assert_float(s.pitch_deg).is_less(30.0)
	# Sokak preset'i kendi eğimini (12 derece, perf tabanı `street:port`) korur; zarf tabanı (~3 derece) onu YUKARI
	# çekmez ve altına inmez. Uzaklık 60 m'de kalır.
	assert_float(s.pitch_deg).is_equal_approx(CameraPresets.STREET_PITCH_DEG, 0.001)
	assert_float(s.pitch_deg).is_greater_equal(CameraEnvelope.load_default().pitch_min_deg(s.distance))


func test_street_accepts_region_code_and_site_kind_and_parenthesis_point() -> void:
	var by_region: CameraState = CameraPresets.resolve("street:D4", _world)["state"]
	var d4 := _world.region_by_code(&"D4").anchor
	assert_float(Vector2(by_region.focus_x, by_region.focus_z).distance_to(d4)).is_less(0.01)
	var by_site: CameraState = CameraPresets.resolve("street:port", _world)["state"]
	assert_float(Vector2(by_site.focus_x, by_site.focus_z).distance_to(_world.port_site.position)).is_less(0.01)
	var by_paren: CameraState = CameraPresets.resolve("street(5000, 6000)", _world)["state"]
	assert_float(by_paren.focus_x).is_equal_approx(5000.0, 0.01)
	assert_float(by_paren.focus_z).is_equal_approx(6000.0, 0.01)
	# Kenar payı içindeki nokta odakta pay sınırına çekilir (sokak bandında kutu kenarı pusla kapanır).
	var near_edge: CameraState = CameraPresets.resolve("street(1000, 2000)", _world)["state"]
	var inner := CameraEnvelope.load_default().inner_rect(_world.bounds())
	assert_float(near_edge.focus_x).is_equal_approx(inner.position.x, 0.01)


func test_street_point_outside_the_world_is_clamped_and_flagged_and_garbage_is_rejected() -> void:
	var r := CameraPresets.resolve("street:999999,-5", _world)
	assert_bool(r["ok"]).is_true()
	assert_bool(r["clamped"]).is_true()
	var inner := CameraEnvelope.load_default().inner_rect(_world.bounds())
	assert_bool(inner.grow(0.01).has_point(Vector2(r["state"].focus_x, r["state"].focus_z))).is_true()  # kenar payı içinde
	for bad in ["street:", "street:abc", "street:1,2,3", "street:ZZ9", "teleport", "district:", "district:D99"]:
		var rejected := CameraPresets.resolve(bad, _world)
		assert_bool(rejected["ok"]).is_false()
		assert_bool(rejected["state"].is_valid()).is_true()  # yedek geçerli: kamera bozulmaz


func test_street_faces_downhill_which_at_the_coast_means_towards_the_water() -> void:
	var port := _world.port_site.position
	var s: CameraState = CameraPresets.resolve("street:port", _world)["state"]
	var fwd := CameraMath.forward(s.heading_deg, 0.0)
	var ahead := port + Vector2(fwd.x, fwd.z) * 600.0
	var behind := port - Vector2(fwd.x, fwd.z) * 600.0
	assert_float(_world.height_at(ahead.x, ahead.y)).is_less(_world.height_at(behind.x, behind.y))


# --- T-001 preset'leri ---

func test_all_five_t001_presets_resolve_with_their_original_numbers_under_the_legacy_envelope() -> void:
	var expected := {
		&"bay_west": [78.0, 32.0, 17000.0], &"plain_east": [150.0, 38.0, 24000.0],
		&"harbor": [235.0, 42.0, 8500.0], &"d5_slopes": [null, 35.0, 7000.0],
	}
	assert_int(CameraPresets.KEY_ORDER.find(&"d5_slopes")).is_equal(4)  # 5. tuş
	for name in expected:
		var r := CameraPresets.resolve(String(name), _world, Callable(), _legacy)
		assert_bool(r["ok"]).is_true()
		var s: CameraState = r["state"]
		var e: Array = expected[name]
		if e[0] != null:
			assert_float(s.heading_deg).is_equal_approx(e[0], 0.001)
		assert_float(s.pitch_deg).is_equal_approx(e[1], 0.001)
		assert_float(s.distance).is_equal_approx(e[2], 0.001)
		assert_float(s.fov_deg).is_equal(40.0)


func test_t001_presets_under_the_player_envelope_are_pulled_into_the_envelope_never_the_old_image() -> void:
	var env := CameraEnvelope.load_default()
	for name in ["bay_west", "plain_east", "harbor", "d5_slopes"]:
		var s: CameraState = CameraPresets.resolve(name, _world, _ground(_world))["state"]
		assert_float(s.distance).is_less_equal(env.d_max_m)
		assert_float(s.pitch_deg).is_greater_equal(env.pitch_min_deg(s.distance) - 0.001)
		assert_bool(_k1_ok(env, s)).is_true()
	# plain_east eskiden 24 km idi: tavan altına iner (zarfsız görüntü yalnız legacy ile).
	assert_float((CameraPresets.resolve("plain_east", _world)["state"] as CameraState).distance).is_less_equal(env.d_max_m)


func test_d5_slopes_preset_derives_from_the_d5_anchor_and_looks_at_the_slope() -> void:
	var s: CameraState = CameraPresets.resolve("d5_slopes", _world)["state"]
	var d5 := _world.region_by_code(&"D5")
	var center := _world.origin + _world.size * 0.5
	var focus := Vector2(s.focus_x, s.focus_z)
	assert_float(focus.distance_to(d5.anchor)).is_between(500.0, minf(d5.radius.x, d5.radius.y) * 0.5)
	assert_float((focus - d5.anchor).normalized().dot((center - d5.anchor).normalized())).is_greater(0.99)
	# Kamera, odağın ova/körfez tarafında durur ve D5'e (yamaca) bakar.
	var fwd := CameraMath.forward(s.heading_deg, 0.0)
	assert_float(Vector2(fwd.x, fwd.z).normalized().dot((d5.anchor - focus).normalized())).is_greater(0.9)


func test_d5_slopes_preset_follows_the_data_when_the_anchor_moves() -> void:
	var moved := WorldTestSupport.coarse(WorldTestSupport.control())
	moved.region_by_code(&"D5").anchor += Vector2(-3000.0, -2000.0)
	var a: CameraState = CameraPresets.resolve("d5_slopes", _world)["state"]
	var b: CameraState = CameraPresets.resolve("d5_slopes", moved)["state"]
	assert_float(Vector2(a.focus_x, a.focus_z).distance_to(Vector2(b.focus_x, b.focus_z))).is_greater(2000.0)


func test_legacy_presets_fall_back_to_the_center_when_regions_are_missing_without_crashing() -> void:
	for name in ["plain_east", "d5_slopes", "harbor"]:
		var r := CameraPresets.resolve(name, _fixture)  # fixture: D4/D5 yok
		assert_bool(r["ok"]).is_true()
		assert_bool(r["state"].is_valid()).is_true()
