extends GdUnitTestSuite
## B-015 · Yıkılan kamulaştırmalı yolun şeridine yeniden yol çizmek (ADR-0005 Ek J takip d). GERÇEK köprü
## (`NetworkExpropriationPort`) + gerçek facade. Alınanlar dünyaya dönmediği için şerit boştur (`taken` = 0), ama
## birleşen blok parselli olduğundan düz denetim `crosses_parcels` verir: teklif çıkmalı, onaylanınca yol HAVUZLU (0
## alınan) kurulmalı; parsel kimlikleri korunmalı (yeni numara yok, `parcels_changed` yok); geri al/yık döngüsü ve
## kayıt/yükleme bit-eşit olmalı.

const P := preload("res://tests/sim/public_works/public_works_support.gd")
const DIAGONAL: Array[int] = [110000, 110000, 126000, 120000]


func _diag() -> PackedInt64Array:
	return PackedInt64Array(DIAGONAL)


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
	var handle := EconomyBootstrap.create(world_seed, ListParcelSource.create(&"b015.real_world", views),
		EconomyTestSupport.config(P.economy_patch()), ListStockSource.create(rows))
	assert_object(handle).is_not_null()
	var rules := RoadDraftRules.from_control({"player_roads": {"crossing_parcels": "expropriate"}})
	var ctx := PublicWorksContext.create(net, RoadDraftRules.new(), PublicWorksConfig.load_default())
	ctx.set_expropriation(NetworkExpropriationPort.new(net, rules))
	assert_bool(handle.facade.attach_public_works(ctx)).is_true()
	assert_bool(handle.facade.attach_budget(BudgetConfig.load_default())).is_true()
	handle.facade.advance(1)
	return {"facade": handle.facade, "net": net, "taken": taken}


func _f(run: Dictionary) -> SimFacadeImpl:
	return run["facade"]


## Kamulaştırmalı yolu çizer, yıkar. Dönüş: yıkım sonrası serbest şeritli koşu.
func _freed_strip() -> Dictionary:
	var run := _setup()
	var f := _f(run)
	f.submit_command(SimCommand.public_work_road(_diag(), &"local", true))
	f.advance(1)
	assert_int(f.public_works().size()).is_equal(1)
	f.submit_command(SimCommand.public_work_demolish(f.public_works()[0].command_id))
	f.advance(1)
	assert_int(f.public_works().size()).is_equal(0)
	return run


func _redraw(expropriate: bool) -> SimCommand:
	return SimCommand.public_work_road(_diag(), &"local", expropriate)


func test_redrawing_over_the_freed_strip_is_valid_and_offers_a_zero_parcel_proposal() -> void:
	var run := _freed_strip()
	var f := _f(run)
	var net: WorldNetwork = run["net"]
	assert_int(NetworkExpropriation.taken_parcels(net, RoadDraftCheck.points_from_cm(_diag()),
		net.rules.width_of(&"local")).size()).is_equal(0)  # şerit gerçekten boş
	var asked := f.validate_command(_redraw(true))
	assert_str(String(asked.status)).override_failure_message("%s %s" % [asked.reason_key, asked.args]).is_equal("valid")
	assert_int(int(asked.args["taken_parcels"])).is_equal(0)
	var plain := f.validate_command(_redraw(false))
	assert_str(String(plain.reason_key)).is_equal("public_work.reject.crosses_parcels")
	assert_bool(plain.args.has("taken_parcels")).override_failure_message("teklif çıkmadı: %s" % plain.args).is_true()
	assert_int(int(plain.args["taken_parcels"])).is_equal(0)


func test_confirming_the_proposal_builds_the_road_and_keeps_every_parcel_identity() -> void:
	var run := _freed_strip()
	var f := _f(run)
	var net: WorldNetwork = run["net"]
	var before := net.parcels.duplicate()
	var counter: int = NetworkRestore.counters(net)["parcel"]
	var r := f.submit_command(_redraw(true))
	assert_str(String(r.status)).override_failure_message("%s %s" % [r.reason_key, r.args]).is_equal("queued")
	f.advance(1)
	assert_int(f.public_works().size()).is_equal(1)
	assert_int(f.public_works()[0].taken_parcel_ids.size()).is_equal(0)
	assert_bool(f.public_works()[0].expropriated).is_false()  # alınan yok: sim kaydı düz yol
	var op: Dictionary = net.delta.ops[net.delta.ops.size() - 1]
	assert_bool(bool(op.get("expropriate", false))).override_failure_message("yol havuzlu kurulmadı").is_true()
	assert_array(op["taken"]).is_empty()
	assert_array(net.parcels.keys()).contains_exactly_in_any_order(before.keys())  # ne yeni ne kayıp
	for pid: int in before:
		assert_object(net.parcels[pid]).is_same(before[pid])
	assert_int(NetworkRestore.counters(net)["parcel"]).is_equal(counter)  # yeni numara harcanmadı
	assert_array(NetworkInvariants.check_parcels(net)).is_empty()
	assert_array(NetworkInvariants.check_graph_integrity(net)).is_empty()
	assert_bool(f.undo_available()).is_true()
	assert_str(BudgetState.validate_data(BudgetState.data(f.game_state()))).is_empty()


func test_undoing_the_redrawn_road_returns_the_world_bit_exactly_and_the_cycle_repeats() -> void:
	var run := _freed_strip()
	var f := _f(run)
	var net: WorldNetwork = run["net"]
	var state_before := net.state_hash()
	var graph_before := net.graph_hash()
	f.submit_command(_redraw(true))
	f.advance(1)
	assert_str(net.graph_hash()).is_not_equal(graph_before)
	f.submit_command(SimCommand.public_work_undo_last())
	f.advance(1)
	assert_str(net.state_hash()).is_equal(state_before)
	assert_str(net.graph_hash()).is_equal(graph_before)
	f.submit_command(_redraw(true))  # geri al -> yeniden çiz -> yık -> yeniden çiz
	f.advance(1)
	assert_int(f.public_works().size()).is_equal(1)
	var parcels := net.parcels.keys()
	f.submit_command(SimCommand.public_work_demolish(f.public_works()[0].command_id))
	f.advance(1)
	assert_int(f.public_works().size()).is_equal(0)
	assert_str(net.graph_hash()).is_equal(graph_before)
	assert_array(net.parcels.keys()).contains_exactly_in_any_order(parcels)
	f.submit_command(_redraw(true))
	f.advance(1)
	assert_int(f.public_works().size()).is_equal(1)
	assert_array(NetworkInvariants.check_parcels(net)).is_empty()


func test_save_and_load_after_the_redraw_is_hash_equal_and_continues_identically() -> void:
	var a := _freed_strip()
	var f := _f(a)
	f.submit_command(_redraw(true))
	f.advance(10)
	assert_int(f.public_works().size()).is_equal(1)
	var bytes := f.export_save()
	var b := _setup()
	var loaded := _f(b).import_save(bytes)
	assert_bool(loaded.ok).override_failure_message(loaded.message).is_true()
	assert_str(_f(b).state_hash()).is_equal(f.state_hash())
	var net_a: WorldNetwork = a["net"]
	var net_b: WorldNetwork = b["net"]
	assert_str(net_b.graph_hash()).is_equal(net_a.graph_hash())
	assert_str(net_b.state_hash()).is_equal(net_a.state_hash())
	assert_array(net_b.parcels.keys()).contains_exactly_in_any_order(net_a.parcels.keys())
	f.advance(40)
	_f(b).advance(40)
	assert_str(_f(b).state_hash()).is_equal(f.state_hash())
