extends PoliticsTestBase
## T-017 ölçüt 2 · Küçük meclis oylaması (`council.vote`, SIM-05/SIM-12, Q-007/Q-014): her üye gerekçeli oy verir;
## sonuç salt çoğunluk/eşitlik/çekimser VERİSİNE göre; `requires_council` iki yolda da çalışır (doğrudan yürürlük ya da
## oylama); kabul yalnız koşulu (pending_zone) değiştirir (CAN-03); tahmin sonuçtan ayrıdır ve durumu değiştirmez.

const AXIS := "growth_vs_preservation"
const MEMBERS: Array[String] = [COUNCIL_1, COUNCIL_2, COUNCIL_3, COUNCIL_4, COUNCIL_5]
## Önerinin eksen konumu -1000: duruşu -1000 olan üye "evet" (uyum +1000), +1000 olan "hayır" (uyum -1000).
const RIGGED_AXES := {"zoning": {"zone.mixed": {"growth_vs_preservation": -1000}}}


func _rig(f: Dictionary) -> void:
	f["council"]["proposal_axes"] = RIGGED_AXES
	f["council"]["proposal_effects"] = {"zoning": {"zone.mixed": {}}}


func _stance(h: PoliticsHandle, votes_yes: Array[String]) -> void:
	for member in MEMBERS:
		if ActorStore.has_actor(h.state(), member):
			ActorStore.actor_ref(h.state(), member)["stance"][AXIS] = -1000 if votes_yes.has(member) else 1000


func _propose(h: PoliticsHandle, parcels: PackedInt64Array = PackedInt64Array()) -> CommandResult:
	var ids := parcels if not parcels.is_empty() else h.facade.parcel_ids()
	return h.facade.submit_command(SimCommand.zoning_propose(ids, &"zone.mixed"))


func _open_budget_vote(h: PoliticsHandle, yes_members: Array[String]) -> int:
	_stance(h, yes_members)
	var spec := CouncilEngine.budget_spec(1, {"lines": 1}, {"axes": {AXIS: -1000}, "stakes": {}, "realism": 0})
	return CouncilEngine.open_vote(h.state(), h.context, spec)


## Oylamaya bağlı üye oyu gerekçeleri (medya haber gerekçesi de oylamaya bağlanır; o ayrıdır).
func _member_records(h: PoliticsHandle, vote_id: int) -> Array[ReasonRecord]:
	var out: Array[ReasonRecord] = []
	for record in h.facade.reasons_for(SimContract.ref(SimContract.REF_VOTE, vote_id)):
		if record.decision_key == &"decision.council.vote":
			out.append(record)
	return out


func _resolved(h: PoliticsHandle, vote_id: int) -> Dictionary:
	h.facade.advance(20)
	return CouncilEngine.vote_by_id(h.state(), vote_id)


func test_simple_majority_passes_minority_fails_and_unanimity_is_unanimous() -> void:
	var cases: Array = [
		[[COUNCIL_1, COUNCIL_2, COUNCIL_3], "passed", 3, 2],
		[[COUNCIL_1, COUNCIL_2], "failed", 2, 3],
		[MEMBERS, "passed", 5, 0],
		[[], "failed", 0, 5],
	]
	for entry: Array in cases:
		var h := handle()
		var typed: Array[String] = []
		typed.assign(entry[0])
		var vote := _resolved(h, _open_budget_vote(h, typed))
		assert_str(String(vote["status"])).override_failure_message(str(entry)).is_equal(entry[1])
		assert_int(vote["yes"]).override_failure_message(str(entry)).is_equal(entry[2])
		assert_int(vote["no"]).override_failure_message(str(entry)).is_equal(entry[3])
		assert_int(vote["abstain"]).is_equal(0)


func test_tie_follows_the_data_rule_on_an_even_council() -> void:
	var four := func(f: Dictionary) -> void:
		var roster: Array = f["roster_m2"]["actors"]
		roster.remove_at(roster.find_custom(func(a: Dictionary) -> bool: return a["key"] == COUNCIL_5))
	for rule in ["fail", "pass"]:
		var h := handle({}, 6, SEED, func(f: Dictionary) -> void: f["council"]["tie_result"] = rule, four)
		assert_int(h.context.politics.council["members"].size()).is_equal(4)
		_stance(h, [COUNCIL_1, COUNCIL_2])
		var vote_id := CouncilEngine.open_vote(h.state(), h.context,
			CouncilEngine.budget_spec(1, {}, {"axes": {AXIS: -1000}, "realism": 0}))
		var vote := _resolved(h, vote_id)
		assert_int(vote["yes"]).is_equal(2)
		assert_int(vote["no"]).is_equal(2)
		assert_str(String(vote["status"])).override_failure_message("eşitlik kuralı: %s" % rule) \
			.is_equal("passed" if rule == "pass" else "failed")


func test_members_inside_the_abstain_band_abstain_and_do_not_count() -> void:
	var h := handle({}, 6, SEED, func(f: Dictionary) -> void: f["council"]["abstain_band"] = 1000)
	var vote := _resolved(h, _open_budget_vote(h, [COUNCIL_1, COUNCIL_2, COUNCIL_3]))
	assert_int(vote["abstain"]).is_equal(5)
	assert_int(vote["yes"] + vote["no"]).is_equal(0)
	assert_str(String(vote["status"])).override_failure_message("0-0 eşitlik").is_equal("failed")
	var narrow := handle({}, 6, SEED, func(f: Dictionary) -> void: f["council"]["abstain_band"] = 250)
	var mixed := _resolved(narrow, _open_budget_vote(narrow, [COUNCIL_1, COUNCIL_2, COUNCIL_3]))
	assert_int(mixed["yes"] + mixed["no"] + mixed["abstain"]).is_equal(5)
	assert_int(mixed["abstain"]).override_failure_message("sınırdaki oylar çekimser kalmalı").is_less(5)


func test_every_member_vote_is_reasoned_with_the_full_factor_set_and_links() -> void:
	var h := handle()
	var vote_id := _open_budget_vote(h, [COUNCIL_1, COUNCIL_2, COUNCIL_3])
	h.facade.advance(20)
	var records := _member_records(h, vote_id)
	assert_int(records.size()).is_equal(5)
	var members := {}
	for record in records:
		members[String(record.actor.ref())] = true
		assert_str(String(record.decision_key)).is_equal("decision.council.vote")
		assert_bool(record.is_consistent()).is_true()
		assert_bool(ReasonModel.from_record(record).is_consistent()).is_true()
		var names := record.factors.map(
			func(f: ReasonFactor) -> String: return String(f.name_key).trim_prefix("reason.factor."))
		assert_array(names).contains(["stance_distance", "trust_in_player", "resentment", "bloc_pressure", "lobby_pressure",
			"budget_realism", "obligation", "noise"])
		assert_array(Array(record.subjects)).contains(["vote.%d" % vote_id, "budget.1"])
	assert_int(members.size()).is_equal(5)
	var view: CouncilVoteView = h.facade.snapshot().council.vote(vote_id)
	for position in view.positions:
		assert_bool(position.reason_id > 0).is_true()
		assert_bool(h.facade.reason(position.reason_id).actor.ref() == position.bloc.ref()).is_true()
	assert_array(SimContractChecks.check_facade(h.facade)).is_empty()


func test_member_positions_follow_each_members_own_inputs() -> void:
	var h := handle()
	_stance(h, [COUNCIL_1])
	var rel := ActorStore.ensure_relation(h.state(), h.context.actors, COUNCIL_2, PLAYER)
	rel["trust"] = -1000
	rel["resentment"] = 1000
	var vote_id := CouncilEngine.open_vote(h.state(), h.context,
		CouncilEngine.budget_spec(1, {}, {"axes": {AXIS: -1000}, "realism": 0}))
	var vote := CouncilEngine.vote_by_id(h.state(), vote_id)
	var angry := CouncilEngine.member_factors(h.state(), h.context, COUNCIL_2, vote, PLAYER)
	var calm := CouncilEngine.member_factors(h.state(), h.context, COUNCIL_1, vote, PLAYER)
	assert_int(angry["trust_in_player"]["value"]).is_equal(-1000)
	assert_int(angry["resentment"]["value"]).is_equal(-1000)
	assert_int(calm["stance_distance"]).is_equal(1000)
	assert_int(angry["stance_distance"]).is_equal(-1000)


func test_forecast_is_separate_from_the_result_and_never_mutates_state() -> void:
	var h := handle()
	var vote_id := _open_budget_vote(h, [COUNCIL_1, COUNCIL_2, COUNCIL_3])
	var before := h.state().state_hash()
	var reasons_before := h.state().reasons.size()
	var forecast: Dictionary = PoliticsQuery.forecasts(h.state(), h.context)[vote_id]
	assert_str(h.state().state_hash()).override_failure_message("tahmin durumu değiştirdi").is_equal(before)
	assert_int(h.state().reasons.size()).is_equal(reasons_before)
	assert_int(forecast["yes"]).is_equal(3)
	assert_int(forecast["no"]).is_equal(2)
	assert_bool(forecast["passes"]).is_true()
	var pending: CouncilVoteView = h.facade.snapshot().council.vote(vote_id)
	assert_str(String(pending.status)).is_equal("pending")
	assert_int(pending.yes + pending.no).override_failure_message("sonuç oylamadan önce görünmemeli").is_equal(0)
	var extensions := h.facade.snapshot().extensions
	assert_int(extensions["x.sim.council.forecast.yes.%d" % vote_id]).is_equal(3)
	h.facade.advance(20)
	var closed: CouncilVoteView = h.facade.snapshot().council.vote(vote_id)
	assert_int(closed.yes).is_equal(forecast["yes"])
	assert_bool(h.facade.snapshot().extensions.has("x.sim.council.forecast.yes.%d" % vote_id)) \
		.override_failure_message("kapanan oylamanın tahmini kalmamalı").is_false()


func test_votes_close_at_the_next_session_after_the_minimum_lead() -> void:
	var h := handle()
	h.facade.advance(20)
	var vote_id := _open_budget_vote(h, MEMBERS)
	var vote := CouncilEngine.vote_by_id(h.state(), vote_id)
	assert_int(vote["opened_tick"]).is_equal(20)
	assert_int(vote["closes_tick"]).is_equal(28)  # 20 + 3 -> 14 günlük oturum sınırına yuvarlanır
	var short := handle({}, 6, SEED, func(f: Dictionary) -> void:
		f["council"]["session_days"] = 1
		f["council"]["min_lead_days"] = 0)
	var instant := CouncilEngine.open_vote(short.state(), short.context, CouncilEngine.budget_spec(1, {}, {}))
	assert_int(CouncilEngine.vote_by_id(short.state(), instant)["closes_tick"]).is_equal(0)


func test_closed_vote_history_is_bounded_but_pending_votes_are_kept() -> void:
	var h := handle({}, 6, SEED, func(f: Dictionary) -> void: f["council"]["history_limit"] = 3)
	for i in 6:
		var spec := CouncilEngine.budget_spec(i + 1, {}, {"axes": {AXIS: -1000}, "realism": 0})
		CouncilEngine.open_vote(h.state(), h.context, spec)
		h.facade.advance(14)
	var pending := CouncilEngine.open_vote(h.state(), h.context, CouncilEngine.budget_spec(9, {}, {}))
	var votes: Array = pol(h)["council"]["votes"]
	var closed := votes.filter(func(v: Dictionary) -> bool: return v["status"] != "pending")
	assert_int(closed.size()).is_equal(3)
	assert_int(closed[0]["id"]).override_failure_message("en eski kapanmışlar budanır").is_equal(4)
	assert_bool(CouncilEngine.vote_by_id(h.state(), pending).is_empty()).is_false()


# --- requires_council: iki yol (Q-014) ---

func test_without_council_requirement_the_proposal_takes_effect_directly() -> void:
	var h := handle({}, 6, SEED, func(f: Dictionary) -> void:
		_rig(f)
		f["council"]["requires_council"]["zoning.propose"] = false)
	_stance(h, [])
	var result := _propose(h)
	assert_bool(result.is_rejected()).is_false()
	h.facade.advance(1)
	var parcel := int(h.facade.parcel_ids()[0])
	assert_str(String(h.facade.parcel_views(PackedInt64Array([parcel]))[0].pending_zone)).is_equal("zone.mixed")
	assert_array(events_of(h, &"council.vote_opened")).is_empty()
	assert_int(pol(h)["council"]["votes"].size()).is_equal(0)
	h.facade.advance(5)
	assert_str(String(h.facade.parcel_views(PackedInt64Array([parcel]))[0].zone)).is_equal("zone.mixed")


func test_with_council_requirement_a_passing_vote_applies_the_zoning_after_session_and_friction() -> void:
	var h := handle({}, 6, SEED, _rig)
	_stance(h, MEMBERS)
	var result := _propose(h)
	assert_bool(result.is_rejected()).is_false()
	h.facade.advance(1)
	var parcel := int(h.facade.parcel_ids()[0])
	assert_str(String(h.facade.parcel_views(PackedInt64Array([parcel]))[0].pending_zone)) \
		.override_failure_message("oylamadan önce") \
		.is_equal("")
	assert_int(events_of(h, &"council.vote_opened").size()).is_equal(1)
	var opened := h.facade.snapshot().council.pending_votes()[0]
	assert_str(String(opened.subject_ref)).is_equal("command.1")
	assert_int(opened.closes_tick).is_equal(14)
	h.facade.advance(13)  # tick 14: oylama çözüldü
	var vote := h.facade.snapshot().council.vote(opened.vote_id)
	assert_str(String(vote.status)).is_equal("passed")
	var pending_view := h.facade.parcel_views(PackedInt64Array([parcel]))[0]
	assert_str(String(pending_view.pending_zone)).is_equal("zone.mixed")
	assert_str(String(pending_view.zone)) \
		.override_failure_message("kabul anında yürürlük yok").is_equal("zone.residential")
	h.facade.advance(5)  # tick 19: facade gecikmesi 3 + meclis sürtünmesi 3 -> yürürlük 20. gün
	assert_str(String(h.facade.parcel_views(PackedInt64Array([parcel]))[0].zone)) \
		.override_failure_message("14 + 3 + 3 = 20") \
		.is_equal("zone.residential")
	h.facade.advance(2)
	assert_str(String(h.facade.parcel_views(PackedInt64Array([parcel]))[0].zone)).is_equal("zone.mixed")
	var resolved := events_of(h, &"council.vote_resolved")
	assert_str(String(resolved[0].message_key)).is_equal("event.council.vote_passed")
	assert_int(resolved[0].reason_ids.size()).is_equal(5)
	var story := h.state().reasons.latest({"decision": "decision.media.coverage"})
	assert_array(Array(story["subjects"])) \
		.override_failure_message("sonuç haberi oylamaya bağlanmalı").contains(["vote.1"])


func test_with_council_requirement_a_failing_vote_leaves_the_zoning_untouched() -> void:
	var h := handle({}, 6, SEED, _rig)
	_stance(h, [])
	_propose(h)
	h.facade.advance(40)
	var vote := h.facade.snapshot().council.votes[0]
	assert_str(String(vote.status)).is_equal("failed")
	assert_int(vote.no).is_equal(5)
	for view in h.facade.parcel_views(h.facade.parcel_ids()):
		assert_str(String(view.pending_zone)).is_equal("")
		assert_str(String(view.zone)).is_equal("zone.residential")
	assert_array(events_of(h, &"parcel.changed").filter(
		func(e: SimEvent) -> bool: return e.message_key == &"event.zoning.applied")).is_empty()
	assert_str(String(events_of(h, &"council.vote_resolved")[0].message_key)).is_equal("event.council.vote_failed")
	# başarısız oylamanın da gerekçesi var (SIM-12)
	assert_int(_member_records(h, 1).size()).is_equal(5)


func test_both_paths_exist_in_the_same_build_chosen_only_by_data() -> void:
	var direct := handle({}, 6, SEED, func(f: Dictionary) -> void:
		f["council"]["requires_council"]["zoning.propose"] = false)
	var gated := handle()
	assert_bool(direct.context.politics.requires_council("zoning.propose")).is_false()
	assert_bool(gated.context.politics.requires_council("zoning.propose")).is_true()
	_propose(direct)
	_propose(gated)
	direct.facade.advance(2)
	gated.facade.advance(2)
	assert_int(events_of(direct, &"council.vote_opened").size()).is_equal(0)
	assert_int(events_of(gated, &"council.vote_opened").size()).is_equal(1)


func test_second_proposal_on_a_parcel_with_a_pending_vote_is_rejected_with_the_vote_reference() -> void:
	var h := handle({}, 6, SEED, _rig)
	_stance(h, MEMBERS)
	var ids := h.facade.parcel_ids()
	_propose(h, PackedInt64Array([ids[0]]))
	h.facade.advance(1)
	var again := h.facade.submit_command(SimCommand.zoning_propose(PackedInt64Array([ids[0]]), &"zone.commercial"))
	assert_bool(again.is_rejected()).is_true()
	assert_str(String(again.reason_key)).is_equal("command.reject.precondition")
	assert_str(String(again.args["why"])).is_equal("vote.pending")
	assert_str(String(again.args["ref"])).is_equal("vote.1")
	var other := h.facade.validate_command(SimCommand.zoning_propose(PackedInt64Array([ids[1]]), &"zone.commercial"))
	assert_bool(other.is_rejected()).override_failure_message("başka parsel serbest").is_false()


func test_council_only_writes_the_pending_zone_condition_never_a_building() -> void:
	var h := handle({"decision": {"review_enabled": 0}}, 6, SEED, _rig)
	_stance(h, MEMBERS)
	var stages_before := (EconomyState.data(h.state()).get("stage", PackedByteArray()) as PackedByteArray).duplicate()
	_propose(h)
	h.facade.advance(14)
	var data := EconomyState.data(h.state())
	assert_bool(data.is_empty()).is_false()
	for stage in data["stage"] as PackedByteArray:
		assert_int(stage).override_failure_message("meclis kararı bina yarattı").is_equal(EconomyState.STAGE_VACANT)
	assert_int(EconomyQuery.totals(h.state())["approvals"]).is_equal(0)
	assert_bool(stages_before.is_empty() or stages_before == data["stage"]).is_true()
	for kind in [&"building.place", &"private.spawn", &"spawn.house"]:
		var rejected := h.facade.submit_command(SimCommand.make(kind, {}))
		assert_bool(rejected.is_rejected()).is_true()
		assert_str(String(rejected.reason_key)).is_equal("command.reject.not_a_mayor_verb")


func test_snapshot_council_section_is_real_and_available() -> void:
	var h := handle()
	var snapshot := h.facade.snapshot()
	assert_bool(snapshot.extensions["x.sim.available.council"]).is_true()
	assert_int(snapshot.council.seats_total).is_equal(5)
	assert_int(snapshot.council.blocs.size()).is_equal(5)
	assert_str(String(snapshot.council.council.ref())).is_equal(String(h.context.politics.council["body"]))
	var members := snapshot.council.blocs.map(func(b: CouncilBlocView) -> String: return String(b.bloc.ref()))
	assert_array(members).is_equal(MEMBERS)
	for bloc in snapshot.council.blocs:
		assert_int(bloc.seats).is_equal(1)
		assert_str(String(bloc.position)).is_equal("undecided")
	var trust := snapshot.council.blocs.map(func(b: CouncilBlocView) -> int: return b.stance)
	assert_array(trust).override_failure_message("üye tutumu ilişki güveninden gelir").contains([100, -80])


# --- Kesim baskısı (bloc_pressure) ---

func _pressure(h: PoliticsHandle, member: String, stakes: Dictionary) -> Dictionary:
	var actor := ActorStore.actor_ref(h.state(), member)
	return CouncilEngine.bloc_pressure(h.state(), h.context, actor, stakes)


func test_constituency_pressure_follows_the_stake_of_the_blocs_a_member_represents() -> void:
	var h := handle(E.regions(STRESS))
	tick(h, 8)  # kesim öncelikleri türetildi
	var harm := {"housed": {"mobility": -1000}, "seeking": {"housing_cost": 1000}}
	var housed_member := _pressure(h, COUNCIL_1, harm)  # actor.bloc.1 (barınan) temsil eder
	var seeking_member := _pressure(h, COUNCIL_3, harm)  # actor.bloc.2 (arayan) temsil eder
	assert_int(housed_member["value"]).override_failure_message("zarar gören kesim üyeyi karşıya iter").is_less(-100)
	assert_int(seeking_member["value"]).override_failure_message("yararlanan kesim üyeyi destekçi yapar").is_greater(100)
	assert_str(String(housed_member["source_ref"])).is_equal(BLOC_HOUSED)
	assert_str(String(seeking_member["source_ref"])).is_equal(BLOC_SEEKING)
	assert_int(_pressure(h, COUNCIL_1, {})["value"]).override_failure_message("etkisiz öneri baskı yaratmaz").is_equal(0)
	# yoğunluk: kesimin şikâyeti/memnuniyeti ne kadar yüksekse baskı o kadar güçlü
	pol(h)["blocs"][BLOC_HOUSED]["G"] = 0
	pol(h)["blocs"][BLOC_HOUSED]["S"] = 0
	var calm: int = _pressure(h, COUNCIL_1, harm)["value"]
	pol(h)["blocs"][BLOC_HOUSED]["G"] = 1000
	var inflamed: int = _pressure(h, COUNCIL_1, harm)["value"]
	assert_int(inflamed).override_failure_message("öfkeli kesim daha güçlü baskı yapar").is_less(calm)
	# kesim temsil etmeyen üye: baskı yok
	ActorStore.actor_ref(h.state(), COUNCIL_2)["state"]["constituency_blocs"] = []
	assert_int(_pressure(h, COUNCIL_2, harm)["value"]).is_equal(0)


func test_pressure_reaches_the_recorded_vote_factor_and_moves_the_outcome() -> void:
	var h := handle(E.regions(STRESS), 6, SEED, func(f: Dictionary) -> void:
		f["council"]["proposal_axes"] = {"zoning": {"zone.mixed": {}}}
		f["council"]["proposal_effects"] = {"zoning": {"zone.mixed": {"housed": {"mobility": -1000},
			"seeking": {"housing_cost": 1000}}}})
	tick(h, 8)
	_propose(h)
	h.facade.advance(20)
	var by_member := {}
	for record in _member_records(h, 1):
		for factor in record.factors:
			if factor.name_key == &"reason.factor.bloc_pressure":
				by_member[String(record.actor.ref())] = factor
	assert_int(by_member[COUNCIL_1].value).is_less(0)
	assert_int(by_member[COUNCIL_3].value).is_greater(0)
	assert_str(String(by_member[COUNCIL_1].source_ref)).is_equal(BLOC_HOUSED)
	assert_str(String(by_member[COUNCIL_3].source_ref)).is_equal(BLOC_SEEKING)
