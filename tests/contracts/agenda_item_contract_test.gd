extends GdUnitTestSuite
## T-042b gündem sözleşmesi (ADR-0005 Ek F, v1.5 isteğe bağlı ekleme): `SimFacade.agenda_items()` ve `AgendaItemView`.
## Sim'in açtığı AÇIK gündem öğeleri (PE-01 yerinden edilme dahil) salt okunur ve değer kopyasıdır; varsayılan boş
## listedir (uydurma öğe yok). MOCK paritesi: aynı DTO, `provenance = mock`.

const S := preload("res://tests/contracts/contract_test_support.gd")
const SCENARIO := "mock_scenario_expropriation"
const ROAD := [-45000, 21000, -45000, 11000]


func _road() -> SimCommand:
	return SimCommand.public_work_road(PackedInt64Array(ROAD), &"local", true)


func _facade_after_road() -> MockSimFacade:
	var f := S.facade(SCENARIO)
	f.submit_command(_road())
	f.advance(12)
	return f


func test_default_facade_methods_report_no_agenda_items_and_do_not_invent_any() -> void:
	for scenario_name in S.ALL_SCENARIOS:
		assert_int(S.facade(scenario_name).agenda_items().size()).is_equal(0)


func test_version_is_1_8_and_agenda_items_is_still_optional_with_an_empty_default() -> void:
	assert_str(SimContract.VERSION).is_equal("1.10")  # agenda_items 1.5; ...; 1.8 arazi; 1.9 liste; 1.10 yapılı parsel
	assert_bool(SimContract.REF_AGENDA == &"agenda").is_true()


func test_agenda_item_view_round_trips_through_json_and_has_an_agenda_ref() -> void:
	var v := AgendaItemView.new()
	v.item_id = 3
	v.template_id = &"PE-01"
	v.delivery = &"agenda"
	v.status = AgendaItemView.STATUS_OPEN
	v.region_code = &"D1"
	v.group = ActorRef.make(&"group", 2, &"actor.group.2.name")
	v.opened_tick = 14
	v.deadline_tick = 44
	v.title_key = &"event.pe01.reason"
	v.args = {"topic": "housing", "stage": 0}
	v.reason_ids = PackedInt64Array([5])
	v.cause_refs = PackedStringArray(["command.1", "parcel.2"])
	var back := AgendaItemView.from_dict(JSON.parse_string(JSON.stringify(v.to_dict())))
	assert_bool(back.same_as(v)).is_true()
	assert_str(String(back.ref())).is_equal("agenda.3")
	assert_array(Array(back.cause_refs)).is_equal(["command.1", "parcel.2"])


func test_old_documents_without_agenda_fields_get_defaults() -> void:
	var back := AgendaItemView.from_dict({})
	assert_int(back.item_id).is_equal(0)
	assert_str(String(back.status)).is_equal("open")
	assert_object(back.group).is_null()
	assert_int(back.reason_ids.size()).is_equal(0)


func test_mock_opens_the_pe01_item_only_after_the_displacement_reaction() -> void:
	var f := S.facade(SCENARIO)
	f.submit_command(_road())
	f.advance(2)
	assert_int(f.agenda_items().size()).is_equal(0)
	f.advance(10)
	var items := f.agenda_items()
	assert_int(items.size()).is_equal(1)
	var it := items[0]
	assert_str(String(it.template_id)).is_equal("PE-01")
	assert_str(String(it.status)).is_equal("open")
	assert_str(String(it.region_code)).is_equal("F1")
	assert_str(String(it.provenance)).is_equal("mock")
	assert_bool(it.cause_refs.has("command.1")).is_true()
	assert_int(it.reason_ids.size()).is_greater(0)
	for rid in it.reason_ids:
		assert_object(f.reason(rid)).is_not_null()


func test_agenda_reads_are_value_copies_and_do_not_change_the_observable_state() -> void:
	var f := _facade_after_road()
	var before := S.observable_hash(f)
	var first := f.agenda_items()
	var cause_count := first[0].cause_refs.size()
	first[0].status = AgendaItemView.STATUS_EXPIRED
	first[0].cause_refs.append("parcel.99")
	first.clear()
	assert_int(f.agenda_items().size()).is_equal(1)
	assert_str(String(f.agenda_items()[0].status)).is_equal("open")
	assert_int(f.agenda_items()[0].cause_refs.size()).is_equal(cause_count)
	assert_str(S.observable_hash(f)).is_equal(before)


func test_undoing_the_road_does_not_withdraw_the_agenda_item() -> void:
	var f := _facade_after_road()
	f.submit_command(SimCommand.public_work_undo_last())
	f.advance(2)
	assert_int(f.agenda_items().size()).is_equal(1)  # halk tepkisi geri gelmez (D-011)


func test_agenda_check_accepts_the_mock_item_and_flags_broken_items() -> void:
	var f := _facade_after_road()
	assert_array(Array(SimContractChecks.check_agenda(f))).is_empty()
	assert_array(Array(SimContractChecks.check_facade(f))).is_empty()
	var good := f.agenda_items()[0]
	var unresolved := AgendaItemView.from_dict(good.to_dict())
	unresolved.reason_ids = PackedInt64Array([999])
	var backwards := AgendaItemView.from_dict(good.to_dict())
	backwards.deadline_tick = backwards.opened_tick - 1
	var no_template := AgendaItemView.from_dict(good.to_dict())
	no_template.template_id = &""
	var bad_ref := AgendaItemView.from_dict(good.to_dict())
	bad_ref.cause_refs = PackedStringArray(["not a ref"])
	for item in [unresolved, backwards, no_template, bad_ref]:
		var list: Array[AgendaItemView] = [item]
		assert_int(SimContractChecks.check_agenda_items(f, list).size()) \
			.override_failure_message("ihlal yakalanmalı").is_greater(0)
	var twice: Array[AgendaItemView] = [good, good]
	assert_int(SimContractChecks.check_agenda_items(f, twice).size()).is_greater(0)  # yinelenen kimlik


func test_agenda_view_has_no_aggregate_score_field() -> void:
	var f := _facade_after_road()
	assert_array(Array(SimContractChecks.check_no_aggregate_score(f.agenda_items()[0].to_dict(), "agenda"))).is_empty()
