extends "res://tests/sim/public_works/resettlement_queue_test_base.gd"
## T-067 (D-019 E1) · Bekleme listesi: hane kaderi, politika kapalıyken duraklama, geri al, gerekçe, kayıt/determinizm.

# --- Hane kaderi ---

func test_families_who_stayed_in_their_own_region_are_served_by_homes_built_there() -> void:
	var run := _queued()  # return_to_latent: aileler D1'in bekleyen talebinde
	_complete(run, SOURCE, 5)
	_f(run).advance(1)
	var record := _record(run)
	assert_int(int(record["rehoused"])).is_equal(5)
	assert_array((record["served"][0] as Array).slice(1, 3)).is_equal([SOURCE, SOURCE])
	assert_int(_latent(run, SOURCE)).override_failure_message("hane zaten orada: sayı değişmez").is_equal(420)
	assert_int(_latent(run, TARGET)).is_equal(40)


func test_under_leave_region_a_served_family_arrives_without_leaving_twice() -> void:
	var run := _queued(FULL, LEAVE)
	assert_int(_latent(run, SOURCE)).is_equal(420 - 16)  # bulunamayanlar ayrıldı
	_complete(run, TARGET, 10)
	_f(run).advance(1)
	assert_int(_latent(run, TARGET)).is_equal(50)
	assert_int(_latent(run, SOURCE)).override_failure_message("kaynaktan ikinci kez düşmez").is_equal(420 - 16)
	assert_int(int((_record(run)["served"][0] as Array)[5])).is_equal(0)


# --- Politika kapalıyken liste durur ---

func test_closing_the_policy_pauses_the_queue_and_homes_finished_meanwhile_do_not_count() -> void:
	var run := _queued()
	_policy(run, false)
	_complete(run, TARGET, 10)
	_f(run).advance(3)
	assert_int(int(_record(run)["rehoused"])).override_failure_message("kapalıyken atama yok").is_equal(0)
	assert_int(_wait(run).waiting_households).override_failure_message("aile listede kalır").is_equal(16)
	_policy(run, true)
	_f(run).advance(3)
	assert_int(int(_record(run)["rehoused"])).override_failure_message("kapalıyken biten ev yeni sayılmaz").is_equal(0)
	_complete(run, TARGET, 4)
	_f(run).advance(1)
	assert_int(int(_record(run)["rehoused"])).is_equal(4)


# --- Geri al ---

func test_undo_takes_back_the_homes_that_were_given_and_clears_the_queue() -> void:
	var run := _queued()
	_complete(run, TARGET, 10)
	_f(run).advance(1)
	_do(run, SimCommand.public_work_undo_last())
	assert_int(_latent(run, SOURCE)).is_equal(420)
	assert_int(_latent(run, TARGET)).is_equal(40)
	var restored := _events(run, SimEvent.KIND_PUBLIC_WORK_RESTORED)[0]
	assert_int(int(restored.args["rehoused_returned"])).is_equal(10)
	assert_bool(ResettlementQueue.exists(_state(run))).is_false()
	assert_int(_wait(run).waiting_households).is_equal(0)


func test_undo_under_leave_region_restores_the_departed_exactly_once() -> void:
	var run := _queued(FULL, LEAVE)
	_complete(run, TARGET, 10)
	_f(run).advance(1)
	_do(run, SimCommand.public_work_undo_last())
	assert_int(_latent(run, SOURCE)).is_equal(420)
	assert_int(_latent(run, TARGET)).is_equal(40)


# --- Gerekçe (SIM-12) ---

func test_every_assignment_leaves_a_reason_that_names_the_road_and_the_numbers() -> void:
	var run := _queued()
	_complete(run, TARGET, 10)
	_f(run).advance(1)
	var found := false
	for r in _f(run).reasons_for(SimContract.ref(SimContract.REF_COMMAND, _command_of(run))):
		if r.decision_key == ResettlementQueue.DECISION:
			found = true
			var served := 0
			for fac in r.factors:
				if fac.name_key == ResettlementQueue.FACTOR_SERVED:
					served = int(fac.value)
			assert_int(served).is_equal(10)
	assert_bool(found).is_true()


# --- Kayıt, determinizm ---

func test_two_runs_with_the_same_commands_reach_the_same_hash() -> void:
	var a := _queued()
	var b := _queued()
	for run in [a, b]:
		_f(run).advance(4)
		_complete(run, TARGET, 7)
		_f(run).advance(30)
	assert_str(_f(a).state_hash()).is_equal(_f(b).state_hash())
	var c := _queued()
	_f(c).advance(34)
	assert_str(_f(c).state_hash()).override_failure_message("ev verilmesi hash'e girer").is_not_equal(_f(a).state_hash())


func test_save_load_in_the_middle_of_the_wait_resumes_the_same_hash() -> void:
	var run := _queued()
	_f(run).advance(3)
	_complete(run, TARGET, 6)
	_f(run).advance(2)
	var bytes := _f(run).export_save()
	var fresh := _rworld(0, FULL)
	var loaded := _f(fresh).import_save(bytes)
	assert_bool(loaded.ok).override_failure_message(loaded.message).is_true()
	assert_str(_f(fresh).state_hash()).is_equal(_f(run).state_hash())
	assert_int(_f(fresh).policies()[0].waiting_households).is_equal(10)
	for each in [run, fresh]:
		_complete(each, TARGET, 5)
		_f(each).advance(30)
	assert_str(_f(fresh).state_hash()).is_equal(_f(run).state_hash())
	assert_int(_f(run).policies()[0].waiting_households).is_equal(5)


func test_a_corrupt_queue_record_or_mark_is_refused_on_load() -> void:
	var run := _queued()
	_complete(run, TARGET, 10)
	_f(run).advance(1)
	var good: Dictionary = PublicWorksState.data(_state(run)).duplicate(true)
	assert_str(PublicWorksState.validate_data(good)).is_empty()
	var cases := {
		"rehoused != Σ moves + Σ served": func(r: Dictionary) -> void: r["rehoused"] = 9,
		"served satırı kısa": func(r: Dictionary) -> void: r["served"][0] = [1, SOURCE, TARGET],
		"served hane <= 0": func(r: Dictionary) -> void: r["served"][0][3] = 0,
		"served sınıf 0/1 değil": func(r: Dictionary) -> void: r["served"][0][4] = 2,
		"served dizi değil": func(r: Dictionary) -> void: r["served"] = "x",
		"weight_by tamsayı değil": func(r: Dictionary) -> void: r["weight_by"] = {SOURCE: "x"},
		"partial > rehoused": func(r: Dictionary) -> void: r["partial"] = 99,
	}
	for label: String in cases:
		var bad := good.duplicate(true)
		(cases[label] as Callable).call(bad["works"][0]["expropriation"]["resettlement"])
		assert_str(PublicWorksState.validate_data(bad)).override_failure_message(label).is_not_empty()
	var policy: Dictionary = PolicyState.data(_state(run)).duplicate(true)
	assert_str(PolicyState.validate_data(policy)).is_empty()
	policy["resettlement_queue"] = {"built_mark": {SOURCE: "x"}}
	assert_str(PolicyState.validate_data(policy)).is_not_empty()
	policy["resettlement_queue"] = "x"
	assert_str(PolicyState.validate_data(policy)).is_not_empty()
