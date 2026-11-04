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
	assert_bool(it.answerable()).is_true()  # fixture PE-01 üç seçenek verir (sim'in listesi aynen)


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


# --- Yanıt kartları (mock yolu) ---

func test_the_item_carries_the_sim_options_and_is_answerable() -> void:
	_build_road_and_react()
	var it := AgendaModel.derive_all(_facade, _facade.snapshot())[0]
	assert_bool(it.answerable()).is_true()
	assert_int(it.agenda_item_id).is_equal(_facade.agenda_items()[0].item_id)
	var ids: Array = []
	for o in it.options:
		ids.append(String(o.id))
	assert_array(ids).is_equal(["listen", "remedy", "reverse"])


func test_option_cards_show_plain_effects_without_cost_numbers_or_defer() -> void:
	_build_road_and_react()
	var text := _panel().joined_text()
	assert_str(text).contains("Dinleme toplantısı yap")
	assert_str(text).contains("Mahalle şikâyeti azalır (bu konuda); 7 gün sonra başlar, 90 gün sürer")
	assert_str(text).contains("Yatırımcı riski artar (bu bölgede); hemen başlar, 180 gün sürer")
	assert_str(text).contains("Güven artar (bu grupta); 7 gün sonra başlar, tek seferlik")
	assert_str(text).contains("Yolu geri almaz")  # "Kararı gözden geçir" gerçek etkisini söyler
	assert_bool(text.contains("Bedel")).is_false()
	assert_bool(text.contains("Ertele")).is_false()
	assert_array(Array(UiText.missing_keys())).is_empty()


func test_locked_option_is_grey_with_its_reason_and_cannot_be_sent() -> void:
	_build_road_and_react()
	var panel := _panel()
	var item := _facade.agenda_items()[0]
	var remedy := panel.named_buttons("choose_%s_remedy" % item.ref())[0]
	assert_bool(remedy.disabled).is_true()
	assert_str(panel.joined_text()).contains("Kilitli: ilçe işleri yetkisi gerekir.")
	var chosen := []
	panel.option_chosen.connect(func(i: StringName, o: StringName, _r: CommandResult) -> void: chosen.append([i, o]))
	remedy.pressed.emit()
	assert_array(chosen).is_empty()  # kilitliye komut gitmez


func test_choose_submits_agenda_respond_and_the_item_leaves_on_the_next_tick() -> void:
	_build_road_and_react()
	var panel := _panel()
	var item := _facade.agenda_items()[0]
	var chosen := []
	panel.option_chosen.connect(func(i: StringName, o: StringName, r: CommandResult) -> void:
		chosen.append([i, o, r.is_rejected()]))
	var btn := panel.named_buttons("choose_%s_listen" % item.ref())[0]
	assert_bool(btn.disabled).is_false()
	btn.pressed.emit()
	assert_array(chosen).is_equal([[item.ref(), &"listen", false]])
	assert_str(panel.joined_text()).contains("Yanıt gönderildi")
	for b in panel.named_buttons("choose_"):
		assert_bool(b.disabled).is_true()  # çift gönderim yok
	_facade.advance(1)
	panel.refresh()
	assert_bool(panel.joined_text().contains("Dinleme toplantısı yap")).is_false()  # öğe listeden kalktı


func test_touch_profile_response_buttons_are_at_least_44_points() -> void:
	_build_road_and_react()
	var ctx := UiContext.for_profile_name(&"touch")
	var holder := Control.new()
	holder.theme = UiTheme.build(ctx)
	holder.size = Vector2(440.0, 1800.0)
	add_child(holder)
	auto_free(holder)
	var panel := AgendaPanel.create(ctx, _facade)
	holder.add_child(panel)
	panel.size = holder.size
	var buttons := panel.named_buttons("choose_")
	assert_int(buttons.size()).is_equal(3)
	for b in buttons:
		assert_float(b.custom_minimum_size.y).is_greater_equal(44.0)
		assert_float(b.custom_minimum_size.x).is_greater_equal(44.0)


func test_a_rejected_response_shows_the_sims_reason() -> void:
	_build_road_and_react()
	var panel := _panel()
	var it := AgendaModel.derive_all(_facade, _facade.snapshot())[0]
	var stale := AgendaModel.Option.new()   # sim'in listelemediği seçenek -> invalid_value
	stale.id = &"nope"
	stale.label_key = &"event.pe01.opt.listen"
	var res := panel.respond(it, stale)
	assert_bool(res.is_rejected()).is_true()
	assert_str(panel.joined_text()).contains("Yanıt verilemedi: ")
	assert_str(panel.joined_text()).contains(UiText.reject_reason(res.reason_key, res.args))


func test_an_item_without_options_gets_no_response_button() -> void:
	var panel := _panel()
	var it := AgendaModel.Item.new()
	it.id = &"agenda.9"
	it.kind = &"event"
	it.title_key = &"event.pe01.reason"
	it.days_left = 5
	panel.set_item_provider(func(_s: SimSnapshot) -> Array[AgendaModel.Item]: return [it])
	assert_int(panel.named_buttons("choose_").size()).is_equal(0)
	assert_bool(panel.joined_text().contains("Bu yanıtı ver")).is_false()
	assert_object(panel.button_with_text("Ertele")).is_null()


func test_late_rejection_event_is_shown_on_the_card() -> void:
	_build_road_and_react()
	var panel := _panel()
	var it := AgendaModel.derive_all(_facade, _facade.snapshot())[0]
	var res := panel.respond(it, it.options[0])
	var ev := SimEvent.new()
	ev.kind = SimEvent.KIND_COMMAND_REJECTED
	ev.command_id = res.command_id
	ev.message_key = CommandResult.REJECT_PRECONDITION
	ev.args = {"why": "agenda.closed"}
	panel.handle_event(ev)
	assert_str(panel.joined_text()).contains("Yanıt uygulanırken reddedildi: öğe artık açık değil")
