extends GdUnitTestSuite
## T-042b adım 2 (sim) · Sözleşme 1.5 (ADR-0005 Ek F, D-011): `public_work.road` + `expropriate` bayrağı, kamulaştırma
## önizleme/ret/olay yüzeyi, `ParcelView` `taken` durumu ve MOCK paritesi. UI/oyun ekipleri dünya tarafı bitmeden bu
## mock
## ile çalışır; mock geometri HESAPLAMAZ, sayılar senaryo verisidir (MOCK). Gerçek sim aynı `ExpropriationSummary`
## yardımcısıyla aynı anahtarları üretir (tests/sim/public_works/expropriation_*).

const S := preload("res://tests/contracts/contract_test_support.gd")
const SCENARIO := "mock_scenario_expropriation"
const POINTS := [-45000, 21000, -45000, 11000]
const KEYS: Array[String] = ["expropriate", "taken_parcels", "taken_built_parcels", "taken_project_parcels",
	"taken_res_units", "taken_com_units", "displaced_households", "taken_regions", "nearby_households",
	"nearby_parcels"]


func _road(expropriate: bool) -> SimCommand:
	return SimCommand.public_work_road(PackedInt64Array(POINTS), &"local", expropriate)


# --- Sürüm ve komut şekli ---

func test_contract_version_is_1_6_and_older_documents_stay_compatible() -> void:
	assert_str(SimContract.VERSION).is_equal("1.6")  # 1.5 kamulaştırma; 1.6 geri al + yolu yık (ADR-0005 Ek H)
	assert_int(SimContract.VERSION_MINOR).is_equal(6)
	for old in ["1.0", "1.3", "1.4", "1.5"]:
		assert_bool(SimContract.is_compatible(old)).is_true()


func test_expropriate_is_an_optional_boolean_and_absent_means_the_old_command() -> void:
	assert_bool(_road(true).validate_shape().is_empty()).is_true()
	assert_bool(_road(false).validate_shape().is_empty()).is_true()
	# yok = Ek E komutu, bit-bit aynı parametre sözlüğü (komut günlüğü/hash değişmez)
	assert_bool(_road(false).params.has("expropriate")).is_false()
	assert_bool(bool(_road(true).params["expropriate"])).is_true()
	var wrong := SimCommand.make(&"public_work.road",
		{"points_cm": PackedInt64Array(POINTS), "road_class": &"local", "expropriate": 1})
	assert_str(String(wrong.validate_shape()["reason_key"])).is_equal("command.reject.bad_param_type")


func test_expropriate_flag_survives_a_json_round_trip() -> void:
	var back := SimCommand.from_dict(JSON.parse_string(JSON.stringify(_road(true).to_dict())))
	assert_bool(back.params["expropriate"] is bool).is_true()
	assert_bool(bool(back.params["expropriate"])).is_true()
	assert_bool(back.validate_shape().is_empty()).is_true()


func test_expropriation_does_not_add_a_private_building_verb() -> void:
	assert_bool(SimCommand.CATALOG.has(&"public_work.expropriate")).is_false()  # yeni komut türü yok (CAN-03)
	for kind: StringName in SimCommand.CATALOG:
		assert_bool(SimCommand.is_forbidden_kind(kind)).is_false()


# --- Sabitler ve DTO'lar ---

func test_event_kinds_reject_keys_and_taken_state_are_declared() -> void:
	assert_str(String(SimEvent.KIND_PUBLIC_WORK_EXPROPRIATED)).is_equal("public_work.expropriated")
	assert_str(String(SimEvent.KIND_PUBLIC_WORK_RESTORED)).is_equal("public_work.restored")
	assert_str(String(ParcelView.DEVELOPMENT_TAKEN)).is_equal("taken")
	for key: StringName in [CommandResult.REJECT_PROTECTED_STRUCTURE, CommandResult.REJECT_EXPROPRIATION_DISABLED,
			CommandResult.REJECT_EXPROPRIATION_CHANGED, CommandResult.REJECT_ECONOMY_NOT_STARTED]:
		assert_bool(String(key).begins_with(CommandResult.REJECT_PUBLIC_WORK_PREFIX)).is_true()
		assert_bool(CommandReject.is_passthrough(key)).is_true()  # precondition'a düşürülmez


func test_summary_helper_builds_the_same_flat_preview_and_event_args() -> void:
	var summary := {"parcel_ids": PackedInt64Array([3, 1]), "built_parcels": 1, "project_parcels": 0, "res_units": 12,
		"com_units": 0, "households": 11, "regions": {"F1": 2}, "nearby_households": 5, "nearby_parcels": 2}
	var args := ExpropriationSummary.preview_args(summary)
	assert_array(args.keys()).contains_exactly_in_any_order(KEYS)
	assert_int(int(args["taken_parcels"])).is_equal(2)
	assert_int(int(args["displaced_households"])).is_equal(11)
	assert_dict(args["taken_regions"]).is_equal({"F1": 2})
	var ids := ExpropriationSummary.sorted_ids(summary)
	assert_array(Array(ids)).is_equal([1, 3])  # artan, tekrarsız


func test_public_work_view_round_trips_the_expropriation_fields() -> void:
	var w := PublicWorkView.new()
	w.work_id = 1
	w.command_id = 4
	w.expropriated = true
	w.taken_parcel_ids = PackedInt64Array([2, 5])
	w.taken_built_parcels = 2
	w.taken_res_units = 9
	w.taken_com_units = 3
	w.displaced_households = 8
	var back := PublicWorkView.from_dict(JSON.parse_string(JSON.stringify(w.to_dict())))
	assert_bool(back.expropriated).is_true()
	assert_array(Array(back.taken_parcel_ids)).is_equal([2, 5])
	assert_int(back.displaced_households).is_equal(8)
	assert_bool(PublicWorkView.new().expropriated).is_false()  # eski yol: varsayılan


func test_taken_parcel_passes_the_contract_checks_and_other_states_are_unchanged() -> void:
	var p := ParcelView.new()
	p.id = 1
	p.development = ParcelView.DEVELOPMENT_TAKEN
	p.taken_by_command = 3
	assert_array(Array(SimContractChecks.check_parcel_projects([p]))).is_empty()
	assert_array(Array(SimContractChecks.check_parcel_decisions([p]))).is_empty()
	p.units = 4  # alınmış parselde proje alanı kalmamalı
	assert_int(SimContractChecks.check_parcel_projects([p]).size()).is_greater(0)
	var vacant := ParcelView.new()
	vacant.id = 2
	vacant.taken_by_command = 1  # yalnız `taken` iken anlamlı
	assert_int(SimContractChecks.check_parcel_projects([vacant]).size()).is_greater(0)


# --- Mock: teklif -> önizleme -> uygulama -> geri alma ---

func test_scenario_loads_and_is_marked_mock() -> void:
	assert_array(Array(S.scenario(SCENARIO).errors)).is_empty()
	assert_bool(S.facade(SCENARIO).is_mock()).is_true()


func test_mock_plain_road_through_buildings_is_rejected_with_the_expropriation_offer() -> void:
	var f := S.facade(SCENARIO)
	var untouched := S.facade(SCENARIO)
	for r in [f.validate_command(_road(false)), f.submit_command(_road(false))]:
		assert_str(String(r.reason_key)).is_equal("public_work.reject.crosses_parcels")
		assert_bool(bool(r.args["expropriate"])).is_true()  # gerçek sim ile AYNI anahtar (parite)
		assert_int(int(r.args["taken_parcels"])).is_equal(3)
		assert_int(int(r.args["displaced_households"])).is_equal(11)
		var preview := f.validate_command(_road(true)).args  # teklifin sayıları = kabul edilecek yolun önizlemesi
		for key: String in KEYS.slice(1):
			assert_that(r.args[key]).is_equal(preview[key])
	f.advance(10)
	untouched.advance(10)
	assert_str(S.observable_hash(f)).is_equal(S.observable_hash(untouched))
	assert_int(f.public_works().size()).is_equal(0)


func test_mock_expropriating_road_previews_sim_style_numbers_and_no_cost() -> void:
	var f := S.facade(SCENARIO)
	var v := f.validate_command(_road(true))
	assert_str(String(v.status)).is_equal("valid")
	assert_array(v.args.keys()).contains(KEYS)
	assert_bool(bool(v.args["expropriate"])).is_true()
	assert_int(int(v.args["taken_built_parcels"])).is_equal(2)
	assert_int(int(v.args["taken_res_units"])).is_equal(12)
	assert_int(int(v.args["taken_com_units"])).is_equal(4)
	assert_int(int(v.args["nearby_households"])).is_equal(8)
	assert_bool(bool(v.args["cost_available"])).is_false()  # bedel yalnız gösterge: henüz kurulmadı (T-014)
	assert_str(String(v.args["cost_reason_key"])).is_equal("public_work.cost.not_built")


func test_mock_applies_taking_parcels_with_events_in_the_contract_order() -> void:
	var f := S.facade(SCENARIO)
	assert_str(String(f.parcel_views(S.ids([1]))[0].development)).is_equal("built")
	var q := f.submit_command(_road(true))
	assert_int(q.command_id).is_equal(1)
	f.advance(1)
	for id in [1, 2, 3]:
		var p := f.parcel_views(S.ids([id]))[0]
		assert_str(String(p.development)).is_equal("taken")
		assert_int(p.taken_by_command).is_equal(1)
		assert_int(p.units).is_equal(0)
	assert_str(String(f.parcel_views(S.ids([4]))[0].development)).is_equal("built")  # yakındaki alınmadı
	var kinds: Array[String] = []
	for e in f.events_since(0):
		kinds.append(String(e.kind))
	assert_array(kinds).is_equal(["public_work.expropriated", "public_work.built", "command.applied"])
	var taken := S.events_of(f, SimEvent.KIND_PUBLIC_WORK_EXPROPRIATED)[0]
	assert_bool(taken.subjects.has("command.1")).is_true()
	assert_bool(taken.subjects.has("region.F1")).is_true()
	assert_bool(taken.subjects.has("parcel.2")).is_true()
	assert_int(int(taken.args["households"])).is_equal(11)
	var w := f.public_works()[0]
	assert_bool(w.expropriated).is_true()
	assert_array(Array(w.taken_parcel_ids)).is_equal([1, 2, 3])
	assert_array(Array(f.parcel_changes_since(0).ids)).contains([1, 2, 3])
	assert_array(Array(SimContractChecks.check_facade(f))).is_empty()


func test_mock_group_reaction_arrives_and_is_not_undone_with_the_road() -> void:
	var f := S.facade(SCENARIO)
	f.submit_command(_road(true))
	f.advance(6)
	assert_str(String(f.snapshot().group_reactions[0].reaction)).is_equal("protest")
	f.submit_command(SimCommand.public_work_undo_last())
	f.advance(1)
	var before := {1: "built", 2: "built", 3: "vacant"}  # alınmadan önceki hali
	for id: int in before:
		var p := f.parcel_views(S.ids([id]))[0]
		assert_str(String(p.development)).is_equal(before[id])
		assert_int(p.taken_by_command).is_equal(0)
	assert_int(f.public_works().size()).is_equal(0)
	assert_str(String(f.snapshot().group_reactions[0].reaction)).is_equal("protest")  # halk tepkisi geri gelmez
	var kinds: Array[String] = []
	for e in f.events_since(0):
		kinds.append(String(e.kind))
	assert_bool(kinds.has("public_work.restored")).is_true()
	assert_bool(kinds.find("public_work.restored") < kinds.find("public_work.removed")).is_true()
	assert_array(Array(SimContractChecks.check_facade(f))).is_empty()


func test_mock_is_deterministic_for_the_same_commands() -> void:
	var a := S.facade(SCENARIO)
	var b := S.facade(SCENARIO)
	for f in [a, b]:
		f.submit_command(_road(true))
		f.advance(8)
	assert_str(S.observable_hash(a)).is_equal(S.observable_hash(b))
