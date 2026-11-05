extends GdUnitTestSuite
## D-021 · Bina çatı/cephe çeşitliliği (görünüm tarafı): veri odaklı oranlar, parsel kimliğinden deterministik seçim,
## yan yana tekrarın kırılması, düz çatılı modüllerde çatı modu yok, sim sütunlarına yazma yok.

var _kit: BuildingKit
var _world: WorldData


func before() -> void:
	_kit = BuildingTestSupport.kit()
	_world = BuildingTestSupport.flat_world(6000.0, 100.0, Rect2(), 12.0)


func test_pick_is_deterministic_and_data_driven() -> void:
	var v := BuildingVariety.load_default()
	assert_bool(v.enabled).is_true()
	for pid in 200:
		assert_int(v.pick("hero_res_house", pid, 3, true, 0)).is_equal(v.pick("hero_res_house", pid, 3, true, 0))
	var tile := 0
	var light := 0
	var n := 4000
	for pid in n:
		var code := v.pick("hero_res_house", pid, 3, true, 0)
		tile += 1 if code % BuildingVariety.ROOF_MODES == 0 else 0
		light += 1 if code / BuildingVariety.ROOF_MODES == 1 else 0
	var keep := float(v.rule_for("hero_res_house")["roof_tile_keep"])
	assert_float(float(tile) / n).is_between(keep - 0.04, keep + 0.04)
	assert_float(float(light) / n).is_between(0.36, 0.44)
	# kiremit hala en çok: tek başına en büyük çatı sınıfı
	assert_float(float(tile) / n).is_greater(0.5)


func test_flat_roof_modules_never_get_a_roof_mode() -> void:
	var v := BuildingVariety.load_default()
	for pid in 500:
		assert_int(v.pick("hero_res_mid", pid, 1, false, 0) % BuildingVariety.ROOF_MODES).is_equal(0)


func test_disabled_gives_neutral_code_and_zero_custom_data() -> void:
	var v := BuildingVariety.new()
	assert_int(v.pick("hero_res_house", 5, 1, true, 0)).is_equal(0)


func test_neighbours_of_the_same_module_rarely_share_a_variant() -> void:
	var m := _kit.module_index(BuildingTestSupport.HOUSE_A)
	var cols := BuildingTestSupport.grid_columns(m, 10, 14.0, 50.0, 50.0)
	var plan := BuildingChunkPlan.build(cols, _world.origin, 1000.0, 4)
	var data := BuildingChunkBuilder.build_cell(cols, plan, plan.keys()[0], _kit, _world, BuildingViewConfig.new())
	var same := 0
	var pairs := 0
	for j in data.kept.size():
		for k in range(j + 1, data.kept.size()):
			var a := data.kept[j]
			var b := data.kept[k]
			if Vector2(cols.x[a] - cols.x[b], cols.z[a] - cols.z[b]).length() <= 15.0:
				pairs += 1
				same += 1 if data.variants[j] == data.variants[k] else 0
	assert_int(pairs).is_greater(100)
	# yeniden çekmesiz komşu çifti ~%30 aynı kod alırdı (kiremit/açık-olmayan baskın); belirgin azalır
	assert_float(float(same) / pairs).is_less(0.18)


func test_same_columns_give_identical_variants_and_columns_are_not_touched() -> void:
	var m := _kit.module_index(BuildingTestSupport.HOUSE_B)
	var cols := BuildingTestSupport.grid_columns(m, 6, 30.0, 80.0, 80.0)
	var before_state: Dictionary = cols.state_dict()
	var plan := BuildingChunkPlan.build(cols, _world.origin, 1000.0, 4)
	var a := BuildingChunkBuilder.build_cell(cols, plan, plan.keys()[0], _kit, _world, BuildingViewConfig.new())
	var b := BuildingChunkBuilder.build_cell(cols, plan, plan.keys()[0], _kit, _world, BuildingViewConfig.new())
	assert_array(a.variants).is_equal(b.variants)
	assert_array(a.hlod1_colors).is_equal(b.hlod1_colors)
	assert_dict(cols.state_dict()).is_equal(before_state)


func test_instance_buffer_carries_custom_data_and_hlod1_uses_variant_colors() -> void:
	var m := _kit.module_index(BuildingTestSupport.HOUSE_A)
	var cols := BuildingTestSupport.grid_columns(m, 8, 25.0, 60.0, 60.0)
	var plan := BuildingChunkPlan.build(cols, _world.origin, 1000.0, 4)
	var data := BuildingChunkBuilder.build_cell(cols, plan, plan.keys()[0], _kit, _world, BuildingViewConfig.new())
	var stride := BuildingChunkBuilder.INSTANCE_STRIDE
	var seen := {}
	for r in data.counts[0]:
		var mode := int(data.buffers[0][r * stride + 12])
		var light := int(data.buffers[0][r * stride + 13])
		seen[mode + BuildingVariety.ROOF_MODES * light] = true
		assert_int(mode + BuildingVariety.ROOF_MODES * light).is_equal(data.variants[r])
	assert_int(seen.size()).is_greater(2)
	var tpl := _kit.proxies[m] as BuildingKit.ProxyTemplate
	assert_int(tpl.variant_colors.size()).is_equal(BuildingVariety.CODES)
	assert_bool(tpl.colors_for(1) != tpl.colors).is_true()   # beton çatı: HLOD1 köşe renkleri değişir
