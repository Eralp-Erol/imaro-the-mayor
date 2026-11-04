extends "res://tests/sim/public_works/municipal_land_test_base.gd"
## T-066 / CAN-03: belediye toprağı da mevcut imar/meclis yolundan geçer; teklif ve oy bina üretmez.


func test_a_pending_council_vote_keeps_every_municipal_parcel_taken() -> void:
	var run := _land_demolished("pass")
	var f := _land_f(run)
	var result := _land_do(run, _land_command(run["taken"]))
	var first := int((run["taken"] as PackedInt64Array)[0])
	var vote_id := CouncilEngine.pending_vote_for_parcel(f.game_state(), first)
	assert_int(vote_id).is_greater(0)
	var vote := CouncilEngine.vote_by_id(f.game_state(), vote_id)
	assert_int(int(vote["proposal"]["command_id"])).is_equal(result.command_id)
	assert_bool(bool(vote["proposal"].get("municipal_reuse", false))).is_true()
	_land_assert_taken(run)
	f.advance(2)
	assert_int(CouncilEngine.pending_vote_for_parcel(f.game_state(), first)).is_equal(vote_id)
	_land_assert_taken(run)


func test_a_failed_vote_never_returns_the_world_parcels_or_the_old_buildings() -> void:
	var run := _land_demolished("fail")
	var f := _land_f(run)
	var world_before := (run["net"] as WorldNetwork).state_hash()
	var taken_before := PublicWorksState.taken_count(f.game_state())
	var command := _land_do(run, _land_command(run["taken"]))
	f.advance(40)
	_land_assert_taken(run)
	assert_str((run["net"] as WorldNetwork).state_hash()).is_equal(world_before)
	assert_int(PublicWorksState.taken_count(f.game_state())).is_equal(taken_before)
	assert_int(_land_events_for(run, command.command_id, &"event.zoning.applied").size()).is_equal(0)
	assert_int(_land_events_for(run, command.command_id, &"event.zoning.plan_rejected").size()).is_greater(0)


func test_a_passed_vote_preserves_the_delay_and_only_then_opens_empty_parcels() -> void:
	var run := _land_demolished("pass")
	var f := _land_f(run)
	var command := _land_do(run, _land_command(run["taken"]))
	var first := int((run["taken"] as PackedInt64Array)[0])
	var pending := ParcelZoningSystem.overlay_of(f.game_state(), first)
	for _day in 40:
		if pending.has("due_tick") and int(pending["due_tick"]) > f.current_tick():
			break
		_land_assert_taken(run)
		f.advance(1)
		pending = ParcelZoningSystem.overlay_of(f.game_state(), first)
	assert_bool(pending.has("due_tick")).is_true()
	var due := int(pending.get("due_tick", -1))
	assert_int(due).is_greater(f.current_tick())
	f.advance(due - f.current_tick() - 1)
	_land_assert_taken(run)
	f.advance(1)
	_land_assert_fresh_green(run)
	assert_int(_land_events_for(run, command.command_id, &"event.zoning.applied").size()) \
		.is_equal((run["taken"] as PackedInt64Array).size())
