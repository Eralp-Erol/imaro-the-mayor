extends GdUnitTestSuite
## T-028 ölçüt 5 · etiket çakışması: yerleştirici hiçbir iki etiketi örtüştürmez, sınır içinde kalır.

const BOUNDS := Rect2(0.0, 0.0, 600.0, 400.0)


func test_same_anchor_labels_do_not_overlap() -> void:
	var placer := TopologyLabelPlacer.new(BOUNDS)
	var rects: Array[Rect2] = []
	for i in 6:
		var placed := placer.place(Vector2(300.0, 200.0), Vector2(60.0, 20.0))
		rects.append(placed["rect"])
	for i in rects.size():
		for j in range(i + 1, rects.size()):
			assert_bool(rects[i].intersects(rects[j])).override_failure_message("%d x %d" % [i, j]).is_false()


func test_labels_stay_inside_bounds_near_the_edge() -> void:
	var placer := TopologyLabelPlacer.new(BOUNDS)
	for anchor in [Vector2(2.0, 2.0), Vector2(598.0, 398.0), Vector2(3.0, 395.0)]:
		var placed := placer.place(anchor, Vector2(80.0, 24.0))
		assert_bool(BOUNDS.encloses(placed["rect"])).is_true()


func test_obstacle_is_avoided() -> void:
	var placer := TopologyLabelPlacer.new(BOUNDS)
	var obstacle := Rect2(250.0, 180.0, 120.0, 50.0)
	placer.add_obstacle(obstacle)
	var placed := placer.place(Vector2(300.0, 200.0), Vector2(60.0, 20.0))
	assert_bool((placed["rect"] as Rect2).intersects(obstacle)).is_false()


func test_moved_label_asks_for_a_leader_line() -> void:
	var placer := TopologyLabelPlacer.new(BOUNDS)
	placer.place(Vector2(300.0, 200.0), Vector2(60.0, 20.0))
	var second := placer.place(Vector2(300.0, 200.0), Vector2(60.0, 20.0))
	assert_bool(second["moved"]).is_true()


func test_negative_overlap_is_detected_when_rects_are_forced() -> void:
	# Olumsuz: yerleştirici atlanıp iki etiket aynı yere konursa çakışma sayacı bunu yakalar.
	var rects: Array[Rect2] = [Rect2(10, 10, 50, 20), Rect2(30, 15, 50, 20)]
	assert_int(TopologyLabelPlacer.count_overlaps(rects)).is_equal(1)
	assert_int(TopologyLabelPlacer.count_overlaps([Rect2(0, 0, 10, 10), Rect2(20, 0, 10, 10)])).is_equal(0)
