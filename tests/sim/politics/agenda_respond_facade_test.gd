# gdlint:disable=max-public-methods
extends "res://tests/sim/politics/reaction_world_base.gd"
## Gündem yanıtı, GERÇEK sim (ADR-0005 Ek F, v1.5 isteğe bağlı ek): `agenda.respond {item_id, option_id}` sözleşme
## kataloğunda; `agenda_items()` her öğeye YALNIZ gerçekten etki üretebilen seçenekleri koyar (sahte düğme yok);
## komut tick sınırında uygulanır, gerekçeli reddedilir, deterministik ve kayıt/yükleme sürekli; yanıt asla özel bina
## yaratmaz (CAN-03). Seçenek etkileri yalnız `data/politics/events/*.json` verisinden ve mevcut mekanizmalardan gelir.

const DEFAULT_OPTIONS := ["listen", "remedy", "reverse"]


func _open_world(edit: Callable = Callable()) -> PoliticsHandle:
	var h: PoliticsHandle = _world(true, edit)["handle"]
	h.facade.advance(14)
	assert_int(h.facade.agenda_items().size()).override_failure_message("ön koşul: PE-01 öğesi açık").is_greater(0)
	return h


func _item(h: PoliticsHandle) -> AgendaItemView:
	return h.facade.agenda_items()[0]


func _option(item: AgendaItemView, option_id: String) -> AgendaOptionView:
	for o in item.options:
		if String(o.option_id) == option_id:
			return o
	return null


func _respond(h: PoliticsHandle, option_id: String) -> CommandResult:
	return h.facade.submit_command(SimCommand.agenda_respond(_item(h).item_id, StringName(option_id)))


func _rejected_keys(h: PoliticsHandle) -> Array[String]:
	var out: Array[String] = []
	for e in events_of(h, &"command.rejected"):
		out.append(String(e.message_key))
	return out


func _template_options() -> Dictionary:
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(EVENTS_DIR + "pe-01.json"))
	var out := {}
	for option: Dictionary in raw["options"]:
		out[option["id"]] = option
	return out


# --- Seçenekler sözleşmede ---

func test_the_displacement_item_lists_exactly_the_options_that_can_act_and_no_effectless_one() -> void:
	var h := _open_world()
	var ids: Array[String] = []
	for o in _item(h).options:
		ids.append(String(o.option_id))
		assert_int(o.effects.size()).override_failure_message("%s: etkisiz seçenek gösterilmez" % o.option_id) \
			.is_greater(0)
	assert_array(ids).is_equal(DEFAULT_OPTIONS)  # `defer` etkisizdir: listede YOK


func test_option_previews_come_from_the_template_data_in_direction_delay_duration_and_curve() -> void:
	var h := _open_world()
	var data := _template_options()
	for o in _item(h).options:
		var source: Array = data[String(o.option_id)]["effects"]
		assert_str(String(o.label_key)).is_equal(data[String(o.option_id)]["label_key"])
		assert_str(String(o.verb)).is_equal(data[String(o.option_id)]["verb"])
		assert_int(o.effects.size()).is_less_equal(source.size())
		for preview: Dictionary in o.effects:
			var match_found := source.any(func(e: Dictionary) -> bool:
				return e["target"] == String(preview["target"]) and e["scope"] == String(preview["scope"]) \
					and signi(int(e["magnitude"])) == int(preview["direction"]) \
					and int(e["delay_days"]) == int(preview["delay_days"]) \
					and int(e["duration_days"]) == int(preview["duration_days"]) \
					and e["curve"] == String(preview["curve"]))
			assert_bool(match_found).override_failure_message("%s: önizleme veriyle eşleşmiyor: %s" % [o.option_id, preview]) \
				.is_true()


func test_options_carry_no_cost_numbers_because_the_sim_does_not_charge_them() -> void:
	var o := _option(_item(_open_world()), "remedy")
	assert_bool(o.to_dict().has("costs")).is_false()  # bütçe/siyasi sermaye bedeli sim'de düşülmüyor: sahte bedel yok


func test_dead_effects_are_not_previewed_and_an_option_with_only_dead_effects_disappears() -> void:
	var h := _open_world()
	pol(h)["events"]["agenda"][0]["topic"] = ""  # konu yok: şikâyet etkileri hedefsiz kalır
	var item := _item(h)
	assert_object(_option(item, "remedy")).override_failure_message("yalnız şikâyet etkisi var: ölü").is_null()
	var listen := _option(item, "listen")
	assert_object(listen).is_not_null()
	assert_int(listen.effects.size()).is_equal(1)
	assert_str(String(listen.effects[0]["target"])).is_equal("relation.trust")


func test_a_locked_option_stays_visible_with_its_authority_and_is_not_available() -> void:
	var h := _open_world(func(f: Dictionary) -> void: f["authority"]["granted"] = ["council_vote"])
	var remedy := _option(_item(h), "remedy")
	assert_object(remedy).is_not_null()
	assert_bool(remedy.available).is_false()
	assert_str(String(remedy.locked_by)).is_equal("district_works")
	var listen := _option(_item(h), "listen")
	assert_bool(listen.available).is_true()
	assert_str(String(listen.locked_by)).is_equal("")


func test_reading_options_does_not_change_the_state_hash() -> void:
	var h := _open_world()
	var twin := _open_world()
	for _i in 3:
		h.facade.agenda_items()
	assert_str(h.facade.state_hash()).is_equal(twin.facade.state_hash())


func test_the_contract_checks_pass_on_the_real_item_with_options() -> void:
	var h := _open_world()
	assert_array(Array(SimContractChecks.check_agenda(h.facade))).is_empty()
	assert_array(Array(SimContractChecks.check_facade(h.facade))).is_empty()


# --- Komut: kabul ve etki ---

func test_a_valid_response_is_queued_applied_at_the_boundary_and_closes_the_item() -> void:
	var h := _open_world()
	var item_id := _item(h).item_id
	var result := _respond(h, "listen")
	assert_str(String(result.status)).is_equal("queued")
	assert_int(result.command_id).is_greater(0)
	assert_str(str(pol(h)["events"]["agenda"][0]["chosen"])).override_failure_message("komut sınırdan önce uygulanmaz") \
		.is_equal("")
	assert_int((pol(h)["events"]["effects"] as Array).size()).is_equal(0)
	assert_int(h.facade.agenda_items().size()).is_equal(1)
	h.facade.advance(1)
	for it in h.facade.agenda_items():
		assert_int(it.item_id).override_failure_message("yanıtlanan öğe açık listeden çıkar").is_not_equal(item_id)
	var applied := events_of(h, &"command.applied").filter(func(e: SimEvent) -> bool:
		return e.args.get("kind", &"") == SimCommand.KIND_AGENDA_RESPOND)
	assert_int(applied.size()).is_equal(1)
	assert_array(Array(applied[0].subjects)).contains(["agenda.%d" % item_id])
	assert_str(String(pol(h)["events"]["agenda"][0]["chosen"])).is_equal("listen")


func test_a_chosen_option_really_moves_the_sim_while_an_unanswered_twin_does_not() -> void:
	var answered := _open_world()
	var twin := _open_world()
	var trust := func(h: PoliticsHandle) -> int:
		return int(ActorStore.relation(h.state(), h.context.actors, BLOC_HOUSED, PLAYER)["trust"])
	_respond(answered, "listen")
	answered.facade.advance(20)  # dinleme: 7 gün gecikmeli, tek seferlik güven artışı (hafıza kuralından)
	twin.facade.advance(20)
	var a: int = trust.call(answered)
	var b: int = trust.call(twin)
	assert_int(a).override_failure_message("dinleme güveni artırmalı (yanıtlı %d, yanıtsız %d)" % [a, b]).is_greater(b)
	assert_str(answered.facade.state_hash()).is_not_equal(twin.facade.state_hash())


func test_validate_command_is_a_dry_run_and_never_queues() -> void:
	var h := _open_world()
	var twin := _open_world()
	var result := h.facade.validate_command(SimCommand.agenda_respond(_item(h).item_id, &"listen"))
	assert_str(String(result.status)).is_equal("valid")
	assert_int(result.command_id).is_equal(0)
	assert_str(h.facade.state_hash()).override_failure_message("kuru koşu durumu değiştirmez") \
		.is_equal(twin.facade.state_hash())
	h.facade.advance(1)
	twin.facade.advance(1)
	assert_str(h.facade.state_hash()).is_equal(twin.facade.state_hash())
	assert_int(h.facade.agenda_items().size()).override_failure_message("kuru koşu öğeyi kapatmaz").is_equal(1)


# --- Komut: gerekçeli ret (durum değişmez) ---

func test_rejections_carry_contract_codes_and_leave_the_state_untouched() -> void:
	var h := _open_world(func(f: Dictionary) -> void: f["authority"]["granted"] = ["council_vote"])
	var id := _item(h).item_id
	var cases := [
		[SimCommand.agenda_respond(9999, &"listen"), "command.reject.invalid_target", {"ref": "agenda.9999"}],
		[SimCommand.agenda_respond(id, &"fly"), "command.reject.invalid_value", {"param": "option_id"}],
		[SimCommand.agenda_respond(id, &"defer"), "command.reject.invalid_value", {"param": "option_id"}],
		[SimCommand.agenda_respond(id, &"remedy"), "command.reject.precondition",
			{"why": "authority.locked", "authority": "district_works"}],
	]
	var before := h.facade.state_hash()
	for c: Array in cases:
		var result := h.facade.submit_command(c[0])
		assert_str(String(result.status)).is_equal("rejected")
		assert_str(String(result.reason_key)).is_equal(c[1])
		for k: String in c[2]:
			assert_str(str(result.args[k])).override_failure_message("%s.%s" % [c[1], k]).is_equal(str(c[2][k]))
	assert_str(h.facade.state_hash()).override_failure_message("reddedilen komut durumu değiştirmez").is_equal(before)
	assert_int(h.facade.agenda_items().size()).is_equal(1)


func test_an_already_answered_item_is_rejected_as_closed() -> void:
	var h := _open_world()
	var id := _item(h).item_id
	_respond(h, "listen")
	h.facade.advance(1)
	var again := h.facade.submit_command(SimCommand.agenda_respond(id, &"listen"))
	assert_str(String(again.reason_key)).is_equal("command.reject.precondition")
	assert_str(String(again.args["why"])).is_equal("agenda.closed")


func test_two_responses_queued_for_one_item_apply_once_and_the_second_is_rejected_at_the_boundary() -> void:
	var h := _open_world()
	var id := _item(h).item_id
	h.facade.submit_command(SimCommand.agenda_respond(id, &"listen"))
	h.facade.submit_command(SimCommand.agenda_respond(id, &"reverse"))
	h.facade.advance(1)
	assert_str(String(pol(h)["events"]["agenda"][0]["chosen"])).is_equal("listen")
	assert_array(_rejected_keys(h)).is_equal(["command.reject.precondition"])


func test_shape_errors_are_rejected_before_the_sim_sees_them() -> void:
	var h := _open_world()
	var id := _item(h).item_id
	var cases := [
		[SimCommand.make(&"agenda.respond", {"item_id": id}), "command.reject.missing_param"],
		[SimCommand.make(&"agenda.respond", {"item_id": id, "option_id": "listen"}), "command.reject.bad_param_type"],
		[SimCommand.make(&"agenda.respond", {"item_id": str(id), "option_id": &"listen"}),
			"command.reject.bad_param_type"],
		[SimCommand.make(&"agenda.respond", {"item_id": id, "option_id": &""}), "command.reject.invalid_value"],
		[SimCommand.make(&"agenda.respond", {"item_id": -1, "option_id": &"listen"}), "command.reject.invalid_value"],
		[SimCommand.make(&"agenda.respond", {"item_id": id, "option_id": &"listen", "force": true}),
			"command.reject.unknown_param"],
	]
	for c: Array in cases:
		assert_str(String(h.facade.submit_command(c[0]).reason_key)).is_equal(c[1])


func test_a_facade_without_politics_rejects_the_command_with_a_not_built_reason() -> void:
	var f := SimFacadeImpl.create(SEED, ListParcelSource.create(&"agenda.plain", _views()))
	var result := f.submit_command(SimCommand.agenda_respond(1, &"listen"))
	assert_str(String(result.reason_key)).is_equal("command.reject.precondition")
	assert_str(String(result.args["why"])).is_equal("system.not_built")
	assert_str(String(result.args["system"])).is_equal("agenda")


# --- Determinizm / kayıt ---

func test_same_commands_give_the_same_hash_and_a_different_choice_gives_a_different_one() -> void:
	var a := _open_world()
	var b := _open_world()
	var c := _open_world()
	_respond(a, "listen")
	_respond(b, "listen")
	_respond(c, "reverse")
	for h in [a, b, c]:
		h.facade.advance(60)
	assert_str(a.facade.state_hash()).is_equal(b.facade.state_hash())
	assert_str(a.facade.state_hash()).is_not_equal(c.facade.state_hash())


func test_save_load_continue_equals_an_uninterrupted_run_with_a_pending_response() -> void:
	var straight := _open_world()
	_respond(straight, "remedy")
	straight.facade.advance(90)
	var first := _open_world()
	_respond(first, "remedy")
	first.facade.advance(30)  # etkiler kuyrukta (gecikme 60 gün)
	assert_int((pol(first)["events"]["effects"] as Array).size()).is_greater(0)
	var restored: PoliticsHandle = _world(false)["handle"]
	var loaded := restored.facade.import_save(first.facade.export_save())
	assert_bool(loaded.ok).override_failure_message(loaded.message).is_true()
	assert_str(restored.facade.state_hash()).is_equal(first.facade.state_hash())
	restored.facade.advance(60)
	assert_str(restored.facade.state_hash()).is_equal(straight.facade.state_hash())


func test_a_command_queued_before_save_is_applied_after_load_like_the_straight_run() -> void:
	var straight := _open_world()
	_respond(straight, "listen")
	straight.facade.advance(40)
	var first := _open_world()
	_respond(first, "listen")  # kuyrukta, henüz uygulanmadı
	var restored: PoliticsHandle = _world(false)["handle"]
	assert_bool(restored.facade.import_save(first.facade.export_save()).ok).is_true()
	restored.facade.advance(40)
	assert_str(restored.facade.state_hash()).is_equal(straight.facade.state_hash())


# --- CAN-03 ---

func test_responding_never_places_a_private_building() -> void:
	for option_id in DEFAULT_OPTIONS:
		var h := _open_world()
		var before := h.facade.parcel_views(h.facade.parcel_ids()).filter(
			func(v: ParcelView) -> bool: return v.developed_by_sim).size()
		_respond(h, option_id)
		h.facade.advance(1)
		var after_command := h.facade.parcel_views(h.facade.parcel_ids()).filter(
			func(v: ParcelView) -> bool: return v.developed_by_sim).size()
		assert_int(after_command).override_failure_message("%s: komut anında bina doğdu" % option_id) \
			.is_equal(before)
		h.facade.advance(240)
		var developed: Array[int] = []
		for v in h.facade.parcel_views(h.facade.parcel_ids()):
			if v.developed_by_sim:
				developed.append(v.id)
		for id in developed:  # her sim binasının arkasında bir YATIRIMCI kararı kaydı var (aktör kararı)
			var has_decision := reasons_of(h, "decision.investor.develop").any(func(rec: Dictionary) -> bool:
				return (rec["subjects"] as PackedStringArray).has("parcel.%d" % id))
			assert_bool(has_decision).override_failure_message("%s: parsel %d aktör kararsız gelişti" % [option_id, id]) \
				.is_true()
		for id in [1, 2, 3]:  # alınan parseller yatırımcıya dönmez
			assert_str(String(h.facade.parcel_views(PackedInt64Array([id]))[0].development)).is_equal("taken")


func test_the_tick_that_applies_a_response_leaves_every_parcel_exactly_as_the_unanswered_twin() -> void:
	# Komut parsel/ekonomi sütunlarına yazarsa (var olan bir yapıyı değiştirmek dahil) ikizden ayrışırdı.
	for option_id in DEFAULT_OPTIONS:
		var answered := _open_world()
		var twin := _open_world()
		_respond(answered, option_id)
		answered.facade.advance(1)
		twin.facade.advance(1)
		var a := SimDto.dicts_of(answered.facade.parcel_views(answered.facade.parcel_ids()))
		var b := SimDto.dicts_of(twin.facade.parcel_views(twin.facade.parcel_ids()))
		assert_array(a).override_failure_message("%s: komut anında parsel değişti" % option_id).is_equal(b)
		assert_str(String(EconomyState.data(answered.state())["stage"].hex_encode())) \
			.is_equal(String(EconomyState.data(twin.state())["stage"].hex_encode()))


func test_the_respond_event_names_only_the_agenda_item_never_a_parcel() -> void:
	var h := _open_world()
	_respond(h, "reverse")
	h.facade.advance(1)
	for e in events_of(h, &"command.applied"):
		if e.args.get("kind", &"") == SimCommand.KIND_AGENDA_RESPOND:
			for subject in e.subjects:
				assert_bool(String(subject).begins_with("agenda.") or String(subject).begins_with("command.")) \
					.override_failure_message("beklenmeyen konu %s" % subject).is_true()


func test_the_catalog_kind_is_a_mayor_verb_and_no_option_effect_targets_buildings() -> void:
	assert_bool(SimCommand.is_forbidden_kind(SimCommand.KIND_AGENDA_RESPOND)).is_false()
	assert_bool(SimCommand.CATALOG.has(SimCommand.KIND_AGENDA_RESPOND)).is_true()
	for template in politics_config().templates:
		for option: Dictionary in template["options"]:
			for effect: Dictionary in option["effects"]:
				assert_array(EventSpec.TARGETS).contains([effect["target"]])
