extends "res://tests/sim/public_works/resettlement_test_base.gd"
## T-065 Aşama 1 · Kalıcı politika durumu `state.systems["policy"]` ve `policy.set` komutu (ADR-0009 A/C/D, D-016 §1).
## Bölüm YALNIZ ilk KABUL EDİLEN `policy.set` ile yaratılır (okuma/önizleme/doğrulama/ret yaratmaz); yokluk = kapalı;
## kapatma bölümü silmez; kayıt sürümü artmaz, eski kayıt açılır; bozuk bölüm `corrupt` ile reddedilir.


func _has_section(run: Dictionary) -> bool:
	return _h(run).state().systems.has("policy")


# --- Tembel yaratım: dokunulmazsa tek bayt yok ---

func test_the_section_is_never_created_by_reads_previews_validation_or_rejections() -> void:
	var run := _rworld(60)
	var f := _f(run)
	f.advance(10)
	assert_bool(_has_section(run)).is_false()
	f.policies()
	f.validate_command(SimCommand.policy_set(PolicyView.ID_RESETTLEMENT, true))  # kuru koşu
	f.validate_command(SimCommand.public_work_road(PackedInt64Array(DIAGONAL), &"local", true))  # önizleme
	f.snapshot()
	assert_bool(_has_section(run)).override_failure_message("okuma/önizleme bölüm yarattı").is_false()
	# ret de yaratmaz: bilinmeyen politika, zaten kapalı
	assert_bool(f.submit_command(SimCommand.policy_set(&"no_such_policy", true)).is_rejected()).is_true()
	assert_bool(f.submit_command(SimCommand.policy_set(PolicyView.ID_RESETTLEMENT, false)).is_rejected()).is_true()
	f.advance(3)
	assert_bool(_has_section(run)).override_failure_message("ret bölüm yarattı").is_false()


func test_a_whole_run_with_roads_and_no_policy_command_never_writes_the_section_or_a_record() -> void:
	var run := _rworld(60)
	_road(run)
	_f(run).advance(40)
	assert_bool(_has_section(run)).is_false()
	assert_bool(_record(run).is_empty()).override_failure_message("kapalıyken tahsis kaydı yazıldı").is_true()
	assert_int(_f(run).public_works()[0].rehoused_households).is_equal(0)
	assert_bool(_f(run).public_works()[0].resettlement_applied).is_false()


# --- policy.set ---

func test_the_first_accepted_set_creates_the_section_with_who_and_when() -> void:
	var run := _rworld()
	var queued := _f(run).submit_command(SimCommand.policy_set(PolicyView.ID_RESETTLEMENT, true))
	assert_str(String(queued.status)).is_equal("queued")
	_f(run).advance(1)
	var section: Dictionary = _h(run).state().systems["policy"]
	assert_int(int(section["version"])).is_equal(1)
	var row: Dictionary = section["resettlement"]
	assert_bool(bool(row["enabled"])).is_true()
	assert_int(int(row["command_id"])).is_equal(queued.command_id)
	assert_int(int(row["changed_tick"])).is_greater_equal(1)
	var views := _f(run).policies()
	assert_int(views.size()).is_equal(1)
	assert_bool(views[0].enabled).is_true()
	assert_int(views[0].changed_by_command).is_equal(queued.command_id)
	assert_int(views[0].changed_tick).is_equal(int(row["changed_tick"]))
	assert_str(String(views[0].provenance)).is_equal("sim")


func test_a_set_writes_a_reason_and_a_policy_changed_event_then_command_applied() -> void:
	var run := _rworld()
	var queued := _do(run, SimCommand.policy_set(PolicyView.ID_RESETTLEMENT, true))
	var events := _events(run, SimEvent.KIND_POLICY_CHANGED)
	assert_int(events.size()).is_equal(1)
	assert_str(String(events[0].args["policy_id"])).is_equal("resettlement")
	assert_bool(bool(events[0].args["enabled"])).is_true()
	assert_bool(bool(events[0].args["previous"])).is_false()
	assert_int(events[0].command_id).is_equal(queued.command_id)
	assert_int(events[0].reason_ids.size()).is_equal(1)  # SIM-12: karar gerekçesi
	var reason := _f(run).reason(events[0].reason_ids[0])
	assert_str(String(reason.decision_key)).is_equal("decision.municipal.policy_set")
	var seqs: Array[int] = []
	for e in _f(run).events_since(0):
		if e.command_id == queued.command_id:
			seqs.append(e.seq)
			if e.kind == SimEvent.KIND_COMMAND_APPLIED:
				assert_int(e.seq).override_failure_message("command.applied olaydan ÖNCE").is_greater(
					events[0].seq)


func test_switching_off_keeps_the_section_and_records_the_new_value() -> void:
	var run := _rworld()
	_policy(run, true)
	_policy(run, false)
	assert_bool(_has_section(run)).is_true()
	assert_bool(bool(_h(run).state().systems["policy"]["resettlement"]["enabled"])).is_false()
	assert_bool(_f(run).policies()[0].enabled).is_false()
	var events := _events(run, SimEvent.KIND_POLICY_CHANGED)
	assert_int(events.size()).is_equal(2)
	assert_bool(bool(events[1].args["previous"])).is_true()


func test_unchanged_unknown_and_not_built_are_rejected_with_the_documented_codes() -> void:
	var run := _rworld()
	var unchanged := _f(run).validate_command(SimCommand.policy_set(PolicyView.ID_RESETTLEMENT, false))
	assert_str(String(unchanged.reason_key)).is_equal("command.reject.precondition")
	assert_str(String(unchanged.args["why"])).is_equal("policy.unchanged")
	var unknown := _f(run).validate_command(SimCommand.policy_set(&"no_such_policy", true))
	assert_str(String(unknown.reason_key)).is_equal("command.reject.invalid_value")
	assert_str(String(unknown.args["param"])).is_equal("policy_id")
	_policy(run, true)
	var twice := _f(run).validate_command(SimCommand.policy_set(PolicyView.ID_RESETTLEMENT, true))
	assert_str(String(twice.args["why"])).is_equal("policy.unchanged")
	# yapılandırmada yoksa: system.not_built
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PublicWorksConfig.DEFAULT_PATH))
	(raw["expropriation"] as Dictionary).erase("resettlement")
	var bare := _world(false, Callable(), [], true, PublicWorksConfig.from_dict(raw))
	var unbuilt := _f(bare).validate_command(SimCommand.policy_set(PolicyView.ID_RESETTLEMENT, true))
	assert_str(String(unbuilt.reason_key)).is_equal("command.reject.precondition")
	assert_str(String(unbuilt.args["why"])).is_equal("system.not_built")
	assert_int(_f(bare).policies().size()).override_failure_message("kurulu olmayan politika listelenmez").is_equal(0)


func test_policies_lists_resettlement_off_and_never_changed_on_a_fresh_world() -> void:
	var views := _f(_rworld()).policies()
	assert_int(views.size()).is_equal(1)
	assert_str(String(views[0].policy_id)).is_equal("resettlement")
	assert_bool(views[0].enabled).is_false()
	assert_int(views[0].changed_tick).is_equal(-1)
	assert_int(views[0].changed_by_command).is_equal(0)


func test_the_policy_is_a_command_and_creates_no_building_can03() -> void:
	var run := _rworld(60)
	var built_before := _res_built(run, SOURCE) + _res_built(run, TARGET)
	var views_before := _f(run).parcel_views(_f(run).parcel_ids())
	_policy(run, true)
	_f(run).advance(20)
	assert_int(_res_built(run, SOURCE) + _res_built(run, TARGET)).is_equal(built_before)
	var views_after := _f(run).parcel_views(_f(run).parcel_ids())
	for k in views_before.size():
		assert_str(String(views_after[k].development)).is_equal(String(views_before[k].development))


# --- Determinizm, kayıt ---

func test_same_commands_same_hash_and_a_different_policy_gives_a_different_hash() -> void:
	var on_a := _rworld()
	_policy(on_a, true)
	_f(on_a).advance(10)
	var on_b := _rworld()
	_policy(on_b, true)
	_f(on_b).advance(10)
	assert_str(_f(on_a).state_hash()).is_equal(_f(on_b).state_hash())
	var never := _rworld()
	_f(never).advance(11)
	assert_str(_f(never).state_hash()).is_not_equal(_f(on_a).state_hash())


func test_save_with_the_policy_on_loads_into_a_fresh_world_and_resumes_the_same_hash() -> void:
	var run := _rworld(60)
	_policy(run, true)
	_f(run).advance(5)
	var bytes := _f(run).export_save()
	var straight := _rworld(60)
	_policy(straight, true)
	_f(straight).advance(5)
	_f(straight).advance(20)
	var fresh := _rworld(60)
	var result := _f(fresh).import_save(bytes)
	assert_bool(result.ok).override_failure_message(result.message).is_true()
	assert_bool(_f(fresh).policies()[0].enabled).is_true()
	assert_str(_f(fresh).state_hash()).is_equal(_f(run).state_hash())
	_f(fresh).advance(20)
	assert_str(_f(fresh).state_hash()).is_equal(_f(straight).state_hash())


func test_a_save_without_the_section_loads_as_off_and_the_save_version_is_unchanged() -> void:
	var run := _rworld(60)
	_f(run).advance(5)
	assert_bool(_has_section(run)).is_false()
	var fresh := _rworld(60)
	assert_bool(_f(fresh).import_save(_f(run).export_save()).ok).is_true()
	assert_bool(_f(fresh).policies()[0].enabled).is_false()
	assert_bool(_has_section(fresh)).is_false()
	assert_int(SimSave.VERSION).is_equal(2)  # ADR-0009 C: taşıma yok


func test_a_corrupt_policy_section_is_refused_on_load_with_corrupt() -> void:
	var run := _rworld()
	_policy(run, true)
	var good: Dictionary = (_h(run).state().systems["policy"] as Dictionary).duplicate(true)
	assert_str(PolicyState.validate_data(good)).is_empty()
	assert_str(PolicyState.validate_data(null)).is_empty()  # bölüm yoksa geçerli
	var bad_cases: Array = []
	var wrong_version := good.duplicate(true)
	wrong_version["version"] = 9
	bad_cases.append(wrong_version)
	var wrong_enabled := good.duplicate(true)
	wrong_enabled["resettlement"]["enabled"] = 1
	bad_cases.append(wrong_enabled)
	var wrong_tick := good.duplicate(true)
	wrong_tick["resettlement"]["changed_tick"] = -3
	bad_cases.append(wrong_tick)
	var wrong_command := good.duplicate(true)
	wrong_command["resettlement"]["command_id"] = 0
	bad_cases.append(wrong_command)
	bad_cases.append("not a dictionary")
	for bad in bad_cases:
		assert_str(PolicyState.validate_data(bad)).override_failure_message(str(bad)).is_not_empty()
	# zincir: GameState.validate_dict politika bölümünü de denetler
	var dict := _h(run).state().to_dict()
	assert_str(GameState.validate_dict(dict)).is_empty()
	dict["systems"]["policy"]["resettlement"]["enabled"] = "yes"
	assert_str(GameState.validate_dict(dict)).contains("policy")
	# bilinmeyen politika anahtarı reddedilmez (ileriye dönük), okunmaz
	var future := good.duplicate(true)
	future["future_policy"] = {"enabled": true}
	assert_str(PolicyState.validate_data(future)).is_empty()
