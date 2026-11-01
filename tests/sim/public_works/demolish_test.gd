extends GdUnitTestSuite
## T-042c (D-014 §1) · Yolu YIKMA: her zaman mümkün (klasik geri al penceresi kapandıktan sonra da), bir MALİYETİ vardır
## (gösterge; değer `budget_config.json road.demolish_cost_per_m`) ve geri alma DEĞİLDİR: alınan parseller/yıkılan
## binalar geri gelmez, halk tepkisi silinmez. Yıkılan yol `public_works()`ten çıkar, kapasitesi düşer. Dünya köprüsü
## TEST İKİZİdir (`FakeExpropriationWorld`); gerçek dünya davranışı `demolish_real_world_test.gd`de.

const P := preload("res://tests/sim/public_works/public_works_support.gd")
const B := preload("res://tests/sim/budget/budget_support.gd")
const KEYS := "public_work.reject."
const DIAGONAL: Array[int] = [110000, 110000, 126000, 120000]


func _diag() -> PackedInt64Array:
	return PackedInt64Array(DIAGONAL)


func _setup(world_seed: int = P.SEED, budget: bool = true) -> Dictionary:
	var net := P.network()
	var stock := ListStockSource.create([
		{"parcel_id": 1, "use": "residential", "units": 10, "owner": 1},
		{"parcel_id": 2, "use": "residential", "units": 6, "owner": 1},
		{"parcel_id": 3, "use": "commercial", "units": 4, "owner": 1},
		{"parcel_id": 5, "use": "residential", "units": 8, "owner": 1}])
	var handle := EconomyBootstrap.create(world_seed, P.source(), EconomyTestSupport.config(P.economy_patch()), stock)
	assert_object(handle).is_not_null()
	var ctx := PublicWorksContext.create(net, RoadDraftRules.new(), PublicWorksConfig.load_default())
	var fake := FakeExpropriationWorld.new(net)
	fake.take(_diag(), [1, 2, 3])
	fake.take(P.spur_b_cm(), [5])
	ctx.set_expropriation(fake)
	assert_bool(handle.facade.attach_public_works(ctx)).is_true()
	if budget:
		assert_bool(handle.facade.attach_budget(B.config())).is_true()
	handle.facade.advance(1)
	return {"facade": handle.facade, "net": net, "ctx": ctx, "fake": fake}


func _f(run: Dictionary) -> SimFacadeImpl:
	return run["facade"]


func _build(run: Dictionary, points: PackedInt64Array, expropriate: bool = false) -> CommandResult:
	var r := _f(run).submit_command(SimCommand.public_work_road(points, &"local", expropriate))
	_f(run).advance(1)
	return r


func _demolish(run: Dictionary, command_id: int) -> CommandResult:
	var r := _f(run).submit_command(SimCommand.public_work_demolish(command_id))
	_f(run).advance(1)
	return r


func _kinds(f: SimFacade) -> Array[StringName]:
	var out: Array[StringName] = []
	for e in f.events_since(0):
		out.append(e.kind)
	return out


func _view(f: SimFacadeImpl, id: int) -> ParcelView:
	return f.parcel_views(PackedInt64Array([id]))[0]


func _delta_edges(net: WorldNetwork) -> int:
	var n := 0
	for id: int in net.edges:
		if (net.edges[id] as WorldRoadEdge).layer == WorldRoadEdge.LAYER_DELTA:
			n += 1
	return n


func _cost_per_m() -> int:
	return int(B.raw_config()["road"]["demolish_cost_per_m"])


# --- Plan: düz yol ---

func test_demolishing_a_plain_road_removes_it_and_its_capacity_and_closes_the_undo_window() -> void:
	var run := _setup()
	var f := _f(run)
	var net: WorldNetwork = run["net"]
	var base := net.graph_hash()
	var built := _build(run, P.spur_a_cm())
	assert_int(_delta_edges(net)).is_equal(1)
	assert_int(PublicWorksState.infra_bonus(f.game_state(), P.CODE_A)).is_greater(0)
	assert_bool(f.undo_available()).is_true()
	var demolished := _demolish(run, built.command_id)
	assert_str(String(demolished.status)).is_equal("queued")
	assert_str(net.graph_hash()).is_equal(base)  # ağ yolsuz haline döndü
	assert_int(_delta_edges(net)).is_equal(0)
	assert_int(f.public_works().size()).is_equal(0)
	assert_int(PublicWorksState.infra_bonus(f.game_state(), P.CODE_A)).is_equal(0)
	assert_bool(f.undo_available()).is_false()
	assert_bool(_kinds(f).has(&"public_work.demolished")).is_true()
	assert_array(SimContractChecks.check_facade(f)).is_empty()
	assert_str(PublicWorksState.validate_data(PublicWorksState.data(f.game_state()))).is_empty()


func test_demolition_works_after_the_undo_window_closed_and_leaves_other_roads_alone() -> void:
	var run := _setup()
	var f := _f(run)
	var net: WorldNetwork = run["net"]
	var first := _build(run, P.spur_a_cm())
	var second := _build(run, P.spur_b_cm())
	var closed := f.validate_command(SimCommand.public_work_undo_last())  # son yol geri alınabilir; ilki değil
	assert_int(int(closed.args["removed_command_id"])).is_equal(second.command_id)
	f.submit_command(SimCommand.public_work_undo_last())
	f.advance(1)
	assert_bool(f.undo_available()).is_false()
	var again := _build(run, P.spur_b_cm())  # pencere yeni yola açıldı
	assert_bool(f.undo_available()).is_true()
	# ilk yol artık geri alınamaz ama YIKILABİLİR
	var preview := f.validate_command(SimCommand.public_work_demolish(first.command_id))
	assert_str(String(preview.status)).is_equal("valid")
	_demolish(run, first.command_id)
	assert_int(f.public_works().size()).is_equal(1)
	assert_int(f.public_works()[0].command_id).is_equal(again.command_id)
	assert_int(_delta_edges(net)).is_equal(1)
	assert_int(PublicWorksState.infra_bonus(f.game_state(), P.CODE_A)).is_equal(0)
	assert_int(PublicWorksState.infra_bonus(f.game_state(), P.CODE_B)).is_greater(0)
	assert_bool(f.undo_available()).is_false()  # yıkım da "başka eylem": pencere kapandı


func test_the_preview_names_what_is_demolished_and_that_nothing_comes_back() -> void:
	var run := _setup(P.SEED, false)
	var built := _build(run, P.spur_a_cm())
	var preview := _f(run).validate_command(SimCommand.public_work_demolish(built.command_id))
	assert_int(int(preview.args["target_command_id"])).is_equal(built.command_id)
	assert_int(int(preview.args["length_m"])).is_equal(100)
	assert_int(int(preview.args["edges"])).is_equal(1)
	assert_bool(bool(preview.args["expropriated"])).is_false()
	assert_bool(bool(preview.args["restores_nothing"])).is_true()
	assert_bool(bool(preview.args["cost_available"])).is_false()  # bütçe kurulu değil: dürüst "henüz kurulmadı"
	assert_int(_f(run).demolish_cost(built.command_id)).is_equal(-1)


# --- Maliyet ---

func test_the_cost_is_length_times_the_configured_rate_and_is_booked_once() -> void:
	var run := _setup()
	var f := _f(run)
	var built := _build(run, P.spur_a_cm())
	var length_m := f.public_works()[0].length_cm / 100
	var expected := length_m * _cost_per_m()
	assert_int(expected).is_greater(0)
	var preview := f.validate_command(SimCommand.public_work_demolish(built.command_id))
	assert_bool(bool(preview.args["cost_available"])).is_true()
	assert_int(int(preview.args["cost"])).is_equal(expected)
	assert_int(f.demolish_cost(built.command_id)).is_equal(expected)
	var state := f.game_state()
	var before: Dictionary = BudgetState.data(state).duplicate(true)
	var build_cost := BudgetState.charged_amount(state, built.command_id)
	_demolish(run, built.command_id)
	var after := BudgetState.data(state)
	assert_int(int(after["balance"])).is_equal(int(before["balance"]) - expected)
	assert_int(BudgetState.charged_amount(state, built.command_id)).is_equal(build_cost + expected)  # iade YOK
	assert_int(int(after["roads_net"])).is_equal(int(before["roads_net"]) + expected)
	assert_str(BudgetState.validate_data(after)).is_empty()
	var ledger: Array = after["ledger"]
	assert_str(String((ledger[ledger.size() - 1] as Dictionary)["kind"])).is_equal("road_demolish")
	assert_int(int((ledger[ledger.size() - 1] as Dictionary)["amount"])).is_equal(expected)
	f.advance(40)  # günlük uzlaştırma gideri yeniden yazmaz
	assert_int(int(BudgetState.data(state)["balance"])).is_equal(int(after["balance"]))
	assert_int(f.demolish_cost(built.command_id)).is_equal(-1)  # artık yıkılacak yol yok


func test_demolition_cost_does_not_block_the_command_when_the_treasury_is_empty() -> void:
	var run := _setup(P.SEED, true)
	var f := _f(run)
	var built := _build(run, P.spur_a_cm())
	var state := f.game_state()
	var d := BudgetState.data(state)
	d["balance"] = -1000000  # gösterge bütçe: kasa kısıt değildir
	_demolish(run, built.command_id)
	assert_int(f.public_works().size()).is_equal(0)


# --- Kamulaştırmalı yol: yıkım geri getirmez ---

func test_demolishing_an_expropriating_road_neither_restores_buildings_nor_removes_the_reaction() -> void:
	var run := _setup()
	var f := _f(run)
	var built := _build(run, P.spur_b_cm(), true)  # açık arazide kuzey kolu; sim parsel 5'i (D2) alır
	var state := f.game_state()
	var res_before := StateHash.of(EconomyState.data(state)["regions"]["res_built"])
	var rows_before := PublicWorksState.reaction_rows(state, "displaced", "D2").size()
	assert_int(rows_before).is_equal(1)
	var preview := f.validate_command(SimCommand.public_work_demolish(built.command_id))
	assert_str(String(preview.status)).override_failure_message("%s %s" % [preview.reason_key, preview.args]) \
		.is_equal("valid")
	assert_bool(bool(preview.args["expropriated"])).is_true()
	assert_int(int(preview.args["taken_parcels"])).is_equal(1)
	_demolish(run, built.command_id)
	assert_str(String(_view(f, 5).development)).is_equal("taken")  # bina GERİ GELMEZ
	assert_str(StateHash.of(EconomyState.data(state)["regions"]["res_built"])).is_equal(res_before)
	assert_int(PublicWorksState.reaction_rows(state, "displaced", "D2").size()).is_equal(rows_before)
	assert_int(f.public_works().size()).is_equal(0)
	assert_str(ExpropriationFlow.consistency_problem(state)).is_empty()  # alınan küme kayıtta kalır
	assert_int(PublicWorksState.taken_count(state)).is_equal(1)
	assert_int(PublicWorksState.taken_command(state, 5)).is_equal(built.command_id)
	assert_array(SimContractChecks.check_facade(f)).is_empty()


func test_a_road_whose_removal_would_regenerate_parcels_cannot_be_demolished_and_nothing_changes() -> void:
	var run := _setup()
	var f := _f(run)
	var net: WorldNetwork = run["net"]
	var built := _build(run, _diag(), true)  # parselli bloktan geçen yol: kenarını silmek bloğu yeniden parsellerdi
	var parcels := net.parcels.size()
	var graph := net.graph_hash()
	var hash_before := f.state_hash()
	var r := f.validate_command(SimCommand.public_work_demolish(built.command_id))
	assert_str(String(r.status)).is_equal("rejected")
	assert_str(String(r.reason_key)).is_equal(KEYS + "demolition_changes_parcels")
	assert_int(int(r.args["added_parcels"])).is_greater(0)
	assert_int(net.parcels.size()).is_equal(parcels)  # kuru koşu ağı geri bıraktı
	assert_str(net.graph_hash()).is_equal(graph)
	f.submit_command(SimCommand.public_work_demolish(built.command_id))
	f.advance(1)
	assert_int(f.public_works().size()).is_equal(1)
	assert_str(net.graph_hash()).is_equal(graph)
	assert_int(net.parcels.size()).is_equal(parcels)
	assert_bool(f.undo_available()).is_true()  # reddedilen yıkım pencereyi kapatmaz
	assert_bool(hash_before != f.state_hash()).is_true()  # yalnız tick ilerledi


# --- Olumsuz ---

func test_demolishing_an_unknown_or_already_demolished_road_is_rejected_and_changes_nothing() -> void:
	var run := _setup()
	var f := _f(run)
	var unknown := f.validate_command(SimCommand.public_work_demolish(99))
	assert_str(String(unknown.status)).is_equal("rejected")
	assert_str(String(unknown.reason_key)).is_equal(KEYS + "no_such_road")
	var built := _build(run, P.spur_a_cm())
	_demolish(run, built.command_id)
	var hash_after := f.state_hash()
	var again := f.validate_command(SimCommand.public_work_demolish(built.command_id))
	assert_str(String(again.reason_key)).is_equal(KEYS + "no_such_road")
	f.submit_command(SimCommand.public_work_demolish(built.command_id))
	var rejected_before := f.events_since(0).filter(func(e: SimEvent) -> bool: return e.kind == &"command.rejected").size()
	f.advance(1)
	assert_int(f.events_since(0).filter(func(e: SimEvent) -> bool: return e.kind == &"command.rejected").size()) \
		.is_equal(rejected_before)  # gönderimde reddedildi, kuyruğa girmedi
	assert_bool(f.state_hash() != hash_after).is_true()  # yalnız tick ilerledi
	assert_int(PublicWorksState.data(f.game_state())["works"].size()).is_equal(2)  # yol + 1 yıkım satırı


func test_a_malformed_demolish_command_is_rejected_by_shape() -> void:
	var f := _f(_setup())
	var missing := f.validate_command(SimCommand.make(SimCommand.KIND_PUBLIC_WORK_DEMOLISH, {}))
	assert_str(String(missing.reason_key)).is_equal("command.reject.missing_param")
	var negative := f.validate_command(SimCommand.public_work_demolish(-1))
	assert_str(String(negative.reason_key)).is_equal("command.reject.invalid_value")


func test_demolition_spawns_no_building_and_no_investor_ever_builds_on_the_taken_parcels() -> void:
	var run := _setup()
	var f := _f(run)
	var built := _build(run, P.spur_b_cm(), true)
	_demolish(run, built.command_id)
	f.advance(150)
	for id in [5]:
		assert_str(String(_view(f, id).development)).override_failure_message("parsel %d" % id).is_equal("taken")
		var investors: Array[ReasonRecord] = f.reasons_for(SimContract.parcel_ref(id)).filter(
			func(r: ReasonRecord) -> bool: return String(r.decision_key).begins_with("decision.investor"))
		assert_int(investors.size()).is_equal(0)


# --- Kayıt ve determinizm ---

func test_save_and_load_replays_the_demolition_and_continues_identically() -> void:
	var a := _setup()
	_build(a, P.spur_a_cm())
	var second := _build(a, P.spur_b_cm())
	_demolish(a, _f(a).public_works()[0].command_id)
	_f(a).advance(10)
	var bytes := _f(a).export_save()
	var b := _setup()
	var loaded := _f(b).import_save(bytes)
	assert_bool(loaded.ok).override_failure_message(loaded.message).is_true()
	assert_str(_f(b).state_hash()).is_equal(_f(a).state_hash())
	assert_str((b["net"] as WorldNetwork).graph_hash()).is_equal((a["net"] as WorldNetwork).graph_hash())
	assert_int(_f(b).public_works().size()).is_equal(1)
	assert_int(_f(b).public_works()[0].command_id).is_equal(second.command_id)
	_f(a).advance(40)
	_f(b).advance(40)
	assert_str(_f(b).state_hash()).is_equal(_f(a).state_hash())


func test_a_save_with_a_demolition_row_that_points_at_no_road_is_corrupt() -> void:
	var run := _setup()
	var built := _build(run, P.spur_a_cm())
	_demolish(run, built.command_id)
	var section := PublicWorksState.data(_f(run).game_state())
	assert_str(PublicWorksState.validate_data(section)).is_empty()
	var broken := section.duplicate(true)
	(broken["works"][0] as Dictionary).erase("demolished_by")  # yıkım satırı var, işaret yok
	assert_str(PublicWorksState.validate_data(broken)).is_not_empty()
	var dangling := section.duplicate(true)
	(dangling["works"][1] as Dictionary)["target_command_id"] = 4242
	assert_str(PublicWorksState.validate_data(dangling)).is_not_empty()


func test_same_commands_with_a_demolition_give_the_same_hash_on_five_seeds() -> void:
	for world_seed in [11, 20261030, 3033, 40404, 505050]:
		var hashes: Array[String] = []
		var graphs: Array[String] = []
		for _i in 2:
			var run := _setup(world_seed)
			var first := _build(run, P.spur_a_cm())
			_build(run, P.spur_b_cm(), true)
			_demolish(run, first.command_id)
			_f(run).advance(20)
			hashes.append(_f(run).state_hash())
			graphs.append((run["net"] as WorldNetwork).graph_hash())
		assert_str(hashes[1]).override_failure_message("tohum %d" % world_seed).is_equal(hashes[0])
		assert_str(graphs[1]).is_equal(graphs[0])
