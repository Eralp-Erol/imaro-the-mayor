extends GdUnitTestSuite
## Sözleşme 1.7 (ADR-0005 Ek I, ADR-0009 Değişiklik 3; T-065 Aşama 1, D-016) · Yeniden iskân politikası yüzeyi:
## `policy.set {policy_id, enabled}` komutu, `policy.changed` olayı, `SimFacade.policies()`/`PolicyView`,
## `public_work.road` önizleme ve `PublicWorkView` isteğe bağlı yeniden iskân alanları, `restored.rehoused_returned`,
## `budget.line.resettlement`. Gerçek sim davranışı tests/sim/public_works/resettlement_*; burada yalnız sözleşme
## şekli, varsayılanlar ve MOCK paritesi.

const S := preload("res://tests/contracts/contract_test_support.gd")


func _policy(enabled: bool = true) -> SimCommand:
	return SimCommand.policy_set(&"resettlement", enabled)


# --- Sürüm ---

func test_contract_version_is_1_10_and_older_documents_stay_compatible() -> void:
	assert_str(SimContract.VERSION).is_equal("1.10")
	assert_int(SimContract.VERSION_MAJOR).is_equal(1)
	assert_int(SimContract.VERSION_MINOR).is_equal(10)
	for older in ["1.0", "1.5", "1.6", "1.7", "1.8", "1.9"]:
		assert_bool(SimContract.is_compatible(older)).is_true()
	assert_bool(SimContract.is_compatible("2.0")).is_false()


# --- Komut şekli ---

func test_policy_set_is_a_catalogued_mayor_verb_with_a_name_and_a_boolean() -> void:
	assert_str(String(SimCommand.KIND_POLICY_SET)).is_equal("policy.set")
	assert_bool(SimCommand.CATALOG.has(&"policy.set")).is_true()
	assert_bool(SimCommand.is_forbidden_kind(SimCommand.KIND_POLICY_SET)).is_false()
	assert_bool(_policy().validate_shape().is_empty()).is_true()
	assert_bool(_policy(false).validate_shape().is_empty()).is_true()
	assert_bool(bool(_policy(false).params["enabled"])).is_false()
	assert_str(String(_policy().params["policy_id"])).is_equal("resettlement")


func test_policy_set_rejects_a_missing_or_mistyped_parameter_by_shape() -> void:
	var missing := SimCommand.make(&"policy.set", {"policy_id": &"resettlement"})
	assert_str(String(missing.validate_shape()["reason_key"])).is_equal("command.reject.missing_param")
	var wrong := SimCommand.make(&"policy.set", {"policy_id": &"resettlement", "enabled": 1})
	assert_str(String(wrong.validate_shape()["reason_key"])).is_equal("command.reject.bad_param_type")
	var empty := SimCommand.make(&"policy.set", {"policy_id": &"", "enabled": true})
	assert_str(String(empty.validate_shape()["reason_key"])).is_equal("command.reject.invalid_value")
	var extra := SimCommand.make(&"policy.set", {"policy_id": &"resettlement", "enabled": true, "x": 1})
	assert_str(String(extra.validate_shape()["reason_key"])).is_equal("command.reject.unknown_param")


func test_policy_set_survives_a_json_round_trip_with_canonical_types() -> void:
	var back := SimCommand.from_dict(JSON.parse_string(JSON.stringify(_policy().to_dict())))
	assert_bool(back.params["enabled"] is bool).is_true()
	assert_bool(back.params["policy_id"] is StringName).is_true()
	assert_bool(back.validate_shape().is_empty()).is_true()


func test_the_catalog_still_has_no_private_building_verb() -> void:
	for kind: StringName in SimCommand.CATALOG:
		assert_bool(SimCommand.is_forbidden_kind(kind)).is_false()
		assert_bool(String(kind).begins_with("building.") or String(kind).begins_with("spawn.")).is_false()


# --- Olay ve metin anahtarı ---

func test_policy_changed_event_kind_and_budget_line_key_are_declared() -> void:
	assert_str(String(SimEvent.KIND_POLICY_CHANGED)).is_equal("policy.changed")
	assert_str(String(BudgetLineView.KEY_RESETTLEMENT)).is_equal("budget.line.resettlement")
	assert_bool(BudgetLineView.KEY_RESETTLEMENT != &"budget.line.roads").is_true()


# --- PolicyView ---

func test_policy_view_defaults_say_never_changed_and_off() -> void:
	var v := PolicyView.new()
	assert_bool(v.enabled).is_false()
	assert_int(v.changed_tick).is_equal(-1)
	assert_int(v.changed_by_command).is_equal(0)
	assert_str(String(PolicyView.ID_RESETTLEMENT)).is_equal("resettlement")


func test_policy_view_round_trips_through_dict_json_and_bytes() -> void:
	var v := PolicyView.new()
	v.policy_id = PolicyView.ID_RESETTLEMENT
	v.enabled = true
	v.changed_tick = 12
	v.changed_by_command = 4
	v.provenance = SimContract.PROVENANCE_SIM
	var back := PolicyView.from_dict(JSON.parse_string(JSON.stringify(v.to_dict())))
	assert_bool(back.same_as(v)).is_true()
	assert_bool(PolicyView.from_dict(bytes_to_var(v.to_bytes())).same_as(v)).is_true()
	var old := PolicyView.from_dict({"policy_id": "resettlement"})  # eksik alan = varsayılan (geri uyum)
	assert_int(old.changed_tick).is_equal(-1)
	assert_bool(old.enabled).is_false()


## Sözleşme 1.9 (T-067, D-019 E1) · bekleme listesi verisi: isteğe bağlı alanlar, varsayılan "kimse beklemiyor".
func test_policy_view_waiting_fields_default_to_nobody_waiting_and_round_trip() -> void:
	var v := PolicyView.new()
	assert_int(v.waiting_households).is_equal(0)
	assert_dict(v.waiting_by_region).is_empty()
	assert_int(v.served_households).is_equal(0)
	v.policy_id = PolicyView.ID_RESETTLEMENT
	v.waiting_households = 9
	v.waiting_by_region = {"D1": 6, "D2": 3}
	v.served_households = 4
	var back := PolicyView.from_dict(JSON.parse_string(JSON.stringify(v.to_dict())))
	assert_bool(back.same_as(v)).is_true()
	assert_int(back.waiting_households).is_equal(9)
	assert_dict(back.waiting_by_region).is_equal({"D1": 6, "D2": 3})
	assert_bool(PolicyView.from_dict(bytes_to_var(v.to_bytes())).same_as(v)).is_true()
	var old := PolicyView.from_dict({"policy_id": "resettlement", "enabled": true})  # 1.7/1.8 belgesi
	assert_int(old.waiting_households).is_equal(0)
	assert_dict(old.waiting_by_region).is_empty()


func test_facade_default_for_policies_is_empty_so_older_implementations_still_work() -> void:
	var bare := SimFacadeNoPolicies.new()
	assert_int(bare.policies().size()).is_equal(0)


# --- Yol önizleme / görünüm alanları ---

func test_public_work_view_resettlement_fields_default_to_none_and_round_trip() -> void:
	var w := PublicWorkView.new()
	assert_bool(w.resettlement_applied).is_false()
	assert_int(w.rehoused_households).is_equal(0)
	assert_int(w.unplaced_households).is_equal(0)
	assert_int(w.resettlement_cost).is_equal(0)
	w.resettlement_applied = true
	w.rehoused_households = 7
	w.unplaced_households = 5
	w.resettlement_cost = 1200
	var back := PublicWorkView.from_dict(JSON.parse_string(JSON.stringify(w.to_dict())))
	assert_bool(back.same_as(w)).is_true()
	var old := PublicWorkView.from_dict({"work_id": 1, "command_id": 2})
	assert_bool(old.resettlement_applied).is_false()


func test_resettlement_args_helper_writes_the_four_documented_keys_only() -> void:
	var args := ExpropriationSummary.resettlement_args({"rehoused": 7, "unplaced": 5, "cost": 1200})
	var keys: Array = args.keys()
	keys.sort()
	assert_array(keys).is_equal(["rehoused_households", "resettlement_applied", "resettlement_cost",
		"unplaced_households"])
	assert_bool(bool(args["resettlement_applied"])).is_true()
	assert_int(int(args["rehoused_households"])).is_equal(7)
	assert_int(int(args["unplaced_households"])).is_equal(5)
	assert_int(int(args["resettlement_cost"])).is_equal(1200)
	# politika kapalı / kayıt yok: HİÇ anahtar yazılmaz (1.6 tüketicisi ve kapalı yol bit-bit aynı)
	assert_bool(ExpropriationSummary.resettlement_args({}).is_empty()).is_true()


func test_event_args_carry_the_resettlement_keys_only_when_given_a_record() -> void:
	var summary := {"parcel_ids": PackedInt64Array([1]), "households": 12}
	assert_bool(ExpropriationSummary.event_args(summary).has("rehoused_households")).is_false()
	var with := ExpropriationSummary.event_args(summary, {"rehoused": 7, "unplaced": 5, "cost": 1200})
	assert_int(int(with["rehoused_households"])).is_equal(7)
	assert_int(int(with["unplaced_households"])).is_equal(5)


# --- MOCK paritesi ---

func test_mock_lists_the_resettlement_policy_off_and_never_changed() -> void:
	var f := S.facade(S.SCENARIO_POSITIVE)
	var list := f.policies()
	assert_int(list.size()).is_equal(1)
	assert_str(String(list[0].policy_id)).is_equal("resettlement")
	assert_bool(list[0].enabled).is_false()
	assert_int(list[0].changed_tick).is_equal(-1)
	assert_str(String(list[0].provenance)).is_equal("mock")


func test_mock_policy_set_validates_applies_and_emits_policy_changed() -> void:
	var f := S.facade(S.SCENARIO_POSITIVE)
	var valid := f.validate_command(_policy(true))
	assert_bool(valid.is_rejected()).is_false()
	var queued := f.submit_command(_policy(true))
	assert_str(String(queued.status)).is_equal("queued")
	f.advance(1)
	var after := f.policies()[0]
	assert_bool(after.enabled).is_true()
	assert_int(after.changed_tick).is_equal(1)
	assert_int(after.changed_by_command).is_equal(queued.command_id)
	var events := S.events_of(f, SimEvent.KIND_POLICY_CHANGED)
	assert_int(events.size()).is_equal(1)
	assert_bool(bool(events[0].args.get("enabled", false))).is_true()
	assert_str(String(events[0].args.get("policy_id", ""))).is_equal("resettlement")


func test_mock_policy_set_rejects_an_unknown_policy_and_an_unchanged_value() -> void:
	var f := S.facade(S.SCENARIO_POSITIVE)
	var unknown := f.validate_command(SimCommand.policy_set(&"no_such_policy", true))
	assert_str(String(unknown.reason_key)).is_equal("command.reject.invalid_value")
	assert_str(String(unknown.args.get("param", ""))).is_equal("policy_id")
	var same := f.validate_command(_policy(false))  # zaten kapalı
	assert_str(String(same.reason_key)).is_equal("command.reject.precondition")
	assert_str(String(same.args.get("why", ""))).is_equal("policy.unchanged")


func test_mock_snapshot_hash_ignores_the_policy_and_the_mock_marks_itself() -> void:
	var f := S.facade(S.SCENARIO_POSITIVE)
	for policy in f.policies():
		assert_str(String(policy.provenance)).is_equal("mock")
	assert_array(SimContractChecks.check_facade(f)).is_empty()


## `policies()`i geçersiz kılmayan en küçük uygulama (soyut metodları boş doldurur): varsayılan davranışı sınar.
class SimFacadeNoPolicies extends SimFacade:
	func provenance() -> StringName:
		return SimContract.PROVENANCE_MOCK

	func current_tick() -> int:
		return 0

	func speed() -> int:
		return 0

	func available_speeds() -> PackedInt32Array:
		return PackedInt32Array([0])

	func set_speed(_level: int) -> bool:
		return false

	func advance(_ticks: int) -> int:
		return 0

	func validate_command(_command: SimCommand) -> CommandResult:
		return null

	func submit_command(_command: SimCommand) -> CommandResult:
		return null

	func snapshot() -> SimSnapshot:
		return null

	func parcel_ids(_region_code: StringName = &"") -> PackedInt64Array:
		return PackedInt64Array()

	func parcel_views(_ids: PackedInt64Array) -> Array[ParcelView]:
		return []

	func events_since(_after_seq: int, _max_count: int = 0) -> Array[SimEvent]:
		return []

	func last_event_seq() -> int:
		return 0

	func first_retained_event_seq() -> int:
		return 1

	func reasons_for(_subject_ref: StringName) -> Array[ReasonRecord]:
		return []

	func reason(_reason_id: int) -> ReasonRecord:
		return null
