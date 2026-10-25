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
	var sand: Color = m.get_shader_parameter("sand_color")
	assert_float(sand.r).is_greater(sand.b)  # sıcak kum rengi
