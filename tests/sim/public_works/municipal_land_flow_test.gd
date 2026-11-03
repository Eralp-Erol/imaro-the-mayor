extends "res://tests/sim/public_works/municipal_land_test_base.gd"
## D-018 / T-066: gerçek parsellerle tekrar imar; belediye bina/hane üretmez (CAN-03).


class BlockablePort extends NetworkExpropriationPort:
	var blocked_id: int = -1

	func available_land(source_op: int, ids: PackedInt64Array) -> Dictionary:
		if ids.has(blocked_id):
			return {"ok": false, "error": "qa.land_blocked", "parcel_ids": PackedInt64Array()}
		return super.available_land(source_op, ids)


class FailingRestorePort extends NetworkExpropriationPort:
	var fail_source: int = -1
	var successful_restores: int = 0

	func restore_land(source_op: int, ids: PackedInt64Array) -> Dictionary:
		if source_op == fail_source:
			return {"ok": false, "error": "qa.restore_failed", "restored": PackedInt64Array()}
		var result := super.restore_land(source_op, ids)
		if bool(result["ok"]):
			successful_restores += 1
		return result


func test_demolition_and_legacy_zoning_leave_municipal_land_empty() -> void:
	var run := _land_demolished()
	var f := _land_f(run)
	var before_query := f.state_hash()
	var world_before := (run["net"] as WorldNetwork).state_hash()
	var lands := f.municipal_lands()
	assert_str(f.state_hash()).is_equal(before_query)
	assert_str((run["net"] as WorldNetwork).state_hash()).is_equal(world_before)
	assert_int(lands.size()).is_equal((run["taken"] as PackedInt64Array).size())
	for land in lands:
		assert_bool((run["taken"] as PackedInt64Array).has(land.id)).is_true()
		assert_bool(land.available).is_true()
		assert_int(land.source_command_id).is_equal(run["road_command_id"])
	_land_do(run, _land_command(run["taken"], &"zone.green", false))
	f.advance(12)
	_land_assert_taken(run)
	assert_int(PublicWorksState.data(f.game_state())["version"]).is_equal(PublicWorksState.VERSION_EXPROPRIATION)


func test_direct_plan_waits_until_effective_day_then_creates_only_empty_parcels() -> void:
	var run := _land_demolished()
	var f := _land_f(run)
	var original := PublicWorksState.data(f.game_state())
	var history := StateHash.of(original["works"][0]["expropriation"])
	var displaced := StateHash.of(original["displaced"])
	var charged := BudgetState.charged_amount(f.game_state(), int(run["road_command_id"]))
	var latent := _land_latent(run)
	var command := _land_do(run, _land_command(run["taken"]))
	var first := int((run["taken"] as PackedInt64Array)[0])
	var pending := ParcelZoningSystem.overlay_of(f.game_state(), first)
	var due := int(pending["due_tick"])
	assert_int(due).is_greater(f.current_tick())
	_land_assert_taken(run)
	f.advance(due - f.current_tick() - 1)
	_land_assert_taken(run)
	f.advance(1)
	_land_assert_fresh_green(run)
	assert_int(_land_events_for(run, command.command_id, &"event.zoning.applied").size()) \
		.is_equal((run["taken"] as PackedInt64Array).size())
	assert_str(StateHash.of(PublicWorksState.data(f.game_state())["works"][0]["expropriation"])).is_equal(history)
	assert_str(StateHash.of(PublicWorksState.data(f.game_state())["displaced"])).is_equal(displaced)
	assert_int(BudgetState.charged_amount(f.game_state(), int(run["road_command_id"]))).is_equal(charged)
	assert_array(Array(_land_latent(run))).is_equal(Array(latent))
	assert_int(f.public_works().size()).override_failure_message("imar işlemi yeni yol sayılmaz").is_equal(0)


func test_a_standing_road_and_a_second_release_are_rejected_without_mutation() -> void:
	var run := _land_setup()
	var built := _land_do(run, SimCommand.public_work_road(_land_points(), &"local", true))
	var f := _land_f(run)
	for phase in ["road_stands", "already_reused"]:
		if phase == "already_reused":
			_land_do(run, SimCommand.public_work_demolish(built.command_id))
			_land_do(run, _land_command(run["taken"]))
			f.advance(12)
			_land_assert_fresh_green(run)
		var before := f.state_hash()
		var net_before := (run["net"] as WorldNetwork).state_hash()
		var result := f.submit_command(_land_command(run["taken"]))
		assert_bool(result.is_rejected()).override_failure_message(phase).is_true()
		assert_str(f.state_hash()).is_equal(before)
		assert_str((run["net"] as WorldNetwork).state_hash()).is_equal(net_before)


func test_a_pending_plan_can_be_saved_loaded_and_continued_bit_identically() -> void:
	var straight := _land_demolished()
	_land_do(straight, _land_command(straight["taken"]))
	var bytes := _land_f(straight).export_save()
	var loaded := _land_setup()
	var result := _land_f(loaded).import_save(bytes)
	assert_bool(result.ok).override_failure_message(result.message).is_true()
	_land_assert_taken(loaded)
	_land_f(straight).advance(40)
	_land_f(loaded).advance(40)
	_land_assert_fresh_green(loaded)
	assert_str(_land_f(loaded).state_hash()).is_equal(_land_f(straight).state_hash())
	assert_str((loaded["net"] as WorldNetwork).state_hash()).is_equal((straight["net"] as WorldNetwork).state_hash())


func test_pending_municipal_group_cannot_be_split_by_an_ordinary_plan() -> void:
	var run := _land_demolished()
	var f := _land_f(run)
	_land_do(run, _land_command(run["taken"]))
	var before := f.state_hash()
	var world_before := (run["net"] as WorldNetwork).state_hash()
	var one := PackedInt64Array([int((run["taken"] as PackedInt64Array)[0])])
	var result := f.submit_command(_land_command(one, &"zone.mixed", false))
	assert_bool(result.is_rejected()).is_true()
	assert_str(f.state_hash()).is_equal(before)
	assert_str((run["net"] as WorldNetwork).state_hash()).is_equal(world_before)


func test_tampered_pending_group_is_corrupt_and_cannot_mutate_the_live_game() -> void:
	var source := _land_demolished()
	_land_do(source, _land_command(source["taken"]))
	var bytes := _land_f(source).export_save()
	var ids: PackedInt64Array = source["taken"]
	assert_int(ids.size()).is_greater(1)
	var edits: Array[Callable] = [
		func(entry: Dictionary) -> void: entry["due_tick"] = int(entry["due_tick"]) - 1,
		func(entry: Dictionary) -> void: entry["municipal_reuse"] = false,
		func(entry: Dictionary) -> void: entry.erase("municipal_reuse"),
		func(entry: Dictionary) -> void: entry["pending_zone"] = &"zone.mixed",
		func(entry: Dictionary) -> void: entry["command_id"] = int(entry["command_id"]) + 10,
		func(entry: Dictionary) -> void: entry.erase("municipal_group"),
		func(entry: Dictionary) -> void: entry["municipal_group"] = [int(ids[0])],
		func(entry: Dictionary) -> void: (entry["municipal_group"] as Array).append(999999),
	]
	for edit in edits:
		var envelope: Dictionary = bytes_to_var(bytes)
		var body: Dictionary = envelope["state"]
		var entry: Dictionary = body["systems"]["parcels"]["overlay"][int(ids[0])]
		edit.call(entry)
		envelope["state_hash"] = StateHash.of(body)
		var target := _land_setup("direct", LAND_P.SEED + 1)
		_land_do(target, LAND_P.road(LAND_P.spur_b_cm()))
		var before := _land_f(target).state_hash()
		var world_before := (target["net"] as WorldNetwork).state_hash()
		var loaded := _land_f(target).import_save(var_to_bytes(envelope))
		assert_bool(loaded.ok).is_false()
		assert_str(String(loaded.error_code)).is_equal("corrupt")
		assert_str(_land_f(target).state_hash()).is_equal(before)
		assert_str((target["net"] as WorldNetwork).state_hash()).is_equal(world_before)


func test_effective_precheck_rejects_the_whole_group_before_any_parcel_is_restored() -> void:
	var run := _land_demolished()
	var f := _land_f(run)
	var net: WorldNetwork = run["net"]
	var ctx: PublicWorksContext = run["ctx"]
	var rules := RoadDraftRules.from_control({"player_roads": {"crossing_parcels": "expropriate"}})
	var port := BlockablePort.new(net, rules)
	ctx.set_expropriation(port)
	var command := _land_do(run, _land_command(run["taken"]))
	var before := net.state_hash()
	port.blocked_id = int((run["taken"] as PackedInt64Array)[-1])
	f.advance(12)
	_land_assert_taken(run)
	assert_str(net.state_hash()).is_equal(before)
	assert_int(_land_events_for(run, command.command_id, &"event.zoning.applied").size()).is_equal(0)
	assert_int(_land_events_for(run, command.command_id, &"event.zoning.plan_rejected").size()).is_greater(0)
	assert_int(PublicWorksState.data(f.game_state())["version"]).is_equal(PublicWorksState.VERSION_EXPROPRIATION)


func test_second_source_restore_failure_rolls_back_the_first_world_restore() -> void:
	var run := _land_demolished()
	var f := _land_f(run)
	var net: WorldNetwork = run["net"]
	var second_points := PackedInt64Array([174000, 110000, 190000, 120000])
	var second_ids := RoadDraftCheck.taken_parcels(net, RoadDraftCheck.points_from_cm(second_points), &"local")
	assert_int(second_ids.size()).is_greater(0)
	var second_source := net.delta.ops.size()
	var second_road := _land_do(run, SimCommand.public_work_road(second_points, &"local", true))
	_land_do(run, SimCommand.public_work_demolish(second_road.command_id))
	var all: PackedInt64Array = (run["taken"] as PackedInt64Array).duplicate()
	all.append_array(second_ids)
	all.sort()
	run["taken"] = all
	var ctx: PublicWorksContext = run["ctx"]
	var rules := RoadDraftRules.from_control({"player_roads": {"crossing_parcels": "expropriate"}})
	var port := FailingRestorePort.new(net, rules)
	port.fail_source = second_source
	ctx.set_expropriation(port)
	var command := _land_do(run, _land_command(all))
	var before := net.state_hash()
	var ops_before := net.delta.ops.size()
	f.advance(12)
	assert_int(port.successful_restores).is_greater(0)
	_land_assert_taken(run)
	assert_str(net.state_hash()).is_equal(before)
	assert_int(net.delta.ops.size()).is_equal(ops_before)
	assert_int(_land_events_for(run, command.command_id, &"event.zoning.applied").size()).is_equal(0)
	assert_int(_land_events_for(run, command.command_id, &"event.zoning.plan_rejected").size()).is_greater(0)
	assert_bool(ctx.tracks(f.game_state())).is_true()


func test_reopened_land_can_be_expropriated_again_and_replays_in_chronological_order() -> void:
	var run := _land_demolished()
	var f := _land_f(run)
	_land_do(run, _land_command(run["taken"]))
	f.advance(12)
	_land_assert_fresh_green(run)
	_land_do(run, SimCommand.public_work_road(_land_points(), &"local", true))
	_land_assert_taken(run)
	var saved := f.export_save()
	var fresh := _land_setup()
	var result := _land_f(fresh).import_save(saved)
	assert_bool(result.ok).override_failure_message(result.message).is_true()
	assert_str(_land_f(fresh).state_hash()).is_equal(f.state_hash())
	assert_str((fresh["net"] as WorldNetwork).state_hash()).is_equal((run["net"] as WorldNetwork).state_hash())
	_land_assert_taken(fresh)
