extends "res://tests/sim/politics/politics_test_base.gd"
## T-066 bağımsız QA: gerçek ağ, ekonomi, siyaset ve bütçe; yalnız veri başlangıç koşulları denetlenir.

const LAND_P := preload("res://tests/sim/public_works/public_works_support.gd")
const LAND_DIAGONAL: Array[int] = [110000, 110000, 126000, 120000]
const LAND_AXIS := "growth_vs_preservation"
const LAND_COUNCIL: Array[String] = [COUNCIL_1, COUNCIL_2, COUNCIL_3, COUNCIL_4, COUNCIL_5]


func _land_points() -> PackedInt64Array:
	return PackedInt64Array(LAND_DIAGONAL)


## council_mode: direct | pass | fail. Eşik yalnız testte değiştirilir; canlı veriye yazılmaz.
func _land_setup(council_mode: String = "direct", seed_value: int = LAND_P.SEED,
		isolate_investment: bool = false) -> Dictionary:
	var net := LAND_P.network()
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
		view.zone = LAND_P.ZONE
		view.land_value = 1000
		views.append(view)
	var taken := RoadDraftCheck.taken_parcels(net, RoadDraftCheck.points_from_cm(_land_points()), &"local")
	var stock_rows: Array = []
	for id in taken:
		stock_rows.append({"parcel_id": int(id), "use": "residential", "units": 6, "owner": 1})
	var edit := func(files: Dictionary) -> void:
		files["council"]["requires_council"]["zoning.propose"] = council_mode != "direct"
		files["council"]["plan_council_min_parcels"] = 1
		files["council"]["plan_council_min_units"] = 0
		files["council"]["proposal_axes"] = {"zoning": {
			"zone.mixed": {LAND_AXIS: -1000}, "zone.green": {LAND_AXIS: -1000}}}
		files["council"]["proposal_effects"] = {"zoning": {"zone.mixed": {}, "zone.green": {}}}
	var source := ListParcelSource.create(&"municipal_land.qa", views)
	var economy_patch := LAND_P.economy_patch({
		String(LAND_P.CODE_A): E.favorable(), String(LAND_P.CODE_B): E.favorable()})
	if isolate_investment:
		economy_patch["decision"] = {"review_enabled": 0}
	var economy_cfg := E.config(economy_patch)
	var h := PoliticsBootstrap.create(seed_value, source, economy_cfg, ListStockSource.create(stock_rows),
		config(), pol_valid(edit, config()))
	assert_object(h).is_not_null()
	var works_raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PublicWorksConfig.DEFAULT_PATH))
	works_raw["expropriation"]["household_fate"] = "leave_region"
	var ctx := PublicWorksContext.create(net, RoadDraftRules.new(), PublicWorksConfig.from_dict(works_raw))
	var rules := RoadDraftRules.from_control({"player_roads": {"crossing_parcels": "expropriate"}})
	ctx.set_expropriation(NetworkExpropriationPort.new(net, rules))
	assert_bool(h.facade.attach_public_works(ctx)).is_true()
	assert_bool(h.facade.attach_budget(BudgetConfig.load_default())).is_true()
	h.facade.advance(1)
	for member in LAND_COUNCIL:
		if ActorStore.has_actor(h.state(), member):
			ActorStore.actor_ref(h.state(), member)["stance"][LAND_AXIS] = 1000 if council_mode == "fail" else -1000
	return {"handle": h, "net": net, "ctx": ctx, "taken": taken, "stock": stock_rows}


func _land_f(run: Dictionary) -> SimFacadeImpl:
	return (run["handle"] as PoliticsHandle).facade as SimFacadeImpl


func _land_do(run: Dictionary, command: SimCommand) -> CommandResult:
	var result := _land_f(run).submit_command(command)
	assert_str(String(result.status)).override_failure_message(String(result.reason_key)).is_equal("queued")
	_land_f(run).advance(1)
	return result


func _land_demolished(council_mode: String = "direct") -> Dictionary:
	var run := _land_setup(council_mode)
	var built := _land_do(run, SimCommand.public_work_road(_land_points(), &"local", true))
	run["road_command_id"] = built.command_id
	_land_do(run, SimCommand.public_work_demolish(built.command_id))
	_land_assert_taken(run)
	return run


func _land_command(ids: PackedInt64Array, use: StringName = &"zone.green", reuse: bool = true) -> SimCommand:
	var params := {"parcel_ids": ids, "land_use": use}
	if reuse:
		params["municipal_reuse"] = true
	return SimCommand.make(SimCommand.KIND_ZONING_PROPOSE, params)


func _land_assert_taken(run: Dictionary, ids: PackedInt64Array = PackedInt64Array()) -> void:
	var expected: PackedInt64Array = run["taken"] if ids.is_empty() else ids
	var net: WorldNetwork = run["net"]
	var d := EconomyState.data(_land_f(run).game_state())
	for id in expected:
		assert_bool(net.parcels.has(id)).override_failure_message("dünya parseli erken döndü: %d" % id).is_false()
		assert_int(int(d["stage"][EconomyState.index_of(d, id)])).is_equal(EconomyState.STAGE_TAKEN)


func _land_assert_fresh_green(run: Dictionary, ids: PackedInt64Array = PackedInt64Array()) -> void:
	var expected: PackedInt64Array = run["taken"] if ids.is_empty() else ids
	var net: WorldNetwork = run["net"]
	var d := EconomyState.data(_land_f(run).game_state())
	for id in expected:
		assert_bool(net.parcels.has(id)).override_failure_message("açılan parsel dünyada yok: %d" % id).is_true()
		var i := EconomyState.index_of(d, id)
		assert_int(int(d["stage"][i])).is_equal(EconomyState.STAGE_VACANT)
		assert_int(int(d["units"][i])).is_equal(0)
		assert_int(int(d["owner_id"][i])).is_equal(0)
		assert_str(String(_land_f(run).parcel_views(PackedInt64Array([id]))[0].zone)).is_equal("zone.green")
	assert_str(ExpropriationFlow.consistency_problem(_land_f(run).game_state())).is_empty()
	assert_array(NetworkInvariants.check_parcels(net)).is_empty()


func _land_events_for(run: Dictionary, command_id: int, message_key: StringName) -> Array[SimEvent]:
	var out: Array[SimEvent] = []
	for event in _land_f(run).events_since(0):
		if event.command_id == command_id and event.message_key == message_key:
			out.append(event)
	return out


func _land_latent(run: Dictionary) -> PackedInt64Array:
	return (EconomyState.data(_land_f(run).game_state())["regions"]["latent_hh"] as PackedInt64Array).duplicate()
