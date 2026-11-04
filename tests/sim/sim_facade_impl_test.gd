# gdlint:disable=max-public-methods
extends SimTestBase
## T-027 ölçüt 2-3, 7 · SimFacadeImpl: gerçek sim ADR-0005 yüzeyini sözleşmeye uygun sunar; CAN-03 beyaz liste,
## gerekçeli ret, kurulmamış sistemler `available=false`, değer kopyası, okuma yan etkisiz.

const A1 := &"actor.investor.1"
const A2 := &"actor.group.2"


func _facade(per_region: int = 3) -> SimFacadeImpl:
	return FacadeTestSupport.facade(per_region)


func _zoning(ids: Array, land_use: StringName = &"zone.mixed") -> SimCommand:
	return SimCommand.zoning_propose(PackedInt64Array(ids), land_use)


func _delay() -> int:
	return FacadeConfig.load_default().apply_delay_days


func _events_of(f: SimFacade, kind: StringName) -> Array[SimEvent]:
	var out: Array[SimEvent] = []
	for e in f.events_since(0):
		if e.kind == kind:
			out.append(e)
	return out


# --- Kimlik ve uyum ---

func test_facade_is_a_sim_facade_with_sim_provenance() -> void:
	var f := _facade()
	assert_object(f).is_instanceof(SimFacade)
	assert_str(String(f.provenance())).is_equal("sim")
	assert_bool(f.is_mock()).is_false()
	assert_str(f.contract_version()).is_equal(SimContract.VERSION)
	assert_bool(f.snapshot().is_mock()).is_false()


func test_contract_checks_are_clean_fresh_and_after_activity() -> void:
	var f := _facade()
	assert_array(SimContractChecks.check_facade(f)).is_empty()
	f.submit_command(_zoning([1, 2]))
	f.advance(_delay() + 2)
	f.submit_command(_zoning([3], &"zone.green"))
	f.advance(1)
	assert_array(SimContractChecks.check_facade(f)).is_empty()
	assert_bool(f.last_event_seq() > 0).is_true()


func test_contract_checks_catch_a_broken_facade() -> void:
	# Olumsuz: kontrol gerçekten ihlal yakalar (sahte yeşil değil).
	var f := _facade()
	f.game_state().record_reason(A1, &"decision.investor.develop", [{"name": &"x", "value": 1000}], 500)
	SimEventLog.emit(f.game_state(), &"actor.decided", &"event.x", PackedStringArray(), {}, PackedInt64Array([77]))
	assert_array(SimContractChecks.check_facade(f)).override_failure_message("kayıp gerekçe yakalanmalı").is_not_empty()


func test_unbuilt_sections_report_available_false_with_empty_dtos() -> void:
	var s := _facade().snapshot()
	assert_bool(s.extensions["x.sim.available.parcels"]).is_true()
	for section in ["budget", "council", "groups"]:
		assert_bool(s.extensions["x.sim.available." + section]) \
			.override_failure_message("%s kurulu görünüyor" % section).is_false()
	assert_array(s.group_reactions).is_empty()
	assert_array(s.council.blocs).is_empty()
	assert_array(s.council.votes).is_empty()
	assert_array(s.budget.lines).is_empty()
	assert_str(String(s.budget.status)).is_equal(String(BudgetView.STATUS_DRAFT))
	assert_object(s.council.council).is_null()


# --- Saat ve hız ---

func test_speed_levels_map_to_driver_speeds_and_set_speed_validates() -> void:
	var f := _facade()
	assert_array(Array(f.available_speeds())).is_equal([0, 1, 2, 3])
	assert_int(f.speed()).is_equal(SimFacade.SPEED_NORMAL)
	assert_bool(f.set_speed(SimFacade.SPEED_FAST)).is_true()
	assert_int(f.speed()).is_equal(SimFacade.SPEED_FAST)
	assert_bool(f.set_speed(9)).is_false()
	assert_bool(f.set_speed(-1)).is_false()
	assert_int(f.speed()).override_failure_message("geçersiz seviye hızı değiştirmemeli").is_equal(2)
	assert_int(f.snapshot().clock.speed).is_equal(2)


func test_driver_ticks_follow_speed_table_and_pause_stops_time() -> void:
	var f := _facade()
	var table: Dictionary = new_config().driver["speeds"]
	assert_int(f.drive_usec(2_000_000)).is_equal(2 * int(table["normal"]))
	f.set_speed(SimFacade.SPEED_FAST)
	var before := f.current_tick()
	assert_int(f.drive_usec(1_000_000)).is_equal(int(table["fast"]))
	assert_int(f.current_tick()).is_equal(before + int(table["fast"]))
	f.set_speed(SimFacade.SPEED_PAUSED)
	assert_int(f.drive_usec(9_000_000)).is_equal(0)
	assert_int(f.current_tick()).is_equal(before + int(table["fast"]))


func test_platform_speed_cap_closes_levels_and_clamps_current() -> void:
	var f := _facade()
	f.set_speed(SimFacade.SPEED_FASTEST)
	f.set_max_speed_level(SimFacade.SPEED_NORMAL)
	assert_array(Array(f.available_speeds())).is_equal([0, 1])
	assert_int(f.speed()).is_equal(SimFacade.SPEED_NORMAL)
	assert_bool(f.set_speed(SimFacade.SPEED_FAST)).is_false()
	assert_array(SimContractChecks.check_facade(f)).is_empty()


func test_speed_is_not_sim_state() -> void:
	var f := _facade()
	var h := f.state_hash()
	for level in [0, 2, 3, 1]:
		f.set_speed(level)
	f.set_max_speed_level(1)
	assert_str(f.state_hash()).override_failure_message("hız hash'e girmemeli").is_equal(h)


func test_advance_returns_ticks_and_ignores_negative() -> void:
	var f := _facade()
	assert_int(f.advance(5)).is_equal(5)
	assert_int(f.current_tick()).is_equal(5)
	assert_int(f.advance(-3)).is_equal(0)
	assert_int(f.current_tick()).is_equal(5)
	assert_int(f.snapshot().clock.tick).is_equal(5)


# --- Parseller ---

func test_parcel_ids_and_views_follow_the_source() -> void:
	var f := _facade(3)
	var src := FacadeTestSupport.fixture_source(3)
	assert_array(Array(f.parcel_ids())).is_equal(Array(src.parcel_ids()))
	assert_int(f.snapshot().parcel_count).is_equal(src.parcel_count())
	var region_code: StringName = src.template(src.parcel_ids()[0]).region_code
	assert_array(Array(f.parcel_ids(region_code))).is_equal(Array(src.parcel_ids(region_code)))
	var ids := PackedInt64Array([src.parcel_ids()[2], 99999, src.parcel_ids()[0]])
	var views := f.parcel_views(ids)
	assert_int(views.size()).override_failure_message("bilinmeyen kimlik atlanır").is_equal(2)
	assert_int(views[0].id).is_equal(ids[0])
	assert_int(views[1].id).is_equal(ids[2])
	assert_str(String(views[0].provenance)).is_equal("sim")
	assert_str(String(views[0].zone)).is_equal(String(FacadeTestSupport.ZONE))
	assert_str(String(views[0].pending_zone)).is_empty()
	assert_str(String(views[0].development)).is_equal(String(ParcelView.DEVELOPMENT_VACANT))
	assert_array(Array(views[0].reason_ids)).is_empty()
	assert_vector(views[0].center).is_equal(src.template(ids[0]).center)


func test_empty_parcel_source_works() -> void:
	var src := ListParcelSource.create(&"empty.world", [])
	var f := SimFacadeImpl.create(1, src)
	assert_array(Array(f.parcel_ids())).is_empty()
	assert_int(f.snapshot().parcel_count).is_equal(0)
	assert_array(SimContractChecks.check_facade(f)).is_empty()


func test_invalid_setup_returns_null_with_error() -> void:
	var result: Array = [RefCounted.new()]
	await assert_error(func() -> void: result[0] = SimFacadeImpl.create(1, null)) \
		.is_push_error("SimFacadeImpl: parsel kaynağı yok")
	assert_object(result[0]).is_null()
	var bad := ListParcelSource.create(&"", [])
	result[0] = RefCounted.new()
	await assert_error(func() -> void: result[0] = SimFacadeImpl.create(1, bad)) \
		.is_push_error("SimFacadeImpl: parsel kaynağı geçersiz: world_id boş")
	assert_object(result[0]).is_null()


# --- Komutlar: yaşam döngüsü ---

func test_zoning_proposal_is_queued_applied_then_takes_effect_after_delay() -> void:
	var f := _facade()
	var result := f.submit_command(_zoning([1]))
	assert_str(String(result.status)).is_equal("queued")
	assert_int(result.command_id).is_equal(1)
	assert_int(result.apply_tick).is_equal(f.current_tick() + 1)
	assert_str(String(result.provenance)).is_equal("sim")
	assert_array(_events_of(f, SimEvent.KIND_COMMAND_APPLIED)).override_failure_message("tick sınırı gelmedi").is_empty()
	assert_str(String(f.parcel_views(PackedInt64Array([1]))[0].pending_zone)).is_empty()

	f.advance(1)
	var applied := _events_of(f, SimEvent.KIND_COMMAND_APPLIED)
	assert_int(applied.size()).is_equal(1)
	assert_int(applied[0].command_id).is_equal(1)
	assert_array(Array(applied[0].subjects)).is_equal(["parcel.1", "command.1"])
	var pending := f.parcel_views(PackedInt64Array([1]))[0]
	assert_str(String(pending.pending_zone)).is_equal("zone.mixed")
	assert_str(String(pending.zone)).override_failure_message("imar henüz yürürlükte değil") \
		.is_equal(String(FacadeTestSupport.ZONE))

	f.advance(_delay() - 2)
	assert_str(String(f.parcel_views(PackedInt64Array([1]))[0].zone)).is_equal(String(FacadeTestSupport.ZONE))
	f.advance(1)
	var done := f.parcel_views(PackedInt64Array([1]))[0]
	assert_str(String(done.zone)).is_equal("zone.mixed")
	assert_str(String(done.pending_zone)).is_empty()
	var changed := _events_of(f, SimEvent.KIND_PARCEL_CHANGED)
	assert_int(changed.size()).is_equal(1)
	assert_str(String(changed[0].message_key)).is_equal("event.zoning.applied")
	assert_int(changed[0].command_id).is_equal(1)
	assert_array(Array(changed[0].subjects)).is_equal(["parcel.1"])
	assert_str(String(changed[0].args["zone"])).is_equal("zone.mixed")
	assert_array(SimContractChecks.check_facade(f)).is_empty()


func test_other_parcels_are_untouched_by_a_zoning_proposal() -> void:
	var f := _facade()
	var before := f.parcel_views(PackedInt64Array([2, 3]))
	f.submit_command(_zoning([1]))
	f.advance(_delay() + 1)
	var after := f.parcel_views(PackedInt64Array([2, 3]))
	for i in before.size():
		assert_bool(before[i].same_as(after[i])).is_true()


func test_command_ids_increase_and_rejections_consume_none() -> void:
	var f := _facade()
	assert_int(f.submit_command(_zoning([1])).command_id).is_equal(1)
	assert_int(f.submit_command(_zoning([99999])).command_id).is_equal(0)
	assert_int(f.submit_command(SimCommand.make(&"building.place")).command_id).is_equal(0)
	assert_int(f.submit_command(_zoning([2])).command_id).is_equal(2)


func test_rejected_commands_carry_contract_reason_keys_and_change_nothing() -> void:
	var f := _facade()
	var h := f.state_hash()
	var cases := [
		[SimCommand.make(&"building.place", {"parcel_ids": PackedInt64Array([1])}), CommandResult.REJECT_NOT_A_MAYOR_VERB],
		[SimCommand.make(&"private.invest"), CommandResult.REJECT_NOT_A_MAYOR_VERB],
		[SimCommand.make(&"spawn.house"), CommandResult.REJECT_NOT_A_MAYOR_VERB],
		[SimCommand.make(&"zoning.teleport"), CommandResult.REJECT_UNKNOWN_KIND],
		[SimCommand.make(&"zoning.propose", {"land_use": &"zone.mixed"}), CommandResult.REJECT_MISSING_PARAM],
		[SimCommand.make(&"zoning.propose", {"parcel_ids": PackedInt64Array([1]), "land_use": &"zone.mixed",
			"surprise": 1}), CommandResult.REJECT_UNKNOWN_PARAM],
		[SimCommand.make(&"zoning.propose", {"parcel_ids": [1], "land_use": &"zone.mixed"}),
			CommandResult.REJECT_BAD_PARAM_TYPE],
		[_zoning([]), CommandResult.REJECT_INVALID_VALUE],
		[_zoning([1], &"zone.casino"), CommandResult.REJECT_INVALID_VALUE],
		[_zoning([1, 99999]), CommandResult.REJECT_INVALID_TARGET],
		[SimCommand.budget_propose({&"budget.line.roads": 5}), CommandResult.REJECT_PRECONDITION],
		[null, CommandResult.REJECT_UNKNOWN_KIND],
	]
	for c: Array in cases:
		var r := f.submit_command(c[0])
		assert_str(String(r.status)).is_equal("rejected")
		assert_str(String(r.reason_key)).override_failure_message("durum: %s" % [c]).is_equal(String(c[1]))
		assert_int(r.command_id).is_equal(0)
		assert_str(String(r.provenance)).is_equal("sim")
	assert_str(f.state_hash()).override_failure_message("reddedilen komut durumu değiştirmemeli").is_equal(h)
	f.advance(3)
	assert_array(f.events_since(0).filter(func(e: SimEvent) -> bool: return e.kind == SimEvent.KIND_COMMAND_APPLIED)) \
		.is_empty()


func test_reject_arguments_name_the_offending_target_or_unbuilt_system() -> void:
	var f := _facade()
	var bad_target := f.submit_command(_zoning([1, 99999]))
	assert_dict(bad_target.args).is_equal({"ref": "parcel.99999"})
	var bad_use := f.submit_command(_zoning([1], &"zone.casino"))
	assert_dict(bad_use.args).is_equal({"param": "land_use"})
	var budget := f.submit_command(SimCommand.budget_propose({&"budget.line.roads": 5}))
	assert_dict(budget.args).is_equal({"why": "system.not_built", "system": "budget"})
	var missing := f.submit_command(SimCommand.make(&"zoning.propose", {"land_use": &"zone.mixed"}))
	assert_dict(missing.args).is_equal({"param": "parcel_ids"})


func test_validate_command_is_a_dry_run_matching_submit() -> void:
	var f := _facade()
	var h := f.state_hash()
	var ok := f.validate_command(_zoning([1]))
	assert_str(String(ok.status)).is_equal("valid")
	assert_int(ok.command_id).is_equal(0)
	assert_str(f.state_hash()).override_failure_message("kuru koşu durumu değiştirmemeli").is_equal(h)
	assert_int(f.submit_command(_zoning([1])).command_id).override_failure_message("kuru koşu kimlik tüketmemeli") \
		.is_equal(1)
	for c: SimCommand in [_zoning([99999]), SimCommand.make(&"building.place"), SimCommand.budget_propose({&"b": 1})]:
		var dry := f.validate_command(c)
		var real := f.submit_command(c)
		assert_str(String(dry.status)).is_equal("rejected")
		assert_str(String(dry.reason_key)).is_equal(String(real.reason_key))
		assert_dict(dry.args).is_equal(real.args)


func test_submitted_command_is_copied_from_the_caller() -> void:
	var f := _facade()
	var c := _zoning([1])
	f.submit_command(c)
	c.params["land_use"] = &"zone.green"
	(c.params["parcel_ids"] as PackedInt64Array).append(2)
	f.advance(_delay() + 1)
	assert_str(String(f.parcel_views(PackedInt64Array([1]))[0].zone)).is_equal("zone.mixed")
	assert_str(String(f.parcel_views(PackedInt64Array([2]))[0].zone)).is_equal(String(FacadeTestSupport.ZONE))


func test_optional_density_and_height_are_validated_and_stored() -> void:
	var f := _facade()
	var c := SimCommand.make(&"zoning.propose", {"parcel_ids": PackedInt64Array([1]), "land_use": &"zone.mixed",
		"density": 400, "max_height_m": 18})
	assert_str(String(f.submit_command(c).status)).is_equal("queued")
	f.advance(1)
	var overlay := ParcelZoningSystem.overlay_of(f.game_state(), 1)
	assert_int(overlay["pending_density"]).is_equal(400)
	assert_int(overlay["pending_max_height_m"]).is_equal(18)
	var negative := SimCommand.make(&"zoning.propose", {"parcel_ids": PackedInt64Array([1]), "land_use": &"zone.mixed",
		"density": -1})
	assert_str(String(f.submit_command(negative).reason_key)).is_equal(String(CommandResult.REJECT_INVALID_VALUE))


func test_direct_sim_level_malformed_command_is_still_rejected_with_reason() -> void:
	# Facade'ı atlayıp Commands.submit ile gelen biçimsiz komut da gerekçeli reddedilir (savunma derinliği).
	var f := _facade()
	Commands.submit(f.game_state(), &"zoning.propose", {"land_use": "zone.mixed"})
	Commands.submit(f.game_state(), &"building.place", {})
	f.advance(1)
	var rejected := _events_of(f, SimEvent.KIND_COMMAND_REJECTED)
	assert_int(rejected.size()).is_equal(2)
	assert_str(String(rejected[0].message_key)).is_equal(String(CommandResult.REJECT_MISSING_PARAM))
	assert_str(String(rejected[1].message_key)).is_equal(String(CommandResult.REJECT_UNKNOWN_KIND))
	assert_array(SimContractChecks.check_facade(f)).is_empty()


# --- CAN-03 ---

func test_municipal_commands_never_create_private_development() -> void:
	var f := _facade(4)
	var all_ids := f.parcel_ids()
	for use in FacadeConfig.load_default().land_uses:
		f.submit_command(SimCommand.zoning_propose(all_ids, use))
		f.advance(_delay() + 2)
	for p in f.parcel_views(all_ids):
		assert_str(String(p.development)).override_failure_message("CAN-03: parsel %d" % p.id) \
			.is_equal(String(ParcelView.DEVELOPMENT_VACANT))
		assert_object(p.owner).is_null()
	for e in f.events_since(0):
		assert_bool([SimEvent.KIND_COMMAND_APPLIED, SimEvent.KIND_PARCEL_CHANGED].has(e.kind)) \
			.override_failure_message("beklenmeyen olay %s" % e.kind).is_true()
	var allowed: Array = ["events", "parcels", "world"]
	for key: String in f.game_state().systems:
		assert_bool(allowed.has(key)).override_failure_message("beklenmeyen sistem verisi: %s" % key).is_true()
	assert_array(SimContractChecks.check_facade(f)).is_empty()


func test_every_parcel_changed_event_follows_an_applied_command() -> void:
	var f := _facade()
	f.advance(10)
	assert_array(_events_of(f, SimEvent.KIND_PARCEL_CHANGED)).override_failure_message("komutsuz değişim yok").is_empty()
	f.submit_command(_zoning([1, 2]))
	f.advance(_delay() + 1)
	for e in _events_of(f, SimEvent.KIND_PARCEL_CHANGED):
		var applied := _events_of(f, SimEvent.KIND_COMMAND_APPLIED).filter(
			func(a: SimEvent) -> bool: return a.command_id == e.command_id)
		assert_int(applied.size()).is_equal(1)
		assert_bool(applied[0].seq < e.seq).is_true()


# --- Olaylar ---

func test_events_are_gapless_pageable_and_report_retention() -> void:
	var f := _facade()
	assert_int(f.last_event_seq()).is_equal(0)
	assert_int(f.first_retained_event_seq()).is_equal(1)
	f.submit_command(_zoning([1, 2]))
	f.submit_command(_zoning([3]))
	f.advance(_delay() + 1)
	var all := f.events_since(0)
	assert_int(all.size()).is_equal(f.last_event_seq())
	for i in all.size():
		assert_int(all[i].seq).is_equal(i + 1)
	assert_int(f.events_since(all.size()).size()).is_equal(0)
	var page := f.events_since(1, 2)
	assert_int(page.size()).is_equal(2)
	assert_int(page[0].seq).is_equal(2)
	assert_int(f.events_since(-4).size()).is_equal(all.size())


func test_event_retention_follows_capacity() -> void:
	var cfg := new_config()
	cfg.sim["event_log_capacity"] = 3
	var f := SimFacadeImpl.create(1, FacadeTestSupport.fixture_source(3), cfg)
	for i in 6:
		f.submit_command(_zoning([1 + i % 3]))
		f.advance(1)
	var last := f.last_event_seq()
	assert_int(last).is_greater(3)  # saklama sınırı aşıldı (komut + yürürlük olayları)
	assert_int(f.first_retained_event_seq()).is_equal(last - 2)
	assert_int(f.events_since(0).size()).is_equal(3)
	assert_int(f.events_since(0)[0].seq).is_equal(last - 2)
	assert_array(SimContractChecks.check_facade(f)).is_empty()


# --- Gerekçeler ---

func test_recorded_reasons_surface_as_consistent_contract_records() -> void:
	var f := _facade()
	var st := f.game_state()
	st.tick = 4
	var first := st.record_reason(A1, &"decision.investor.develop", [
		{"name": &"reason.factor.demand", "value": 800, "weight": 500},
		{"name": &"reason.factor.construction_cost", "value": -300, "weight": 1000, "is_estimate": true,
			"source_ref": &"parcel.1"},
	], 100, &"code_x", PackedStringArray(["parcel.1"]))
	var second := st.record_reason(A2, &"decision.group.protest", [{"name": &"reason.factor.traffic_noise",
		"value": 600}], 900, &"", PackedStringArray(["parcel.1", "command.1"]), PackedInt64Array([first]))
	assert_int(first).is_equal(1)
	var r := f.reason(first)
	assert_object(r).is_not_null()
	assert_bool(r.is_consistent()).override_failure_message(r.consistency_error()).is_true()
	assert_int(r.id).is_equal(1)
	assert_int(r.tick).is_equal(4)
	assert_str(String(r.actor.ref())).is_equal("actor.investor.1")
	assert_str(String(r.actor.name_key)).is_equal("actor.investor.1.name")
	assert_str(String(r.decision_key)).is_equal("decision.investor.develop")
	assert_str(String(r.outcome)).is_equal("positive")
	assert_int(r.score).is_equal(400 + -300)
	assert_int(r.threshold).is_equal(100)
	assert_int(r.factors.size()).is_equal(2)
	assert_str(String(r.factors[1].name_key)).is_equal("reason.factor.construction_cost")
	assert_bool(r.factors[1].is_estimate).is_true()
	assert_str(String(r.factors[1].source_ref)).is_equal("parcel.1")
	assert_str(String(r.provenance)).is_equal("sim")
	var neg := f.reason(second)
	assert_str(String(neg.outcome)).is_equal("negative")
	assert_array(Array(neg.parent_ids)).is_equal([first])
	assert_array(Array(neg.subjects)).is_equal(["parcel.1", "command.1"])
	assert_object(f.reason(0)).is_null()
	assert_object(f.reason(99)).is_null()
	assert_array(f.reasons_for(&"parcel.1").map(func(x: ReasonRecord) -> int: return x.id)).is_equal([1, 2])
	assert_array(f.reasons_for(&"command.1").map(func(x: ReasonRecord) -> int: return x.id)).is_equal([2])
	assert_array(f.reasons_for(&"actor.investor.1").map(func(x: ReasonRecord) -> int: return x.id)).is_equal([1])
	assert_array(f.reasons_for(&"parcel.77")).is_empty()
	assert_array(Array(f.parcel_views(PackedInt64Array([1]))[0].reason_ids)).is_equal([1, 2])
	assert_array(Array(f.parcel_views(PackedInt64Array([2]))[0].reason_ids)).is_empty()
	assert_array(SimContractChecks.check_facade(f)).is_empty()


func test_parcel_reason_ids_are_limited_to_the_newest() -> void:
	var f := _facade()
	var limit := FacadeConfig.load_default().parcel_reason_limit
	for i in limit + 3:
		f.game_state().record_reason(A1, &"decision.investor.develop", [], 0, &"", PackedStringArray(["parcel.1"]))
	var ids: Array = Array(f.parcel_views(PackedInt64Array([1]))[0].reason_ids)
	assert_int(ids.size()).is_equal(limit)
	assert_int(ids[ids.size() - 1]).is_equal(limit + 3)
	assert_int(ids[0]).is_equal(4)


func test_events_with_reasons_and_pruned_reason_chains_stay_resolvable() -> void:
	var cfg := new_config()
	cfg.sim["reason_log_capacity"] = 3
	cfg.sim["event_log_capacity"] = 3
	var f := SimFacadeImpl.create(1, FacadeTestSupport.fixture_source(3), cfg)
	var st := f.game_state()
	var ids: Array[int] = []
	for i in 5:
		var parents := PackedInt64Array([ids[i - 1]]) if i > 0 else PackedInt64Array()
		ids.append(st.record_reason(A1, &"decision.investor.develop", [], 0, &"",
			PackedStringArray(["parcel.1"]), parents))
		SimEventLog.emit(st, &"actor.decided", &"event.investor.develop", PackedStringArray(["parcel.1"]), {},
			PackedInt64Array([ids[i]]), 0, A1)
	# Gerekçe 1-2 budandı (kapasite 3), olay kapasitesi 3: olaylar 3..5 saklı, hepsinin gerekçesi çözülür.
	assert_object(f.reason(1)).is_null()
	assert_object(f.reason(3)).is_not_null()
	var oldest := f.reason(3)
	assert_array(Array(oldest.parent_ids)).override_failure_message("budanmış ebeveyn elenir").is_empty()
	assert_array(SimContractChecks.check_facade(f)).is_empty()


func test_event_retention_horizon_never_exceeds_reason_horizon() -> void:
	# Olay kapasitesi gerekçe kapasitesine eşit ama her olay eski bir gerekçeyi gösterirse: budanmış gerekçeye işaret
	# eden olay saklanmış sayılmaz (ADR-0005 §5).
	var cfg := new_config()
	cfg.sim["reason_log_capacity"] = 2
	cfg.sim["event_log_capacity"] = 2
	var f := SimFacadeImpl.create(1, FacadeTestSupport.fixture_source(3), cfg)
	var st := f.game_state()
	var first := st.record_reason(A1, &"decision.investor.develop", [], 0)
	SimEventLog.emit(st, &"actor.decided", &"event.a", PackedStringArray(), {}, PackedInt64Array([first]))  # seq 1
	st.record_reason(A1, &"decision.investor.develop", [], 0)
	st.record_reason(A1, &"decision.investor.develop", [], 0)  # 1 budandı
	SimEventLog.emit(st, &"actor.decided", &"event.b", PackedStringArray(), {}, PackedInt64Array([3]))  # seq 2
	assert_object(f.reason(first)).is_null()
	assert_int(f.first_retained_event_seq()).override_failure_message("seq 1 budanmış gerekçeyi gösteriyor").is_equal(2)
	var events := f.events_since(0)
	assert_int(events.size()).is_equal(1)
	assert_int(events[0].seq).is_equal(2)
	assert_array(SimContractChecks.check_facade(f)).is_empty()


# --- Değer kopyası ve yan etkisiz okuma ---

func test_reads_do_not_change_sim_state() -> void:
	var f := _facade()
	f.submit_command(_zoning([1]))
	f.advance(2)
	f.game_state().record_reason(A1, &"decision.investor.develop", [], 0, &"", PackedStringArray(["parcel.1"]))
	var h := f.state_hash()
	f.snapshot()
	f.parcel_ids()
	f.parcel_views(f.parcel_ids())
	f.events_since(0)
	f.first_retained_event_seq()
	f.reasons_for(&"parcel.1")
	f.reason(1)
	f.validate_command(_zoning([1]))
	SimContractChecks.check_facade(f)
	SimContractChecks.observable_state(f)
	assert_str(f.state_hash()).is_equal(h)


func test_returned_dtos_are_copies_ui_cannot_mutate_sim() -> void:
	var f := _facade()
	f.submit_command(_zoning([1]))
	f.advance(2)
	f.game_state().record_reason(A1, &"decision.investor.develop", [{"name": &"reason.factor.demand", "value": 5}], 0,
		&"", PackedStringArray(["parcel.1"]))
	var before := SimContractChecks.observable_state(f)
	var h := f.state_hash()
	var snap := f.snapshot()
	snap.clock.tick = 9999
	snap.extensions["x.sim.available.budget"] = true
	snap.group_reactions.append(GroupReactionView.new())
	var views := f.parcel_views(f.parcel_ids())
	views[0].zone = &"zone.hacked"
	views[0].area_m2 = -1
	views[0].reason_ids.append(555)
	var events := f.events_since(0)
	events[0].message_key = &"hacked"
	events[0].subjects.append("parcel.9")
	var reasons := f.reasons_for(&"parcel.1")
	reasons[0].factors[0].value = 999999
	reasons[0].subjects.append("parcel.9")
	reasons[0].outcome = &"negative"
	var single := f.reason(1)
	single.threshold = 123456
	assert_str(f.state_hash()).is_equal(h)
	assert_dict(SimContractChecks.observable_state(f)).is_equal(before)
