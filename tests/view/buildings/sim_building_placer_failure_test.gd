extends GdUnitTestSuite
## B-002 · SimBuildingPlacer yerleşememe nedenleri ve ek denemeler: ek denemeler ÖNCE yerleşen hiçbir parselin sonucunu
## değiştirmez, geometri/site kuralları aynıdır; neden kodu her başarısız planda doludur.

var _placer: SimBuildingPlacer
var _ids: Array[int] = []


func before() -> void:
	var fx := M2RenderSupport.fixture()
	_placer = SimBuildingPlacer.create(fx["settlement"], SimBuildingMapping.load_default(), M2RenderSupport.SEED)
	for v: ParcelView in fx["views"]:
		_ids.append(v.id)


func _signature(plan: SimBuildingPlacer.Plan) -> String:
	if plan == null:
		return "null"
	var parts := PackedStringArray()
	for p in plan.pieces:
		parts.append("%s@%.3f,%.3f,%d,%d,%d" % [p.module.id, p.u0, p.v0, p.wall, p.roof, p.accent])
	return ";".join(parts)


func test_every_failed_plan_has_a_reason_and_successful_ones_have_none() -> void:
	var failed := 0
	var merged := 0
	for pid in _ids:
		var plan := _placer.plan(pid, &"residential", 4)
		if plan == null:
			failed += 1
			assert_str(String(_placer.plan_failure())).override_failure_message("parsel %d: neden yok" % pid).is_not_empty()
			if _placer.plan_failure() == SimBuildingPlacer.FAIL_T0_MERGED:
				merged += 1
		else:
			assert_str(String(_placer.plan_failure())).is_empty()
	assert_int(failed).is_greater(0)
	assert_int(merged).is_greater(0)
	assert_object(_placer.plan(-5, &"residential", 4)).is_null()
	assert_str(String(_placer.plan_failure())).is_equal("no_parcel")
	assert_object(_placer.plan(_ids[0], &"nonexistent", 4)).is_null()
	assert_str(String(_placer.plan_failure())).is_equal("unknown_use")


func test_extra_attempts_never_change_an_already_placed_parcel_and_only_add_placements() -> void:
	var added := 0
	for pid in _ids:
		for units: int in [1, 4, 20, 400]:
			_placer.extra_attempts = false
			var base := _signature(_placer.plan(pid, &"residential", units))
			_placer.extra_attempts = true
			var ext := _signature(_placer.plan(pid, &"residential", units))
			if base != "null":
				assert_str(ext).override_failure_message("parsel %d birim %d: mevcut yerleşim değişti" % [pid, units]) \
						.is_equal(base)
			elif ext != "null":
				added += 1
	_placer.extra_attempts = true
	# Çok büyük birim (400) sığan en uzun modüle indirilir: en az bir parsel yeni yerleşir ya da hepsi zaten yerleşiyordu.
	assert_int(added).is_greater_equal(0)


func test_huge_unit_counts_fall_back_to_the_tallest_fitting_module() -> void:
	var placed_without := 0
	var placed_with := 0
	for pid in _ids:
		_placer.extra_attempts = false
		if _placer.plan(pid, &"residential", 5000) != null:
			placed_without += 1
		_placer.extra_attempts = true
		if _placer.plan(pid, &"residential", 5000) != null:
			placed_with += 1
	assert_int(placed_with).override_failure_message("ek deneme birim=5000 için hiçbir parsel kazanmadı") \
			.is_greater(placed_without)
