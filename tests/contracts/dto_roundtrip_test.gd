extends GdUnitTestSuite
## T-023 ölçüt 2/5 · Her DTO var_to_bytes ile serileşir, StateHash ile karşılaştırılabilir, JSON'dan kayıpsız
## kanonikleşir; sürüm kuralı (MAJOR reddi, MINOR kabul) ve geri uyum (eksik alan → varsayılan).


func _actor(kind: StringName, id: int) -> ActorRef:
	return ActorRef.make(kind, id, StringName("mock.actor.%s.%d" % [kind, id]))


func _reason() -> ReasonRecord:
	var r := ReasonRecord.new()
	r.id = 7
	r.tick = 12
	r.actor = _actor(&"investor", 3)
	r.decision_key = &"decision.investor.develop"
	r.factors.append(ReasonFactor.make(&"reason.factor.demand", 700, 400))
	var est := ReasonFactor.make(&"reason.factor.construction_cost", -300, 100)
	est.is_estimate = true
	est.source_ref = &"parcel.4"
	r.factors.append(est)
	r.threshold = 200
	r.subjects = PackedStringArray(["parcel.4", "command.2"])
	r.parent_ids = PackedInt64Array([3, 5])
	r.provenance = SimContract.PROVENANCE_MOCK
	return r.finalize()


func _parcel() -> ParcelView:
	var p := ParcelView.new()
	p.id = 4
	p.region_code = &"F1"
	p.center = Vector2(-412.5, 1250.25)
	p.area_m2 = 1800
	p.zone = &"zone.mixed"
	p.pending_zone = &"zone.commercial"
	p.development = ParcelView.DEVELOPMENT_PLANNED
	p.owner = _actor(&"investor", 3)
	p.land_value = 2600
	p.reason_ids = PackedInt64Array([7])
	return p


func _budget() -> BudgetView:
	var b := BudgetView.new()
	b.period = 2
	b.status = BudgetView.STATUS_PROPOSED
	b.revenue = 120000
	b.balance = -500
	b.lines.append(BudgetLineView.make(&"budget.line.roads", 40000))
	var parks := BudgetLineView.make(&"budget.line.parks", 15000)
	parks.proposed = 20000
	parks.actual = 300
	b.lines.append(parks)
	b.pending_vote_id = 1
	b.reason_ids = PackedInt64Array([1, 2])
	return b


func _vote() -> CouncilVoteView:
	var v := CouncilVoteView.new()
	v.vote_id = 1
	v.subject_ref = &"budget.2"
	v.title_key = &"council.vote.budget"
	v.opened_tick = 3
	v.closes_tick = 6
	v.status = CouncilVoteView.STATUS_PASSED
	v.yes = 6
	v.no = 5
	var pos := CouncilBlocView.new()
	pos.bloc = _actor(&"council_bloc", 1)
	pos.seats = 6
	pos.stance = 200
	pos.position = CouncilBlocView.POSITION_YES
	pos.reason_id = 1
	v.positions.append(pos)
	v.reason_ids = PackedInt64Array([1])
	return v


func _council() -> CouncilView:
	var c := CouncilView.new()
	c.council = _actor(&"council", 1)
	c.seats_total = 11
	var bloc := CouncilBlocView.new()
	bloc.bloc = _actor(&"council_bloc", 2)
	bloc.seats = 5
	bloc.stance = -300
	c.blocs.append(bloc)
	c.votes.append(_vote())
	return c


func _group() -> GroupReactionView:
	var g := GroupReactionView.new()
	g.group = _actor(&"group", 2)
	g.region_code = &"F1"
	g.stance = -400
	g.stance_delta = -300
	g.reaction = GroupReactionView.REACTION_PROTEST
	g.intensity = 700
	g.cause_refs = PackedStringArray(["parcel.2"])
	g.reason_ids = PackedInt64Array([2])
	g.tick = 3
	return g


func _snapshot() -> SimSnapshot:
	var s := SimSnapshot.new()
	s.provenance = SimContract.PROVENANCE_MOCK
	s.world_id = &"fixture.world"
	s.scenario_id = &"mock_x"
	s.clock.tick = 42
	s.clock.speed = SimFacade.SPEED_FAST
	s.clock.available_speeds = PackedInt32Array([0, 1, 2])
	s.last_event_seq = 9
	s.parcel_count = 3
	s.budget = _budget()
	s.council = _council()
	s.group_reactions.append(_group())
	s.extensions = {"x.ux.focus": "parcel.4"}
	return s


func _event() -> SimEvent:
	var e := SimEvent.new()
	e.seq = 5
	e.tick = 4
	e.kind = SimEvent.KIND_ACTOR_DECIDED
	e.actor = _actor(&"investor", 3)
	e.subjects = PackedStringArray(["parcel.4"])
	e.message_key = &"event.investor.develop"
	e.args = {"count": 2, "zone": "zone.mixed"}
	e.reason_ids = PackedInt64Array([7])
	e.command_id = 2
	return e


func _command_result() -> CommandResult:
	var cmd := SimCommand.zoning_propose(PackedInt64Array([99]), &"zone.mixed")
	var r := CommandResult.rejected(cmd, CommandResult.REJECT_INVALID_TARGET, {"ref": &"parcel.99"}, 5, &"mock")
	r.reason_ids = PackedInt64Array([3])
	return r


## [ad, örnek DTO, from_dict çağrısı]
func _samples() -> Array:
	return [
		["ActorRef", _actor(&"investor", 3), func(d: Dictionary) -> SimDto: return ActorRef.from_dict(d)],
		["ReasonFactor", _reason().factors[1], func(d: Dictionary) -> SimDto: return ReasonFactor.from_dict(d)],
		["ReasonRecord", _reason(), func(d: Dictionary) -> SimDto: return ReasonRecord.from_dict(d)],
		["ParcelView", _parcel(), func(d: Dictionary) -> SimDto: return ParcelView.from_dict(d)],
		["BudgetLineView", _budget().lines[1], func(d: Dictionary) -> SimDto: return BudgetLineView.from_dict(d)],
		["BudgetView", _budget(), func(d: Dictionary) -> SimDto: return BudgetView.from_dict(d)],
		["CouncilBlocView", _vote().positions[0], func(d: Dictionary) -> SimDto: return CouncilBlocView.from_dict(d)],
		["CouncilVoteView", _vote(), func(d: Dictionary) -> SimDto: return CouncilVoteView.from_dict(d)],
		["CouncilView", _council(), func(d: Dictionary) -> SimDto: return CouncilView.from_dict(d)],
		["GroupReactionView", _group(), func(d: Dictionary) -> SimDto: return GroupReactionView.from_dict(d)],
		["ClockView", _snapshot().clock, func(d: Dictionary) -> SimDto: return ClockView.from_dict(d)],
		["SimSnapshot", _snapshot(), func(d: Dictionary) -> SimDto: return SimSnapshot.from_dict(d)],
		["SimEvent", _event(), func(d: Dictionary) -> SimDto: return SimEvent.from_dict(d)],
		["SimCommand", SimCommand.budget_propose({&"budget.line.roads": 5}),
			func(d: Dictionary) -> SimDto: return SimCommand.from_dict(d)],
		["CommandResult", _command_result(), func(d: Dictionary) -> SimDto: return CommandResult.from_dict(d)],
	]


func test_every_dto_roundtrips_through_var_to_bytes_with_equal_hash() -> void:
	for sample: Array in _samples():
		var dto: SimDto = sample[1]
		var from_dict: Callable = sample[2]
		var bytes := dto.to_bytes()
		var back: SimDto = from_dict.call(bytes_to_var(bytes))
		assert_bool(back.same_as(dto)).override_failure_message("%s bytes differ after round-trip" % sample[0]) \
			.is_true()
		var h := StateHash.of(dto.to_dict())
		assert_int(h.length()).override_failure_message("%s not hashable" % sample[0]).is_equal(64)
		assert_str(StateHash.of(back.to_dict())).is_equal(h)


func test_every_dto_roundtrips_through_json_canonically() -> void:
	for sample: Array in _samples():
		var dto: SimDto = sample[1]
		var from_dict: Callable = sample[2]
		var json_dict: Dictionary = JSON.parse_string(JSON.stringify(dto.to_dict()))
		var back: SimDto = from_dict.call(json_dict)
		assert_bool(back.same_as(dto)) \
			.override_failure_message("%s JSON round-trip:\n%s\n!=\n%s" % [sample[0], back.to_dict(), dto.to_dict()]) \
			.is_true()


func test_hash_changes_when_a_field_changes() -> void:
	var p := _parcel()
	var before := StateHash.of(p.to_dict())
	p.land_value += 1
	assert_str(StateHash.of(p.to_dict())).is_not_equal(before)
	var r := _reason()
	var r_before := StateHash.of(r.to_dict())
	r.factors[0].weight += 1
	assert_str(StateHash.of(r.to_dict())).is_not_equal(r_before)


func test_dto_dicts_are_hashable_by_state_hash_without_vectors() -> void:
	# StateHash tekil Vector2'yi reddeder; to_dict onu [x, z] dizisine çevirmeli.
	var d := _parcel().to_dict()
	assert_bool(d["center"] is Array).is_true()
	assert_str(StateHash.of(_snapshot().to_dict())).is_not_empty()


func test_snapshot_rejects_incompatible_major_and_accepts_newer_minor() -> void:
	var d := _snapshot().to_dict()
	d["contract_version"] = "2.0"
	assert_object(SimSnapshot.from_dict(d)).is_null()
	d["contract_version"] = "garbage"
	assert_object(SimSnapshot.from_dict(d)).is_null()
	d["contract_version"] = "1.7"
	d["x_future_field"] = {"anything": 1}
	var s := SimSnapshot.from_dict(d)
	assert_object(s).is_not_null()
	assert_int(s.tick()).is_equal(42)


func test_missing_fields_fall_back_to_defaults() -> void:
	var p := ParcelView.from_dict({"id": 3})
	assert_int(p.id).is_equal(3)
	assert_str(String(p.development)).is_equal("vacant")
	assert_object(p.owner).is_null()
	assert_str(String(p.provenance)).is_equal("sim")
	var r := ReasonRecord.from_dict({})
	assert_str(String(r.outcome)).is_equal("negative")
	assert_array(r.factors).is_empty()


func test_reason_record_consistency_invariant() -> void:
	var r := _reason()
	assert_int(r.score).is_equal(280 - 30)
	assert_bool(r.is_consistent()).is_true()
	r.outcome = ReasonRecord.OUTCOME_NEGATIVE
	assert_bool(r.is_consistent()).is_false()
	r.finalize()
	r.score += 1
	assert_str(r.consistency_error()).contains("linear sum")
	r.finalize()
	r.scoring = &"sigmoid"
	assert_bool(r.is_consistent()).is_false()


func test_contribution_is_truncated_integer_arithmetic() -> void:
	assert_int(SimContract.contribution(333, 333)).is_equal(110)
	assert_int(SimContract.contribution(-333, 333)).is_equal(-110)
	assert_int(SimContract.contribution(SimContract.FIXED_SCALE, 250)).is_equal(250)


func test_refs_roundtrip() -> void:
	assert_str(String(SimContract.parcel_ref(12))).is_equal("parcel.12")
	assert_str(String(_actor(&"investor", 3).ref())).is_equal("actor.investor.3")
	assert_dict(SimContract.parse_ref(&"actor.investor.3")).is_equal({"kind": "actor.investor", "id": 3})
	assert_dict(SimContract.parse_ref(&"broken")).is_equal({"kind": "", "id": 0})
