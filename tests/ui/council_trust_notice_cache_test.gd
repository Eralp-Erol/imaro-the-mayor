extends "res://tests/sim/politics/reaction_world_base.gd"
## B-042: `CouncilTrustNotice.affected_members` artımlı önbellekten (facade `latest_reason_by_subject`) AYNI sonucu
## verir (tam tarama `affected_members_scan` referanstır); yükleme/geri sarmada ve yeni `displacement_trust` kaydında
## geçersizlenir.

const TRUST := {"enabled": true, "decision": "decision.council.displacement_trust", "cohorts": ["housed"],
	"window_days": 30, "threshold_households": 2, "drop_per_household_pm": 10, "cap_pm": 400,
	"recover_per_scan_pm": 400}


func _road_world(expropriate: bool) -> PoliticsHandle:
	var edit := func(files: Dictionary) -> void:
		files["reactions"] = _raw_reactions()
		files["reactions"]["council_trust"] = TRUST.duplicate(true)
	return _world(expropriate, edit)["handle"]


func _same(h: PoliticsHandle) -> int:
	var fast := CouncilTrustNotice.affected_members(h.facade)
	assert_int(fast).override_failure_message("önbellekli sonuç tam taramadan farklı").is_equal(
		CouncilTrustNotice.affected_members_scan(h.facade))
	return fast


func test_cached_result_matches_full_scan_through_drop_and_recovery() -> void:
	var h := _road_world(true)
	assert_int(_same(h)).is_equal(0)  # henüz tarama yok
	h.facade.advance(14)
	assert_int(_same(h)).is_equal(3)
	assert_int(_same(h)).is_equal(3)  # ikinci çağrı (önbellek sıcak)
	for i in 5:
		h.facade.advance(1)  # başka gerekçe kayıtları gelebilir; sonuç değişmez
		assert_int(_same(h)).is_equal(3)
	h.facade.advance(400)
	assert_int(_same(h)).is_equal(0)


func test_negative_case_without_demolition_is_zero() -> void:
	var h := _road_world(false)
	h.facade.advance(14)
	assert_int(_same(h)).is_equal(0)
	h.facade.advance(30)
	assert_int(_same(h)).is_equal(0)


func test_cache_invalidates_on_load_rewind() -> void:
	var h := _road_world(true)
	h.facade.advance(14)
	var saved := h.facade.export_save()
	assert_int(_same(h)).is_equal(3)
	h.facade.advance(400)
	assert_int(_same(h)).is_equal(0)
	var res := h.facade.import_save(saved)
	assert_bool(res.ok).is_true()
	assert_int(_same(h)).override_failure_message("geri sarma sonrası eski güven kesintisi görünmeli").is_equal(3)
	h.facade.advance(400)
	assert_int(_same(h)).is_equal(0)


func test_new_trust_record_after_warm_cache_is_seen() -> void:
	var h := _road_world(false)
	h.facade.advance(20)
	assert_int(_same(h)).is_equal(0)  # önbellek sıcak, kayıt yok
	h.facade.submit_command(SimCommand.public_work_road(PackedInt64Array(DIAGONAL), &"local", true))
	h.facade.advance(14)
	assert_int(_same(h)).is_equal(CouncilTrustNotice.affected_members_scan(h.facade))


func test_facade_without_fast_path_falls_back_to_scan() -> void:
	var mock := MockSimFacade.new()
	assert_int(CouncilTrustNotice.affected_members(mock)).is_equal(CouncilTrustNotice.affected_members_scan(mock))
