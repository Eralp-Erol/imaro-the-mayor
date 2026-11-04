extends ActorTestBase
## T-016 ölçüt 6 · `ReasonLog` sözleşme hizası: aktör kararları `actor.*` ref'li, `subjects`/`parent_ids` doğru,
## ReasonRecord değişmezi ve UI ReasonPanel'in kendi değişmez kontrolü (ReasonModel) aynı kayıtları KABUL eder;
## bozulmuş kayıt ikisinde de işaretlenir (olumsuz kontrol). Gerçek `SimFacadeImpl` ile (mock değil).

const TICKS := 130


func before_test() -> void:
	UiText.reset()
	UiText.report_missing = false


func after_test() -> void:
	UiText.reset()


func _run() -> SimFacadeImpl:
	var cfg := config()
	var systems: Array[SimSystem] = [ActorSystem.create(cfg), ActorScenarioSystem.new(cfg)]
	var impl := SimFacadeImpl.create(SEED, FacadeTestSupport.fixture_source(3), null, null, systems)
	impl.advance(TICKS)
	return impl


func _retained_ids(f: SimFacadeImpl) -> Array[int]:
	var ids: Array[int] = []
	var state := f.game_state()
	for id in range(state.reasons.first_id(), state.reasons.last_id() + 1):
		ids.append(id)
	return ids


func test_every_actor_reason_satisfies_the_contract_invariant_and_the_ui_checker() -> void:
	var f := _run()
	var roster := ActorStore.keys(f.game_state())
	var seen_kinds := {}
	var ids := _retained_ids(f)
	assert_int(ids.size()).override_failure_message("ölü senaryo").is_greater(15)
	for id in ids:
		var r := f.reason(id)
		assert_object(r).override_failure_message("kayıt %d çözülmüyor" % id).is_not_null()
		assert_str(r.consistency_error()).override_failure_message("sözleşme değişmezi %d" % id).is_empty()
		var model := ReasonModel.from_record(r)
		assert_bool(model.is_consistent()).override_failure_message("UI değişmezi %d: %s" % [id, str(model.issues)]).is_true()
		assert_bool(r.actor != null and r.actor.is_valid()).is_true()
		assert_bool(roster.has(String(r.actor.ref()))).override_failure_message("kadroda olmayan aktör").is_true()
		seen_kinds[String(r.actor.kind)] = true
		assert_str(String(r.actor.name_key)).is_equal(String(r.actor.ref()) + ".name")
		assert_bool(String(r.decision_key).begins_with("decision.")).is_true()
		assert_int(r.factors.size()).override_failure_message("tek faktörlü gerekçe").is_greater_equal(3)
		var absolute := 0
		for fa in r.factors:
			assert_bool(String(fa.name_key).begins_with("reason.factor.")).is_true()
			absolute += 0 if fa.name_key == ActorDecision.NOISE_FACTOR else absi(fa.weight)
		assert_int(absolute).override_failure_message("kayıt %d: Σ|ağırlık| != 1000" % id).is_equal(1000)
		assert_str(String(r.provenance)).is_equal("sim")
		for parent in r.parent_ids:
			assert_int(parent).is_less(id)
	assert_array(seen_kinds.keys()).contains(["council", "bloc"])
	assert_array(SimContractChecks.check_facade(f)).is_empty()


func test_subjects_and_actor_queries_return_the_recorded_decisions() -> void:
	var f := _run()
	var by_actor := f.reasons_for(StringName(COUNCIL_1))
	assert_int(by_actor.size()).is_greater(2)
	for r in by_actor:
		assert_str(String(r.actor.ref())).is_equal(COUNCIL_1)
	var by_vote := f.reasons_for(&"vote.2")
	assert_int(by_vote.size()).override_failure_message("her meclis üyesi bir kayıt").is_equal(5)
	var members := {}
	for r in by_vote:
		members[String(r.actor.ref())] = true
		assert_array(Array(r.subjects)).contains(["vote.2"])
	assert_int(members.size()).is_equal(5)
	var reacted := f.reasons_for(&"parcel.1")
	assert_bool(reacted.is_empty()).override_failure_message("kesim tepkisi parsele bağlı").is_false()


func test_decision_events_link_to_resolvable_reasons_of_the_same_actor() -> void:
	var f := _run()
	var decided := f.events_since(0).filter(func(e: SimEvent) -> bool: return e.kind == &"actor.decided")
	assert_int(decided.size()).is_greater(10)
	for e: SimEvent in decided:
		assert_bool(e.actor != null and e.actor.is_valid()).is_true()
		assert_bool(e.reason_ids.is_empty()).is_false()
		for rid in e.reason_ids:
			assert_str(String(f.reason(rid).actor.ref())).is_equal(String(e.actor.ref()))


func test_tampered_records_are_flagged_by_both_checkers() -> void:
	var f := _run()
	var original := f.reason(f.game_state().reasons.last_id())
	assert_bool(original.is_consistent()).is_true()
	var wrong_score := ReasonRecord.from_dict(original.to_dict())
	wrong_score.score += 1
	assert_bool(wrong_score.is_consistent()).is_false()
	assert_bool(ReasonModel.from_record(wrong_score).has_issue(ReasonModel.ISSUE_SCORE)).is_true()
	var wrong_outcome := ReasonRecord.from_dict(original.to_dict())
	wrong_outcome.outcome = ReasonRecord.OUTCOME_NEGATIVE if original.outcome == ReasonRecord.OUTCOME_POSITIVE \
		else ReasonRecord.OUTCOME_POSITIVE
	assert_bool(wrong_outcome.is_consistent()).is_false()
	assert_bool(ReasonModel.from_record(wrong_outcome).has_issue(ReasonModel.ISSUE_OUTCOME)).is_true()


func test_the_real_reason_panel_renders_actor_decisions_without_an_inconsistency_banner() -> void:
	var f := _run()
	var ctx := UiContext.for_profile_name(&"desktop")
	var holder := Control.new()
	holder.theme = UiTheme.build(ctx)
	holder.size = Vector2(440, 1200)
	add_child(holder)
	auto_free(holder)
	var panel := ReasonPanel.create(ctx, f)
	holder.add_child(panel)
	panel.size = holder.size
	var checked := 0
	for id in _retained_ids(f):
		panel.show_record(id)
		assert_array(panel.find_roles(ReasonPanel.NAME_BANNER)).override_failure_message("kayıt %d tutarsız görünüyor" % id) \
			.is_empty()
		checked += 1
	assert_int(checked).is_greater(15)
	assert_bool(panel.badge.visible).override_failure_message("sim kaynaklı veri MOCK görünmemeli").is_false()
	panel.show_subject(&"vote.2")
	assert_int(panel.find_roles(ReasonPanel.NAME_ROW).size()) \
		.override_failure_message("aynı oylamanın 5 kaydı listelenir") \
		.is_equal(5)
