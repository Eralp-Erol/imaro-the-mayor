extends ActorTestBase
## T-016 ölçüt 4 · İlişki güncellemesi deterministik ve sınırlı (characters-npc §4, SIM-05/SIM-11): başlangıç önseli,
## güven/kırgınlık asimetrisi, yara izi, yarı ömürlü tembel çürüme, reddedilen olaylar, kampanya sınırı, hash kapsamı.
## Sayılar el ile türetilmiştir (impact = m*rho*alpha*fam/10^9; ayrıntı test içinde).


func _rel(state: GameState, cfg: ActorConfig, actor_key: String, target: String = PLAYER) -> Dictionary:
	return ActorStore.relation(state, cfg, actor_key, target)


func test_initial_state_is_built_from_the_roster_with_relation_priors_and_the_actors_stream() -> void:
	var cfg := config()
	var state := new_actor_state()
	assert_int(ActorStore.keys(state).size()).is_equal(9)
	assert_str(ActorStore.protagonist_key(state, cfg)).is_equal(PLAYER)
	var friendly := _rel(state, cfg, COUNCIL_1)
	assert_int(friendly["trust"]).is_equal(100)
	assert_int(friendly["trust0"]).override_failure_message("çürüme hedefi başlangıç güveni").is_equal(100)
	assert_int(friendly["familiarity"]).is_equal(200)
	var wary := _rel(state, cfg, COUNCIL_3)
	assert_int(wary["trust"]).is_equal(-80)
	assert_int(wary["resentment"]).is_equal(120)
	assert_int(wary["peak_resentment"]).is_equal(120)
	assert_int(_rel(state, cfg, MEDIA_1)["familiarity"]).is_equal(500)
	assert_bool(ActorStore.actor(state, COUNCIL_4)["relations"].is_empty()) \
		.override_failure_message("ilişkiler seyrek").is_true()
	assert_bool(state.rng.has_stream(&"actors")).is_true()
	assert_bool(ActorStore.config_matches(state, cfg)).is_true()


func test_initialization_is_idempotent_and_never_resets_progress() -> void:
	var cfg := config()
	var state := new_actor_state()
	apply(state, cfg, COUNCIL_1, event_of("housing_cost", -500))
	var before := state_hash_of(state)
	assert_bool(ActorStore.ensure_initialized(state, cfg)).is_true()
	assert_str(state_hash_of(state)).is_equal(before)


func test_positive_event_raises_trust_by_the_derived_amount() -> void:
	# council.1: duyarlılık housing_cost=500, tanıdıklık 200 -> fam 600; impact = 800*500*1000*600/1e9 = 240
	# kazanç = 400*240*(1000-100)*500/1e9 = 43
	var cfg := config()
	var state := new_actor_state()
	var result := apply(state, cfg, COUNCIL_1, event_of("housing_cost", 500))
	assert_int(result["impact"]).is_equal(240)
	assert_int(result["trust_delta"]).is_equal(43)
	var rel := _rel(state, cfg, COUNCIL_1)
	assert_int(rel["trust"]).is_equal(143)
	assert_int(rel["resentment"]).override_failure_message("kırgınlık yok, azalacak şey yok").is_equal(0)
	assert_int(rel["familiarity"]).override_failure_message("temas tanıdıklığı artırır").is_equal(220)


func test_negative_event_hits_trust_and_resentment_and_leaves_a_scar_floor() -> void:
	# loss = 800*240*(1000+100)*500/1e9 = 105 ; kırgınlık += 500*240*1000*500/1e9 = 60 ; yara izi = 300*60/1000 = 18
	var cfg := config()
	var state := new_actor_state()
	var result := apply(state, cfg, COUNCIL_1, event_of("housing_cost", -500))
	assert_int(result["trust_delta"]).is_equal(-105)
	assert_int(result["resentment_delta"]).is_equal(60)
	var rel := _rel(state, cfg, COUNCIL_1)
	assert_int(rel["trust"]).is_equal(-5)
	assert_int(rel["resentment"]).is_equal(60)
	assert_int(rel["peak_resentment"]).is_equal(60)
	assert_int(rel["scar_floor"]).is_equal(18)


func test_loss_aversion_makes_harm_outweigh_equal_benefit() -> void:
	var cfg := config()
	var gain_state := new_actor_state()
	var loss_state := new_actor_state()
	var gain: int = apply(gain_state, cfg, COUNCIL_2, event_of("housing_cost", 500))["trust_delta"]
	var loss: int = -apply(loss_state, cfg, COUNCIL_2, event_of("housing_cost", -500))["trust_delta"]
	assert_int(gain).is_equal(57)
	assert_int(loss).is_equal(115)
	assert_int(loss).override_failure_message("kayıp kazancın en az loss_aversion katı").is_greater_equal(2 * gain)


func test_impact_scales_with_salience_and_attribution_and_zero_means_no_relation_change() -> void:
	var cfg := config()
	var state := new_actor_state()
	var unconcerned := apply(state, cfg, COUNCIL_1, event_of("jobs_income", -900))
	assert_int(unconcerned["impact"]).override_failure_message("duyarlılık 0").is_equal(0)
	assert_int(_rel(state, cfg, COUNCIL_1)["trust"]).is_equal(100)
	assert_int(ActorStore.actor(state, COUNCIL_1)["memory"].size()) \
		.override_failure_message("olay yine de hatırlanır").is_equal(1)
	var halved := event_of("housing_cost", -100, 800, PLAYER, {"attribution": 500})
	var half := apply(new_actor_state(), cfg, COUNCIL_1, halved)
	var full := apply(new_actor_state(), cfg, COUNCIL_1, event_of("housing_cost", -100))
	assert_int(full["impact"]).is_equal(240)
	assert_int(half["impact"]).is_equal(120)
	var unattributed := apply(state, cfg, COUNCIL_1, event_of("housing_cost", -900, 800, PLAYER, {"attribution": 0}))
	assert_int(unattributed["impact"]).override_failure_message("sorumluluk yüklenmedi").is_equal(0)


func test_event_without_a_responsible_actor_only_updates_memory() -> void:
	var cfg := config()
	var state := new_actor_state()
	var before: Dictionary = ActorStore.actor(state, COUNCIL_2)["relations"].duplicate(true)
	var event := {"topic_id": "mobility", "valence": -600, "magnitude": 500}
	var result := apply(state, cfg, COUNCIL_2, event)
	assert_int(result["trust_delta"]).is_equal(0)
	assert_dict(ActorStore.actor(state, COUNCIL_2)["relations"]).is_equal(before)
	assert_int(ActorStore.actor(state, COUNCIL_2)["memory"].size()).is_equal(1)


func test_repair_restores_trust_but_never_erases_the_scar() -> void:
	var cfg := config()
	var state := new_actor_state()
	apply(state, cfg, COUNCIL_1, event_of("housing_cost", -1000, 1000))
	var harmed := _rel(state, cfg, COUNCIL_1)
	assert_int(harmed["scar_floor"]).is_greater(0)
	for i in 40:
		apply(state, cfg, COUNCIL_1, event_of("housing_cost", 1000, 1000))
	var repaired := _rel(state, cfg, COUNCIL_1)
	assert_int(repaired["trust"]).is_greater(harmed["trust"])
	assert_int(repaired["trust"]).is_less_equal(1000)
	assert_int(repaired["resentment"]).override_failure_message("kırgınlık yara izinin altına inemez") \
		.is_equal(harmed["scar_floor"])
	assert_int(repaired["scar_floor"]).is_equal(harmed["scar_floor"])


func test_trust_decays_toward_its_baseline_with_the_configured_half_life() -> void:
	# council.2: trust0 = 0; zarar sonrası güven -115 (el ile türetildi); 360 günde yarıya iner.
	var cfg := config()
	var state := new_actor_state()
	apply(state, cfg, COUNCIL_2, event_of("housing_cost", -500))
	assert_int(_rel(state, cfg, COUNCIL_2)["trust"]).is_equal(-115)
	state.tick = 360
	assert_int(_rel(state, cfg, COUNCIL_2)["trust"]).is_between(-59, -56)
	state.tick = 720
	assert_int(_rel(state, cfg, COUNCIL_2)["trust"]).is_between(-30, -27)
	state.tick = 100_000
	assert_int(_rel(state, cfg, COUNCIL_2)["trust"]).override_failure_message("hedefe tam varır, aşmaz").is_equal(0)


func test_resentment_outlives_trust_and_settles_exactly_on_the_scar_floor() -> void:
	# council.2: kırgınlık 72, yara izi 21 (300*72/1000); 900 günde fark yarıya iner: 21 + 51/2 ~ 46
	var cfg := config()
	var state := new_actor_state()
	apply(state, cfg, COUNCIL_2, event_of("housing_cost", -500))
	state.tick = 900
	var mid := _rel(state, cfg, COUNCIL_2)
	assert_int(mid["resentment"]).is_between(45, 48)
	state.tick = 100_000
	var settled := _rel(state, cfg, COUNCIL_2)
	assert_int(settled["resentment"]).is_equal(21)
	assert_int(settled["trust"]).is_equal(0)
	# güven yarı ömrü kırgınlıktan kısa: 360 günde güvenin kalan farkı oranı < kırgınlığınki
	state.tick = 360
	var at_year := _rel(state, cfg, COUNCIL_2)
	assert_bool(absi(at_year["trust"]) * 51 < (at_year["resentment"] - 21) * 115) \
		.override_failure_message("kırgınlık daha yavaş silinir").is_true()


func test_reading_a_relation_never_changes_state() -> void:
	var cfg := config()
	var state := new_actor_state()
	apply(state, cfg, COUNCIL_2, event_of("housing_cost", -500))
	var before := state_hash_of(state)
	state.tick = 50
	var hash_at_50 := state_hash_of(state)
	for i in 3:
		_rel(state, cfg, COUNCIL_2)
		_rel(state, cfg, COUNCIL_4)
		ActorInputs.relation_factors(state, cfg, COUNCIL_2, PLAYER, "housing_cost")
	assert_str(state_hash_of(state)).is_equal(hash_at_50)
	assert_str(before).is_not_equal(hash_at_50)


func test_invalid_events_are_rejected_without_touching_state() -> void:
	var cfg := config()
	var state := new_actor_state()
	var before := state_hash_of(state)
	var cases := {
		"protagonist": [PLAYER, event_of("housing_cost", -100), "kadro aktörü"],
		"bilinmeyen aktör": ["actor.council.99", event_of("housing_cost", -100), "council.99"],
		"bilinmeyen konu": [COUNCIL_1, event_of("no_topic", -100), "no_topic"],
		"valence": [COUNCIL_1, event_of("housing_cost", 1001), "valence"],
		"magnitude": [COUNCIL_1, event_of("housing_cost", 100, -1), "magnitude"],
		"attribution": [COUNCIL_1, event_of("housing_cost", 100, 500, PLAYER, {"attribution": 1001}), "attribution"],
		"decay_class": [COUNCIL_1, event_of("housing_cost", 100, 500, PLAYER, {"decay_class": "trust"}), "decay_class"],
		"bilinmeyen hedef": [COUNCIL_1, event_of("housing_cost", 100, 500, "actor.rival.1"), "rival.1"],
		"kendine": [COUNCIL_1, event_of("housing_cost", 100, 500, COUNCIL_1), "kendisi"],
		"bilinmeyen alan": [COUNCIL_1, event_of("housing_cost", 100, 500, PLAYER, {"bogus": 1}), "bogus"],
		"float": [COUNCIL_1, event_of("housing_cost", 100, 500, PLAYER, {"valence": 0.5}), "valence"],
	}
	for label: String in cases:
		var result := ActorMemory.apply_event(state, cfg, cases[label][0], cases[label][1])
		assert_bool(result["ok"]).override_failure_message("kabul edildi: %s" % label).is_false()
		assert_bool(str(result["error"]).contains(cases[label][2])) \
			.override_failure_message("%s: %s" % [label, str(result["error"])]).is_true()
	assert_str(state_hash_of(state)).override_failure_message("reddedilen olay durumu değiştirdi").is_equal(before)


func test_events_cannot_cross_campaign_boundaries() -> void:
	var cfg := mutated(func(f: Dictionary) -> void: roster_actor(f, COUNCIL_2)["campaign_id"] = "other_campaign")
	assert_bool(cfg.is_valid()).override_failure_message(cfg.error).is_true()
	var state := new_actor_state(SEED, cfg)
	var cross := ActorMemory.apply_event(state, cfg, COUNCIL_1, event_of("housing_cost", -100, 500, COUNCIL_2))
	assert_bool(cross["ok"]).is_false()
	assert_bool(str(cross["error"]).contains("CAN-09")).is_true()
	apply(state, cfg, COUNCIL_1, event_of("housing_cost", -500))
	var queued: Array = ActorStore.data_ref(state)["spill_queue"]
	for entry: Dictionary in queued:
		assert_str(entry["to"]).override_failure_message("kampanya dışına dedikodu sızdı").is_not_equal(COUNCIL_2)


func test_same_events_give_the_same_state_hash_and_a_changed_event_changes_it() -> void:
	var cfg := config()
	var a := new_actor_state()
	var b := new_actor_state()
	var c := new_actor_state()
	for state in [a, b]:
		state.tick = 5
		apply(state, cfg, COUNCIL_1, event_of("housing_cost", -500))
		apply(state, cfg, COUNCIL_3, event_of("mobility", 300))
	c.tick = 5
	apply(c, cfg, COUNCIL_1, event_of("housing_cost", -501))
	apply(c, cfg, COUNCIL_3, event_of("mobility", 300))
	assert_str(state_hash_of(a)).is_equal(state_hash_of(b))
	assert_str(state_hash_of(a)).override_failure_message("durum hash'e girmiyor").is_not_equal(state_hash_of(c))
