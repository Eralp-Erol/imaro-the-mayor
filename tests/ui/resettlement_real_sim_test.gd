extends "res://tests/sim/public_works/resettlement_test_base.gd"
## T-065 Aşama 1 UI uçtan uca: GERÇEK `SimFacadeImpl` (sahte dünya köprüsü, gerçek sim/politika/bütçe) -> Politikalar
## paneli, yol önizleme satırları, olay metni, gündem satırı ve neden paneli. Sayılar sim'in kendi kaydıyla
## karşılaştırılır
## (UI uydurmaz). Dünya: D1'de 16 hane yerinden edilir (bkz. ResettlementTestBase).

const FULL := {"max_distance_m": 5000}


func before_test() -> void:
	InspectorHost.default_interval_msec = 0
	UiText.reset()
	UiText.report_missing = false


func after_test() -> void:
	UiText.reset()


func _holder(width: float = 440.0, ctx: UiContext = null) -> Control:
	var c := ctx if ctx != null else UiContext.for_profile_name(&"desktop")
	var holder := Control.new()
	holder.theme = UiTheme.build(c)
	holder.size = Vector2(width, 2400.0)
	add_child(holder)
	auto_free(holder)
	return holder


func _preview(run: Dictionary) -> Dictionary:
	var r := _f(run).validate_command(SimCommand.public_work_road(PackedInt64Array(DIAGONAL), &"local", true))
	assert_bool(r.is_rejected()).override_failure_message("yol reddedilmemeli: %s" % r.reason_key).is_false()
	return r.args


func test_the_policy_panel_turns_the_real_policy_on_after_the_next_tick() -> void:
	var run := _rworld(60, FULL)
	var ctx := UiContext.for_profile_name(&"desktop")
	var holder := _holder(440.0, ctx)
	var panel := PolicyPanel.create(ctx, _f(run), {})
	holder.add_child(panel)
	panel.size = holder.size
	assert_str(panel.status_text()).is_equal("Kapalı")
	assert_bool(_f(run).policies()[0].enabled).is_false()
	panel.toggle_button().pressed.emit()
	assert_bool(_f(run).policies()[0].enabled).override_failure_message("kuyrukta: sim henüz değişmedi").is_false()
	_f(run).advance(1)
	panel.refresh()
	assert_bool(_f(run).policies()[0].enabled).is_true()
	assert_str(panel.status_text()).is_equal("Açık")
	assert_str(panel.toggle_button().text).is_equal("Yeniden iskânı kapat")


func test_real_preview_with_enough_vacancy_reports_the_sims_housed_count() -> void:
	var run := _rworld(60, FULL)
	_policy(run, true)
	var args := _preview(run)
	var text := " ".join(ExpropriationText.resettlement_lines(args))
	assert_str(text).contains("%d haneye ev ayrıldı" % int(args["rehoused_households"]))
	assert_int(int(args["rehoused_households"])).is_equal(16)
	assert_str(text).not_contains("için ev yok")
	assert_str(text).contains("Yeniden iskân bedeli: %s" % UiText.money(int(args["resettlement_cost"])))
	assert_array(Array(UiText.missing_keys())).is_empty()


func test_real_preview_without_any_vacancy_still_builds_the_road_and_says_nobody_is_housed() -> void:
	var run := _rworld(0, FULL)
	_policy(run, true)
	var args := _preview(run)   # reddedilmedi: yol yine yapılır (D-016 §3)
	var text := " ".join(ExpropriationText.resettlement_lines(args))
	assert_str(text).contains("16 hane için ev yok")
	assert_str(text).contains("hiçbir haneye ev ayrılamadı")
	assert_str(text).contains("Yol yine yapılır")
	assert_str(text).not_contains("tepkisi azalır")
	_road(run)
	assert_int(_f(run).public_works().size()).is_equal(1)


func test_real_preview_with_the_policy_off_has_no_resettlement_keys_so_only_the_off_note_applies() -> void:
	var run := _rworld(60, FULL)
	var args := _preview(run)
	assert_bool(ExpropriationText.resettlement_lines(args).is_empty()).is_true()
	assert_bool(ExpropriationText.resettlement_off_needed(args, false)).is_true()


func test_real_expropriated_event_says_how_many_moved() -> void:
	var run := _rworld(60, FULL)
	_policy(run, true)
	_road(run)
	var e := _events(run, SimEvent.KIND_PUBLIC_WORK_EXPROPRIATED)[0]
	assert_str(UiText.event_text(e)).contains("16 hane taşındı")
	assert_str(UiText.event_text(e)).not_contains("ev yok")
	assert_str(NotificationStrip.strip_text(e)).contains("16 hane taşındı")


func test_real_expropriated_event_says_how_many_have_no_home() -> void:
	var run := _rworld(0, FULL)
	_policy(run, true)
	_road(run)
	var e := _events(run, SimEvent.KIND_PUBLIC_WORK_EXPROPRIATED)[0]
	assert_str(UiText.event_text(e)).contains("16 aile için ev yok")
	assert_str(UiText.event_text(e)).not_contains("taşındı")


func test_real_policy_changed_event_reads_plainly() -> void:
	var run := _rworld(60, FULL)
	_policy(run, true)
	var e := _events(run, SimEvent.KIND_POLICY_CHANGED)[0]
	assert_str(NotificationStrip.strip_text(e)).is_equal("Yeniden iskân politikası açıldı")


func _agenda_text(run: Dictionary) -> String:
	var ctx := UiContext.for_profile_name(&"desktop")
	var holder := _holder(440.0, ctx)
	var panel := AgendaPanel.create(ctx, _f(run))
	holder.add_child(panel)
	panel.size = holder.size
	return panel.joined_text()


func test_the_agenda_says_how_many_families_have_no_home_from_the_sims_reason_record() -> void:
	var run := _rworld(0, FULL)
	_policy(run, true)
	_road(run)
	_f(run).advance(14)
	var items := AgendaModel.derive_all(_f(run), _f(run).snapshot())
	var cause: Dictionary = {}
	for it in items:
		if it.kind == AgendaModel.KIND_DISPLACEMENT:
			cause = AgendaModel.displaced_cause(_f(run), it.reason_ids)
	assert_bool(cause.is_empty()).override_failure_message("yerinden edilme öğesi gündemde olmalı").is_false()
	assert_bool(bool(cause["resettled"])).is_true()
	assert_int(int(cause["unplaced"])).is_equal(16)
	assert_int(int(cause["rehoused"])).is_equal(0)
	var text := _agenda_text(run)
	assert_str(text).contains("16 aile için ev yok.")
	# Gündem öğesi bölge ölçekli kayda bağlıdır (tahsis etkeni yok): sayı yolun sim kaydından gelir ve "bu yol" denir.
	assert_str(String(cause["scope"])).is_equal("road")
	assert_str(text).contains("Bu yoldaki yeniden iskân: 16 haneden 0 tanesine ev ayrıldı.")


func test_the_agenda_with_housing_found_says_so_and_has_no_no_home_line() -> void:
	var run := _rworld(60, FULL)
	_policy(run, true)
	_road(run)
	_f(run).advance(14)
	var cause := {}
	for it in AgendaModel.derive_all(_f(run), _f(run).snapshot()):
		if it.kind == AgendaModel.KIND_DISPLACEMENT:
			cause = AgendaModel.displaced_cause(_f(run), it.reason_ids)
	if cause.is_empty():
		return   # kalan tepki eşiğin altında kaldı: gündem öğesi hiç doğmadı (sim kararı); satır uydurulmaz
	assert_int(int(cause["rehoused"])).is_equal(16)
	var text := _agenda_text(run)
	assert_str(text).contains("16 haneden 16 tanesine ev ayrıldı")
	assert_str(text).not_contains("için ev yok")


func test_the_agenda_without_the_policy_shows_no_resettlement_line() -> void:
	var run := _rworld(60, FULL)
	_road(run)
	_f(run).advance(14)
	var text := _agenda_text(run)
	assert_str(text).contains("Yol yüzünden 16 hane yerinden edildi.")
	assert_str(text).not_contains("Yeniden iskân")
	assert_str(text).not_contains("ev yok")


func test_the_reason_panel_shows_the_two_resettlement_counts_as_counts() -> void:
	var run := _rworld(0, FULL)
	_policy(run, true)
	_road(run)
	_f(run).advance(2)
	# Mahalle ölçekli neden kaydı (sim'in kendi yazıcısı) tahsis sayımlarını taşır.
	var cfg: Dictionary = politics_config().reactions["local"]
	var reading := ReactionAgenda.local_readings(_h(run).state(), int(politics_config().blocs["reaction_window"]),
			cfg)[0]
	var cause := ReactionCause.record_local(_h(run).state(), _h(run).context, BLOC_HOUSED, reading)
	assert_bool(cause.is_empty()).is_false()
	var ctx := UiContext.for_profile_name(&"desktop")
	var holder := _holder(440.0, ctx)
	var panel := ReasonPanel.create(ctx, _f(run))
	holder.add_child(panel)
	panel.size = holder.size
	panel.show_record(int(cause["id"]))
	var text := " ".join(Array(panel.texts()))
	assert_str(text).contains("Ev bulunamayan hane sayısı")
	assert_str(text).contains("Ev ayrılan hane sayısı")
	assert_str(text).contains("16 hane (sayım; karar hesabına girmez)")
	assert_str(text).contains("0 hane (sayım; karar hesabına girmez)")
	assert_array(Array(UiText.missing_keys())).is_empty()
