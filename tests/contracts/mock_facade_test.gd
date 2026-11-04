extends GdUnitTestSuite
## T-023 ölçüt 3/5 · MockSimFacade SimFacade arayüzünü sağlar: değer kopyaları, tick sınırında uygulama, olay imleci,
## kuru doğrulama, hız; tüm senaryolar SimContractChecks uyum kontrollerinden geçer.

const S := preload("res://tests/contracts/contract_test_support.gd")


func _zoning_one() -> SimCommand:
	return SimCommand.zoning_propose(PackedInt64Array([1]), &"zone.mixed")


func test_mock_is_a_sim_facade_with_mock_provenance() -> void:
	var f := S.facade(S.SCENARIO_POSITIVE)
	assert_bool(f is SimFacade).is_true()
	assert_bool(f.is_mock()).is_true()
	assert_str(String(f.provenance())).is_equal("mock")
	assert_str(f.contract_version()).is_equal(SimContract.VERSION)


func test_mock_implements_every_facade_method() -> void:
	var facade_script: Script = load("res://src/contracts/sim_facade.gd")
	var f := S.facade(S.SCENARIO_POSITIVE)
	var names := 0
	for m: Dictionary in facade_script.get_script_method_list():
		names += 1
		assert_bool(f.has_method(m["name"])).override_failure_message("missing %s" % m["name"]).is_true()
	assert_int(names).is_greater_equal(16)


func test_every_scenario_conforms_before_and_after_driving() -> void:
	for scenario_name in S.ALL_SCENARIOS:
		var f := S.facade(scenario_name)
		assert_array(f.load_errors()).override_failure_message("%s: %s" % [scenario_name, f.load_errors()]).is_empty()
		assert_array(SimContractChecks.check_facade(f)).is_empty()
		f.submit_command(_zoning_one())
		f.submit_command(SimCommand.budget_propose({&"budget.line.roads": 50000}))
		f.advance(12)
		var problems := SimContractChecks.check_facade(f)
		assert_array(problems).override_failure_message("%s: %s" % [scenario_name, problems]).is_empty()


func test_command_is_queued_and_applied_only_at_next_tick_boundary() -> void:
	var f := S.facade(S.SCENARIO_POSITIVE)
	var r := f.submit_command(_zoning_one())
	assert_str(String(r.status)).is_equal("queued")
	assert_int(r.command_id).is_equal(1)
	assert_int(r.apply_tick).is_equal(1)
	assert_str(String(f.parcel_views(S.ids([1]))[0].pending_zone)).is_empty()
	assert_int(f.last_event_seq()).is_equal(0)
	assert_int(f.advance(1)).is_equal(1)
	var applied := S.events_of(f, SimEvent.KIND_COMMAND_APPLIED)
	assert_int(applied.size()).is_equal(1)
	assert_int(applied[0].tick).is_equal(1)
	assert_int(applied[0].command_id).is_equal(1)
	assert_str(String(f.parcel_views(S.ids([1]))[0].pending_zone)).is_equal("zone.mixed")


func test_validate_command_is_a_dry_run() -> void:
	var f := S.facade(S.SCENARIO_POSITIVE)
	var before := S.observable_hash(f)
	var r := f.validate_command(_zoning_one())
	assert_str(String(r.status)).is_equal("valid")
	assert_int(r.command_id).is_equal(SimContract.NO_ID)
	f.advance(1)
	assert_array(S.events_of(f, SimEvent.KIND_COMMAND_APPLIED)).is_empty()
	var g := S.facade(S.SCENARIO_POSITIVE)
	g.advance(1)
	assert_str(S.observable_hash(f)).is_equal(S.observable_hash(g))
	assert_str(before).is_not_empty()
	var bad := f.validate_command(SimCommand.zoning_propose(PackedInt64Array([99]), &"zone.mixed"))
	assert_str(String(bad.reason_key)).is_equal(String(CommandResult.REJECT_INVALID_TARGET))


func test_returned_dtos_are_value_copies() -> void:
	var f := S.facade(S.SCENARIO_POSITIVE)
	f.submit_command(_zoning_one())
	f.advance(5)
	var snap := f.snapshot()
	snap.budget.balance = -1
	snap.group_reactions.clear()
	assert_int(f.snapshot().budget.balance).is_equal(30000)
	var p := f.parcel_views(S.ids([1]))[0]
	p.development = ParcelView.DEVELOPMENT_BUILT
	assert_str(String(f.parcel_views(S.ids([1]))[0].development)).is_equal("planned")
	var r := f.reasons_for(&"parcel.1")[0]
	r.factors.clear()
	assert_int(f.reasons_for(&"parcel.1")[0].factors.size()).is_equal(4)
	var e := f.events_since(0)[0]
	e.kind = &"tampered"
	assert_str(String(f.events_since(0)[0].kind)).is_equal("command.applied")


func test_events_since_cursor_and_max_count() -> void:
	var f := S.facade(S.SCENARIO_POSITIVE)
	f.submit_command(_zoning_one())
	f.advance(12)
	var all := f.events_since(0)
	assert_int(all.size()).is_equal(f.last_event_seq())
	assert_int(all.size()).is_greater_equal(4)
	assert_int(f.events_since(2)[0].seq).is_equal(3)
	assert_int(f.events_since(0, 2).size()).is_equal(2)
	assert_array(f.events_since(f.last_event_seq())).is_empty()
	assert_int(f.first_retained_event_seq()).is_equal(1)


func test_speed_levels_are_limited_to_available_speeds() -> void:
	var f := S.facade(S.SCENARIO_POSITIVE)
	assert_bool(f.available_speeds().has(SimFacade.SPEED_PAUSED)).is_true()
	assert_bool(f.set_speed(SimFacade.SPEED_FAST)).is_true()
	assert_int(f.speed()).is_equal(SimFacade.SPEED_FAST)
	assert_bool(f.set_speed(99)).is_false()
	assert_int(f.speed()).is_equal(SimFacade.SPEED_FAST)
	assert_bool(f.snapshot().clock.is_paused()).is_false()
	f.set_speed(SimFacade.SPEED_PAUSED)
	assert_bool(f.snapshot().clock.is_paused()).is_true()


func test_advance_never_goes_backwards() -> void:
	var f := S.facade(S.SCENARIO_POSITIVE)
	assert_int(f.advance(-3)).is_equal(0)
	assert_int(f.current_tick()).is_equal(0)
	f.advance(4)
	assert_int(f.current_tick()).is_equal(4)
	assert_int(f.snapshot().tick()).is_equal(4)


func test_parcel_queries_filter_by_region_and_skip_unknown_ids() -> void:
	var f := S.facade(S.SCENARIO_POSITIVE)
	assert_array(Array(f.parcel_ids())).is_equal([1, 2, 3])
	assert_array(Array(f.parcel_ids(&"F2"))).is_equal([3])
	assert_array(Array(f.parcel_ids(&"NOPE"))).is_empty()
	var views := f.parcel_views(S.ids([3, 99, 1]))
	assert_int(views.size()).is_equal(2)
	assert_int(views[0].id).is_equal(3)
	assert_int(views[1].id).is_equal(1)


func test_invalid_scenario_yields_empty_but_conformant_facade() -> void:
	var f := MockSimFacade.new(MockScenario.from_dict({"provenance": "SIM"}))
	assert_array(f.load_errors()).is_not_empty()
	assert_int(f.parcel_ids().size()).is_equal(0)
	assert_array(SimContractChecks.check_facade(f)).is_empty()
