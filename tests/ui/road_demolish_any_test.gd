extends GdUnitTestSuite
## D-014 §1 (kullanıcı sözü: "yolu ayrıca yıkma seçeneği hep olsun") · Ayakta duran HER yol panelden seçilip
## yıkılabilir:
## liste yalnız sim kaydından (`public_works`) ve sim yıkım önizlemesinden (maliyet/ret nedeni) kurulur, yıkım ek onay
## ister, onaylanan yol YALNIZ seçilen yoldur, dokunmatik hedefler >= 44 pt.

const P := preload("res://tests/sim/public_works/public_works_support.gd")

var _run: Dictionary
var _facade: SimFacadeImpl
var _tool: RoadDrawTool


func before_test() -> void:
	UiText.reset()
	UiText.report_missing = false
	_run = P.setup()
	_facade = _run["facade"]
	_tool = RoadDrawTool.create(_run["net"], _facade)
	_tool.activate()


func after_test() -> void:
	UiText.reset()


func _panel(profile: StringName = &"desktop", window: Vector2 = Vector2(440.0, 1400.0)) -> RoadDrawPanel:
	var ctx := UiContext.for_profile_name(profile)
	var holder := Control.new()
	holder.theme = UiTheme.build(ctx)
	holder.size = window
	add_child(holder)
	auto_free(holder)
	var panel := RoadDrawPanel.create(ctx, _facade, _tool)
	holder.add_child(panel)
	panel.size = window
	return panel


func _two_roads() -> Array[int]:
	_facade.submit_command(SimCommand.public_work_road(P.spur_a_cm(), &"local", false))
	_facade.advance(1)
	_facade.submit_command(SimCommand.public_work_road(P.spur_b_cm(), &"local", false))
	_facade.advance(1)
	var ids: Array[int] = []
	for w in _facade.public_works():
		ids.append(w.command_id)
	return ids


func test_keys_exist() -> void:
	for key in [&"road.demolish_list_show", &"road.demolish_list_hide", &"road.demolish_row",
			&"road.demolish_row_blocked"]:
		assert_bool(UiText.has(key)).override_failure_message("eksik metin: %s" % key).is_true()


func test_single_road_has_no_list_button_only_last_road_button() -> void:
	_facade.submit_command(SimCommand.public_work_road(P.spur_a_cm(), &"local", false))
	_facade.advance(1)
	var panel := _panel()
	assert_object(panel.demolish_button()).is_not_null()
	assert_object(panel.demolish_list_button()).is_null()


func test_list_offers_every_older_standing_road_with_sim_cost() -> void:
	var ids := _two_roads()
	assert_int(ids.size()).is_equal(2)
	var panel := _panel()
	assert_object(panel.demolish_list_button()).is_not_null()
	assert_int(panel.demolish_row_buttons().size()).is_equal(0)   # kapalıyken satır yok (şehri örtmez)
	panel.demolish_list_button().pressed.emit()
	assert_int(panel.demolish_row_buttons().size()).is_equal(1)
	var cost := _tool.demolish_cost(ids[0])
	var text := panel.joined_text()
	if cost >= 0:
		assert_str(text).contains(UiText.t(&"road.demolish_cost_units", {"units": UiText.number(cost)}))
	else:
		assert_str(text).contains(UiText.t(&"road.demolish_cost_unset"))
	assert_bool(panel.demolish_row_buttons()[0].text.begins_with("Yol 1:")).is_true()


func test_demolishing_an_older_road_removes_only_that_road_after_confirm() -> void:
	var ids := _two_roads()
	var panel := _panel()
	panel.demolish_list_button().pressed.emit()
	panel.demolish_row_buttons()[0].pressed.emit()
	assert_bool(panel.demolish_pending()).is_true()
	assert_int(panel.demolish_target()).is_equal(ids[0])
	assert_int(_facade.public_works().size()).is_equal(2)   # ilk dokunuş yıkmaz
	assert_str(panel.joined_text()).contains("Yol 1:")
	panel.demolish_confirm_button().pressed.emit()
	_facade.advance(1)
	panel.refresh()
	var left: Array[int] = []
	for w in _facade.public_works():
		left.append(w.command_id)
	assert_array(left).is_equal([ids[1]])


func test_keep_cancels_without_command() -> void:
	_two_roads()
	var panel := _panel()
	panel.demolish_list_button().pressed.emit()
	panel.demolish_row_buttons()[0].pressed.emit()
	panel.demolish_keep_button().pressed.emit()
	assert_bool(panel.demolish_pending()).is_false()
	assert_int(_facade.public_works().size()).is_equal(2)


func test_after_demolishing_the_older_road_the_list_disappears() -> void:
	var ids := _two_roads()
	_tool.demolish_road(ids[0])
	_facade.advance(1)
	var panel := _panel()
	assert_object(panel.demolish_list_button()).is_null()
	assert_str(panel.joined_text()).not_contains("public_work.reject")


func test_touch_targets_in_open_list() -> void:
	_two_roads()
	var panel := _panel(&"touch", Vector2(520.0, 1200.0))
	panel.demolish_list_button().pressed.emit()
	await get_tree().process_frame
	var buttons := UiTestSupport.visible_buttons(panel)
	assert_int(buttons.size()).is_greater(2)
	for b in buttons:
		assert_float(b.size.y).override_failure_message("%s: %s" % [b.text, b.size]).is_greater_equal(44.0)
