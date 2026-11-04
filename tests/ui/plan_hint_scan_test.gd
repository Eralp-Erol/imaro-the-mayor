extends GdUnitTestSuite
## Yol sonrası "imar planı yok" ipucu taraması kare dilimli (`PlanHintScan`): sonuç eski tek seferlik taramayla AYNI
## (aynı sıra, aynı bölge başına üst sınır, ilk doğruda durma); dilimleme yalnız işi karelere böler. Sabit
## kare/süre yok:
## bütçe 0 -> çağrı başına en çok bir parsel denetimi.

const LIMIT := 5


## Eski davranış (referans): bölgeler sırasıyla, her birinde ilk LIMIT parsel, ilk doğruda dur.
func _reference(codes: Array, ids_of: Callable, needs: Callable) -> bool:
	for code: Variant in codes:
		var ids: PackedInt64Array = ids_of.call(code)
		for i in mini(ids.size(), LIMIT):
			if bool(needs.call(ids[i])):
				return true
	return false


func _ids_of(table: Dictionary) -> Callable:
	return func(code: Variant) -> PackedInt64Array: return table.get(code, PackedInt64Array())


func test_scan_result_equals_the_one_shot_reference_for_many_layouts() -> void:
	var table := {"A": PackedInt64Array([1, 2, 3, 4, 5, 6, 7]), "B": PackedInt64Array([10, 11, 12]),
			"C": PackedInt64Array()}
	var ids_of := _ids_of(table)
	for planned_from in [[], [3], [6], [7], [11], [10, 12], [1, 2, 3, 4, 5, 6, 7, 10, 11, 12]]:
		var needing: Array = planned_from
		var needs := func(id: int) -> bool: return needing.has(id)
		for codes in [["A"], ["B"], ["A", "B"], ["C", "B"], ["C"], []]:
			var scan := PlanHintScan.create(codes, ids_of, needs, LIMIT)
			scan.start()
			var got := scan.settle()
			assert_bool(got).override_failure_message("needing=%s codes=%s" % [str(needing), str(codes)]) \
					.is_equal(_reference(codes, ids_of, needs))
			assert_bool(scan.done).is_true()


func test_limit_is_per_region_and_parcels_after_it_are_never_checked() -> void:
	var table := {"A": PackedInt64Array([1, 2, 3, 4, 5, 6, 7]), "B": PackedInt64Array([20, 21])}
	var needs := func(id: int) -> bool: return id == 6   # LIMIT'ten sonra: görünmez
	var scan := PlanHintScan.create(["A", "B"], _ids_of(table), needs, LIMIT)
	scan.start()
	assert_bool(scan.settle()).is_false()
	assert_int(scan.checked).is_equal(LIMIT + 2)


func test_zero_budget_checks_at_most_one_parcel_per_step_and_stops_at_the_first_hit() -> void:
	var table := {"A": PackedInt64Array([1, 2, 3, 4, 5])}
	var needs := func(id: int) -> bool: return id == 3
	var scan := PlanHintScan.create(["A"], _ids_of(table), needs, LIMIT)
	scan.start()
	var steps := 0
	var before := 0
	while not scan.step(0):
		steps += 1
		assert_int(scan.checked - before).override_failure_message("adım başına en çok bir parsel").is_less_equal(1)
		before = scan.checked
		if steps > 1000:
			break
		OS.delay_msec(1)   # işçi bölge listesini hazırlayana dek adımlar boş döner
	assert_bool(scan.found).is_true()
	assert_int(scan.checked).override_failure_message("ilk doğruda durur").is_equal(3)


func test_empty_region_list_is_done_and_not_found_immediately() -> void:
	var scan := PlanHintScan.create([], Callable(), Callable(), LIMIT)
	assert_bool(scan.done).is_true()
	assert_bool(scan.step(0)).is_true()
	assert_bool(scan.found).is_false()


func test_dropping_a_scan_with_pending_worker_tasks_does_not_leak_or_crash() -> void:
	var table := {"A": PackedInt64Array([1]), "B": PackedInt64Array([2])}
	var scan := PlanHintScan.create(["A", "B"], _ids_of(table), func(_id: int) -> bool: return true, LIMIT)
	scan.start()
	scan = null   # PREDELETE işçileri bekler
	assert_bool(true).is_true()
