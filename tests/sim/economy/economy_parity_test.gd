extends SimTestBase
## T-013 ölçüt 8 · Mock/gerçek eşlik: `ux`'in olumlu/olumsuz yatırım senaryolarındaki karar şekli (gerekçe, olaylar,
## parsel görünümü) gerçek ekonomili facade'de AYNI DTO'larla görünür. Şekil eşliği (alan kümesi + tür); değerler
## farklı olabilir. Mock sayıları denge verisi değildir.

const Parity := preload("res://tests/sim/sim_facade_parity_test.gd")
const C := preload("res://tests/contracts/contract_test_support.gd")
const W := preload("res://tests/sim/economy/economy_world.gd")
const S := preload("res://tests/sim/economy/economy_test_support.gd")
const ISOLATE := {"decision": {"review_enabled": 0}}
const MOCK_FACTORS: Array[StringName] = [
	&"reason.factor.demand", &"reason.factor.expected_return", &"reason.factor.infrastructure_capacity",
	&"reason.factor.construction_cost",
]


func _real(good: bool) -> SimFacadeImpl:
	var region := S.favorable() if good else S.unfavorable()
	var f := W.facade(S.merge(ISOLATE, S.regions({"F1": region})))
	f.submit_command(SimCommand.zoning_propose(PackedInt64Array([1]), &"zone.mixed"))
	f.advance(25)
	return f


func _mock(scenario_name: String) -> MockSimFacade:
	var m := C.facade(scenario_name)
	m.submit_command(SimCommand.zoning_propose(PackedInt64Array([1]), &"zone.mixed"))
	m.advance(30)
	return m


func _first(events: Array[SimEvent], message_key: StringName) -> SimEvent:
	for e in events:
		if e.message_key == message_key:
			return e
	return null


func test_positive_investment_reason_has_the_mock_shape_and_a_superset_of_its_factors() -> void:
	var mock_reason: ReasonRecord = _mock(C.SCENARIO_POSITIVE).reasons_for(&"parcel.1")[0]
	var real_reason: ReasonRecord = _real(true).reasons_for(&"parcel.1")[0]
	var diff := Parity.shape_diff(mock_reason.to_dict(), real_reason.to_dict(), "reason")
	assert_array(diff).override_failure_message(str(diff)).is_empty()
	assert_str(String(real_reason.decision_key)).is_equal(String(mock_reason.decision_key))
	assert_str(String(real_reason.outcome)).is_equal("positive")
	assert_str(String(mock_reason.outcome)).is_equal("positive")
	var real_names: Array[StringName] = []
	for factor in real_reason.factors:
		real_names.append(factor.name_key)
	for name in MOCK_FACTORS:
		assert_bool(real_names.has(name)).override_failure_message("mock etkeni gerçekte yok: %s" % name).is_true()
	for i in mini(mock_reason.factors.size(), real_reason.factors.size()):
		var factor_diff := Parity.shape_diff(mock_reason.factors[i].to_dict(), real_reason.factors[i].to_dict(), "factor")
		assert_array(factor_diff).is_empty()
	assert_bool(real_reason.is_consistent()).is_true()


func test_declined_investment_reason_has_the_mock_shape_and_negative_outcome() -> void:
	var mock_reason: ReasonRecord = _mock(C.SCENARIO_DECLINED).reasons_for(&"parcel.1")[0]
	var real_reason: ReasonRecord = _real(false).reasons_for(&"parcel.1")[0]
	var diff := Parity.shape_diff(mock_reason.to_dict(), real_reason.to_dict(), "reason")
	assert_array(diff).override_failure_message(str(diff)).is_empty()
	assert_str(String(real_reason.outcome)).is_equal("negative")
	assert_str(String(mock_reason.outcome)).is_equal("negative")
	assert_bool(real_reason.is_consistent()).is_true()


func test_decision_events_have_the_mock_shape_and_message_keys() -> void:
	var mock_pos := _mock(C.SCENARIO_POSITIVE).events_since(0)
	var real_pos := _real(true).events_since(0)
	for key in [&"event.investor.develop", &"event.construction.started", &"event.zoning.applied"]:
		var m := _first(mock_pos, key)
		var r := _first(real_pos, key)
		assert_object(m).override_failure_message("mock olayı yok: %s" % key).is_not_null()
		assert_object(r).override_failure_message("gerçek olay yok: %s" % key).is_not_null()
		var diff := Parity.shape_diff(m.to_dict(), r.to_dict(), String(key))
		assert_array(diff).override_failure_message(str(diff)).is_empty()
		assert_str(String(r.kind)).is_equal(String(m.kind))
	var mock_neg := _mock(C.SCENARIO_DECLINED).events_since(0)
	var real_neg := _real(false).events_since(0)
	var m_declined := _first(mock_neg, &"event.investor.declined")
	var r_declined := _first(real_neg, &"event.investor.declined")
	assert_object(r_declined).is_not_null()
	assert_array(Parity.shape_diff(m_declined.to_dict(), r_declined.to_dict(), "declined")).is_empty()
	assert_str(String(r_declined.kind)).is_equal(String(SimEvent.KIND_ACTOR_DECIDED))
	assert_int(r_declined.reason_ids.size()).is_equal(1)


func test_event_reason_ids_resolve_to_real_reasons_like_in_the_mock() -> void:
	var f := _real(true)
	for e in f.events_since(0):
		for rid in e.reason_ids:
			assert_object(f.reason(rid)).override_failure_message("olay %d çözülemeyen gerekçe %d" % [e.seq, rid]).is_not_null()
	assert_array(SimContractChecks.check_facade(f)).is_empty()


func test_parcel_view_in_construction_has_the_mock_shape_with_an_investor_owner() -> void:
	var mock_view := _mock(C.SCENARIO_POSITIVE).parcel_views(PackedInt64Array([1]))[0]
	var real_view := _real(true).parcel_views(PackedInt64Array([1]))[0]
	assert_str(String(mock_view.development)).is_equal("under_construction")
	assert_str(String(real_view.development)).is_equal("under_construction")
	var diff := Parity.shape_diff(mock_view.to_dict(), real_view.to_dict(), "parcel")
	assert_array(diff).override_failure_message(str(diff)).is_empty()
	assert_str(String(real_view.owner.kind)).is_equal(String(mock_view.owner.kind))
	assert_int(real_view.reason_ids.size()).is_greater(0)


func test_declined_parcel_view_stays_vacant_with_a_reason_id_like_the_mock() -> void:
	var mock_view := _mock(C.SCENARIO_DECLINED).parcel_views(PackedInt64Array([1]))[0]
	var real_view := _real(false).parcel_views(PackedInt64Array([1]))[0]
	assert_str(String(mock_view.development)).is_equal("vacant")
	assert_str(String(real_view.development)).is_equal("vacant")
	assert_int(real_view.reason_ids.size()).is_equal(mock_view.reason_ids.size())
	assert_array(Parity.shape_diff(mock_view.to_dict(), real_view.to_dict(), "parcel")).is_empty()


func test_all_real_development_values_belong_to_the_contract_vocabulary() -> void:
	var allowed: Array[StringName] = [ParcelView.DEVELOPMENT_VACANT, ParcelView.DEVELOPMENT_PLANNED,
		ParcelView.DEVELOPMENT_UNDER_CONSTRUCTION, ParcelView.DEVELOPMENT_BUILT, ParcelView.DEVELOPMENT_STALLED]
	var f := W.facade(S.regions({"F1": S.favorable(), "F2": S.favorable()}))
	var seen := {}
	for t in 200:
		f.advance(1)
		for v in f.parcel_views(f.parcel_ids()):
			assert_bool(allowed.has(v.development)).override_failure_message("sözleşme dışı: %s" % v.development).is_true()
			seen[String(v.development)] = true
	for stage in ["vacant", "planned", "under_construction", "built"]:
		assert_bool(seen.has(stage)).override_failure_message("görülmeyen aşama: %s" % stage).is_true()


func test_same_command_sequence_gives_the_same_command_result_shape_with_the_economy_installed() -> void:
	# Mevcut T-027 komut eşliği ekonomi kurulunca da geçerli: aynı beş komut, aynı sonuç şekilleri/anahtarları.
	var mock := C.facade(C.SCENARIO_POSITIVE)
	var real := W.facade(ISOLATE)
	var commands: Array[SimCommand] = [
		SimCommand.zoning_propose(PackedInt64Array([1]), &"zone.mixed"),
		SimCommand.zoning_propose(PackedInt64Array([99999]), &"zone.mixed"),
		SimCommand.make(&"building.place", {"parcel_ids": PackedInt64Array([1])}),
		SimCommand.make(&"zoning.propose", {"land_use": &"zone.mixed"}),
	]
	for c in commands:
		var m := mock.submit_command(c)
		var r := real.submit_command(c)
		assert_array(Parity.shape_diff(m.to_dict(), r.to_dict(), "result")).is_empty()
		assert_str(String(r.status)).is_equal(String(m.status))
		assert_str(String(r.reason_key)).is_equal(String(m.reason_key))
