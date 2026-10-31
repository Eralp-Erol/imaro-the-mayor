# gdlint:disable=max-public-methods
extends GdUnitTestSuite
## T-042b UI adımı (D-011, ADR-0005 Ek F v1.5; CAN-03, SIM-12) · Kamulaştırma arayüzü MOCK fixture ile (dünya adımı
## bitmeden): teklif ve önizleme sayıları YALNIZ sim args'ından, "Bedel: henüz kurulmadı", iki adımlı onay, yeni ret
## metinleri, kamulaştırma kapalıyken teklif YOK, geri alma onayı, denetçide "Kamulaştırıldı ← Yol", şerit özeti.
## Gerçek dünya bağdaştırıcısı ve gerçek ekran görüntüsü YOK (dünya adımı bitmedi); burada panel düğümleri sınanır.

const P := preload("res://tests/sim/public_works/public_works_support.gd")
const SCENARIO := "mock_scenario_expropriation"
const START := Vector2(-450.0, 210.0)
const END := Vector2(-450.0, 110.0)
const DESKTOP := Vector2(1600.0, 900.0)

var _facade: MockSimFacade
var _net: WorldNetwork
var _tool: RoadDrawTool


func before_test() -> void:
	InspectorHost.default_interval_msec = 0
	UiText.reset()
	UiText.report_missing = false
	_facade = UiTestSupport.mock(SCENARIO)
	_net = P.network()
	_tool = RoadDrawTool.create(_net, _facade)
	_tool.activate()


func after_test() -> void:
	UiText.reset()


## Taslağı doğrudan REVIEW'a kurar (fixture noktaları; dünya yapışması bu testin konusu değil) ve sim'e sordurur.
func _review(facade: SimFacade = null, a: Vector2 = START, b: Vector2 = END) -> void:
	if facade != null:
		_tool = RoadDrawTool.create(_net, facade)
		_tool.activate()
		_facade = facade as MockSimFacade
	_tool.start = a
	_tool.end = b
	_tool.step = RoadDrawTool.Step.REVIEW
	_tool.refresh_if_graph_changed()


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


func _offer_args() -> Dictionary:
	return _tool.verdict.args


# --- teklif (crosses_parcels reddi) ---

func test_crossing_road_shows_the_sims_offer_with_numbers_from_args_and_an_unbuilt_cost() -> void:
	_review()
	assert_bool(_tool.is_valid()).is_false()
	assert_str(String(_tool.verdict.reason_key)).is_equal("public_work.reject.crosses_parcels")
	var args := _offer_args()
	var text := _panel().joined_text()
	assert_str(text).contains(UiText.t(&"expropriation.offer_title"))
	# Sayılar sim args'ından: 2 yapılı arsa, 11 hane (fixture).
	assert_str(text).contains("%d bina yıkılacak, %d hane yerinden edilecek." % [
			int(args["taken_built_parcels"]), int(args["displaced_households"])])
	assert_str(text).contains("Bedel: henüz kurulmadı.")
	assert_str(text).contains(UiText.t(&"expropriation.nearby", {"parcels": int(args["nearby_parcels"]),
			"households": int(args["nearby_households"])}))
	assert_str(text).contains("F1 (3 arsa)")
	assert_array(Array(UiText.missing_keys())).is_empty()


func test_numbers_follow_the_sim_args_not_the_ui() -> void:
	_review()
	var args := _offer_args().duplicate(true)
	args["taken_built_parcels"] = 7
	args["displaced_households"] = 41
	assert_str(ExpropriationText.impact_line(args)).is_equal("7 bina yıkılacak, 41 hane yerinden edilecek.")
	args["taken_built_parcels"] = 0
	args["displaced_households"] = 0
	args["taken_parcels"] = 2
	assert_str(ExpropriationText.impact_line(args)).is_equal("Yıkılacak bina yok; 2 boş arsa alınacak.")
	assert_bool(ExpropriationText.demolishes(args)).is_false()


func test_offer_has_one_primary_accept_button_and_no_dead_confirm_and_no_currency() -> void:
	_review()
	var panel := _panel()
	assert_object(panel.accept_button()).is_not_null()
	assert_str(panel.accept_button().text).is_equal(UiText.t(&"expropriation.accept"))
	assert_bool(panel.accept_button().disabled).is_false()
	assert_object(panel.confirm_button()).is_null()   # teklif varken ölü "Onayla" yok
	var text := panel.joined_text()
	for forbidden in ["₺", "TL", "lira"]:
		assert_bool(text.contains(forbidden)).is_false()
	assert_bool(_tool.can_confirm()).is_false()


func test_without_an_offer_in_the_reject_args_no_offer_is_shown_and_the_text_says_not_yet() -> void:
	# Kamulaştırma kapalı/dünya sunmuyor: sim ret args'ına teklif koymaz (args boş).
	_review(UiTestSupport.mock("mock_scenario_public_road"), Vector2(-400.0, 210.0), Vector2(-400.0, 110.0))
	assert_str(String(_tool.verdict.reason_key)).is_equal("public_work.reject.crosses_parcels")
	assert_bool(_tool.offer().is_empty()).is_true()
	var panel := _panel()
	assert_object(panel.accept_button()).is_null()
	assert_str(panel.joined_text()).contains("kamulaştırma henüz yok")
	assert_str(panel.joined_text()).not_contains(UiText.t(&"expropriation.offer_title"))


# --- iki adımlı onay ---

func test_accepting_the_offer_asks_the_sim_again_and_requires_a_distinct_demolition_confirm() -> void:
	_review()
	var panel := _panel()
	panel.accept_button().pressed.emit()
	assert_bool(_tool.expropriate).is_true()
	assert_bool(_tool.is_valid()).is_true()
	assert_bool(_tool.demolishes()).is_true()
	assert_bool(bool(_tool.preview_args()["expropriate"])).is_true()
	assert_object(panel.accept_button()).is_null()
	assert_object(panel.back_button()).is_not_null()
	assert_str(panel.confirm_button().text).is_equal(UiText.t(&"expropriation.confirm"))   # "Yıkımı onayla"
	var text := panel.joined_text()
	assert_str(text).contains("2 bina yıkılacak, 11 hane yerinden edilecek.")
	assert_str(text).contains("Bedel: henüz kurulmadı.")
	assert_str(text).contains(UiText.t(&"expropriation.undo_note"))
	assert_str(text).contains(UiText.t(&"expropriation.valid_title"))
	# Hiçbir komut sim'e gitmedi (mock kuyruğu boş).
	assert_int(_facade.public_works().size()).is_equal(0)


func test_demolishing_road_is_not_confirmed_by_a_stray_second_tap_on_the_same_point() -> void:
	_review()
	_tool.accept_offer()
	_tool.tap_at(END, 12.0)   # aynı noktaya yeniden dokunuş
	assert_int(_tool.step).is_equal(RoadDrawTool.Step.REVIEW)
	assert_bool(_tool.expropriate).is_true()   # bitiş değişmedi: kabul düşmedi
	assert_int(_facade.public_works().size()).is_equal(0)


func test_changing_the_end_drops_the_acceptance_so_the_new_draft_is_offered_again() -> void:
	_review()
	_tool.accept_offer()
	_tool.tap_at(END + Vector2(0.0, -50.0), 12.0)
	assert_bool(_tool.expropriate).is_false()


func test_back_button_withdraws_the_acceptance_and_shows_the_offer_again() -> void:
	_review()
	var panel := _panel()
	panel.accept_button().pressed.emit()
	panel.back_button().pressed.emit()
	assert_bool(_tool.expropriate).is_false()
	assert_object(panel.accept_button()).is_not_null()


func test_confirming_sends_the_expropriate_flag_and_the_mock_takes_the_parcels() -> void:
	_review()
	_tool.accept_offer()
	var result := _tool.confirm()
	assert_object(result).is_not_null()
	assert_bool(result.is_rejected()).is_false()
	_facade.advance(1)
	assert_bool(bool(_facade.public_works()[0].expropriated)).is_true()
	assert_str(String(_facade.parcel_views(PackedInt64Array([1]))[0].development)).is_equal("taken")


func test_enter_and_chip_path_uses_can_confirm_and_the_chip_names_the_demolition() -> void:
	_review()
	var ctx := UiContext.for_profile_name(&"desktop")
	var chip := RoadConfirmChip.create(ctx)
	add_child(chip)
	auto_free(chip)
	var before := chip.text
	_tool.accept_offer()
	chip.set_demolition(_tool.demolishes())
	assert_str(chip.text).is_equal(UiText.t(&"road.chip_demolish"))
	assert_str(chip.text).is_not_equal(before)
	chip.set_demolition(false)
	assert_str(chip.text).is_equal(before)


func test_touch_targets_for_the_expropriation_buttons_are_at_least_44() -> void:
	_review()
	var panel := _panel(&"touch", Vector2(520.0, 1200.0))
	var accept := panel.accept_button()
	assert_float(accept.get_combined_minimum_size().y).is_greater_equal(44.0)
	accept.pressed.emit()
	assert_float(panel.confirm_button().get_combined_minimum_size().y).is_greater_equal(44.0)
	assert_float(panel.back_button().get_combined_minimum_size().y).is_greater_equal(44.0)
	assert_str(panel.joined_text()).contains(UiText.t(&"expropriation.confirm_hint_touch"))


# --- yeni ret metinleri ---

func test_every_new_reject_text_and_event_text_exists_in_turkish() -> void:
	var rejects := {
		"public_work.reject.protected_structure": {"protected_parcels": 2, "protected_parcel_id": 5, "taken_parcels": 3},
		"public_work.reject.expropriation_disabled": {},
		"public_work.reject.expropriation_changed": {},
		"public_work.reject.economy_not_started": {},
	}
	for key: String in rejects:
		assert_bool(UiText.has(StringName(key))).override_failure_message("metin yok: %s" % key).is_true()
		var text := UiText.reject_reason(StringName(key), rejects[key])
		assert_str(text).is_not_empty()
		assert_bool(text.contains("{")).override_failure_message("yer tutucu açıkta: %s" % text).is_false()
	var protected_key := "public_work.reject.protected_structure"
	assert_str(UiText.reject_reason(StringName(protected_key), rejects[protected_key])).contains("2 korunan arsa")
	assert_str(UiText.reject_reason(&"public_work.reject.economy_not_started")).contains("henüz işleyişe başlamadı")
	assert_array(Array(UiText.missing_keys())).is_empty()


func test_crosses_parcels_without_offer_keeps_the_not_yet_text_and_with_offer_uses_the_offer_text() -> void:
	assert_str(UiText.reject_reason(&"public_work.reject.crosses_parcels", {})).contains("kamulaştırma henüz yok")
	assert_str(UiText.reject_reason(&"public_work.reject.crosses_parcels", {"taken_parcels": 3})) \
			.contains("Kamulaştırarak geçilebilir")


func test_protected_structure_reject_offers_no_expropriation() -> void:
	var args := {"protected_parcels": 1, "protected_parcel_id": 9, "taken_parcels": 2}
	assert_bool(ExpropriationText.is_offer(&"public_work.reject.protected_structure", args)).is_false()
	assert_str(String(ExpropriationText.reject_key(&"public_work.reject.protected_structure", args))) \
			.is_equal("public_work.reject.protected_structure")


# --- geri alma onayı ---

func test_undoing_a_demolishing_road_needs_a_second_step_that_states_the_reaction_stays() -> void:
	_review()
	_tool.accept_offer()
	_tool.confirm()
	_facade.advance(1)
	_tool.step = RoadDrawTool.Step.PICK_A
	var panel := _panel()
	assert_object(panel.undo_button()).is_not_null()
	panel.undo_button().pressed.emit()
	assert_bool(panel.undo_pending()).is_true()
	assert_int(_facade.public_works().size()).is_equal(1)   # henüz geri alınmadı
	var text := panel.joined_text()
	assert_str(text).contains("Yıkımlı yolu geri almak binaları geri getirir, halkın tepkisi geri gelmez.")
	assert_str(text).contains("Geri gelecek: 2 bina, 12 konut birimi, 4 ticaret birimi.")
	panel.undo_keep_button().pressed.emit()
	assert_bool(panel.undo_pending()).is_false()
	assert_int(_facade.public_works().size()).is_equal(1)
	panel.undo_button().pressed.emit()
	panel.undo_confirm_button().pressed.emit()
	_facade.advance(1)
	assert_int(_facade.public_works().size()).is_equal(0)
	assert_str(String(_facade.parcel_views(PackedInt64Array([1]))[0].development)).is_equal("built")


func test_undoing_a_plain_road_stays_one_step() -> void:
	var f := UiTestSupport.mock("mock_scenario_public_road")
	_review(f)
	assert_bool(_tool.is_valid()).is_true()
	_tool.confirm()
	f.advance(1)
	_tool.step = RoadDrawTool.Step.PICK_A
	var panel := _panel()
	panel.undo_button().pressed.emit()
	assert_bool(panel.undo_pending()).is_false()
	f.advance(1)
	assert_int(f.public_works().size()).is_equal(0)


# --- denetçi: Kamulaştırıldı ← Yol ---

func test_inspector_shows_taken_parcel_with_the_road_and_its_day() -> void:
	_review()
	_tool.accept_offer()
	_tool.confirm()
	_facade.advance(1)
	var hud := HudRoot.new()
	add_child(hud)
	hud.setup(_facade, UiTestSupport.platform(&"desktop"))
	hud.set_anchors_preset(Control.PRESET_TOP_LEFT)
	hud.size = DESKTOP
	hud.refresh()
	auto_free(hud)
	var host := InspectorHost.attach(hud, _facade, func(_c: Callable) -> void: pass, func(_id: int) -> void: pass)
	host.set_band(&"street")
	host.select_parcel(1)
	var panel := host.panel()
	assert_object(panel).is_not_null()
	var w := _facade.public_works()[0]
	var expected := UiText.t(&"inspector.taken_line", {"date": UiText.tick_date(w.tick)})
	assert_str(panel.joined_text()).contains(expected)
	assert_str(expected).starts_with("Kamulaştırıldı ← Yol")
	assert_str(panel.joined_text()).contains(UiText.t(&"inspector.taken_owner"))
	# Alınmayan yakın parsel bu satırı taşımaz.
	host.select_parcel(4)
	assert_str(host.panel().joined_text()).not_contains("Kamulaştırıldı ← Yol")


# --- şerit: gerçek olaylar, tek satır ---

func _strip() -> NotificationStrip:
	var s := NotificationStrip.create(UiContext.for_profile_name(&"desktop"))
	add_child(s)
	return auto_free(s)


func test_strip_merges_the_demolition_summary_into_the_road_built_row_from_real_event_args() -> void:
	_review()
	_tool.accept_offer()
	_tool.confirm()
	_facade.advance(1)
	var strip := _strip()
	var events := _facade.events_since(0)
	strip.push_events(events)
	var taken: SimEvent = null
	for e in events:
		if e.kind == SimEvent.KIND_PUBLIC_WORK_EXPROPRIATED:
			taken = e
	assert_object(taken).is_not_null()
	var expected := UiText.t(&"strip.expropriation_suffix", taken.args)
	var rows := strip.row_texts()
	var with_summary := 0
	for r in rows:
		if r.contains(expected):
			with_summary += 1
	assert_int(with_summary).is_equal(1)
	# Kamulaştırma olayının kendi satırı kalmaz (aynı komutun yol satırı özetini taşır).
	for r in rows:
		assert_bool(r == UiText.event_text(taken)).is_false()
	assert_str(expected).contains("%d hane yerinden edildi" % int(taken.args["households"]))


func test_group_reaction_after_displacement_reaches_the_strip_with_a_why_button() -> void:
	_review()
	_tool.accept_offer()
	_tool.confirm()
	_facade.advance(8)
	var strip := _strip()
	strip.push_events(_facade.events_since(0))
	var found := false
	for r in strip.row_texts():
		if r.contains(UiText.t(&"event.group.protest")):
			found = true
	assert_bool(found).override_failure_message("halk tepkisi şeritte yok").is_true()


func test_restored_event_text_says_buildings_return_and_reaction_does_not() -> void:
	_review()
	_tool.accept_offer()
	_tool.confirm()
	_facade.advance(1)
	_facade.submit_command(SimCommand.public_work_undo_last())
	_facade.advance(1)
	var restored: SimEvent = null
	for e in _facade.events_since(0):
		if e.kind == SimEvent.KIND_PUBLIC_WORK_RESTORED:
			restored = e
	assert_object(restored).is_not_null()
	var text := UiText.event_text(restored)
	assert_str(text).contains("2 bina geri geldi")
	assert_str(text).contains("Halkın tepkisi geri gelmedi")
	assert_array(Array(UiText.missing_keys())).is_empty()


func test_reason_texts_for_the_expropriation_records_exist() -> void:
	for key in ["decision.municipal.expropriate.positive", "decision.municipal.restore_parcel.positive",
			"reason.factor.road_work", "reason.factor.demolished_units", "reason.factor.displaced_households",
			"reason.factor.road_proximity", "parcel.development.taken"]:
		assert_bool(UiText.has(StringName(key))).override_failure_message("metin yok: %s" % key).is_true()


func test_no_new_private_building_verb_appears_in_the_expropriation_ui() -> void:
	_review()
	var panel := _panel()
	var all := panel.joined_text() + " ".join(Array(UiTestSupport.button_texts(panel)))
	for forbidden in ["Bina yerleştir", "Bina yap", "Özel bina"]:
		assert_bool(all.contains(forbidden)).is_false()
