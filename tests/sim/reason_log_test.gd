extends SimTestBase
## T-002 ölçüt 5 · Gerekçe kaydı altyapısı {aktör, karar, faktörler, eşik}: sorgulanabilir, hash'e/kayda dâhil (SIM-12).


func _factors() -> Array:
	return [{"name": &"yield", "value": 7, "weight": 3}, {"name": &"risk", "value": 2}]


func test_record_returns_increasing_ids_and_stores_all_fields() -> void:
	var state := new_state()
	state.tick = 12
	var id0 := state.record_reason(&"investor_1", &"invest", _factors(), 5, &"yield_above_threshold")
	var id1 := state.record_reason(&"investor_2", &"decline", [], 9)
	assert_int(id0).is_equal(0)
	assert_int(id1).is_equal(1)
	var rec := state.reasons.by_id(id0)
	assert_int(rec["tick"]).is_equal(12)
	assert_str(str(rec["actor"])).is_equal("investor_1")
	assert_str(str(rec["decision"])).is_equal("invest")
	assert_int(rec["threshold"]).is_equal(5)
	assert_str(str(rec["code"])).is_equal("yield_above_threshold")
	assert_int(rec["factors"].size()).is_equal(2)
	assert_dict(rec["factors"][0]).is_equal({"name": &"yield", "value": 7, "weight": 3})


func test_missing_factor_weight_defaults_to_one() -> void:
	var state := new_state()
	var id := state.record_reason(&"a", &"d", _factors(), 0)
	assert_int(state.reasons.by_id(id)["factors"][1]["weight"]).is_equal(1)


func test_query_by_actor_decision_code_and_tick_range() -> void:
	var state := new_state()
	var sim := Simulation.new()
	state.record_reason(&"investor_1", &"invest", [], 1, &"c1")
	sim.advance(state, 5)
	state.record_reason(&"investor_2", &"decline", [], 1, &"c2")
	state.record_reason(&"investor_1", &"decline", [], 1, &"c2")
	sim.advance(state, 5)
	state.record_reason(&"investor_1", &"invest", [], 1, &"c1")
	assert_int(state.reasons.find({"actor": &"investor_1"}).size()).is_equal(3)
	assert_int(state.reasons.find({"decision": &"decline"}).size()).is_equal(2)
	assert_int(state.reasons.find({"code": &"c2"}).size()).is_equal(2)
	assert_int(state.reasons.find({"actor": &"investor_1", "decision": &"decline"}).size()).is_equal(1)
	assert_int(state.reasons.find({"from_tick": 5, "to_tick": 9}).size()).is_equal(2)
	assert_int(state.reasons.find({"from_tick": 100}).size()).is_equal(0)
	assert_int(state.reasons.find({}).size()).is_equal(3 + 1)
	var latest := state.reasons.latest({"actor": &"investor_1"})
	assert_int(latest["tick"]).is_equal(10)
	assert_bool(state.reasons.latest({"actor": &"nobody"}).is_empty()).is_true()


func test_string_and_stringname_actor_ids_match_and_int_ids_work() -> void:
	var state := new_state()
	state.record_reason("firm_7", &"invest", [], 0)
	state.record_reason(42, &"invest", [], 0)
	assert_int(state.reasons.find({"actor": &"firm_7"}).size()).is_equal(1)
	assert_int(state.reasons.find({"actor": 42}).size()).is_equal(1)
	assert_int(state.reasons.find({"actor": "42"}).size()).is_equal(0)


func test_invalid_records_are_rejected_with_error_and_not_stored() -> void:
	var state := new_state()
	var ids := [0, 0, 0, 0, 0]
	await assert_error(func() -> void: ids[0] = state.record_reason(&"", &"invest", [], 0)) \
		.is_push_error("ReasonLog: actor must be a non-empty String/StringName or an int")
	await assert_error(func() -> void: ids[1] = state.record_reason(&"a", &"", [], 0)) \
		.is_push_error("ReasonLog: decision must be a non-empty String/StringName")
	await assert_error(func() -> void: ids[2] = state.record_reason(&"a", &"d", [{"value": 1}], 0)) \
		.is_push_error("ReasonLog: factor[0] needs a non-empty 'name'")
	await assert_error(func() -> void: ids[3] = state.record_reason(&"a", &"d", [{"name": &"x", "value": "high"}], 0)) \
		.is_push_error("ReasonLog: factor[0] 'value' must be int or float")
	await assert_error(func() -> void: ids[4] = state.record_reason(&"a", &"d", [], "five")) \
		.is_push_error("ReasonLog: threshold must be int or float")
	for id: int in ids:
		assert_int(id).is_equal(-1)
	assert_int(state.reasons.size()).is_equal(0)


func test_query_results_are_copies() -> void:
	var state := new_state()
	var id := state.record_reason(&"a", &"d", _factors(), 3)
	var rec := state.reasons.by_id(id)
	rec["decision"] = &"tampered"
	rec["factors"][0]["value"] = 999
	var again := state.reasons.by_id(id)
	assert_str(str(again["decision"])).is_equal("d")
	assert_int(again["factors"][0]["value"]).is_equal(7)


func test_input_factor_array_is_copied_on_record() -> void:
	var state := new_state()
	var factors := _factors()
	var id := state.record_reason(&"a", &"d", factors, 3)
	factors[0]["value"] = 12345
	assert_int(state.reasons.by_id(id)["factors"][0]["value"]).is_equal(7)


func test_reason_log_is_part_of_state_hash() -> void:
	var state := new_state()
	var h0 := state_hash_of(state)
	state.record_reason(&"a", &"d", [], 1)
	assert_str(state_hash_of(state)).is_not_equal(h0)


func test_decision_system_records_a_causally_consistent_reason_per_decision() -> void:
	var state := new_state()
	var sim := Simulation.new()
	sim.add_system(DecisionSystem.new())
	sim.advance(state, 80)
	var records := state.reasons.find({"actor": &"investor_1"})
	assert_int(records.size()).is_equal(80)
	var invested := 0
	for rec: Dictionary in records:
		var roll: int = rec["factors"][0]["value"]
		var invest := str(rec["decision"]) == "invest"
		# Gerekçe, kararı açıklar: karar ancak faktör eşiği aşarsa "invest".
		assert_bool(roll >= rec["threshold"]).is_equal(invest)
		assert_str(str(rec["code"])).is_equal("roll_above_threshold" if invest else "roll_below_threshold")
		invested += 1 if invest else 0
	assert_int(invested).is_between(1, 79)  # iki sonuç da görülmeli (test karar üretiyor)


func test_reason_log_is_deterministic_for_same_seed() -> void:
	var dumps: Array[String] = []
	for world_seed: int in [SEED, SEED, SEED + 1]:
		var state := new_state(world_seed)
		var sim := Simulation.new()
		sim.add_system(DecisionSystem.new())
		sim.advance(state, 50)
		dumps.append(assert_hash(StateHash.of(state.reasons.to_dict())))
	assert_str(dumps[0]).is_equal(dumps[1])
	assert_str(dumps[0]).is_not_equal(dumps[2])


func test_log_is_capped_by_config_keeping_newest_and_ids_stay_monotonic() -> void:
	var cfg := new_config()
	cfg.sim["reason_log_capacity"] = 4
	var state := new_state(SEED, cfg)
	for i in 10:
		state.record_reason(&"a", &"d", [], i)
	assert_int(state.reasons.size()).is_equal(4)
	assert_int(state.reasons.by_id(9)["threshold"]).is_equal(9)
	assert_bool(state.reasons.by_id(5).is_empty()).is_true()  # budanmış
	assert_int(state.record_reason(&"a", &"d", [], 10)).is_equal(10)
