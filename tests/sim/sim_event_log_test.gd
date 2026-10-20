extends SimTestBase
## T-027 ölçüt 2 (olaylar) · Sim olay günlüğü: durumun parçasıdır (kayıt/hash'e girer), seq 1'den boşluksuz artar,
## kapasite aşılınca en eskiler budanır, komut sınırı `command.applied/rejected` olaylarını üretir (ADR-0005 §4-5).


func _state() -> GameState:
	return new_state()


func test_empty_log_reports_no_events_and_does_not_create_state() -> void:
	var state := _state()
	var before := state_hash_of(state)
	assert_int(SimEventLog.last_seq(state)).is_equal(0)
	assert_int(SimEventLog.first_seq(state)).is_equal(1)
	assert_array(SimEventLog.since(state, 0)).is_empty()
	assert_str(state_hash_of(state)).override_failure_message("okuma durumu değiştirmemeli").is_equal(before)


func test_emit_assigns_gapless_sequence_from_one_and_stores_fields() -> void:
	var state := _state()
	state.tick = 7
	var a := SimEventLog.emit(state, &"parcel.changed", &"event.zoning.applied", PackedStringArray(["parcel.3"]),
		{"zone": &"zone.mixed"}, PackedInt64Array([2]), 5, &"actor.investor.1")
	var b := SimEventLog.emit(state, &"budget.changed", &"event.budget.approved", PackedStringArray())
	assert_int(a).is_equal(1)
	assert_int(b).is_equal(2)
	assert_int(SimEventLog.last_seq(state)).is_equal(2)
	var events := SimEventLog.since(state, 0)
	assert_int(events.size()).is_equal(2)
	var e: Dictionary = events[0]
	assert_int(e["seq"]).is_equal(1)
	assert_int(e["tick"]).is_equal(7)
	assert_str(str(e["kind"])).is_equal("parcel.changed")
	assert_str(str(e["message_key"])).is_equal("event.zoning.applied")
	assert_array(Array(e["subjects"])).is_equal(["parcel.3"])
	assert_array(Array(e["reason_ids"])).is_equal([2])
	assert_int(e["command_id"]).is_equal(5)
	assert_str(str(e["actor"])).is_equal("actor.investor.1")
	assert_str(str(e["args"]["zone"])).is_equal("zone.mixed")


func test_since_returns_only_newer_events_and_honours_max_count() -> void:
	var state := _state()
	for i in 6:
		SimEventLog.emit(state, &"k", &"m", PackedStringArray(), {"i": i})
	assert_int(SimEventLog.since(state, 4).size()).is_equal(2)
	assert_int(SimEventLog.since(state, 6).size()).is_equal(0)
	var limited := SimEventLog.since(state, 1, 2)
	assert_int(limited.size()).is_equal(2)
	assert_int(limited[0]["seq"]).override_failure_message("en eskiler önce").is_equal(2)
	assert_int(SimEventLog.since(state, -5).size()).is_equal(6)


func test_since_returns_copies() -> void:
	var state := _state()
	SimEventLog.emit(state, &"k", &"m", PackedStringArray(["parcel.1"]), {"a": 1})
	var got: Dictionary = SimEventLog.since(state, 0)[0]
	got["message_key"] = &"tampered"
	(got["args"] as Dictionary)["a"] = 99
	var again: Dictionary = SimEventLog.since(state, 0)[0]
	assert_str(str(again["message_key"])).is_equal("m")
	assert_int(again["args"]["a"]).is_equal(1)


func test_capacity_prunes_oldest_and_sequence_keeps_growing() -> void:
	var cfg := new_config()
	cfg.sim["event_log_capacity"] = 3
	var state := new_state(SEED, cfg)
	for i in 8:
		SimEventLog.emit(state, &"k", &"m", PackedStringArray(), {"i": i})
	assert_int(SimEventLog.last_seq(state)).is_equal(8)
	assert_int(SimEventLog.first_seq(state)).is_equal(6)
	var kept := SimEventLog.since(state, 0)
	assert_int(kept.size()).is_equal(3)
	assert_int(kept[0]["seq"]).is_equal(6)
	assert_int(SimEventLog.emit(state, &"k", &"m", PackedStringArray())).is_equal(9)


func test_event_log_is_part_of_state_hash_and_save_round_trip() -> void:
	var state := _state()
	var h0 := state_hash_of(state)
	SimEventLog.emit(state, &"k", &"m", PackedStringArray(["parcel.1"]), {"n": 1}, PackedInt64Array([1]))
	assert_str(state_hash_of(state)).is_not_equal(h0)
	var result := SimSave.decode(SimSave.encode(state))
	assert_bool(result.ok).override_failure_message(result.message).is_true()
	assert_str(state_hash_of(result.state)).is_equal(state_hash_of(state))
	assert_int(SimEventLog.last_seq(result.state)).is_equal(1)


func test_corrupt_event_section_is_rejected_by_state_validation() -> void:
	var state := _state()
	for i in 3:
		SimEventLog.emit(state, &"k", &"m", PackedStringArray())
	var good := state.to_dict()
	assert_str(GameState.validate_dict(good)).is_empty()
	var gap := good.duplicate(true)
	(gap["systems"]["events"]["records"] as Array).remove_at(1)
	assert_str(GameState.validate_dict(gap)).override_failure_message("seq boşluğu kabul edildi").is_not_empty()
	var bad_next := good.duplicate(true)
	bad_next["systems"]["events"]["next_seq"] = 1
	assert_str(GameState.validate_dict(bad_next)).is_not_empty()
	var not_dict := good.duplicate(true)
	not_dict["systems"]["events"]["records"][0] = 5
	assert_str(GameState.validate_dict(not_dict)).is_not_empty()


# --- Komut sınırı olayları ---

func test_applied_command_emits_command_applied_with_its_id_and_subjects() -> void:
	var state := _state()
	var sim := new_sim_full()
	var seq := Commands.submit(state, &"set_value", {"key": "tax", "value": 5})
	sim.step(state)
	var events := SimEventLog.since(state, 0)
	assert_int(events.size()).is_equal(1)
	var e: Dictionary = events[0]
	assert_str(str(e["kind"])).is_equal("command.applied")
	assert_str(str(e["message_key"])).is_equal("event.command.applied")
	assert_int(e["command_id"]).override_failure_message("sözleşme kimliği = seq + 1").is_equal(seq + 1)
	assert_array(Array(e["subjects"])).contains(["command.%d" % (seq + 1)])
	assert_str(str(e["args"]["kind"])).is_equal("set_value")
	assert_int(e["tick"]).override_failure_message("uygulama tick sınırında (artıştan önce)").is_equal(0)


func test_rejected_command_emits_command_rejected_with_contract_reject_key() -> void:
	var state := _state()
	var sim := new_sim_full()
	Commands.submit(state, &"no_such_command")
	Commands.submit(state, &"set_value", {"key": "tax", "value": -1})
	sim.step(state)
	var events := SimEventLog.since(state, 0)
	assert_int(events.size()).is_equal(2)
	assert_str(str(events[0]["kind"])).is_equal("command.rejected")
	assert_str(str(events[0]["message_key"])).is_equal("command.reject.unknown_kind")
	assert_str(str(events[1]["kind"])).is_equal("command.rejected")
	assert_str(str(events[1]["message_key"])).override_failure_message("kodu bilinmeyen ret = ön koşul") \
		.is_equal("command.reject.precondition")
	assert_str(str(events[1]["args"]["code"])).is_equal("value_negative")
	assert_int(events[0]["command_id"]).is_equal(1)
	assert_int(events[1]["command_id"]).is_equal(2)


func test_reject_key_mapping() -> void:
	assert_str(str(CommandReject.key_for(&"unknown_command"))).is_equal("command.reject.unknown_kind")
	for suffix in ["unknown_kind", "not_a_mayor_verb", "missing_param", "unknown_param", "bad_param_type",
			"invalid_value", "invalid_target", "precondition"]:
		assert_str(str(CommandReject.key_for(StringName(suffix)))).is_equal("command.reject." + suffix)
	assert_str(str(CommandReject.key_for(&"insufficient_funds"))).is_equal("command.reject.precondition")
