extends GdUnitTestSuite
## T-004 ölçüt 1 · Palet (tek kaynak kit_palette.json) ve parça/örnek verisi kodlaması: spec bölüm 5-6.
## Renk kuralları: duvar HSV S ≤ 0,40 (tuğla W10 ≤ 0,56), V 0,55–0,86; çatı S ≤ 0,55; oyuncak doygunluk yok (VIS-05).


func test_palette_has_32_rows_and_16_parts_with_unique_names() -> void:
	var pal := KitMaterial.palette()
	var names := {}
	assert_int((pal["rows"] as Array).size()).is_equal(32)
	for r in pal["rows"]:
		names[r["name"]] = true
		assert_bool(Color.html(str(r["hex"])) != Color.MAGENTA or str(r["hex"]) == "#FF00FF").is_true()
	assert_int(names.size()).is_equal(32)
	assert_int((pal["parts"] as Array).size()).is_equal(16)


func test_wall_rows_obey_saturation_and_value_limits() -> void:
	for r in KitMaterial.palette()["rows"]:
		var n := str(r["name"])
		if not n.begins_with("W"):
			continue
		var c := Color.html(str(r["hex"]))
		assert_float(c.s).is_less_equal(0.57 if n == "W10" else 0.41)
		assert_float(c.v).is_between(0.55, 0.86)


func test_roof_rows_obey_saturation_limit_and_tile_is_not_a_single_red() -> void:
	var tile_hues := []
	for r in KitMaterial.palette()["rows"]:
		var n := str(r["name"])
		if not n.begins_with("R"):
			continue
		var c := Color.html(str(r["hex"]))
		assert_float(c.s).is_less_equal(0.56)
		if n in ["R3", "R4", "R5"]:
			tile_hues.append(c.v)
	assert_int(tile_hues.size()).is_equal(3)
	var hi := maxf(tile_hues[0], maxf(tile_hues[1], tile_hues[2]))
	var lo := minf(tile_hues[0], minf(tile_hues[1], tile_hues[2]))
	var spread := hi - lo
	assert_float(spread).is_greater(0.1)       # 3 kiremit tonu birbirinden belirgin ayrışır


func test_row_lookup_and_instance_encoding_round_trip() -> void:
	assert_int(KitMaterial.row_index("W1")).is_equal(0)
	assert_int(KitMaterial.row_index("R3")).is_equal(15)
	assert_int(KitMaterial.row_index("A3")).is_equal(24)
	assert_int(KitMaterial.row_index("nope")).is_equal(-1)
	var c := KitMaterial.encode_instance(3, 16, 22, 1.06)
	assert_int(roundi(c.r * 32.0)).is_equal(3)
	assert_int(roundi(c.g * 32.0)).is_equal(16)
	assert_int(roundi(c.b * 32.0)).is_equal(22)
	assert_float(c.a * 32.0).is_equal_approx(1.06, 0.001)


func test_shader_parameters_come_from_the_palette_file() -> void:
	var mat := KitMaterial.create()
	assert_str(mat.resource_name).is_equal("mat_kit")
	var pal: PackedVector3Array = mat.get_shader_parameter("palette")
	assert_int(pal.size()).is_equal(32)
	var w1 := Color.html("#D9D2C3")
	assert_float(pal[0].x).is_equal_approx(w1.r, 0.002)
	var part_row: PackedFloat32Array = mat.get_shader_parameter("part_row")
	assert_float(part_row[0]).is_equal(-1.0)       # duvar = örnek duvar satırı
	assert_float(part_row[1]).is_equal(-2.0)       # çatı = örnek çatı satırı
	assert_float(part_row[3]).is_equal(21.0)       # cam = sabit G1
	var part_mul: PackedFloat32Array = mat.get_shader_parameter("part_mul")
	assert_float(part_mul[5]).is_equal_approx(0.85, 0.001)   # trim = duvar × 0,85 (spec 6)
