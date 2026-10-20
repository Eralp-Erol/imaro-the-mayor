extends GdUnitTestSuite
## T-012 · Kit tablosu: manifest sırası = module_idx, PROXY şablonları (HLOD1 birleştirme girdisi), palet.

var _kit: BuildingKit


func before() -> void:
	_kit = BuildingTestSupport.kit()


func test_module_order_matches_the_manifest_and_dimensions_come_from_it() -> void:
	var modules: Array = BuildingTestSupport.library().manifest["modules"]
	assert_int(_kit.count).is_equal(modules.size())
	for n in modules.size():
		assert_str(_kit.ids[n]).is_equal(str(modules[n]["id"]))
		assert_float(_kit.footprint_w[n]).is_equal_approx(float(modules[n]["footprint_m"][0]), 0.001)
		assert_float(_kit.footprint_d[n]).is_equal_approx(float(modules[n]["footprint_m"][1]), 0.001)
	assert_int(_kit.module_index("bld_res_mid_a")).is_greater_equal(0)
	assert_int(_kit.module_index("yok_boyle_bir_modul")).is_equal(-1)


func test_landmark_and_building_kinds_are_flagged() -> void:
	var tower := _kit.module_index("bld_lmk_clocktower")
	assert_int(tower).is_greater_equal(0)
	assert_int(_kit.is_landmark[tower]).is_equal(1)
	assert_int(_kit.is_landmark[_kit.module_index("bld_res_mid_a")]).is_equal(0)
	assert_float(_kit.height_m[tower]).is_between(21.0, 26.0)   # kit spec §4


func test_proxy_templates_are_unindexed_triangles_within_the_14_triangle_budget() -> void:
	var built := 0
	for m in _kit.count:
		var tpl: BuildingKit.ProxyTemplate = _kit.proxies[m]
		if tpl == null:
			continue
		built += 1
		assert_int(tpl.vertices.size() % 3).is_equal(0)
		assert_int(tpl.vertices.size()).is_equal(tpl.normals.size())
		assert_int(tpl.triangle_count()).is_between(1, 14)   # kit manifest proxy_max_tris
		var total := 0
		for len_v in tpl.group_len:
			total += len_v
		assert_int(total).is_equal(tpl.vertices.size())   # gruplar köşeleri eksiksiz böler
	assert_int(built).is_greater_equal(28)   # bina modüllerinin hepsi


func test_proxy_colours_use_wall_roof_and_accent_rows_of_the_instance() -> void:
	var tpl: BuildingKit.ProxyTemplate = _kit.proxies[_kit.module_index("bld_res_house_a")]
	var wall := KitMaterial.row_index("W1")
	var roof := KitMaterial.row_index("R3")
	var colours := BuildingChunkBuilder.template_colors(_kit, tpl, wall, roof, 22, 1.0)
	assert_int(colours.size()).is_equal(tpl.vertices.size())
	var has_wall := false
	var has_roof := false
	for c in colours:
		has_wall = has_wall or c.is_equal_approx(_kit.shaded(wall, 1.0))
		has_roof = has_roof or c.is_equal_approx(_kit.shaded(roof, 1.0))
	assert_bool(has_wall).is_true()
	assert_bool(has_roof).is_true()
	# başka satırlarla farklı renk çıkar (renk gerçekten örnek verisinden geliyor)
	var other := BuildingChunkBuilder.template_colors(_kit, tpl, KitMaterial.row_index("W5"), roof, 22, 1.0)
	assert_bool(other != colours).is_true()


func test_brightness_scales_proxy_colours() -> void:
	var tpl: BuildingKit.ProxyTemplate = _kit.proxies[_kit.module_index("bld_res_mid_a")]
	var dim := BuildingChunkBuilder.template_colors(_kit, tpl, 0, 13, 22, 0.94)
	var lit := BuildingChunkBuilder.template_colors(_kit, tpl, 0, 13, 22, 1.06)
	assert_float(lit[0].r).is_greater(dim[0].r)


func test_palette_has_32_rows_from_the_single_source() -> void:
	assert_int(_kit.palette.size()).is_equal(KitMaterial.ROW_COUNT)
	assert_bool(_kit.palette[0].is_equal_approx(KitMaterial.row_color(0))).is_true()
	assert_bool(_kit.palette[21].is_equal_approx(KitMaterial.row_color(21))).is_true()
