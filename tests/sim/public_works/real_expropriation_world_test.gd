extends GdUnitTestSuite
## T-042b dünya adımı · sim <-> GERÇEK dünya bağdaştırıcısı (`NetworkExpropriationPort`): test ikizi
## (FakeExpropriationWorld)
## yerine gerçek `WorldNetwork` kamulaştırması. Sim parsel kimliği = dünya parsel kimliği: sim görünümleri ağın gerçek
## parsellerinden kurulur; yolun aldığı küme DÜNYANIN geometri hesabıdır. Komut -> tick -> olay -> geri alma ->
## kayıt/yükleme
## ve 5 tohumda aynı durum + graf özeti.

const P := preload("res://tests/sim/public_works/public_works_support.gd")
const SEEDS: Array[int] = [11, 20261030, 3033, 40404, 505050]
## Izgaranın bir bloğunu köşegen kesen yol (cm): GRID_ORIGIN -> bir blok ötesi.
const DIAGONAL: Array[int] = [110000, 110000, 126000, 120000]


func _diag() -> PackedInt64Array:
	return PackedInt64Array(DIAGONAL)


## Ağ + ağın GERÇEK parsellerinden sim kaynağı; alınacak parsellerin hepsi konutlu, ayrıca iki komşu parsel stokta.
func _setup(world_seed: int = P.SEED) -> Dictionary:
	var net := P.network()
	var views: Array[ParcelView] = []
	var ids: Array = net.parcels.keys()
	ids.sort()
	for pid: int in ids:
		var wp: WorldParcel = net.parcels[pid]
		var v := ParcelView.new()
		v.id = pid
		v.region_code = wp.region_code
		v.center = wp.centroid
		v.area_m2 = int(wp.area)
		v.zone = P.ZONE
		v.land_value = 1000
		views.append(v)
	var taken := RoadDraftCheck.taken_parcels(net, RoadDraftCheck.points_from_cm(_diag()), &"local")
	var rows: Array = []
	for id in taken:
		rows.append({"parcel_id": int(id), "use": "residential", "units": 6, "owner": 1})
	var spare := 0
	for pid: int in ids:
		if not taken.has(pid) and spare < 2:
			rows.append({"parcel_id": pid, "use": "residential", "units": 4, "owner": 1})
			spare += 1
	var handle := EconomyBootstrap.create(world_seed, ListParcelSource.create(&"t042b.real_world", views),
		EconomyTestSupport.config(P.economy_patch()), ListStockSource.create(rows))
	assert_object(handle).is_not_null()
	var rules := RoadDraftRules.from_control({"player_roads": {"crossing_parcels": "expropriate"}})
	var ctx := PublicWorksContext.create(net, RoadDraftRules.new(), PublicWorksConfig.load_default())
	var port := NetworkExpropriationPort.new(net, rules)
	assert_bool(port.available()).is_true()
	ctx.set_expropriation(port)
	assert_bool(handle.facade.attach_public_works(ctx)).is_true()
	handle.facade.advance(1)
	return {"facade": handle.facade, "net": net, "ctx": ctx, "taken": taken, "views": views, "rows": rows}


func _f(run: Dictionary) -> SimFacadeImpl:
	return run["facade"]


func _road() -> SimCommand:
	return SimCommand.public_work_road(_diag(), &"local", true)


func _view(f: SimFacadeImpl, id: int) -> ParcelView:
	return f.parcel_views(PackedInt64Array([id]))[0]


func _take(run: Dictionary) -> CommandResult:
	var r := _f(run).submit_command(_road())
	_f(run).advance(1)
	return r


func test_plain_road_is_still_rejected_and_the_offer_comes_from_the_real_world() -> void:
	var run := _setup()
	var r := _f(run).validate_command(SimCommand.public_work_road(_diag(), &"local", false))
	assert_str(String(r.reason_key)).is_equal("public_work.reject.crosses_parcels")
	var taken: PackedInt64Array = run["taken"]
	assert_int(taken.size()).is_greater(0)
	assert_int(int(r.args["taken_parcels"])).is_equal(taken.size())  # teklif = dünyanın hesabı
	assert_int(int(r.args["taken_built_parcels"])).is_equal(taken.size())
	var asked := _f(run).validate_command(_road())
	assert_str(String(asked.status)).is_equal("valid")
	assert_int(int(asked.args["taken_parcels"])).is_equal(taken.size())


func test_the_real_world_takes_exactly_the_previewed_set_and_sim_marks_the_same_ids() -> void:
	var run := _setup()
	var f := _f(run)
	var net: WorldNetwork = run["net"]
	var taken: PackedInt64Array = run["taken"]
	var total_before := net.parcels.size()
	var r := _take(run)
	assert_str(String(r.status)).is_equal("queued")
	assert_int(net.parcels.size()).is_equal(total_before - taken.size())
	var work := f.public_works()[0]
	assert_array(Array(work.taken_parcel_ids)).is_equal(Array(taken))
	assert_int(work.taken_built_parcels).is_equal(taken.size())
	for id in taken:
		assert_object(net.parcel(id)).is_null()
		assert_str(String(_view(f, id).development)).is_equal("taken")
	var op := net.peek_last_op()
	assert_bool(op["expropriate"]).is_true()
	assert_array(op["taken"]).is_equal(Array(taken))
	assert_array(NetworkInvariants.check_parcels(net)).is_empty()
	var expropriated := f.events_since(0).filter(func(e: SimEvent) -> bool: return e.kind == &"public_work.expropriated")
	assert_array(expropriated).has_size(1)


func test_undo_gives_the_buildings_and_the_parcels_back_with_their_identity() -> void:
	var run := _setup()
	var f := _f(run)
	var net: WorldNetwork = run["net"]
	var state := net.state_hash()
	var graph := net.graph_hash()
	var taken: PackedInt64Array = run["taken"]
	var sim_before := f.state_hash()
	_take(run)
	assert_str(net.graph_hash()).is_not_equal(graph)
	f.submit_command(SimCommand.public_work_undo_last())
	f.advance(1)
	assert_str(net.state_hash()).is_equal(state)
	assert_str(net.graph_hash()).is_equal(graph)
	assert_int(f.public_works().size()).is_equal(0)
	for id in taken:
		assert_object(net.parcel(id)).is_not_null()
		assert_str(String(_view(f, id).development)).is_not_equal("taken")
	assert_str(f.state_hash()).is_not_equal(sim_before)  # halk tepkisi geri gelmez (D-011): durum aynı DEĞİL


func test_save_and_load_replays_the_real_expropriating_road_and_continues_identically() -> void:
	var a := _setup()
	_take(a)
	_f(a).advance(20)
	var bytes := _f(a).export_save()
	var b := _setup()
	var loaded := _f(b).import_save(bytes)
	assert_bool(loaded.ok).override_failure_message(loaded.message).is_true()
	assert_str(_f(b).state_hash()).is_equal(_f(a).state_hash())
	assert_str((b["net"] as WorldNetwork).graph_hash()).is_equal((a["net"] as WorldNetwork).graph_hash())
	assert_str((b["net"] as WorldNetwork).state_hash()).is_equal((a["net"] as WorldNetwork).state_hash())
	_f(a).advance(60)
	_f(b).advance(60)
	assert_str(_f(b).state_hash()).is_equal(_f(a).state_hash())


func test_five_seeds_give_the_same_sim_state_and_the_same_graph_digest() -> void:
	for world_seed in SEEDS:
		var a := _setup(world_seed)
		var b := _setup(world_seed)
		_take(a)
		_take(b)
		_f(a).advance(40)
		_f(b).advance(40)
		assert_str(_f(a).state_hash()).override_failure_message("tohum %d" % world_seed).is_equal(_f(b).state_hash())
		assert_str((a["net"] as WorldNetwork).graph_hash()).is_equal((b["net"] as WorldNetwork).graph_hash())
		assert_str((a["net"] as WorldNetwork).state_hash()).is_equal((b["net"] as WorldNetwork).state_hash())
