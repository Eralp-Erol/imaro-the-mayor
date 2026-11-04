extends ActorTestBase
## T-016 ölçüt 3 · Sim sistemi olarak kayıt (`SimFacadeImpl.create(..., extra_systems)`): tembel başlatma, sabit sıra,
## tohumlu akış yalıtımı, durum hash kapsamı, determinizm, kare bağımsızlığı, kaydet->yükle->devam ve kapasite uyumu.

const TICKS := 130


func _facade(world_seed: int = SEED, variant: int = 0, sim_config: SimConfig = null) -> SimFacadeImpl:
	var cfg := config()
	var systems: Array[SimSystem] = [ActorSystem.create(cfg), ActorScenarioSystem.new(cfg, variant)]
	var impl := SimFacadeImpl.create(world_seed, FacadeTestSupport.fixture_source(3), sim_config, null, systems)
	assert_object(impl).is_not_null()
	return impl


func _obs(f: SimFacade) -> String:
	return assert_hash(StateHash.of(SimContractChecks.observable_state(f)))


func test_system_registers_with_the_facade_and_initializes_on_the_first_tick() -> void:
	var f := _facade()
	var state := f.game_state()
	assert_int(f.simulation().system_count()).override_failure_message("imar + aktör + senaryo").is_equal(3)
	assert_bool(ActorStore.is_initialized(state)).is_false()
	f.advance(1)
	assert_bool(ActorStore.is_initialized(state)).is_true()
	assert_int(ActorStore.keys(state).size()).is_equal(9)
	assert_bool(state.rng.has_stream(&"actors")).is_true()
	assert_str(str(ActorSystem.create(config()).system_id())).is_equal("actors")


func test_the_system_step_applies_due_gossip_and_the_queue_never_holds_overdue_entries() -> void:
	var f := _facade()
	f.advance(60)
	var state := f.game_state()
	var queue: Array = ActorStore.data_ref(state)["spill_queue"]
	for entry: Dictionary in queue:
		assert_int(entry["due_tick"]).override_failure_message("vadesi geçmiş dedikodu bekliyor").is_greater(state.tick)
	var spilled := 0
	for key in ActorStore.keys(state):
		spilled += 1 if ActorStore.actor(state, key)["relations"].has(PLAYER) else 0
	assert_int(spilled).is_greater(2)


func test_invalid_configuration_yields_no_system() -> void:
	var broken := mutated(func(f: Dictionary) -> void: f["memory_params"].erase("K_mem"))
	assert_bool(broken.is_valid()).is_false()
	assert_bool(ActorStore.ensure_initialized(new_state(), broken)).is_false()


func test_scenario_actually_exercises_events_decisions_gossip_and_memory() -> void:
	var f := _facade()
	f.advance(TICKS)
	var state := f.game_state()
	assert_int(state.reasons.size()).override_failure_message("ölü senaryo: karar yok").is_greater(15)
	var remembered := 0
	var related := 0
	for key in ActorStore.keys(state):
		var actor := ActorStore.actor(state, key)
		remembered += actor["memory"].size()
		related += actor["relations"].size()
	assert_int(remembered).is_greater(5)
	assert_int(related).is_greater(5)
	assert_int(f.last_event_seq()).is_greater(15)


func test_same_seed_and_script_give_identical_hash_and_observable_state() -> void:
	var a := _facade()
	var b := _facade()
	a.advance(TICKS)
	b.advance(TICKS)
	assert_str(assert_hash(a.state_hash())).is_equal(b.state_hash())
	assert_str(_obs(a)).is_equal(_obs(b))
	assert_array(SimContractChecks.check_facade(a)).is_empty()


func test_different_seed_or_different_player_actions_diverge() -> void:
	var base := _facade()
	var other_seed := _facade(SEED + 1)
	var other_play := _facade(SEED, 1)
	for f in [base, other_seed, other_play]:
		f.advance(TICKS)
	assert_str(base.state_hash()).override_failure_message("tohum aktör kararlarına girmiyor") \
		.is_not_equal(other_seed.state_hash())
	assert_str(base.state_hash()).override_failure_message("farklı olay aynı durumu veriyor (SIM-10)") \
		.is_not_equal(other_play.state_hash())
	assert_str(_obs(base)).is_not_equal(_obs(other_play))


func test_actor_state_is_part_of_the_hash_and_the_serialized_state() -> void:
	var f := _facade()
	f.advance(40)
	var state := f.game_state()
	var before := state.state_hash()
	var rel := ActorStore.ensure_relation(state, config(), COUNCIL_4, PLAYER)
	rel["trust"] = int(rel["trust"]) + 1
	assert_str(state.state_hash()).override_failure_message("ilişki hash'e girmiyor").is_not_equal(before)
	var copy := GameState.from_dict(state.to_dict())
	assert_object(copy).is_not_null()
	assert_str(copy.state_hash()).override_failure_message("seri hale getirme aktör durumunu kaybetti") \
		.is_equal(state.state_hash())
	assert_str(ActorStore.validate_data(copy.systems["actors"])).is_empty()


func test_frame_slicing_does_not_change_the_actor_state() -> void:
	var plans: Array = [
		[4_000_000, 4_000_000, 125_000],
		[65_000, 65_000, 4_000_000, 3_995_000],
		[1_000_000, 2_000_000, 1_500_000, 3_625_000],
	]
	var hashes: Array[String] = []
	for plan: Array in plans:
		var f := _facade()
		f.set_speed(SimFacade.SPEED_FASTEST)
		var ticks := 0
		for usec: int in plan:
			ticks += f.drive_usec(usec)
		assert_int(ticks).is_equal(TICKS)
		hashes.append(assert_hash(f.state_hash()))
	for h in hashes:
		assert_str(h).is_equal(hashes[0])


func test_save_load_continue_equals_the_uninterrupted_run() -> void:
	var straight := _facade()
	straight.advance(TICKS)
	var first := _facade()
	first.advance(70)
	var bytes := first.export_save()
	assert_int(bytes.size()).is_greater(0)
	var restored := _facade()
	var result := restored.import_save(bytes)
	assert_bool(result.ok).override_failure_message(result.message).is_true()
	assert_str(restored.state_hash()).is_equal(first.state_hash())
	restored.advance(TICKS - 70)
	assert_str(restored.state_hash()).override_failure_message("kayıt aktör durumunu/gürültüyü bozdu") \
		.is_equal(straight.state_hash())
	assert_str(_obs(restored)).is_equal(_obs(straight))
	assert_array(SimContractChecks.check_facade(restored)).is_empty()


func test_adding_the_actor_system_does_not_shift_other_systems_random_streams() -> void:
	var cfg := config()
	var alone := Simulation.new()
	alone.add_system(SimTestBase.DrawSystem.new(&"draw_a", &"stream_a"))
	var together := Simulation.new()
	together.add_system(SimTestBase.DrawSystem.new(&"draw_a", &"stream_a"))
	together.add_system(ActorSystem.create(cfg))
	together.add_system(ActorScenarioSystem.new(cfg))
	var state_a := new_state()
	var state_b := new_state()
	alone.advance(state_a, 90)
	together.advance(state_b, 90)
	assert_dict(state_b.systems["draw_a"]).override_failure_message("akış paylaşımı: ek sistem diğerini kaydırdı") \
		.is_equal(state_a.systems["draw_a"])
	assert_int(state_b.reasons.size()).is_greater(0)


func test_reason_capacity_is_respected_and_chains_stay_resolvable() -> void:
	var base := SimConfig.load_default()
	var small := SimConfig.from_dict({
		"sim": {"days_per_month": 30, "months_per_quarter": 3, "reason_log_capacity": 24, "command_log_capacity": 50,
			"event_log_capacity": 24},
		"driver": base.driver,
	})
	assert_bool(small.is_valid()).override_failure_message(small.error).is_true()
	var f := _facade(SEED, 0, small)
	f.advance(200)
	var state := f.game_state()
	assert_int(state.reasons.size()).is_equal(24)
	assert_array(SimContractChecks.check_facade(f)).is_empty()
	for key in ActorStore.keys(state):
		assert_int(ActorStore.actor(state, key)["memory"].size()).is_less_equal(32)
	assert_int(state.reasons.last_id()).override_failure_message("kimlikler yeniden kullanılmaz").is_greater(24)


func test_validate_data_accepts_good_state_and_explains_corruption() -> void:
	var f := _facade()
	f.advance(60)
	var good: Dictionary = f.game_state().systems["actors"]
	assert_str(ActorStore.validate_data(good)).is_empty()
	assert_str(ActorStore.validate_data(null)).override_failure_message("sistem hiç kurulmadıysa geçerli").is_empty()
	var cases := {
		"şema": func(d: Dictionary) -> void: d["schema"] = 2,
		"aktör sözlüğü": func(d: Dictionary) -> void: d["actors"] = [],
		"aktör anahtarı": func(d: Dictionary) -> void: d["actors"][COUNCIL_1]["key"] = "x",
		"kesirli güven": func(d: Dictionary) -> void: d["actors"][COUNCIL_1]["relations"][PLAYER]["trust"] = 1.5,
		"ilişki sözlük değil": func(d: Dictionary) -> void: d["actors"][COUNCIL_1]["relations"][PLAYER] = 3,
		"hafıza alanı": func(d: Dictionary) -> void:
			d["actors"][COUNCIL_1]["memory"].append({"tick": 1}),
		"dedikodu kuyruğu": func(d: Dictionary) -> void: d["spill_queue"] = {},
	}
	for label: String in cases:
		var copy: Dictionary = good.duplicate(true)
		cases[label].call(copy)
		assert_bool(ActorStore.validate_data(copy).is_empty()) \
			.override_failure_message("bozuk veri kabul edildi: %s" % label).is_false()
