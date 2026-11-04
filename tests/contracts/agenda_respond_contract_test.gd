extends GdUnitTestSuite
## Gündem yanıtı sözleşmesi (ADR-0005 Ek F, v1.5 isteğe bağlı ek): `agenda.respond {item_id, option_id}` komutu ve
## `AgendaItemView.options` (`AgendaOptionView`). Katalog beyaz listede kalır (CAN-03); seçenek etkisizse gösterilmez;
## mock gerçek sim ile aynı ret kodlarını verir. Sürüm 1.5 kalır.

const S := preload("res://tests/contracts/contract_test_support.gd")
const SCENARIO := "mock_scenario_expropriation"
const ROAD := [-45000, 21000, -45000, 11000]


func _facade_with_item() -> MockSimFacade:
	var f := S.facade(SCENARIO)
	f.submit_command(SimCommand.public_work_road(PackedInt64Array(ROAD), &"local", true))
	f.advance(12)
	assert_int(f.agenda_items().size()).override_failure_message("ön koşul: mock PE-01 öğesi").is_equal(1)
	return f


func _reason_of(cmd: SimCommand) -> String:
	var problem := cmd.validate_shape()
	return "" if problem.is_empty() else String(problem["reason_key"])


func _effect(target: String = "bloc.grievance", direction: int = -1) -> Dictionary:
	return {"target": target, "scope": "trigger_topic", "direction": direction, "delay_days": 7,
		"duration_days": 90, "curve": "decay"}


func _option(id: String = "listen") -> AgendaOptionView:
	var o := AgendaOptionView.new()
	o.option_id = StringName(id)
	o.verb = &"listen_session"
	o.label_key = &"event.pe01.opt.listen"
	o.available = true
	o.effects = [_effect()]
	return o


# --- Komut kataloğu ---

func test_version_is_1_8_and_the_command_is_a_catalogued_mayor_verb() -> void:
	assert_str(SimContract.VERSION).is_equal("1.9")  # agenda.respond 1.5'te geldi; ...; 1.7 yeniden iskân; 1.8 arazi; 1.9
	assert_bool(SimCommand.CATALOG.has(&"agenda.respond")).is_true()
	assert_str(String(SimCommand.KIND_AGENDA_RESPOND)).is_equal("agenda.respond")
	assert_bool(SimCommand.is_forbidden_kind(SimCommand.KIND_AGENDA_RESPOND)).is_false()


func test_catalog_still_has_no_kind_that_creates_private_buildings() -> void:
	for kind: StringName in SimCommand.CATALOG:
		for prefix in SimCommand.FORBIDDEN_PREFIXES:
			assert_bool(String(kind).begins_with(prefix)).override_failure_message(String(kind)).is_false()


func test_agenda_respond_factory_builds_a_shape_valid_command() -> void:
	var c := SimCommand.agenda_respond(3, &"listen")
	assert_str(String(c.kind)).is_equal("agenda.respond")
	assert_int(c.params["item_id"]).is_equal(3)
	assert_str(String(c.params["option_id"])).is_equal("listen")
	assert_str(_reason_of(c)).is_empty()


func test_shape_violations_use_the_shared_reason_keys() -> void:
	var cases := [
		[SimCommand.make(&"agenda.respond", {"option_id": &"listen"}), CommandResult.REJECT_MISSING_PARAM],
		[SimCommand.make(&"agenda.respond", {"item_id": 1}), CommandResult.REJECT_MISSING_PARAM],
		[SimCommand.make(&"agenda.respond", {"item_id": 1, "option_id": "listen"}), CommandResult.REJECT_BAD_PARAM_TYPE],
		[SimCommand.make(&"agenda.respond", {"item_id": "1", "option_id": &"listen"}),
			CommandResult.REJECT_BAD_PARAM_TYPE],
		[SimCommand.agenda_respond(-2, &"listen"), CommandResult.REJECT_INVALID_VALUE],
		[SimCommand.agenda_respond(1, &""), CommandResult.REJECT_INVALID_VALUE],
		[SimCommand.make(&"agenda.respond", {"item_id": 1, "option_id": &"listen", "building": 1}),
			CommandResult.REJECT_UNKNOWN_PARAM],
	]
	for c: Array in cases:
		assert_str(_reason_of(c[0])).is_equal(String(c[1]))


func test_command_survives_a_json_round_trip_with_canonical_types() -> void:
	var back := SimCommand.from_dict(JSON.parse_string(JSON.stringify(SimCommand.agenda_respond(4, &"remedy").to_dict())))
	assert_str(_reason_of(back)).is_empty()
	assert_int(back.params["item_id"]).is_equal(4)
	assert_int(typeof(back.params["option_id"])).is_equal(TYPE_STRING_NAME)


# --- DTO ---

func test_option_view_round_trips_through_json_and_old_documents_get_defaults() -> void:
	var o := _option("remedy")
	o.available = false
	o.locked_by = &"district_works"
	var back := AgendaOptionView.from_dict(JSON.parse_string(JSON.stringify(o.to_dict())))
	assert_bool(back.same_as(o)).is_true()
	var empty := AgendaOptionView.from_dict({})
	assert_bool(empty.available).is_false()
	assert_int(empty.effects.size()).is_equal(0)


func test_item_view_with_options_round_trips_and_old_items_have_no_options() -> void:
	var v := AgendaItemView.new()
	v.item_id = 2
	v.template_id = &"PE-01"
	v.options = [_option("listen"), _option("reverse")]
	var back := AgendaItemView.from_dict(JSON.parse_string(JSON.stringify(v.to_dict())))
	assert_bool(back.same_as(v)).is_true()
	assert_int(back.options.size()).is_equal(2)
	assert_int(AgendaItemView.from_dict({}).options.size()).is_equal(0)
	var legacy := v.to_dict()
	legacy.erase("options")
	assert_int(AgendaItemView.from_dict(legacy).options.size()).is_equal(0)


func test_option_effect_previews_are_value_copies() -> void:
	var f := _facade_with_item()
	var first := f.agenda_items()[0]
	first.options[0].effects[0]["direction"] = 99
	first.options.clear()
	var again := f.agenda_items()[0]
	assert_int(again.options.size()).is_greater(0)
	assert_int(int(again.options[0].effects[0]["direction"])).is_not_equal(99)


# --- Sözleşme denetimi ---

func test_check_accepts_the_mock_item_with_options() -> void:
	var f := _facade_with_item()
	assert_array(Array(SimContractChecks.check_agenda(f))).is_empty()
	assert_array(Array(SimContractChecks.check_facade(f))).is_empty()


func test_check_flags_dishonest_or_malformed_options() -> void:
	var f := _facade_with_item()
	var good := f.agenda_items()[0]
	var broken: Array[Callable] = [
		func(it: AgendaItemView) -> void: it.options.append(it.options[0]),  # yinelenen seçenek kimliği
		func(it: AgendaItemView) -> void: it.options[0].effects = [],  # etkisiz seçenek = sahte düğme
		func(it: AgendaItemView) -> void: it.options[0].label_key = &"",
		func(it: AgendaItemView) -> void: it.options[0].option_id = &"",
		func(it: AgendaItemView) -> void:
			it.options[0].available = false
			it.options[0].locked_by = &"",  # kilitli ama nedeni yok
		func(it: AgendaItemView) -> void: it.options[0].locked_by = &"district_works",  # açık ama kilit nedeni var
		func(it: AgendaItemView) -> void: it.options[0].effects[0]["direction"] = 0,  # yönsüz etki
		func(it: AgendaItemView) -> void: it.options[0].effects[0]["overall_score"] = 5,  # SIM-09
	]
	for mutate in broken:
		var item := AgendaItemView.from_dict(good.to_dict())
		mutate.call(item)
		var list: Array[AgendaItemView] = [item]
		assert_int(SimContractChecks.check_agenda_items(f, list).size()) \
			.override_failure_message("ihlal yakalanmalı").is_greater(0)


# --- Mock davranışı (gerçek sim ile aynı ret kodları) ---

func test_mock_lists_options_with_a_locked_one_shown_with_its_authority() -> void:
	var item := _facade_with_item().agenda_items()[0]
	var ids: Array[String] = []
	for o in item.options:
		ids.append(String(o.option_id))
		assert_int(o.effects.size()).is_greater(0)
	assert_array(ids).is_equal(["listen", "remedy", "reverse"])
	var remedy := item.options[1]
	assert_bool(remedy.available).is_false()
	assert_str(String(remedy.locked_by)).is_equal("district_works")


func test_mock_valid_response_closes_the_item_and_emits_command_applied_for_it() -> void:
	var f := _facade_with_item()
	var r := f.submit_command(SimCommand.agenda_respond(1, &"listen"))
	assert_str(String(r.status)).is_equal("queued")
	assert_int(f.agenda_items().size()).is_equal(1)  # sınırdan önce uygulanmaz
	f.advance(1)
	assert_int(f.agenda_items().size()).is_equal(0)
	var applied := S.events_of(f, SimEvent.KIND_COMMAND_APPLIED).filter(func(e: SimEvent) -> bool:
		return e.args.get("kind", &"") == SimCommand.KIND_AGENDA_RESPOND)
	assert_int(applied.size()).is_equal(1)
	assert_array(Array(applied[0].subjects)).contains(["agenda.1"])


func test_mock_rejections_use_the_same_codes_as_the_real_sim() -> void:
	var f := _facade_with_item()
	var cases := [
		[SimCommand.agenda_respond(77, &"listen"), CommandResult.REJECT_INVALID_TARGET, "ref", "agenda.77"],
		[SimCommand.agenda_respond(1, &"fly"), CommandResult.REJECT_INVALID_VALUE, "param", "option_id"],
		[SimCommand.agenda_respond(1, &"defer"), CommandResult.REJECT_INVALID_VALUE, "param", "option_id"],
		[SimCommand.agenda_respond(1, &"remedy"), CommandResult.REJECT_PRECONDITION, "why", "authority.locked"],
	]
	var before := S.observable_hash(f)
	for c: Array in cases:
		var r := f.submit_command(c[0])
		assert_str(String(r.status)).is_equal("rejected")
		assert_str(String(r.reason_key)).is_equal(String(c[1]))
		assert_str(str(r.args[c[2]])).is_equal(c[3])
		assert_str(String(f.validate_command(c[0]).reason_key)).is_equal(String(c[1]))
	assert_str(S.observable_hash(f)).override_failure_message("ret durumu değiştirmez").is_equal(before)
	f.submit_command(SimCommand.agenda_respond(1, &"listen"))
	f.advance(1)
	var again := f.submit_command(SimCommand.agenda_respond(1, &"listen"))
	assert_str(String(again.reason_key)).is_equal(String(CommandResult.REJECT_PRECONDITION))
	assert_str(String(again.args["why"])).is_equal("agenda.closed")
	f.advance(40)  # süresi dolan öğe de kapalıdır
	assert_str(String(f.submit_command(SimCommand.agenda_respond(1, &"reverse")).args["why"])).is_equal("agenda.closed")


func test_mock_without_any_agenda_item_rejects_the_command_with_an_invalid_target() -> void:
	for scenario_name in S.ALL_SCENARIOS:
		var r := S.facade(scenario_name).submit_command(SimCommand.agenda_respond(1, &"listen"))
		assert_str(String(r.reason_key)).is_equal(String(CommandResult.REJECT_INVALID_TARGET))


func test_mock_response_never_touches_parcels() -> void:
	var f := _facade_with_item()
	var parcels := StateHash.of(SimDto.dicts_of(f.parcel_views(f.parcel_ids())))
	f.submit_command(SimCommand.agenda_respond(1, &"reverse"))
	f.advance(3)
	assert_str(StateHash.of(SimDto.dicts_of(f.parcel_views(f.parcel_ids())))).is_equal(parcels)  # CAN-03


func test_mock_runs_are_deterministic() -> void:
	var a := _facade_with_item()
	var b := _facade_with_item()
	for f in [a, b]:
		f.submit_command(SimCommand.agenda_respond(1, &"listen"))
		f.advance(5)
	assert_str(S.observable_hash(a)).is_equal(S.observable_hash(b))
