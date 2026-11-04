extends ActorTestBase
## T-016 ölçüt 4 · Hafıza ve dedikodu (characters-npc §4.2): kapasite sınırı (K_mem), birleştirme, güncellik ağırlıklı
## konu hafızası, budama, tek sıçrama dedikodu ve olay fırtınasında değişmezler (S-N1).


func _rel(state: GameState, cfg: ActorConfig, actor_key: String, target: String = PLAYER) -> Dictionary:
	return ActorStore.relation(state, cfg, actor_key, target)


func test_memory_is_recorded_and_bounded_by_k_mem_forgetting_when_topics_are_all_distinct() -> void:
	var cfg := config_with_memory({"K_mem": 3})
	var state := new_actor_state(SEED, cfg)
	var topics := ["housing_cost", "mobility", "fiscal_burden", "environment_health", "jobs_income", "public_space",
		"heritage_identity", "services_utilities"]
	for i in topics.size():
		state.tick = i * 10
		apply(state, cfg, COUNCIL_1, event_of(topics[i], -300 if i % 2 == 0 else 300, 400))
	var actor := ActorStore.actor(state, COUNCIL_1)
	assert_int(actor["memory"].size()).is_equal(3)
	assert_int(actor["memory_dropped"]).is_equal(5)
	assert_str(actor["memory"][2]["topic_id"]).override_failure_message("en yeniler kalır").is_equal("services_utilities")


func test_same_topic_events_are_merged_not_dropped_and_counts_are_conserved() -> void:
	var cfg := config_with_memory({"K_mem": 3})
	var state := new_actor_state(SEED, cfg)
	for i in 10:
		state.tick = i * 5
		apply(state, cfg, COUNCIL_1, event_of("housing_cost", 100 * i - 400, 500))
	var actor := ActorStore.actor(state, COUNCIL_1)
	assert_int(actor["memory"].size()).is_equal(3)
	assert_int(actor["memory_dropped"]).is_equal(0)
	var total := 0
	for entry: Dictionary in actor["memory"]:
		total += entry["count"]
	assert_int(total).override_failure_message("birleştirme olay sayısını korur").is_equal(10)


func test_merge_weights_the_two_lowest_same_topic_entries_by_recency() -> void:
	var cfg := config_with_memory({"K_mem": 2})
	var state := new_actor_state(SEED, cfg)
	state.tick = 1
	apply(state, cfg, COUNCIL_1, event_of("housing_cost", 800, 800))
	state.tick = 400
	apply(state, cfg, COUNCIL_1, event_of("housing_cost", -200, 800))
	state.tick = 410
	var result := apply(state, cfg, COUNCIL_1, event_of("mobility", 100, 100))
	assert_bool(result["merged"]).is_true()
	var memory: Array = ActorStore.actor(state, COUNCIL_1)["memory"]
	assert_int(memory.size()).is_equal(2)
	assert_str(memory[0]["topic_id"]).is_equal("housing_cost")
	assert_int(memory[0]["count"]).is_equal(2)
	assert_int(memory[0]["valence"]) \
		.override_failure_message("yeni kayıt baskın: ortalama 300 değil, < 0").is_between(-200, -100)
	assert_int(memory[0]["tick"]).is_between(300, 400)
	assert_str(memory[1]["topic_id"]).is_equal("mobility")


func test_topic_memory_is_recency_weighted_and_long_memory_fades_slower() -> void:
	var cfg := config()
	var short_state := new_actor_state()
	apply(short_state, cfg, COUNCIL_1, event_of("housing_cost", -800, 1000))
	assert_int(ActorMemory.topic_memory(short_state, cfg, COUNCIL_1, "housing_cost")).is_equal(-800)
	short_state.tick = 360
	apply(short_state, cfg, COUNCIL_1, event_of("housing_cost", 800, 1000))
	var short_value := ActorMemory.topic_memory(short_state, cfg, COUNCIL_1, "housing_cost")
	assert_int(short_value).override_failure_message("yeni olumlu hatıra baskın").is_between(690, 720)
	var long_state := new_actor_state()
	apply(long_state, cfg, COUNCIL_1, event_of("housing_cost", -800, 1000, PLAYER, {"decay_class": "memory_long"}))
	long_state.tick = 360
	apply(long_state, cfg, COUNCIL_1, event_of("housing_cost", 800, 1000))
	var long_value := ActorMemory.topic_memory(long_state, cfg, COUNCIL_1, "housing_cost")
	assert_int(long_value).override_failure_message("uzun hafıza eski kötü olayı daha çok tutar").is_less(short_value)
	assert_int(ActorMemory.topic_memory(short_state, cfg, COUNCIL_1, "mobility")).is_equal(0)


func test_faded_memories_are_pruned_on_the_maintenance_cadence() -> void:
	var cfg := config()
	var state := new_actor_state()
	apply(state, cfg, COUNCIL_1, event_of("housing_cost", -500))
	state.tick = 497  # 71*7: bakım günü; ağırlık 2^(-497/90) ~ 2,2% >= 1%
	ActorMemory.advance(state, cfg)
	assert_int(ActorStore.actor(state, COUNCIL_1)["memory"].size()).is_equal(1)
	state.tick = 700  # ağırlık ~ 0,5% < 1%
	ActorMemory.advance(state, cfg)
	assert_int(ActorStore.actor(state, COUNCIL_1)["memory"].size()).is_equal(0)
	state.tick = 701  # bakım günü değil
	apply(state, cfg, COUNCIL_1, event_of("housing_cost", -500))
	state.tick = 704
	ActorMemory.advance(state, cfg)
	assert_int(ActorStore.actor(state, COUNCIL_1)["memory"].size()).is_equal(1)


func test_gossip_is_a_single_delayed_jump_to_direct_neighbours_only() -> void:
	# council.1 -105 güven: komşu (ortak bloc.1) -> 150*500*(-105)/1e6 = -7 (sıfıra doğru kesme), 14 gün sonra.
	var cfg := config()
	var state := new_actor_state()
	state.tick = 10
	apply(state, cfg, COUNCIL_1, event_of("housing_cost", -500))
	assert_int(ActorStore.data_ref(state)["spill_queue"].size()) \
		.override_failure_message("council.2, council.5, bloc.1").is_equal(3)
	for t in range(11, 24):
		state.tick = t
		ActorMemory.advance(state, cfg)
	assert_int(_rel(state, cfg, COUNCIL_2)["trust"]).override_failure_message("gecikme dolmadan etki yok").is_equal(0)
	state.tick = 24
	ActorMemory.advance(state, cfg)
	assert_int(_rel(state, cfg, COUNCIL_2)["trust"]).is_equal(-7)
	assert_int(_rel(state, cfg, COUNCIL_5)["trust"]).is_equal(-7)
	assert_int(_rel(state, cfg, BLOC_1)["trust"]).is_equal(-7)
	assert_int(_rel(state, cfg, COUNCIL_3)["trust"]) \
		.override_failure_message("ortak bağ yok: değişmez (-80 önsel)").is_equal(-80)
	assert_bool(ActorStore.actor(state, COUNCIL_4)["relations"].has(PLAYER)).is_false()
	assert_int(ActorStore.data_ref(state)["spill_queue"].size()) \
		.override_failure_message("zincir yok: kuyruk boşalır").is_equal(0)
	for t in range(25, 60):
		state.tick = t
		ActorMemory.advance(state, cfg)
	assert_int(_rel(state, cfg, COUNCIL_3)["trust"]).is_equal(-80)
	assert_int(_rel(state, cfg, COUNCIL_4)["trust"]) \
		.override_failure_message("dedikodu komşudan komşuya sıçramaz").is_equal(0)


func test_spill_queue_is_bounded_and_counts_what_it_drops() -> void:
	var cfg := config_with_memory({"spill_queue_max": 2})
	var state := new_actor_state(SEED, cfg)
	apply(state, cfg, COUNCIL_1, event_of("housing_cost", -500))
	assert_int(ActorStore.data_ref(state)["spill_queue"].size()).is_equal(2)
	assert_int(ActorStore.data_ref(state)["spill_dropped"]).is_equal(1)


func test_event_storm_keeps_every_bound_and_invariant() -> void:
	var cfg := config_with_memory({"K_mem": 6, "spill_queue_max": 12})
	var state := new_actor_state(SEED, cfg)
	var dice := RandomNumberGenerator.new()
	dice.seed = 7
	var topics := cfg.topic_ids
	var actors := ["actor.council.1", "actor.council.2", "actor.council.3", "actor.council.4", "actor.council.5",
		"actor.bloc.1", "actor.bloc.2", "actor.media.1"]
	for step in 600:
		state.tick = step
		var event := event_of(topics[dice.randi_range(0, topics.size() - 1)], dice.randi_range(-1000, 1000),
			dice.randi_range(0, 1000), PLAYER, {"attribution": dice.randi_range(0, 1000)})
		apply(state, cfg, actors[dice.randi_range(0, actors.size() - 1)], event)
		ActorMemory.advance(state, cfg)
	for key in actors:
		var actor := ActorStore.actor(state, key)
		assert_int(actor["memory"].size()).is_less_equal(6)
		for target: String in actor["relations"]:
			var rel := ActorStore.relation(state, cfg, key, target)
			assert_int(rel["trust"]).is_between(-1000, 1000)
			assert_int(rel["resentment"]).is_between(rel["scar_floor"], 1000)
			assert_int(rel["scar_floor"]).is_less_equal(rel["peak_resentment"])
			assert_int(rel["familiarity"]).is_between(0, 1000)
	assert_int(ActorStore.data_ref(state)["spill_queue"].size()).is_less_equal(12)
	assert_str(ActorStore.validate_data(ActorStore.data_ref(state))).is_empty()


func test_merge_picks_the_pair_with_the_lowest_weight_among_several_same_topic_pairs() -> void:
	var cfg := config_with_memory({"K_mem": 3})
	var state := new_actor_state(SEED, cfg)
	state.tick = 0
	apply(state, cfg, COUNCIL_1, event_of("housing_cost", 500, 600))
	state.tick = 10
	apply(state, cfg, COUNCIL_1, event_of("housing_cost", 300, 600))
	state.tick = 300
	apply(state, cfg, COUNCIL_1, event_of("mobility", -400, 600))
	state.tick = 305
	var result := apply(state, cfg, COUNCIL_1, event_of("mobility", -200, 600))
	assert_bool(result["merged"]).is_true()
	var memory: Array = ActorStore.actor(state, COUNCIL_1)["memory"]
	assert_int(memory.size()).is_equal(3)
	assert_str(memory[0]["topic_id"]).is_equal("housing_cost")
	assert_int(memory[0]["count"]).override_failure_message("en eski (en düşük ağırlıklı) çift birleşir").is_equal(2)
	assert_int(memory[1]["count"]).is_equal(1)
	assert_int(memory[2]["count"]).is_equal(1)


func test_gossip_never_flows_back_to_the_actor_the_event_was_about() -> void:
	# council.2 -> council.1 (ortak bloc.1): dedikodu council.1'e (olayın hedefi) gitmez; kendine ilişki oluşmaz.
	var cfg := config()
	var state := new_actor_state()
	state.tick = 1
	apply(state, cfg, COUNCIL_2, event_of("housing_cost", -800, 900, COUNCIL_1))
	for t in range(2, 30):
		state.tick = t
		ActorMemory.advance(state, cfg)
	assert_bool(ActorStore.actor(state, COUNCIL_1)["relations"].has(COUNCIL_1)) \
		.override_failure_message("kendine ilişki") \
		.is_false()
	assert_bool(ActorStore.actor(state, COUNCIL_5)["relations"].has(COUNCIL_1)) \
		.override_failure_message("komşuya yayıldı") \
		.is_true()
