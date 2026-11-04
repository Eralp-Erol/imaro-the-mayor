extends PoliticsTestBase
## T-017 ölçüt 7 · Mock/gerçek parity (ADR-0005): gerçek siyasi katmanın grup tepkisi ve meclis oylaması DTO şekilleri
## T-023 mock senaryolarıyla aynı alan kümelerini ve değer kümelerini taşır (UI mock'tan gerçeğe kod değişmeden geçer);
## olay anahtarları mock adlandırmasıyla uyumlu; tüm siyasi gerekçeler UI ReasonPanel değişmez kontrolünden geçer.

const MOCK_GROUPS := "res://tests/fixtures/mock_scenario_group_reactions.json"
const MOCK_COUNCIL := "res://tests/fixtures/mock_scenario_council_budget_vote.json"


func before_test() -> void:
	UiText.reset()
	UiText.report_missing = false


func after_test() -> void:
	UiText.reset()


func _mock_group_keys() -> Array:
	var mock := MockSimFacade.from_file(MOCK_GROUPS)
	mock.submit_command(SimCommand.zoning_propose(PackedInt64Array([2]), &"zone.commercial"))
	mock.advance(5)
	return mock.snapshot().group_reactions[0].to_dict().keys()


func _mock_council() -> CouncilView:
	var mock := MockSimFacade.from_file(MOCK_COUNCIL)
	mock.submit_command(SimCommand.budget_propose({&"budget.line.roads": 50000}))
	mock.advance(5)
	return mock.snapshot().council


func _real(ticks: int = 200, with_council: bool = false) -> PoliticsHandle:
	var h: PoliticsHandle
	if with_council:  # imar önerisi meclis oylamasından geçer (requires_council veri varsayılanı)
		h = handle(E.regions(STRESS), 14)
		h.facade.submit_command(SimCommand.zoning_propose(h.facade.parcel_ids(), &"zone.mixed"))
	else:
		h = stress_handle(14)
	tick(h, ticks)
	return h


func _sorted(keys: Array) -> Array:
	var out := keys.duplicate()
	out.sort()
	return out


func test_group_reaction_shape_matches_the_mock_field_for_field() -> void:
	var real := _real().facade.snapshot().group_reactions[0].to_dict()
	assert_array(_sorted(real.keys())).is_equal(_sorted(_mock_group_keys()))
	for key in real:
		var mock_group := MockSimFacade.from_file(MOCK_GROUPS).snapshot().group_reactions[0].to_dict()
		assert_int(typeof(real[key])).override_failure_message("alan türü: %s" % key).is_equal(typeof(mock_group[key]))


func test_real_reaction_values_stay_inside_the_vocabulary_the_mock_uses() -> void:
	var h := _real()
	var mock_reactions := {}
	var mock := MockSimFacade.from_file(MOCK_GROUPS)
	mock.submit_command(SimCommand.zoning_propose(PackedInt64Array([2]), &"zone.commercial"))
	mock.advance(5)
	for g in mock.snapshot().group_reactions:
		mock_reactions[String(g.reaction)] = true
	assert_array(mock_reactions.keys()).contains(["support", "protest"])
	var seen := {}
	for e in events_of(h, &"group.reacted"):
		seen[String(e.message_key)] = true
		assert_str(String(e.kind)).is_equal(SimEvent.KIND_GROUP_REACTED)
		assert_bool(e.actor != null and e.actor.is_valid()).is_true()
		assert_bool(e.reason_ids.is_empty()).is_false()
	assert_bool(seen.has("event.group.support")).override_failure_message(str(seen.keys())).is_true()
	assert_bool(seen.has("event.group.protest") or seen.has("event.group.oppose")).is_true()
	for g in h.facade.snapshot().group_reactions:
		assert_array([&"neutral", &"support", &"oppose", &"protest"]).contains([g.reaction])
		for cause in g.cause_refs:
			assert_bool(cause.begins_with("parcel.")).is_true()


func test_council_and_vote_shapes_match_the_mock() -> void:
	var h := handle()
	h.facade.advance(1)
	CouncilEngine.open_vote(h.state(), h.context, CouncilEngine.budget_spec(1, {}, {}))
	h.facade.advance(20)
	var real := h.facade.snapshot().council
	var mock := _mock_council()
	assert_array(_sorted(real.to_dict().keys())).is_equal(_sorted(mock.to_dict().keys()))
	assert_array(_sorted(real.votes[0].to_dict().keys())).is_equal(_sorted(mock.votes[0].to_dict().keys()))
	assert_array(_sorted(real.votes[0].positions[0].to_dict().keys())).is_equal(
		_sorted(mock.votes[0].positions[0].to_dict().keys()))
	assert_array(_sorted(real.blocs[0].to_dict().keys())).is_equal(_sorted(mock.blocs[0].to_dict().keys()))
	assert_array(["passed", "failed"]).contains([String(real.votes[0].status)])
	assert_array(["passed", "failed"]).contains([String(mock.votes[0].status)])
	assert_array(["yes", "no", "abstain"]).contains([String(real.votes[0].positions[0].position)])
	assert_array(events_of(h, SimEvent.KIND_COUNCIL_VOTE_RESOLVED)).is_not_empty()
	assert_array(events_of(h, SimEvent.KIND_COUNCIL_VOTE_OPENED)).is_not_empty()


func test_every_political_reason_passes_the_contract_and_the_ui_checker() -> void:
	var h := _real(260, true)
	var state := h.state()
	var kinds := {}
	for id in range(state.reasons.first_id(), state.reasons.last_id() + 1):
		var record := h.facade.reason(id)
		assert_object(record).is_not_null()
		assert_str(record.consistency_error()).override_failure_message("kayıt %d" % id).is_empty()
		var model := ReasonModel.from_record(record)
		assert_bool(model.is_consistent()).override_failure_message("UI değişmezi %d: %s" % [id, str(model.issues)]).is_true()
		kinds[String(record.decision_key).get_slice(".", 1)] = true
		for parent in record.parent_ids:
			assert_int(parent).is_less(id)
	assert_array(kinds.keys()).contains(["bloc", "council", "media", "investor"])


func test_the_real_reason_panel_shows_political_decisions_without_an_inconsistency_banner() -> void:
	var h := _real(260, true)
	var ctx := UiContext.for_profile_name(&"desktop")
	var holder := Control.new()
	holder.theme = UiTheme.build(ctx)
	holder.size = Vector2(440, 1200)
	add_child(holder)
	auto_free(holder)
	var panel := ReasonPanel.create(ctx, h.facade)
	holder.add_child(panel)
	panel.size = holder.size
	var checked := 0
	var political := 0
	for id in range(h.state().reasons.first_id(), h.state().reasons.last_id() + 1):
		panel.show_record(id)
		assert_array(panel.find_roles(ReasonPanel.NAME_BANNER)).override_failure_message("kayıt %d tutarsız görünüyor" % id) \
			.is_empty()
		checked += 1
		political += 1 if not String(h.facade.reason(id).decision_key).begins_with("decision.investor") else 0
	assert_int(checked).is_greater(10)
	assert_int(political).is_greater(5)
	assert_bool(panel.badge.visible).override_failure_message("sim kaynaklı veri MOCK görünmemeli").is_false()


func test_event_fire_reasons_with_the_system_actor_pass_the_ui_checker_too() -> void:
	var h := handle(E.regions(STRESS), 14, SEED, func(f: Dictionary) -> void:
		f["templates"]["pe-04"]["weight"] = 1000
		f["templates"]["pe-04"]["hard"] = []
		for driver: Dictionary in f["templates"]["pe-04"]["drivers"]:
			driver["lo"] = -100000
			driver["hi"] = -99999)
	tick(h, 8)
	var fires := reasons_of(h, "decision.event.fire")
	assert_int(fires.size()).is_greater(0)
	var record := h.facade.reason(fires[0]["id"])
	assert_bool(record.is_consistent()).is_true()
	assert_bool(ReasonModel.from_record(record).is_consistent()).is_true()
	assert_str(String(record.actor.kind)).is_equal("sys")


func test_snapshot_group_and_council_dto_dicts_round_trip_losslessly() -> void:
	var h := _real()
	var snapshot := h.facade.snapshot()
	for g in snapshot.group_reactions:
		assert_bool(g.same_as(GroupReactionView.from_dict(g.to_dict()))).is_true()
	assert_bool(snapshot.council.same_as(CouncilView.from_dict(snapshot.council.to_dict()))).is_true()
