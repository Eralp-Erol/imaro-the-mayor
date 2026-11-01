extends GdUnitTestSuite
## B-014 (madde 1-2): yol ipucu kartı HUD kartlarının (bildirim satırları, hız ipucu) üstüne binmez; kart yok sayılan
## alanlardan kaçınır. Saf yerleşim: `RoadCursorTip.place_near` / `place_at_top` + engel dikdörtgenleri. Dokunmatik
## hedefleri örten kart düğmeleri tıklanabilir ama okunmuyordu.

const GAP := 8.0
## iPad 1024x768 gerçek ölçüsü (QA kare + sondaj): bildirim sütunu ve sağındaki hız ipucu kartı.
const AREA := Rect2(0.0, 92.0, 635.0, 543.0)
const STRIP_ROWS: Array[Rect2] = [Rect2(16.0, 76.0, 285.0, 60.0), Rect2(16.0, 142.0, 285.0, 60.0),
	Rect2(16.0, 208.0, 285.0, 60.0), Rect2(16.0, 274.0, 285.0, 77.0)]
const HINT := Rect2(314.0, 103.0, 310.0, 97.0)


func before_test() -> void:
	UiText.reset()
	UiText.report_missing = false


func after_test() -> void:
	UiText.reset()


func _tip() -> RoadCursorTip:
	var tip := RoadCursorTip.create()
	add_child(tip)
	tip.theme = UiTheme.build(UiContext.for_profile_name(&"touch"))
	tip.show_text("", true, UiText.t(&"road.tip.step1_touch"))
	return auto_free(tip)


func _obstacles() -> Array[Rect2]:
	var out: Array[Rect2] = [HINT]
	out.append_array(STRIP_ROWS)
	return out


func _assert_clear(tip: RoadCursorTip, obstacles: Array[Rect2], tag: String) -> void:
	var rect := Rect2(tip.position, tip.size)
	for o in obstacles:
		assert_bool(rect.intersects(o.grow(GAP - 0.01))).override_failure_message(
			"%s: ipucu kartı %s engele %s binmiş/yapışık" % [tag, rect, o]).is_false()
	assert_bool(AREA.encloses(rect)).override_failure_message("%s: kart harita alanı dışında %s" % [tag, rect]).is_true()


func test_touch_tip_at_top_avoids_the_strip_and_the_speed_hint() -> void:
	var tip := _tip()
	tip.place_at_top(AREA, _obstacles())
	_assert_clear(tip, _obstacles(), "dokunmatik")


func test_desktop_tip_near_a_cursor_over_the_strip_moves_clear_of_it() -> void:
	var tip := _tip()
	for cursor: Vector2 in [Vector2(120.0, 110.0), Vector2(150.0, 300.0), Vector2(400.0, 130.0), Vector2(60.0, 600.0)]:
		tip.place_near(cursor, Vector2(1024.0, 768.0), AREA, _obstacles())
		_assert_clear(tip, _obstacles(), "imleç %s" % cursor)


func test_without_obstacles_placement_is_unchanged() -> void:
	var tip := _tip()
	tip.place_near(Vector2(20.0, 400.0), Vector2(1024.0, 768.0), AREA)
	assert_vector(tip.position).is_equal(Vector2(20.0, 400.0) + RoadCursorTip.CURSOR_OFFSET)
	tip.place_at_top(AREA)
	assert_float(tip.position.y).is_equal(AREA.position.y + 8.0)
