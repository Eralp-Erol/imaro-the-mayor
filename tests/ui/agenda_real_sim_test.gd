extends "res://tests/sim/politics/reaction_world_base.gd"
## T-042b gündem uçtan uca (D-008 "halk tepki versin" -> gündemde gör): GERÇEK `SimFacadeImpl` + gerçek PE-01 yerinden
## edilme öğesi -> `AgendaModel.derive_all` -> `AgendaPanel`. Hane sayısı sim'in neden kaydından okunur (UI uydurmaz).


func before_test() -> void:
	InspectorHost.default_interval_msec = 0
	UiText.reset()
	UiText.report_missing = false


func after_test() -> void:
	UiText.reset()


func test_real_pe01_item_reaches_the_agenda_model_with_the_recorded_household_count() -> void:
	var h: PoliticsHandle = _world()["handle"]
	h.facade.advance(14)
	var items := AgendaModel.derive_all(h.facade, h.facade.snapshot())
	assert_int(items.size()).override_failure_message("gerçek PE-01 gündemde görünmeli").is_greater(0)
	var it: AgendaModel.Item = null
	for candidate in items:
		if candidate.kind == &"displacement":
			it = candidate
	assert_object(it).is_not_null()
	var cause := AgendaModel.displaced_cause(h.facade, it.reason_ids)
	assert_bool(bool(cause["found"])).is_true()
	assert_int(int(cause["households"])).is_equal(h.facade.public_works()[0].displaced_households)


func test_real_pe01_item_is_listed_in_the_panel_with_the_why_button() -> void:
	var h: PoliticsHandle = _world()["handle"]
	h.facade.advance(14)
	var ctx := UiContext.for_profile_name(&"desktop")
	var holder := Control.new()
	holder.theme = UiTheme.build(ctx)
	holder.size = Vector2(440.0, 1400.0)
	add_child(holder)
	auto_free(holder)
	var panel := AgendaPanel.create(ctx, h.facade)
	holder.add_child(panel)
	panel.size = holder.size
	var households := h.facade.public_works()[0].displaced_households
	var text := panel.joined_text()
	assert_str(text).contains("Yol yüzünden %s hane yerinden edildi." % UiText.number(households))
	assert_object(panel.button_with_text("Nedenini gör")).is_not_null()


func _panel_for(h: PoliticsHandle) -> AgendaPanel:
	var ctx := UiContext.for_profile_name(&"desktop")
	var holder := Control.new()
	holder.theme = UiTheme.build(ctx)
	holder.size = Vector2(440.0, 1800.0)
	add_child(holder)
	auto_free(holder)
	var panel := AgendaPanel.create(ctx, h.facade)
	holder.add_child(panel)
	panel.size = holder.size
	return panel


func test_real_pe01_shows_the_sims_options_with_honest_effects() -> void:
	var h: PoliticsHandle = _world()["handle"]
	h.facade.advance(14)
	var view: AgendaItemView = h.facade.agenda_items()[0]
	assert_int(view.options.size()).is_greater(0)
	var panel := _panel_for(h)
	var text := panel.joined_text()
	for ov in view.options:
		assert_str(text).contains(UiText.t(ov.label_key))
		for effect in ov.effects:
			assert_str(text).contains(AgendaModel.effect_text(effect))
	assert_int(panel.named_buttons("choose_").size()).is_equal(view.options.size())
	assert_bool(text.contains("Bedel")).is_false()
	assert_bool(text.contains("Ertele")).is_false()
	for ov in view.options:
		if not ov.available:
			assert_bool(panel.named_buttons("choose_%s_%s" % [view.ref(), ov.option_id])[0].disabled).is_true()
			assert_str(text).contains("Kilitli")


func test_real_pe01_response_goes_through_the_sim_and_the_item_leaves_next_tick() -> void:
	var h: PoliticsHandle = _world()["handle"]
	h.facade.advance(14)
	var view: AgendaItemView = h.facade.agenda_items()[0]
	var pick: AgendaOptionView = null
	for ov in view.options:
		if ov.available:
			pick = ov
			break
	assert_object(pick).is_not_null()
	var panel := _panel_for(h)
	panel.named_buttons("choose_%s_%s" % [view.ref(), pick.option_id])[0].pressed.emit()
	assert_str(panel.joined_text()).contains("Yanıt gönderildi")
	assert_int(h.facade.agenda_items().size()).is_equal(1)  # sonraki tick'e kadar öğe SİM'de açık (iyimser silme yok)
	h.facade.advance(1)
	panel.refresh()
	assert_int(h.facade.agenda_items().size()).is_equal(0)
	assert_bool(panel.joined_text().contains("Bu yanıtı ver")).is_false()
	assert_bool(panel.joined_text().contains("Yanıt gönderildi")).is_false()


func test_real_sim_refusal_reason_is_shown_for_a_locked_option() -> void:
	var h: PoliticsHandle = _world()["handle"]
	h.facade.advance(14)
	var view: AgendaItemView = h.facade.agenda_items()[0]
	var locked: AgendaOptionView = null
	for ov in view.options:
		if not ov.available:
			locked = ov
	if locked == null:
		return  # bu dünyada kilitli seçenek yok (yetki verilmiş); kilit yolu mock testinde
	var panel := _panel_for(h)
	var it := AgendaModel.derive_all(h.facade, h.facade.snapshot())[0]
	var o := AgendaModel.Option.new()
	o.id = locked.option_id
	o.available = false
	var res := panel.respond(it, o)  # kilitli düğme gönderilmez; kuru yoldan sim'e doğrudan sor
	assert_object(res).is_null()
	var direct := h.facade.validate_command(SimCommand.agenda_respond(view.item_id, locked.option_id))
	assert_bool(direct.is_rejected()).is_true()
	assert_str(String(direct.args.get("why", ""))).is_equal("authority.locked")


func test_without_expropriation_no_displacement_item_reaches_the_agenda() -> void:
	var h: PoliticsHandle = _world(false)["handle"]
	h.facade.advance(30)
	for it in AgendaModel.derive_all(h.facade, h.facade.snapshot()):
		assert_str(String(it.kind)).is_not_equal("displacement")
