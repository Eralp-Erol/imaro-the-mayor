extends GdUnitTestSuite
## T-042 adım 3 (CAN-04, D-008/D-009) · Yol çizim aracının durum makinesi gerçek facade ile: yola yapışma, iki dokunuş +
## onay, ret nedeni sim'den, iptal, gönderim -> olay -> yeni taslak, geri alma. Araç sim'e yalnız komutla yazar.

const P := preload("res://tests/sim/public_works/public_works_support.gd")
const R := 12.0
const NORTH := Vector2(1100.0, 1000.0)

var _run: Dictionary
var _facade: SimFacadeImpl
var _net: WorldNetwork
var _tool: RoadDrawTool


func before_test() -> void:
	_run = P.setup()
	_facade = _run["facade"]
	_net = _run["net"]
	_tool = RoadDrawTool.create(_net, _facade)


func _pick_a() -> void:
	_tool.activate()
	_tool.tap_at(P.GRID_ORIGIN + Vector2(3.0, -2.0), R)


func _events() -> Array[SimEvent]:
	var out: Array[SimEvent] = []
	out.append_array(_facade.events_since(0))
	return out


func test_activation_starts_at_pick_a_and_deactivation_clears_everything() -> void:
	assert_bool(_tool.is_active()).is_false()
	_pick_a()
	assert_int(_tool.step).is_equal(RoadDrawTool.Step.PICK_B)
	_tool.deactivate()
	assert_int(_tool.step).is_equal(RoadDrawTool.Step.OFF)
	assert_object(_tool.verdict).is_null()


func test_start_snaps_to_the_nearby_road_end_and_free_land_is_refused_with_a_message() -> void:
	_tool.activate()
	_tool.tap_at(Vector2(300.0, 2500.0), R)
	assert_int(_tool.step).is_equal(RoadDrawTool.Step.PICK_A)
	assert_str(String(_tool.message)).is_equal(String(RoadDrawTool.MSG_START_NOT_ON_ROAD))
	_tool.tap_at(P.GRID_ORIGIN + Vector2(3.0, -2.0), R)
	assert_int(_tool.step).is_equal(RoadDrawTool.Step.PICK_B)
	assert_vector(_tool.start).is_equal(P.GRID_ORIGIN)


func test_snap_picks_the_edge_point_when_no_end_is_in_reach() -> void:
	var snap := _tool.snap_to_road(Vector2(1180.0, 1104.0), 10.0)
	assert_bool(snap["snapped"]).is_true()
	assert_str(String(snap["kind"])).is_equal("edge")
	assert_float((snap["pos"] as Vector2).y).is_equal_approx(1100.0, 0.01)
	assert_bool(_tool.snap_to_road(Vector2(1180.0, 1160.0), 10.0)["snapped"]).is_false()


func test_hover_in_pick_b_previews_with_the_sim_and_valid_draft_can_be_confirmed() -> void:
	_pick_a()
	_tool.hover_at(NORTH + Vector2(0.0, 1.0), 2.0)
	assert_object(_tool.verdict).is_not_null()
	assert_bool(_tool.is_valid()).override_failure_message(str(_tool.verdict.reason_key)).is_true()
	assert_float(float(_tool.preview_args()["length_m"])).is_greater(90.0)
	assert_bool(_tool.can_confirm()).is_false()  # önce ikinci dokunuş
	_tool.tap_at(NORTH, 2.0)
	assert_int(_tool.step).is_equal(RoadDrawTool.Step.REVIEW)
	assert_bool(_tool.can_confirm()).is_true()


func test_too_long_and_too_short_drafts_show_the_sims_reject_key_and_cannot_be_confirmed() -> void:
	_pick_a()
	_tool.tap_at(P.GRID_ORIGIN + Vector2(0.0, -500.0), 2.0)
	assert_bool(_tool.is_valid()).is_false()
	assert_str(String(_tool.verdict.reason_key)).is_equal("public_work.reject.too_long")
	assert_bool(_tool.can_confirm()).is_false()
	assert_object(_tool.confirm()).is_null()  # reddedilen taslak gönderilmez
	assert_array(_facade.public_works()).is_empty()
	_tool.tap_at(P.GRID_ORIGIN + Vector2(0.0, -5.0), 0.5)
	assert_str(String(_tool.verdict.reason_key)).is_equal("public_work.reject.too_short")


func test_confirm_submits_only_a_command_and_the_net_changes_at_the_tick_not_before() -> void:
	_pick_a()
	_tool.tap_at(NORTH, 2.0)
	var edges := _net.edges.size()
	var result := _tool.confirm()
	assert_str(String(result.status)).is_equal("queued")
	assert_int(_tool.step).is_equal(RoadDrawTool.Step.SENDING)
	assert_int(_net.edges.size()).is_equal(edges)
	assert_bool(_net.delta.ops.is_empty()).is_true()
	# Gönderim sürerken Esc yutulur, dokunuş taslağı değiştirmez.
	assert_bool(_tool.cancel()).is_true()
	assert_int(_tool.step).is_equal(RoadDrawTool.Step.SENDING)
	_facade.advance(1)
	assert_int(_net.edges.size()).is_greater(edges)
	_tool.on_events(_events())
	assert_int(_tool.step).is_equal(RoadDrawTool.Step.PICK_A)
	assert_str(String(_tool.message)).is_equal(String(RoadDrawTool.MSG_DONE))
	assert_bool(_tool.has_undoable_road()).is_true()


func test_drawing_the_same_road_again_is_a_duplicate_and_undo_removes_the_road() -> void:
	_pick_a()
	_tool.tap_at(NORTH, 2.0)
	_tool.confirm()
	_facade.advance(1)
	_tool.on_events(_events())
	var edges := _net.edges.size()
	_pick_a()
	_tool.tap_at(NORTH, 2.0)
	assert_bool(_tool.is_valid()).is_false()
	_tool.deactivate()
	var undo := _tool.undo_last()
	assert_str(String(undo.status)).is_equal("queued")
	_facade.advance(1)
	assert_int(_net.edges.size()).is_less(edges)
	assert_bool(_tool.has_undoable_road()).is_false()


func test_undo_with_nothing_built_is_rejected_with_the_sims_key_and_changes_no_state() -> void:
	var before := _facade.state_hash()
	var result := _tool.undo_last()
	assert_bool(result.is_rejected()).is_true()
	assert_str(String(result.reason_key)).is_equal("public_work.reject.nothing_to_undo")
	assert_str(String(_tool.message)).is_equal(String(RoadDrawTool.MSG_FAILED))
	assert_str(_facade.state_hash()).is_equal(before)


func test_cancel_returns_to_pick_a_and_at_pick_a_reports_nothing_cancelled() -> void:
	_pick_a()
	_tool.tap_at(NORTH, 2.0)
	assert_bool(_tool.cancel()).is_true()
	assert_int(_tool.step).is_equal(RoadDrawTool.Step.PICK_A)
	assert_object(_tool.verdict).is_null()
	assert_bool(_tool.cancel()).is_false()
	assert_int(_tool.step).is_equal(RoadDrawTool.Step.PICK_A)


func test_metro_band_locks_the_tool_and_taps_do_nothing() -> void:
	_tool.activate()
	_tool.set_band(&"metro")
	assert_bool(_tool.band_active).is_false()
	_tool.tap_at(P.GRID_ORIGIN, R)
	assert_int(_tool.step).is_equal(RoadDrawTool.Step.PICK_A)
	_tool.set_band(&"street")
	_tool.tap_at(P.GRID_ORIGIN, R)
	assert_int(_tool.step).is_equal(RoadDrawTool.Step.PICK_B)


func test_a_command_rejected_event_returns_to_review_with_the_reason() -> void:
	_pick_a()
	_tool.tap_at(NORTH, 2.0)
	_tool.confirm()
	var rejected := SimEvent.new()
	rejected.kind = SimEvent.KIND_COMMAND_REJECTED
	rejected.command_id = _tool.sending_command_id
	rejected.message_key = &"public_work.reject.duplicate"
	var events: Array[SimEvent] = [rejected]
	_tool.on_events(events)
	assert_int(_tool.step).is_equal(RoadDrawTool.Step.REVIEW)
	assert_str(String(_tool.message)).is_equal(String(RoadDrawTool.MSG_FAILED))
	assert_str(String(_tool.message_args["reason_key"])).is_equal("public_work.reject.duplicate")


# --- T-042c (D-014 §1): klasik geri al penceresi + her zaman yıkma ---

func _draw(from_a: Vector2, to_b: Vector2) -> void:
	_tool.activate()
	_tool.tap_at(from_a + Vector2(3.0, -2.0), R)
	_tool.tap_at(to_b, 2.0)
	_tool.confirm()
	_facade.advance(1)
	_tool.on_events(_events())


func test_the_undo_option_lasts_only_until_another_road_is_built_and_does_not_stack() -> void:
	var east := P.GRID_ORIGIN + Vector2(P.DX * P.COLS, 0)
	_draw(P.GRID_ORIGIN, NORTH)
	assert_bool(_tool.has_undoable_road()).is_true()
	var first_id := _facade.public_works()[0].command_id
	_draw(east, east + Vector2(0, -100))
	assert_int(_facade.public_works().size()).is_equal(2)
	assert_bool(_tool.has_undoable_road()).is_true()  # yeni yol için açık
	var undo := _tool.undo_last()
	assert_str(String(undo.status)).is_equal("queued")
	_facade.advance(1)
	assert_int(_facade.public_works().size()).is_equal(1)
	assert_int(_facade.public_works()[0].command_id).is_equal(first_id)
	assert_bool(_tool.has_undoable_road()).is_false()  # ilk yol artık geri alınamaz
	var again := _tool.undo_last()
	assert_bool(again.is_rejected()).is_true()
	assert_str(String(again.reason_key)).is_equal("public_work.reject.undo_window_closed")
	assert_str(String(_tool.message)).is_equal(String(RoadDrawTool.MSG_FAILED))


func test_demolish_is_always_available_costs_something_and_removes_the_road() -> void:
	assert_bool(_facade.attach_budget(BudgetConfig.load_default())).is_true()  # oyunda PlayableBudget takar
	_draw(P.GRID_ORIGIN, NORTH)
	var road_id := _facade.public_works()[0].command_id
	var edges := _net.edges.size()
	assert_int(_tool.demolish_cost(road_id)).override_failure_message("yer tutucu maliyet > 0").is_greater(0)
	var result := _tool.demolish_road(road_id)
	assert_str(String(result.status)).is_equal("queued")
	assert_str(String(_tool.message)).is_equal(String(RoadDrawTool.MSG_DEMOLISHED))
	_facade.advance(1)
	assert_int(_net.edges.size()).is_less(edges)
	assert_int(_facade.public_works().size()).is_equal(0)
	assert_bool(_tool.has_undoable_road()).is_false()
	assert_int(_tool.demolish_cost(road_id)).is_equal(-1)
	var again := _tool.demolish_road(road_id)
	assert_bool(again.is_rejected()).is_true()
	assert_str(String(again.reason_key)).is_equal("public_work.reject.no_such_road")
