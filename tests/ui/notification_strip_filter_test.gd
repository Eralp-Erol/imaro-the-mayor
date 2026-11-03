extends GdUnitTestSuite
## Bildirim şeridi seçimi: oyuncunun eylemi ve inşaat öncelikli, plansız toplu "vazgeçti" tek tek gösterilmez (tek özet
## satırı), aynı mesaj tekrar doldurmaz. Filtre YALNIZ şeritte; olay günlüğü/gerekçe ekranları etkilenmez.


func before_test() -> void:
	UiText.reset()
	UiText.report_missing = false


func after_test() -> void:
	UiText.reset()


func _strip() -> NotificationStrip:
	var s := NotificationStrip.create(UiContext.for_profile_name(&"desktop"))
	add_child(s)
	return auto_free(s)


func test_an_idle_strip_keeps_no_unowned_summary_nodes() -> void:
	var before := get_tree().root.get_orphan_node_ids().size()
	var strip := _strip()
	assert_bool(strip.visible).is_false()
	assert_int(get_tree().root.get_orphan_node_ids().size()).is_equal(before)


func _ev(seq: int, kind: StringName, key: StringName, parcel: int = 0, args: Dictionary = {},
		command_id: int = 0) -> SimEvent:
	var e := SimEvent.new()
	e.seq = seq
	e.kind = kind
	e.message_key = key
	e.args = args
	e.command_id = command_id
	if parcel > 0:
		e.subjects = PackedStringArray(["parcel.%d" % parcel])
	return e


func _unplanned(seq: int, parcel: int) -> SimEvent:
	return _ev(seq, &"actor.decided", &"event.investor.declined", parcel, {"code": "zoning_unplanned"})


func test_unplanned_declines_are_not_listed_one_by_one() -> void:
	var s := _strip()
	var evs: Array[SimEvent] = []
	for k in 50:
		evs.append(_unplanned(k + 1, k + 100))
	s.push_events(evs)
	assert_int(s.row_count()).is_equal(0)


func test_unplanned_summary_uses_real_distinct_parcel_count() -> void:
	var s := _strip()
	var evs: Array[SimEvent] = []
	for k in 5:
		evs.append(_unplanned(k + 1, 100 + k))
	evs.append(_unplanned(6, 100))  # aynı parsel yeniden: sayıya eklenmez
	s.push_events(evs)
	assert_int(s.unplanned_count()).is_equal(5)
	assert_str(s.summary_text()).is_equal(UiText.t(&"strip.unplanned_summary", {"n": 5}))
	assert_bool(s.visible).is_true()
	# bir parsel yatırım alırsa artık plansız beklemiyor
	s.push_events([_ev(7, &"actor.decided", &"event.investor.develop", 100)])
	assert_int(s.unplanned_count()).is_equal(4)


func test_player_results_survive_a_flood_of_background_events() -> void:
	var s := _strip()
	s.push_events([_ev(1, &"public_work.built", &"event.road.built", 0, {"length_m": 40, "units_total": 3}, 9)])
	var noise: Array[SimEvent] = []
	for k in 20:
		noise.append(_ev(k + 2, &"actor.decided", &"event.investor.declined", 200 + k, {"code": "demand_too_low"}))
	s.push_events(noise)
	var texts := Array(s.row_texts())
	var has_road := false
	for t: String in texts:
		if t.begins_with("Yol yapıldı"):
			has_road = true
	assert_bool(has_road).is_true()


func test_construction_and_player_command_events_outrank_background_declines() -> void:
	var started := _ev(2, &"parcel.changed", &"event.construction.started", 2)
	var done := _ev(3, &"parcel.changed", &"event.construction.completed", 3)
	var plan := _ev(5, &"command.applied", &"event.command.applied", 5, {"kind": "plan"}, 7)
	var s := _strip()
	s.push_events([
		_ev(1, &"actor.decided", &"event.investor.declined", 1, {"code": "demand_too_low"}),
		started,
		done,
		_ev(4, &"actor.decided", &"event.investor.declined", 4, {"code": "return_too_low"}),
		plan,
	])
	var joined := " | ".join(s.row_texts())
	assert_str(joined).contains(NotificationStrip.strip_text(started))
	assert_str(joined).contains(NotificationStrip.strip_text(done))
	assert_str(joined).contains(NotificationStrip.strip_text(plan))
	assert_int(s.row_count()).is_equal(3)


func test_identical_message_does_not_fill_the_strip() -> void:
	var s := _strip()
	for k in 6:
		s.push_events([_ev(k + 1, &"actor.decided", &"event.investor.declined", 7, {"code": "demand_too_low"})])
	assert_int(s.row_count()).is_equal(1)
