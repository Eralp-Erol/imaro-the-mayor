extends GdUnitTestSuite
## T-003 ölçüt 4, 6 · Kamera preset'leri VERİDEN türer: metro / district(kod) / street(nokta) + T-001 preset'leri
## değişmeden. Koordinat gömülü olsaydı veri değişince (ve fixture'da, farklı kodlar/boyut) testler kırılır.

var _world: WorldData
var _fixture: WorldData


func before() -> void:
	_world = WorldTestSupport.coarse(WorldTestSupport.control())
	_fixture = WorldFixture.build()


func _ground(w: WorldData) -> Callable:
	return func(x: float, z: float) -> float: return maxf(w.height_at(x, z), w.sea_level)


# --- metro ---

func test_metro_preset_frames_the_whole_world_and_scales_with_it() -> void:
	var r := CameraPresets.resolve("metro", _world, _ground(_world))
	assert_bool(r["ok"]).is_true()
	var s: CameraState = r["state"]
	var center := _world.origin + _world.size * 0.5
	assert_float(Vector2(s.focus_x, s.focus_z).distance_to(center)).is_less(_world.size.y * 0.1)
	assert_float(s.distance).is_equal_approx(_world.size.x * 1.45, 1.0)
	assert_float(s.pitch_deg).is_equal(50.0)
	# Küçük fixture dünyasında aynı preset küçük uzaklık verir: boyut gömülü değil.
	var f: CameraState = CameraPresets.resolve("metro", _fixture)["state"]
	assert_float(f.distance).is_equal_approx(_fixture.size.x * 1.45, 1.0)
	assert_float(f.distance).is_less(s.distance * 0.5)


# --- district ---

func test_district_focuses_the_region_anchor_and_scales_with_region_radius() -> void:
	for code in [&"D1", &"D2", &"D4", &"D6"]:
		var r := CameraPresets.resolve("district:%s" % code, _world, _ground(_world))
		assert_bool(r["ok"]).is_true()
		var region := _world.region_by_code(code)
		var s: CameraState = r["state"]
		assert_float(Vector2(s.focus_x, s.focus_z).distance_to(region.anchor)).is_less(0.01)
		assert_float(s.distance).is_between(3000.0, 25000.0)
		assert_float(s.distance).is_greater_equal(maxf(region.radius.x, region.radius.y) * 2.0)


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
	assert_float(Vector2(ok["state"].focus_x, ok["state"].focus_z).distance_to(anchor)).is_less(0.01)
	# Fixture'da D4 yok: sessiz uydurma yok, net hata + güvenli yedek (metro).
	var bad := CameraPresets.resolve("district:D4", _fixture)
	assert_bool(bad["ok"]).is_false()
	assert_str(String(bad["error"])).contains("D4")
	assert_str(String(bad["name"])).is_equal("metro")


func test_district_heading_looks_from_the_metro_center_towards_the_region() -> void:
	var d2: CameraState = CameraPresets.resolve("district:D2", _world)["state"]
	var center := _world.origin + _world.size * 0.5
	var fwd := CameraMath.forward(d2.heading_deg, 0.0)
	var to_anchor := (_world.region_by_code(&"D2").anchor - center).normalized()
	assert_float(Vector2(fwd.x, fwd.z).dot(to_anchor)).is_greater(0.99)


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


func test_street_accepts_region_code_and_site_kind_and_parenthesis_point() -> void:
	var by_region: CameraState = CameraPresets.resolve("street:D4", _world)["state"]
	var d4 := _world.region_by_code(&"D4").anchor
	assert_float(Vector2(by_region.focus_x, by_region.focus_z).distance_to(d4)).is_less(0.01)
	var by_site: CameraState = CameraPresets.resolve("street:port", _world)["state"]
	assert_float(Vector2(by_site.focus_x, by_site.focus_z).distance_to(_world.port_site.position)).is_less(0.01)
	var by_paren: CameraState = CameraPresets.resolve("street(1000, 2000)", _world)["state"]
	assert_float(by_paren.focus_x).is_equal_approx(1000.0, 0.01)
	assert_float(by_paren.focus_z).is_equal_approx(2000.0, 0.01)


func test_street_point_outside_the_world_is_clamped_and_flagged_and_garbage_is_rejected() -> void:
	var r := CameraPresets.resolve("street:999999,-5", _world)
	assert_bool(r["ok"]).is_true()
	assert_bool(r["clamped"]).is_true()
	assert_bool(_world.bounds().grow(0.01).has_point(Vector2(r["state"].focus_x, r["state"].focus_z))).is_true()
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

func test_all_five_t001_presets_resolve_with_their_original_numbers() -> void:
	var expected := {
		&"bay_west": [78.0, 32.0, 17000.0], &"plain_east": [150.0, 38.0, 24000.0],
		&"harbor": [235.0, 42.0, 8500.0], &"d5_slopes": [null, 35.0, 7000.0],
	}
	assert_int(CameraPresets.KEY_ORDER.find(&"d5_slopes")).is_equal(4)  # 5. tuş
	assert_int(CameraPresets.KEY_ORDER.find(&"metro")).is_equal(0)
	for name in expected:
		var r := CameraPresets.resolve(String(name), _world)
		assert_bool(r["ok"]).is_true()
		var s: CameraState = r["state"]
		var e: Array = expected[name]
		if e[0] != null:
			assert_float(s.heading_deg).is_equal_approx(e[0], 0.001)
		assert_float(s.pitch_deg).is_equal_approx(e[1], 0.001)
		assert_float(s.distance).is_equal_approx(e[2], 0.001)
		assert_float(s.fov_deg).is_equal(40.0)


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
