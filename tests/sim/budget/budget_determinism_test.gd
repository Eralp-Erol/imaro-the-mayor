extends GdUnitTestSuite
## T-043C ölçüt 5 · Bütçe bölümü YALNIZ yazıldığında durum yaratılır. Bütçesiz yapılandırmada durum/özet DEĞİŞMEZ
## (altın değerler tests/sim/m2_query_test.gd bu görevde değişmedi); bütçeli koşuda hash yeni ama tekrar oynatmada eşit;
## kayıt/yükleme kesintisiz koşuyla bit-bit aynı; bozuk bölüm yüklenmez.

const B := preload("res://tests/sim/budget/budget_support.gd")
const P := preload("res://tests/sim/public_works/public_works_support.gd")
const TAIL := 70


func _scenario(world_seed: int, attach: bool) -> SimFacadeImpl:
	var f := B.road_run(world_seed, {}, attach)["facade"] as SimFacadeImpl
	f.advance(10)
	f.submit_command(P.road(P.spur_a_cm()))
	f.advance(25)
	f.submit_command(P.road(P.spur_b_cm()))
	f.advance(10)
	f.submit_command(SimCommand.public_work_undo_last())
	f.advance(40)
	return f


func test_no_budget_section_exists_until_a_budget_is_attached_and_a_tick_runs() -> void:
	var plain := B.road_run(P.SEED, {}, false)["facade"] as SimFacadeImpl
	plain.advance(70)
	assert_bool(plain.game_state().systems.has("budget")).is_false()
	assert_bool(bool(plain.snapshot().extensions["x.sim.available.budget"])).is_false()
	assert_int(plain.snapshot().budget.lines.size()).is_equal(0)
	var attached := B.road_run()["facade"] as SimFacadeImpl
	assert_bool(attached.game_state().systems.has("budget")).is_false()  # t0: bölüm yok
	assert_bool(bool(attached.snapshot().extensions["x.sim.available.budget"])).is_true()
	attached.advance(1)
	assert_bool(attached.game_state().systems.has("budget")).is_true()


func test_t0_hash_is_identical_with_and_without_a_budget_attached() -> void:
	var plain := B.road_run(P.SEED, {}, false)["facade"] as SimFacadeImpl
	var attached := B.road_run()["facade"] as SimFacadeImpl
	assert_str(plain.state_hash()).is_equal(attached.state_hash())


func test_budget_run_replays_to_the_same_hash_and_differs_from_the_budgetless_run() -> void:
	for world_seed in [11, 20261030, 3033]:
		var one := _scenario(world_seed, true)
		var two := _scenario(world_seed, true)
		assert_str(one.state_hash()).is_not_empty()
		assert_str(one.state_hash()).override_failure_message("tohum %d" % world_seed).is_equal(two.state_hash())
		assert_str(_scenario(world_seed, false).state_hash()).is_not_equal(one.state_hash())


func test_different_commands_give_a_different_budget_hash() -> void:
	var a := _scenario(P.SEED, true)
	var b := B.road_run()["facade"] as SimFacadeImpl
	b.advance(115)
	assert_str(b.state_hash()).is_not_equal(a.state_hash())


func test_save_load_continues_to_the_same_hash_as_an_uninterrupted_run() -> void:
	var straight := _scenario(P.SEED, true)
	straight.advance(TAIL)
	var first := _scenario(P.SEED, true)
	var bytes := first.export_save()
	var view_before := first.snapshot().budget.to_dict()
	var fresh := B.road_run()["facade"] as SimFacadeImpl
	var result := fresh.import_save(bytes)
	assert_bool(result.ok).override_failure_message(result.message).is_true()
	assert_dict(fresh.snapshot().budget.to_dict()).is_equal(view_before)
	fresh.advance(TAIL)
	assert_str(fresh.state_hash()).is_equal(straight.state_hash())
	assert_dict(fresh.snapshot().budget.to_dict()).is_equal(straight.snapshot().budget.to_dict())


func test_a_corrupt_budget_section_is_rejected_and_the_old_state_survives() -> void:
	var source := _scenario(P.SEED, true)
	var envelope: Dictionary = bytes_to_var(source.export_save())
	var body: Dictionary = envelope["state"]
	(body["systems"]["budget"] as Dictionary)["balance"] = "çok"
	envelope["state_hash"] = StateHash.of(body)
	var target := B.road_run()["facade"] as SimFacadeImpl
	target.advance(3)
	var before := target.state_hash()
	var result := target.import_save(var_to_bytes(envelope))
	assert_bool(result.ok).is_false()
	assert_str(String(result.error_code)).is_equal("corrupt")
	assert_str(target.state_hash()).is_equal(before)


func test_charged_list_that_disagrees_with_the_roads_is_rejected() -> void:
	var source := _scenario(P.SEED, true)
	var envelope: Dictionary = bytes_to_var(source.export_save())
	var body: Dictionary = envelope["state"]
	(body["systems"]["budget"] as Dictionary)["roads_net"] = 12345  # kalemlerin toplamıyla tutmuyor
	envelope["state_hash"] = StateHash.of(body)
	var target := B.road_run()["facade"] as SimFacadeImpl
	assert_str(String(target.import_save(var_to_bytes(envelope)).error_code)).is_equal("corrupt")
