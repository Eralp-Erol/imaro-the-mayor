extends SimTestBase
## T-045 · `ParcelChangeLog` birim testleri: tekilleştirme/sıralama, pencere kesimi, sıkıştırma (uzun koşuda) ve
## yükleme sıfırlaması. Referans: kaba kuvvet (tüm geçmiş) listesi.


func _brute(history: Array, since: int) -> Array:
	var seen := {}
	for entry: Array in history:
		if int(entry[0]) > since:
			seen[int(entry[1])] = true
	var ids: Array = seen.keys()
	ids.sort()
	return ids


func test_ids_are_sorted_unique_and_only_after_the_requested_tick() -> void:
	var log := ParcelChangeLog.new(100)
	log.begin_tick(1)
	log.note(9)
	log.note(3)
	log.begin_tick(2)
	log.note(3)
	log.note(5)
	log.note(5)
	log.begin_tick(3)
	assert_array(Array(log.ids_since(0))).is_equal([3, 5, 9])
	assert_array(Array(log.ids_since(1))).is_equal([3, 5])
	assert_array(Array(log.ids_since(2))).is_equal([])
	assert_array(Array(log.ids_since(3))).is_equal([])
	assert_int(log.size()).is_equal(5)


func test_covers_is_false_for_the_future_and_for_ticks_older_than_the_window() -> void:
	var log := ParcelChangeLog.new(16)
	for t in range(1, 41):
		log.begin_tick(t)
		log.note(t)
	assert_int(log.floor_tick()).is_equal(24)
	assert_bool(log.covers(24, 40)).is_true()
	assert_bool(log.covers(23, 40)).is_false()
	assert_bool(log.covers(40, 40)).is_true()
	assert_bool(log.covers(41, 40)).is_false()
	assert_array(Array(log.ids_since(24))).is_equal(range(25, 41))
	assert_int(log.size()).is_equal(16)


func test_a_long_run_stays_bounded_and_equal_to_the_brute_force_reference_through_compaction() -> void:
	var log := ParcelChangeLog.new(16)
	var history: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 4545
	var max_size := 0
	for t in range(1, 6001):  # sıkıştırma eşiği (1024 sınır) birçok kez aşılır
		log.begin_tick(t)
		for _k in rng.randi_range(0, 5):
			var id := rng.randi_range(1, 400)
			log.note(id)
			history.append([t, id])
		max_size = maxi(max_size, log.size())
		if t % 97 == 0 or t > 5990:
			for since in [t - 16, t - 9, t - 1, t]:
				assert_array(Array(log.ids_since(since))).override_failure_message("tick %d since %d" % [t, since]) \
					.is_equal(_brute(history, since))
	assert_int(max_size).override_failure_message("halka sınırsız büyümemeli").is_less_equal(16 * 5)


func test_reset_forgets_history_and_only_keeps_what_comes_after_the_loaded_tick() -> void:
	var log := ParcelChangeLog.new(100)
	log.begin_tick(1)
	log.note(7)
	log.reset(50)
	assert_int(log.size()).is_equal(0)
	assert_bool(log.covers(49, 50)).is_false()
	assert_bool(log.covers(50, 50)).is_true()
	log.begin_tick(51)
	log.note(8)
	assert_array(Array(log.ids_since(50))).is_equal([8])
