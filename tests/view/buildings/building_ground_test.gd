extends GdUnitTestSuite
## T-012 ölçüt 1 · Yükseklik WorldData.height_at'ten, su/dünya dışı ayak izi çizilmez (olumsuz varyantlar dahil).

const HW := 7.0
const HD := 5.5


func test_flat_land_seats_the_base_just_below_the_terrain() -> void:
	var world := BuildingTestSupport.flat_world(4000.0, 100.0, Rect2(), 10.0)
	var y := BuildingGround.base_y(world, 2000.0, 2000.0, 0.7, HW, HD)
	assert_float(y).is_equal_approx(10.0 - BuildingGround.SINK_M, 0.001)


func test_base_follows_the_lowest_footprint_sample_on_a_slope() -> void:
	var world := BuildingTestSupport.flat_world(4000.0, 100.0, Rect2(), 10.0)
	# x'e göre rampa: yükseklik = 10 + x / 100
	for j in world.height:
		for i in world.width:
			world.heights[j * world.width + i] = 10.0 + float(i)
	var y := BuildingGround.base_y(world, 2000.0, 2000.0, 0.0, HW, HD)
	var expected := world.height_at(2000.0 - HW, 2000.0) - BuildingGround.SINK_M
	assert_float(y).is_equal_approx(expected, 0.001)
	assert_float(y).is_less(world.height_at(2000.0, 2000.0))


func test_footprint_touching_water_is_dropped() -> void:
	var world := BuildingTestSupport.flat_world(4000.0, 100.0, Rect2(2000.0, 0.0, 2000.0, 4000.0))
	# merkez karada (x = 1950), ama köşe suya taşıyor (x + HW > 2000 civarı; hücre kıyısı ~ 1950-2050 aralığında bilineer)
	assert_bool(is_nan(BuildingGround.base_y(world, 1990.0, 1000.0, 0.0, 30.0, 10.0))).is_true()
	assert_bool(is_nan(BuildingGround.base_y(world, 2500.0, 1000.0, 0.0, HW, HD))).is_true()
	assert_bool(is_nan(BuildingGround.base_y(world, 1000.0, 1000.0, 0.0, HW, HD))).is_false()


func test_coast_margin_rejects_buildings_hugging_the_shore() -> void:
	var world := BuildingTestSupport.flat_world(4000.0, 100.0, Rect2(2000.0, 0.0, 2000.0, 4000.0))
	var x := 1925.0   # ayak izi kıyıdan kıl payı içeride
	var tight := BuildingGround.base_y(world, x, 1000.0, 0.0, HW, HD, 0.0)
	var margin := BuildingGround.base_y(world, x, 1000.0, 0.0, HW, HD, 60.0)
	assert_bool(is_nan(tight)).is_false()
	assert_bool(is_nan(margin)).is_true()


func test_outside_the_world_is_dropped() -> void:
	var world := BuildingTestSupport.flat_world(4000.0, 100.0, Rect2(), 10.0)
	assert_bool(is_nan(BuildingGround.base_y(world, -5.0, 100.0, 0.0, HW, HD))).is_true()
	assert_bool(is_nan(BuildingGround.base_y(world, 100.0, 4010.0, 0.0, HW, HD))).is_true()


func test_yaw_rotates_the_sample_corners() -> void:
	# kıyı x = 2000 (su doğuda): uzun kenar (HW = 30) doğuya bakarsa suya taşar, kuzeye bakarsa taşmaz
	var world := BuildingTestSupport.flat_world(4000.0, 100.0, Rect2(2000.0, 0.0, 2000.0, 4000.0))
	var east_facing := BuildingGround.base_y(world, 1950.0, 1000.0, 0.0, 30.0, 4.0)
	var north_facing := BuildingGround.base_y(world, 1950.0, 1000.0, PI * 0.5, 30.0, 4.0)
	assert_bool(is_nan(east_facing)).is_true()
	assert_bool(is_nan(north_facing)).is_false()
