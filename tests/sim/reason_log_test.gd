extends SimTestBase
## T-002 ölçüt 5 + T-027 ölçüt 1 · Gerekçe kaydı {aktör, karar, faktörler, eşik}: ADR-0005 ReasonRecord ile eşlenebilir
## (id 1'den, 1000 ölçekli tamsayı değer/ağırlık, outcome/score/subjects/parent_ids), sorgulanabilir, hash'e ve
## kayda dâhil.

const A1 := &"actor.investor.1"
const A2 := &"actor.investor.2"


func _factors() -> Array:
	return [{"name": &"yield", "value": 7000, "weight": 3000}, {"name": &"risk", "value": 2000}]


func test_ids_start_at_one_and_increase() -> void:
	var state := new_state()
	state.tick = 12
	var id1 := state.record_reason(A1, &"invest", _factors(), 5000, &"yield_above_threshold")
	var id2 := state.record_reason(A2, &"decline", [], 9000)
	assert_int(id1).is_equal(1)
	assert_int(id2).is_equal(2)
	assert_bool(state.reasons.by_id(0).is_empty()).override_failure_message("id 0 yok").is_true()
	var rec := state.reasons.by_id(id1)
	assert_int(rec["tick"]).is_equal(12)
	assert_str(str(rec["actor"])).is_equal("actor.investor.1")
	assert_str(str(rec["decision"])).is_equal("invest")
	assert_int(rec["threshold"]).is_equal(5000)
	assert_str(str(rec["code"])).is_equal("yield_above_threshold")
	assert_int(rec["factors"].size()).is_equal(2)
	assert_str(str(rec["factors"][0]["name"])).is_equal("yield")
	assert_int(rec["factors"][0]["value"]).is_equal(7000)
	assert_int(rec["factors"][0]["weight"]).is_equal(3000)


func test_missing_factor_weight_defaults_to_one_in_fixed_point() -> void:
	var state := new_state()
	var id := state.record_reason(A1, &"d", _factors(), 0)
	assert_int(state.reasons.by_id(id)["factors"][1]["weight"]).is_equal(SimContract.FIXED_SCALE)


func test_score_is_linear_sum_of_truncated_contributions() -> void:
	var state := new_state()
	# 7000*3000/1000 = 21000; 2000*1000/1000 = 2000; -1*999/1000 -> 0 (sıfıra doğru kesme, floor olsaydı -1)
	var factors := [
		{"name": &"yield", "value": 7000, "weight": 3000},
		{"name": &"risk", "value": 2000},
		{"name": &"dust", "value": -1, "weight": 999},
	]
	var rec := state.reasons.by_id(state.record_reason(A1, &"d", factors, 0))
	assert_int(rec["score"]).is_equal(23000)
	assert_int(rec["factors"][2]["value"]).is_equal(-1)
	var expected := 0
	for f: Dictionary in rec["factors"]:
		expected += SimContract.contribution(f["value"], f["weight"])
	assert_int(rec["score"]).is_equal(expected)


func test_outcome_is_positive_exactly_when_score_reaches_threshold() -> void:
	var state := new_state()
	var f := [{"name": &"x", "value": 500}]  # skor 500
	var below := state.reasons.by_id(state.record_reason(A1, &"d", f, 501))
	var equal := state.reasons.by_id(state.record_reason(A1, &"d", f, 500))
	var above := state.reasons.by_id(state.record_reason(A1, &"d", f, 499))
	assert_str(str(below["outcome"])).is_equal("negative")
	assert_str(str(equal["outcome"])).is_equal("positive")
	assert_str(str(above["outcome"])).is_equal("positive")
	var negative_score := state.reasons.by_id(state.record_reason(A1, &"d", [{"name": &"x", "value": -300}], -300))
	assert_str(str(negative_score["outcome"])).override_failure_message("eşit = olumlu, işaretten bağımsız") \
		.is_equal("positive")


func test_subjects_and_parent_ids_are_stored_and_queryable() -> void:
	var state := new_state()
	var parent := state.reasons.record(1, A1, &"d", [], 0, &"", PackedStringArray(["parcel.12"]))
	var child := state.reasons.record(2, A2, &"d", [], 0, &"", PackedStringArray(["parcel.12", "command.3"]),
		PackedInt64Array([parent]))
	var rec := state.reasons.by_id(child)
	assert_array(Array(rec["subjects"])).is_equal(["parcel.12", "command.3"])
	assert_array(Array(rec["parent_ids"])).is_equal([parent])
	assert_int(state.reasons.find({"subject": "parcel.12"}).size()).is_equal(2)
	assert_int(state.reasons.find({"subject": &"command.3"}).size()).is_equal(1)
	assert_int(state.reasons.find({"subject": "actor.investor.2"}).size()).override_failure_message("aktör de konudur") \
		.is_equal(1)
	assert_int(state.reasons.find({"subject": "parcel.99"}).size()).is_equal(0)


func test_query_by_actor_decision_code_and_tick_range() -> void:
	var state := new_state()
	var sim := Simulation.new()
	state.record_reason(A1, &"invest", [], 1, &"c1")
	sim.advance(state, 5)
	state.record_reason(A2, &"decline", [], 1, &"c2")
	state.record_reason(A1, &"decline", [], 1, &"c2")
	sim.advance(state, 5)
	state.record_reason(A1, &"invest", [], 1, &"c1")
	assert_int(state.reasons.find({"actor": A1}).size()).is_equal(3)
	assert_int(state.reasons.find({"decision": &"decline"}).size()).is_equal(2)
	assert_int(state.reasons.find({"code": &"c2"}).size()).is_equal(2)
	assert_int(state.reasons.find({"actor": A1, "decision": &"decline"}).size()).is_equal(1)
	assert_int(state.reasons.find({"from_tick": 5, "to_tick": 9}).size()).is_equal(2)
	assert_int(state.reasons.find({"from_tick": 100}).size()).is_equal(0)
	assert_int(state.reasons.find({}).size()).is_equal(3 + 1)
	var latest := state.reasons.latest({"actor": A1})
	assert_int(latest["tick"]).is_equal(10)
	assert_bool(state.reasons.latest({"actor": &"actor.nobody.1"}).is_empty()).is_true()


func test_string_and_stringname_actor_refs_match() -> void:
	var state := new_state()
	state.record_reason("actor.firm.7", &"invest", [], 0)
	assert_int(state.reasons.find({"actor": &"actor.firm.7"}).size()).is_equal(1)
	assert_int(state.reasons.find({"actor": "actor.firm.7"}).size()).is_equal(1)
	assert_int(state.reasons.find({"actor": 7}).size()).is_equal(0)


func test_invalid_records_are_rejected_with_error_and_not_stored() -> void:
	var state := new_state()
	var ids := [0, 0, 0, 0, 0, 0, 0, 0, 0]
	await assert_error(func() -> void: ids[0] = state.record_reason(&"", &"invest", [], 0)) \
		.is_push_error("ReasonLog: actor must be an actor ref 'actor.<kind>.<n>' (n >= 1)")
	await assert_error(func() -> void: ids[1] = state.record_reason(&"investor_1", &"invest", [], 0)) \
		.is_push_error("ReasonLog: actor must be an actor ref 'actor.<kind>.<n>' (n >= 1)")
	await assert_error(func() -> void: ids[2] = state.record_reason(&"actor.a.1", &"", [], 0)) \
		.is_push_error("ReasonLog: decision must be a non-empty String/StringName")
	await assert_error(func() -> void: ids[3] = state.record_reason(A1, &"d", [{"value": 1}], 0)) \
		.is_push_error("ReasonLog: factor[0] needs a non-empty 'name'")
	await assert_error(func() -> void: ids[4] = state.record_reason(A1, &"d", [{"name": &"x", "value": "high"}], 0)) \
		.is_push_error("ReasonLog: factor[0] 'value' must be an int (fixed-point, scale 1000)")
	await assert_error(func() -> void: ids[5] = state.record_reason(A1, &"d", [{"name": &"x", "value": 1.5}], 0)) \
		.is_push_error("ReasonLog: factor[0] 'value' must be an int (fixed-point, scale 1000)")
	var half := [{"name": &"x", "value": 1, "weight": 0.5}]
	await assert_error(func() -> void: ids[6] = state.record_reason(A1, &"d", half, 0)) \
		.is_push_error("ReasonLog: factor[0] 'weight' must be an int (fixed-point, scale 1000)")
	await assert_error(func() -> void: ids[7] = state.record_reason(A1, &"d", [], 5.5)) \
		.is_push_error("ReasonLog: threshold must be an int (fixed-point, scale 1000)")
	await assert_error(func() -> void: ids[8] = state.reasons.record(0, A1, &"d", [], 0, &"", PackedStringArray(),
			PackedInt64Array([5]))) \
		.is_push_error("ReasonLog: parent_ids must refer to earlier reasons (1 <= id < 1)")
	for id: int in ids:
		assert_int(id).is_equal(-1)
	assert_int(state.reasons.size()).is_equal(0)
	assert_int(state.record_reason(A1, &"d", [], 0)).override_failure_message("reddedilen kayıt kimlik tüketmez") \
		.is_equal(1)


func test_invalid_subjects_are_rejected() -> void:
	var state := new_state()
	var id := [0]
	await assert_error(func() -> void: id[0] = state.reasons.record(0, A1, &"d", [], 0, &"",
			PackedStringArray(["not a ref"]))) \
		.is_push_error("ReasonLog: subjects must be refs '<kind>.<n>'")
	assert_int(id[0]).is_equal(-1)


func test_query_results_are_copies() -> void:
	var state := new_state()
	var id := state.record_reason(A1, &"d", _factors(), 3000)
	var rec := state.reasons.by_id(id)
	rec["decision"] = &"tampered"
	rec["factors"][0]["value"] = 999
	var again := state.reasons.by_id(id)
	assert_str(str(again["decision"])).is_equal("d")
	assert_int(again["factors"][0]["value"]).is_equal(7000)


func test_input_factor_array_is_copied_on_record() -> void:
	var state := new_state()
	var factors := _factors()
	var id := state.record_reason(A1, &"d", factors, 3000)
	factors[0]["value"] = 12345
	assert_int(state.reasons.by_id(id)["factors"][0]["value"]).is_equal(7000)


func test_reason_log_is_part_of_state_hash() -> void:
	var state := new_state()
	var h0 := state_hash_of(state)
	state.record_reason(A1, &"d", [], 1)
	assert_str(state_hash_of(state)).is_not_equal(h0)


func test_decision_system_records_a_causally_consistent_reason_per_decision() -> void:
	var state := new_state()
	var sim := Simulation.new()
	sim.add_system(DecisionSystem.new())
	sim.advance(state, 80)
	var records := state.reasons.find({"actor": &"actor.investor.1"})
	assert_int(records.size()).is_equal(80)
	var invested := 0
	for rec: Dictionary in records:
		var roll: int = rec["factors"][0]["value"]
		var invest := str(rec["decision"]) == "invest"
		# Gerekçe, kararı açıklar: karar ancak puan eşiği aşarsa "invest"; sonuç alanı bunu kaydeder.
		assert_bool(rec["score"] >= rec["threshold"]).is_equal(invest)
		assert_str(str(rec["outcome"])).is_equal("positive" if invest else "negative")
		assert_int(rec["score"]).is_equal(roll)
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
		state.record_reason(A1, &"d", [], i)
	assert_int(state.reasons.size()).is_equal(4)
	assert_int(state.reasons.by_id(10)["threshold"]).is_equal(9)
	assert_bool(state.reasons.by_id(6).is_empty()).is_true()  # budanmış
	assert_int(state.reasons.first_id()).is_equal(7)
	assert_int(state.reasons.last_id()).is_equal(10)
	assert_int(state.record_reason(A1, &"d", [], 10)).is_equal(11)


func test_empty_log_has_no_ids() -> void:
	var state := new_state()
	assert_int(state.reasons.first_id()).is_equal(0)
	assert_int(state.reasons.last_id()).is_equal(0)


func test_validate_dict_rejects_malformed_records() -> void:
	var state := new_state()
	state.record_reason(A1, &"d", _factors(), 3000)
	var good := state.reasons.to_dict()
	assert_str(ReasonLog.validate_dict(good)).is_empty()
	for key in ["outcome", "score", "subjects", "parent_ids"]:
		var broken := good.duplicate(true)
		(broken["records"][0] as Dictionary).erase(key)
		assert_str(ReasonLog.validate_dict(broken)).override_failure_message("eksik %s kabul edildi" % key).is_not_empty()
	var bad_outcome := good.duplicate(true)
	bad_outcome["records"][0]["outcome"] = &"maybe"
	assert_str(ReasonLog.validate_dict(bad_outcome)).is_not_empty()
	var bad_next := good.duplicate(true)
	bad_next["next_id"] = 0
	assert_str(ReasonLog.validate_dict(bad_next)).is_not_empty()
	var float_value := good.duplicate(true)
	float_value["records"][0]["factors"][0]["value"] = 1.5
	assert_str(ReasonLog.validate_dict(float_value)).override_failure_message("float değer kaydı kabul edildi") \
		.is_not_empty()
