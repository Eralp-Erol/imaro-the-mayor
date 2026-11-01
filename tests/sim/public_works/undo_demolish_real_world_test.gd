extends GdUnitTestSuite
## T-042c (D-014 §1) · Klasik geri al ve yıkma, GERÇEK dünya köprüsüyle (`NetworkExpropriationPort`, gerçek
## `WorldNetwork` parselleri). Geri alma: ağ/parsel durumu ve ekonomi hiç yol yapılmamış koşuyla aynı, tepki defteri
## boş. Yıkma: düz yol kalkar; kamulaştırmalı yolun kenarını silmek dünyanın parsellerini yeniden üretirdi -> yıkım
## REDDEDİLİR, hiçbir şey değişmez (sim parsel kümesi sabit; world-engineer takibi: parsel kimliklerini koruyan
## birleştirme).

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
	var handle := EconomyBootstrap.create(world_seed, ListParcelSource.create(&"t042c.real_world", views),
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


## Alınan parsellerin ekonomi satırları (geri alma bunları yoldan önceki haline getirmelidir).
func _rows_of(f: SimFacadeImpl, ids: PackedInt64Array) -> Array:
	var d := EconomyState.data(f.game_state())
	var out: Array = []
	for id in ids:
		var i := EconomyState.index_of(d, id)
		out.append([id, d["stage"][i], d["use"][i], d["units"][i], d["owner_id"][i], d["days_left"][i],
			d["next_review"][i], d["last_code"][i]])
	return out


func test_undoing_the_real_expropriating_road_restores_the_world_and_the_taken_parcels_exactly() -> void:
	var run := _setup()
	var f := _f(run)
	var net: WorldNetwork = run["net"]
	var control := _setup()  # hiç yol yapılmayan eşlenik koşu
	var net_state := net.state_hash()
	var graph := net.graph_hash()
	var parcels := net.parcels.size()
	var rows_before := _rows_of(f, run["taken"])
	f.submit_command(SimCommand.public_work_road(_diag(), &"local", true))
	f.advance(1)
	assert_int(net.parcels.size()).is_less(parcels)
	var rows_during := PublicWorksState.reaction_rows(f.game_state(), "displaced", "D1").size() \
		+ PublicWorksState.reaction_rows(f.game_state(), "displaced", "D2").size()
	assert_int(rows_during).is_equal(1)
	f.submit_command(SimCommand.public_work_undo_last())
	f.advance(1)
	_f(control).advance(2)
	assert_str(net.state_hash()).is_equal(net_state)  # dünya: bit-bit aynı
	assert_str(net.graph_hash()).is_equal(graph)
	assert_int(net.parcels.size()).is_equal(parcels)
	# Alınan parsellerin satırları yoldan önceki haliyle aynı. NOT: yol ayaktayken yatırımcılar (özel aktörler) artan
	# kapasiteye bakıp BAŞKA parsellerde proje başlatmış olabilir; belediye özel kararı iptal edemez (CAN-03), bu yüzden
	# bölge toplamları kontrol koşusundan farklı olabilir. Fark yalnız alınmayan parsellerdedir.
	assert_array(_rows_of(f, run["taken"])).is_equal(rows_before)
	var d := EconomyState.data(f.game_state())
	var control_d := EconomyState.data(_f(control).game_state())
	for id in run["taken"]:
		assert_int(int(d["stage"][EconomyState.index_of(d, id)])).is_equal(
			int(control_d["stage"][EconomyState.index_of(control_d, id)]))
	print("UNDO_HASHES net_before=%s net_after=%s graph_before=%s graph_after=%s" %
		[net_state.substr(0, 12), net.state_hash().substr(0, 12), graph.substr(0, 12), net.graph_hash().substr(0, 12)])
	for id in run["taken"]:
		assert_object(net.parcel(id)).is_not_null()
		assert_str(String(f.parcel_views(PackedInt64Array([id]))[0].development)).is_not_equal("taken")
	assert_dict(PublicWorksState.data(f.game_state())["displaced"]).is_empty()
	assert_dict(PublicWorksState.data(f.game_state())["nearby"]).is_empty()
	assert_bool(f.undo_available()).is_false()
	assert_str(BudgetState.validate_data(BudgetState.data(f.game_state()))).is_empty()
	assert_int(int(BudgetState.data(f.game_state())["roads_net"])).is_equal(0)  # yapım gideri geri alınınca iade


func test_a_real_expropriating_road_cannot_be_demolished_because_the_world_would_reparcel() -> void:
	var run := _setup()
	var f := _f(run)
	var net: WorldNetwork = run["net"]
	f.submit_command(SimCommand.public_work_road(_diag(), &"local", true))
	f.advance(1)
	var road_id := f.public_works()[0].command_id
	var graph := net.graph_hash()
	var net_state := net.state_hash()
	var r := f.validate_command(SimCommand.public_work_demolish(road_id))
	assert_str(String(r.status)).is_equal("rejected")
	assert_str(String(r.reason_key)).is_equal("public_work.reject.demolition_changes_parcels")
	assert_int(int(r.args["added_parcels"])).is_greater(0)
	assert_str(net.state_hash()).is_equal(net_state)  # kuru koşu ağı bıraktığı gibi geri koydu
	f.submit_command(SimCommand.public_work_demolish(road_id))
	f.advance(1)
	assert_str(net.graph_hash()).is_equal(graph)
	assert_int(f.public_works().size()).is_equal(1)
	assert_int(f.demolish_cost(road_id)).is_equal(-1)
	assert_bool(f.undo_available()).is_true()  # reddedilen yıkım pencereyi kapatmadı
	assert_array(NetworkInvariants.check_parcels(net)).is_empty()


func test_a_real_plain_road_is_demolished_and_the_network_returns_to_the_base() -> void:
	var run := _setup()
	var f := _f(run)
	var net: WorldNetwork = run["net"]
	var net_state := net.state_hash()
	var parcels := net.parcels.size()
	f.submit_command(SimCommand.public_work_road(P.spur_a_cm(), &"local"))
	f.advance(1)
	var road_id := f.public_works()[0].command_id
	var build_cost := BudgetState.charged_amount(f.game_state(), road_id)
	f.submit_command(SimCommand.public_work_demolish(road_id))
	f.advance(1)
	assert_int(f.public_works().size()).is_equal(0)
	assert_str(net.state_hash()).is_equal(net_state)
	assert_int(net.parcels.size()).is_equal(parcels)
	assert_int(BudgetState.charged_amount(f.game_state(), road_id)).is_greater(build_cost)  # yapım + yıkım gideri
	assert_str(BudgetState.validate_data(BudgetState.data(f.game_state()))).is_empty()
