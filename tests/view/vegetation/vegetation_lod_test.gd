extends GdUnitTestSuite
## T-062 B1 / T-057 Karar 5 · kademe seçimi: LOD0 < 120 m, LOD1 < 400 m, ötesinde bireysel proxy YOK (palmiye hariç).


func _lod() -> VegetationLod:
	return VegetationLod.from_config(VegetationViewConfig.load_default())


func test_tier_boundaries_are_half_open_and_gapless() -> void:
	var lod := _lod()
	assert_int(lod.tier_for(0.0, false)).is_equal(VegetationLod.Tier.LOD0)
	assert_int(lod.tier_for(119.999, false)).is_equal(VegetationLod.Tier.LOD0)
	assert_int(lod.tier_for(120.0, false)).is_equal(VegetationLod.Tier.LOD1)
	assert_int(lod.tier_for(399.999, false)).is_equal(VegetationLod.Tier.LOD1)
	assert_int(lod.tier_for(400.0, false)).is_equal(VegetationLod.Tier.NONE)
	assert_int(lod.tier_for(5000.0, false)).is_equal(VegetationLod.Tier.NONE)


func test_non_palm_species_never_get_an_individual_proxy_beyond_lod1() -> void:
	var lod := _lod()
	for d in [400.0, 401.0, 800.0, 1499.0, 1500.0, 10000.0]:
		assert_int(lod.tier_for(d, false)).is_equal(VegetationLod.Tier.NONE)


func test_palms_keep_the_proxy_between_lod1_and_the_proxy_end() -> void:
	var lod := _lod()
	assert_int(lod.tier_for(399.9, true)).is_equal(VegetationLod.Tier.LOD1)
	assert_int(lod.tier_for(400.0, true)).is_equal(VegetationLod.Tier.PROXY)
	assert_int(lod.tier_for(1499.9, true)).is_equal(VegetationLod.Tier.PROXY)
	assert_int(lod.tier_for(1500.0, true)).is_equal(VegetationLod.Tier.NONE)


func test_only_palm_species_in_the_game_table_have_a_proxy_level() -> void:
	var sp := VegetationTestSupport.species()
	for i in sp.size():
		assert_bool(sp.has_proxy(i)).is_equal(sp.keys[i].begins_with("palm_"))


func test_box_distance_range_and_uniform_tier() -> void:
	var lod := _lod()
	var r := VegetationLod.box_distance_range(Vector3(0, 0, 0), Vector3(100, 0, 0), Vector3(356, 10, 256))
	assert_float(r.x).is_equal_approx(100.0, 0.001)
	assert_float(r.y).is_equal_approx(sqrt(356.0 * 356.0 + 10.0 * 10.0 + 256.0 * 256.0), 0.01)
	# kamera kutunun içinde: en yakın 0
	var inside := VegetationLod.box_distance_range(Vector3(5, 5, 5), Vector3(0, 0, 0), Vector3(10, 10, 10))
	assert_float(inside.x).is_equal(0.0)
	assert_int(lod.uniform_tier(Vector2(10.0, 100.0), false)).is_equal(VegetationLod.Tier.LOD0)
	assert_int(lod.uniform_tier(Vector2(130.0, 390.0), false)).is_equal(VegetationLod.Tier.LOD1)
	assert_int(lod.uniform_tier(Vector2(410.0, 900.0), false)).is_equal(VegetationLod.Tier.NONE)
	assert_int(lod.uniform_tier(Vector2(100.0, 130.0), false)).is_equal(VegetationLod.MIXED)


func test_problems_detects_a_broken_chain() -> void:
	var lod := _lod()
	assert_array(Array(lod.problems())).is_empty()
	lod.lod1_end_m = lod.lod0_end_m
	assert_bool(lod.problems().is_empty()).is_false()
