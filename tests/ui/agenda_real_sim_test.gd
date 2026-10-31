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


func test_without_expropriation_no_displacement_item_reaches_the_agenda() -> void:
	var h: PoliticsHandle = _world(false)["handle"]
	h.facade.advance(30)
	for it in AgendaModel.derive_all(h.facade, h.facade.snapshot()):
		assert_str(String(it.kind)).is_not_equal("displacement")
