extends GdUnitTestSuite
## T-028 ölçüt 3 · kıyı/kontur çizgileri WorldData yüksekliğinden türer (marching squares): noktalar gerçekten seviyede.

const BLOB: PackedStringArray = [
	".......",
	".##....",
	".###.1.",
	".##....",
	".......",
]


func _level_error(world: WorldData, chain: Dictionary, level: float) -> float:
	var worst := 0.0
	for p: Vector2 in chain["points"]:
		worst = maxf(worst, absf(world.height_at(p.x, p.y) - level))
	return worst


func test_blob_and_island_give_two_closed_coast_loops_with_landmass_ids() -> void:
	var w := TopologyTestSupport.ascii_world(BLOB)
	var chains := TopologyContour.trace(w, w.sea_level)
	assert_int(chains.size()).is_equal(2)
	var ids := []
	for c in chains:
		assert_bool(c["closed"]).is_true()
		ids.append(c["landmass"])
	ids.sort()
	assert_array(ids).is_equal([1, 2])


func test_every_contour_point_lies_on_the_level() -> void:
	var w := TopologyTestSupport.ascii_world(BLOB)
	for c in TopologyContour.trace(w, w.sea_level):
		assert_float(_level_error(w, c, w.sea_level)).is_less(0.001)
	var real := WorldTestSupport.default_world()
	var coast := TopologyContour.trace(real, real.sea_level)
	assert_int(coast.size()).is_greater(1)
	for c in coast:
		assert_float(_level_error(real, c, real.sea_level)).is_less(0.01)


func test_land_touching_map_edge_gives_open_chain() -> void:
	var w := TopologyTestSupport.ascii_world(PackedStringArray([
		"####...", "####...", "####...", ".......", ".......",
	]))
	var chains := TopologyContour.trace(w, w.sea_level)
	assert_int(chains.size()).is_equal(1)
	assert_bool(chains[0]["closed"]).is_false()


func test_all_land_or_all_water_has_no_contour() -> void:
	var land := TopologyTestSupport.ascii_world(PackedStringArray(["###", "###", "###"]))
	assert_int(TopologyContour.trace(land, land.sea_level).size()).is_equal(0)
	var sea := TopologyTestSupport.ascii_world(PackedStringArray(["...", "...", "..."]))
	assert_int(TopologyContour.trace(sea, sea.sea_level).size()).is_equal(0)


func test_saddle_cell_does_not_cross_chains() -> void:
	# Çapraz iki kara hücresi: ambiguous (saddle) durum; her iki çözüm de kapalı döngü(ler) üretmeli, boş olmamalı.
	var w := TopologyTestSupport.ascii_world(PackedStringArray(["....", ".#..", "..#.", "...."]))
	var chains := TopologyContour.trace(w, w.sea_level)
	assert_int(chains.size()).is_greater(0)
	for c in chains:
		assert_bool(c["closed"]).is_true()


func test_island_count_matches_data_on_real_world() -> void:
	var real := WorldTestSupport.default_world()
	var coast := TopologyContour.trace(real, real.sea_level)
	var island_loops := 0
	for c in coast:
		if int(c["landmass"]) > WorldData.LANDMASS_MAINLAND:
			island_loops += 1
	assert_int(island_loops).is_equal(real.islands.size())


func test_deterministic_order() -> void:
	var real := WorldTestSupport.default_world()
	var a := TopologyContour.trace(real, real.sea_level)
	var b := TopologyContour.trace(real, real.sea_level)
	assert_int(a.size()).is_equal(b.size())
	for i in a.size():
		assert_array(a[i]["points"]).is_equal(b[i]["points"])
