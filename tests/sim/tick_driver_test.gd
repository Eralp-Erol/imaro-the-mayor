extends SimTestBase
## T-002 ölçüt 2 · Tick sürücüsü: gerçek zaman x hız -> tamsayı tick; farklı kare süresi dizileri aynı oyun
## süresinde aynı hash'i verir. Sürücü `src/app/` içindedir; simülasyon `delta` görmez.

const FAST_TPS := 4  # data/sim/core_config.json speeds.fast; test yapılandırmadan okur (aşağıda doğrulanır)


func _driver(state: GameState, speed: StringName = &"fast") -> TickDriver:
	var cfg := new_config()
	var driver := TickDriver.new(new_sim_full(), state, cfg.driver)
	assert_bool(driver.set_speed(speed)).is_true()
	return driver


## Verilen mikrosaniye kare dizisini sürer; yürütülen toplam tick'i döndürür.
func _run(driver: TickDriver, frames_usec: Array) -> int:
	var total := 0
	for usec: int in frames_usec:
		total += driver.advance_usec(usec)
	return total


func _constant(frame_usec: int, count: int) -> Array:
	var out: Array = []
	out.resize(count)
	out.fill(frame_usec)
	return out


## Toplamı tam `total_usec` olan, tohumlu rastgele bölünmüş kare dizisi (testin kendi RNG'si; sim'e dokunmaz).
func _random_split(total_usec: int, world_seed: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed
	var out: Array = []
	var left := total_usec
	while left > 0:
		var piece := mini(left, rng.randi_range(1, 90_000))
		out.append(piece)
		left -= piece
	return out


func test_config_speed_used_by_these_tests_matches_data() -> void:
	assert_int(new_config().driver["speeds"]["fast"]).is_equal(FAST_TPS)


func test_different_frame_sequences_same_game_time_give_same_hash() -> void:
	var total_usec := 10_000_000  # 10 s gerçek zaman x 4 tick/s = 40 tick
	var sequences: Array = [
		_constant(16_000, 625),
		_constant(40_000, 250),
		_constant(1_000_000, 10),
		[total_usec],
		_random_split(total_usec, 1),
		_random_split(total_usec, 2),
	]
	var hashes: Array[String] = []
	for seq: Array in sequences:
		var state := new_state()
		var driver := _driver(state)
		assert_int(_run(driver, seq)).is_equal(40)
		assert_int(state.tick).is_equal(40)
		hashes.append(state_hash_of(state))
	for h: String in hashes:
		assert_str(h).is_equal(hashes[0])


func test_float_delta_seconds_path_matches_integer_microseconds() -> void:
	var a := new_state()
	var da := _driver(a)
	for i in 250:
		da.advance(0.04)
	var b := new_state()
	_run(_driver(b), _constant(40_000, 250))
	assert_int(a.tick).is_equal(40)
	assert_str(state_hash_of(a)).is_equal(state_hash_of(b))


func test_different_total_time_gives_different_hash() -> void:
	var a := new_state()
	_run(_driver(a), _constant(40_000, 250))
	var b := new_state()
	_run(_driver(b), _constant(40_000, 251))  # 0,04 s fazla = 0,16 tick: henüz tam tick değil
	var c := new_state()
	_run(_driver(c), _constant(40_000, 256))  # 0,24 s fazla = 0,96 tick
	var d := new_state()
	_run(_driver(d), _constant(40_000, 257))  # 0,28 s fazla -> 41. tick
	assert_int(b.tick).is_equal(40)
	assert_int(c.tick).is_equal(40)
	assert_int(d.tick).is_equal(41)
	assert_str(state_hash_of(a)).is_equal(state_hash_of(b))
	assert_str(state_hash_of(a)).is_not_equal(state_hash_of(d))


func test_sub_tick_remainder_is_carried_across_frames() -> void:
	var state := new_state()
	var driver := _driver(state)  # 4 tick/s => tick başına 250 ms
	assert_int(driver.advance_usec(200_000)).is_equal(0)
	assert_int(driver.advance_usec(49_999)).is_equal(0)
	assert_int(driver.advance_usec(1)).is_equal(1)
	assert_int(state.tick).is_equal(1)


func test_pause_runs_zero_ticks_and_discards_time() -> void:
	var state := new_state()
	var driver := _driver(state, &"paused")
	assert_int(driver.advance_usec(60_000_000)).is_equal(0)
	assert_int(state.tick).is_equal(0)
	driver.set_speed(&"fast")
	assert_int(driver.advance_usec(100_000)).is_equal(0)  # duraklatıkken geçen süre birikmedi


func test_speed_multiplies_ticks_per_real_second() -> void:
	for pair: Array in [[&"normal", 10], [&"fast", 40], [&"fastest", 160]]:
		var state := new_state()
		var driver := _driver(state, pair[0])
		_run(driver, _constant(10_000, 1000))  # 10 s
		assert_int(state.tick).override_failure_message("hız %s" % pair[0]).is_equal(pair[1])


func test_speed_change_mid_run_is_deterministic_regardless_of_frame_split() -> void:
	var hashes: Array[String] = []
	for frame_usec: int in [10_000, 25_000, 50_000]:
		var state := new_state()
		var driver := _driver(state, &"normal")
		_run(driver, _constant(frame_usec, 2_000_000 / frame_usec))  # 2 s @ 1 tps = 2 tick
		driver.set_speed(&"fastest")
		_run(driver, _constant(frame_usec, 1_000_000 / frame_usec))  # 1 s @ 16 tps = 16 tick
		driver.set_speed(&"fast")
		_run(driver, _constant(frame_usec, 500_000 / frame_usec))  # 0,5 s @ 4 tps = 2 tick
		assert_int(state.tick).is_equal(20)
		hashes.append(state_hash_of(state))
	assert_str(hashes[1]).is_equal(hashes[0])
	assert_str(hashes[2]).is_equal(hashes[0])


func test_single_huge_frame_is_capped_per_call_but_no_time_is_lost() -> void:
	var cfg := new_config()
	var cap: int = cfg.driver["max_ticks_per_advance"]
	var state := new_state()
	var driver := _driver(state)
	var huge := 1_000_000 * 100  # 100 s -> 400 tick > sınır
	assert_int(huge * FAST_TPS / 1_000_000).is_greater(cap)
	assert_int(driver.advance_usec(huge)).is_equal(cap)
	assert_int(state.tick).is_equal(cap)
	for i in 20:  # sınırlı döngü: sürücü zaman kaybederse test takılmadan başarısız olsun
		if state.tick >= 400:
			break
		assert_int(driver.advance_usec(0)).is_between(1, cap)
	assert_int(state.tick).is_equal(400)
	assert_int(driver.advance_usec(0)).is_equal(0)


func test_negative_delta_is_ignored() -> void:
	var state := new_state()
	var driver := _driver(state)
	assert_int(driver.advance_usec(-5_000_000)).is_equal(0)
	assert_int(driver.advance(-1.0)).is_equal(0)
	assert_int(state.tick).is_equal(0)


func test_unknown_speed_is_refused_and_keeps_current_speed() -> void:
	var state := new_state()
	var driver := _driver(state, &"normal")
	assert_bool(driver.set_speed(&"warp_nine")).is_false()
	assert_str(str(driver.speed)).is_equal("normal")


func test_rebinding_a_loaded_state_continues_identically() -> void:
	var straight := new_state()
	var d1 := _driver(straight)
	_run(d1, _constant(40_000, 500))
	var first := new_state()
	var d2 := _driver(first)
	_run(d2, _constant(40_000, 250))
	var restored := SimSave.decode(SimSave.encode(first)).state
	d2.bind_state(restored)
	_run(d2, _constant(40_000, 250))
	assert_int(restored.tick).is_equal(straight.tick)
	assert_str(state_hash_of(restored)).is_equal(state_hash_of(straight))
