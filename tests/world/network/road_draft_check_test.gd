# gdlint:disable=max-public-methods
extends GdUnitTestSuite
## T-042 adım 1 · RoadDraftCheck: oyuncu yolu taslağı denetimi (CAN-04, D-009, ADR-0005 Ek E). Sentetik düz dünya + el
## yapımı ızgara (3x3 blok, parselli) + etrafında AÇIK arazi. Her ret nedeninin olumlu ve olumsuz karşılığı vardır;
## gerçek (hafif) Ismeral ağında 500 tohumlu taslak: denetim geçerse parsel kümesi ve graf bütün kalır, aynı girdi aynı
## sonuç.
## Izgara: x çizgileri 500/660/820/980, y çizgileri 500/600/700/800 (DX=160, DZ=100).

const DX := 160.0
const DZ := 100.0
const ORIGIN := Vector2(500.0, 500.0)
const LOCAL := WorldRoadEdge.CLASS_LOCAL

var _world: WorldData
var _rules: RoadDraftRules


func before() -> void:
	_world = NetworkTestSupport.flat_world(3000.0)
	_rules = RoadDraftRules.new()


func _grid(world: WorldData = null, extra: Dictionary = NetworkTestSupport.KEEP_PARCELS) -> WorldNetwork:
	return NetworkTestSupport.grid_network(world if world != null else _world, 3, 3, DX, DZ, ORIGIN, 7, extra)


func _check(net: WorldNetwork, pts: Array, cls: StringName = LOCAL, rules: RoadDraftRules = null,
		busy: bool = false) -> Dictionary:
	return RoadDraftCheck.check(net, PackedVector2Array(pts), cls, rules if rules != null else _rules, busy)


func _assert_rejected(result: Dictionary, reason: StringName) -> void:
	assert_bool(result["ok"]).override_failure_message(str(result)).is_false()
	assert_str(String(result["reason"])).is_equal(String(reason))
	assert_str(result["key"]).is_equal("public_work.reject.%s" % reason)


# --- Olumlu ---

func test_road_leaving_an_existing_road_into_open_land_is_valid() -> void:
	var net := _grid()
	var result := _check(net, [Vector2(580, 500), Vector2(580, 400)])
	assert_bool(result["ok"]).override_failure_message(str(result)).is_true()
	assert_str(String(result["reason"])).is_equal("")
	assert_str(result["key"]).is_equal("")
	assert_float(result["length_m"]).is_equal_approx(100.0, 0.01)
	assert_int(result["connections"]).is_greater(0)
	assert_float((result["regions"] as Dictionary)["D1"]).is_equal_approx(100.0, 0.01)


func test_check_is_pure_it_never_changes_the_network() -> void:
	var net := _grid()
	var before_state := net.state_hash()
	var version := net.graph_version
	for pts: Array in [[Vector2(580, 500), Vector2(580, 400)], [Vector2(580, 430), Vector2(580, 550)],
			[Vector2(1500, 1500), Vector2(1500, 1600)]]:
		_check(net, pts)
	assert_str(net.state_hash()).is_equal(before_state)
	assert_int(net.graph_version).is_equal(version)
	assert_int(net.delta.ops.size()).is_equal(0)


func test_same_input_gives_the_same_result_dictionary() -> void:
	var net := _grid()
	var pts: Array[Vector2] = [Vector2(581.234, 500.0), Vector2(580.111, 401.5)]
	assert_str(JSON.stringify(_check(net, pts))).is_equal(JSON.stringify(_check(net, pts)))
	assert_str(JSON.stringify(_check(net, pts))).is_equal(JSON.stringify(_check(_grid(), pts)))


func test_check_sees_the_points_the_way_add_road_will_see_them() -> void:
	var net := _grid()
	var result := _check(net, [Vector2(580.004, 500.0), Vector2(580.0, 400.006)])
	assert_array(NetworkDelta.encode_points(result["points"])).is_equal(NetworkDelta.encode_points(
			PackedVector2Array([Vector2(580.0, 500.0), Vector2(580.0, 400.01)])))


func test_points_from_cm_matches_the_command_shape() -> void:
	var pts := RoadDraftCheck.points_from_cm(PackedInt64Array([58000, 50000, 58000, 40000]))
	assert_array(Array(pts)).is_equal([Vector2(580, 500), Vector2(580, 400)])
	assert_int(RoadDraftCheck.points_from_cm(PackedInt64Array([1, 2, 3])).size()).is_equal(1)


# --- Her ret nedeni: olumsuz ---

func test_too_short_is_rejected() -> void:
	var net := _grid()
	_assert_rejected(_check(net, [Vector2(580, 500), Vector2(585, 500)]), RoadDraftCheck.REASON_TOO_SHORT)
	_assert_rejected(_check(net, [Vector2(580, 500)]), RoadDraftCheck.REASON_TOO_SHORT)
	_assert_rejected(_check(net, []), RoadDraftCheck.REASON_TOO_SHORT)
	_assert_rejected(_check(net, [Vector2(580, 500), Vector2(NAN, 400)]), RoadDraftCheck.REASON_TOO_SHORT)


func test_too_long_is_rejected_and_reports_the_limit() -> void:
	var net := _grid()
	var result := _check(net, [Vector2(580, 500), Vector2(580, 50)])
	_assert_rejected(result, RoadDraftCheck.REASON_TOO_LONG)
	assert_float(result["max_length_m"]).is_equal(_rules.max_length_m)


func test_water_is_rejected_with_the_position() -> void:
	var wet := NetworkTestSupport.flat_world(3000.0, 100.0, Rect2(1100, 500, 600, 600))
	var net := _grid(wet)
	var result := _check(net, [Vector2(980, 650), Vector2(1200, 650)])
	_assert_rejected(result, RoadDraftCheck.REASON_WATER)
	assert_bool(result["has_at"]).is_true()
	assert_float((result["at"] as Vector2).x).is_greater_equal(1050.0)
	assert_bool(_check(net, [Vector2(980, 650), Vector2(1040, 650)])["ok"]).is_true()


func test_steep_slope_is_rejected() -> void:
	var steep := NetworkTestSupport.flat_world(3000.0)
	for j in steep.height:
		for i in steep.width:
			if i >= 14:
				steep.heights[j * steep.width + i] = 10.0 + float(i - 13) * 80.0
	var net := _grid(steep)
	_assert_rejected(_check(net, [Vector2(980, 650), Vector2(1300, 650)]), RoadDraftCheck.REASON_SLOPE)
	assert_bool(_check(net, [Vector2(980, 650), Vector2(1040, 650)])["ok"]).is_true()
	var lenient := RoadDraftRules.new()
	lenient.max_slope_deg = 60.0
	assert_bool(_check(net, [Vector2(980, 650), Vector2(1300, 650)], LOCAL, lenient)["ok"]).is_true()


func test_a_draft_with_no_contact_to_the_main_network_is_not_connected() -> void:
	var net := _grid()
	_assert_rejected(_check(net, [Vector2(1500, 1500), Vector2(1500, 1600)]), RoadDraftCheck.REASON_NOT_CONNECTED)
	_assert_rejected(_check(net, [Vector2(1100, 650), Vector2(1200, 650)]), RoadDraftCheck.REASON_NOT_CONNECTED)
	# Olumlu karşılık: aynı doğru ağa değdirilince geçer (uç yola yapışır).
	assert_bool(_check(net, [Vector2(980, 650), Vector2(1100, 650)])["ok"]).is_true()


func test_a_road_crossing_the_main_network_counts_as_connected() -> void:
	var net := _grid()
	assert_bool(RoadDraftCheck.apply(net, PackedVector2Array([Vector2(580, 500), Vector2(580, 300)]), LOCAL,
			_rules)["applied"]).is_true()
	# Her iki ucu açık arazide, ortası yeni sokağı keser: planarizer kesişimi düğüme çevirir -> bağlı.
	var crossing: Array[Vector2] = [Vector2(500, 400), Vector2(660, 400)]
	var result := _check(net, crossing)
	assert_bool(result["ok"]).override_failure_message(str(result)).is_true()
	assert_int(result["connections"]).is_greater(0)
	# Olumsuz karşılık: aynı doğru, kesilecek sokak yokken bağlantısızdır.
	_assert_rejected(_check(_grid(), crossing), RoadDraftCheck.REASON_NOT_CONNECTED)


func test_a_road_into_a_parcelled_block_is_rejected() -> void:
	var net := _grid()
	var result := _check(net, [Vector2(580, 430), Vector2(580, 550)])
	_assert_rejected(result, RoadDraftCheck.REASON_CROSSES_PARCELS)
	assert_bool(result["has_at"]).is_true()
	assert_float((result["at"] as Vector2).y).is_greater(500.0)
	# Bloğu baştan başa kesen yol da (iki sınır yoluna bağlı olsa bile) reddedilir.
	_assert_rejected(_check(net, [Vector2(580, 500), Vector2(580, 600)]), RoadDraftCheck.REASON_CROSSES_PARCELS)


func test_a_road_beside_a_block_but_inside_open_land_is_not_a_parcel_crossing() -> void:
	var net := _grid()
	# Kuzey sınır yolunun hemen DIŞINDA ona paralel (10 m uzakta) giden yol: şeridi parselle çakışmaz.
	_assert_rejected(_check(net, [Vector2(500, 480), Vector2(660, 480)]), RoadDraftCheck.REASON_NOT_CONNECTED)
	var parallel := _check(net, [Vector2(500, 500), Vector2(500, 420), Vector2(660, 420)])
	assert_bool(parallel["ok"]).override_failure_message(str(parallel)).is_true()


func test_a_draft_along_an_existing_road_is_a_duplicate() -> void:
	var net := _grid()
	_assert_rejected(_check(net, [Vector2(500, 500), Vector2(660, 500)]), RoadDraftCheck.REASON_DUPLICATE)
	_assert_rejected(_check(net, [Vector2(520, 500.5), Vector2(640, 499.5)]), RoadDraftCheck.REASON_DUPLICATE)
	# Yarısı mevcut yolda, yarısı açık arazide olan taslak kopya DEĞİLDİR.
	assert_bool(_check(net, [Vector2(500, 500), Vector2(500, 420)])["ok"]).is_true()


func test_outside_the_jurisdiction_is_rejected() -> void:
	var net := _grid()
	var other := RoadDraftRules.new()
	other.jurisdiction_regions = [&"D9"]
	_assert_rejected(_check(net, [Vector2(580, 500), Vector2(580, 400)], LOCAL, other),
			RoadDraftCheck.REASON_OUTSIDE_JURISDICTION)
	var allowed := RoadDraftRules.new()
	allowed.jurisdiction_regions = [&"D1"]
	assert_bool(_check(net, [Vector2(580, 500), Vector2(580, 400)], LOCAL, allowed)["ok"]).is_true()


func test_outside_the_world_bounds_is_outside_the_jurisdiction() -> void:
	var net := _grid()
	var long_rules := RoadDraftRules.new()
	long_rules.max_length_m = 1000.0
	_assert_rejected(_check(net, [Vector2(580, 500), Vector2(580, -30)], LOCAL, long_rules),
			RoadDraftCheck.REASON_OUTSIDE_JURISDICTION)


func test_busy_world_rejects_even_a_valid_draft() -> void:
	var net := _grid()
	_assert_rejected(_check(net, [Vector2(580, 500), Vector2(580, 400)], LOCAL, null, true),
			RoadDraftCheck.REASON_BUSY)


func test_nothing_to_undo_is_reported_with_its_key() -> void:
	var net := _grid()
	var result := RoadDraftCheck.undo(net)
	assert_bool(result["ok"]).is_false()
	assert_str(String(result["reason"])).is_equal("nothing_to_undo")
	assert_str(result["key"]).is_equal("public_work.reject.nothing_to_undo")


func test_a_class_outside_the_allowed_list_is_rejected_as_bad_class() -> void:
	var net := _grid()
	_assert_rejected(_check(net, [Vector2(580, 500), Vector2(580, 400)], WorldRoadEdge.CLASS_ARTERIAL),
			RoadDraftCheck.REASON_BAD_CLASS)
	_assert_rejected(_check(net, [Vector2(580, 500), Vector2(580, 400)], WorldRoadEdge.CLASS_FERRY),
			RoadDraftCheck.REASON_BAD_CLASS)


func test_every_reason_key_of_the_plan_is_covered_by_the_constants() -> void:
	var keys: Array[String] = []
	for reason in RoadDraftCheck.ALL_REASONS:
		keys.append(RoadDraftCheck.key_of(reason))
	assert_array(keys).contains_exactly_in_any_order(["public_work.reject.too_short", "public_work.reject.too_long",
			"public_work.reject.water", "public_work.reject.slope", "public_work.reject.not_connected",
			"public_work.reject.crosses_parcels", "public_work.reject.duplicate",
			"public_work.reject.outside_jurisdiction", "public_work.reject.busy", "public_work.reject.nothing_to_undo"])


# --- Parselli bloğa giriş kuralı veri güdümlüdür (aşama 2 açabilir), v0'da KAPALI ---

func test_crossing_parcels_is_a_data_rule_closed_in_v0_and_openable_for_stage_two() -> void:
	var net := _grid()
	var pts: Array[Vector2] = [Vector2(580, 430), Vector2(580, 550)]
	_assert_rejected(_check(net, pts), RoadDraftCheck.REASON_CROSSES_PARCELS)
	var stage_two := RoadDraftRules.new()
	stage_two.crossing_parcels = RoadDraftRules.CROSSING_ALLOW
	assert_bool(_check(net, pts, LOCAL, stage_two)["ok"]).is_true()
	var from_data := RoadDraftRules.from_control({"player_roads": {"crossing_parcels": "allow"}})
	assert_bool(_check(net, pts, LOCAL, from_data)["ok"]).is_true()
	assert_str(String(RoadDraftRules.load_path().crossing_parcels)).is_equal("expropriate")  # T-042b; düz denetim yine ret


# --- v0 değişmezi: geçerli taslak parsel kümesini değiştirmez; geri alınca taban ---

func test_applying_a_valid_spur_keeps_the_parcel_set_and_undo_restores_the_exact_state() -> void:
	var net := _grid()
	var base_state := net.state_hash()
	var base_graph := net.graph_hash()
	var base_parcels := RoadDraftCheck.parcel_set_hash(net)
	var applied := RoadDraftCheck.apply(net, PackedVector2Array([Vector2(580, 500), Vector2(580, 400)]), LOCAL, _rules)
	assert_bool(applied["applied"]).override_failure_message(str(applied["reason"])).is_true()
	assert_str(net.graph_hash()).is_not_equal(base_graph)
	assert_str(RoadDraftCheck.parcel_set_hash(net)).is_equal(base_parcels)
	assert_array(applied["report"]["added_parcels"]).is_empty()
	assert_array(applied["report"]["removed_parcels"]).is_empty()
	for eid in applied["report"]["added_edges"]:
		assert_int(net.edge(eid).layer).is_equal(WorldRoadEdge.LAYER_DELTA)
	assert_array(NetworkInvariants.check_graph_integrity(net)).is_empty()
	assert_array(NetworkInvariants.check_parcels(net)).is_empty()
	var undone := RoadDraftCheck.undo(net)
	assert_bool(undone["ok"]).is_true()
	assert_str(net.graph_hash()).is_equal(base_graph)
	assert_str(net.state_hash()).is_equal(base_state)


func test_a_road_closing_a_loop_in_open_land_keeps_the_new_face_unparcelled() -> void:
	var net := _grid()
	var base_parcels := RoadDraftCheck.parcel_set_hash(net)
	var loop := PackedVector2Array([Vector2(660, 500), Vector2(660, 400), Vector2(820, 400), Vector2(820, 500)])
	var applied := RoadDraftCheck.apply(net, loop, LOCAL, _rules)
	assert_bool(applied["applied"]).override_failure_message(str(applied["reason"])).is_true()
	assert_str(RoadDraftCheck.parcel_set_hash(net)).is_equal(base_parcels)
	assert_int((applied["report"]["added_blocks"] as Array).size()).is_equal(1)
	var added: WorldBlock = net.block(int(applied["report"]["added_blocks"][0]))
	assert_str(String(added.kind)).is_equal(String(WorldBlock.KIND_OPEN))
	assert_bool(added.parcel_ids.is_empty()).is_true()
	# Karşıt kanıt: kural kapalıyken (eski davranış) aynı yol yeni yüzü parsellerdi.
	var legacy := _grid(null, {})
	var legacy_report := legacy.add_road(loop, LOCAL)
	assert_int((legacy_report["added_parcels"] as Array).size()).is_greater(0)


func test_the_delta_never_upgrades_an_existing_edge_under_the_v0_rule() -> void:
	var field_net := NetworkTestSupport.empty_network(_world, 7, NetworkTestSupport.KEEP_PARCELS)
	field_net.author_polyline(PackedVector2Array([Vector2(500, 500), Vector2(700, 500), Vector2(700, 600),
			Vector2(500, 600), Vector2(500, 500)]), WorldRoadEdge.CLASS_FIELD)
	field_net.seal_base()
	var base_state := field_net.state_hash()
	var report := field_net.add_road(PackedVector2Array([Vector2(500, 500), Vector2(700, 500)]), LOCAL)
	assert_bool(report["ok"]).is_true()
	for e: WorldRoadEdge in field_net.edges.values():
		assert_str(String(e.road_class)).is_equal(String(WorldRoadEdge.CLASS_FIELD))
	assert_str(field_net.state_hash()).is_equal(base_state)
	# Karşıt kanıt: kural kapalıyken (eski davranış) aynı çizim kenarı yerel sokağa yükseltir.
	var legacy := NetworkTestSupport.empty_network(_world, 7)
	legacy.author_polyline(PackedVector2Array([Vector2(500, 500), Vector2(700, 500), Vector2(700, 600),
			Vector2(500, 600), Vector2(500, 500)]), WorldRoadEdge.CLASS_FIELD)
	legacy.seal_base()
	assert_bool(legacy.add_road(PackedVector2Array([Vector2(500, 500), Vector2(700, 500)]), LOCAL)["ok"]).is_true()
	assert_str(legacy.state_hash()).is_not_equal(base_state)


# --- 500 tohumlu taslak, gerçek (hafif) Ismeral ağı ---

func test_500_seeded_drafts_pass_implies_parcels_unchanged_and_graph_whole() -> void:
	var net := NetworkTestSupport.fresh_light()
	var rules := RoadDraftRules.load_path()
	rules.jurisdiction_regions = []
	var base_graph := net.graph_hash()
	var base_state := net.state_hash()
	var base_parcel_hash := RoadDraftCheck.parcel_set_hash(net)
	var edge_ids: Array = net.edges.keys()
	edge_ids.sort()
	var rng := RandomNumberGenerator.new()
	rng.seed = 42042
	var valid := 0
	var applied_count := 0
	var reasons := {}
	for i in 500:
		var e: WorldRoadEdge = net.edges[edge_ids[rng.randi() % edge_ids.size()]]
		var a := net.node_pos(e.a).lerp(net.node_pos(e.b), rng.randf())
		var b := a + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(20.0, 330.0)
		var pts := PackedVector2Array([a, b])
		var first := RoadDraftCheck.check(net, pts, LOCAL, rules)
		var second := RoadDraftCheck.check(net, pts, LOCAL, rules)
		assert_str(JSON.stringify(first)).is_equal(JSON.stringify(second))
		reasons[String(first["reason"])] = int(reasons.get(String(first["reason"]), 0)) + 1
		if not bool(first["ok"]):
			assert_str(first["key"]).starts_with("public_work.reject.")
			continue
		valid += 1
		if applied_count >= 40:
			continue
		var before_parcels := net.parcels.size()
		var result := RoadDraftCheck.apply(net, pts, LOCAL, rules)
		assert_bool(result["applied"]).override_failure_message("%d: %s" % [i, str(result["reason"])]).is_true()
		applied_count += 1
		assert_int(net.parcels.size()).is_equal(before_parcels)
		assert_array(result["report"]["added_parcels"]).is_empty()
		assert_array(result["report"]["removed_parcels"]).is_empty()
		assert_bool((result["change"] as NetworkChange).changes_parcels()).is_false()
		if applied_count % 8 == 0:
			assert_array(NetworkInvariants.check_graph_integrity(net)).is_empty()
	assert_int(valid).override_failure_message(str(reasons)).is_greater(10)
	assert_int(applied_count).is_greater(5)
	assert_str(RoadDraftCheck.parcel_set_hash(net)).is_equal(base_parcel_hash)
	assert_array(NetworkInvariants.check_graph_integrity(net)).is_empty()
	assert_array(NetworkInvariants.check_parcels(net)).is_empty()
	# Hepsini LIFO geri al: taban graf ve taban durum bit-eşit.
	while net.can_undo():
		assert_bool(RoadDraftCheck.undo(net)["ok"]).is_true()
	assert_str(net.graph_hash()).is_equal(base_graph)
	assert_str(net.state_hash()).is_equal(base_state)
	assert_int(net.delta.ops.size()).is_equal(0)
