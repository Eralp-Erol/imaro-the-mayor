extends GdUnitTestSuite
## D-014 §1 (T-042c) · Yol çizim aracında klasik GERİ AL ve YOLU YIK arayüzü: düğmeler yalnız sim izin verdiğinde
## görünür (ölü düğme yok), yıkım maliyeti sim önizlemesinden gelir, yıkım ek onay ister ve alınan parsel/bina
## dönmez notunu düz Türkçe söyler, geri alma kapanınca sim'in nedeni yazılır, dokunmatik hedef >= 44, aralık >= 8 pt.

const P := preload("res://tests/sim/public_works/public_works_support.gd")
const B := preload("res://tests/sim/budget/budget_support.gd")
const NORTH := Vector2(1100.0, 1000.0)

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


func _build_road(b: Vector2 = NORTH) -> void:
	_tool.tap_at(P.GRID_ORIGIN, 5.0)
	_tool.tap_at(b, 1.0)
	_tool.confirm()
	_facade.advance(1)
	_tool.on_events(_facade.events_since(0))


func test_keys_exist() -> void:
	for key in [&"road.undo_closed", &"road.demolish_last", &"road.demolish_cost_units", &"road.demolish_cost_unset",
			&"road.demolish_blocked", &"road.demolish_title", &"road.demolish_effect", &"road.demolish_warning",
			&"road.demolish_warning_taken", &"road.demolish_confirm", &"road.demolish_keep",
			&"public_work.reject.undo_window_closed", &"public_work.reject.no_such_road",
			&"public_work.reject.demolition_unavailable", &"public_work.reject.demolition_changes_parcels"]:
		assert_bool(UiText.has(key)).override_failure_message("eksik metin: %s" % key).is_true()


func test_no_road_means_neither_undo_nor_demolish_button() -> void:
	var panel := _panel()
	assert_object(panel.undo_button()).is_null()
	assert_object(panel.demolish_button()).is_null()


func test_after_a_road_both_undo_and_demolish_are_offered_and_cost_comes_from_the_sim() -> void:
	_build_road()
	var panel := _panel()
	assert_object(panel.undo_button()).is_not_null()
	assert_object(panel.demolish_button()).is_not_null()
	assert_str(panel.demolish_button().text).is_equal(UiText.t(&"road.demolish_last"))
	var id := _tool.last_road().command_id
	var cost := _tool.demolish_cost(id)
	var text := panel.joined_text()
	if cost >= 0:
		assert_str(text).contains(UiText.t(&"road.demolish_cost_units", {"units": UiText.number(cost)}))
	else:
		assert_str(text).contains(UiText.t(&"road.demolish_cost_unset"))
	for token in ["₺", "lira", "¤"]:
		assert_str(text).not_contains(token)


func test_demolish_needs_a_second_confirm_step_with_plain_warning_and_nothing_happens_on_keep() -> void:
	_build_road()
	var panel := _panel()
	panel.demolish_button().pressed.emit()
	assert_bool(panel.demolish_pending()).is_true()
	assert_int(_facade.public_works().size()).is_equal(1)   # ilk dokunuş yıkmaz
	var text := panel.joined_text()
	assert_str(text).contains(UiText.t(&"road.demolish_title"))
	assert_str(text).contains(UiText.t(&"road.demolish_warning"))
	assert_object(panel.demolish_confirm_button()).is_not_null()
	panel.demolish_keep_button().pressed.emit()
	assert_bool(panel.demolish_pending()).is_false()
	assert_int(_facade.public_works().size()).is_equal(1)
	assert_object(panel.demolish_button()).is_not_null()


func test_confirming_demolition_removes_the_road_and_hides_both_buttons() -> void:
	_build_road()
	var panel := _panel()
	panel.demolish_button().pressed.emit()
	panel.demolish_confirm_button().pressed.emit()
	_facade.advance(1)
	panel.refresh()
	assert_int(_facade.public_works().size()).is_equal(0)
	assert_object(panel.demolish_button()).is_null()
	assert_object(panel.undo_button()).is_null()
	assert_bool(_facade.undo_available()).is_false()
	assert_str(panel.joined_text()).contains(UiText.t(&"road.demolish_sent"))


func test_demolish_stays_available_after_the_undo_window_closes_and_the_sim_reason_is_shown() -> void:
	# İki yol, ikincisi geri alınır: kalan ilk yol artık geri alınamaz (`superseded`) ama yıkılabilir.
	_facade.submit_command(SimCommand.public_work_road(P.spur_a_cm(), &"local", false))
	_facade.advance(1)
	_facade.submit_command(SimCommand.public_work_road(P.spur_b_cm(), &"local", false))
	_facade.advance(1)
	_facade.submit_command(SimCommand.public_work_undo_last())
	_facade.advance(1)
	assert_int(_facade.public_works().size()).is_equal(1)
	assert_bool(_facade.undo_available()).is_false()
	var panel := _panel()
	assert_object(panel.undo_button()).is_null()
	assert_object(panel.demolish_button()).is_not_null()
	var closed := _facade.validate_command(SimCommand.public_work_undo_last())
	assert_str(String(closed.args.get("cause", ""))).is_equal("superseded")
	assert_str(panel.joined_text()).contains(UiText.t(&"road.undo_closed",
			{"reason": UiText.reject_reason(closed.reason_key, closed.args)}))
	assert_str(panel.joined_text()).not_contains("public_work.reject")


func test_undo_button_click_removes_the_last_road() -> void:
	_build_road()
	var panel := _panel()
	panel.undo_button().pressed.emit()
	_facade.advance(1)
	assert_int(_facade.public_works().size()).is_equal(0)
	assert_str(_tool.message).is_equal(String(RoadDrawTool.MSG_UNDONE))


## Bütçeli + kamulaştırmalı dünya (sim testlerindeki test ikizi): maliyet sayı olarak, alınan arsa uyarısı yazılı.
func _priced_expropriating_facade() -> SimFacadeImpl:
	var net := P.network()
	var stock := ListStockSource.create([
		{"parcel_id": 1, "use": "residential", "units": 10, "owner": 1},
		{"parcel_id": 5, "use": "residential", "units": 8, "owner": 1}])
	var handle := EconomyBootstrap.create(P.SEED, P.source(), EconomyTestSupport.config(P.economy_patch()), stock)
	var ctx := PublicWorksContext.create(net, RoadDraftRules.new(), PublicWorksConfig.load_default())
	var fake := FakeExpropriationWorld.new(net)
	fake.take(P.spur_b_cm(), [5])
	ctx.set_expropriation(fake)
	handle.facade.attach_public_works(ctx)
	handle.facade.attach_budget(B.config())
	handle.facade.advance(1)
	_tool = RoadDrawTool.create(net, handle.facade)
	_tool.activate()
	return handle.facade


func test_priced_expropriating_road_shows_numeric_cost_and_taken_parcels_stay_taken_warning() -> void:
	_facade = _priced_expropriating_facade()
	_facade.submit_command(SimCommand.public_work_road(P.spur_b_cm(), &"local", true))
	_facade.advance(1)
	var id := _tool.last_road().command_id
	var cost := _tool.demolish_cost(id)
	assert_int(cost).is_greater_equal(0)
	var panel := _panel()
	assert_str(panel.joined_text()).contains(UiText.t(&"road.demolish_cost_units", {"units": UiText.number(cost)}))
	panel.demolish_button().pressed.emit()
	var text := panel.joined_text()
	assert_str(text).contains(UiText.t(&"road.demolish_warning_taken", {"parcels": 1}))
	assert_str(text).contains("geri gelmez")
	assert_str(text).contains("tepkisi de kalır")
	assert_int(_facade.public_works().size()).is_equal(1)
	panel.demolish_confirm_button().pressed.emit()
	_facade.advance(1)
	assert_int(_facade.public_works().size()).is_equal(0)
	# Alınan arsa geri gelmedi (sim kaydı): yıkım geri alma değildir.
	assert_str(String(_facade.parcel_views(PackedInt64Array([5]))[0].development)).is_equal("taken")


func test_touch_targets_are_44pt_with_8pt_gaps_in_both_demolish_states() -> void:
	_build_road()
	var panel := _panel(&"touch", Vector2(520.0, 1200.0))
	await get_tree().process_frame
	_assert_touch(panel)
	panel.demolish_button().pressed.emit()
	await get_tree().process_frame
	_assert_touch(panel)


func _assert_touch(panel: RoadDrawPanel) -> void:
	var buttons := UiTestSupport.visible_buttons(panel)
	assert_int(buttons.size()).is_greater(1)
	for b in buttons:
		assert_float(b.size.y).override_failure_message("%s: %s" % [b.text, b.size]).is_greater_equal(44.0)
		assert_float(b.size.x).override_failure_message("%s: %s" % [b.text, b.size]).is_greater_equal(44.0)
	for i in buttons.size():
		for j in range(i + 1, buttons.size()):
			var a := Rect2(buttons[i].global_position, buttons[i].size)
			var c := Rect2(buttons[j].global_position, buttons[j].size)
			assert_bool(a.grow(8.0).intersects(c, false) and not a.intersects(c)) \
					.override_failure_message("%s / %s < 8 pt" % [buttons[i].text, buttons[j].text]).is_false()
