extends GdUnitTestSuite
## T-043C ölçüt 4 (OLUMSUZ test) · Kasa YALNIZ gösterge: sıfırın altına inse de hiçbir komut reddedilmez, kısıt yoktur.
## CAN-03: komut beyaz listesi değişmez; `budget.propose` kurulmaz.

const B := preload("res://tests/sim/budget/budget_support.gd")
const P := preload("res://tests/sim/public_works/public_works_support.gd")
const BROKE := {"initial_balance": 0}


func _applied(f: SimFacadeImpl, command_id: int) -> bool:
	for e in f.events_since(0):
		if e.kind == SimEvent.KIND_COMMAND_APPLIED and e.command_id == command_id:
			return true
	return false


func _rejected(f: SimFacadeImpl, command_id: int) -> bool:
	for e in f.events_since(0):
		if e.kind == SimEvent.KIND_COMMAND_REJECTED and e.command_id == command_id:
			return true
	return false


func test_roads_are_accepted_and_applied_while_the_treasury_is_negative() -> void:
	var run := B.road_run(P.SEED, BROKE)
	var f: SimFacadeImpl = run["facade"]
	f.advance(2)
	var first := f.submit_command(P.road(P.spur_a_cm()))
	assert_str(String(first.status)).is_equal("queued")
	f.advance(1)
	assert_int(f.snapshot().budget.balance).is_less(0)
	assert_bool(_applied(f, first.command_id)).is_true()
	# kasa negatifken ikinci yol ve geri alma da reddedilmez
	assert_str(String(f.validate_command(P.road(P.spur_b_cm())).status)).is_equal("valid")
	var second := f.submit_command(P.road(P.spur_b_cm()))
	assert_str(String(second.status)).is_equal("queued")
	f.advance(1)
	assert_bool(_applied(f, second.command_id)).is_true()
	assert_bool(_rejected(f, second.command_id)).is_false()
	assert_int(f.public_works().size()).is_equal(2)
	assert_int(f.snapshot().budget.balance).is_less(0)
	var undo := f.submit_command(SimCommand.public_work_undo_last())
	assert_str(String(undo.status)).is_equal("queued")
	f.advance(1)
	assert_bool(_applied(f, undo.command_id)).is_true()


func test_zoning_proposals_are_not_blocked_by_a_negative_treasury() -> void:
	var run := B.road_run(P.SEED, {"initial_balance": -500000})
	var f: SimFacadeImpl = run["facade"]
	f.advance(2)
	assert_int(f.snapshot().budget.balance).is_less(0)
	var parcel := f.parcel_ids(P.CODE_A)[0]
	var result := f.submit_command(SimCommand.zoning_propose(PackedInt64Array([parcel]), &"zone.mixed"))
	assert_str(String(result.status)).is_equal("queued")
	f.advance(1)
	assert_bool(_applied(f, result.command_id)).is_true()


func test_budget_propose_stays_unbuilt_and_private_building_verbs_stay_forbidden() -> void:
	var run := B.road_run()
	var f: SimFacadeImpl = run["facade"]
	var propose := f.validate_command(SimCommand.budget_propose({&"budget.line.roads": 10}))
	assert_str(String(propose.status)).is_equal("rejected")
	assert_str(String(propose.reason_key)).is_equal("command.reject.precondition")
	assert_str(String(propose.args.get("why", ""))).is_equal("system.not_built")
	for kind in [&"building.construct", &"private.invest", &"spawn.building"]:
		var forbidden := f.validate_command(SimCommand.make(kind, {}))
		assert_str(String(forbidden.reason_key)).is_equal("command.reject.not_a_mayor_verb")


func test_budget_never_spawns_buildings_without_a_demand_decision() -> void:
	# SIM-07/CAN-03: bütçeli ve bütçesiz koşuda aynı (komutsuz) tohumla aynı parsel durumu; bütçe bina üretmez.
	var a := B.road_run(P.SEED, BROKE)["facade"] as SimFacadeImpl
	var b := B.road_run(P.SEED, {}, false)["facade"] as SimFacadeImpl
	a.advance(120)
	b.advance(120)
	for f in [a, b]:
		for v in f.parcel_views(f.parcel_ids()):
			assert_str(String(v.development)).is_equal("vacant")
