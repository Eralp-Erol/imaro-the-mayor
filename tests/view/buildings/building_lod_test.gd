extends GdUnitTestSuite
## T-012 ölçüt 1-2 · LOD aralıkları: margin'li, çakışan, boşluksuz; kademe sırası. Bozuk ayarlar yakalanır.


func test_default_ranges_follow_spec_bands_and_overlap_each_neighbour() -> void:
	var lod := BuildingLod.new()
	assert_array(lod.problems()).is_empty()
	var r0 := lod.range_for(BuildingLod.Tier.LOD0)
	var r1 := lod.range_for(BuildingLod.Tier.LOD1)
	var r2 := lod.range_for(BuildingLod.Tier.HLOD1)
	var r3 := lod.range_for(BuildingLod.Tier.HLOD2)
	assert_float(r0["begin"]).is_equal(0.0)
	assert_float(r3["end"]).is_equal(0.0)   # HLOD2 sonsuza kadar
	# spec §7.2: LOD1 ~600'te başlar, LOD0 ~700'e kadar uzar -> çakışma > 0 ve en az iki marjin kadar
	assert_float(lod.overlap_between(BuildingLod.Tier.LOD0, BuildingLod.Tier.LOD1)).is_greater_equal(
			2.0 * float(r0["end_margin"]))
	assert_float(lod.overlap_between(BuildingLod.Tier.LOD1, BuildingLod.Tier.HLOD1)).is_greater_equal(
			2.0 * float(r1["end_margin"]))
	assert_float(lod.overlap_between(BuildingLod.Tier.HLOD1, BuildingLod.Tier.HLOD2)).is_greater(
			float(r2["end_margin"]))
	assert_float(float(r1["begin"])).is_less(float(r0["end"]))


func test_every_distance_has_at_least_one_visible_tier_in_the_first_view() -> void:
	# Godot 4 mesafe kuralı modeli: gizli -> görünür ancak (begin + begin_margin, end - end_margin) içinde.
	var lod := BuildingLod.new()
	var d := 0.0
	while d <= 80000.0:
		assert_int(lod.initially_visible_tiers(d).size()).is_greater_equal(1)
		d += 5.0


func test_near_distance_shows_only_lod0_and_far_distance_only_hlod2() -> void:
	var lod := BuildingLod.new()
	assert_array(lod.initially_visible_tiers(100.0)).is_equal([BuildingLod.Tier.LOD0])
	assert_array(lod.initially_visible_tiers(1500.0)).is_equal([BuildingLod.Tier.LOD1])
	assert_array(lod.initially_visible_tiers(60000.0)).is_equal([BuildingLod.Tier.HLOD2])


func test_tiers_are_ordered_by_start_distance() -> void:
	var rs := BuildingLod.new().all_ranges()
	for t in range(1, rs.size()):
		assert_float(float(rs[t]["begin"])).is_greater(float(rs[t - 1]["begin"]))


func test_gap_between_tiers_is_reported_as_problem() -> void:
	var lod := BuildingLod.new()
	lod.lod1_end_m = 600.0   # LOD1 bitişi LOD0'a gömülü: HLOD1 LOD1'den önce başlıyor (sıra bozuk)
	assert_bool(lod.problems().is_empty()).is_false()
	var lod2 := BuildingLod.new()
	lod2.hlod2_overlap_m = -1000.0   # HLOD2 HLOD1 bitişinden sonra başlıyor: boşluk
	assert_bool(lod2.problems().is_empty()).is_false()


func test_margin_larger_than_range_is_reported() -> void:
	var lod := BuildingLod.new()
	lod.lod0_margin_m = 5000.0
	assert_bool(lod.problems().is_empty()).is_false()


func test_apply_writes_visibility_range_and_margins_to_nodes() -> void:
	var lod := BuildingLod.new()
	var node: MeshInstance3D = auto_free(MeshInstance3D.new())
	lod.apply(node, BuildingLod.Tier.LOD1)
	var r := lod.range_for(BuildingLod.Tier.LOD1)
	assert_float(node.visibility_range_begin).is_equal(float(r["begin"]))
	assert_float(node.visibility_range_begin_margin).is_equal(float(r["begin_margin"]))
	assert_float(node.visibility_range_end).is_equal(float(r["end"]))
	assert_float(node.visibility_range_end_margin).is_equal(float(r["end_margin"]))
	assert_int(node.visibility_range_fade_mode).is_equal(GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED)
