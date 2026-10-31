extends GdUnitTestSuite
## T-042b gündem bağdaştırıcısı (D-008 son adım): sözleşmenin `SimFacade.agenda_items()` öğeleri, mevcut gündem
## modeline/paneline ince bir köprüyle girer. Kaynak: MOCK fixture `mock_scenario_expropriation` (sayılar SAHTE).
## Gerçek `SimFacadeImpl` ile uçtan uca doğrulama: `agenda_real_sim_test.gd`.

const P := preload("res://tests/sim/public_works/public_works_support.gd")
const SCENARIO := "mock_scenario_expropriation"

var _facade: MockSimFacade


func before_test() -> void:
	InspectorHost.default_interval_msec = 0
	UiText.reset()
	UiText.report_missing = false
	_facade = UiTestSupport.mock(SCENARIO)


func after_test() -> void:
	UiText.reset()


func _build_road_and_react() -> void:
	var tool := RoadDrawTool.create(P.network(), _facade)
	tool.activate()
	tool.start = Vector2(-450.0, 210.0)
	tool.end = Vector2(-450.0, 110.0)
	tool.step = RoadDrawTool.Step.REVIEW
	tool.refresh_if_graph_changed()
	tool.accept_offer()
	tool.confirm()
	_facade.advance(12)


func _panel() -> AgendaPanel:
	var ctx := UiContext.for_profile_name(&"desktop")
	var holder := Control.new()
	holder.theme = UiTheme.build(ctx)
	holder.size = Vector2(440.0, 1400.0)
	add_child(holder)
	auto_free(holder)
	var panel := AgendaPanel.create(ctx, _facade)
	holder.add_child(panel)
	panel.size = holder.size
	return panel


func test_without_facade_items_derive_all_equals_the_council_derivation() -> void:
	var snap := _facade.snapshot()
	var base := AgendaModel.derive(snap)
	var all := AgendaModel.derive_all(_facade, snap)
	assert_int(all.size()).is_equal(base.size())
	for i in base.size():
		assert_str(String(all[i].id)).is_equal(String(base[i].id))


func test_a_facade_item_becomes_a_displacement_agenda_item_with_the_chain_ids() -> void:
	_build_road_and_react()
	var source := _facade.agenda_items()
	assert_int(source.size()).is_equal(1)
	var items := AgendaModel.derive_all(_facade, _facade.snapshot())
	assert_int(items.size()).is_equal(1)
	var it := items[0]
	assert_str(String(it.id)).is_equal(String(source[0].ref()))
	assert_str(String(it.kind)).is_equal("displacement")
	assert_str(String(it.title_key)).is_equal(String(source[0].title_key))
	assert_array(Array(it.reason_ids)).is_equal(Array(source[0].reason_ids))
	assert_int(it.deadline_tick).is_equal(source[0].deadline_tick)
	assert_int(it.days_left).is_equal(maxi(0, source[0].deadline_tick - _facade.current_tick()))
	assert_bool(it.answerable()).is_false()  # yanıt komutu yok: seçenek/ertele düğmesi uydurulmaz


func test_items_are_ordered_by_deadline_across_votes_and_facade_items() -> void:
	_build_road_and_react()
	var items := AgendaModel.derive_all(_facade, _facade.snapshot())
	for i in range(1, items.size()):
		assert_bool(items[i - 1].deadline_tick <= items[i].deadline_tick).is_true()


func test_the_panel_shows_the_real_displacement_item_and_its_household_count() -> void:
	_build_road_and_react()
	var panel := _panel()
	var text := panel.joined_text()
	assert_str(text).contains("Yerinden edilme tepkisi")
	assert_str(text).contains("Yol yüzünden 11 hane yerinden edildi.")
	assert_object(panel.button_with_text("Nedenini gör")).is_not_null()
	assert_array(Array(UiText.missing_keys())).is_empty()


func test_the_panel_is_empty_before_the_reaction_and_invents_no_item() -> void:
	var panel := _panel()
	assert_bool(panel.joined_text().contains("hane yerinden edildi")).is_false()
	assert_object(panel.button_with_text("Nedenini gör")).is_null()
