extends GdUnitTestSuite
## T-042 adım 2 · Sözleşme 1.3 (ADR-0005 Ek E): `public_work.road` / `public_work.undo_last` katalog satırları,
## olaylar ve
## MOCK paritesi. UI mock ile çalışır: mock aynı komut şeklini, aynı ret anahtarlarını, aynı olayları ve aynı okuma
## yüzeyini (`public_works()`, `validate_command` ön izleme `args`) verir. Mock geometri hesaplamaz: senaryo kuralı
## karar verir.

const S := preload("res://tests/contracts/contract_test_support.gd")
const SCENARIO := "mock_scenario_public_road"
const GOOD := [-45000, 21000, -45000, 11000]
const BAD := [-40000, 21000, -40000, 11000]


func _road(points: Array) -> SimCommand:
	return SimCommand.public_work_road(PackedInt64Array(points), &"local")


func test_contract_version_is_1_3_and_old_documents_stay_compatible() -> void:
	assert_str(SimContract.VERSION).is_equal("1.3")
	assert_bool(SimContract.is_compatible("1.2")).is_true()
	assert_bool(SimContract.is_compatible("1.0")).is_true()


func test_catalog_has_the_two_public_work_verbs_and_they_are_mayor_verbs() -> void:
	for kind: StringName in [&"public_work.road", &"public_work.undo_last"]:
		assert_bool(SimCommand.CATALOG.has(kind)).is_true()
		assert_bool(SimCommand.is_forbidden_kind(kind)).is_false()  # CAN-03: özel bina doğurmaz
	assert_bool(SimCommand.public_work_undo_last().validate_shape().is_empty()).is_true()
	assert_bool(_road(GOOD).validate_shape().is_empty()).is_true()


func test_command_round_trips_through_json_dictionary() -> void:
	var cmd := _road(GOOD)
	var back := SimCommand.from_dict(JSON.parse_string(JSON.stringify(cmd.to_dict())))
	assert_bool(back.params["points_cm"] is PackedInt64Array).is_true()
	assert_array(Array(back.params["points_cm"])).is_equal(GOOD)
	assert_str(String(back.params["road_class"])).is_equal("local")
	assert_bool(back.validate_shape().is_empty()).is_true()


func test_event_kinds_are_declared() -> void:
	assert_str(String(SimEvent.KIND_PUBLIC_WORK_BUILT)).is_equal("public_work.built")
	assert_str(String(SimEvent.KIND_PUBLIC_WORK_REMOVED)).is_equal("public_work.removed")


# --- Mock: ret -> yol -> onay ---

func test_scenario_loads_and_marks_itself_as_mock() -> void:
	var sc := S.scenario(SCENARIO)
	assert_array(Array(sc.errors)).is_empty()
	assert_bool(S.facade(SCENARIO).is_mock()).is_true()


func test_mock_rejects_the_bad_draft_with_the_public_work_key_and_changes_nothing() -> void:
	var f := S.facade(SCENARIO)
	var untouched := S.facade(SCENARIO)
	for r in [f.validate_command(_road(BAD)), f.submit_command(_road(BAD))]:
		assert_str(String(r.reason_key)).is_equal("public_work.reject.crosses_parcels")
		assert_int(r.command_id).is_equal(0)
	f.advance(10)
	untouched.advance(10)
	assert_str(S.observable_hash(f)).is_equal(S.observable_hash(untouched))
	assert_int(f.public_works().size()).is_equal(0)


func test_mock_valid_road_previews_applies_and_approves_the_declined_parcel() -> void:
	var f := S.facade(SCENARIO)
	var v := f.validate_command(_road(GOOD))
	assert_str(String(v.status)).is_equal("valid")
	assert_int(int(v.args["length_m"])).is_equal(100)
	assert_dict(v.args["regions"]).is_equal({"F1": 10})
	assert_bool(bool(v.args["cost_available"])).is_false()
	assert_str(String(f.parcel_views(S.ids([1]))[0].decision)).is_equal("declined")
	var q := f.submit_command(_road(GOOD))
	assert_str(String(q.status)).is_equal("queued")
	assert_int(q.command_id).is_equal(1)
	f.advance(1)
	var built := S.events_of(f, SimEvent.KIND_PUBLIC_WORK_BUILT)
	assert_int(built.size()).is_equal(1)
	assert_bool(built[0].subjects.has("command.1")).is_true()
	assert_bool(built[0].subjects.has("region.F1")).is_true()
	assert_int(f.public_works().size()).is_equal(1)
	f.advance(5)
	var p := f.parcel_views(S.ids([1]))[0]
	assert_str(String(p.decision)).is_equal("approved")
	assert_str(String(f.parcel_views(S.ids([2]))[0].decision)).is_equal("declined")  # B reddedilmiş kalır
	var reason := f.reason(p.decision_reason_id)
	assert_object(reason).is_not_null()
	var infra: ReasonFactor = null
	for fac in reason.factors:
		if fac.name_key == &"reason.factor.infrastructure_capacity":
			infra = fac
	assert_str(String(infra.source_ref)).is_equal("command.1")
	assert_bool(reason.is_consistent()).is_true()
	assert_array(Array(SimContractChecks.check_facade(f))).is_empty()


func test_mock_undo_follows_the_same_rules_as_the_real_sim() -> void:
	var f := S.facade(SCENARIO)
	assert_str(String(f.submit_command(SimCommand.public_work_undo_last()).reason_key)) \
		.is_equal("public_work.reject.nothing_to_undo")
	f.submit_command(_road(GOOD))
	f.advance(1)
	assert_str(String(f.validate_command(SimCommand.public_work_undo_last()).status)).is_equal("valid")
	f.submit_command(SimCommand.public_work_undo_last())
	f.advance(1)
	assert_int(f.public_works().size()).is_equal(0)
	var removed := S.events_of(f, SimEvent.KIND_PUBLIC_WORK_REMOVED)
	assert_int(removed.size()).is_equal(1)
	assert_int(int(removed[0].args["removed_command_id"])).is_equal(1)


func test_mock_is_deterministic_for_the_same_commands() -> void:
	var a := S.facade(SCENARIO)
	var b := S.facade(SCENARIO)
	for f in [a, b]:
		f.submit_command(_road(GOOD))
		f.advance(8)
	assert_str(S.observable_hash(a)).is_equal(S.observable_hash(b))


func test_shape_violations_are_rejected_identically_by_mock_and_real_sim() -> void:
	var real := EconomyBootstrap.create(1, FacadeTestSupport.fixture_source(3)).facade
	var mock := S.facade(SCENARIO)
	var bad: Array[SimCommand] = [
		SimCommand.make(&"public_work.road", {"road_class": &"local"}),
		SimCommand.make(&"public_work.road", {"points_cm": PackedInt64Array([1, 2, 3]), "road_class": &"local"}),
		SimCommand.make(&"public_work.undo_last", {"x": 1}),
		SimCommand.make(&"public_work.road", {"points_cm": PackedInt64Array([1, 2, 3, 4]), "road_class": ""}),
	]
	for cmd in bad:
		assert_str(String(mock.validate_command(cmd).reason_key)) \
			.is_equal(String(real.validate_command(cmd).reason_key))
