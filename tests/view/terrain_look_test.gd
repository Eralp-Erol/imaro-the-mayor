extends GdUnitTestSuite
## T-049b · Arazi görünümü: veri yükleme, gürültü dokusu, kıyı kumu ve dik yamaç kaya kuralları.

var _look: TerrainLook


func before() -> void:
	_look = TerrainLook.from_file(TerrainLook.DATA_PATH)


func test_look_data_loads_and_has_all_sections() -> void:
	assert_bool(_look.is_valid()).is_true()
	var e := _look.facet_slope_deg()
	assert_float(e.x).is_less(e.y)
	assert_bool(FileAccess.file_exists(TerrainLook.SHADER_PATH)).is_true()


func test_noise_texture_is_deterministic_and_tileable_with_mipmaps() -> void:
	var a := _look.make_noise_texture().get_image()
	var b := TerrainLook.from_file(TerrainLook.DATA_PATH).make_noise_texture().get_image()
	assert_array(a.get_data()).is_equal(b.get_data())
	assert_bool(a.has_mipmaps()).is_true()
	# Kenar sürekliliği: sarma noktasında komşu pikseller yakın (tileable).
	var w := a.get_width()
	var worst := 0.0
	for y in w:
		worst = maxf(worst, absf(a.get_pixel(0, y).r - a.get_pixel(w - 1, y).r))
	assert_float(worst).is_less(0.2)
	# Gürültü gerçekten değişir (düz doku değil).
	var lo := 1.0
	var hi := 0.0
	for k in 200:
		var v := a.get_pixel(k % w, (k * 7) % w).g
		lo = minf(lo, v)
		hi = maxf(hi, v)
	assert_float(hi - lo).is_greater(0.2)


func test_coast_sand_rule_sand_on_flat_shore_not_on_cliff_or_inland() -> void:
	assert_float(_look.sand_weight(0.5, 2.0)).is_greater(0.6)
	assert_float(_look.sand_weight(30.0, 2.0)).is_equal(0.0)
	assert_float(_look.sand_weight(0.5, 35.0)).is_equal(0.0)
	assert_float(_look.sand_weight(0.5, 2.0, 4000.0)).is_equal(0.0)  # iç havza: kıyıdan uzak kum yok


func test_rock_rule_is_slope_driven() -> void:
	assert_float(_look.rock_weight(10.0)).is_equal(0.0)
	assert_float(_look.rock_weight(55.0)).is_greater(0.5)
	assert_float(_look.rock_weight(38.0)).is_between(0.0, _look.rock_weight(55.0))


func test_material_builds_with_shader_and_data_driven_uniforms() -> void:
	var m := _look.make_material()
	assert_object(m.shader).is_not_null()
	assert_object(m.get_shader_parameter("noise_tex")).is_not_null()
	assert_float(float(m.get_shader_parameter("scale_fine"))).is_greater(0.0)
	# T-062 A4: renk uniform'ları kalktı; onaylı katman dizisi + tile_m + rol->katman uniform'ları var.
	assert_object(m.get_shader_parameter("layers")).is_same(GroundLayerSet.shared().array)
	assert_object(m.get_shader_parameter("layers")).is_instanceof(Texture2DArray)
	var tiles: PackedFloat32Array = m.get_shader_parameter("tile_m")
	assert_int(tiles.size()).is_equal(TerrainLook.MAX_LAYERS)
	assert_float(tiles[GroundLayerSet.shared().index_of("gnd_tex_beach_sand")]).is_equal(4.0)   # katalog tile_m
	var slots: PackedFloat32Array = m.get_shader_parameter("slot_layer")
	assert_int(slots.size()).is_equal(TerrainLook.MAX_LAYERS)
	assert_float(float(m.get_shader_parameter("detail_far"))).is_greater(0.0)


func test_roles_come_from_data_and_resolve_to_the_intended_approved_layers() -> void:
	var layers := GroundLayerSet.shared()
	var resolved := _look.resolve_ground_roles(layers)
	assert_int(resolved.size()).is_equal(TerrainLook.GROUND_ROLES.size())
	var expect := {
		&"coast_sand": "gnd_tex_beach_sand", &"rock": "gnd_tex_rock_cliff", &"field_a": "gnd_tex_field_plowed",
		&"field_b": "gnd_tex_field_stubble", &"urban_plaza": "gnd_tex_plaza_stone_a",
		&"urban_dirt": "gnd_tex_dirt_courtyard", &"urban_green": "gnd_tex_grass_green",
		&"urban_industrial": "gnd_tex_gravel", &"urban_sidewalk": "gnd_tex_sidewalk_cobble",
		&"natural_default": "gnd_tex_grass_dry", &"scrub": "gnd_tex_scrub_maquis", &"olive": "gnd_tex_olive_ground",
	}
	for role: StringName in expect:
		var role_index := TerrainLook.GROUND_ROLES.find(role)
		assert_int(role_index).is_greater_equal(0)
		assert_int(resolved[role_index]).is_equal(layers.index_of(str(expect[role])))
	# Veri güdümlü: JSON eşlemesini değiştirmek çözümü değiştirir (kodda sabit eşleme yok).
	var other := TerrainLook.from_file(TerrainLook.DATA_PATH)
	other.data["ground"]["roles"]["coast_sand"] = "gnd_tex_gravel"
	var changed := other.resolve_ground_roles(layers)
	var i_sand := TerrainLook.GROUND_ROLES.find(&"coast_sand")
	assert_int(changed[i_sand]).is_equal(layers.index_of("gnd_tex_gravel"))
	assert_int(changed[i_sand]).is_not_equal(resolved[i_sand])


func test_unapproved_role_id_is_denied_by_the_gate_and_never_loaded() -> void:
	# Negatif: eşlemede onaysız/bilinmeyen kimlik -> kapı reddeder (sayaç), katman YÜKLENMEZ, yedek katman kullanılır.
	var gate := LibraryGate.load_default()
	gate.report_errors = false
	var layers := GroundLayerSet.build(gate, false)
	var count_before := layers.count()
	var other := TerrainLook.from_file(TerrainLook.DATA_PATH)
	other.data["ground"]["roles"]["rock"] = "gnd_tex_rock_cliff_REJECTED"
	var resolved := other.resolve_ground_roles(layers)
	var i_rock := TerrainLook.GROUND_ROLES.find(&"rock")
	assert_int(resolved[i_rock]).is_equal(layers.index_of(str(other.data["ground"]["fallback"])))
	assert_array(Array(gate.unapproved_ids)).contains_exactly(["gnd_tex_rock_cliff_REJECTED"])
	assert_int(layers.count()).is_equal(count_before)
	assert_bool(layers.has_layer("gnd_tex_rock_cliff_REJECTED")).is_false()
	# Eski/laboratuvar kimlikleri de kapıdan geçmez.
	other.data["ground"]["roles"]["scrub"] = "gnd_macro"
	other.resolve_ground_roles(layers)
	assert_array(Array(gate.unapproved_ids)).contains(["gnd_macro"])


func test_shader_role_constants_match_the_role_order_and_field_grid_matches_the_palette() -> void:
	var code := FileAccess.get_file_as_string(TerrainLook.SHADER_PATH)
	var consts := {
		&"natural_default": "R_DEFAULT", &"natural_green": "R_GREEN", &"scrub": "R_SCRUB", &"olive": "R_OLIVE",
		&"rock": "R_ROCK", &"coast_sand": "R_SAND", &"coast_gravel": "R_GRAVEL", &"field_a": "R_FIELD_A",
		&"field_b": "R_FIELD_B", &"field_edge": "R_FIELD_EDGE", &"urban_plaza": "R_PLAZA", &"urban_dirt": "R_UDIRT",
		&"urban_green": "R_UGREEN", &"urban_industrial": "R_UIND", &"urban_sidewalk": "R_WALK",
	}
	assert_int(consts.size()).is_equal(TerrainLook.GROUND_ROLES.size())
	for k in TerrainLook.GROUND_ROLES.size():
		var role: StringName = TerrainLook.GROUND_ROLES[k]
		assert_bool(code.contains("const int %s = %d;" % [consts[role], k])).override_failure_message(
				"gölgelendirici %s != rol sırası %d" % [consts[role], k]).is_true()
	assert_bool(code.contains("const int ROLE_COUNT = %d;" % TerrainLook.GROUND_ROLES.size())).is_true()
	# JSON rol anahtarları = rol listesi (eksik/fazla yok).
	var keys: Array = (_look.data["ground"]["roles"] as Dictionary).keys()
	keys.sort()
	var want: Array = []
	for role in TerrainLook.GROUND_ROLES:
		want.append(String(role))
	want.sort()
	assert_array(keys).is_equal(want)
	# Tarla ızgarası paletle aynı (gölgelendirici tarla katmanı = palet tarla rengi hücreleri).
	var f: Dictionary = _look.data["ground"]["fields"]
	assert_float(float(f["rotation_rad"])).is_equal(TerrainPalette.FIELD_ROTATION_RAD)
	assert_float(float((f["size_m"] as Array)[0])).is_equal(TerrainPalette.FIELD_SIZE_M.x)
	assert_float(float((f["size_m"] as Array)[1])).is_equal(TerrainPalette.FIELD_SIZE_M.y)
	assert_float(float(f["share_plowed"]) + float(f["share_stubble"])).is_less_equal(1.0)
