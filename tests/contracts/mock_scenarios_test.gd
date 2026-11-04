extends GdUnitTestSuite
## T-023 ölçüt 3/5 · Beş MOCK senaryosu: (i) olumlu yatırım kararı, (ii) aynı imar farklı koşulda yatırım gelmiyor
## (SIM-07), (iii) ≥2 grup zıt tepki (SIM-09), (iv) meclis bütçe oylaması (SIM-05), (v) geçersiz komut gerekçeli reddi
## (CAN-03). Determinizm: aynı senaryo + komutlar → aynı hash; farklı komut → farklı hash. Her yerde MOCK işareti.

const S := preload("res://tests/contracts/contract_test_support.gd")
const HORIZON := 30


func _zoning(ids: Array, land_use: StringName) -> SimCommand:
	return SimCommand.zoning_propose(PackedInt64Array(ids), land_use)


func _budget_cmd() -> SimCommand:
	return SimCommand.budget_propose({&"budget.line.roads": 50000, &"budget.line.parks": 20000})


## Senaryonun ana komutunu gönderip ufka kadar ilerletir.
func _drive(scenario_name: String) -> MockSimFacade:
	var f := S.facade(scenario_name)
	if scenario_name == S.SCENARIO_COUNCIL:
		f.submit_command(_budget_cmd())
	elif scenario_name == S.SCENARIO_GROUPS:
		f.submit_command(_zoning([2], &"zone.commercial"))
	else:
		f.submit_command(_zoning([1], &"zone.mixed"))
	f.advance(HORIZON)
	return f


func _investor_reason(f: SimFacade) -> ReasonRecord:
	for r in f.reasons_for(&"parcel.1"):
		if r.decision_key == &"decision.investor.develop":
			return r
	return null


# --- (i) olumlu yatırım ---

func test_zoning_change_leads_to_positive_investor_decision_with_reason() -> void:
	var f := _drive(S.SCENARIO_POSITIVE)
	var r := _investor_reason(f)
	assert_object(r).is_not_null()
	assert_str(String(r.outcome)).is_equal("positive")
	assert_int(r.factors.size()).is_equal(4)
	assert_int(r.score).is_equal(590)
	assert_int(r.threshold).is_equal(500)
	assert_bool(r.is_consistent()).is_true()
	assert_bool(r.subjects.has("command.1")).is_true()
	assert_str(String(r.actor.ref())).is_equal("actor.investor.1")
	var p := f.parcel_views(S.ids([1]))[0]
	assert_str(String(p.zone)).is_equal("zone.mixed")
	assert_str(String(p.development)).is_equal("under_construction")
	assert_str(String(p.owner.ref())).is_equal("actor.investor.1")
	assert_bool(p.reason_ids.has(r.id)).is_true()
	var decided := S.events_of(f, SimEvent.KIND_ACTOR_DECIDED)
	assert_int(decided.size()).is_equal(1)
	assert_bool(decided[0].reason_ids.has(r.id)).is_true()


func test_development_takes_time() -> void:
	var f := S.facade(S.SCENARIO_POSITIVE)
	f.submit_command(_zoning([1], &"zone.mixed"))
	f.advance(3)
	assert_object(_investor_reason(f)).is_null()
	assert_str(String(f.parcel_views(S.ids([1]))[0].development)).is_equal("vacant")
	f.advance(2)
	assert_str(String(f.parcel_views(S.ids([1]))[0].development)).is_equal("planned")
	f.advance(5)
	assert_str(String(f.parcel_views(S.ids([1]))[0].development)).is_equal("under_construction")


# --- (ii) yatırım gelmiyor ---

func test_same_zoning_under_different_conditions_brings_no_investment() -> void:
	var f := _drive(S.SCENARIO_DECLINED)
	var r := _investor_reason(f)
	assert_object(r).is_not_null()
	assert_str(String(r.outcome)).is_equal("negative")
	assert_int(r.score).is_equal(200)
	assert_bool(r.score < r.threshold).is_true()
	assert_bool(r.is_consistent()).is_true()
	var p := f.parcel_views(S.ids([1]))[0]
	assert_str(String(p.zone)).override_failure_message("zoning itself still applies").is_equal("zone.mixed")
	assert_str(String(p.development)).override_failure_message("SIM-07: no investment").is_equal("vacant")
	assert_str(String(p.owner.ref())).is_equal("actor.landowner.1")
	assert_bool(p.reason_ids.has(r.id)).override_failure_message("vacancy must be explained").is_true()
	assert_str(String(S.events_of(f, SimEvent.KIND_ACTOR_DECIDED)[0].message_key)).is_equal("event.investor.declined")


func test_positive_and_declined_share_command_and_decision_but_not_outcome() -> void:
	var pos := _investor_reason(_drive(S.SCENARIO_POSITIVE))
	var neg := _investor_reason(_drive(S.SCENARIO_DECLINED))
	assert_str(String(pos.decision_key)).is_equal(String(neg.decision_key))
	assert_str(String(pos.outcome)).is_not_equal(String(neg.outcome))
	var names_pos: Array = pos.factors.map(func(x: ReasonFactor) -> StringName: return x.name_key)
	var names_neg: Array = neg.factors.map(func(x: ReasonFactor) -> StringName: return x.name_key)
	assert_array(names_pos).is_equal(names_neg)


# --- (iii) grup tepkileri ---

func test_two_groups_react_in_opposite_directions_with_reasons() -> void:
	var f := _drive(S.SCENARIO_GROUPS)
	var groups := f.snapshot().group_reactions
	assert_int(groups.size()).is_greater_equal(2)
	var support: GroupReactionView = null
	var protest: GroupReactionView = null
	for g in groups:
		if g.reaction == GroupReactionView.REACTION_SUPPORT:
			support = g
		elif g.reaction == GroupReactionView.REACTION_PROTEST:
			protest = g
	assert_object(support).is_not_null()
	assert_object(protest).is_not_null()
	assert_str(String(support.group.ref())).is_not_equal(String(protest.group.ref()))
	assert_bool(support.stance_delta > 0 and protest.stance_delta < 0).is_true()
	for g: GroupReactionView in [support, protest]:
		assert_int(g.reason_ids.size()).is_equal(1)
		var r := f.reason(g.reason_ids[0])
		assert_bool(r.is_consistent()).is_true()
		assert_str(String(r.actor.ref())).is_equal(String(g.group.ref()))
		assert_bool(g.cause_refs.has("parcel.2")).is_true()
	assert_int(S.events_of(f, SimEvent.KIND_GROUP_REACTED).size()).is_equal(2)


func test_no_single_aggregate_score_anywhere() -> void:
	for scenario_name in S.ALL_SCENARIOS:
		var state := SimContractChecks.observable_state(_drive(scenario_name))
		assert_array(SimContractChecks.check_no_aggregate_score(state, scenario_name)).is_empty()
	# Olumsuz: denetim gerçekten yakalar.
	assert_array(SimContractChecks.check_no_aggregate_score({"a": [{"Happiness": 50}]}, "x")).is_not_empty()


# --- (iv) meclis bütçe oylaması ---

func test_budget_proposal_goes_through_council_vote() -> void:
	var f := S.facade(S.SCENARIO_COUNCIL)
	assert_str(String(f.submit_command(_budget_cmd()).status)).is_equal("queued")
	f.advance(1)
	var snap := f.snapshot()
	assert_str(String(snap.budget.status)).is_equal("proposed")
	assert_int(snap.budget.pending_vote_id).is_equal(1)
	assert_int(snap.budget.line(&"budget.line.roads").amount).override_failure_message("not yet in force") \
		.is_equal(40000)
	var vote := snap.council.vote(1)
	assert_str(String(vote.status)).is_equal("pending")
	assert_int(vote.opened_tick).is_equal(1)
	assert_int(vote.closes_tick).is_equal(4)
	var second := f.submit_command(_budget_cmd())
	assert_str(String(second.reason_key)).is_equal(String(CommandResult.REJECT_PRECONDITION))
	f.advance(3)
	snap = f.snapshot()
	vote = snap.council.vote(1)
	assert_str(String(vote.status)).is_equal("passed")
	assert_int(vote.yes).is_equal(6)
	assert_int(vote.no).is_equal(5)
	assert_int(vote.opened_tick).override_failure_message("opened tick preserved").is_equal(1)
	assert_int(vote.positions.size()).is_equal(2)
	assert_str(String(f.reason(vote.positions[0].reason_id).outcome)).is_equal("positive")
	assert_str(String(f.reason(vote.positions[1].reason_id).outcome)).is_equal("negative")
	assert_str(String(snap.budget.status)).is_equal("approved")
	assert_int(snap.budget.line(&"budget.line.roads").amount).is_equal(50000)
	assert_int(snap.budget.line(&"budget.line.services").amount).is_equal(50000)
	assert_int(snap.budget.pending_vote_id).is_equal(0)
	assert_int(S.events_of(f, SimEvent.KIND_COUNCIL_VOTE_RESOLVED).size()).is_equal(1)
	assert_int(f.reasons_for(&"vote.1").size()).is_equal(2)


# --- (v) geçersiz komutlar ---

func test_invalid_commands_are_rejected_with_reason_and_change_nothing() -> void:
	var f := S.facade(S.SCENARIO_INVALID)
	var before := S.observable_hash(f)
	var cases := [
		[SimCommand.make(&"building.place", {"parcel_ids": PackedInt64Array([1])}), CommandResult.REJECT_NOT_A_MAYOR_VERB],
		[SimCommand.make(&"zoning.teleport"), CommandResult.REJECT_UNKNOWN_KIND],
		[SimCommand.make(&"zoning.propose", {"land_use": &"zone.mixed"}), CommandResult.REJECT_MISSING_PARAM],
		[_zoning([99], &"zone.mixed"), CommandResult.REJECT_INVALID_TARGET],
		[_zoning([1], &"zone.casino"), CommandResult.REJECT_INVALID_VALUE],
		[SimCommand.budget_propose({&"budget.line.unknown": 5}), CommandResult.REJECT_INVALID_TARGET],
		[null, CommandResult.REJECT_UNKNOWN_KIND],
	]
	for c: Array in cases:
		var r := f.submit_command(c[0])
		assert_str(String(r.status)).is_equal("rejected")
		assert_str(String(r.reason_key)).override_failure_message("case %s" % [c]).is_equal(String(c[1]))
		assert_int(r.command_id).is_equal(SimContract.NO_ID)
		assert_str(String(r.provenance)).is_equal("mock")
	f.advance(2)
	var untouched := S.facade(S.SCENARIO_INVALID)
	untouched.advance(2)
	assert_str(S.observable_hash(f)).is_equal(S.observable_hash(untouched))
	assert_str(before).is_not_empty()
	assert_int(f.submit_command(_zoning([1], &"zone.mixed")).command_id) \
		.override_failure_message("rejected commands must not consume ids").is_equal(1)


func test_state_dependent_rejection_happens_at_tick_boundary_with_event() -> void:
	var f := S.facade(S.SCENARIO_INVALID)
	var r := f.submit_command(_zoning([2], &"zone.mixed"))
	assert_str(String(r.status)).is_equal("queued")
	f.advance(1)
	var rejected := S.events_of(f, SimEvent.KIND_COMMAND_REJECTED)
	assert_int(rejected.size()).is_equal(1)
	assert_int(rejected[0].command_id).is_equal(r.command_id)
	assert_str(String(rejected[0].message_key)).is_equal(String(CommandResult.REJECT_INVALID_TARGET))
	assert_dict(rejected[0].args).is_equal({"why": "zoning.reject.protected_area"})
	assert_array(S.events_of(f, SimEvent.KIND_COMMAND_APPLIED)).is_empty()
	var p := f.parcel_views(S.ids([2]))[0]
	assert_str(String(p.pending_zone)).is_empty()
	assert_str(String(p.zone)).is_equal("zone.residential")


# --- Determinizm ---

func test_same_scenario_and_commands_give_same_hash() -> void:
	for scenario_name in S.ALL_SCENARIOS:
		var a := S.observable_hash(_drive(scenario_name))
		var b := S.observable_hash(_drive(scenario_name))
		assert_int(a.length()).is_equal(64)
		assert_str(a).override_failure_message(scenario_name).is_equal(b)


func test_different_commands_or_conditions_give_different_hash() -> void:
	var idle := S.facade(S.SCENARIO_POSITIVE)
	idle.advance(HORIZON)
	assert_str(S.observable_hash(idle)).is_not_equal(S.observable_hash(_drive(S.SCENARIO_POSITIVE)))
	assert_str(S.observable_hash(_drive(S.SCENARIO_POSITIVE))) \
		.is_not_equal(S.observable_hash(_drive(S.SCENARIO_DECLINED)))


# --- MOCK işareti ---

func test_mock_data_is_marked_mock_everywhere() -> void:
	for scenario_name in S.ALL_SCENARIOS:
		var raw := S.scenario_dict(scenario_name)
		assert_str(str(raw["provenance"])).is_equal("MOCK")
		assert_bool(str(raw["description"]).begins_with("MOCK")).is_true()
		var f := _drive(scenario_name)
		assert_bool(f.snapshot().is_mock()).is_true()
		for e in f.events_since(0):
			assert_str(String(e.provenance)).is_equal("mock")
			for rid in e.reason_ids:
				assert_str(String(f.reason(rid).provenance)).is_equal("mock")
		for p in f.parcel_views(f.parcel_ids()):
			assert_str(String(p.provenance)).is_equal("mock")
			if p.owner != null:
				assert_bool(String(p.owner.name_key).begins_with("mock.")).is_true()


func test_mock_parcels_lie_on_fixture_land_in_their_region() -> void:
	var world := WorldFixture.build()
	for scenario_name in S.ALL_SCENARIOS:
		var f := S.facade(scenario_name)
		assert_str(String(f.snapshot().world_id)).is_equal(String(world.world_id))
		for p in f.parcel_views(f.parcel_ids()):
			assert_bool(world.is_water(p.center.x, p.center.y)) \
				.override_failure_message("%s parcel %d in water" % [scenario_name, p.id]).is_false()
			assert_str(String(world.region_code_at(p.center.x, p.center.y))).is_equal(String(p.region_code))
