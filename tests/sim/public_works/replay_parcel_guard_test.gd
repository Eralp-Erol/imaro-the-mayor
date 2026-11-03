extends GdUnitTestSuite
## ADR-0005 Ek J takip c: graf aynı kalsa da dünya parsel raporundaki sapma yüklemeyi reddettirir.

const P := preload("res://tests/sim/public_works/public_works_support.gd")
const DIAGONAL: Array[int] = [110000, 110000, 126000, 120000]


## Gerçek ağ yeniden oynatılır; yalnız sınırdan gelen rapora kontrollü sapma enjekte edilir.
class DriftContext extends PublicWorksContext:
	var drift: String = ""
	var injected: int = 0

	func _replay_op(op: Dictionary) -> Dictionary:
		var report := super._replay_op(op)
		if not bool(report["ok"]):
			return report
		if str(op["op"]) == PublicWorksState.OP_REMOVE_EDGE and drift in ["added", "removed"]:
			report["%s_parcels" % drift] = [999999]
			injected += 1
		elif drift == "zero" and bool(op.get("expropriate", false)) and (op.get("taken", []) as Array).is_empty():
			report["removed_parcels"] = PackedInt64Array([999999])
			injected += 1
		return report


func _setup(seed_value: int = P.SEED) -> Dictionary:
	var net := P.network()
	var views: Array[ParcelView] = []
	var ids := net.parcels.keys()
	ids.sort()
	for id: int in ids:
		var parcel: WorldParcel = net.parcels[id]
		var view := ParcelView.new()
		view.id = id
		view.region_code = parcel.region_code
		view.center = parcel.centroid
		view.area_m2 = int(parcel.area)
		view.zone = P.ZONE
		view.land_value = 1000
		views.append(view)
	var handle := EconomyBootstrap.create(seed_value, ListParcelSource.create(&"replay.guard", views),
		EconomyTestSupport.config(P.economy_patch()))
	var ctx := DriftContext.new()
	ctx.net = net
	ctx.rules = RoadDraftRules.new()
	ctx.config = PublicWorksConfig.load_default()
	var rules := RoadDraftRules.from_control({"player_roads": {"crossing_parcels": "expropriate"}})
	ctx.set_expropriation(NetworkExpropriationPort.new(net, rules))
	assert_bool(handle.facade.attach_public_works(ctx)).is_true()
	handle.facade.advance(1)
	return {"facade": handle.facade, "net": net, "ctx": ctx}


func _f(run: Dictionary) -> SimFacadeImpl:
	return run["facade"]


func _do(run: Dictionary, command: SimCommand) -> void:
	var result := _f(run).submit_command(command)
	assert_str(String(result.status)).override_failure_message(String(result.reason_key)).is_equal("queued")
	_f(run).advance(1)


func _zero_taken_save() -> Dictionary:
	var run := _setup()
	_do(run, SimCommand.public_work_road(PackedInt64Array(DIAGONAL), &"local", true))
	_do(run, SimCommand.public_work_demolish(_f(run).public_works()[0].command_id))
	_do(run, SimCommand.public_work_road(PackedInt64Array(DIAGONAL), &"local", true))
	var section := PublicWorksState.data(_f(run).game_state())
	assert_bool(section["ops"].back()["expropriate"]).is_true()
	assert_array(section["ops"].back()["taken"]).is_empty()
	assert_bool(section["works"].back().has("expropriation")).is_false()
	return run


func _assert_rejected_without_mutation(source: Dictionary, drift: String) -> void:
	var target := _setup(P.SEED + 1)
	_do(target, P.road(P.spur_b_cm()))  # farklı mevcut yol: ret, geri yükleme yolunu da sınar
	var before := _f(target).state_hash()
	var net: WorldNetwork = target["net"]
	var world_before := net.state_hash()
	var ctx: DriftContext = target["ctx"]
	ctx.drift = drift
	var loaded := _f(target).import_save(_f(source).export_save())
	assert_int(ctx.injected).is_greater(0)
	assert_bool(loaded.ok).is_false()
	assert_str(String(loaded.error_code)).is_equal("network_mismatch")
	assert_str(_f(target).state_hash()).is_equal(before)
	assert_str(net.state_hash()).is_equal(world_before)
	assert_bool(ctx.tracks(_f(target).game_state())).is_true()


func test_demolition_replay_rejects_added_or_removed_parcels_and_restores_the_live_game() -> void:
	var source := _setup()
	_do(source, P.road(P.spur_a_cm()))
	_do(source, SimCommand.public_work_demolish(_f(source).public_works()[0].command_id))
	for drift in ["added", "removed"]:
		_assert_rejected_without_mutation(source, drift)


func test_zero_taken_pooled_road_replay_rejects_an_unexpected_removal() -> void:
	_assert_rejected_without_mutation(_zero_taken_save(), "zero")


func test_zero_taken_pooled_road_save_load_and_continuation_remain_identical() -> void:
	var source := _zero_taken_save()
	var target := _setup()
	var loaded := _f(target).import_save(_f(source).export_save())
	assert_bool(loaded.ok).override_failure_message(loaded.message).is_true()
	assert_str((target["net"] as WorldNetwork).state_hash()).is_equal((source["net"] as WorldNetwork).state_hash())
	_f(source).advance(40)
	_f(target).advance(40)
	assert_str(_f(target).state_hash()).is_equal(_f(source).state_hash())
