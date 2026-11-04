extends GdUnitTestSuite
## T-028 ölçüt 3 · geometri: kuzey = -z (ekranda yukarı), piksel <-> metre, ölçek çubuğu ölçüsü.

const WORLD := Rect2(0.0, 0.0, 40000.0, 40000.0)


func _proj() -> TopologyProjection:
	return TopologyProjection.fit(WORLD, Rect2(30.0, 150.0, 1500.0, 1500.0))


func test_north_is_minus_z_and_points_up_on_screen() -> void:
	var p := _proj()
	var south := p.to_screen(Vector2(20000.0, 30000.0))
	var north := p.to_screen(Vector2(20000.0, 10000.0))
	assert_float(north.y).is_less(south.y)
	assert_float(north.x).is_equal_approx(south.x, 0.001)
	assert_vector(TopologyProjection.NORTH).is_equal(Vector2(0.0, -1.0))
	assert_vector(p.north_on_screen()).is_equal_approx(Vector2(0.0, -1.0), Vector2(0.001, 0.001))


func test_east_is_plus_x_to_the_right() -> void:
	var p := _proj()
	assert_float(p.to_screen(Vector2(30000.0, 5000.0)).x).is_greater(p.to_screen(Vector2(10000.0, 5000.0)).x)


func test_pixel_meter_scale_is_uniform_and_roundtrips() -> void:
	var p := _proj()
	assert_float(p.px_per_m).is_equal_approx(1500.0 / 40000.0, 1.0e-9)
	assert_float(p.meters_per_pixel() * p.px_per_m).is_equal_approx(1.0, 1.0e-9)
	for w in [Vector2(0.0, 0.0), Vector2(12345.6, 7890.1), Vector2(40000.0, 40000.0)]:
		var back := p.to_world(p.to_screen(w))
		assert_vector(back).is_equal_approx(w, Vector2(0.01, 0.01))
	# 10 km = 375 px
	var a := p.to_screen(Vector2(5000.0, 5000.0))
	var b := p.to_screen(Vector2(15000.0, 5000.0))
	assert_float(a.distance_to(b)).is_equal_approx(375.0, 0.001)


func test_fit_keeps_aspect_and_centers_in_target() -> void:
	var p := TopologyProjection.fit(Rect2(0.0, 0.0, 40000.0, 20000.0), Rect2(0.0, 0.0, 1000.0, 1000.0))
	assert_float(p.screen_rect.size.x).is_equal_approx(1000.0, 0.001)
	assert_float(p.screen_rect.size.y).is_equal_approx(500.0, 0.001)
	assert_float(p.screen_rect.position.y).is_equal_approx(250.0, 0.001)


func test_scale_bar_pixel_length_matches_meters() -> void:
	var p := _proj()
	var bar := p.scale_bar(500.0)
	var meters: float = bar["meters"]
	var pixels: float = bar["pixels"]
	assert_float(pixels).is_less_equal(500.0)
	assert_float(pixels).is_equal_approx(meters * p.px_per_m, 0.001)
	assert_float(meters).is_equal(10000.0)


func test_nice_length_picks_1_2_5_steps() -> void:
	assert_float(TopologyProjection.nice_length_m(7300.0)).is_equal(5000.0)
	assert_float(TopologyProjection.nice_length_m(1999.0)).is_equal(1000.0)
	assert_float(TopologyProjection.nice_length_m(2000.0)).is_equal(2000.0)
	assert_float(TopologyProjection.nice_length_m(180.0)).is_equal(100.0)
	assert_float(TopologyProjection.nice_length_m(26000.0)).is_equal(20000.0)

