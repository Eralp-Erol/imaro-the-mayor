extends ActorTestBase
## T-016 ölçüt 1 ve 5 · Tek puanlama çatısı `ActorDecision.decide(factors, table, context)` (characters-npc §6.1-§6.2):
## aynı girdi aynı gerekçe, eşik sınırları, olumsuz varyantlar, özellik kaydırması, histerez, gürültü, kayıt değişmezi.

const SCALE := 1000


## Gürültüsüz, histerezsiz iki faktörlü tablo; `theta` verilir.
func _table(theta: int, weights: Array = [500, 500], hysteresis: int = 0, noise_amp: int = 0) -> Dictionary:
	var factors: Array = []
	for i in weights.size():
		factors.append({"name": "f%d" % i, "weight": weights[i], "trait_mod": {}})
	return {"kind": "council", "verb": "vote", "factors": factors, "theta": theta, "hysteresis": hysteresis,
		"noise_amp": noise_amp, "tiers": []}


func _assert_record_invariant(result: Dictionary) -> void:
	var sum := 0
	for f: Dictionary in result["factors"]:
		sum += SimContract.contribution(f["value"], f["weight"])
	assert_int(result["score"]).override_failure_message("score != Σ katkı").is_equal(sum)
	var expected := &"positive" if result["score"] >= result["threshold"] else &"negative"
	assert_str(str(result["outcome"])).override_failure_message("outcome eşikle uyuşmuyor").is_equal(str(expected))
	assert_int(result["margin"]).is_equal(result["score"] - result["threshold"])


func test_same_input_gives_identical_result_and_record_invariant_holds() -> void:
	var table := config().table("council.vote")
	var factors := {"stance_distance": 400, "trust_in_player": -200, "resentment": -300, "bloc_pressure": 650,
		"lobby_pressure": 100, "budget_realism": 0, "obligation": 50}
	var ctx := {"traits": {"partisanship": 400, "public_spirit": 600}, "draw": 321}
	var a := ActorDecision.decide(factors, table, ctx)
	var b := ActorDecision.decide(factors.duplicate(), table, ctx.duplicate(true))
	assert_bool(a["ok"]).override_failure_message(str(a.get("error"))).is_true()
	assert_dict(a).is_equal(b)
	_assert_record_invariant(a)
	assert_str(str(a["factors"][0]["name"])).is_equal("reason.factor.stance_distance")


func test_base_weights_are_normalized_to_exactly_one_thousand_absolute() -> void:
	var table := config().table("bloc.react")  # negatif ağırlıklar dâhil
	for traits: Dictionary in [{}, {"volatility": 1000, "combativeness": 0}, {"volatility": 0}]:
		var weights := ActorDecision.normalized_weights(table, traits)
		var total := 0
		for w in weights:
			total += absi(w)
		assert_int(total).override_failure_message("Σ|w| != 1000: %s" % str(weights)).is_equal(SCALE)
	var signed := ActorDecision.normalized_weights(table, {})
	assert_int(signed[0]).is_greater(0)
	assert_int(signed[1]).override_failure_message("karşı faktör negatif kalır").is_less(0)


func test_threshold_boundary_is_inclusive_at_exact_score() -> void:
	# 400*500/1000 + 200*500/1000 = 300
	var factors := {"f0": 400, "f1": 200}
	var at_threshold := ActorDecision.decide(factors, _table(300))
	var just_above := ActorDecision.decide(factors, _table(301))
	var just_below := ActorDecision.decide(factors, _table(299))
	assert_int(at_threshold["score"]).is_equal(300)
	assert_str(str(at_threshold["outcome"])).override_failure_message("eşitlik olumlu").is_equal("positive")
	assert_str(str(just_above["outcome"])).is_equal("negative")
	assert_str(str(just_below["outcome"])).is_equal("positive")
	assert_int(just_above["margin"]).is_equal(-1)


func test_negative_variant_flips_outcome_when_one_factor_turns_against() -> void:
	var table := _table(100)
	var supportive := ActorDecision.decide({"f0": 600, "f1": 300}, table)
	var turned := ActorDecision.decide({"f0": 600, "f1": -900}, table)
	assert_str(str(supportive["outcome"])).is_equal("positive")
	assert_str(str(turned["outcome"])).is_equal("negative")
	_assert_record_invariant(turned)


func test_extreme_inputs_stay_in_range_and_valid() -> void:
	var table := config().table("council.vote")
	for sign_value in [-1000, 1000]:
		var factors := {}
		for f: Dictionary in table["factors"]:
			factors[f["name"]] = sign_value
		var r := ActorDecision.decide(factors, table, {"traits": {"volatility": 1000}, "draw": sign_value})
		assert_bool(r["ok"]).is_true()
		assert_int(r["score"]).is_between(-SCALE - 100, SCALE + 100)
		_assert_record_invariant(r)


func test_trait_modifier_shifts_weight_share_and_clamps_at_zero() -> void:
	var table := _table(0)
	table["factors"][0]["trait_mod"] = {"partisanship": 1000}
	var neutral := ActorDecision.normalized_weights(table, {"partisanship": 500})
	var high := ActorDecision.normalized_weights(table, {"partisanship": 1000})
	var absent := ActorDecision.normalized_weights(table, {})
	assert_array(neutral).is_equal([500, 500])
	assert_array(absent).override_failure_message("özellik yoksa nötr (500)").is_equal(neutral)
	assert_int(high[0]).is_greater(neutral[0])
	assert_int(high[0] + high[1]).is_equal(SCALE)
	table["factors"][0]["trait_mod"] = {"partisanship": 2000}
	var low := ActorDecision.normalized_weights(table, {"partisanship": 0})
	assert_array(low).override_failure_message("ağırlık işaret değiştirmez, sıfıra kırpılır").is_equal([0, 1000])


func test_hysteresis_lowers_threshold_after_a_previous_positive() -> void:
	var table := _table(100, [500, 500], 30)
	var factors := {"f0": 100, "f1": 100}  # skor 100 -> eşiğe eşit; 90 ile
	var factors_between := {"f0": 80, "f1": 80}  # skor 80: 70 <= 80 < 100
	var fresh := ActorDecision.decide(factors_between, table, {"previous_positive": false})
	var sticky := ActorDecision.decide(factors_between, table, {"previous_positive": true})
	assert_int(fresh["threshold"]).is_equal(100)
	assert_int(sticky["threshold"]).override_failure_message("eşik histerez kadar düşer").is_equal(70)
	assert_str(str(fresh["outcome"])).is_equal("negative")
	assert_str(str(sticky["outcome"])).override_failure_message("ping-pong önlenir").is_equal("positive")
	assert_bool(sticky["hysteresis_applied"]).is_true()
	assert_bool(ActorDecision.decide(factors, table)["hysteresis_applied"]).is_false()


func test_noise_is_a_recorded_factor_scaled_by_volatility_and_draw() -> void:
	var table := _table(0, [500, 500], 0, 80)
	var base := {"f0": 100, "f1": 100}
	var up := ActorDecision.decide(base, table, {"traits": {"volatility": 300}, "draw": 1000})
	var down := ActorDecision.decide(base, table, {"traits": {"volatility": 300}, "draw": -1000})
	var calm := ActorDecision.decide(base, table, {"traits": {"volatility": 0}, "draw": 1000})
	assert_int(up["noise"]).override_failure_message("80*300*1000/1e6").is_equal(24)
	assert_int(down["noise"]).is_equal(-24)
	assert_int(calm["noise"]).is_equal(0)
	var noise_factor: Dictionary = up["factors"][up["factors"].size() - 1]
	assert_str(str(noise_factor["name"])).is_equal("reason.factor.noise")
	assert_int(noise_factor["weight"]).is_equal(SCALE)
	assert_int(noise_factor["value"]).is_equal(24)
	assert_int(up["score"]).is_equal(down["score"] + 48)
	_assert_record_invariant(up)
	_assert_record_invariant(down)
	var silent := ActorDecision.decide(base, _table(0), {"draw": 1000})
	assert_int(silent["factors"].size()).override_failure_message("gürültüsüz tabloda gürültü faktörü yok").is_equal(2)


func test_noise_can_flip_a_borderline_decision_in_both_directions() -> void:
	var table := _table(100, [500, 500], 0, 400)
	var borderline := {"f0": 100, "f1": 100}
	var ctx_hi := {"traits": {"volatility": 1000}, "draw": 500}
	var ctx_lo := {"traits": {"volatility": 1000}, "draw": -500}
	assert_str(str(ActorDecision.decide(borderline, table, ctx_hi)["outcome"])).is_equal("positive")
	assert_str(str(ActorDecision.decide(borderline, table, ctx_lo)["outcome"])).is_equal("negative")


func test_info_only_factor_is_recorded_but_does_not_move_the_score() -> void:
	var table := _table(0, [600, 400, 0])
	var with_info := ActorDecision.decide({"f0": 100, "f1": 100, "f2": 900}, table)
	var without := ActorDecision.decide({"f0": 100, "f1": 100, "f2": -900}, table)
	assert_int(with_info["score"]).is_equal(without["score"])
	assert_int(with_info["factors"][2]["weight"]).is_equal(0)
	assert_int(with_info["factors"][2]["value"]).is_equal(900)


func test_inputs_can_carry_source_ref_and_estimate_flag() -> void:
	var table := _table(0)
	var r := ActorDecision.decide({"f0": {"value": 100, "source_ref": "actor.bloc.1", "is_estimate": true}, "f1": 50},
		table)
	assert_bool(r["ok"]).is_true()
	assert_str(str(r["factors"][0]["source_ref"])).is_equal("actor.bloc.1")
	assert_bool(r["factors"][0]["is_estimate"]).is_true()
	assert_bool(r["factors"][1]["is_estimate"]).is_false()


func test_bad_inputs_are_rejected_with_a_clear_error_and_no_partial_result() -> void:
	var table := _table(0)
	var cases := {
		"eksik faktör": [{"f0": 10}, "f1"],
		"fazladan faktör": [{"f0": 10, "f1": 10, "f9": 5}, "f9"],
		"aralık dışı": [{"f0": 1001, "f1": 0}, "f0"],
		"tamsayı değil": [{"f0": 0.5, "f1": 0}, "f0"],
		"metin": [{"f0": "x", "f1": 0}, "f0"],
	}
	for label: String in cases:
		var r := ActorDecision.decide(cases[label][0], table)
		assert_bool(r["ok"]).override_failure_message("kabul edildi: %s" % label).is_false()
		assert_bool(str(r["error"]).contains(cases[label][1])) \
			.override_failure_message("%s: %s" % [label, str(r["error"])]).is_true()
		assert_bool(r.has("score")).override_failure_message("başarısız sonuçta skor yok: %s" % label).is_false()
	assert_bool(ActorDecision.decide({"f0": 1, "f1": 1}, table, {"draw": 1001})["ok"]).is_false()


func test_single_factor_or_zero_weight_tables_cannot_produce_a_reason() -> void:
	var single := _table(0, [1000])
	assert_bool(ActorDecision.decide({"f0": 900}, single)["ok"]) \
		.override_failure_message("tek faktörlü sahte karar").is_false()
	var zero := _table(0, [0, 0])
	assert_bool(ActorDecision.decide({"f0": 900, "f1": 900}, zero)["ok"]).is_false()
	var all_clamped := _table(0, [500, 500])
	all_clamped["factors"][0]["trait_mod"] = {"partisanship": 2000}
	all_clamped["factors"][1]["trait_mod"] = {"partisanship": 2000}
	assert_bool(ActorDecision.decide({"f0": 1, "f1": 1}, all_clamped, {"traits": {"partisanship": 0}})["ok"]).is_false()


func test_tiered_table_requires_an_explicit_tier_threshold() -> void:
	var table := config().table("bloc.react")
	var factors := {}
	for f: Dictionary in table["factors"]:
		factors[f["name"]] = 500
	assert_bool(ActorDecision.decide(factors, table)["ok"]) \
		.override_failure_message("basamak eşiği bağlamda olmalı").is_false()
	var ok := ActorDecision.decide(factors, table, {"theta": 250})
	assert_bool(ok["ok"]).is_true()
	assert_int(ok["threshold"]).is_equal(250)


func test_noise_draw_is_keyed_stable_and_independent_of_call_order() -> void:
	var state := new_state()
	state.tick = 40
	var first := ActorDecision.noise_draw(state, COUNCIL_1, "council.vote")
	var other_actor := ActorDecision.noise_draw(state, COUNCIL_2, "council.vote")
	var other_decision := ActorDecision.noise_draw(state, COUNCIL_1, "media.coverage")
	var again := ActorDecision.noise_draw(state, COUNCIL_1, "council.vote")
	assert_int(again).override_failure_message("aynı anahtar aynı çekiliş").is_equal(first)
	assert_bool(first == other_actor and first == other_decision) \
		.override_failure_message("anahtar kullanılmıyor").is_false()
	state.tick = 41
	assert_int(ActorDecision.noise_draw(state, COUNCIL_1, "council.vote")).is_not_equal(first)
	var other_seed_draw := ActorDecision.noise_draw(new_state(SEED + 1), COUNCIL_1, "council.vote")
	assert_int(other_seed_draw).override_failure_message("tohum kullanılmıyor") \
		.is_not_equal(ActorDecision.noise_draw(new_state(), COUNCIL_1, "council.vote"))


func test_noise_draw_covers_the_range_in_both_signs_and_never_leaves_it() -> void:
	var state := new_state()
	var negatives := 0
	var positives := 0
	for tick in 400:
		state.tick = tick
		var draw := ActorDecision.noise_draw(state, COUNCIL_1, "council.vote")
		assert_int(draw).is_between(-SCALE, SCALE)
		negatives += 1 if draw < 0 else 0
		positives += 1 if draw > 0 else 0
	assert_int(negatives).is_greater(120)
	assert_int(positives).is_greater(120)
