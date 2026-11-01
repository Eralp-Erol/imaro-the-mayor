extends GdUnitTestSuite
## T-042c (D-014 §1) · Yol yapımında KLASİK GERİ AL: başka bir yol parçası yapılana kadar son yol geri alınabilir;
## geri alma eylemi "hiç yapılmamış gibi" yapar (yol kalkar, alınan parseller/binalar döner, o yola bağlı tepki defteri
## satırları silinir). Pencere kapanırsa (başka yol yapıldı / zaten geri alındı / halk tepkisi siyaset taramasına
## girdi) geri alma REDDEDİLİR (yarım geri alma yok). Dünya köprüsü TEST İKİZİdir (`FakeExpropriationWorld`).
## Stok: D1'de 1 (konut 10), 2 (konut 6), 3 (ticaret 4); D2'de 5 (konut 8). Köşegen yol 1,2,3'ü, kuzey kolu 5'i alır.

const P := preload("res://tests/sim/public_works/public_works_support.gd")
const KEYS := "public_work.reject."
const DIAGONAL: Array[int] = [110000, 110000, 126000, 120000]


func _diag() -> PackedInt64Array:
	return PackedInt64Array(DIAGONAL)


func _setup(world_seed: int = P.SEED) -> Dictionary:
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
	handle.facade.advance(1)
	return {"facade": handle.facade, "net": net, "ctx": ctx, "fake": fake, "handle": handle}


func _f(run: Dictionary) -> SimFacadeImpl:
	return run["facade"]


func _build(run: Dictionary, points: PackedInt64Array, expropriate: bool = false) -> CommandResult:
	var r := _f(run).submit_command(SimCommand.public_work_road(points, &"local", expropriate))
	_f(run).advance(1)
	return r


func _undo(run: Dictionary) -> CommandResult:
	var r := _f(run).submit_command(SimCommand.public_work_undo_last())
	_f(run).advance(1)
	return r


func _rejected_keys(f: SimFacade) -> Array[String]:
	var out: Array[String] = []
	for e in f.events_since(0):
		if e.kind == &"command.rejected":
			out.append(String(e.message_key))
	return out


func _view(f: SimFacadeImpl, id: int) -> ParcelView:
	return f.parcel_views(PackedInt64Array([id]))[0]


## Geri almanın dokunduğu her şey (yol listesi, ağ, alınan parseller, bölge sütunları, tepki defteri).
func _footprint(run: Dictionary) -> Dictionary:
	var f := _f(run)
	var state := f.game_state()
	var regions: Dictionary = EconomyState.data(state)["regions"]
	var rows: Array = []
	for id in [1, 2, 3, 4, 5]:
		var v := _view(f, id)
		rows.append([v.development, v.use, v.units, v.owner.id if v.owner != null else 0])
	return {"graph": (run["net"] as WorldNetwork).graph_hash(), "rows": rows,
		"res": StateHash.of(regions["res_built"]), "com": StateHash.of(regions["com_built"]),
		"latent": StateHash.of(regions["latent_hh"]), "works": f.public_works().size(),
		"infra": [PublicWorksState.infra_bonus(state, P.CODE_A), PublicWorksState.infra_bonus(state, P.CODE_B)],
		"d1": PublicWorksState.reaction_rows(state, "displaced", "D1").size(),
		"d2": PublicWorksState.reaction_rows(state, "displaced", "D2").size(),
		"n1": PublicWorksState.reaction_rows(state, "nearby", "D1").size()}


# --- Pencere: yalnız son yol, başka yol yapılana kadar ---

func test_there_is_nothing_to_undo_before_any_road() -> void:
	var run := _setup()
	assert_bool(_f(run).undo_available()).is_false()
	var r := _f(run).validate_command(SimCommand.public_work_undo_last())
	assert_str(String(r.reason_key)).is_equal(KEYS + "nothing_to_undo")


func test_the_latest_road_can_be_undone_and_the_preview_names_it() -> void:
	var run := _setup()
	var f := _f(run)
	var built := _build(run, P.spur_a_cm())
	assert_bool(f.undo_available()).is_true()
	var preview := f.validate_command(SimCommand.public_work_undo_last())
	assert_str(String(preview.status)).is_equal("valid")
	assert_int(int(preview.args["removed_command_id"])).is_equal(built.command_id)


func test_after_a_second_road_only_the_second_can_be_undone_and_then_nothing_more() -> void:
	var run := _setup()
	var f := _f(run)
	var first := _build(run, P.spur_a_cm())
	var second := _build(run, P.spur_b_cm())
	assert_bool(f.undo_available()).is_true()
	assert_int(int(f.validate_command(SimCommand.public_work_undo_last()).args["removed_command_id"])) \
		.is_equal(second.command_id)  # ilk yol artık hedef değil
	_undo(run)
	assert_int(f.public_works().size()).is_equal(1)
	assert_int(f.public_works()[0].command_id).is_equal(first.command_id)
	assert_bool(f.undo_available()).is_false()  # geri alma yığılmaz: ikinci yol gidince ilki geri alınamaz
	var r := f.validate_command(SimCommand.public_work_undo_last())
	assert_str(String(r.status)).is_equal("rejected")
	assert_str(String(r.reason_key)).is_equal(KEYS + "undo_window_closed")
	assert_str(String(r.args["cause"])).is_equal("superseded")
	f.submit_command(SimCommand.public_work_undo_last())  # gönderimde de reddedilir, ağ ve durum değişmez
	var ops_before := (run["net"] as WorldNetwork).delta.ops.size()
	f.advance(1)
	assert_int((run["net"] as WorldNetwork).delta.ops.size()).is_equal(ops_before)
	assert_int(f.public_works().size()).is_equal(1)


func test_a_new_road_after_an_undo_opens_the_window_for_the_new_road() -> void:
	var run := _setup()
	var f := _f(run)
	_build(run, P.spur_a_cm())
	_undo(run)
	assert_bool(f.undo_available()).is_false()
	var again := _build(run, P.spur_b_cm())
	assert_bool(f.undo_available()).is_true()
	assert_int(int(f.validate_command(SimCommand.public_work_undo_last()).args["removed_command_id"])) \
		.is_equal(again.command_id)


func test_undoing_the_second_of_two_roads_leaves_the_first_exactly_as_it_was() -> void:
	var run := _setup()
	_build(run, P.spur_a_cm())
	var with_first := _footprint(run)
	_build(run, P.spur_b_cm())
	_undo(run)
	assert_dict(_footprint(run)).is_equal(with_first)


# --- "Hiç yapılmamış gibi" (kamulaştırmalı yol) ---

func test_undo_of_an_expropriating_road_restores_parcels_buildings_and_removes_its_reaction() -> void:
	var run := _setup()
	var f := _f(run)
	var before := _footprint(run)
	assert_int(int(before["d1"])).is_equal(0)
	_build(run, _diag(), true)
	var during := _footprint(run)
	assert_int(int(during["d1"])).is_equal(1)  # tepki defterine yazıldı
	assert_str(String(_view(f, 1).development)).is_equal("taken")
	_undo(run)
	var after := _footprint(run)
	assert_dict(after).is_equal(before)
	assert_str(String(_view(f, 1).development)).is_equal("built")
	assert_int(PublicWorksState.reaction_rows(f.game_state(), "displaced", "D1").size()).is_equal(0)
	assert_int(PublicWorksState.reaction_rows(f.game_state(), "nearby", "D1").size()).is_equal(0)
	assert_array(SimContractChecks.check_facade(f)).is_empty()


func test_undo_removes_only_the_undone_roads_reaction_rows() -> void:
	var run := _setup()
	var f := _f(run)
	var first := _build(run, _diag(), true)  # D1: 1,2,3
	_build(run, P.spur_b_cm(), true)  # D2: 5
	var state := f.game_state()
	assert_int(PublicWorksState.reaction_rows(state, "displaced", "D2").size()).is_equal(1)
	_undo(run)
	assert_int(PublicWorksState.reaction_rows(state, "displaced", "D2").size()).is_equal(0)
	var d1 := PublicWorksState.reaction_rows(state, "displaced", "D1")
	assert_int(d1.size()).is_equal(1)  # ilk yolun tepkisi durur
	assert_int(int(d1[0][2])).is_equal(first.command_id)
	assert_str(String(_view(f, 5).development)).is_equal("built")
	assert_str(String(_view(f, 1).development)).is_equal("taken")


func test_undo_has_no_reaction_to_remove_for_a_plain_road_and_changes_nothing_else() -> void:
	var run := _setup()
	var before := _footprint(run)
	_build(run, P.spur_a_cm())
	assert_bool(PublicWorksState.has_reactions(_f(run).game_state())).is_false()
	_undo(run)
	assert_dict(_footprint(run)).is_equal(before)


## Denetim izi (olay/gerekçe günlüğü) tarihçedir: geri alınan yolun "Kamulaştırıldı/Geri verildi" kayıtları orada
## kalır ve sonraki gerekçe numaralarını kaydırır. Dünyanın kendisi (sütunlar, bölge toplamları, stok, RNG) ise hiç
## yol yapılmamış koşuyla BİREBİR aynıdır; fark yalnız `reason_id` sütunundaki günlük numaralarıdır.
func test_undo_leaves_the_same_economy_as_a_run_that_never_built_the_road() -> void:
	var a := _setup()
	_build(a, _diag(), true)
	_undo(a)
	_f(a).advance(1)
	var b := _setup()
	_f(b).advance(3)
	assert_int(_f(a).current_tick()).is_equal(_f(b).current_tick())
	var ea := EconomyState.data(_f(a).game_state())
	var eb := EconomyState.data(_f(b).game_state())
	var differing: Array[String] = []
	for key: String in ea:
		if key != "reason_id" and StateHash.of(ea[key]) != StateHash.of(eb.get(key)):
			differing.append("%s a=%s b=%s" % [key, str(ea[key]).substr(0, 200), str(eb.get(key)).substr(0, 200)])
	assert_array(differing).override_failure_message("ekonomi hiç yol yapılmamış koşudan farklı: %s" % str(differing)) \
		.is_empty()


# --- Kayıt ---

func test_save_and_load_keeps_the_window_state() -> void:
	var a := _setup()
	_build(a, P.spur_a_cm())
	var bytes := _f(a).export_save()
	var b := _setup()
	var loaded := _f(b).import_save(bytes)
	assert_bool(loaded.ok).override_failure_message(loaded.message).is_true()
	assert_bool(_f(b).undo_available()).is_true()
	assert_str(_f(b).state_hash()).is_equal(_f(a).state_hash())
	_undo(a)
	var closed := _f(a).export_save()
	var c := _setup()
	assert_bool(_f(c).import_save(closed).ok).is_true()
	assert_bool(_f(c).undo_available()).is_false()
	assert_str(_f(c).state_hash()).is_equal(_f(a).state_hash())


func test_a_save_whose_window_points_at_another_road_is_corrupt() -> void:
	var a := _setup()
	_build(a, P.spur_a_cm())
	_build(a, P.spur_b_cm())
	var state := _f(a).game_state()
	var section := PublicWorksState.data(state)
	assert_bool(section.has("undo")).is_true()
	var broken := section.duplicate(true)
	broken["undo"] = {"command_id": 999, "scans": -1}
	assert_str(PublicWorksState.validate_data(broken)).is_not_empty()
	assert_str(PublicWorksState.validate_data(section)).is_empty()


func test_a_state_saved_before_the_window_existed_treats_the_last_road_as_open() -> void:
	var run := _setup()
	_build(run, P.spur_a_cm())
	var section := PublicWorksState.data(_f(run).game_state())
	section.erase("undo")  # eski kayıt: pencere alanı yok
	assert_str(PublicWorksState.validate_data(section)).is_empty()
	assert_bool(_f(run).undo_available()).is_true()


# --- Determinizm ---

func test_same_commands_with_an_undo_give_the_same_hash_on_five_seeds() -> void:
	for world_seed in [11, 20261030, 3033, 40404, 505050]:
		var hashes: Array[String] = []
		for _i in 2:
			var run := _setup(world_seed)
			_build(run, _diag(), true)
			_undo(run)
			_build(run, P.spur_b_cm(), true)
			_f(run).advance(20)
			hashes.append(_f(run).state_hash())
		assert_str(hashes[1]).override_failure_message("tohum %d" % world_seed).is_equal(hashes[0])
