extends GdUnitTestSuite
## T-042b UI metinleri (SIM-12, CAN-03): gerçek sim'in yazdığı yerinden edilme nedeni ve tepki kararı
## (`decision.bloc.expropriation_cause`, `decision.bloc.react.<basamak>`) Türkçe düz metinle görünür; hane sayısı
## neden kaydından okunur (UI uydurmaz); gündem öğesinde "Nedenini gör" zinciri nedene iner.
## Kaynak: MOCK fixture `mock_scenario_expropriation` (gerçek sim kayıt yapısıyla hizalı, sayılar SAHTE).
## Bu testler gündem öğesini `item_provider` ile besler; gerçek `SimFacadeImpl` + `agenda_items()` bağlantısı
## `agenda_real_sim_test.gd` ve `agenda_facade_adapter_test.gd`de sınanır.

const P := preload("res://tests/sim/public_works/public_works_support.gd")
const SCENARIO := "mock_scenario_expropriation"
const CAUSE_KEY := "decision.bloc.expropriation_cause"

var _facade: MockSimFacade


func before_test() -> void:
	InspectorHost.default_interval_msec = 0
	UiText.reset()
	UiText.report_missing = false
	_facade = UiTestSupport.mock(SCENARIO)
	var tool := RoadDrawTool.create(P.network(), _facade)
	tool.activate()
	tool.start = Vector2(-450.0, 210.0)
	tool.end = Vector2(-450.0, 110.0)
	tool.step = RoadDrawTool.Step.REVIEW
	tool.refresh_if_graph_changed()
	tool.accept_offer()
	tool.confirm()
	_facade.advance(8)


func after_test() -> void:
	UiText.reset()


func _record(decision_key: String) -> ReasonRecord:
	for id in UiTestSupport.all_reason_ids(_facade):
		var r := _facade.reason(id)
		if r != null and String(r.decision_key) == decision_key:
			return r
	return null


func _reason_panel() -> ReasonPanel:
	var ctx := UiContext.for_profile_name(&"desktop")
	var holder := Control.new()
	holder.theme = UiTheme.build(ctx)
	holder.size = Vector2(440.0, 1400.0)
	add_child(holder)
	auto_free(holder)
	var panel := ReasonPanel.create(ctx, _facade)
	holder.add_child(panel)
	panel.size = holder.size
	return panel


func test_cause_and_react_records_have_plain_turkish_decision_and_factor_texts() -> void:
	assert_object(_record(CAUSE_KEY)).is_not_null()
	assert_object(_record("decision.bloc.react.protest")).is_not_null()
	for key in ["decision.bloc.expropriation_cause.positive", "decision.bloc.expropriation_cause.negative",
			"decision.bloc.react.petition.positive", "decision.bloc.react.petition.negative",
			"decision.bloc.react.protest.positive", "decision.bloc.react.protest.negative",
			"decision.bloc.react.boycott.positive", "decision.bloc.react.boycott.negative",
			"reason.factor.displaced_household_count", "reason.factor.displaced_households",
			"reason.factor.road_proximity", "reason.factor.grievance_level", "reason.factor.satisfaction_level",
			"reason.factor.media_amplification", "reason.factor.organizer_capacity",
			"reason.factor.trust_in_player"]:
		assert_bool(UiText.has(StringName(key))).override_failure_message("metin yok: %s" % key).is_true()


func test_cause_detail_shows_the_household_count_as_a_count_not_a_fixed_point_number() -> void:
	var cause := _record(CAUSE_KEY)
	var panel := _reason_panel()
	panel.show_record(cause.id)
	var text := " ".join(Array(panel.texts()))
	assert_str(text).contains("Yerinden edilen hane sayısı")
	assert_str(text).contains("11 hane")
	assert_str(text).contains("Yola yakınlık")
	assert_str(text).contains(UiText.t(&"common.estimate"))  # yakınlık tahmin işaretli
	assert_array(Array(UiText.missing_keys())).is_empty()


func test_real_react_decision_shows_and_its_chain_leads_to_the_displacement_cause() -> void:
	var react := _record("decision.bloc.react.protest")
	assert_int(react.parent_ids.size()).is_equal(1)
	var panel := _reason_panel()
	panel.show_record(react.id)
	var text := " ".join(Array(panel.texts()))
	assert_str(text).contains("Grup protesto etti")
	assert_str(text).contains("Şikâyet düzeyi")
	assert_str(text).contains("Haberlerin etkisi")
	var parents := panel.named_buttons(ReasonPanel.NAME_PARENT)
	assert_int(parents.size()).is_equal(1)
	parents[0].pressed.emit()
	var next := " ".join(Array(panel.texts()))
	assert_str(next).contains("Yerinden edilen hane sayısı")
	assert_array(Array(UiText.missing_keys())).is_empty()


func test_group_reaction_reason_ids_start_with_the_cause_record() -> void:
	var groups := _facade.snapshot().group_reactions
	assert_int(groups.size()).is_greater(0)
	var g: GroupReactionView = groups[0]
	assert_int(g.reason_ids[0]).is_equal(_record(CAUSE_KEY).id)
	assert_bool(g.cause_refs.has("command.1")).is_true()


func _agenda_panel(reason_ids: PackedInt64Array) -> AgendaPanel:
	var ctx := UiContext.for_profile_name(&"desktop")
	var holder := Control.new()
	holder.theme = UiTheme.build(ctx)
	holder.size = Vector2(440.0, 1400.0)
	add_child(holder)
	auto_free(holder)
	var panel := AgendaPanel.create(ctx, _facade)
	holder.add_child(panel)
	panel.size = holder.size
	var it := AgendaModel.Item.new()
	it.id = &"event.pe01.1"
	it.kind = &"displacement"
	it.title_key = &"event.pe01.reason"
	it.days_left = 6
	it.reason_ids = reason_ids
	panel.set_item_provider(func(_s: SimSnapshot) -> Array[AgendaModel.Item]: return [it])
	return panel


func test_agenda_item_reads_the_household_count_from_the_cause_record_and_opens_its_chain() -> void:
	var react := _record("decision.bloc.react.protest")
	var panel := _agenda_panel(PackedInt64Array([react.id]))  # zincir: ateşleme kaydı -> ebeveyn = neden
	var text := panel.joined_text()
	assert_str(text).contains("Yerinden edilme tepkisi")
	assert_str(text).contains("Yol yüzünden 11 hane yerinden edildi.")
	var requested := []
	panel.reason_requested.connect(func(initial: Callable) -> void: requested.append(initial))
	panel.button_with_text("Nedenini gör").pressed.emit()
	assert_int(requested.size()).is_equal(1)
	var rp := _reason_panel()
	(requested[0] as Callable).call(rp)
	assert_str(" ".join(Array(rp.texts()))).contains("Grup protesto etti")


func test_agenda_item_without_a_recorded_count_shows_no_invented_number_or_button() -> void:
	var support: ReasonRecord = null
	for id in UiTestSupport.all_reason_ids(_facade):
		var r := _facade.reason(id)
		if r != null and String(r.decision_key) == "decision.municipal.expropriate":
			support = r
	var ids := PackedInt64Array([support.id]) if support != null else PackedInt64Array([9999])
	var panel := _agenda_panel(ids)
	var text := panel.joined_text()
	assert_bool(text.contains("hane yerinden edildi")).is_false()
	assert_object(panel.button_with_text("Nedenini gör")).is_null()
