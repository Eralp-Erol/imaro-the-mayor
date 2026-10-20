extends PoliticsTestBase
## T-017 ölçüt 1 · Kesim türetme (characters-npc §6.6): kesimler roster'daki sabit yer tutucu sayılar DEĞİL, hane
## kohortlarından (EconomyQuery.region_stats) türer; öncelik/eksen konumu veri kurallarından gelir; kimlik
## (actor.bloc.<n>) yeniden türetmede korunur; bölge payı (exposure) kohort büyüklüğünden çıkar, bölge kodu
## gömülü değildir.


func _rows(h: PoliticsHandle) -> Array[Dictionary]:
	return EconomyQuery.region_stats(h.state(), h.context.economy)


func test_bloc_sizes_and_exposure_come_from_household_cohorts() -> void:
	var h := stress_handle()
	tick(h, 100)
	var rows := _rows(h)
	var housed := 0
	var seeking := 0
	for row in rows:
		housed += int(row["housed_hh"])
		seeking += int(row["latent_hh"]) - int(row["housed_hh"])
	assert_int(housed).override_failure_message("ölü senaryo: hane barınmadı").is_greater(0)
	assert_int(pol(h)["blocs"][BLOC_HOUSED]["size"]).is_equal(housed)
	assert_int(pol(h)["blocs"][BLOC_SEEKING]["size"]).is_equal(seeking)
	assert_int(int(bloc_book(h, BLOC_HOUSED, "grievances").size())).is_greater(0)
	for key in [BLOC_HOUSED, BLOC_SEEKING]:
		var exposure: Dictionary = pol(h)["blocs"][key]["exposure"]
		var total := 0
		for code: String in exposure:
			total += int(exposure[code])
			assert_array([&"F1", &"F2"]).contains([StringName(code)])
		assert_int(total).override_failure_message("%s payları 1000 değil" % key).is_equal(1000)
		assert_int(ActorStore.actor_ref(h.state(), key)["state"]["size"]).is_equal(pol(h)["blocs"][key]["size"])


func test_different_household_data_derives_different_blocs() -> void:
	var small := handle(E.regions({"F1": {"initial_households": 20}, "F2": {"initial_households": 20}}))
	var large := handle(E.regions({"F1": {"initial_households": 900}, "F2": {"initial_households": 900}}))
	tick(small, 14)
	tick(large, 14)
	assert_int(pol(large)["blocs"][BLOC_SEEKING]["size"]).is_greater(pol(small)["blocs"][BLOC_SEEKING]["size"])
	assert_int(pol(large)["blocs"][BLOC_SEEKING]["size"]).is_equal(1800)


func test_priority_rule_responds_to_demand_pressure_and_is_clamped() -> void:
	var cfg := politics_config()
	var cohort := cfg.cohort("seeking")
	var relaxed := {"actor": {"salience": {}, "stance": {}, "state": {}}}
	var pressed := {"actor": {"salience": {}, "stance": {}, "state": {}}}
	BlocEngine.derive(relaxed["actor"], cohort, {"demand_shortage": 0})
	BlocEngine.derive(pressed["actor"], cohort, {"demand_shortage": 1000})
	assert_int(relaxed["actor"]["salience"]["housing_cost"]).is_equal(400)
	assert_int(pressed["actor"]["salience"]["housing_cost"]).is_equal(1000)
	assert_int(relaxed["actor"]["stance"]["growth_vs_preservation"]).is_equal(300)
	assert_int(pressed["actor"]["stance"]["growth_vs_preservation"]).is_equal(-300)
	var absurd := {"salience": {}, "stance": {}, "state": {}}
	BlocEngine.derive(absurd, cohort, {"demand_shortage": 100000})
	assert_int(absurd["salience"]["housing_cost"]).is_equal(1000)
	assert_int(absurd["stance"]["growth_vs_preservation"]).is_equal(-1000)


func test_priorities_and_stances_follow_the_data_rules() -> void:
	var h := handle(E.regions(STRESS))
	tick(h, 14)
	var signals: Dictionary = pol(h)["blocs"][BLOC_SEEKING]["signals"]
	var actor := ActorStore.actor_ref(h.state(), BLOC_SEEKING)
	var cohort := h.context.politics.cohort("seeking")
	for rule: Dictionary in cohort["priorities"]:
		var expected: int = rule["base"]
		if not str(rule["source"]).is_empty():
			expected += int(rule["k"]) * (int(signals[rule["source"]]) - 500) / 500
		assert_int(actor["salience"][rule["id"]]).override_failure_message(rule["id"]).is_equal(clampi(expected, 0, 1000))
	var stance_rule: Dictionary = cohort["stances"][0]
	var source_value: int = signals[stance_rule["source"]]
	var expected_stance: int = int(stance_rule["base"]) + int(stance_rule["k"]) * (source_value - 500) / 500
	assert_int(actor["stance"][stance_rule["id"]]).is_equal(expected_stance)
	assert_int(expected_stance).override_failure_message("kural etkisiz: stance 0").is_not_equal(0)
	# veri değişince türetme değişir (kodda sabit değil)
	var shifted := handle(E.regions(STRESS), 6, SEED, func(f: Dictionary) -> void:
		f["blocs"]["cohorts"]["seeking"]["priorities"][0]["base"] = 300)
	tick(shifted, 14)
	assert_int(ActorStore.actor_ref(shifted.state(), BLOC_SEEKING)["salience"]["housing_cost"]) \
		.is_less(actor["salience"]["housing_cost"])


func test_bloc_identity_is_kept_across_rederivation() -> void:
	var h := stress_handle()
	tick(h, 14)
	var first_tick: int = pol(h)["blocs"][BLOC_HOUSED]["derived_tick"]
	var keys_before := PoliticsState.bloc_keys(h.state())
	var memory_marker := {"topic_id": "mobility", "valence": -500, "magnitude": 500, "attributed_to": PLAYER,
		"source_ref": "command.1"}
	ActorMemory.apply_event(h.state(), h.context.actors, BLOC_HOUSED, memory_marker)
	var memories_before: int = ActorStore.actor_ref(h.state(), BLOC_HOUSED)["memory"].size()
	tick(h, int(h.context.politics.cadence["rederive_days"]) + 8)
	assert_array(PoliticsState.bloc_keys(h.state())).is_equal(keys_before)
	assert_int(pol(h)["blocs"][BLOC_HOUSED]["derived_tick"]).is_greater(first_tick)
	assert_int(ActorStore.actor_ref(h.state(), BLOC_HOUSED)["memory"].size()) \
		.override_failure_message("hafıza yeniden türetmede silindi").is_greater_equal(memories_before)


func test_peak_and_mean_blending_differ_for_multi_region_blocs() -> void:
	var peak := stress_handle(14)
	var mean := stress_handle(14, SEED, func(f: Dictionary) -> void: f["blocs"]["blend"]["mode"] = "mean")
	tick(peak, 100)
	tick(mean, 100)
	var peak_stress: int = pol(peak)["blocs"][BLOC_HOUSED]["signals"]["infra_stress"]
	var mean_stress: int = pol(mean)["blocs"][BLOC_HOUSED]["signals"]["infra_stress"]
	assert_int(peak_stress).override_failure_message("peak yerel baskıyı göstermeli").is_greater(mean_stress)
	assert_int(peak_stress).is_greater(700)


func test_zero_households_creates_empty_blocs_without_crashing() -> void:
	var h := handle(E.regions({"F1": {"initial_households": 0}, "F2": {"initial_households": 0}}),
		6, SEED, func(f: Dictionary) -> void: f["council"]["requires_council"]["zoning.propose"] = false)
	tick(h, 60)
	for key in [BLOC_HOUSED, BLOC_SEEKING]:
		assert_int(pol(h)["blocs"][key]["size"]).is_equal(0)
		assert_str(pol(h)["blocs"][key]["eval"]["reaction"]).is_equal("neutral")
	assert_array(reasons_of(h, "decision.bloc.react.petition")).is_empty()
