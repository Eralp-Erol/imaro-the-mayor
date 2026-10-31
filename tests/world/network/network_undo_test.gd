# gdlint:disable=max-public-methods
extends GdUnitTestSuite
## T-042 adım 1 · Delta geri alma (LIFO), değişim günlüğü, yerel blok yenileme, parsel kümesi değişmezi (CAN-04).
## Sentetik düz dünya + 3x3 ızgara. Geri alma graf hash'ini VE blok/parsel durumunu (kimlik, `owner_id`) bit-eşit verir.

const PURE_SOURCES: Array[String] = [
	"res://src/world/network/network_op_journal.gd", "res://src/world/network/network_change.gd",
	"res://src/world/network/network_restore.gd", "res://src/world/network/network_local_refresh.gd",
	"res://src/world/network/network_block_match.gd", "res://src/world/network/network_columns.gd",
	"res://src/world/network/road_draft_check.gd", "res://src/world/network/road_draft_rules.gd",
]
const DX := 160.0
const DZ := 100.0
const ORIGIN := Vector2(500.0, 500.0)
const LOCAL := WorldRoadEdge.CLASS_LOCAL
const SPUR: Array = [Vector2(580, 500), Vector2(580, 400)]
const LOOP: Array = [Vector2(660, 500), Vector2(660, 400), Vector2(820, 400), Vector2(820, 500)]
const SPLITTER: Array = [Vector2(580, 500), Vector2(580, 600)]

var _world: WorldData


func before() -> void:
	_world = NetworkTestSupport.flat_world(3000.0)


func _grid(extra: Dictionary = NetworkTestSupport.KEEP_PARCELS, cols: int = 3, rows: int = 3) -> WorldNetwork:
	return NetworkTestSupport.grid_network(_world, cols, rows, DX, DZ, ORIGIN, 7, extra)


func _road(net: WorldNetwork, pts: Array, cls: StringName = LOCAL) -> Dictionary:
	var report := net.add_road(PackedVector2Array(pts), cls)
	assert_bool(report["ok"]).override_failure_message(str(report)).is_true()
	return report


## Kimliklerden bağımsız kanonik özet: blok imza+tür çoklu kümesi, parsel çokgenleri, graf hash'i.
func _canonical(net: WorldNetwork) -> String:
	var blocks: Array[String] = []
	for b: WorldBlock in net.blocks.values():
		blocks.append("%s|%s|%d" % [b.signature, String(b.kind), b.parcel_ids.size()])
	blocks.sort()
	return "%s#%s#%s" % [net.graph_hash(), RoadDraftCheck.parcel_set_hash_ignoring_ids(net), "\n".join(blocks).md5_text()]


# --- Geri alma ---

func test_undo_restores_the_exact_state_after_a_spur() -> void:
	var net := _grid()
	var base_state := net.state_hash()
	var base_graph := net.graph_hash()
	var base_counts := net.counts()
	_road(net, SPUR)
	assert_str(net.graph_hash()).is_not_equal(base_graph)
	var undone := net.undo_last_op()
	assert_bool(undone["ok"]).is_true()
	assert_str(net.graph_hash()).is_equal(base_graph)
	assert_str(net.state_hash()).is_equal(base_state)
	assert_dict(net.counts()).is_equal(base_counts)
	assert_int(net.delta.ops.size()).is_equal(0)
	assert_bool(net.can_undo()).is_false()
	assert_array(NetworkInvariants.check_graph_integrity(net)).is_empty()
	assert_array(NetworkInvariants.check_parcels(net)).is_empty()
	# Geri alma sonrası tam yenileme hiçbir şeyi değiştirmez: durum tutarlı.
	var refreshed := net.refresh_blocks()
	for key in ["added_blocks", "removed_blocks", "added_parcels", "removed_parcels"]:
		assert_array(refreshed[key]).is_empty()
	assert_str(net.state_hash()).is_equal(base_state)


func test_undo_gives_back_the_removed_parcels_with_their_ids_and_owner_slots() -> void:
	# Eski davranış (kural kapalı): bloğu bölen yol parselleri siler; geri alma KENDİ nesnelerini geri koyar.
	var net := _grid({})
	var target := net.block_at(ORIGIN.x + DX * 0.5, ORIGIN.y + DZ * 0.5)
	var victim_id: int = target.parcel_ids[0]
	var victim: WorldParcel = net.parcel(victim_id)
	victim.owner_id = 42
	var base_state := net.state_hash()
	var base_parcel_ids: Array = net.parcels.keys()
	base_parcel_ids.sort()
	var report := _road(net, SPLITTER)
	assert_array(report["removed_parcels"]).contains(victim_id)
	assert_object(net.parcel(victim_id)).is_null()
	assert_bool(net.undo_last_op()["ok"]).is_true()
	assert_object(net.parcel(victim_id)).is_same(victim)
	assert_int(net.parcel(victim_id).owner_id).is_equal(42)
	var ids: Array = net.parcels.keys()
	ids.sort()
	assert_array(ids).is_equal(base_parcel_ids)
	assert_str(net.state_hash()).is_equal(base_state)
	assert_array(NetworkInvariants.check_parcels(net)).is_empty()


func test_lifo_chain_of_mixed_ops_restores_every_intermediate_state() -> void:
	for extra: Dictionary in [NetworkTestSupport.KEEP_PARCELS, {}]:
		var net := _grid(extra)
		var states: Array[String] = [net.state_hash()]
		var graphs: Array[String] = [net.graph_hash()]
		_road(net, SPUR)
		states.append(net.state_hash())
		graphs.append(net.graph_hash())
		_road(net, LOOP)
		states.append(net.state_hash())
		graphs.append(net.graph_hash())
		assert_bool(net.set_edge_open(net.edges_near(580.0, 450.0, 3.0)[0].id, false)["ok"]).is_true()
		states.append(net.state_hash())
		graphs.append(net.graph_hash())
		_road(net, SPLITTER)
		states.append(net.state_hash())
		graphs.append(net.graph_hash())
		assert_int(net.delta.ops.size()).is_equal(4)
		var i := states.size() - 1
		while net.can_undo():
			assert_bool(net.undo_last_op()["ok"]).is_true()
			i -= 1
			assert_str(net.state_hash()).override_failure_message("adım %d (kural %s)" % [i, str(extra)]).is_equal(states[i])
			assert_str(net.graph_hash()).is_equal(graphs[i])
		assert_int(i).is_equal(0)


func test_undo_of_an_edge_removal_that_merged_blocks_restores_them() -> void:
	var net := _grid({}, 2, 1)
	var base_state := net.state_hash()
	var mid := net.edges_near(ORIGIN.x + DX, ORIGIN.y + DZ * 0.5, 4.0)
	assert_bool(net.remove_edge(mid[0].id)["ok"]).is_true()
	assert_int(net.counts()["blocks"]).is_equal(1)
	assert_bool(net.undo_last_op()["ok"]).is_true()
	assert_int(net.counts()["blocks"]).is_equal(2)
	assert_str(net.state_hash()).is_equal(base_state)


func test_undo_with_nothing_to_undo_reports_the_key_and_changes_nothing() -> void:
	var net := _grid()
	var state := net.state_hash()
	var result := net.undo_last_op()
	assert_bool(result["ok"]).is_false()
	assert_str(result["error"]).is_equal("nothing_to_undo")
	_road(net, SPUR)
	assert_bool(net.undo_last_op()["ok"]).is_true()
	assert_bool(net.undo_last_op()["ok"]).is_false()
	assert_str(net.state_hash()).is_equal(state)


func test_redo_after_undo_reproduces_the_first_application_bit_for_bit() -> void:
	var net := _grid()
	_road(net, LOOP)
	var first := net.state_hash()
	var first_ops := net.delta.to_dict()
	assert_bool(net.undo_last_op()["ok"]).is_true()
	_road(net, LOOP)
	assert_str(net.state_hash()).is_equal(first)
	assert_str(JSON.stringify(net.delta.to_dict())).is_equal(JSON.stringify(first_ops))


func test_replay_from_saved_delta_is_bit_equal_and_undoable() -> void:
	var live := _grid()
	_road(live, SPUR)
	_road(live, LOOP)
	var saved: Variant = JSON.parse_string(JSON.stringify(live.delta.to_dict()))
	var loaded := _grid()
	var base_state := loaded.state_hash()
	var applied := loaded.apply_delta(NetworkDelta.from_dict(saved))
	assert_bool(applied["ok"]).override_failure_message(str(applied)).is_true()
	assert_str(loaded.state_hash()).is_equal(live.state_hash())
	assert_str(loaded.graph_hash()).is_equal(live.graph_hash())
	# Yüklenen delta da LIFO geri alınabilir (import_save'in ortak önek/fazlayı geri alma yolu).
	assert_bool(loaded.undo_last_op()["ok"]).is_true()
	assert_bool(loaded.undo_last_op()["ok"]).is_true()
	assert_str(loaded.state_hash()).is_equal(base_state)


func test_set_open_is_undoable() -> void:
	var net := _grid()
	var base_state := net.state_hash()
	var edge := net.edges_near(580.0, 500.0, 3.0)[0]
	assert_bool(net.set_edge_open(edge.id, false)["ok"]).is_true()
	assert_bool(edge.open).is_false()
	assert_bool(net.undo_last_op()["ok"]).is_true()
	assert_bool(net.edge(edge.id).open).is_true()
	assert_str(net.state_hash()).is_equal(base_state)


# --- Parsel kümesi değişmezi (v0) ---

func test_spur_and_loop_in_open_land_never_change_the_parcel_set() -> void:
	var net := _grid()
	var base_parcels := RoadDraftCheck.parcel_set_hash(net)
	var ids_before: Array = net.parcels.keys()
	ids_before.sort()
	for pts: Array in [SPUR, LOOP]:
		var report := _road(net, pts)
		assert_array(report["added_parcels"]).is_empty()
		assert_array(report["removed_parcels"]).is_empty()
		assert_bool((report["change"] as NetworkChange).changes_parcels()).is_false()
		assert_str(RoadDraftCheck.parcel_set_hash(net)).is_equal(base_parcels)
	var ids_after: Array = net.parcels.keys()
	ids_after.sort()
	assert_array(ids_after).is_equal(ids_before)


func test_negative_a_road_through_a_block_does_change_the_parcel_set_and_is_detected() -> void:
	# Denetimsiz ham add_road bloğu böler: ihlal hem rapordan hem özetten görülür (test başarısız olabilir).
	var net := _grid()
	var base_parcels := RoadDraftCheck.parcel_set_hash(net)
	var report := _road(net, SPLITTER)
	assert_bool((report["change"] as NetworkChange).changes_parcels()).is_true()
	assert_array(report["removed_parcels"]).is_not_empty()
	assert_str(RoadDraftCheck.parcel_set_hash(net)).is_not_equal(base_parcels)


func test_apply_rolls_back_when_the_parcel_set_would_change() -> void:
	# `apply` yalnız denetimden geçen taslağı uygular: bloğu bölen taslak reddedilir, ağ ve delta değişmez.
	var net := _grid()
	var rules := RoadDraftRules.new()
	var result := RoadDraftCheck.apply(net, PackedVector2Array(SPLITTER), LOCAL, rules)
	assert_bool(result["applied"]).is_false()
	assert_str(String(result["reason"])).is_equal("crosses_parcels")
	assert_int(net.delta.ops.size()).is_equal(0)


func test_connecting_road_splitting_a_parcelled_blocks_short_angled_edge_keeps_its_parcels() -> void:
	# Kısa, eğik kenarda 0,01 m yuvarlamalı bölünme göreli 1e-4 eşdoğrusallığı aşar: imza kayar. Köşe anahtarı bloğu korur.
	var legacy_rebuilds := 0
	for k in 25:
		var x := 502.0 + float(k) * 1.37 + 0.1337
		for keep in [true, false]:
			var net := NetworkTestSupport.empty_network(_world, 7, NetworkTestSupport.KEEP_PARCELS if keep else {})
			net.author_polyline(PackedVector2Array([Vector2(500, 500), Vector2(537.3, 503.1), Vector2(540, 560),
					Vector2(497, 556), Vector2(500, 500)]), LOCAL)
			net.seal_base()
			var block_id: int = net.blocks.keys()[0]
			for b: WorldBlock in net.blocks.values():
				if not b.parcel_ids.is_empty():
					block_id = b.id
			var parcels_before := RoadDraftCheck.parcel_set_hash(net)
			var y := 500.0 + (x - 500.0) * (3.1 / 37.3)
			var report := net.add_road(PackedVector2Array([Vector2(x, y), Vector2(x, y - 90.0)]), LOCAL)
			assert_bool(report["ok"]).is_true()
			var rebuilt := (report["removed_blocks"] as Array).has(block_id)
			if keep:
				assert_bool(rebuilt).override_failure_message("x=%f" % x).is_false()
				assert_str(RoadDraftCheck.parcel_set_hash(net)).is_equal(parcels_before)
			elif rebuilt:
				legacy_rebuilds += 1
	assert_int(legacy_rebuilds).override_failure_message("eski davranışta yeniden üretim yok: test anlamsız").is_greater(0)


func test_corner_key_ignores_split_vertices_but_not_real_corners() -> void:
	var square := PackedVector2Array([Vector2(0, 0), Vector2(100, 0), Vector2(100, 60), Vector2(0, 60)])
	var split := PackedVector2Array([Vector2(0, 0), Vector2(40, 0.006), Vector2(100, 0), Vector2(100, 60), Vector2(0, 60)])
	var moved := PackedVector2Array([Vector2(0, 0), Vector2(40, 0.5), Vector2(100, 0), Vector2(100, 60), Vector2(0, 60)])
	var shifted := PackedVector2Array([Vector2(0, 0), Vector2(100, 0), Vector2(100, 60.5), Vector2(0, 60)])
	assert_str(NetworkBlockMatch.corner_key(split)).is_equal(NetworkBlockMatch.corner_key(square))
	assert_str(NetworkBlockMatch.corner_key(moved)).is_not_equal(NetworkBlockMatch.corner_key(square))
	assert_str(NetworkBlockMatch.corner_key(shifted)).is_not_equal(NetworkBlockMatch.corner_key(square))


# --- Yerel blok yenileme = tam yenileme ---

func test_local_refresh_gives_the_same_result_as_the_full_refresh() -> void:
	var local := _grid()
	var full := _grid()
	full.local_refresh_enabled = false
	assert_bool(local._blocks_single_comp).is_true()
	for pts: Array in [SPUR, LOOP, [Vector2(820, 400), Vector2(820, 300), Vector2(980, 300), Vector2(980, 500)]]:
		_road(local, pts)
		_road(full, pts)
		assert_str(_canonical(local)).is_equal(_canonical(full))
	assert_bool(local.undo_last_op()["ok"]).is_true()
	assert_bool(full.undo_last_op()["ok"]).is_true()
	assert_str(_canonical(local)).is_equal(_canonical(full))
	assert_array(NetworkInvariants.check_parcels(local)).is_empty()


func test_local_refresh_also_matches_the_full_refresh_when_blocks_are_rebuilt() -> void:
	var local := _grid({})
	var full := _grid({})
	full.local_refresh_enabled = false
	for pts: Array in [SPLITTER, [Vector2(740, 500), Vector2(740, 800)]]:
		_road(local, pts)
		_road(full, pts)
		assert_str(_canonical(local)).is_equal(_canonical(full))
	assert_int(local.parcels.size()).is_equal(full.parcels.size())


func test_a_detached_road_falls_back_to_the_full_refresh_and_stays_consistent() -> void:
	var net := _grid()
	_road(net, [Vector2(1800, 1800), Vector2(2000, 1800)])
	assert_bool(net._blocks_single_comp).is_false()
	var link := _road(net, [Vector2(980, 800), Vector2(1800, 1800)])
	assert_bool(link["ok"]).is_true()
	assert_array(NetworkInvariants.check_graph_integrity(net)).is_empty()
	assert_array(NetworkInvariants.check_parcels(net)).is_empty()
	assert_bool(net.undo_last_op()["ok"]).is_true()
	assert_bool(net.undo_last_op()["ok"]).is_true()
	assert_array(NetworkInvariants.check_graph_integrity(net)).is_empty()


# --- Değişim günlüğü (RoadView.rebuild_chunks için) ---

func test_change_record_lists_edges_and_only_the_touched_chunks() -> void:
	var net := _grid()
	var version := net.graph_version
	var report := _road(net, SPUR)
	var change: NetworkChange = report["change"]
	assert_str(String(change.kind)).is_equal("apply")
	assert_int(change.op_index).is_equal(0)
	assert_bool(change.changes_graph()).is_true()
	assert_bool(change.changes_parcels()).is_false()
	# Kenar bölünmesi: yeni yol kenarı + bölünen kenarın ikinci yarısı eklenir; bölünen kenar "değişen"dir.
	assert_array(Array(change.edges_added)).contains(report["added_edges"])
	assert_int(change.edges_added.size()).is_equal(2)
	assert_int(change.edges_changed.size()).is_equal(1)
	assert_array(Array(change.edges_changed)).contains_exactly(report["split_edges"])
	assert_bool(change.dirty_rect.encloses(Rect2(Vector2(575, 400), Vector2(10, 100)))).is_true()
	assert_int(change.graph_version).is_equal(net.graph_version)
	assert_int(change.version_before).is_equal(version)
	var keys := change.chunk_keys(_world.origin, 200.0)
	assert_array(keys).contains([Vector2i(2, 2), Vector2i(2, 1)])
	assert_array(keys).not_contains([Vector2i(10, 10), Vector2i(0, 0)])
	var wide := change.chunk_keys(_world.origin, 2000.0)
	assert_array(wide).is_equal([Vector2i(0, 0)])
	assert_array(net.changes_since(version)).is_equal([change])
	assert_bool(net.change_log_covers(version)).is_true()


func test_undo_change_record_mirrors_the_apply_record() -> void:
	var net := _grid()
	var version := net.graph_version
	var applied: NetworkChange = _road(net, LOOP)["change"]
	var after_apply := net.graph_version
	var undone: NetworkChange = net.undo_last_op()["change"]
	assert_str(String(undone.kind)).is_equal("undo")
	assert_array(Array(undone.edges_removed)).is_equal(Array(applied.edges_added))
	assert_array(Array(undone.edges_added)).is_equal(Array(applied.edges_removed))
	assert_array(Array(undone.nodes_removed)).is_equal(Array(applied.nodes_added))
	assert_int(undone.version_before).is_equal(after_apply)
	assert_int(undone.graph_version).is_greater(after_apply)
	assert_array(undone.chunk_keys(_world.origin, 200.0)).is_equal(applied.chunk_keys(_world.origin, 200.0))
	assert_array(net.changes_since(version)).is_equal([applied, undone])
	assert_array(net.changes_since(after_apply)).is_equal([undone])
	assert_array(net.changes_since(undone.graph_version)).is_empty()


func test_change_log_is_bounded_and_reports_when_it_no_longer_covers() -> void:
	var net := _grid()
	var first_version := net.graph_version
	for i in WorldNetwork.CHANGE_LOG_MAX + 3:
		var edge := net.edges_near(580.0, 500.0, 3.0)[0]
		assert_bool(net.set_edge_open(edge.id, i % 2 == 1)["ok"]).is_true()
	assert_int(net.change_log.size()).is_equal(WorldNetwork.CHANGE_LOG_MAX)
	assert_bool(net.change_log_covers(first_version)).is_false()
	assert_bool(net.change_log_covers(net.change_log[0].version_before)).is_true()
	assert_bool(net.change_log_covers(net.graph_version)).is_true()


func test_failed_ops_leave_no_change_record_and_no_undo_entry() -> void:
	var net := _grid()
	var state := net.state_hash()
	assert_bool(net.add_road(PackedVector2Array([Vector2(100, 100)]), LOCAL)["ok"]).is_false()
	assert_bool(net.remove_edge(99999)["ok"]).is_false()
	assert_array(net.change_log).is_empty()
	assert_bool(net.can_undo()).is_false()
	assert_str(net.state_hash()).is_equal(state)


# --- Veri ---

func test_player_road_rules_live_in_the_network_data_file() -> void:
	var control := NetworkTestSupport.network_control()
	assert_bool(control.has("player_roads")).is_true()
	var data: Dictionary = control["player_roads"]
	assert_bool(data["keep_parcels"]).is_true()
	assert_str(data["crossing_parcels"]).is_equal("expropriate")  # T-042b: köprü açık, DÜZ taslak yine ret
	var rules := RoadDraftRules.from_control(control)
	assert_array(rules.allowed_classes).is_equal([LOCAL])
	assert_float(rules.max_length_m).is_greater(rules.min_length_m)
	var world := WorldTestSupport.default_world()
	for code in rules.jurisdiction_regions:
		assert_object(world.region_by_code(code)).is_not_null()
	assert_bool(NetworkTestSupport.light_network().rules.keep_parcels_on_delta).is_true()
	assert_bool(NetworkTestSupport.test_rules(_world).keep_parcels_on_delta).is_false()


# --- Saflık (TEK-01/02) ---

func test_road_draft_and_undo_sources_have_no_forbidden_apis() -> void:
	for path in PURE_SOURCES:
		assert_str(FileAccess.get_file_as_string(path)).is_not_empty()
		assert_array(WorldTestSupport.forbidden_api_hits(path)).override_failure_message(path).is_empty()
