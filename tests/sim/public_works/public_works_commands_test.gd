# gdlint:disable=max-public-methods
extends GdUnitTestSuite
## T-042 adım 2 · `public_work.road` / `public_work.undo_last` komutları (CAN-04, D-009, ADR-0005 Ek E): doğrulama
## (kuru koşu + gönderim + tick'te yeniden doğrulama), uygulama (ağ delta'sı, olay, durum bölümü), geri alma ve OLUMSUZ
## durumlar. Her ret anahtarı durumu bozmadan reddedilir (hash komutsuz koşuyla aynı kalır).

const P := preload("res://tests/sim/public_works/public_works_support.gd")
const SECTION := "public_works"


func _run() -> Dictionary:
	return P.setup()


func _facade(run: Dictionary) -> SimFacadeImpl:
	return run["facade"]


func _events(f: SimFacade, kind: StringName) -> Array[SimEvent]:
	var out: Array[SimEvent] = []
	for e in f.events_since(0):
		if e.kind == kind:
			out.append(e)
	return out


# --- Olumlu: kuru koşu, gönderim, tick'te uygulama ---

func test_validate_returns_the_sims_own_preview_without_touching_state() -> void:
	var run := _run()
	var f := _facade(run)
	var before := f.state_hash()
	var r := f.validate_command(P.road(P.spur_a_cm()))
	assert_str(String(r.status)).is_equal("valid")
	assert_int(r.command_id).is_equal(0)
	assert_int(int(r.args["length_m"])).is_equal(100)
	assert_int(int(r.args["length_cm"])).is_equal(10000)
	assert_dict(r.args["regions"]).is_equal({String(P.CODE_A): 10})  # 100 m x 100 birim/km (ÇM)
	assert_bool(bool(r.args["cost_available"])).is_false()  # T-014 kurulu değil: uydurma para yok
	assert_str(String(r.args["cost_reason_key"])).is_equal("public_work.cost.not_built")
	assert_str(f.state_hash()).is_equal(before)
	assert_bool((run["net"] as WorldNetwork).delta.ops.is_empty()).is_true()
	assert_bool(f.game_state().systems.has(SECTION)).is_false()


func test_submit_queues_and_the_tick_boundary_adds_the_edge_to_the_shared_network() -> void:
	var run := _run()
	var f := _facade(run)
	var net: WorldNetwork = run["net"]
	var edges_before := net.edges.size()
	var r := f.submit_command(P.road(P.spur_a_cm()))
	assert_str(String(r.status)).is_equal("queued")
	assert_int(r.command_id).is_equal(1)
	assert_int(r.apply_tick).is_equal(1)
	assert_int(net.edges.size()).is_equal(edges_before)  # tick sınırına dek ağ değişmez
	f.advance(1)
	assert_int(net.edges.size()).is_greater(edges_before)
	assert_int(net.delta.ops.size()).is_equal(1)
	var built := _events(f, &"public_work.built")
	assert_int(built.size()).is_equal(1)
	assert_bool(built[0].subjects.has("command.1")).is_true()
	assert_bool(built[0].subjects.has("region." + String(P.CODE_A))).is_true()
	assert_str(String(built[0].message_key)).is_equal("event.road.built")
	assert_int(built[0].command_id).is_equal(1)
	assert_int(int(built[0].args["length_cm"])).is_equal(10000)
	assert_int(_events(f, &"command.applied").size()).is_equal(1)
	var works := f.public_works()
	assert_int(works.size()).is_equal(1)
	assert_int(works[0].command_id).is_equal(1)
	assert_dict(works[0].region_units).is_equal({String(P.CODE_A): 10})


func test_state_section_exists_only_after_the_first_applied_road() -> void:
	var run := _run()
	var f := _facade(run)
	f.validate_command(P.road(P.spur_a_cm()))
	f.submit_command(P.road(P.detached_cm()))  # reddedilir
	f.advance(2)
	assert_bool(f.game_state().systems.has(SECTION)).is_false()
	f.submit_command(P.road(P.spur_a_cm()))
	f.advance(1)
	var d: Dictionary = f.game_state().systems[SECTION]
	assert_int((d["ops"] as Array).size()).is_equal(1)
	assert_int((d["hashes"] as Array).size()).is_equal(1)
	assert_str(d["hashes"][0]).is_equal((run["net"] as WorldNetwork).graph_hash())
	assert_dict(d["infra_bonus"]).is_equal({String(P.CODE_A): 10})
	assert_dict(d["infra_source"]).is_equal({String(P.CODE_A): "command.1"})


func test_road_leaves_the_parcel_set_untouched_and_development_needs_an_investor_decision() -> void:
	var run := _run()
	var f := _facade(run)
	var net: WorldNetwork = run["net"]
	var parcels_before := RoadDraftCheck.parcel_set_hash(net)
	f.submit_command(P.road(P.spur_a_cm()))
	f.advance(60)
	assert_str(RoadDraftCheck.parcel_set_hash(net)).is_equal(parcels_before)
	# CAN-03: yol komutu bina doğurmaz; gelişen her parselin önünde olumlu, gerekçeli bir yatırımcı kararı vardır.
	var developed := 0
	for v in f.parcel_views(f.parcel_ids()):
		if v.development == &"vacant":
			continue
		developed += 1
		var positives := f.reasons_for(v.ref()).filter(
			func(r: ReasonRecord) -> bool: return r.outcome == &"positive" and r.decision_key == &"decision.investor.develop")
		assert_int(positives.size()).override_failure_message("parsel %d gerekçesiz" % v.id).is_equal(1)
	assert_int(developed).is_greater(0)


func test_a_road_to_a_region_without_demand_builds_nothing_infrastructure_is_not_automatic_building() -> void:
	# SIM-07: kapasite vetosu kalkar ama talep yoksa yatırımcı gelmez; yol bina doğurmaz.
	var quiet := {"initial_households": 1, "infra_capacity_units": 4}
	var run := P.setup(P.SEED, P.economy_patch({String(P.CODE_A): quiet, String(P.CODE_B): quiet}))
	var f := _facade(run)
	f.submit_command(P.road(P.spur_a_cm()))
	f.advance(150)
	for v in f.parcel_views(f.parcel_ids()):
		assert_str(String(v.development)).override_failure_message("parsel %d" % v.id).is_equal("vacant")
	var cleared := 0
	for v in f.parcel_views(f.parcel_ids(P.CODE_A)):
		if v.decision_code == &"demand_too_low" or v.decision_code == &"return_too_low":
			cleared += 1
	assert_int(cleared).override_failure_message("kapasite vetosu kalkmadı").is_greater(0)


func test_region_split_road_credits_each_region_by_its_length() -> void:
	var run := _run()
	var f := _facade(run)
	var cross := PackedInt64Array([142000, 110000, 158000, 100000])  # (1420,1100) -> (1580,1000): x = 1500 sınırını keser
	var r := f.validate_command(P.road(cross))
	assert_str(String(r.status)).override_failure_message(str(r.to_dict())).is_equal("valid")
	# Bölge sınırı raster'da en yakın örneğe göre x = 1450: 35 m D1 (3 birim), 154 m D2 (15 birim).
	assert_dict(r.args["regions"]).is_equal({String(P.CODE_A): 3, String(P.CODE_B): 15})


# --- Olumsuz: her ret anahtarı durumu bozmadan ---

func _assert_rejected(run: Dictionary, command: SimCommand, key: String) -> void:
	var f := _facade(run)
	var net: WorldNetwork = run["net"]
	var hash_before := f.state_hash()
	var graph_before := net.graph_hash()
	for r in [f.validate_command(command), f.submit_command(command)]:
		assert_str(String(r.status)).override_failure_message(str(r.to_dict())).is_equal("rejected")
		assert_str(String(r.reason_key)).is_equal(key)
		assert_int(r.command_id).is_equal(0)
	assert_str(f.state_hash()).is_equal(hash_before)  # reddedilen komut kimlik/kuyruk/durum tüketmez
	assert_str(net.graph_hash()).is_equal(graph_before)
	f.advance(2)
	assert_int(net.delta.ops.size()).is_equal(0)


func test_detached_road_is_rejected_as_not_connected() -> void:
	_assert_rejected(_run(), P.road(P.detached_cm()), "public_work.reject.not_connected")


func test_road_over_the_lake_is_rejected_as_water() -> void:
	_assert_rejected(_run(), P.road(P.lake_cm()), "public_work.reject.water")


func test_drawing_the_same_road_twice_is_rejected_as_duplicate() -> void:
	var existing := PackedInt64Array([110000, 110000, 126000, 110000])  # ızgaranın mevcut kenarı
	_assert_rejected(_run(), P.road(existing), "public_work.reject.duplicate")


func test_road_through_a_parcelled_block_is_rejected_as_crossing_parcels() -> void:
	var diagonal := PackedInt64Array([110000, 110000, 126000, 120000])
	_assert_rejected(_run(), P.road(diagonal), "public_work.reject.crosses_parcels")


func test_too_short_and_too_long_roads_are_rejected_with_their_limits() -> void:
	var run := _run()
	var f := _facade(run)
	var short := f.validate_command(P.road(PackedInt64Array([110000, 110000, 110000, 109000])))
	assert_str(String(short.reason_key)).is_equal("public_work.reject.too_short")
	assert_int(int(short.args["min_m"])).is_equal(12)
	var long := f.validate_command(P.road(PackedInt64Array([110000, 110000, 110000, 60000])))
	assert_str(String(long.reason_key)).is_equal("public_work.reject.too_long")
	assert_int(int(long.args["max_m"])).is_equal(400)


func test_outside_the_jurisdiction_is_rejected() -> void:
	var rules := RoadDraftRules.new()
	rules.jurisdiction_regions = [P.CODE_A]
	var net := P.network()
	var handle := EconomyBootstrap.create(P.SEED, P.source(), EconomyTestSupport.config(P.economy_patch()))
	var ctx := PublicWorksContext.create(net, rules, PublicWorksConfig.load_default())
	handle.facade.attach_public_works(ctx)
	var east := handle.facade.validate_command(P.road(P.spur_b_cm()))
	assert_str(String(east.reason_key)).is_equal("public_work.reject.outside_jurisdiction")
	assert_str(String(handle.facade.validate_command(P.road(P.spur_a_cm())).status)).is_equal("valid")


func test_a_class_without_sim_data_is_rejected_as_bad_class() -> void:
	_assert_rejected(_run(), P.road(P.spur_a_cm(), &"arterial"), "public_work.reject.bad_class")


func test_busy_world_rejects_at_submission_but_never_at_the_tick_boundary() -> void:
	var run := _run()
	var f := _facade(run)
	var ctx: PublicWorksContext = run["ctx"]
	var busy := [true]
	ctx.busy_probe = func() -> bool: return busy[0]
	var r := f.submit_command(P.road(P.spur_a_cm()))
	assert_str(String(r.reason_key)).is_equal("public_work.reject.busy")
	busy[0] = false
	f.submit_command(P.road(P.spur_a_cm()))
	busy[0] = true  # tick sınırında meşgul bayrağı sim sonucunu değiştirmez (yeniden oynatılabilirlik)
	f.advance(1)
	assert_int((run["net"] as WorldNetwork).delta.ops.size()).is_equal(1)


func test_rejection_at_the_tick_boundary_carries_the_same_args_regardless_of_the_busy_flag() -> void:
	var run := _run()
	var f := _facade(run)
	var ctx: PublicWorksContext = run["ctx"]
	f.submit_command(P.road(P.spur_a_cm()))
	f.submit_command(P.road(P.spur_a_cm()))
	ctx.busy_probe = func() -> bool: return true  # tick sınırında meşgul bayrağı sonucu ve argümanları etkilemez
	f.advance(1)
	var rejected := _events(f, &"command.rejected")
	assert_int(rejected.size()).is_equal(1)
	assert_str(String(rejected[0].message_key)).is_equal("public_work.reject.duplicate")
	assert_int(int(rejected[0].args["max_m"])).is_equal(400)
	assert_bool(rejected[0].args.has("kind")).is_true()


func test_shape_violations_use_the_common_command_reject_keys() -> void:
	var f := _facade(_run())
	var odd := f.validate_command(SimCommand.make(&"public_work.road",
		{"points_cm": PackedInt64Array([1, 2, 3]), "road_class": &"local"}))
	assert_str(String(odd.reason_key)).is_equal("command.reject.invalid_value")
	var missing := f.validate_command(SimCommand.make(&"public_work.road", {"road_class": &"local"}))
	assert_str(String(missing.reason_key)).is_equal("command.reject.missing_param")
	var wrong := f.validate_command(SimCommand.make(&"public_work.road",
		{"points_cm": [1, 2, 3, 4], "road_class": &"local"}))
	assert_str(String(wrong.reason_key)).is_equal("command.reject.bad_param_type")
	var extra := f.validate_command(SimCommand.make(&"public_work.undo_last", {"x": 1}))
	assert_str(String(extra.reason_key)).is_equal("command.reject.unknown_param")


func test_negative_coordinates_are_valid_command_data() -> void:
	# Dünya kökeni sıfır olmayabilir: koordinat sıfır/negatif olabilir (parsel kimliği kuralı burada geçerli değildir).
	var cmd := SimCommand.make(&"public_work.road",
		{"points_cm": PackedInt64Array([-500000, 0, -500000, 4000]), "road_class": &"local"})
	assert_bool(cmd.validate_shape().is_empty()).is_true()


func test_second_identical_road_in_the_same_tick_is_rejected_at_the_boundary_with_its_key() -> void:
	var run := _run()
	var f := _facade(run)
	f.submit_command(P.road(P.spur_a_cm()))
	f.submit_command(P.road(P.spur_a_cm()))  # gönderim anında ikisi de geçerli görünür
	f.advance(1)
	assert_int((run["net"] as WorldNetwork).delta.ops.size()).is_equal(1)
	var rejected := _events(f, &"command.rejected")
	assert_int(rejected.size()).is_equal(1)
	assert_str(String(rejected[0].message_key)).is_equal("public_work.reject.duplicate")
	assert_int(rejected[0].command_id).is_equal(2)
	assert_int(f.public_works().size()).is_equal(1)


# --- Geri alma ---

func test_undo_without_a_road_is_rejected() -> void:
	var run := _run()
	var f := _facade(run)
	var before := f.state_hash()
	var r := f.submit_command(SimCommand.public_work_undo_last())
	assert_str(String(r.reason_key)).is_equal("public_work.reject.nothing_to_undo")
	assert_str(f.state_hash()).is_equal(before)


## D-014 §1: klasik geri al YIĞILMAZ. Son yol (B) gidince bir önceki (A) yeni bir yol yapılana kadar geri alınamaz
## (kaldırmanın yolu yıkımdır, `demolish_test.gd`).
func test_undo_removes_the_last_road_and_returns_the_graph_and_capacity() -> void:
	var run := _run()
	var f := _facade(run)
	var net: WorldNetwork = run["net"]
	var base_graph := net.graph_hash()
	f.submit_command(P.road(P.spur_a_cm()))
	f.advance(1)
	f.submit_command(P.road(P.spur_b_cm()))
	f.advance(1)
	assert_int(net.delta.ops.size()).is_equal(2)
	assert_str(String(f.validate_command(SimCommand.public_work_undo_last()).status)).is_equal("valid")
	var undo := f.submit_command(SimCommand.public_work_undo_last())
	assert_str(String(undo.status)).is_equal("queued")
	f.advance(1)
	assert_int(net.delta.ops.size()).is_equal(1)
	assert_dict(f.game_state().systems[SECTION]["infra_bonus"]).is_equal({String(P.CODE_A): 10})  # B'nin payı döndü
	var removed := _events(f, &"public_work.removed")
	assert_int(removed.size()).is_equal(1)
	assert_bool(removed[0].subjects.has("region." + String(P.CODE_B))).is_true()
	assert_int(int(removed[0].args["removed_command_id"])).is_equal(2)
	var second := f.validate_command(SimCommand.public_work_undo_last())  # A artık geri alınamaz
	assert_str(String(second.reason_key)).is_equal("public_work.reject.undo_window_closed")
	f.submit_command(SimCommand.public_work_undo_last())
	f.advance(1)
	assert_int(net.delta.ops.size()).is_equal(1)
	assert_str(net.graph_hash()).is_not_equal(base_graph)  # A yerinde
	assert_dict(f.game_state().systems[SECTION]["infra_bonus"]).is_equal({String(P.CODE_A): 10})
	assert_int(f.public_works().size()).is_equal(1)
	f.submit_command(SimCommand.public_work_demolish(f.public_works()[0].command_id))  # A'yı kaldırmanın yolu yıkım
	f.advance(1)
	assert_str(net.graph_hash()).is_equal(base_graph)
	assert_dict(f.game_state().systems[SECTION]["infra_bonus"]).is_equal({})
	assert_int(f.public_works().size()).is_equal(0)
	assert_str(String(f.validate_command(SimCommand.public_work_undo_last()).reason_key)) \
		.is_equal("public_work.reject.nothing_to_undo")


# --- Determinizm ---

func _scripted(world_seed: int) -> Dictionary:
	var run := P.setup(world_seed)
	var f := _facade(run)
	f.advance(15)
	f.submit_command(P.road(P.spur_a_cm()))
	f.advance(20)
	f.submit_command(P.road(P.spur_b_cm()))
	f.advance(20)
	f.submit_command(SimCommand.public_work_undo_last())
	f.advance(40)
	return run


func test_same_seed_and_commands_give_the_same_state_hash_and_graph_hash() -> void:
	var a := _scripted(P.SEED)
	var b := _scripted(P.SEED)
	assert_str(_facade(a).state_hash()).is_not_empty()
	assert_str(_facade(a).state_hash()).is_equal(_facade(b).state_hash())
	assert_str((a["net"] as WorldNetwork).graph_hash()).is_equal((b["net"] as WorldNetwork).graph_hash())


func test_a_different_command_script_gives_a_different_state_hash() -> void:
	var a := _scripted(P.SEED)
	var other := P.setup(P.SEED)
	_facade(other).advance(15)
	_facade(other).submit_command(P.road(P.spur_b_cm()))
	_facade(other).advance(80)
	assert_str(_facade(other).state_hash()).is_not_equal(_facade(a).state_hash())
