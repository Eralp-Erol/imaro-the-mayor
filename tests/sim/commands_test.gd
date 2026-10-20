extends SimTestBase
## T-002 ölçüt 4 · Komut kuyruğu: komutlar tick sınırında doğrulanıp uygulanır, günlüğe yazılır, geçersiz komut
## gerekçeli reddedilir (olumsuz test). TEK-02/CAN-03 zemini: oyuncu niyeti yalnız komuttur.

var _sim: Simulation


func before_test() -> void:
	_sim = Simulation.new()
	_sim.add_handler(SetValueHandler.new())
	_sim.add_handler(WithdrawHandler.new())


func _cmd_value(state: GameState, key: String) -> Variant:
	return state.system_data(&"cmd").get(key, null)


func test_submitted_command_is_not_applied_until_tick_boundary() -> void:
	var state := new_state()
	var seq := Commands.submit(state, &"set_value", {"key": "tax", "value": 7})
	assert_int(seq).is_greater_equal(0)
	assert_object(_cmd_value(state, "tax")).is_null()
	assert_int(Commands.pending_count(state)).is_equal(1)
	_sim.step(state)
	assert_int(_cmd_value(state, "tax")).is_equal(7)
	assert_int(Commands.pending_count(state)).is_equal(0)


func test_commands_apply_in_submission_order() -> void:
	var state := new_state()
	Commands.submit(state, &"set_value", {"key": "tax", "value": 1})
	Commands.submit(state, &"set_value", {"key": "tax", "value": 2})
	Commands.submit(state, &"set_value", {"key": "tax", "value": 3})
	_sim.step(state)
	assert_int(_cmd_value(state, "tax")).is_equal(3)
	var seqs: Array = []
	for e: Dictionary in Commands.log_entries(state):
		seqs.append(e["seq"])
	assert_array(seqs).is_equal([0, 1, 2])


func test_applied_command_is_logged_with_tick_issuer_and_params() -> void:
	var state := new_state()
	_sim.advance(state, 4)
	Commands.submit(state, &"set_value", {"key": "tax", "value": 9}, &"player")
	_sim.step(state)
	var entries := Commands.log_entries(state)
	assert_int(entries.size()).is_equal(1)
	var e: Dictionary = entries[0]
	assert_str(str(e["type"])).is_equal("set_value")
	assert_str(str(e["status"])).is_equal("applied")
	assert_str(str(e["issuer"])).is_equal("player")
	assert_int(e["tick_issued"]).is_equal(4)
	assert_int(e["tick_applied"]).is_equal(4)  # sınır = adım başı (tick henüz artmadan)
	assert_str(str(e["reason"])).is_equal("")
	assert_dict(e["params"]).is_equal({"key": "tax", "value": 9})


func test_invalid_command_is_rejected_with_reason_and_state_unchanged() -> void:
	var state := new_state()
	state.system_data(&"cmd")  # bölümü önceden oluştur: yalnız komutun etkisi ölçülsün
	Commands.submit(state, &"set_value", {"key": "tax", "value": -5})
	var before: Dictionary = state.to_dict()["systems"]
	_sim.step(state)
	assert_object(_cmd_value(state, "tax")).is_null()
	# Reddedilen komut sistem verisini değiştirmez; yalnız olay günlüğüne `command.rejected` düşer (T-027).
	var after: Dictionary = state.to_dict()["systems"]
	assert_array(after.keys()).contains_exactly_in_any_order(["cmd", "events"])
	after.erase("events")
	assert_dict(after).is_equal(before)
	var rejected := Commands.rejected(state)
	assert_int(rejected.size()).is_equal(1)
	assert_str(str(rejected[0]["reason"])).is_equal("value_negative")
	assert_str(str(rejected[0]["status"])).is_equal("rejected")


func test_each_validation_failure_gives_its_own_reason_code() -> void:
	var state := new_state()
	Commands.submit(state, &"set_value", {"value": 1})
	Commands.submit(state, &"set_value", {"key": "k", "value": 1.5})
	Commands.submit(state, &"set_value", {"key": "k", "value": -1})
	_sim.step(state)
	var reasons: Array = []
	for e: Dictionary in Commands.rejected(state):
		reasons.append(str(e["reason"]))
	assert_array(reasons).is_equal(["missing_key", "value_not_int", "value_negative"])


func test_unknown_command_type_is_rejected() -> void:
	var state := new_state()
	Commands.submit(state, &"build_private_tower", {})
	_sim.step(state)
	var rejected := Commands.rejected(state)
	assert_int(rejected.size()).is_equal(1)
	assert_str(str(rejected[0]["reason"])).is_equal("unknown_command")


func test_rejection_does_not_block_following_commands() -> void:
	var state := new_state()
	Commands.submit(state, &"set_value", {"key": "a", "value": -1})
	Commands.submit(state, &"set_value", {"key": "b", "value": 4})
	_sim.step(state)
	assert_object(_cmd_value(state, "a")).is_null()
	assert_int(_cmd_value(state, "b")).is_equal(4)
	assert_int(Commands.log_entries(state).size()).is_equal(2)


func test_validation_runs_at_boundary_against_current_state_not_at_submit() -> void:
	var state := new_state()
	state.system_data(&"bank")["balance"] = 100
	Commands.submit(state, &"withdraw", {"amount": 80})
	Commands.submit(state, &"withdraw", {"amount": 80})  # gönderimde her ikisi de geçerli görünürdü
	_sim.step(state)
	assert_int(int(state.system_data(&"bank")["balance"])).is_equal(20)
	var statuses: Array = []
	for e: Dictionary in Commands.log_entries(state):
		statuses.append(str(e["status"]))
	assert_array(statuses).is_equal(["applied", "rejected"])
	assert_str(str(Commands.rejected(state)[0]["reason"])).is_equal("insufficient_funds")


func test_unserializable_params_are_refused_at_submit() -> void:
	var state := new_state()
	var seq := [0]
	await assert_error(func() -> void: seq[0] = Commands.submit(state, &"set_value", {"key": RefCounted.new()})) \
		.is_push_error("Commands: params not serializable for 'set_value'")
	assert_int(seq[0]).is_equal(-1)
	assert_int(Commands.pending_count(state)).is_equal(0)


func test_submit_copies_params_so_later_caller_mutation_has_no_effect() -> void:
	var state := new_state()
	var params := {"key": "tax", "value": 5}
	Commands.submit(state, &"set_value", params)
	params["value"] = 99
	_sim.step(state)
	assert_int(_cmd_value(state, "tax")).is_equal(5)


func test_pending_queue_and_log_are_part_of_the_hash() -> void:
	var state := new_state()
	var h0 := state_hash_of(state)
	Commands.submit(state, &"set_value", {"key": "tax", "value": 5})
	var h1 := state_hash_of(state)
	assert_str(h1).is_not_equal(h0)
	_sim.step(state)
	assert_str(state_hash_of(state)).is_not_equal(h1)


func test_same_seed_same_command_script_replays_to_same_hash_and_scripts_diverge() -> void:
	var hashes: Array[String] = []
	for variant: int in [0, 0, 1]:
		var state := new_state()
		var sim := new_sim_full()
		sim.advance(state, 10)
		Commands.submit(state, &"set_value", {"key": "tax", "value": 5 + variant})
		sim.advance(state, 30)
		hashes.append(state_hash_of(state))
	assert_str(hashes[0]).is_equal(hashes[1])
	assert_str(hashes[0]).is_not_equal(hashes[2])


func test_command_log_is_capped_by_config_keeping_newest() -> void:
	var cfg := new_config()
	cfg.sim["command_log_capacity"] = 3
	var state := new_state(SEED, cfg)
	for i in 5:
		Commands.submit(state, &"set_value", {"key": "k", "value": i})
	_sim.step(state)
	var entries := Commands.log_entries(state)
	assert_int(entries.size()).is_equal(3)
	assert_int(entries[0]["seq"]).is_equal(2)
	assert_int(entries[2]["seq"]).is_equal(4)
	assert_int(_cmd_value(state, "k")).is_equal(4)
