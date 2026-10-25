extends GdUnitTestSuite
## T-051 Tur 1 · Palet v1 sınırları (design/specs/art/building-kit-v1.md §2.1 son paragraf, VIS-05). `kit_palette.json`
## tek kaynaktır; bu dosya sınırları OTOMATİK doğrular. Tolerans: S/V için ±0,005, hue için ±1,5° (spec tablosunun
## kendi onaltılık değerleri üçüncü ondalıkta sınırın üstüne/altına taşıyor: W1 V 0,871, W3 S 0,424, R5 V 0,549,
## R1 hue 36°; art-director değerleri değiştirmedi, test yuvarlama payını açıkça tanır).

const SV_TOL := 0.005
const HUE_TOL := 1.5
const TILE_ROWS := ["R3", "R4", "R5", "R9"]
const FIXED_ROWS_0_29 := ["W1", "W2", "W3", "W4", "W5", "W6", "W7", "W8", "W9", "W10", "W11", "W12", "W13", "R1", "R2",
		"R3", "R4", "R5", "R6", "R7", "R8", "G1", "A1", "A2", "A3", "P1", "P2", "P3", "P4", "P5"]


func _rows() -> Array:
	return KitMaterial.palette()["rows"]


func _hue_deg(c: Color) -> float:
	return c.h * 360.0


func _lab(c: Color) -> Vector3:
	var lin := c.srgb_to_linear()
	var x := (0.4124 * lin.r + 0.3576 * lin.g + 0.1805 * lin.b) / 0.95047
	var y := 0.2126 * lin.r + 0.7152 * lin.g + 0.0722 * lin.b
	var z := (0.0193 * lin.r + 0.1192 * lin.g + 0.9505 * lin.b) / 1.08883
	var f := func(t: float) -> float:
		return pow(t, 1.0 / 3.0) if t > 0.008856 else 7.787 * t + 16.0 / 116.0
	var fx: float = f.call(x)
	var fy: float = f.call(y)
	var fz: float = f.call(z)
	return Vector3(116.0 * fy - 16.0, 500.0 * (fx - fy), 200.0 * (fy - fz))


func test_row_ids_are_stable_and_reserves_became_r9_and_a4() -> void:
	var rows := _rows()
	assert_int(rows.size()).is_equal(32)
	for i in FIXED_ROWS_0_29.size():
		assert_str(str(rows[i]["name"])).is_equal(FIXED_ROWS_0_29[i])
		assert_int(int(rows[i]["row"])).is_equal(i)
	assert_str(str(rows[30]["name"])).is_equal("R9")
	assert_str(str(rows[31]["name"])).is_equal("A4")
	assert_int(KitMaterial.row_index("R9")).is_equal(30)
	assert_int(KitMaterial.row_index("A4")).is_equal(31)


func test_tile_rows_hue_saturation_value_limits() -> void:
	for n: String in TILE_ROWS:
		var c := KitMaterial.row_color(KitMaterial.row_index(n))
		assert_float(_hue_deg(c)).is_between(14.0 - HUE_TOL, 24.0 + HUE_TOL)
		assert_float(c.s).is_between(0.38 - SV_TOL, 0.66 + SV_TOL)
		assert_float(c.v).is_between(0.55 - SV_TOL, 0.76 + SV_TOL)


func test_tile_tones_are_distinguishable_for_hlod() -> void:
	for i in TILE_ROWS.size():
		for j in range(i + 1, TILE_ROWS.size()):
			var a := _lab(KitMaterial.row_color(KitMaterial.row_index(TILE_ROWS[i])))
			var b := _lab(KitMaterial.row_color(KitMaterial.row_index(TILE_ROWS[j])))
			assert_float(a.distance_to(b)).is_greater_equal(6.0)    # spec 8.2: kiremit tonları ΔE ≥ 6


func test_wall_rows_saturation_and_value_limits() -> void:
	for r in _rows():
		var n := str(r["name"])
		if not n.begins_with("W"):
			continue
		var c := Color.html(str(r["hex"]))
		var s_max := 0.60 if n == "W10" else 0.42
		assert_float(c.s).is_less_equal(s_max + SV_TOL)
		assert_float(c.v).is_between(0.58 - SV_TOL, 0.87 + SV_TOL)


func test_only_industrial_and_late_walls_are_cool() -> void:
	for r in _rows():
		var n := str(r["name"])
		if not n.begins_with("W"):
			continue
		var h := _hue_deg(Color.html(str(r["hex"])))
		var cool := h > 150.0
		assert_bool(cool).is_equal(n in ["W7", "W13"])    # soğuk mavi-gri yalnız geç/yeni (W7) ve sanayi sacı (W13)


func test_terrace_rows_are_warm_grey_not_blue() -> void:
	for n: String in ["R1", "R2"]:
		var c := KitMaterial.row_color(KitMaterial.row_index(n))
		assert_float(_hue_deg(c)).is_between(20.0 - HUE_TOL, 35.0 + HUE_TOL)
		assert_float(c.s).is_less(0.2)


func test_no_row_is_toy_saturated() -> void:
	for r in _rows():
		var c := Color.html(str(r["hex"]))
		assert_float(c.s).is_less_equal(0.70)    # VIS-05: oyuncak doygunluk yok


func test_rooftop_equipment_parts_use_fixed_rows() -> void:
	var parts: Array = KitMaterial.palette()["parts"]
	assert_str(str(parts[10]["name"])).is_equal("tank")
	assert_int(int(parts[10]["row"])).is_equal(KitMaterial.row_index("W12"))
	assert_str(str(parts[11]["name"])).is_equal("solar")
	assert_int(int(parts[11]["row"])).is_equal(KitMaterial.row_index("R7"))


func test_settlement_palette_rows_match_kit_palette() -> void:
	var control: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/world/ismeral/settlement.json"))
	var mapped: Dictionary = control["palette_rows"]
	for r in _rows():
		var n := str(r["name"])
		if mapped.has(n):
			assert_int(int(mapped[n])).is_equal(int(r["row"]))
	assert_bool(mapped.has("R9") and mapped.has("A4")).is_true()
