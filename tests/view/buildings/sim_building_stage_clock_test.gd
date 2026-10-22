extends GdUnitTestSuite
## B-002 · SimBuildingStageClock: iki okumadan toplam inşaat süresi öğrenilir; kat kademesinin değişeceği gün
## kestirimi geç kalmaz (gerçek sim ilerleme formülüyle kaba kuvvet karşılaştırması).

const SCALE := 1000


func _progress(total: int, elapsed: int) -> int:
	return mini(SCALE * elapsed / total, SCALE - 1)


func test_prediction_never_overshoots_the_real_stage_change_for_many_totals() -> void:
	var clock := SimBuildingStageClock.new()
	var checked := 0
	for total: int in [48, 51, 57, 60, 63, 75, 99, 150, 300]:
		for first: int in [1, 2, 3]:
			for target_pm: int in [200, 334, 500, 667, 900]:
				var key := "k%d_%d_%d" % [total, first, target_pm]
				var p1 := _progress(total, first)
				var p2 := _progress(total, first + 1)
				if p2 >= target_pm or p1 >= target_pm:
					continue
				# İkinci okuma (ilk okuma `first` günde, bu okuma first+1'de): hız öğrenilir.
				var gap := clock.gap(key, Vector2i(first, p1), first + 1, p2, target_pm)
				assert_int(gap).override_failure_message("T=%d: süre öğrenilemedi" % total).is_greater(0)
				# Gerçek ilk gün: ilerleme target_pm'e ulaşan en küçük geçen gün.
				var real_day := first + 1
				while _progress(total, real_day) < target_pm:
					real_day += 1
				var predicted := first + 1 + gap
				assert_int(predicted).override_failure_message(
						"T=%d hedef=%d: tahmin gün %d > gerçek %d (geç kalır)" % [total, target_pm, predicted,
						real_day]).is_less_equal(real_day)
				checked += 1
	assert_int(checked).is_greater(50)


func test_candidates_narrow_with_more_samples_and_the_gap_becomes_exact() -> void:
	var clock := SimBuildingStageClock.new()
	var total := 63
	var key := "res|6"
	var prev := Vector2i(1, _progress(total, 1))
	var last_gap := -1
	for day in range(2, 20):
		last_gap = clock.gap(key, prev, day, _progress(total, day), 667)
		prev = Vector2i(day, _progress(total, day))
	assert_int(clock.candidates(key).size()).override_failure_message("adaylar daralmadı").is_less(10)
	var real := 2
	while _progress(total, real) < 667:
		real += 1
	assert_int(19 + last_gap).is_between(real - 2, real)


func test_unknown_without_a_previous_sample_and_model_violation_resets() -> void:
	var clock := SimBuildingStageClock.new()
	assert_int(clock.gap("a", Vector2i(-1, 0), 5, 100, 300)).is_equal(-1)
	assert_int(int(clock.stats["unknown"])).is_equal(1)
	# Tutarsız çift (ilerleme geri gitti): bilinmiyor, çökmez.
	assert_int(clock.gap("a", Vector2i(5, 500), 6, 100, 700)).is_equal(-1)
