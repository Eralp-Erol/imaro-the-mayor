# gdlint:disable=max-public-methods
extends GdUnitTestSuite
## T-042b adım 2 (sim) · `public_work.road {expropriate: true}` + `public_work.undo_last` (D-011, ADR-0005 Ek F):
## önizleme = uygulama sayıları, kamulaştırarak geçme teklifi, korunan yapı, tick'te küme sapması (durum bozulmaz),
## olay sırası, parsel başına gerekçe, geri alma (binalar döner, tepki defteri DÖNMEZ), kayıt/yükleme, determinizm,
## CAN-03. Dünya köprüsü TEST İKİZİdir (`FakeExpropriationWorld`): gerçek ağ, enjekte edilen "alınan küme" tablosu.
## Stok: bölge D1'de 1 (konut 10), 2 (konut 6), 3 (ticaret 4); D2'de 5 (konut 8). Köşegen yol 1,2,3'ü, kuzey kolu 5'i
## alır.

const P := preload("res://tests/sim/public_works/public_works_support.gd")
const SEEDS: Array[int] = [11, 20261030, 3033, 40404, 505050]
const DIAGONAL: Array[int] = [110000, 110000, 126000, 120000]
const KEYS := "public_work.reject."


func _diag() -> PackedInt64Array:
	return PackedInt64Array(DIAGONAL)


func _config_with(section: Dictionary) -> PublicWorksConfig:
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PublicWorksConfig.DEFAULT_PATH))
	var merged: Dictionary = raw["expropriation"]
	merged.merge(section, true)
	return PublicWorksConfig.from_dict(raw)


## `port`: false = köprü yok; `ticks`: kurulumdan sonra ilerletilen gün (ekonomi durumu ilk günlük tick'te kurulur).
func _setup(world_seed: int = P.SEED, port: bool = true, ticks: int = 1,
		config: PublicWorksConfig = null) -> Dictionary:
	var net := P.network()
	var stock := ListStockSource.create([
		{"parcel_id": 1, "use": "residential", "units": 10, "owner": 1},
		{"parcel_id": 2, "use": "residential", "units": 6, "owner": 1},
		{"parcel_id": 3, "use": "commercial", "units": 4, "owner": 1},
		{"parcel_id": 5, "use": "residential", "units": 8, "owner": 1}])
	var handle := EconomyBootstrap.create(world_seed, P.source(), EconomyTestSupport.config(P.economy_patch()), stock)
	assert_object(handle).is_not_null()
	var ctx := PublicWorksContext.create(net, RoadDraftRules.new(),
		config if config != null else PublicWorksConfig.load_default())
	var fake := FakeExpropriationWorld.new(net)
	fake.take(_diag(), [1, 2, 3])
	fake.take(P.spur_b_cm(), [5])
	if port:
		ctx.set_expropriation(fake)
	assert_bool(handle.facade.attach_public_works(ctx)).is_true()
	if ticks > 0:
		handle.facade.advance(ticks)
	return {"facade": handle.facade, "net": net, "ctx": ctx, "fake": fake, "handle": handle}


func _f(run: Dictionary) -> SimFacadeImpl:
	return run["facade"]


func _road(points: PackedInt64Array, expropriate: bool = true) -> SimCommand:
	return SimCommand.public_work_road(points, &"local", expropriate)


func _kinds(f: SimFacade) -> Array[StringName]:
	var out: Array[StringName] = []
	for e in f.events_since(0):
		out.append(e.kind)
	return out


func _events(f: SimFacade, kind: StringName) -> Array[SimEvent]:
	var out: Array[SimEvent] = []
	for e in f.events_since(0):
		if e.kind == kind:
			out.append(e)
	return out


func _view(f: SimFacadeImpl, id: int) -> ParcelView:
	return f.parcel_views(PackedInt64Array([id]))[0]


func _region(f: SimFacadeImpl, code: StringName) -> Dictionary:
	var regions: Dictionary = EconomyState.data(f.game_state())["regions"]
	var r := (regions["codes"] as PackedStringArray).find(String(code))
	return {"latent": regions["latent_hh"][r], "res": regions["res_built"][r], "com": regions["com_built"][r]}


func _rows(f: SimFacadeImpl, ids: Array) -> Array:
	var out: Array = []
	for id: int in ids:
		var v := _view(f, id)
		out.append([v.development, v.use, v.units, v.owner.id if v.owner != null else 0])
	return out


func _take(run: Dictionary, points: PackedInt64Array = PackedInt64Array()) -> CommandResult:
	var r := _f(run).submit_command(_road(points if not points.is_empty() else _diag()))
	_f(run).advance(1)
	return r


# --- Kapalı / hazır değil ---

func test_without_a_world_bridge_expropriation_is_disabled_and_nothing_changes() -> void:
	var run := _setup(P.SEED, false)
	var f := _f(run)
	var before := f.state_hash()
	var r := f.validate_command(_road(_diag()))
	assert_str(String(r.status)).is_equal("rejected")
	assert_str(String(r.reason_key)).is_equal(KEYS + "expropriation_disabled")
	assert_str(f.state_hash()).is_equal(before)
	var submitted := f.submit_command(_road(_diag()))  # gönderimde reddedilir, kuyruğa girmez
	assert_str(String(submitted.status)).is_equal("rejected")
	f.advance(1)
	assert_bool((run["net"] as WorldNetwork).delta.ops.is_empty()).is_true()


func test_data_flag_off_disables_even_with_a_bridge() -> void:
	var run := _setup(P.SEED, true, 1, _config_with({"enabled": false}))
	var r := _f(run).validate_command(_road(_diag()))
	assert_str(String(r.reason_key)).is_equal(KEYS + "expropriation_disabled")
	var offer := _f(run).validate_command(_road(_diag(), false))  # teklif de yok: kamulaştırma kapalı
	assert_str(String(offer.reason_key)).is_equal(KEYS + "crosses_parcels")
	assert_bool(offer.args.has("expropriate")).is_false()


func test_economy_not_started_is_rejected_before_the_first_daily_tick() -> void:
	var run := _setup(P.SEED, true, 0)
	var r := _f(run).validate_command(_road(_diag()))
	assert_str(String(r.reason_key)).is_equal(KEYS + "economy_not_started")


# --- Teklif ve önizleme ---

func test_without_the_flag_the_rejection_carries_the_simulations_own_offer() -> void:
	var f := _f(_setup())
	var plain := f.validate_command(_road(_diag(), false))
	assert_str(String(plain.reason_key)).is_equal(KEYS + "crosses_parcels")
	var preview := f.validate_command(_road(_diag()))
	assert_str(String(preview.status)).is_equal("valid")
	for key in ["expropriate", "taken_parcels", "taken_built_parcels", "taken_project_parcels", "taken_res_units",
			"taken_com_units", "displaced_households", "taken_regions", "nearby_households", "nearby_parcels"]:
		assert_bool(plain.args.has(key)).override_failure_message(key).is_true()
		assert_that(plain.args[key]).override_failure_message(key).is_equal(preview.args[key])


func test_preview_counts_buildings_and_households_from_the_economy_not_from_the_world() -> void:
	var run := _setup()
	var f := _f(run)
	var before := f.state_hash()
	var r := f.validate_command(_road(_diag()))
	assert_str(String(r.status)).is_equal("valid")
	assert_int(int(r.args["taken_parcels"])).is_equal(3)
	assert_int(int(r.args["taken_built_parcels"])).is_equal(3)
	assert_int(int(r.args["taken_res_units"])).is_equal(16)
	assert_int(int(r.args["taken_com_units"])).is_equal(4)
	var region := _region(f, P.CODE_A)
	var housed_after := mini(region["latent"], region["res"] - 16)
	assert_int(int(r.args["displaced_households"])).is_equal(mini(region["latent"], region["res"]) - housed_after)
	assert_int(int(r.args["displaced_households"])).is_greater(0)
	assert_dict(r.args["taken_regions"]).is_equal({"D1": 3})
	assert_bool(bool(r.args["cost_available"])).is_false()  # bedel yalnız gösterge (T-014, Q-003)
	assert_int(int(r.args["length_m"])).is_greater(0)
	assert_str(f.state_hash()).is_equal(before)  # önizleme durumu DEĞİŞTİRMEZ
	assert_bool((run["net"] as WorldNetwork).delta.ops.is_empty()).is_true()


func test_a_flagged_road_that_takes_nothing_behaves_like_a_plain_road() -> void:
	var f := _f(_setup())
	var r := f.validate_command(_road(P.spur_a_cm()))
	assert_str(String(r.status)).is_equal("valid")
	assert_bool(r.args.has("taken_parcels")).is_false()
	f.submit_command(_road(P.spur_a_cm()))
	f.advance(1)
	assert_int(_events(f, &"public_work.expropriated").size()).is_equal(0)
	assert_bool(f.public_works()[0].expropriated).is_false()
	assert_bool(f.game_state().systems["public_works"].has("taken")).is_false()  # v1 kalır


# --- Korunan yapı ---

func test_a_protected_parcel_blocks_the_road_when_heritage_is_protected() -> void:
	var run := _setup()
	(run["ctx"] as PublicWorksContext).set_protected(PackedInt64Array([2]))
	var f := _f(run)
	var r := f.validate_command(_road(_diag()))
	assert_str(String(r.reason_key)).is_equal(KEYS + "protected_structure")
	assert_int(int(r.args["protected_parcels"])).is_equal(1)
	var offer := f.validate_command(_road(_diag(), false))
	assert_bool(offer.args.has("expropriate")).is_false()  # korunan yapı varken teklif yok
	assert_int(int(offer.args["protected_parcels"])).is_equal(1)
	f.submit_command(_road(_diag()))
	f.advance(1)
	assert_str(String(_view(f, 2).development)).is_equal("built")  # hiçbiri alınmadı


func test_the_protection_is_a_data_flag_not_a_constant() -> void:
	var run := _setup(P.SEED, true, 1, _config_with({"protect_heritage": false}))
	(run["ctx"] as PublicWorksContext).set_protected(PackedInt64Array([2]))
	assert_str(String(_f(run).validate_command(_road(_diag())).status)).is_equal("valid")


# --- Uygulama ---

func test_apply_takes_the_parcels_demolishes_the_buildings_and_orders_the_events() -> void:
	var run := _setup()
	var f := _f(run)
	var res_before: int = _region(f, P.CODE_A)["res"]
	var preview := f.validate_command(_road(_diag()))
	var r := _take(run)
	assert_str(String(r.status)).is_equal("queued")
	for id in [1, 2, 3]:
		var v := _view(f, id)
		assert_str(String(v.development)).is_equal("taken")
		assert_int(v.units).is_equal(0)
		assert_int(v.taken_by_command).is_equal(1)
	assert_str(String(_view(f, 4).development)).is_equal("vacant")  # alınmayan parsel olduğu gibi
	assert_str(String(_view(f, 5).development)).is_equal("built")
	assert_int(_region(f, P.CODE_A)["res"]).is_equal(res_before - 16)
	assert_int(_region(f, P.CODE_A)["com"]).is_equal(0)
	var kinds := _kinds(f)
	var at_expropriated := kinds.find(&"public_work.expropriated")
	assert_int(at_expropriated).is_greater_equal(0)
	assert_int(kinds.find(&"public_work.built")).is_greater(at_expropriated)
	assert_int(kinds.find(&"command.applied")).is_greater(kinds.find(&"public_work.built"))
	var event := _events(f, &"public_work.expropriated")[0]
	assert_int(int(event.args["parcels"])).is_equal(int(preview.args["taken_parcels"]))
	assert_int(int(event.args["households"])).is_equal(int(preview.args["displaced_households"]))
	assert_int(int(event.args["res_units"])).is_equal(int(preview.args["taken_res_units"]))
	for ref in ["command.1", "region.D1", "parcel.1", "parcel.2", "parcel.3"]:
		assert_bool(event.subjects.has(ref)).override_failure_message(ref).is_true()
	assert_str(String(event.message_key)).is_equal("event.road.expropriated")
	assert_int(event.command_id).is_equal(1)
	assert_array(SimContractChecks.check_facade(f)).is_empty()


func test_each_taken_parcel_has_a_municipal_reason_the_inspector_can_explain() -> void:
	var run := _setup()
	var f := _f(run)
	_take(run)
	for id in [1, 2, 3]:
		var reasons := f.reasons_for(SimContract.parcel_ref(id))
		var found: Array[ReasonRecord] = reasons.filter(
			func(r: ReasonRecord) -> bool: return r.decision_key == &"decision.municipal.expropriate")
		assert_int(found.size()).override_failure_message("parsel %d" % id).is_equal(1)
		assert_bool(found[0].subjects.has("command.1")).is_true()
		assert_bool(_view(f, id).reason_ids.has(found[0].id)).is_true()
	assert_int(_events(f, &"public_work.expropriated")[0].reason_ids.size()).is_equal(3)


func test_public_works_view_records_what_the_road_took() -> void:
	var run := _setup()
	_take(run)
	var w := _f(run).public_works()[0]
	assert_bool(w.expropriated).is_true()
	assert_array(Array(w.taken_parcel_ids)).is_equal([1, 2, 3])
	assert_int(w.taken_built_parcels).is_equal(3)
	assert_int(w.taken_res_units).is_equal(16)
	assert_int(w.taken_com_units).is_equal(4)
	assert_int(w.displaced_households).is_greater(0)


func test_reaction_books_record_displacement_and_lighter_proximity_by_region() -> void:
	var run := _setup()
	var f := _f(run)
	_take(run)
	var state := f.game_state()
	var displaced := PublicWorksState.reaction_rows(state, "displaced", "D1")
	assert_int(displaced.size()).is_equal(1)
	assert_int(int(displaced[0][1])).is_equal(f.public_works()[0].displaced_households)
	assert_int(int(displaced[0][2])).is_equal(1)
	assert_int(PublicWorksState.reaction_rows(state, "displaced", "D2").size()).is_equal(0)


# --- Tick'te küme sapması ---

func test_a_world_report_that_differs_from_the_preview_rejects_and_leaves_state_untouched() -> void:
	var run := _setup()
	var f := _f(run)
	(run["fake"] as FakeExpropriationWorld).report_instead(_diag(), [1, 2])
	var net: WorldNetwork = run["net"]
	var rows_before := _rows(f, [1, 2, 3, 4, 5])
	var region_before := _region(f, P.CODE_A)
	var graph_before := net.graph_hash()
	f.submit_command(_road(_diag()))
	f.advance(1)
	var rejected := _events(f, &"command.rejected")
	assert_int(rejected.size()).is_equal(1)
	assert_str(String(rejected[0].message_key)).is_equal(KEYS + "expropriation_changed")
	assert_array(_rows(f, [1, 2, 3, 4, 5])).is_equal(rows_before)
	assert_dict(_region(f, P.CODE_A)).is_equal(region_before)
	assert_str(net.graph_hash()).is_equal(graph_before)  # ağ geri alındı
	assert_bool(net.delta.ops.is_empty()).is_true()
	assert_bool(f.game_state().systems.has("public_works")).is_false()
	assert_int(_events(f, &"public_work.expropriated").size()).is_equal(0)
	assert_int((run["fake"] as FakeExpropriationWorld).undos).is_equal(1)


# --- Geri alma ---

func test_undo_restores_the_buildings_but_not_the_publics_reaction() -> void:
	var run := _setup()
	var f := _f(run)
	var net: WorldNetwork = run["net"]
	var rows_before := _rows(f, [1, 2, 3, 4, 5])
	var region_before := _region(f, P.CODE_A)
	_take(run)
	var displaced := f.public_works()[0].displaced_households
	f.submit_command(SimCommand.public_work_undo_last())
	f.advance(1)
	assert_array(_rows(f, [1, 2, 3, 4, 5])).is_equal(rows_before)
	assert_int(_region(f, P.CODE_A)["res"]).is_equal(region_before["res"])
	assert_int(_region(f, P.CODE_A)["com"]).is_equal(region_before["com"])
	assert_int(_view(f, 1).taken_by_command).is_equal(0)
	assert_str(net.graph_hash()).is_equal(net.base_hash)
	assert_int(f.public_works().size()).is_equal(0)
	var rows := PublicWorksState.reaction_rows(f.game_state(), "displaced", "D1")
	assert_int(rows.size()).is_equal(1)  # halk tepkisi geri alınmaz (D-011)
	assert_int(int(rows[0][1])).is_equal(displaced)
	var kinds := _kinds(f)
	assert_int(kinds.rfind(&"public_work.removed")).is_greater(kinds.rfind(&"public_work.restored"))
	assert_int(kinds.rfind(&"public_work.restored")).is_greater_equal(0)
	assert_array(SimContractChecks.check_facade(f)).is_empty()


func test_undo_preview_names_what_comes_back() -> void:
	var run := _setup()
	_take(run)
	var r := _f(run).validate_command(SimCommand.public_work_undo_last())
	assert_str(String(r.status)).is_equal("valid")
	assert_int(int(r.args["restored_parcels"])).is_equal(3)
	assert_int(int(r.args["restored_built_parcels"])).is_equal(3)


func test_undo_is_lifo_across_an_expropriating_and_a_plain_road() -> void:
	var run := _setup()
	var f := _f(run)
	_take(run)  # 1: köşegen (1,2,3)
	_take(run, P.spur_b_cm())  # 2: kuzey kolu (5)
	assert_str(String(_view(f, 5).development)).is_equal("taken")
	f.submit_command(SimCommand.public_work_undo_last())
	f.advance(1)
	assert_str(String(_view(f, 5).development)).is_equal("built")
	assert_str(String(_view(f, 1).development)).is_equal("taken")  # eski yol hâlâ kalıcı
	f.submit_command(SimCommand.public_work_undo_last())
	f.advance(1)
	assert_str(String(_view(f, 1).development)).is_equal("built")


func test_undo_without_the_bridge_is_refused_when_the_last_road_took_parcels() -> void:
	var run := _setup()
	_take(run)
	(run["ctx"] as PublicWorksContext).set_expropriation(null)
	var r := _f(run).validate_command(SimCommand.public_work_undo_last())
	assert_str(String(r.reason_key)).is_equal(KEYS + "expropriation_disabled")


# --- Hane kaderi (Q-017 çalışma bayrağı) ---

func test_leave_region_fate_removes_households_and_undo_returns_them() -> void:
	var run := _setup(P.SEED, true, 1, _config_with({"household_fate": "leave_region"}))
	var f := _f(run)
	var latent_before: int = _region(f, P.CODE_A)["latent"]
	var displaced := int(f.validate_command(_road(_diag())).args["displaced_households"])
	assert_int(displaced).is_greater(0)
	_take(run)
	assert_int(_region(f, P.CODE_A)["latent"]).is_equal(latent_before - displaced)
	f.submit_command(SimCommand.public_work_undo_last())
	f.advance(1)
	assert_int(_region(f, P.CODE_A)["latent"]).is_equal(latent_before)


func test_return_to_latent_fate_keeps_the_regions_waiting_households() -> void:
	var run := _setup()
	var f := _f(run)
	var latent_before: int = _region(f, P.CODE_A)["latent"]
	_take(run)
	assert_int(_region(f, P.CODE_A)["latent"]).is_equal(latent_before)


# --- CAN-03 ---

func test_nothing_is_built_on_taken_parcels_and_the_municipality_spawns_no_building() -> void:
	var run := _setup()
	var f := _f(run)
	_take(run)
	f.advance(150)
	for id in [1, 2, 3]:
		assert_str(String(_view(f, id).development)).override_failure_message("parsel %d" % id).is_equal("taken")
		var investors: Array[ReasonRecord] = f.reasons_for(SimContract.parcel_ref(id)).filter(
			func(r: ReasonRecord) -> bool: return String(r.decision_key).begins_with("decision.investor"))
		assert_int(investors.size()).is_equal(0)


# --- Determinizm / kayıt ---

func test_same_commands_give_the_same_state_hash_and_graph_hash_on_five_seeds() -> void:
	for world_seed in SEEDS:
		var hashes: Array[String] = []
		var graphs: Array[String] = []
		for _i in 2:
			var run := _setup(world_seed)
			_take(run)
			_f(run).advance(40)
			hashes.append(_f(run).state_hash())
			graphs.append((run["net"] as WorldNetwork).graph_hash())
		assert_str(hashes[1]).override_failure_message("tohum %d" % world_seed).is_equal(hashes[0])
		assert_str(graphs[1]).is_equal(graphs[0])


func test_save_and_load_replays_the_expropriating_road_and_continues_identically() -> void:
	var a := _setup()
	_take(a)
	_f(a).advance(20)
	var bytes := _f(a).export_save()
	var b := _setup()
	var loaded := _f(b).import_save(bytes)
	assert_bool(loaded.ok).override_failure_message(loaded.message).is_true()
	assert_str(_f(b).state_hash()).is_equal(_f(a).state_hash())
	assert_str((b["net"] as WorldNetwork).graph_hash()).is_equal((a["net"] as WorldNetwork).graph_hash())
	assert_int((b["fake"] as FakeExpropriationWorld).replays).is_equal(1)
	_f(a).advance(60)
	_f(b).advance(60)
	assert_str(_f(b).state_hash()).is_equal(_f(a).state_hash())


func test_loading_into_a_session_without_the_bridge_fails_cleanly() -> void:
	var a := _setup()
	_take(a)
	var bytes := _f(a).export_save()
	var b := _setup(P.SEED, false)
	var before := _f(b).state_hash()
	var loaded := _f(b).import_save(bytes)
	assert_bool(loaded.ok).is_false()
	assert_str(String(loaded.error_code)).is_equal("network_mismatch")
	assert_str(_f(b).state_hash()).is_equal(before)
	assert_bool((b["net"] as WorldNetwork).delta.ops.is_empty()).is_true()


func test_a_save_whose_taken_set_disagrees_with_the_economy_is_corrupt() -> void:
	var a := _setup()
	_take(a)
	var d := EconomyState.data(_f(a).game_state())
	var stage: PackedByteArray = d["stage"]
	stage[EconomyState.index_of(d, 1)] = EconomyState.STAGE_BUILT
	var bytes := _f(a).export_save()
	var loaded := _f(_setup()).import_save(bytes)
	assert_bool(loaded.ok).is_false()
	assert_str(String(loaded.error_code)).is_equal("corrupt")


func test_a_save_with_a_different_taken_parcel_set_than_the_world_reports_is_a_network_mismatch() -> void:
	var a := _setup()
	_take(a)
	var bytes := _f(a).export_save()
	var b := _setup()
	(b["fake"] as FakeExpropriationWorld).take(_diag(), [1, 2])  # yüklenen dünya başka küme alıyor
	var loaded := _f(b).import_save(bytes)
	assert_bool(loaded.ok).is_false()
	assert_str(String(loaded.error_code)).is_equal("network_mismatch")


func test_a_plain_v1_save_still_loads_into_a_session_with_the_bridge() -> void:
	var a := _setup()
	_f(a).submit_command(_road(P.spur_a_cm()))
	_f(a).advance(5)
	assert_int(int(_f(a).game_state().systems["public_works"]["version"])).is_equal(1)
	var loaded := _f(_setup()).import_save(_f(a).export_save())
	assert_bool(loaded.ok).override_failure_message(loaded.message).is_true()


# --- Çekirdek kancası ---

class _RefusingHandler extends CommandHandler:
	var applied: int = 0

	func command_type() -> StringName:
		return &"test.refuse_on_apply"

	func validate(_state: GameState, _params: Dictionary) -> StringName:
		return &""

	func apply(_state: GameState, _params: Dictionary) -> void:
		applied += 1

	func try_apply(_state: GameState, _params: Dictionary, _command_id: int) -> StringName:
		return &"changed_meanwhile"


func test_try_apply_can_reject_at_apply_time_without_calling_apply() -> void:
	var state := GameState.create(1, SimConfig.load_default())
	var handler := _RefusingHandler.new()
	Commands.submit(state, handler.command_type())
	Commands.process_pending(state, {String(handler.command_type()): handler})
	assert_int(handler.applied).is_equal(0)
	assert_str(String(Commands.log_entries(state)[0]["status"])).is_equal("rejected")
	assert_str(String(Commands.log_entries(state)[0]["reason"])).is_equal("changed_meanwhile")
