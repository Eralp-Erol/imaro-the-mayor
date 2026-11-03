extends GdUnitTestSuite
## T-066 / D-018; TEK-01/02/03, CAN-03: arşiv geometri geri gelir, eski sahip/bina geri getirilmez.

const THROUGH: Array = [Vector2(580, 500), Vector2(580, 600)]
const SPUR: Array = [Vector2(580, 500), Vector2(580, 560)]


func _grid(local: bool = true) -> WorldNetwork:
	var world := NetworkTestSupport.flat_world(3000.0)
	var net := NetworkTestSupport.grid_network(world, 3, 3, 160.0, 100.0, Vector2(500, 500), 7,
		NetworkTestSupport.KEEP_PARCELS)
	net.local_refresh_enabled = local
	for id: int in net.parcels:
		(net.parcels[id] as WorldParcel).owner_id = id * 3 + 1
	return net


func _demolished(points: Array = THROUGH, local: bool = true) -> Dictionary:
	var net := _grid(local)
	var base := net.state_hash()
	var drawn := net.add_road_expropriating(PackedVector2Array(points), &"local")
	assert_bool(drawn["ok"]).is_true()
	var ids := PackedInt64Array(drawn["removed_parcels"])
	ids.sort()
	assert_int(ids.size()).is_greater(0)
	var archives := {}
	var journal: NetworkOpJournal = net._undo_stack[0]
	for collection in [journal.parcels_removed, journal.parcels_retired]:
		for parcel: WorldParcel in collection:
			if ids.has(parcel.id):
				archives[parcel.id] = parcel
	var run := DemolitionPlan.run(net, net.peek_last_op(), true)
	assert_bool(run["ok"]).is_true()
	return {"net": net, "ids": ids, "archives": archives, "base": base}


func test_restoring_is_a_blank_clone_and_undo_is_bit_equal_without_graph_invalidation() -> void:
	for points: Array in [THROUGH, SPUR]:
		for local in [false, true]:
			var fixture := _demolished(points, local)
			var net: WorldNetwork = fixture["net"]
			var before := net.state_hash()
			var graph := net.graph_hash()
			var version := net.graph_version
			var counter: int = NetworkRestore.counters(net)["parcel"]
			var restored := net.restore_parcels(0, fixture["ids"])
			assert_bool(restored["ok"]).override_failure_message(restored["error"]).is_true()
			assert_array(restored["added_parcels"]).is_equal(Array(fixture["ids"]))
			assert_int(net.graph_version).is_equal(version)
			assert_int(net.parcel_revision).is_equal(1)
			assert_array(net.changes_since(version)).is_empty()
			assert_str(net.graph_hash()).is_equal(graph)
			assert_int(NetworkRestore.counters(net)["parcel"]).is_equal(counter)
			for id in fixture["ids"]:
				var parcel: WorldParcel = net.parcels[id]
				var archive: WorldParcel = fixture["archives"][id]
				assert_object(parcel).is_not_same(archive)
				assert_int(parcel.owner_id).is_equal(0)
				assert_int(archive.owner_id).is_equal(id * 3 + 1)
				assert_array(parcel.outline).is_equal(archive.outline)
				assert_int(parcel.detail).is_equal(archive.detail)
				var vertex := archive.outline[0]
				parcel.outline[0] += Vector2.ONE
				assert_vector(archive.outline[0]).is_equal(vertex)
				parcel.outline[0] = vertex
			assert_array(NetworkInvariants.check_parcels(net)).is_empty()
			assert_array(NetworkInvariants.check_graph_integrity(net)).is_empty()
			assert_bool(net.undo_last_op()["ok"]).is_true()
			assert_str(net.state_hash()).is_equal(before)
			assert_int(net.graph_version).is_equal(version)
			assert_int(net.parcel_revision).is_equal(2)


func _assert_rejected(net: WorldNetwork, source: int, ids: PackedInt64Array) -> void:
	var before := net.state_hash()
	var delta := StateHash.of(net.delta.to_dict())
	var version := net.graph_version
	var revision := net.parcel_revision
	assert_bool(net.restore_parcels(source, ids)["ok"]).is_false()
	assert_str(net.state_hash()).is_equal(before)
	assert_str(StateHash.of(net.delta.to_dict())).is_equal(delta)
	assert_int(net.graph_version).is_equal(version)
	assert_int(net.parcel_revision).is_equal(revision)


func test_wrong_source_duplicate_unknown_and_occupied_requests_leave_everything_untouched() -> void:
	var fixture := _demolished()
	var net: WorldNetwork = fixture["net"]
	var ids: PackedInt64Array = fixture["ids"]
	_assert_rejected(net, -1, ids)
	_assert_rejected(net, 1, ids)
	_assert_rejected(net, 0, PackedInt64Array())
	_assert_rejected(net, 0, PackedInt64Array([999999]))
	_assert_rejected(net, 0, PackedInt64Array([ids[0], ids[0]]))
	var reversed := ids.duplicate()
	reversed.reverse()
	_assert_rejected(net, 0, reversed)
	assert_bool(net.restore_parcels(0, ids)["ok"]).is_true()
	_assert_rejected(net, 0, ids)
	var standing := _grid()
	var drawn := standing.add_road_expropriating(PackedVector2Array(THROUGH), &"local")
	_assert_rejected(standing, 0, PackedInt64Array(drawn["removed_parcels"]))


func test_archive_survives_many_ops_and_restore_then_retake_replays_and_undoes_bit_equal() -> void:
	var fixture := _demolished()
	var net: WorldNetwork = fixture["net"]
	var edge: int = net.edges.keys().min()
	for i in 12:  # component snapshot penceresi geometri arşivini düşürmemeli
		assert_bool(net.set_edge_open(edge, i % 2 == 0)["ok"]).is_true()
	assert_bool(net.restore_parcels(0, fixture["ids"])["ok"]).is_true()
	var second_source := net.delta.ops.size()
	var drawn := net.add_road_expropriating(PackedVector2Array(THROUGH), &"local")
	assert_bool(drawn["ok"]).is_true()
	assert_array(drawn["removed_parcels"]).contains_exactly_in_any_order(Array(fixture["ids"]))
	assert_bool(DemolitionPlan.run(net, net.peek_last_op(), true)["ok"]).is_true()
	_assert_rejected(net, 0, fixture["ids"])
	assert_bool(net.restore_parcels(second_source, fixture["ids"])["ok"]).is_true()
	var replay := _grid()
	var saved := NetworkDelta.from_dict(JSON.parse_string(JSON.stringify(net.delta.to_dict())))
	var applied := replay.apply_delta(saved)
	assert_bool(applied["ok"]).override_failure_message(applied["error"]).is_true()
	assert_str(replay.state_hash()).is_equal(net.state_hash())
	assert_array(NetworkInvariants.check_parcels(replay)).is_empty()
	while replay.can_undo():
		assert_bool(replay.undo_last_op()["ok"]).is_true()
	assert_str(replay.state_hash()).is_equal(fixture["base"])


func test_partial_restore_and_port_queries_do_not_mutate_archives_or_world() -> void:
	var fixture := _demolished()
	var net: WorldNetwork = fixture["net"]
	var ids: PackedInt64Array = fixture["ids"]
	var rules := RoadDraftRules.from_control({"player_roads": {"crossing_parcels": "expropriate"}})
	var port := NetworkExpropriationPort.new(net, rules)
	var before := net.state_hash()
	assert_bool(port.available_land(0, ids)["ok"]).is_true()
	assert_int(port.archived_land(0, ids).size()).is_equal(ids.size())
	assert_str(net.state_hash()).is_equal(before)
	var first := PackedInt64Array([ids[0]])
	assert_bool(port.restore_land(0, first)["ok"]).is_true()
	for id in ids:
		assert_bool(net.parcels.has(id)).is_equal(id == ids[0])
	assert_array(NetworkInvariants.check_parcels(net)).is_empty()
