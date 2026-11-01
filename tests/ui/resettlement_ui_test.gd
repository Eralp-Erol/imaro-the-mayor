# gdlint:disable=max-public-methods
extends GdUnitTestSuite
## T-065 Aşama 1 UI (D-014 §3, D-015, D-016; SIM-07, SIM-12, CAN-03) · MOCK facade ile: "Politikalar" paneli (yeniden
## iskân aç/kapa), yol önizlemesinde yeniden iskân satırları, olay/şerit metni, neden etkeni metinleri. Sayılar YALNIZ
## sim args'ından (mock'ta senaryo verisi). Gerçek sim ile uçtan uca: resettlement_real_sim_test.gd.

const P := preload("res://tests/sim/public_works/public_works_support.gd")
const SCENARIO := "mock_scenario_expropriation"
const START := Vector2(-450.0, 210.0)
const END := Vector2(-450.0, 110.0)


## Politikası olmayan dünya: araç kaydı ve panel dürüst kalmalı.
class NoPolicyFacade:
	extends MockSimFacade

	func policies() -> Array[PolicyView]:
		return []


var _facade: MockSimFacade


func before_test() -> void:
	InspectorHost.default_interval_msec = 0
	UiText.reset()
	UiText.report_missing = false
	_facade = UiTestSupport.mock(SCENARIO)


func after_test() -> void:
	UiText.reset()


func _holder(ctx: UiContext, width: float = 440.0) -> Control:
	var holder := Control.new()
	holder.theme = UiTheme.build(ctx)
	holder.size = Vector2(width, 1600.0)
	add_child(holder)
	auto_free(holder)
	return holder


func _policy_panel(profile: StringName = &"desktop", width: float = 440.0) -> PolicyPanel:
	var ctx := UiContext.for_profile_name(profile)
	var holder := _holder(ctx, width)
	var panel := PolicyPanel.create(ctx, _facade, {})
	holder.add_child(panel)
	panel.size = holder.size
	return panel


func _enable_policy(on: bool = true) -> void:
	_facade.submit_command(SimCommand.policy_set(PolicyView.ID_RESETTLEMENT, on))
	_facade.advance(1)


func _road_panel() -> RoadDrawPanel:
	var net := P.network()
	var tool := RoadDrawTool.create(net, _facade)
	tool.activate()
	tool.start = START
	tool.end = END
	tool.step = RoadDrawTool.Step.REVIEW
	tool.refresh_if_graph_changed()
	var ctx := UiContext.for_profile_name(&"desktop")
	var holder := _holder(ctx)
	var panel := RoadDrawPanel.create(ctx, _facade, tool)
	holder.add_child(panel)
	panel.size = holder.size
	return panel


# --- Politikalar paneli ---

func test_policy_panel_states_what_happens_when_on_and_when_off_in_plain_turkish() -> void:
	var panel := _policy_panel()
	var text := panel.joined_text()
	assert_str(text).contains("Yeniden iskân")
	assert_str(text).contains("Durum")
	assert_str(text).contains("Kapalı")
	assert_str(text).contains(UiText.t(&"policy.resettlement.when_on"))
	assert_str(text).contains(UiText.t(&"policy.resettlement.when_off"))
	assert_str(text).contains(UiText.t(&"policy.permanent_note"))
	assert_array(Array(UiText.missing_keys())).is_empty()
	for raw in ["policy.", "resettlement", "_"]:
		assert_bool(text.contains(raw)).override_failure_message("ham anahtar sızdı: %s" % raw).is_false()


func test_policy_button_turns_the_policy_on_through_policy_set_and_waits_for_the_sim() -> void:
	var panel := _policy_panel()
	var b := panel.toggle_button()
	assert_object(b).is_not_null()
	assert_str(b.text).is_equal("Yeniden iskânı aç")
	b.pressed.emit()
	# Komut kuyruğa girdi; sim henüz değişmedi: panel iyimser davranmaz (durum hâlâ Kapalı, istek bekliyor).
	assert_bool(_facade.policies()[0].enabled).is_false()
	assert_str(panel.joined_text()).contains(UiText.t(&"policy.pending"))
	assert_bool(panel.toggle_button().disabled).is_true()
	_facade.advance(1)
	panel.refresh()
	assert_bool(_facade.policies()[0].enabled).is_true()
	assert_str(panel.toggle_button().text).is_equal("Yeniden iskânı kapat")
	assert_bool(panel.toggle_button().disabled).is_false()
	assert_str(panel.joined_text()).not_contains(UiText.t(&"policy.pending"))


func test_policy_button_turns_it_back_off() -> void:
	_enable_policy(true)
	var panel := _policy_panel()
	assert_str(panel.status_text()).is_equal("Açık")
	panel.toggle_button().pressed.emit()
	_facade.advance(1)
	panel.refresh()
	assert_bool(_facade.policies()[0].enabled).is_false()
	assert_str(panel.status_text()).is_equal("Kapalı")


func test_a_rejected_policy_request_shows_the_sims_reason_not_a_key() -> void:
	var panel := _policy_panel()
	_enable_policy(true)   # panel bayat: sim zaten açık
	panel.toggle_button().pressed.emit()
	var text := panel.joined_text()
	assert_str(text).contains(UiText.t(&"policy.why.unchanged"))
	assert_str(text).not_contains("policy.unchanged")


func test_without_a_policy_in_the_world_the_panel_says_not_built_and_has_no_button() -> void:
	_facade = NoPolicyFacade.new(MockScenario.load_file(UiTestSupport.FIXTURES + SCENARIO + ".json"))
	var panel := _policy_panel()
	assert_object(panel.toggle_button()).is_null()
	assert_str(panel.state_view.visible_text()).contains(UiText.t(&"policy.not_built"))


func test_policy_tool_is_registered_only_when_the_world_has_a_policy() -> void:
	var hud := HudRoot.new()
	add_child(hud)
	auto_free(hud)
	hud.setup(_facade, UiTestSupport.platform(&"desktop"))
	DecisionPanels.attach(hud, _facade, Callable(), false)
	hud.toolbar.select_mode(ModeToolbar.MODE_MANAGE)   # araç düğmeleri yalnız etkin modun
	assert_object(hud.toolbar.tool_button(ModeToolbar.TOOL_POLICY)).is_not_null()
	var bare := HudRoot.new()
	add_child(bare)
	auto_free(bare)
	var none := NoPolicyFacade.new(MockScenario.load_file(UiTestSupport.FIXTURES + SCENARIO + ".json"))
	bare.setup(none, UiTestSupport.platform(&"desktop"))
	DecisionPanels.attach(bare, none, Callable(), false)
	bare.toolbar.select_mode(ModeToolbar.MODE_MANAGE)
	assert_object(bare.toolbar.tool_button(ModeToolbar.TOOL_POLICY)).is_null()


func test_selecting_the_policy_tool_opens_the_policy_panel() -> void:
	var hud := HudRoot.new()
	add_child(hud)
	auto_free(hud)
	hud.setup(_facade, UiTestSupport.platform(&"desktop"))
	var decisions := DecisionPanels.attach(hud, _facade, Callable(), false)
	assert_bool(decisions.on_tool_selected(ModeToolbar.TOOL_POLICY)).is_true()
	assert_str(String(hud.panel_id())).is_equal("policy")
	assert_object(decisions.policy_panel()).is_not_null()


func test_policy_pending_survives_a_profile_rebuild() -> void:
	var hud := HudRoot.new()
	add_child(hud)
	auto_free(hud)
	hud.setup(_facade, UiTestSupport.platform(&"desktop"))
	var decisions := DecisionPanels.attach(hud, _facade, Callable(), false)
	decisions.open_policy()
	decisions.policy_panel().toggle_button().pressed.emit()
	hud.apply_profile(UiTestSupport.platform(&"touch"))
	assert_str(decisions.policy_panel().joined_text()).contains(UiText.t(&"policy.pending"))
	await get_tree().process_frame   # eski HUD düğümleri (queue_free) bu karede serbest kalır


func test_touch_policy_panel_fits_a_narrow_slot_with_44pt_targets_and_8pt_gaps() -> void:
	var panel := _policy_panel(&"touch", 389.0)
	assert_array(Array(TouchAudit.violations(panel, 389.0, 44.0))).is_empty()
	assert_float(TouchAudit.min_button_gap(panel)).is_greater_equal(8.0)


func test_ipad_landscape_hud_shows_the_policy_button_without_scrolling_and_nothing_overflows() -> void:
	for size: Vector2 in [Vector2(1024.0, 768.0), Vector2(768.0, 1024.0)]:
		var hud := HudRoot.new()
		add_child(hud)
		hud.set_anchors_preset(Control.PRESET_TOP_LEFT)
		hud.setup(_facade, UiTestSupport.platform(&"touch"))
		hud.size = size
		auto_free(hud)
		var decisions := DecisionPanels.attach(hud, _facade, Callable(), false)
		decisions.open_policy()
		hud.refresh()
		await get_tree().process_frame
		await get_tree().process_frame
		var button := decisions.policy_panel().toggle_button()
		var panel_rect := hud.panel.get_global_rect()
		var button_rect := button.get_global_rect()
		assert_float(button_rect.end.y).override_failure_message("%s: düğme panelin altından taştı" % str(size)) \
				.is_less_equal(panel_rect.end.y + 0.5)
		assert_float(button_rect.end.x).is_less_equal(panel_rect.end.x + 0.5)
		assert_float(minf(button_rect.size.x, button_rect.size.y)).is_greater_equal(44.0)
		assert_float(panel_rect.end.x).is_less_equal(size.x + 0.5)
		assert_float(panel_rect.end.y).is_less_equal(size.y + 0.5)


# --- Yol önizlemesi ---

func test_road_preview_with_the_policy_on_says_housed_unhoused_and_the_indicative_cost() -> void:
	_enable_policy(true)
	var panel := _road_panel()
	panel.accept_button().pressed.emit()
	var text := panel.joined_text()
	assert_str(text).contains("2 bina yıkılacak, 11 hane yerinden edilecek.")
	assert_str(text).contains("7 haneye ev ayrıldı")
	assert_str(text).contains("4 hane için ev yok")
	assert_str(text).contains("Yol yine yapılır")
	assert_str(text).contains("Yeniden iskân bedeli: 5.200 ¤ (gösterge)")
	assert_str(text).contains(UiText.t(&"resettlement.preview.relief"))
	assert_str(text).not_contains("₺")
	assert_str(text).not_contains(UiText.t(&"resettlement.preview.off"))
	assert_array(Array(UiText.missing_keys())).is_empty()


func test_road_preview_numbers_follow_the_sim_args() -> void:
	var args := {"displaced_households": 20, "resettlement_applied": true, "rehoused_households": 12,
			"unplaced_households": 8, "resettlement_cost": 900}
	var lines := ExpropriationText.resettlement_lines(args)
	assert_str(" ".join(lines)).contains("12 haneye ev ayrıldı")
	assert_str(" ".join(lines)).contains("8 hane için ev yok")
	assert_str(" ".join(lines)).contains("900 ¤")
	args["unplaced_households"] = 0
	assert_str(" ".join(ExpropriationText.resettlement_lines(args))).not_contains("için ev yok")
	args["rehoused_households"] = 0
	args["unplaced_households"] = 20
	var none_housed := " ".join(ExpropriationText.resettlement_lines(args))
	assert_str(none_housed).contains("hiçbir haneye ev ayrılamadı")
	assert_str(none_housed).contains("20 hane için ev yok")
	assert_str(none_housed).not_contains(UiText.t(&"resettlement.preview.relief"))


func test_road_preview_with_the_policy_off_keeps_todays_text_and_names_the_off_state_once() -> void:
	var panel := _road_panel()
	panel.accept_button().pressed.emit()
	var text := panel.joined_text()
	assert_str(text).contains("2 bina yıkılacak, 11 hane yerinden edilecek.")
	assert_str(text).contains("Bedel: henüz kurulmadı.")
	assert_str(text).not_contains("ev ayrıldı")
	assert_str(text).not_contains("gösterge")
	assert_str(text).contains(UiText.t(&"resettlement.preview.off"))


func test_no_resettlement_line_without_displaced_households() -> void:
	assert_bool(ExpropriationText.resettlement_lines({"displaced_households": 0}).is_empty()).is_true()
	assert_bool(ExpropriationText.resettlement_off_needed({"displaced_households": 0}, false)).is_false()
	assert_bool(ExpropriationText.resettlement_off_needed({"displaced_households": 3}, false)).is_true()
	assert_bool(ExpropriationText.resettlement_off_needed({"displaced_households": 3,
			"resettlement_applied": true}, false)).is_false()
	assert_bool(ExpropriationText.resettlement_off_needed({"displaced_households": 3}, true)).is_false()


# --- Olay / şerit metni ---

func _event(key: StringName, args: Dictionary, kind: StringName = SimEvent.KIND_PUBLIC_WORK_EXPROPRIATED) -> SimEvent:
	return SimEvent.from_dict({"seq": 1, "tick": 3, "kind": kind, "message_key": key, "args": args, "command_id": 4})


func test_expropriated_event_says_moved_and_unplaced_only_when_the_sim_recorded_an_allocation() -> void:
	var base := {"built_parcels": 2, "households": 11, "parcels": 3}
	var plain := UiText.event_text(_event(&"event.road.expropriated", base))
	assert_str(plain).is_equal("Yol arsaları kamulaştırdı: 2 bina yıkıldı, 11 hane yerinden edildi")
	var args := base.duplicate()
	args.merge({"resettlement_applied": true, "rehoused_households": 7, "unplaced_households": 4,
			"resettlement_cost": 5200})
	var text := UiText.event_text(_event(&"event.road.expropriated", args))
	assert_str(text).contains("7 hane taşındı")
	assert_str(text).contains("4 aile için ev yok")
	var suffix := ExpropriationText.strip_suffix(_event(&"event.road.expropriated", args))
	assert_str(suffix).contains("7 hane taşındı")
	assert_str(suffix).contains("4 aile için ev yok")
	assert_str(ExpropriationText.strip_suffix(_event(&"event.road.expropriated", base))).not_contains("taşındı")
	args["unplaced_households"] = 0
	assert_str(UiText.event_text(_event(&"event.road.expropriated", args))).not_contains("ev yok")


func test_restored_event_names_the_returned_households_only_when_given() -> void:
	var args := {"built_parcels": 2, "households": 11, "parcels": 3}
	assert_str(UiText.event_text(_event(&"event.road.restored", args, SimEvent.KIND_PUBLIC_WORK_RESTORED))) \
			.not_contains("döndü")
	args["rehoused_returned"] = 5
	assert_str(UiText.event_text(_event(&"event.road.restored", args, SimEvent.KIND_PUBLIC_WORK_RESTORED))) \
			.contains("5 hane eski bölgesine döndü")


func test_policy_changed_event_has_plain_text_for_both_directions() -> void:
	var on := UiText.event_text(_event(&"event.policy.changed", {"policy_id": "resettlement", "enabled": true,
			"previous": false}, SimEvent.KIND_POLICY_CHANGED))
	var off := UiText.event_text(_event(&"event.policy.changed", {"policy_id": "resettlement", "enabled": false,
			"previous": true}, SimEvent.KIND_POLICY_CHANGED))
	assert_str(on).is_equal("Yeniden iskân politikası açıldı")
	assert_str(off).is_equal("Yeniden iskân politikası kapatıldı")


func test_mock_policy_event_reaches_the_strip_text_without_a_raw_key() -> void:
	_enable_policy(true)
	var found := false
	for e in _facade.events_since(0):
		if e.kind == SimEvent.KIND_POLICY_CHANGED:
			found = true
			assert_str(NotificationStrip.strip_text(e)).is_equal("Yeniden iskân politikası açıldı")
	assert_bool(found).is_true()


# --- Neden etkenleri ve karar metinleri ---

func test_reason_texts_exist_for_the_resettlement_factors_and_the_policy_decision() -> void:
	for key in ["reason.factor.rehoused_households", "reason.factor.unplaced_households",
			"reason.factor.policy_enabled", "decision.municipal.policy_set.positive",
			"decision.municipal.policy_set.negative", "event.policy.changed", "tool.policy", "policy.title"]:
		assert_bool(UiText.has(StringName(key))).override_failure_message("metin yok: %s" % key).is_true()
