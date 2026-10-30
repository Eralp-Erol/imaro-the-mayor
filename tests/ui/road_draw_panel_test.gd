extends GdUnitTestSuite
## T-042 adım 3 (CAN-04, D-008/D-009; ui.md) · Yol çizimi arayüzü: Türkçe anahtarlar eksiksiz (ham anahtar görünmez),
## panel adımları ve önizleme kartı gerçek sim verisiyle, dokunmatik hedefler >= 44, 480-1600 px düzeni çakışmaz,
## "Yol yapıldı" kartı ve yatırımcı gerekçesindeki yol kaynağı bağlantısı. Para uydurulmaz: "Maliyet henüz kurulmadı".

const P := preload("res://tests/sim/public_works/public_works_support.gd")
const NORTH := Vector2(1100.0, 1000.0)
## Panel genişlikleri: 480 px pencerede en dar yan panel ... 1600 px'te masaüstü paneli (400) ... iPad yatay %38.
const PANEL_WIDTHS := [300, 356, 400, 456, 600]

var _run: Dictionary
var _facade: SimFacadeImpl
var _net: WorldNetwork
var _tool: RoadDrawTool


func before_test() -> void:
	UiText.reset()
	UiText.report_missing = false
	_run = P.setup()
	_facade = _run["facade"]
	_net = _run["net"]
	_tool = RoadDrawTool.create(_net, _facade)
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


func _draft(b: Vector2) -> void:
	_tool.tap_at(P.GRID_ORIGIN, 5.0)
	_tool.tap_at(b, 1.0)


func test_every_road_text_key_exists_including_all_sim_reject_reasons() -> void:
	var keys: Array[StringName] = [&"tool.road_draw", &"tool.road_draw.hint", &"road.title", &"road.confirm",
			&"road.cancel", &"road.undo_last", &"road.zoom_in", &"road.valid", &"road.start_not_on_road",
			&"public_work.cost.not_built", &"event.road.built", &"event.road.removed", &"alert.open_work",
			&"reason.source_road", &"reason.work_title", &"reason.work_gone", &"road.step.sending"]
	for reason in RoadDraftCheck.ALL_REASONS:
		keys.append(StringName(RoadDraftCheck.key_of(reason)))
	keys.append(StringName(RoadDraftCheck.key_of(RoadDraftCheck.REASON_PARCELS_CHANGED)))
	for key in keys:
		assert_bool(UiText.has(key)).override_failure_message("eksik metin: %s" % key).is_true()
		assert_str(UiText.t(key, {"length": 1, "units": 1, "length_m": 1, "units_total": 1, "min_m": 1, "max_m": 1,
				"date": "x", "regions": "x", "reason": "x"})).is_not_empty()


func test_pick_a_step_explains_the_first_tap_and_states_that_no_building_is_placed() -> void:
	var text := _panel().joined_text()
	assert_str(text).contains(UiText.t(&"road.step.pick_a"))
	assert_str(text).contains(UiText.t(&"road.no_building"))
	assert_str(text).contains(UiText.t(&"road.step_line", {"n": 1, "total": 3}))
	assert_array(Array(UiText.missing_keys())).is_empty()


func test_valid_review_shows_sim_numbers_a_not_built_cost_and_an_enabled_confirm_button() -> void:
	_draft(NORTH)
	var panel := _panel()
	var text := panel.joined_text()
	var args := _tool.preview_args()
	assert_str(text).contains(UiText.t(&"road.length", {"length": int(args["length_m"])}))
	assert_str(text).contains(UiText.t(&"road.capacity", {"units": int(args["units_total"])}))
	assert_str(text).contains(UiText.t(&"public_work.cost.not_built"))
	assert_str(text).contains(UiText.t(&"road.valid"))
	assert_bool(panel.confirm_button().disabled).is_false()
	assert_bool(panel.confirm_button().text == UiText.t(&"road.confirm")).is_true()
	assert_array(Array(UiText.missing_keys())).is_empty()


func test_invalid_review_shows_the_turkish_reason_and_never_a_raw_key_or_an_active_confirm() -> void:
	_draft(P.GRID_ORIGIN + Vector2(0.0, -600.0))
	var panel := _panel()
	var reason := UiText.reject_reason(_tool.verdict.reason_key, _tool.verdict.args)
	assert_str(reason).contains("400")
	var text := panel.joined_text()
	assert_str(text).contains(reason)
	assert_str(text).not_contains("public_work.")
	assert_bool(panel.confirm_button() == null or panel.confirm_button().disabled).is_true()
	assert_str(text).not_contains(UiText.t(&"road.valid"))


func test_undo_row_appears_only_when_a_player_road_exists_and_costs_are_never_invented() -> void:
	assert_object(_panel().undo_button()).is_null()
	_draft(NORTH)
	_tool.confirm()
	_facade.advance(1)
	_tool.on_events(_facade.events_since(0))
	var panel := _panel()
	assert_object(panel.undo_button()).is_not_null()
	assert_str(panel.undo_button().text).is_equal(UiText.t(&"road.undo_last"))
	for token in ["₺", "lira", "¤"]:
		assert_str(panel.joined_text()).not_contains(token)


func test_metro_band_replaces_the_flow_with_the_zoom_in_text() -> void:
	_tool.set_band(&"metro")
	var text := _panel().joined_text()
	assert_str(text).contains(UiText.t(&"road.zoom_in"))
	assert_str(text).not_contains(UiText.t(&"road.step.pick_a"))


func test_touch_profile_buttons_meet_the_44_point_floor() -> void:
	_draft(NORTH)
	_tool.confirm()
	_facade.advance(1)
	_tool.on_events(_facade.events_since(0))
	_draft(NORTH + Vector2(0.0, -1.0))
	var panel := _panel(&"touch", Vector2(520.0, 1200.0))
	await get_tree().process_frame
	var buttons := UiTestSupport.visible_buttons(panel)
	assert_int(buttons.size()).is_greater(1)
	for b in buttons:
		assert_float(b.size.y).override_failure_message("%s: %s" % [b.text, b.size]).is_greater_equal(44.0)
		assert_float(b.size.x).override_failure_message("%s: %s" % [b.text, b.size]).is_greater_equal(44.0)


func test_panel_buttons_stay_inside_the_frame_and_never_overlap_at_every_panel_width() -> void:
	_draft(NORTH)
	for width: int in PANEL_WIDTHS:
		var profile: StringName = &"touch" if width >= 456 else &"desktop"
		var window := Vector2(float(width), 1400.0)
		var panel := _panel(profile, window)
		await get_tree().process_frame
		var buttons := UiTestSupport.visible_buttons(panel)
		assert_int(buttons.size()).is_greater(1)
		var frame := Rect2(panel.get_global_rect().position, window).grow(0.5)
		for i in buttons.size():
			var r := buttons[i].get_global_rect()
			assert_bool(frame.encloses(r)).override_failure_message("taşma %d px: %s / %s" % [width, r, frame]).is_true()
			for j in range(i + 1, buttons.size()):
				assert_bool(r.intersects(buttons[j].get_global_rect())) \
						.override_failure_message("çakışma %d px: %s ~ %s" % [width, buttons[i].text, buttons[j].text]) \
						.is_false()
