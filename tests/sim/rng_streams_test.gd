extends SimTestBase
## T-002 ölçüt 3 · Sistem başına tohumlu RNG akışları durumda saklanır; bir akışa ek çağrı diğerlerini kaydırmaz.


func _draws(state: GameState, stream: StringName, n: int) -> Array:
	var out: Array = []
	var rng := state.rng.stream(stream)
	for i in n:
		out.append(rng.randi())
	return out


func test_same_seed_same_stream_gives_identical_sequence() -> void:
	assert_array(_draws(new_state(), &"investors", 50)).is_equal(_draws(new_state(), &"investors", 50))


func test_different_world_seed_gives_different_sequence() -> void:
	assert_array(_draws(new_state(SEED), &"investors", 20)).is_not_equal(_draws(new_state(SEED + 1), &"investors", 20))


func test_different_streams_are_independent_sequences() -> void:
	var state := new_state()
	var seeds := {}
	for id: StringName in [&"investors", &"households", &"politics", &"macro", &"events"]:
		seeds[RngStreams.derive_seed(SEED, id)] = true
	assert_int(seeds.size()).is_equal(5)
	assert_array(_draws(state, &"investors", 20)).is_not_equal(_draws(state, &"households", 20))


func test_extra_calls_on_one_stream_do_not_shift_another() -> void:
	var quiet := new_state()
	var busy := new_state()
	var expected_b := _draws(quiet, &"households", 30)
	# busy durumda önce "investors" akışına bol çağrı yapılır, sonra "households" çekilir.
	_draws(busy, &"investors", 500)
	assert_array(_draws(busy, &"households", 30)).is_equal(expected_b)
	# Araya karışık çağrı: dönüşümlü çekim de aynı diziyi vermeli.
	var mixed := new_state()
	var got: Array = []
	for i in 30:
		got.append(mixed.rng.stream(&"households").randi())
		mixed.rng.stream(&"investors").randi()
		mixed.rng.stream(&"investors").randf()
	assert_array(got).is_equal(expected_b)


func test_system_with_extra_stream_calls_leaves_other_system_hash_state_unchanged() -> void:
	# Sistem düzeyinde: draw_a'ya ek akış çağrısı eklemek draw_b'nin verisini değiştirmemeli.
	var baseline := new_state()
	var sim_a := Simulation.new()
	sim_a.add_system(DrawSystem.new(&"draw_a", &"stream_a"))
	sim_a.add_system(DrawSystem.new(&"draw_b", &"stream_b"))
	sim_a.advance(baseline, 60)
	var changed := new_state()
	var noisy := DrawSystem.new(&"draw_a", &"stream_a")
	noisy.extra_stream = &"stream_a_extra"
	noisy.extra_draws = 7
	var sim_b := Simulation.new()
	sim_b.add_system(noisy)
	sim_b.add_system(DrawSystem.new(&"draw_b", &"stream_b"))
	sim_b.advance(changed, 60)
	assert_str(StateHash.of(changed.system_data(&"draw_b"))).is_equal(StateHash.of(baseline.system_data(&"draw_b")))
	assert_str(StateHash.of(changed.system_data(&"draw_a"))).is_equal(StateHash.of(baseline.system_data(&"draw_a")))
	# ... ama ek akışın kendisi ilerlediği için genel durum hash'i farklıdır (akış durumu hash'e girer).
	assert_str(state_hash_of(changed)).is_not_equal(state_hash_of(baseline))


func test_stream_state_is_in_game_state_and_hash() -> void:
	var state := new_state()
	var before := state_hash_of(state)
	state.rng.stream(&"investors").randi()
	var after := state_hash_of(state)
	assert_str(after).is_not_equal(before)
	var dumped: Dictionary = state.to_dict()["rng"]["streams"]
	assert_bool(dumped.has("investors")).is_true()
	assert_int(typeof(dumped["investors"]["seed"])).is_equal(TYPE_INT)
	assert_int(typeof(dumped["investors"]["state"])).is_equal(TYPE_INT)


func test_restored_streams_continue_exact_sequence() -> void:
	var state := new_state()
	_draws(state, &"investors", 17)
	_draws(state, &"households", 3)
	var copy := GameState.from_dict(state.to_dict())
	assert_array(_draws(copy, &"investors", 25)).is_equal(_draws(state, &"investors", 25))
	assert_array(_draws(copy, &"households", 25)).is_equal(_draws(state, &"households", 25))
	# Hiç dokunulmamış akış da kopyada aynı tohumdan başlar.
	assert_array(_draws(copy, &"politics", 5)).is_equal(_draws(state, &"politics", 5))


func test_derived_seed_matches_independent_reference_values() -> void:
	# Altın değerler bu GDScript'ten bağımsız bir Python referansıyla (aynı belgelenmiş algoritma: FNV-1a 32 + 32-bit
	# karıştırma) üretildi. Tohum türetimi sürümler/platformlar arası kayıt uyumu için SABİT kalmalı (PLT-04).
	assert_int(RngStreams.derive_seed(1, &"investors")).is_equal(5093529748252463653)
	assert_int(RngStreams.derive_seed(20261020, &"households")).is_equal(8218052277281210486)
	assert_int(RngStreams.derive_seed(0, &"a")).is_equal(5351607491849851896)


func test_derived_seed_depends_on_both_world_seed_and_stream_name() -> void:
	assert_int(RngStreams.derive_seed(1, &"investors")).is_not_equal(RngStreams.derive_seed(2, &"investors"))
	assert_int(RngStreams.derive_seed(1, &"investors")).is_not_equal(RngStreams.derive_seed(1, &"households"))
	assert_int(RngStreams.derive_seed(-1, &"investors")).is_greater_equal(0)
	assert_int(RngStreams.derive_seed(1 << 40, &"investors")).is_not_equal(RngStreams.derive_seed(1, &"investors"))
