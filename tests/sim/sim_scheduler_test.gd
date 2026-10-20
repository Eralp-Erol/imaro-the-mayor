extends SimTestBase
## T-002 ölçüt 1 · GameState + sistem zamanlayıcısı: günlük tick, aylık/çeyreklik kancalar, sabit çalışma sırası,
## tick kodu `delta` görmez (TEK-01/TEK-02).


func _calls(state: GameState) -> Array:
	return state.system_data(&"order").get("calls", [])


func _ticks_of(calls: Array, tag: String, system: String) -> Array:
	var out: Array = []
	var prefix := "%s:%s@" % [system, tag]
	for c: String in calls:
		if c.begins_with(prefix):
			out.append(int(c.substr(prefix.length())))
	return out


func test_each_step_advances_exactly_one_tick() -> void:
	var state := new_state()
	var sim := Simulation.new()
	assert_int(state.tick).is_equal(0)
	sim.step(state)
	assert_int(state.tick).is_equal(1)
	sim.advance(state, 9)
	assert_int(state.tick).is_equal(10)
	sim.advance(state, 0)
	assert_int(state.tick).is_equal(10)


func test_daily_hook_runs_once_per_tick() -> void:
	var state := new_state()
	var sim := Simulation.new()
	sim.add_system(OrderSystem.new(&"a"))
	sim.advance(state, 25)
	assert_array(_ticks_of(_calls(state), "d", "a")).is_equal(range(1, 26))


func test_monthly_and_quarterly_hooks_fire_only_on_calendar_boundaries() -> void:
	var state := new_state()
	var dpm: int = state.config["days_per_month"]
	var mpq: int = state.config["months_per_quarter"]
	var sim := Simulation.new()
	sim.add_system(OrderSystem.new(&"a"))
	sim.advance(state, dpm * mpq * 2 + 1)
	var months: Array = []
	for i in mpq * 2:
		months.append(dpm * (i + 1))
	var quarters: Array = [dpm * mpq, dpm * mpq * 2]
	assert_array(_ticks_of(_calls(state), "m", "a")).is_equal(months)
	assert_array(_ticks_of(_calls(state), "q", "a")).is_equal(quarters)


func test_custom_calendar_from_config_changes_boundaries() -> void:
	var cfg := new_config()
	cfg.sim["days_per_month"] = 7
	cfg.sim["months_per_quarter"] = 2
	var state := new_state(SEED, cfg)
	var sim := Simulation.new()
	sim.add_system(OrderSystem.new(&"a"))
	sim.advance(state, 30)
	assert_array(_ticks_of(_calls(state), "m", "a")).is_equal([7, 14, 21, 28])
	assert_array(_ticks_of(_calls(state), "q", "a")).is_equal([14, 28])


func test_hook_order_is_phase_major_then_registration_order() -> void:
	var state := new_state()
	var boundary: int = state.config["days_per_month"] * state.config["months_per_quarter"]
	var sim := Simulation.new()
	sim.add_system(OrderSystem.new(&"zeta"))
	sim.add_system(OrderSystem.new(&"alpha"))
	sim.advance(state, boundary - 1)
	state.system_data(&"order")["calls"] = []
	sim.step(state)
	var t := boundary
	assert_array(_calls(state)).is_equal([
		"zeta:d@%d" % t, "alpha:d@%d" % t,
		"zeta:m@%d" % t, "alpha:m@%d" % t,
		"zeta:q@%d" % t, "alpha:q@%d" % t,
	])


func test_run_order_follows_registration_not_alphabet_or_id() -> void:
	var state := new_state()
	var sim := Simulation.new()
	sim.add_system(OrderSystem.new(&"b"))
	sim.add_system(OrderSystem.new(&"a"))
	sim.step(state)
	assert_array(_calls(state)).is_equal(["b:d@1", "a:d@1"])


func test_duplicate_system_id_is_rejected() -> void:
	var sim := Simulation.new()
	assert_bool(sim.add_system(OrderSystem.new(&"a"))).is_true()
	var added := [true]
	await assert_error(func() -> void: added[0] = sim.add_system(OrderSystem.new(&"a"))) \
		.is_push_error("Simulation: duplicate system id 'a'")
	assert_bool(added[0]).is_false()
	assert_int(sim.system_count()).is_equal(1)


func test_state_calendar_helpers_follow_tick_and_config() -> void:
	var state := new_state()
	var dpm: int = state.config["days_per_month"]
	var mpq: int = state.config["months_per_quarter"]
	assert_int(state.month_index()).is_equal(0)
	assert_int(state.day_of_month()).is_equal(1)
	state.tick = dpm + 14
	assert_int(state.month_index()).is_equal(1)
	assert_int(state.day_of_month()).is_equal(15)
	state.tick = dpm * mpq
	assert_int(state.quarter_index()).is_equal(1)
	assert_bool(state.is_month_boundary()).is_true()
	assert_bool(state.is_quarter_boundary()).is_true()
	state.tick = dpm * mpq + 1
	assert_bool(state.is_month_boundary()).is_false()
	assert_bool(state.is_quarter_boundary()).is_false()


func test_step_takes_only_the_state_never_delta() -> void:
	var step_args: Array = []
	for m: Dictionary in Simulation.new().get_method_list():
		if m["name"] == "step":
			step_args = m["args"]
	assert_int(step_args.size()).is_equal(1)
	assert_str(step_args[0]["name"]).is_equal("state")
	for hook: String in ["on_daily", "on_monthly", "on_quarterly"]:
		for m: Dictionary in SimSystem.new().get_method_list():
			if m["name"] == hook:
				assert_int(m["args"].size()).is_equal(1)


func test_system_state_lives_in_game_state_and_changes_hash() -> void:
	var state := new_state()
	var before := state_hash_of(state)
	var sim := Simulation.new()
	sim.add_system(OrderSystem.new(&"a"))
	sim.step(state)
	assert_str(state_hash_of(state)).is_not_equal(before)
	assert_bool(state.to_dict()["systems"].has(&"order")).is_true()


func test_same_seed_and_commands_give_same_hash_different_seed_differs() -> void:
	var hashes: Array[String] = []
	for world_seed: int in [SEED, SEED, SEED + 1]:
		var state := new_state(world_seed)
		var sim := new_sim_full()
		sim.advance(state, 120)
		hashes.append(state_hash_of(state))
	assert_str(hashes[0]).is_equal(hashes[1])
	assert_str(hashes[0]).is_not_equal(hashes[2])
