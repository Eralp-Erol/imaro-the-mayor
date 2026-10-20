# gdlint:disable=max-public-methods
extends GdUnitTestSuite
## T-022 ölçüt 1/2 · İmar önerisi akışı durum makinesi (ZoningFlowModel), MOCK ve GERÇEK SimFacadeImpl ile.
## Gerekçeli ret (önizleme + tick sınırı), alan düzenleme, meclis yolu (Q-014: iki yol), yürürlük zamanı.
## Olumsuz: kurulmamış adım atlanamaz, reddedilen öneri gönderilemez, başkasının komutu akışı etkilemez.

var _cursor: int = 0


func before_test() -> void:
	UiText.reset()
	UiText.report_missing = false
	_cursor = 0


func after_test() -> void:
	UiText.reset()


func _model(facade: SimFacade) -> ZoningFlowModel:
	return ZoningFlowModel.create(facade)


func _pump(model: ZoningFlowModel, facade: SimFacade) -> void:
	_cursor = FlowTestSupport.pump(facade, _cursor, model.handle_event)


# --- Adımlar ve alan ---

func test_phases_follow_area_then_use_then_ready() -> void:
	var f := FlowTestSupport.mock("mock_scenario_investment_declined")
	var m := _model(f)
	assert_that(m.phase()).is_equal(ZoningFlowModel.Phase.PICK_AREA)
	assert_int(m.step_number()).is_equal(1)
	assert_bool(m.add_parcel(1)).is_true()
	assert_that(m.phase()).is_equal(ZoningFlowModel.Phase.PICK_USE)
	assert_int(m.step_number()).is_equal(2)
	m.choose_use(&"zone.mixed")
	assert_that(m.phase()).is_equal(ZoningFlowModel.Phase.READY)
	assert_int(m.step_number()).is_equal(3)
	assert_bool(m.can_send()).is_true()


func test_negative_use_cannot_be_chosen_without_area_and_nothing_is_validated() -> void:
	var f := FlowTestSupport.mock("mock_scenario_investment_declined")
	var m := _model(f)
	m.choose_use(&"zone.mixed")
	assert_that(m.phase()).is_equal(ZoningFlowModel.Phase.PICK_AREA)
	assert_object(m.last_validation).is_null()
	assert_bool(m.can_send()).is_false()
	assert_bool(m.send()).is_false()
	assert_int(f.last_event_seq()).is_equal(0)


func test_area_add_remove_and_duplicates() -> void:
	var m := _model(FlowTestSupport.mock("mock_scenario_group_reactions"))
	assert_bool(m.add_parcel(1)).is_true()
	assert_bool(m.add_parcel(1)).is_false()  # tekrar eklenmez
	assert_bool(m.add_parcel(0)).is_false()  # geçersiz kimlik
	assert_bool(m.add_parcel(2)).is_true()
	assert_array(Array(m.parcel_ids)).is_equal([1, 2])
	m.remove_parcel(1)
	assert_array(Array(m.parcel_ids)).is_equal([2])
	m.clear_area()
	assert_that(m.phase()).is_equal(ZoningFlowModel.Phase.PICK_AREA)


func test_changing_area_after_choice_revalidates() -> void:
	var f := FlowTestSupport.mock("mock_scenario_group_reactions")
	var m := _model(f)
	m.add_parcel(1)
	m.choose_use(&"zone.commercial")
	assert_bool(m.last_validation.is_rejected()).is_false()
	m.add_parcel(999)  # olmayan parsel
	assert_that(m.phase()).is_equal(ZoningFlowModel.Phase.INVALID)
	assert_that(m.last_validation.reason_key).is_equal(CommandResult.REJECT_INVALID_TARGET)
	m.remove_parcel(999)
	assert_that(m.phase()).is_equal(ZoningFlowModel.Phase.READY)


# --- Gerekçeli ret ---

func test_invalid_use_is_rejected_with_reason_and_cannot_be_sent_mock() -> void:
	var f := FlowTestSupport.mock("mock_scenario_investment_declined")
	var m := _model(f)
	m.add_parcel(1)
	m.choose_use(&"zone.industrial")
	assert_that(m.phase()).is_equal(ZoningFlowModel.Phase.INVALID)
	assert_that(m.last_validation.reason_key).is_equal(CommandResult.REJECT_INVALID_VALUE)
	assert_str(m.verdict_text()).contains("arazi kullanımı")
	assert_bool(m.can_send()).is_false()
	assert_str(m.send_block_reason()).is_not_empty()
	assert_bool(m.send()).is_false()
	assert_object(m.last_submit).is_null()
	assert_int(f.last_event_seq()).is_equal(0)


func test_invalid_use_is_rejected_with_reason_real() -> void:
	var f := FlowTestSupport.real()
	var m := _model(f)
	m.add_parcel(1)
	m.choose_use(&"zone.industrial")  # gerçek sim bu kullanımı tanımıyor
	assert_that(m.phase()).is_equal(ZoningFlowModel.Phase.INVALID)
	assert_that(m.last_validation.reason_key).is_equal(CommandResult.REJECT_INVALID_VALUE)
	assert_bool(m.last_validation.provenance == SimContract.PROVENANCE_SIM).is_true()


func test_tick_boundary_rejection_shows_the_sim_reason_mock() -> void:
	var f := FlowTestSupport.mock("mock_scenario_invalid_commands")
	var m := _model(f)
	m.add_parcel(2)  # senaryo: parsel 2 koruma alanı, ön doğrulamadan geçer, tick sınırında reddedilir
	m.choose_use(&"zone.commercial")
	assert_that(m.phase()).is_equal(ZoningFlowModel.Phase.READY)
	assert_bool(m.send()).is_true()
	assert_that(m.phase()).is_equal(ZoningFlowModel.Phase.SENT)
	f.advance(3)
	_pump(m, f)
	assert_that(m.phase()).is_equal(ZoningFlowModel.Phase.REFUSED)
	assert_str(m.refusal_text()).contains("Koruma alanında imar değişikliği önerilemez")
	assert_object(m.refusal_event).is_not_null()
	assert_bool(m.can_open_reason()).is_true()


func test_precheck_passes_then_submit_race_rejection_is_refusal() -> void:
	# Doğrulama geçerken gönderim anında ret: sim değişti (parsel kaynağından çıktı gibi).
	var f := FlowTestSupport.real(1)
	var m := _model(f)
	m.add_parcel(1)
	m.choose_use(&"zone.mixed")
	m.parcel_ids = PackedInt64Array([42])  # eski doğrulama geçerli kalır, komut artık geçersiz
	assert_bool(m.send()).is_false()
	assert_that(m.phase()).is_equal(ZoningFlowModel.Phase.REFUSED)
	assert_object(m.refusal_result).is_not_null()
	assert_that(m.refusal_result.reason_key).is_equal(CommandResult.REJECT_INVALID_TARGET)


# --- Mock yolu (uçtan uca) ---

func test_mock_end_to_end_reaches_effective_with_elapsed_days() -> void:
	var f := FlowTestSupport.mock("mock_scenario_investment_declined")
	var m := _model(f)
	m.add_parcel(1)
	m.choose_use(&"zone.mixed")
	assert_bool(m.send()).is_true()
	assert_that(m.last_submit.status).is_equal(CommandResult.STATUS_QUEUED)
	assert_that(m.phase()).is_equal(ZoningFlowModel.Phase.SENT)
	f.advance(1)
	_pump(m, f)
	assert_that(m.phase()).is_equal(ZoningFlowModel.Phase.APPLIED)
	f.advance(1)
	_pump(m, f)
	assert_that(m.phase()).is_equal(ZoningFlowModel.Phase.EFFECTIVE)
	assert_int(m.effective_days()).is_equal(1)
	assert_str(m.status_text()).contains("yürürlüğe girdi")
	assert_bool(m.is_finished()).is_true()


# --- Gerçek sim yolu (uçtan uca) ---

func test_real_end_to_end_effect_arrives_after_the_sims_apply_delay() -> void:
	var f := FlowTestSupport.real()
	var m := _model(f)
	m.add_parcel(1)
	m.choose_use(&"zone.mixed")
	assert_bool(m.send()).is_true()
	assert_that(m.last_submit.provenance).is_equal(SimContract.PROVENANCE_SIM)
	f.advance(1)
	_pump(m, f)
	assert_that(m.phase()).is_equal(ZoningFlowModel.Phase.APPLIED)
	# Bekleyen imar sim'den okunur (ParcelView.pending_zone), UI uydurmaz.
	assert_that(f.parcel_views(PackedInt64Array([1]))[0].pending_zone).is_equal(&"zone.mixed")
	f.advance(1)
	_pump(m, f)
	assert_that(m.phase()).is_equal(ZoningFlowModel.Phase.APPLIED)  # gecikme dolmadı
	f.advance(5)
	_pump(m, f)
	assert_that(m.phase()).is_equal(ZoningFlowModel.Phase.EFFECTIVE)
	assert_int(m.effective_days()).is_equal(3)  # data/sim/facade_config.json apply_delay_days = 3 (gözlenen)
	assert_that(f.parcel_views(PackedInt64Array([1]))[0].zone).is_equal(&"zone.mixed")


func test_real_multi_parcel_becomes_effective_only_when_all_changed() -> void:
	var f := FlowTestSupport.real()
	var m := _model(f)
	m.add_parcel(1)
	m.add_parcel(2)
	m.choose_use(&"zone.commercial")
	m.send()
	f.advance(2)
	_pump(m, f)
	assert_that(m.phase()).is_equal(ZoningFlowModel.Phase.APPLIED)
	f.advance(10)
	_pump(m, f)
	assert_that(m.phase()).is_equal(ZoningFlowModel.Phase.EFFECTIVE)
	assert_int(m.effective_done()).is_equal(2)


func test_partial_effect_is_reported_as_partial() -> void:
	var f := FlowTestSupport.real()
	var m := _model(f)
	m.add_parcel(1)
	m.add_parcel(2)
	m.choose_use(&"zone.commercial")
	m.send()
	m.handle_event(_zone_event(m, 5, "parcel.1"))
	assert_that(m.phase()).is_equal(ZoningFlowModel.Phase.SENT)
	assert_int(m.effective_done()).is_equal(1)
	assert_str(m.status_text()).contains("1/2")
	m.handle_event(_zone_event(m, 5, "parcel.2"))
	assert_that(m.phase()).is_equal(ZoningFlowModel.Phase.EFFECTIVE)


func _zone_event(m: ZoningFlowModel, tick: int, parcel_ref: String) -> SimEvent:
	var e := SimEvent.new()
	e.seq = 100 + tick
	e.tick = tick
	e.kind = SimEvent.KIND_PARCEL_CHANGED
	e.message_key = &"event.zoning.applied"
	e.command_id = m.last_submit.command_id
	e.subjects = PackedStringArray([parcel_ref])
	return e


func test_real_unbuilt_budget_command_is_rejected_with_not_built_reason() -> void:
	# Bütçe önerisi gerçek sim'de kurulmamış: gerekçeli ret (sessiz kabul yok).
	var f := FlowTestSupport.real()
	var r := f.validate_command(SimCommand.budget_propose({&"budget.line.roads": 1000}))
	assert_bool(r.is_rejected()).is_true()
	assert_that(r.reason_key).is_equal(CommandResult.REJECT_PRECONDITION)
	assert_that(r.args.get("why")).is_equal("system.not_built")


# --- Meclis yolu (Q-014: iki yol) ---

func test_council_flag_changes_expected_path_text_not_outcome() -> void:
	var f := FlowTestSupport.mock("mock_scenario_investment_declined")
	var m := _model(f)
	UiPrefs.set_zoning_requires_council(false)
	assert_str(m.path_text()).contains("meclis oylaması olmadan")
	UiPrefs.set_zoning_requires_council(true)
	assert_str(m.path_text()).contains("meclis oylamasına sunulur")
	assert_str(m.submit_label()).is_equal("Meclise sun")
	UiPrefs.set_zoning_requires_council(false)
	assert_str(m.submit_label()).is_equal("Uygula (meclis onayı gerekmiyor)")


func test_council_path_follows_events_voting_then_effective() -> void:
	UiPrefs.set_zoning_requires_council(true)
	var f := FlowTestSupport.mock(FlowTestSupport.ZONING_COUNCIL)
	var m := _model(f)
	m.add_parcel(1)
	m.choose_use(&"zone.mixed")
	assert_bool(m.send()).is_true()
	f.advance(1)
	_pump(m, f)
	assert_that(m.phase()).is_equal(ZoningFlowModel.Phase.VOTING)
	assert_that(m.vote_ref).is_equal(&"vote.1")
	assert_str(m.status_text()).contains("Meclis oylaması bekleniyor")
	f.advance(2)
	_pump(m, f)
	assert_that(m.phase()).is_equal(ZoningFlowModel.Phase.APPLIED)
	assert_bool(m.vote_passed).is_true()
	assert_str(m.status_text()).contains("kabul etti")
	f.advance(3)
	_pump(m, f)
	assert_that(m.phase()).is_equal(ZoningFlowModel.Phase.EFFECTIVE)


func test_flag_true_but_sim_opens_no_vote_stays_honest() -> void:
	# Bayrak yalnız beklenen yolu söyler; sim oylama açmadıysa UI "oylama bekleniyor" demez.
	UiPrefs.set_zoning_requires_council(true)
	var f := FlowTestSupport.real()
	var m := _model(f)
	m.add_parcel(1)
	m.choose_use(&"zone.mixed")
	m.send()
	f.advance(2)
	_pump(m, f)
	assert_that(m.phase()).is_equal(ZoningFlowModel.Phase.APPLIED)
	assert_bool(m.vote_ref == &"").is_true()


func test_failed_vote_is_terminal_with_reason_ids_and_zone_never_changes() -> void:
	var f := FlowTestSupport.mock(FlowTestSupport.ZONING_COUNCIL_FAILED)
	var m := _model(f)
	m.add_parcel(1)
	m.choose_use(&"zone.mixed")
	m.send()
	f.advance(1)
	_pump(m, f)
	assert_that(m.phase()).is_equal(ZoningFlowModel.Phase.VOTING)
	f.advance(2)
	_pump(m, f)
	assert_that(m.phase()).is_equal(ZoningFlowModel.Phase.VOTE_FAILED)
	assert_int(m.reason_ids.size()).is_equal(2)
	assert_bool(m.is_finished()).is_true()
	assert_bool(m.can_open_reason()).is_true()
	f.advance(6)
	_pump(m, f)
	assert_that(m.phase()).is_equal(ZoningFlowModel.Phase.VOTE_FAILED)  # sonraki olaylar sonucu değiştirmez
	assert_that(f.parcel_views(PackedInt64Array([1]))[0].zone).is_equal(&"zone.residential")


# --- Yabancı olaylar ve yeniden başlatma ---

func test_foreign_command_events_are_ignored() -> void:
	var f := FlowTestSupport.mock("mock_scenario_investment_declined")
	var m := _model(f)
	m.add_parcel(1)
	m.choose_use(&"zone.mixed")
	m.send()
	var foreign := SimEvent.new()
	foreign.seq = 50
	foreign.kind = SimEvent.KIND_COMMAND_REJECTED
	foreign.command_id = m.last_submit.command_id + 7
	foreign.message_key = CommandResult.REJECT_INVALID_TARGET
	m.handle_event(foreign)
	assert_that(m.phase()).is_equal(ZoningFlowModel.Phase.SENT)


func test_reset_keeps_area_and_clears_outcome() -> void:
	var f := FlowTestSupport.mock("mock_scenario_investment_declined")
	var m := _model(f)
	m.add_parcel(1)
	m.choose_use(&"zone.mixed")
	m.send()
	f.advance(2)
	_pump(m, f)
	assert_bool(m.is_finished()).is_true()
	m.reset()
	assert_that(m.phase()).is_equal(ZoningFlowModel.Phase.PICK_USE)
	assert_array(Array(m.parcel_ids)).is_equal([1])
	assert_object(m.last_submit).is_null()


func test_area_is_locked_while_a_proposal_is_in_flight() -> void:
	var f := FlowTestSupport.mock("mock_scenario_investment_declined")
	var m := _model(f)
	m.add_parcel(1)
	m.choose_use(&"zone.mixed")
	m.send()
	assert_bool(m.add_parcel(2)).is_false()
	m.remove_parcel(1)
	assert_array(Array(m.parcel_ids)).is_equal([1])
	m.choose_use(&"zone.green")
	assert_that(m.land_use).is_equal(&"zone.mixed")


func test_real_economy_flow_reaches_effect_and_every_recorded_reason_renders_without_missing_keys() -> void:
	UiText.report_missing = false
	var f := FlowTestSupport.real_economy()
	var m := _model(f)
	m.add_parcel(1)
	m.choose_use(&"zone.mixed")
	assert_bool(m.send()).is_true()
	for i in 60:
		f.advance(1)
		_pump(m, f)
	assert_that(m.phase()).is_equal(ZoningFlowModel.Phase.EFFECTIVE)
	# Sim'in kaydettiği gerekçeler (command.N konulu) ReasonPanel'de çözülür; eksik metin anahtarı kalmaz.
	var cmd_ref := StringName("command.%d" % m.last_submit.command_id)
	var records := f.reasons_for(cmd_ref)
	records.append_array(f.reasons_for(&"parcel.1"))
	assert_int(records.size()).override_failure_message("ekonomi gerekçe kaydı üretmedi").is_greater(0)
	assert_int(m.effective_days()).is_greater(0)
	var panel := ReasonPanel.create(UiContext.for_profile_name(&"desktop"), f)
	add_child(auto_free(panel))
	for r in records:
		panel.show_record(r.id)
		panel.refresh()
	assert_array(Array(UiText.missing_keys())).override_failure_message(
		"eksik metin anahtarları: %s" % [UiText.missing_keys()]).is_empty()
