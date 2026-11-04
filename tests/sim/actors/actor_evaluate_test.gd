extends ActorTestBase
## T-016 ölçüt 1, 4, 5, 6 · `ActorDecision.evaluate`: karar + `ReasonLog` kaydı (SIM-12), basamaklı kararlar,
## histerez/emsal geçmişi, ilişkinin kararı değiştirmesi (SIM-10/SIM-11) ve gerekçesiz kararın uygulanmaması.


## council.vote girdileri: ilişki kaynaklı üçü (güven/kırgınlık/borç) ActorInputs'tan, kalanı verilen.
func _vote_factors(state: GameState, cfg: ActorConfig, actor_key: String, stance: int, pressure: int) -> Dictionary:
	var factors := ActorInputs.relation_factors(state, cfg, actor_key, PLAYER)
	factors["stance_distance"] = stance
	factors["bloc_pressure"] = {"value": pressure, "source_ref": BLOC_1}
	factors["lobby_pressure"] = 0
	factors["budget_realism"] = 0
	return factors


func _quiet_config() -> ActorConfig:
	return mutated(func(f: Dictionary) -> void:
		for id: String in f["decision_tables"]["decisions"]:
			f["decision_tables"]["decisions"][id]["noise_amp"] = 0)


func _react_factors(grievance: int, satisfaction: int = 0) -> Dictionary:
	return {"grievance_level": grievance, "satisfaction_level": satisfaction, "media_amplification": 500,
		"organizer_capacity": 500, "trust_in_player": 0}


func test_council_member_weights_follow_its_traits_exactly() -> void:
	# council.1: partisanship 400 (stance_distance mod 100), public_spirit 500, self_interest 500 -> el ile türetildi
	var cfg := config()
	var state := new_actor_state()
	var traits: Dictionary = ActorStore.actor(state, COUNCIL_1)["traits"]
	var weights := ActorDecision.normalized_weights(cfg.table("council.vote"), traits)
	assert_array(weights).is_equal([296, 151, 101, 201, 101, 100, 50])


func test_evaluate_writes_a_consistent_reason_with_actor_ref_subjects_and_factors() -> void:
	var cfg := config()
	var state := new_actor_state()
	state.tick = 12
	var factors := _vote_factors(state, cfg, COUNCIL_1, 400, 600)
	factors["lobby_pressure"] = -100
	factors["budget_realism"] = 200
	var result := ActorDecision.evaluate(state, cfg, COUNCIL_1, "council.vote", factors,
		PackedStringArray(["vote.7", "actor.bloc.1"]))
	assert_bool(result["ok"]).override_failure_message(str(result["error"])).is_true()
	assert_int(result["records"].size()).is_equal(1)
	var rec := state.reasons.by_id(result["records"][0]["reason_id"])
	assert_str(str(rec["actor"])).is_equal(COUNCIL_1)
	assert_str(str(rec["decision"])).is_equal("decision.council.vote")
	assert_int(rec["tick"]).is_equal(12)
	assert_array(rec["subjects"]).is_equal(PackedStringArray(["vote.7", "actor.bloc.1"]))
	assert_str(str(rec["factors"][0]["name"])).is_equal("reason.factor.stance_distance")
	assert_str(str(rec["factors"][-1]["name"])).is_equal("reason.factor.noise")
	assert_str(str(rec["factors"][1]["source_ref"])) \
		.override_failure_message("ilişki faktörü kaynağı: protagonist").is_equal(PLAYER)
	# gürültüsüz skor: 400*296/1000=118, 100*151/1000=15, 0, 600*201/1000=120, -100*101/1000=-10, 200*100/1000=20, 0
	var noise: int = rec["factors"][-1]["value"]
	assert_int(rec["score"]).is_equal(263 + noise)
	var draw := ActorDecision.noise_draw(state, COUNCIL_1, "council.vote")
	assert_int(noise) \
		.override_failure_message("gürültü = 80*volatility(300)*çekiliş/1e6").is_equal(80 * 300 * draw / 1_000_000)
	assert_str(str(rec["code"])).is_equal("score_at_or_above_threshold")
	assert_str(str(rec["outcome"])).is_equal("positive")
	assert_str(str(result["outcome"])).is_equal("positive")


func test_a_decision_without_a_writable_reason_is_not_applied() -> void:
	var cfg := config()
	var state := new_actor_state()
	var factors := _vote_factors(state, cfg, COUNCIL_1, 100, 100)
	state.reasons.record(0, COUNCIL_2, &"decision.x", [{"name": &"a", "value": 1, "weight": 1000}], 0)
	var before := state_hash_of(state)
	var size_before := state.reasons.size()
	var bad := {
		"bilinmeyen karar": [COUNCIL_1, "council.nonexistent", factors, PackedStringArray(), PackedInt64Array(), "tablosu"],
		"tür uyuşmuyor": [BLOC_1, "council.vote", factors, PackedStringArray(), PackedInt64Array(), "veremez"],
		"protagonist": [PLAYER, "council.vote", factors, PackedStringArray(), PackedInt64Array(), "veremez"],
		"bilinmeyen aktör": ["actor.council.99", "council.vote", factors, PackedStringArray(), PackedInt64Array(),
			"bilinmeyen"],
		"eksik faktör": [COUNCIL_1, "council.vote", {"stance_distance": 1}, PackedStringArray(), PackedInt64Array(), "eksik"],
		"geçersiz subject": [COUNCIL_1, "council.vote", factors, PackedStringArray(["vote"]), PackedInt64Array(), "subjects"],
		"geleceğe parent": [COUNCIL_1, "council.vote", factors, PackedStringArray(), PackedInt64Array([5]), "parent_ids"],
		"parent 0": [COUNCIL_1, "council.vote", factors, PackedStringArray(), PackedInt64Array([0]), "parent_ids"],
	}
	for label: String in bad:
		var c: Array = bad[label]
		var result := ActorDecision.evaluate(state, cfg, c[0], c[1], c[2], c[3], c[4])
		assert_bool(result["ok"]).override_failure_message("uygulandı: %s" % label).is_false()
		assert_bool(str(result["error"]).contains(c[5])) \
			.override_failure_message("%s: %s" % [label, result["error"]]).is_true()
		assert_array(result["records"]).is_empty()
	assert_int(state.reasons.size()).override_failure_message("kayıt yazıldı").is_equal(size_before)
	assert_str(state_hash_of(state)).override_failure_message("durum değişti (geçmiş/akış)").is_equal(before)


func test_hysteresis_comes_from_the_recorded_previous_outcome() -> void:
	var cfg := _quiet_config()
	var with_history := new_actor_state(SEED, cfg)
	var fresh := new_actor_state(SEED, cfg)
	var strong := _vote_factors(with_history, cfg, COUNCIL_1, 900, 900)
	var borderline := _vote_factors(with_history, cfg, COUNCIL_1, -50, 0)  # trust 100*151/1000=15; -50*296/1000=-14 -> +1?
	borderline["trust_in_player"] = 0
	borderline["stance_distance"] = -50
	with_history.tick = 5
	var first := ActorDecision.evaluate(with_history, cfg, COUNCIL_1, "council.vote", strong)
	assert_int(first["records"][0]["threshold"]).is_equal(0)
	with_history.tick = 6
	fresh.tick = 6
	var sticky := ActorDecision.evaluate(with_history, cfg, COUNCIL_1, "council.vote", borderline)
	var cold := ActorDecision.evaluate(fresh, cfg, COUNCIL_1, "council.vote", borderline)
	assert_int(sticky["records"][0]["threshold"]).override_failure_message("histerez eşiği 30 düşürür").is_equal(-30)
	assert_int(cold["records"][0]["threshold"]).is_equal(0)
	assert_int(sticky["records"][0]["score"]).is_equal(cold["records"][0]["score"])
	assert_str(str(sticky["outcome"])).is_equal("positive")
	assert_str(str(cold["outcome"])).is_equal("negative")


func test_precedent_is_the_sign_average_of_recent_outcomes_with_a_window() -> void:
	var cfg := _quiet_config()
	var state := new_actor_state(SEED, cfg)
	assert_int(ActorInputs.precedent(state, COUNCIL_1, "council.vote")).is_equal(0)
	var plan := [900, 900, -900]
	for i in plan.size():
		state.tick = i + 1
		ActorDecision.evaluate(state, cfg, COUNCIL_1, "council.vote", _vote_factors(state, cfg, COUNCIL_1, plan[i], plan[i]))
	assert_int(ActorInputs.precedent(state, COUNCIL_1, "council.vote")).is_equal(333)
	for i in 7:
		state.tick = 10 + i
		ActorDecision.evaluate(state, cfg, COUNCIL_1, "council.vote", _vote_factors(state, cfg, COUNCIL_1, 900, 900))
	assert_int(ActorInputs.precedent(state, COUNCIL_1, "council.vote")) \
		.override_failure_message("pencere n_prec=5").is_equal(1000)
	assert_int(ActorStore.recent_outcomes(state, COUNCIL_1, "council.vote").size()).is_equal(cfg.n_prec)


func test_tiered_reaction_writes_one_linked_record_per_evaluated_tier() -> void:
	var cfg := config()
	var state := new_actor_state()
	var cases := {
		"boykot": [_react_factors(1000, -1000), "boycott", ["petition", "protest", "boycott"],
			["positive", "positive", "positive"]],
		"protesto": [_react_factors(900), "protest", ["petition", "protest", "boycott"],
			["positive", "positive", "negative"]],
		"dilekçe": [_react_factors(600), "petition", ["petition", "protest"], ["positive", "negative"]],
		"sessiz": [_react_factors(100), "", ["petition"], ["negative"]],
	}
	var tick := 1
	for label: String in cases:
		state.tick = tick
		tick += 1
		var spec: Array = cases[label]
		var base_parent := state.reasons.record(state.tick, COUNCIL_1, &"decision.council.vote",
			[{"name": &"x", "value": 1, "weight": 1000}], 0)
		var result := ActorDecision.evaluate(state, cfg, BLOC_1, "bloc.react", spec[0], PackedStringArray(["parcel.3"]),
			PackedInt64Array([base_parent]))
		assert_bool(result["ok"]).override_failure_message("%s: %s" % [label, result["error"]]).is_true()
		assert_str(result["reached_tier"]).override_failure_message(label).is_equal(spec[1])
		var tiers: Array = []
		var outcomes: Array = []
		var previous := 0
		for rec: Dictionary in result["records"]:
			tiers.append(rec["tier"])
			outcomes.append(str(rec["outcome"]))
			var stored := state.reasons.by_id(rec["reason_id"])
			assert_str(str(stored["decision"])).is_equal("decision.bloc.react." + rec["tier"])
			assert_int(stored["threshold"]).is_equal(rec["threshold"])
			var expected_parents: Array = [base_parent] if previous == 0 else [base_parent, previous]
			assert_array(Array(stored["parent_ids"])).override_failure_message("%s: zincir" % label).is_equal(expected_parents)
			previous = rec["reason_id"]
		assert_array(tiers).override_failure_message(label).is_equal(spec[2])
		assert_array(outcomes).override_failure_message(label).is_equal(spec[3])
		assert_str(str(result["outcome"])).is_equal(spec[3][0])


func test_relationship_history_changes_the_same_proposal_outcome() -> void:
	var cfg := config()
	var trusting := new_actor_state()
	var wronged := new_actor_state()
	for i in 6:
		wronged.tick = i * 5
		apply(wronged, cfg, COUNCIL_2, event_of("housing_cost", -1000, 1000))
	var harmed := ActorStore.relation(wronged, cfg, COUNCIL_2, PLAYER)
	assert_int(harmed["trust"]).is_less(-300)
	assert_int(harmed["resentment"]).is_greater(300)
	trusting.tick = 40
	wronged.tick = 40
	var same_proposal_a := _vote_factors(trusting, cfg, COUNCIL_2, 200, 150)
	var same_proposal_b := _vote_factors(wronged, cfg, COUNCIL_2, 200, 150)
	assert_int(same_proposal_b["trust_in_player"]["value"]).is_less(same_proposal_a["trust_in_player"]["value"])
	var calm := ActorDecision.evaluate(trusting, cfg, COUNCIL_2, "council.vote", same_proposal_a)
	var bitter := ActorDecision.evaluate(wronged, cfg, COUNCIL_2, "council.vote", same_proposal_b)
	assert_str(str(calm["outcome"])).override_failure_message("ilişki temizken öneri geçer").is_equal("positive")
	assert_str(str(bitter["outcome"])) \
		.override_failure_message("aynı öneri, bozuk ilişkiyle reddedilir").is_equal("negative")
	# neden okunabilir: kırgınlık ve güven faktörleri olumsuz katkı verir
	var rec := wronged.reasons.by_id(bitter["records"][0]["reason_id"])
	var negative_names: Array = []
	for f: Dictionary in rec["factors"]:
		if SimContract.contribution(f["value"], f["weight"]) < 0:
			negative_names.append(str(f["name"]))
	assert_array(negative_names).contains(["reason.factor.trust_in_player", "reason.factor.resentment"])


func test_topic_memory_input_reflects_what_the_actor_lived_through() -> void:
	var cfg := config()
	var state := new_actor_state()
	var before := ActorInputs.relation_factors(state, cfg, COUNCIL_1, PLAYER, "housing_cost")
	apply(state, cfg, COUNCIL_1, event_of("housing_cost", -700, 900))
	var after := ActorInputs.relation_factors(state, cfg, COUNCIL_1, PLAYER, "housing_cost")
	assert_int(before["topic_memory"]["value"]).is_equal(0)
	assert_int(after["topic_memory"]["value"]).is_equal(-630)
	assert_int(after["trust_in_player"]["value"]).is_less(before["trust_in_player"]["value"])
	assert_int(after["resentment"]["value"]).is_less(before["resentment"]["value"])


func test_extreme_relations_still_yield_a_valid_reason_in_range() -> void:
	var cfg := config()
	var state := new_actor_state()
	var rel := ActorStore.ensure_relation(state, cfg, COUNCIL_3, PLAYER)
	rel["trust"] = -1000
	rel["trust0"] = -1000
	rel["resentment"] = 1000
	rel["scar_floor"] = 1000
	rel["peak_resentment"] = 1000
	var factors := _vote_factors(state, cfg, COUNCIL_3, -1000, -1000)
	var result := ActorDecision.evaluate(state, cfg, COUNCIL_3, "council.vote", factors)
	assert_bool(result["ok"]).override_failure_message(str(result["error"])).is_true()
	var record := ReasonAdapter.to_record(state.reasons.by_id(result["records"][0]["reason_id"]), 1)
	assert_bool(record.is_consistent()).is_true()
	assert_str(str(record.outcome)).is_equal("negative")
	for f in record.factors:
		assert_int(f.value).is_between(-1000, 1000)


func test_noise_of_one_decision_does_not_depend_on_other_decisions_made_before() -> void:
	var cfg := config()
	var alone := new_actor_state()
	var busy := new_actor_state()
	alone.tick = 20
	busy.tick = 20
	ActorDecision.evaluate(busy, cfg, COUNCIL_2, "council.vote", _vote_factors(busy, cfg, COUNCIL_2, 10, 10))
	ActorDecision.evaluate(busy, cfg, BLOC_1, "bloc.react", _react_factors(300))
	ActorDecision.evaluate(busy, cfg, MEDIA_1, "media.coverage",
		{"newsworthiness": 100, "lean_alignment": 100, "fact_signal": 100, "credibility_cost": 0})
	var a := ActorDecision.evaluate(alone, cfg, COUNCIL_1, "council.vote", _vote_factors(alone, cfg, COUNCIL_1, 50, 50))
	var b := ActorDecision.evaluate(busy, cfg, COUNCIL_1, "council.vote", _vote_factors(busy, cfg, COUNCIL_1, 50, 50))
	assert_int(a["records"][0]["noise"]) \
		.override_failure_message("gürültü diğer kararlara bağlı").is_equal(b["records"][0]["noise"])
	assert_int(a["records"][0]["score"]).is_equal(b["records"][0]["score"])


func test_same_seed_gives_same_reasons_and_different_seed_different_noise() -> void:
	var cfg := config()
	var runs: Array = []
	for world_seed in [SEED, SEED, SEED + 99]:
		var state := new_actor_state(world_seed)
		var noises: Array = []
		for t in 20:
			state.tick = t + 1
			var r := ActorDecision.evaluate(state, cfg, COUNCIL_1, "council.vote", _vote_factors(state, cfg, COUNCIL_1, 30, 30))
			noises.append(r["records"][0]["noise"])
		runs.append({"noises": noises, "hash": state_hash_of(state), "reasons": state.reasons.to_dict()})
	assert_array(runs[0]["noises"]).is_equal(runs[1]["noises"])
	assert_str(runs[0]["hash"]).is_equal(runs[1]["hash"])
	assert_dict(runs[0]["reasons"]).is_equal(runs[1]["reasons"])
	assert_array(runs[0]["noises"]).override_failure_message("tohum gürültüyü etkilemiyor").is_not_equal(runs[2]["noises"])
	assert_str(runs[0]["hash"]).is_not_equal(runs[2]["hash"])


func test_decision_scores_are_not_dominated_by_a_single_factor() -> void:
	# H2 (characters-npc §13): hiçbir tablo ağırlığı tek başına toplam |ağırlığın| %60'ını almaz.
	var cfg := config()
	for id in cfg.table_ids():
		var weights := ActorDecision.normalized_weights(cfg.table(id), {})
		for w in weights:
			assert_int(absi(w)).override_failure_message("%s: baskın faktör" % id).is_less_equal(600)
