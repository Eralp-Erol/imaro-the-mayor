extends "res://tests/sim/public_works/resettlement_test_base.gd"
## T-065 Aşama 1 · Yeniden iskân: geri alma, hane kaderi (leave_region), kayıt/yükleme ve determinizm (ölçütler 5, 9).

const FULL := {"max_distance_m": 5000}
const SPREAD := {"household_fate": "leave_region"}


func _roads(run: Dictionary) -> Array[PublicWorkView]:
	return _f(run).public_works()


func _o1() -> Dictionary:
	var run := _rworld(60, FULL)
	_policy(run, true)
	_road(run)
	return run


# --- Geri al ---

func test_undo_returns_the_households_and_the_reaction_rows_and_says_how_many_came_back() -> void:
	var run := _o1()
	assert_int(_latent(run, TARGET)).is_equal(56)
	_do(run, SimCommand.public_work_undo_last())
	assert_int(_latent(run, SOURCE)).is_equal(420)
	assert_int(_latent(run, TARGET)).is_equal(40)
	assert_int(_roads(run).size()).is_equal(0)
	var restored := _events(run, SimEvent.KIND_PUBLIC_WORK_RESTORED)[0]
	assert_int(int(restored.args["rehoused_returned"])).is_equal(16)
	assert_int(PublicWorksState.reaction_rows(_h(run).state(), "displaced", SOURCE).size()).is_equal(0)


func test_undo_clips_the_return_to_what_is_left_in_the_target_region() -> void:
	var run := _o1()
	_set_region(run, TARGET, 5, 100)  # aradan geçen ay hedefi azaltmış
	_do(run, SimCommand.public_work_undo_last())
	var restored := _events(run, SimEvent.KIND_PUBLIC_WORK_RESTORED)[0]
	assert_int(int(restored.args["rehoused_returned"])).override_failure_message("dürüst sayı").is_equal(5)
	assert_int(_latent(run, TARGET)).is_equal(0)
	assert_int(_latent(run, SOURCE)).is_equal(420 - 16 + 5)  # negatif yok, dönen kadar döndü


func test_a_restored_road_without_an_allocation_has_no_returned_key() -> void:
	var run := _rworld(60, FULL)
	_road(run)
	_do(run, SimCommand.public_work_undo_last())
	assert_bool(_events(run, SimEvent.KIND_PUBLIC_WORK_RESTORED)[0].args.has("rehoused_returned")).is_false()


# --- hane kaderi: leave_region ---

func test_under_leave_region_the_housed_households_are_moved_not_removed_twice() -> void:
	var run := _rworld(60, FULL, SPREAD)
	_policy(run, true)
	_road(run)
	assert_int(_latent(run, SOURCE)).override_failure_message("çift düşüm yok").is_equal(420 - 16)
	assert_int(_latent(run, TARGET)).is_equal(40 + 16)
	assert_int(int(_record(run)["rehoused"])).is_equal(16)
	_do(run, SimCommand.public_work_undo_last())
	assert_int(_latent(run, SOURCE)).is_equal(420)
	assert_int(_latent(run, TARGET)).is_equal(40)


func test_under_leave_region_the_unplaced_leave_and_come_back_on_undo() -> void:
	var run := _rworld(0, FULL, SPREAD)
	_policy(run, true)
	_road(run)
	assert_int(_latent(run, SOURCE)).is_equal(420 - 16)  # bulunamayan ayrıldı
	_do(run, SimCommand.public_work_undo_last())
	assert_int(_latent(run, SOURCE)).is_equal(420)


# --- Kayıt, determinizm ---

func test_save_load_and_n_ticks_reach_the_same_hash_with_an_allocation_on_the_books() -> void:
	var run := _o1()
	_f(run).advance(10)
	var bytes := _f(run).export_save()
	var fresh := _rworld(60, FULL)
	var loaded := _f(fresh).import_save(bytes)
	assert_bool(loaded.ok).override_failure_message(loaded.message).is_true()
	assert_str(_f(fresh).state_hash()).is_equal(_f(run).state_hash())
	assert_int(_f(fresh).public_works()[0].rehoused_households).is_equal(16)
	_f(run).advance(40)
	_f(fresh).advance(40)
	assert_str(_f(fresh).state_hash()).is_equal(_f(run).state_hash())


func test_two_runs_with_the_same_commands_reach_the_same_hash_and_the_policy_changes_the_hash() -> void:
	var a := _o1()
	var b := _o1()
	_f(a).advance(30)
	_f(b).advance(30)
	assert_str(_f(a).state_hash()).is_equal(_f(b).state_hash())
	var off := _rworld(60, FULL)
	_road(off)
	_f(off).advance(30)
	assert_str(_f(off).state_hash()).is_not_equal(_f(a).state_hash())


func test_a_record_that_does_not_add_up_is_refused_on_load() -> void:
	var run := _o1()
	var good: Dictionary = (PublicWorksState.data(_h(run).state())).duplicate(true)
	assert_str(PublicWorksState.validate_data(good)).is_empty()
	var cases := {
		"rehoused != Σ moves": func(r: Dictionary) -> void: r["rehoused"] = 15,
		"hane <= 0": func(r: Dictionary) -> void: r["moves"][0][2] = 0,
		"rehoused + unplaced != households": func(r: Dictionary) -> void: r["unplaced"] = 3,
		"unplaced != Σ unplaced_by": func(r: Dictionary) -> void: r["unplaced_by"] = {SOURCE: 2},
		"kod dizge değil": func(r: Dictionary) -> void: r["moves"][0][0] = 5,
		"effective eksik": func(r: Dictionary) -> void: r.erase("effective"),
		"moves dizi değil": func(r: Dictionary) -> void: r["moves"] = "x",
		"partial > rehoused": func(r: Dictionary) -> void: r["partial"] = 99,
		"cost negatif": func(r: Dictionary) -> void: r["cost"] = -1,
	}
	for label: String in cases:
		var bad := good.duplicate(true)
		(cases[label] as Callable).call(bad["works"][0]["expropriation"]["resettlement"])
		assert_str(PublicWorksState.validate_data(bad)).override_failure_message(label).is_not_empty()



## Kamulaştıran yol artık yıkılabilir (D-014 §1 "hep olsun"; parsel kimlikleri korunur). Yıkım geri alma DEĞİLDİR
## (ADR-0009 §6): tahsis geri alınmaz, taşınan haneler kaynağa dönmez, tepki satırları silinmez.
func test_demolishing_an_expropriating_road_does_not_undo_the_allocation() -> void:
	var run := _o1()
	var source_before := _latent(run, SOURCE)
	var rows_before := PublicWorksState.reaction_rows(_h(run).state(), "displaced", SOURCE).size()
	var works := PublicWorksState.standing_roads(_h(run).state())
	var road_id := int(works[works.size() - 1]["command_id"])
	var r := _f(run).submit_command(SimCommand.public_work_demolish(road_id))
	assert_bool(r.is_rejected()).override_failure_message("%s %s" % [r.reason_key, r.args]).is_false()
	_f(run).advance(1)
	assert_int(_roads(run).size()).is_equal(0)  # yol kalktı
	assert_int(_latent(run, TARGET)).is_equal(56)  # tahsis geri alınmadı
	assert_int(_latent(run, SOURCE)).is_equal(source_before)
	assert_int(PublicWorksState.reaction_rows(_h(run).state(), "displaced", SOURCE).size()).is_equal(rows_before)
	assert_int(_events(run, SimEvent.KIND_PUBLIC_WORK_RESTORED).size()).is_equal(0)  # "geri alındı" olayı yok
	assert_int(_events(run, SimEvent.KIND_PUBLIC_WORK_DEMOLISHED).size()).is_equal(1)
