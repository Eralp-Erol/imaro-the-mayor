# gdlint:disable=max-public-methods
extends GdUnitTestSuite
## T-022 ölçüt 1/3/4/5/6 · Karar akışı PANELLERİ (imar, meclis, bütçe, gündem) HudRoot + DecisionPanels içinde.
## MOCK zorunluluğu (mock: rozet; sim: yok), kurulmamış durum, tahmin işareti, gerekçe zinciri bağlantısı, ≥ 44 pt
## hedefler, yatay taşma yok, yasak ifadeler (tek skor, ₺) yok. Olumsuz: reddedilen öneri gönderilemez, kilitli bütçe
## düzenlenemez, gündemde uydurma seçenek yok, yeni öğe yoksa otomatik duraklatma yok.

const DESKTOP_SIZE := Vector2(1600, 900)
const IPAD_LANDSCAPE := Vector2(1366, 1024)
const IPAD_PORTRAIT := Vector2(1024, 1366)
const FORBIDDEN := ["mutluluk", "puan", "skor", "₺", " tl"]

var _reason_requests: Array[Callable] = []


func before_test() -> void:
	UiText.reset()
	UiText.report_missing = false
	_reason_requests.clear()


func after_test() -> void:
	UiText.reset()


func _setup(facade: SimFacade, profile_name: StringName = &"desktop", window: Vector2 = DESKTOP_SIZE) -> DecisionPanels:
	var hud := HudRoot.new()
	add_child(hud)
	hud.setup(facade, UiTestSupport.platform(profile_name))
	hud.set_anchors_preset(Control.PRESET_TOP_LEFT)
	hud.size = window
	hud.refresh()
	auto_free(hud)
	var d := DecisionPanels.attach(hud, facade)
	d.reason_wanted.connect(func(initial: Callable) -> void: _reason_requests.append(initial))
	return d


func _council_facade(advance: int = 1) -> MockSimFacade:
	var f := FlowTestSupport.mock(FlowTestSupport.COUNCIL_BUDGET)
	f.submit_command(SimCommand.budget_propose({&"budget.line.roads": 45000}))
	f.advance(advance)
	return f


func _text(d: DecisionPanels) -> String:
	return d.hud.panel.state_view.visible_text() + " " + " | ".join(_panel_texts(d.hud.panel))


func _panel_texts(node: Node) -> PackedStringArray:
	var out := PackedStringArray()
	for child in node.get_children():
		var c := child as Control
		if c != null and not c.visible:
			continue
		if child is Label:
			out.append((child as Label).text)
		elif child is Button:
			out.append((child as Button).text)
		out.append_array(_panel_texts(child))
	return out


func _flow(d: DecisionPanels) -> FlowPanel:
	return _find_flow(d.hud.panel)


func _find_flow(node: Node) -> FlowPanel:
	if node is FlowPanel:
		return node
	for child in node.get_children():
		var found := _find_flow(child)
		if found != null:
			return found
	return null


## Sim'in kuru koşuda verdiği reti ekrana yansıtmayı sınamak için: bütçe önerisini her zaman reddeden facade.
class RejectingBudgetFacade:
	extends MockSimFacade

	func validate_command(command: SimCommand) -> CommandResult:
		if command.kind == SimCommand.KIND_BUDGET_PROPOSE:
			return CommandResult.rejected(command, CommandResult.REJECT_INVALID_TARGET, {}, current_tick(),
				provenance())
		return super.validate_command(command)


func _assert_clean_text(text: String) -> void:
	var low := text.to_lower()
	for word in FORBIDDEN:
		assert_bool(low.contains(word)).override_failure_message("yasak ifade '%s': %s" % [word, text]).is_false()


# --- Yönetim araçları ve MOCK ---

func test_manage_mode_is_built_and_tools_open_the_decision_panels() -> void:
	var d := _setup(_council_facade())
	d.hud.toolbar.select_mode(ModeToolbar.MODE_MANAGE)
	assert_bool(d.hud.toolbar.mode_button(ModeToolbar.MODE_MANAGE).disabled).is_false()
	var cases := {ModeToolbar.TOOL_BUDGET: &"budget", ModeToolbar.TOOL_COUNCIL: &"council",
		ModeToolbar.TOOL_AGENDA: &"agenda"}
	for tool_id: StringName in cases:
		d.hud.toolbar.tool_button(tool_id).pressed.emit()
		assert_that(d.hud.panel_id()).is_equal(cases[tool_id])


func test_unknown_tool_is_not_handled_and_opens_nothing() -> void:
	var d := _setup(_council_facade())
	assert_bool(d.on_tool_selected(&"tool.place_private_building")).is_false()
	assert_bool(d.hud.is_panel_open()).is_false()


func test_mock_badge_on_every_panel_for_mock_and_absent_for_sim() -> void:
	var mock := _setup(_council_facade())
	for opener: Callable in [mock.open_council, mock.open_budget, mock.open_agenda,
			func() -> void: mock.open_zoning(PackedInt64Array([1]))]:
		opener.call()
		var panel := _flow(mock)
		assert_object(panel).is_not_null()
		assert_bool(panel.badge.visible).is_true()
	var sim := _setup(UiTestSupport.non_mock(FlowTestSupport.COUNCIL_BUDGET))
	sim.open_budget()
	var sim_panel := sim.budget_panel()
	assert_bool(sim_panel.badge.visible).is_false()


# --- Meclis ---

func test_council_panel_shows_blocs_pending_vote_and_marks_the_expectation_as_estimate() -> void:
	var d := _setup(_council_facade(1))
	d.open_council()
	var text := _text(d)
	assert_str(text).contains("Meclis grubu 1")
	assert_str(text).contains("6 koltuk")
	assert_str(text).contains("Yönetimi destekliyor")
	assert_str(text).contains("Oylama sürüyor")
	assert_str(text).contains("Sonuç 3 gün içinde")
	assert_str(text).contains("Beklenen sonuç")
	assert_str(text).contains("tahmin")
	assert_str(text).contains("simülasyonun sonucu değildir")
	assert_int(d.council_panel().estimate_chip_count()).is_equal(1)  # tahmin çipi görünür
	assert_str(text).contains("Oylama sürerken oyun akmaya devam eder")
	_assert_clean_text(text)
	# Sonuç henüz yok: kabul/ret ifadesi (sim sonucu) görünmez.
	assert_bool(text.contains("Kabul edildi")).is_false()


func test_council_panel_after_the_vote_shows_sim_result_and_links_the_reason_chain() -> void:
	var d := _setup(_council_facade(6))
	d.open_council()
	var panel := d.council_panel()
	var text := _text(d)
	assert_str(text).contains("Kabul edildi")
	assert_str(text).contains("Evet 6 · Hayır 5 · Çekimser 0")
	assert_bool(text.contains("Beklenen sonuç")).is_false()  # çözülmüş oylamada tahmin yok
	assert_int(panel.estimate_chip_count()).is_equal(0)
	var bloc_buttons := panel.named_buttons("bloc_reason_")
	assert_int(bloc_buttons.size()).is_equal(2)
	bloc_buttons[0].pressed.emit()
	assert_int(_reason_requests.size()).is_equal(1)
	var reason := ReasonPanel.create(d.hud.ctx, d.facade)
	add_child(auto_free(reason))
	_reason_requests[0].call(reason)
	assert_str(" ".join(reason.texts())).contains("Meclis grubu evet oyu verdi")
	panel.named_buttons("vote_reason_")[0].pressed.emit()
	_reason_requests[1].call(reason)
	assert_int(reason.find_roles("ListRow").size()).is_equal(2)  # oylamanın iki blok gerekçesi


func test_council_unbuilt_on_the_real_sim_says_so_and_shows_nothing_else() -> void:
	var d := _setup(FlowTestSupport.real())
	d.open_council()
	var panel := d.council_panel()
	assert_that(panel.state_view.state()).is_equal(StateView.State.NOT_BUILT)
	assert_str(panel.state_view.visible_text()).is_equal("Meclis sistemi henüz kurulmadı")
	assert_bool(panel.state_view.content_visible()).is_false()
	assert_bool(panel.badge.visible).is_false()  # gerçek sim: MOCK rozeti yok


func test_council_inconsistent_seat_data_is_flagged_not_silently_shown() -> void:
	var f := _council_facade(1)
	var d := _setup(f)
	d.open_council()
	var bad := CouncilView.from_dict(f.snapshot().council.to_dict())
	bad.blocs[0].seats = 1
	var model := CouncilModel.build(bad, 1)
	assert_bool(model.issues().has("seats_mismatch")).is_true()


# --- Bütçe ---

func test_budget_panel_reads_sim_numbers_in_configured_currency_only() -> void:
	var d := _setup(_council_facade(0))
	d.open_budget()
	var text := _text(d)
	assert_str(text).contains("120.000 ¤")
	assert_str(text).contains("105.000 ¤")
	assert_str(text).contains("30.000 ¤")
	assert_str(text).contains("Yollar")
	assert_str(text).contains("%38")
	_assert_clean_text(text)
	UiConfig.set_override("economy.currency_symbol", "◆")
	d.budget_panel().refresh_if_changed("farklı")
	assert_str(_text(d)).contains("120.000 ◆")
	assert_bool(_text(d).contains("¤")).is_false()  # simge yalnız yapılandırmadan


func test_budget_editor_steps_validates_and_submits_then_locks_while_the_council_votes() -> void:
	var f := FlowTestSupport.mock(FlowTestSupport.COUNCIL_BUDGET)
	var d := _setup(f)
	d.open_budget()
	var panel := d.budget_panel()
	assert_bool(panel.button_with_text("Meclise sun").disabled).is_true()  # değişiklik yok
	panel.step(&"budget.line.roads", 1)
	assert_str(_text(d)).contains("41.000 ¤")
	assert_str(_text(d)).contains("Toplam gider değişimi")
	var send := panel.button_with_text("Meclise sun")
	assert_bool(send.disabled).is_false()
	send.pressed.emit()
	assert_str(_text(d)).contains("Öneri gönderildi")
	assert_bool(panel.button_with_text("Meclise sun").disabled).is_true()  # sıraya alınmışken ikinci gönderim yok
	f.advance(1)
	d.hud.refresh()
	panel = d.budget_panel()
	assert_str(_text(d)).contains("Öneri meclis oylamasında")
	assert_object(panel.button_with_text("Meclise sun")).is_null()  # kilitli: düzenleyici yok
	assert_int(panel.named_buttons("step_").size()).is_equal(0)
	assert_str(_text(d)).contains("+1.000 ¤")  # öneri sütunu sim'in proposed alanından
	panel.named_buttons("open_vote")[0].pressed.emit()
	assert_that(d.hud.panel_id()).is_equal(&"council")


func test_budget_step_down_is_disabled_at_zero() -> void:
	var f := FlowTestSupport.mock(FlowTestSupport.COUNCIL_BUDGET)
	var d := _setup(f)
	UiConfig.set_override(UiPrefs.KEY_BUDGET_STEP, 15000)
	d.open_budget()
	var panel := d.budget_panel()
	panel.step(&"budget.line.parks", -1)  # 15.000 -> 0
	assert_bool(panel.named_buttons("step_down_budget.line.parks")[0].disabled).is_true()
	panel.step(&"budget.line.parks", -1)  # sıfırın altına inemez
	assert_int(d.budget_draft.amount(&"budget.line.parks")).is_equal(0)


func test_budget_sim_rejection_of_the_draft_blocks_sending_and_shows_the_reason() -> void:
	var f := RejectingBudgetFacade.new(MockScenario.load_file(FlowTestSupport.FIXTURES
		+ FlowTestSupport.COUNCIL_BUDGET + ".json"))
	var d := _setup(f)
	d.open_budget()
	var panel := d.budget_panel()
	panel.step(&"budget.line.roads", 1)
	assert_str(_text(d)).contains("Hedef bu işlem için uygun değil")
	var send := panel.button_with_text("Meclise sun")
	assert_bool(send.disabled).is_true()
	panel.send()  # doğrudan çağrı bile gönderemez
	assert_object(d.budget_draft.last_submit).is_null()
	assert_int(f.last_event_seq()).is_equal(0)


func test_budget_unbuilt_on_the_real_sim() -> void:
	var d := _setup(FlowTestSupport.real())
	d.open_budget()
	var panel := d.budget_panel()
	assert_that(panel.state_view.state()).is_equal(StateView.State.NOT_BUILT)
	assert_str(panel.state_view.visible_text()).is_equal("Bütçe sistemi henüz kurulmadı")
	assert_int(panel.buttons().size()).is_equal(0)  # düzenleyici/gönder düğmesi yok
	assert_bool(d.hud.top_bar.money_visible()).is_false()  # para göstergesi de sahte 0 göstermez


func test_budget_tick_boundary_refusal_shows_the_sim_reason() -> void:
	var f := _council_facade(0)
	var d := _setup(f)
	d.open_budget()
	d.budget_draft.last_submit = f.submit_command(SimCommand.budget_propose({&"budget.line.roads": 1}))
	var event := SimEvent.new()
	event.kind = SimEvent.KIND_COMMAND_REJECTED
	event.command_id = d.budget_draft.last_submit.command_id
	event.message_key = CommandResult.REJECT_PRECONDITION
	event.args = {"ref": "vote.1"}
	d.budget_panel().handle_event(event)
	assert_str(_text(d)).contains("Öneri reddedildi")
	assert_str(_text(d)).contains("Önkoşul sağlanmıyor")
	d.budget_panel().named_buttons("open_reason")[0].pressed.emit()
	assert_int(_reason_requests.size()).is_equal(1)


# --- Gündem ---

func test_agenda_panel_lists_the_pending_vote_without_inventing_options() -> void:
	var d := _setup(_council_facade(1))
	d.open_agenda()
	var text := _text(d)
	assert_str(text).contains("Bütçe önerisi oylaması")
	assert_str(text).contains("Sonuç 3 gün içinde")
	assert_str(text).contains("yalnız açık meclis oylamaları")
	assert_object(d.agenda_panel().button_with_text("Bu seçeneği uygula")).is_null()
	assert_object(d.agenda_panel().button_with_text("Ertele")).is_null()
	assert_int(d.hud.top_bar.agenda.text.length()).is_greater(0)
	assert_bool(d.hud.top_bar.agenda.visible).is_true()
	assert_str(d.hud.top_bar.agenda.text).contains("MOCK")


func test_agenda_empty_and_badge_hidden_without_items() -> void:
	var d := _setup(FlowTestSupport.mock(FlowTestSupport.COUNCIL_BUDGET))
	d.open_agenda()
	assert_str(_text(d)).contains("Bekleyen gündem öğesi yok")
	assert_bool(d.hud.top_bar.agenda.visible).is_false()  # sahte sayı yok


func test_agenda_unbuilt_on_the_real_sim_hides_badge_and_says_so() -> void:
	var d := _setup(FlowTestSupport.real())
	d.open_agenda()
	assert_that(d.agenda_panel().state_view.state()).is_equal(StateView.State.NOT_BUILT)
	assert_str(d.agenda_panel().state_view.visible_text()).is_equal("Olay sistemi henüz kurulmadı")
	assert_bool(d.hud.top_bar.agenda.visible).is_false()


func test_agenda_options_degrade_gracefully_and_render_when_a_v11_item_has_them() -> void:
	var d := _setup(_council_facade(1))
	d.open_agenda()
	var panel := d.agenda_panel()
	var it := AgendaModel.Item.new()
	it.id = &"x.1"
	it.kind = &"event"
	it.title_key = &"agenda.item_new"
	it.days_left = 4
	it.can_defer = true
	var o := AgendaModel.Option.new()
	o.id = &"a"
	o.label_key = &"agenda.option"
	o.has_cost = true
	o.cost = 2000
	o.preview_key = &"zoning.preview.estimate_note"
	it.options = [o]
	panel.set_item_provider(func(_s: SimSnapshot) -> Array[AgendaModel.Item]: return [it])
	var text := " ".join(panel.texts())
	assert_str(text).contains("Bedel: 2.000 ¤")
	assert_str(text).contains("tahmin")  # önizleme tahmin işaretli
	assert_str(text).contains("Yanıt için kalan: 4 gün")
	assert_str(text).contains("Ertelemek de bir karardır")
	var chosen := []
	panel.option_chosen.connect(func(i: StringName, opt: StringName) -> void: chosen.append([i, opt]))
	panel.button_with_text("Bu seçeneği uygula").pressed.emit()
	assert_array(chosen).is_equal([[&"x.1", &"a"]])


func test_auto_pause_setting_off_never_interrupts_the_game() -> void:
	var f := FlowTestSupport.mock(FlowTestSupport.COUNCIL_BUDGET)
	f.set_speed(SimFacade.SPEED_NORMAL)
	var d := _setup(f)
	assert_bool(UiPrefs.auto_pause_agenda()).is_false()
	f.submit_command(SimCommand.budget_propose({&"budget.line.roads": 45000}))
	f.advance(1)
	d.hud.refresh()
	assert_int(d.hud.top_bar.agenda.visible as int).is_equal(1)  # yeni öğe geldi
	assert_int(f.speed()).is_equal(SimFacade.SPEED_NORMAL)  # ama ayar kapalı: hiçbir şey kesilmez


func test_auto_pause_pauses_the_game_when_a_new_vote_appears_and_setting_is_on() -> void:
	var f := FlowTestSupport.mock(FlowTestSupport.COUNCIL_BUDGET)
	f.set_speed(SimFacade.SPEED_NORMAL)
	var d := _setup(f)
	UiPrefs.set_auto_pause_agenda(true)
	var paused := []
	d.auto_paused.connect(func(id: StringName) -> void: paused.append(id))
	f.submit_command(SimCommand.budget_propose({&"budget.line.roads": 45000}))
	f.advance(1)
	d.hud.refresh()
	assert_int(f.speed()).is_equal(SimFacade.SPEED_PAUSED)
	assert_array(paused).is_equal([&"vote.1"])


func test_auto_pause_does_not_fire_for_items_already_present_at_load() -> void:
	var f := _council_facade(1)  # oylama yüklemeden önce açık
	f.set_speed(SimFacade.SPEED_NORMAL)
	UiPrefs.set_auto_pause_agenda(true)
	var d := _setup(f)
	d.hud.refresh()
	assert_int(f.speed()).is_equal(SimFacade.SPEED_NORMAL)


func test_auto_pause_toggle_button_changes_only_the_setting() -> void:
	var f := _council_facade(1)
	f.set_speed(SimFacade.SPEED_NORMAL)
	var d := _setup(f)
	d.open_agenda()
	var button := d.agenda_panel().auto_pause_button()
	assert_bool(UiPrefs.auto_pause_agenda()).is_false()
	button.button_pressed = true
	assert_bool(UiPrefs.auto_pause_agenda()).is_true()
	assert_str(d.agenda_panel().auto_pause_button().text).contains("Açık")
	assert_int(f.speed()).is_equal(SimFacade.SPEED_NORMAL)  # ayarı açmak oyunu kesmez


# --- İmar paneli ---

func test_zoning_panel_rejected_use_blocks_sending_and_shows_the_reason() -> void:
	var d := _setup(FlowTestSupport.mock("mock_scenario_investment_declined"))
	d.open_zoning(PackedInt64Array([1]))
	var panel := d.zoning_panel()
	assert_object(panel.send_button()).is_not_null()
	assert_bool(panel.send_button().is_enabled()).is_false()
	panel.choose_use(&"zone.industrial")
	assert_str(panel.verdict_text()).contains("Değer kabul edilmiyor: arazi kullanımı")
	assert_bool(panel.send_button().is_enabled()).is_false()
	assert_str(panel.send_button().reason_text()).contains("Öneri kabul edilmiyor")
	panel.send()
	assert_object(panel.last_submit).is_null()
	panel.choose_use(&"zone.mixed")
	assert_bool(panel.send_button().is_enabled()).is_true()
	assert_str(" ".join(panel.texts())).contains("Bu karar bina yerleştirmez")


func test_zoning_panel_survives_profile_switch_with_state_intact() -> void:
	var d := _setup(FlowTestSupport.mock("mock_scenario_investment_declined"))
	d.open_zoning(PackedInt64Array([1]))
	d.zoning_panel().choose_use(&"zone.mixed")
	d.zoning_panel().send()
	d.hud.apply_profile(UiTestSupport.platform(&"touch"))
	await await_idle_frame()
	var panel := d.zoning_panel()
	assert_object(panel).is_not_null()
	assert_that(panel.model.phase()).is_equal(ZoningFlowModel.Phase.SENT)
	assert_str(panel.queued_text()).contains("sıraya alındı")
	assert_array(Array(panel.model.parcel_ids)).is_equal([1])


func test_zoning_panel_follows_events_through_to_effect_on_mock_and_real() -> void:
	for facade: SimFacade in [FlowTestSupport.mock("mock_scenario_investment_declined"), FlowTestSupport.real()]:
		var d := _setup(facade)
		d.open_zoning(PackedInt64Array([1]))
		d.zoning_panel().choose_use(&"zone.mixed")
		d.zoning_panel().send()
		facade.advance(8)
		d.hud.refresh()
		var panel := d.zoning_panel()
		assert_that(panel.model.phase()).is_equal(ZoningFlowModel.Phase.EFFECTIVE)
		assert_str(panel.queued_text()).contains("yürürlüğe girdi")
		assert_object(panel.button_with_text("Yeni öneri")).is_not_null()
		assert_object(panel.send_button()).is_null()  # sonuç aşamasında gönder düğmesi yok


func test_zoning_refusal_opens_the_reason_panel_with_the_sims_reason() -> void:
	var f := FlowTestSupport.mock("mock_scenario_invalid_commands")
	var d := _setup(f)
	d.open_zoning(PackedInt64Array([2]))
	d.zoning_panel().choose_use(&"zone.commercial")
	d.zoning_panel().send()
	f.advance(3)
	d.hud.refresh()
	var panel := d.zoning_panel()
	assert_str(panel.queued_text()).contains("Koruma alanında imar değişikliği önerilemez")
	panel.named_buttons("open_reason")[0].pressed.emit()
	assert_int(_reason_requests.size()).is_equal(1)
	var reason := ReasonPanel.create(d.hud.ctx, f)
	add_child(auto_free(reason))
	_reason_requests[0].call(reason)
	assert_that(reason.current_mode()).is_equal(ReasonPanel.MODE_REJECTION)


func test_zoning_council_path_shows_vote_and_links_to_the_council_panel() -> void:
	UiPrefs.set_zoning_requires_council(true)
	var f := FlowTestSupport.mock(FlowTestSupport.ZONING_COUNCIL)
	var d := _setup(f)
	d.open_zoning(PackedInt64Array([1]))
	assert_bool(d.zoning_panel().send_button().is_enabled()).is_false()  # kullanım seçilmeden gönderilemez
	d.zoning_panel().choose_use(&"zone.mixed")
	assert_object(d.zoning_panel().send_button()).is_not_null()
	assert_str(d.zoning_panel().send_button().button.text).is_equal("Meclise sun")
	d.zoning_panel().send()
	f.advance(2)
	d.hud.refresh()
	assert_str(d.zoning_panel().queued_text()).contains("Meclis oylaması bekleniyor")
	d.zoning_panel().named_buttons("open_vote")[0].pressed.emit()
	assert_that(d.hud.panel_id()).is_equal(&"council")
	assert_str(_text(d)).contains("İmar önerisi oylaması")


func test_zoning_area_accepts_more_parcels_from_the_map_only_while_open_and_unlocked() -> void:
	var f := FlowTestSupport.mock("mock_scenario_group_reactions")
	var d := _setup(f)
	assert_bool(d.add_zoning_parcel(2)).is_false()  # panel kapalı
	d.open_zoning(PackedInt64Array([1]))
	assert_bool(d.add_zoning_parcel(2)).is_true()
	assert_str(" | ".join(d.zoning_panel().texts())).contains("Parsel 2")
	d.zoning_panel().choose_use(&"zone.commercial")
	d.zoning_panel().send()
	assert_bool(d.add_zoning_parcel(3)).is_false()  # gönderildikten sonra alan kilitli
	d.open_zoning(PackedInt64Array([3]))  # süren öneri korunur
	assert_array(Array(d.zoning.parcel_ids)).is_equal([1, 2])


# --- Hedefler, taşma, yasak ifadeler (her panel × her profil) ---

## Sarılan etiketin genişliği en uzun sözcüğünden dar olmamalı (harf harf sarılma = okunmaz).
func _assert_no_letter_wrap(flow: FlowPanel, where: String) -> void:
	for label in _labels_in(flow):
		if label.autowrap_mode == TextServer.AUTOWRAP_OFF or label.text.is_empty() or not label.is_visible_in_tree():
			continue
		var font := label.get_theme_font(&"font")
		var size := label.get_theme_font_size(&"font_size")
		var longest := 0.0
		for word in label.text.split(" "):
			longest = maxf(longest, font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x)
		assert_float(label.size.x + 1.0).override_failure_message("'%s' çok dar (%s): %s px < %s px" % [
			label.text, where, label.size.x, longest]).is_greater_equal(minf(longest, 400.0))


func _labels_in(node: Node) -> Array[Label]:
	var out: Array[Label] = []
	for child in node.get_children():
		if child is Label:
			out.append(child)
		out.append_array(_labels_in(child))
	return out


func test_all_panels_meet_targets_and_do_not_overflow_in_every_profile() -> void:
	var cases := [[&"desktop", DESKTOP_SIZE, 32.0], [&"touch", IPAD_LANDSCAPE, 44.0], [&"touch", IPAD_PORTRAIT, 44.0]]
	for c in cases:
		for advance_ticks in [1, 6]:  # 1: oylama açık (tahmin) · 6: oylama sonuçlandı (konumlar, gerekçeler)
			await _check_panels_in(c, advance_ticks)


func _check_panels_in(c: Array, advance_ticks: int) -> void:
	var window: Vector2 = c[1]
	var d := _setup(_council_facade(advance_ticks), c[0], window)
	var openers: Array[Callable] = [d.open_council, d.open_budget, d.open_agenda,
		func() -> void:
			d.open_zoning(PackedInt64Array([1]))
			d.zoning_panel().choose_use(&"zone.mixed")]
	for opener in openers:
		opener.call()
		await await_idle_frame()
		await await_idle_frame()
		var panel_rect := d.hud.panel.get_global_rect()
		var flow := _flow(d)
		assert_object(flow).is_not_null()
		assert_int(flow.buttons().size()).override_failure_message("panelde düğme yok").is_greater(0)
		for b in flow.buttons():
			# Ölü düğme yok: her düğmenin bir eylemi (pressed/toggled bağlantısı) vardır.
			var wired := b.get_signal_connection_list(&"pressed").size() \
				+ b.get_signal_connection_list(&"toggled").size()
			assert_int(wired).override_failure_message("'%s' düğmesine eylem bağlı değil" % b.text).is_greater(0)
			var hit := UiFactory.hit_size(b)
			assert_float(minf(hit.x, hit.y)).override_failure_message(
				"'%s' %s (%s %s)" % [b.text, hit, c[0], window]).is_greater_equal(c[2])
			var r := b.get_global_rect()
			assert_bool(r.position.x >= panel_rect.position.x - 1.0 and r.end.x <= panel_rect.end.x + 1.0) \
				.override_failure_message("'%s' yatay taştı %s / %s" % [b.text, r, panel_rect]).is_true()
		_assert_clean_text(" ".join(flow.texts()))
		_assert_no_letter_wrap(flow, "%s %s" % [c[0], window])
