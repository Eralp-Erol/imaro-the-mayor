extends PoliticsTestBase
## T-017 ölçüt 4 · Gündem öğesine yanıt (political-events §1/§5/§7/§8): yetki kapılı seçenekler (`requires.authority`)
## GİZLENMEZ, kilitli görünür ve reddedilir; `defer` her zaman vardır ve öğeyi kapatmaz; etkiler gecikme + süre + eğri
## ile zamana yayılır (SIM-08) ve yalnız mevcut sistem durumlarına yazar; her durumda >=1 yetkisiz bedelli seçenek
## (PH-9); yükselme aşamaları ve süre dolumu; `agenda.respond` komutu.

const ANGRY := {"mobility": 1000, "environment_health": 1000, "services_utilities": 1000}
const TEMPLATE_IDS := ["pe-01", "pe-02", "pe-03", "pe-04", "pe-07"]


func _certain(f: Dictionary, template_id: String) -> void:
	var t: Dictionary = f["templates"][template_id]
	t["weight"] = 1000
	for driver: Dictionary in t["drivers"]:
		driver["lo"] = -100000
		driver["hi"] = -99999


## PE-01 hazır: koruyucu şablonlar; yalnız PE-01 ateşler.
func _protest_handle(edit: Callable = Callable()) -> PoliticsHandle:
	var h := handle(E.regions(STRESS), 6, SEED, func(f: Dictionary) -> void:
		for id: String in TEMPLATE_IDS:
			f["templates"][id]["weight"] = 0
		_certain(f, "pe-01")
		if edit.is_valid():
			edit.call(f))
	tick(h, 1)
	set_books(h, BLOC_HOUSED, ANGRY, {})
	pol(h)["media"]["tone"] = {"mobility": -1000, "services_utilities": -1000, "environment_health": -1000}
	ActorStore.ensure_relation(h.state(), h.context.actors, BLOC_HOUSED, PLAYER)["trust"] = -800
	scan_blocs(h)
	EventEngine.scan(h.state(), h.context)
	assert_int(PoliticsQuery.agenda(h.state(), h.context).size()) \
		.override_failure_message("ön koşul: PE-01 açık").is_equal(1)
	return h


func _item(h: PoliticsHandle) -> Dictionary:
	return PoliticsQuery.agenda(h.state(), h.context, false)[0]


func _option(item: Dictionary, option_id: String) -> Dictionary:
	for option: Dictionary in item["options"]:
		if option["id"] == option_id:
			return option
	return {}


func test_locked_options_are_shown_with_their_reason_not_hidden_and_cannot_be_chosen() -> void:
	var h := _protest_handle(func(f: Dictionary) -> void: f["authority"]["granted"] = ["council_vote"])
	var item := _item(h)
	var ids: Array = item["options"].map(func(o: Dictionary) -> String: return o["id"])
	assert_array(ids).is_equal(["listen", "remedy", "reverse", "defer"])
	var remedy := _option(item, "remedy")
	assert_bool(remedy["available"]).is_false()
	assert_str(remedy["locked_by"]).is_equal("district_works")
	assert_bool(_option(item, "listen")["available"]).is_true()
	assert_bool(_option(item, "defer")["available"]).is_true()
	var check := EventEngine.check_response(h.state(), h.context, item["id"], "remedy")
	assert_str(String(check["code"])).is_equal("precondition")
	assert_str(String(check["args"]["why"])).is_equal("authority.locked")
	assert_str(String(check["args"]["authority"])).is_equal("district_works")
	var refused := EventEngine.respond(h.state(), h.context, item["id"], "remedy")
	assert_bool(refused["ok"]).is_false()
	assert_str(_item(h)["status"]).override_failure_message("reddedilen yanıt öğeyi kapatmamalı").is_equal("open")
	assert_array(pol(h)["events"]["effects"]).is_empty()


func test_granting_the_authority_unlocks_the_option_by_data_alone() -> void:
	var h := _protest_handle()
	var item := _item(h)
	assert_bool(_option(item, "remedy")["available"]).is_true()
	var result := EventEngine.respond(h.state(), h.context, item["id"], "remedy")
	assert_bool(result["ok"]).is_true()
	assert_int(result["scheduled"]).is_equal(1)
	assert_str(_item(h)["status"]).is_equal("resolved")
	assert_str(_item(h)["chosen"]).is_equal("remedy")


func test_unknown_item_option_and_closed_item_are_rejected_with_contract_codes() -> void:
	var h := _protest_handle()
	var item := _item(h)
	assert_str(String(EventEngine.check_response(h.state(), h.context, 99, "listen")["code"])).is_equal("invalid_target")
	var unknown_option := EventEngine.check_response(h.state(), h.context, item["id"], "fly")
	assert_str(String(unknown_option["code"])).is_equal("invalid_value")
	EventEngine.respond(h.state(), h.context, item["id"], "listen")
	var again := EventEngine.check_response(h.state(), h.context, item["id"], "listen")
	assert_str(String(again["code"])).is_equal("precondition")
	assert_str(String(again["args"]["why"])).is_equal("agenda.closed")


func test_every_template_always_keeps_an_unprivileged_costed_option_even_with_no_authority() -> void:
	for authority_set in [[], ["district_works", "council_vote", "rent_protection", "levy_speculation"]]:
		var cfg := pol_valid(func(f: Dictionary) -> void: f["authority"]["granted"] = authority_set)
		for template in cfg.templates:
			var usable := 0
			var has_defer := false
			for option: Dictionary in template["options"]:
				has_defer = has_defer or option["verb"] == "defer"
				var authority := str(option["requires"]["authority"])
				var locked := not authority.is_empty() and not cfg.is_granted(authority)
				var costed: bool = not option["effects"].is_empty() or not option["costs"].is_empty()
				if option["verb"] != "defer" and not locked and costed:
					usable += 1
			assert_bool(has_defer).override_failure_message("%s: defer yok" % template["id"]).is_true()
			assert_int(usable).override_failure_message("%s yetki=%s: kurtarma yolu yok" % [template["id"], authority_set]) \
				.is_greater(0)


func test_defer_keeps_the_item_open_and_only_notes_it() -> void:
	var h := _protest_handle()
	var item := _item(h)
	var result := EventEngine.respond(h.state(), h.context, item["id"], "defer")
	assert_bool(result["ok"]).is_true()
	assert_int(result["scheduled"]).is_equal(0)
	assert_str(_item(h)["status"]).is_equal("open")
	assert_int(_item(h)["deferred"]).is_equal(1)
	assert_array(pol(h)["events"]["effects"]).is_empty()


func test_effect_curves_are_exact_integers_that_sum_to_the_magnitude() -> void:
	for curve in ["step", "linear", "decay"]:
		for magnitude in [-400, -120, 1, 7, 333, 1000]:
			for duration in [1, 7, 90]:
				var previous := 0
				for step in range(1, duration + 1):
					var cumulative := EventEngine.cumulative_amount(curve, magnitude, step, duration)
					if magnitude >= 0:
						assert_int(cumulative).override_failure_message("%s %d/%d adım %d" % [curve, magnitude, duration, step]) \
							.is_greater_equal(previous)
					previous = cumulative
				assert_int(previous).override_failure_message("%s %d/%d toplamı" % [curve, magnitude, duration]) \
					.is_equal(magnitude)
	assert_int(EventEngine.cumulative_amount("decay", 1000, 45, 90)) \
		.override_failure_message("decay öne yüklü: 1-(1-x/D)^2") \
		.is_equal(750)
	assert_int(EventEngine.cumulative_amount("linear", 1000, 45, 90)).is_equal(500)
	assert_int(EventEngine.cumulative_amount("step", 1000, 1, 90)).is_equal(1000)


func test_chosen_effects_spread_over_time_with_delay_and_do_not_land_at_once() -> void:
	var control := _protest_handle()
	var chosen := _protest_handle()
	EventEngine.respond(chosen.state(), chosen.context, _item(chosen)["id"], "remedy")  # -400, gecikme 60, 360 gün linear
	var topic: String = _item(chosen)["topic"]
	var base := int(bloc_book(chosen, BLOC_HOUSED, "grievances")[topic])
	tick(chosen, 59)
	tick(control, 59)
	assert_int(int(bloc_book(chosen, BLOC_HOUSED, "grievances")[topic])) \
		.override_failure_message("gecikmeden önce etki yok") \
		.is_equal(int(bloc_book(control, BLOC_HOUSED, "grievances")[topic]))
	tick(chosen, 61)
	tick(control, 61)
	var mid_chosen := int(bloc_book(chosen, BLOC_HOUSED, "grievances")[topic])
	var mid_control := int(bloc_book(control, BLOC_HOUSED, "grievances")[topic])
	assert_int(mid_chosen).override_failure_message("etki başladı ama tam değil").is_less(mid_control)
	assert_int(mid_control - mid_chosen).is_less(400)
	tick(chosen, 300)
	tick(control, 300)
	assert_array(pol(chosen)["events"]["effects"]).override_failure_message("süre bitince kuyruk boşalır").is_empty()
	assert_bool(base > 0).is_true()


func test_listen_session_raises_trust_once_after_its_delay_through_the_memory_rules() -> void:
	var chosen := _protest_handle()
	var control := _protest_handle()
	var memories: int = ActorStore.actor_ref(chosen.state(), BLOC_HOUSED)["memory"].size()
	EventEngine.respond(chosen.state(), chosen.context, _item(chosen)["id"], "listen")
	var trust := func(h: PoliticsHandle) -> int:
		return int(ActorStore.relation(h.state(), h.context.actors, BLOC_HOUSED, PLAYER)["trust"])
	tick(chosen, 6)
	tick(control, 6)
	assert_int(trust.call(chosen)).override_failure_message("gecikmeden (7 gün) önce fark yok") \
		.is_equal(trust.call(control))
	tick(chosen, 3)
	tick(control, 3)
	assert_int(trust.call(chosen)).override_failure_message("gecikme sonrası güven yükselmeli") \
		.is_greater(trust.call(control))
	assert_int(ActorStore.actor_ref(chosen.state(), BLOC_HOUSED)["memory"].size()).is_greater(memories)


func test_investor_risk_effect_lowers_the_regional_risk_signal() -> void:
	var edit := func(f: Dictionary) -> void:
		for id: String in TEMPLATE_IDS:
			f["templates"][id]["weight"] = 0
		_certain(f, "pe-02")
		f["templates"]["pe-02"]["hard"] = []
	var treated := handle(E.regions(STRESS), 6, SEED, edit)
	var control := handle(E.regions(STRESS), 6, SEED, edit)
	for h in [treated, control]:
		tick(h, 1)
		pol(h)["events"]["agenda"] = []
		var risk: Dictionary = pol(h)["risk"]
		risk["adjust"] = {"F1": 400, "F2": 400}
		EventEngine.scan(h.state(), h.context)
	var item := PoliticsQuery.agenda(treated.state(), treated.context)[0]
	EventEngine.respond(treated.state(), treated.context, item["id"], "incentive")
	tick(treated, 200)
	tick(control, 200)
	var region: String = item["region"]
	assert_bool(region.is_empty()).is_false()
	assert_int(PoliticsQuery.political_risk(treated.state(), treated.context, region)) \
		.override_failure_message("teşvik siyasi riski düşürmeli") \
		.is_less(PoliticsQuery.political_risk(control.state(), control.context, region))
	assert_int(pol(treated)["risk"]["adjust"][region]).is_less(400)


func test_council_friction_effect_shortens_the_delay_of_later_zoning() -> void:
	var edit := func(f: Dictionary) -> void:
		for id: String in TEMPLATE_IDS:
			f["templates"][id]["weight"] = 0
		_certain(f, "pe-03")
		f["templates"]["pe-03"]["hard"] = []
	var h := handle(E.regions(STRESS), 6, SEED, edit)
	tick(h, 1)
	EventEngine.scan(h.state(), h.context)
	var item := PoliticsQuery.agenda(h.state(), h.context)[0]
	EventEngine.respond(h.state(), h.context, item["id"], "revise")
	tick(h, 20)
	assert_int(pol(h)["council"]["friction_adjust"]).is_equal(-2)


func test_media_tone_effect_changes_the_topic_tone() -> void:
	var h := handle(E.regions(STRESS), 6, SEED, func(f: Dictionary) -> void:
		for id: String in TEMPLATE_IDS:
			f["templates"][id]["weight"] = 0
		_certain(f, "pe-04")
		f["templates"]["pe-04"]["hard"] = [])
	tick(h, 1)
	pol(h)["media"]["last_tick"] = 1
	pol(h)["media"]["last"] = {"tick": 1, "newsworthiness": 1000, "lean": 0, "fact": 0}
	set_books(h, BLOC_HOUSED, {"mobility": 600}, {})
	scan_blocs(h)
	EventEngine.scan(h.state(), h.context)
	var item := PoliticsQuery.agenda(h.state(), h.context)[0]
	item["topic"] = "mobility"
	pol(h)["events"]["agenda"][0]["topic"] = "mobility"
	EventEngine.respond(h.state(), h.context, item["id"], "respond")
	tick(h, 9)
	assert_int(int(PoliticsQuery.media_tone(h.state()).get("mobility", 0))).is_greater(0)


func test_ignored_items_escalate_by_stage_while_the_condition_holds_and_expire_at_the_deadline() -> void:
	var h := _protest_handle()
	var item := _item(h)
	assert_int(item["stage"]).is_equal(0)
	# 30. günde protesto sürüyor: yükselme aşaması etki kuyruğa girer, öğe açık kalır
	for day in 31:
		tick(h, 1)
		set_books(h, BLOC_HOUSED, ANGRY, {})
		pol(h)["blocs"][BLOC_HOUSED]["eval"]["tier"] = "protest"
	assert_int(_item(h)["stage"]).override_failure_message("yükselme aşaması işlenmedi").is_equal(1)
	assert_str(_item(h)["status"]).is_equal("open")
	var deadline: int = _item(h)["deadline"]
	tick(h, deadline - h.state().tick)
	assert_str(_item(h)["status"]).is_equal("expired")
	var kinds := events_of(h, &"politics.agenda_resolved").map(func(e: SimEvent) -> String: return String(e.message_key))
	assert_array(kinds).is_equal(["event.agenda.expired"])


func test_an_item_whose_stage_condition_no_longer_holds_lapses_instead_of_escalating() -> void:
	var h := _protest_handle()
	set_books(h, BLOC_HOUSED, {}, {})
	pol(h)["blocs"][BLOC_HOUSED]["eval"]["tier"] = ""
	tick(h, 31)
	pol(h)["blocs"][BLOC_HOUSED]["eval"]["tier"] = ""
	tick(h, 1)
	assert_str(_item(h)["status"]).is_equal("lapsed")
	assert_array(pol(h)["events"]["effects"]).is_empty()


func test_responding_through_the_command_queue_applies_at_the_tick_boundary_with_gated_rejection() -> void:
	var h := _protest_handle(func(f: Dictionary) -> void: f["authority"]["granted"] = ["council_vote"])
	var item := _item(h)
	var seq := Commands.submit(h.state(), AgendaRespondHandler.KIND, {"item_id": item["id"], "option_id": "remedy"})
	assert_int(seq).is_greater_equal(0)
	assert_str(_item(h)["status"]).override_failure_message("komut sınırdan önce uygulanmaz").is_equal("open")
	h.facade.advance(1)
	var rejected := events_of(h, &"command.rejected")
	assert_int(rejected.size()).is_equal(1)
	assert_str(String(rejected[0].message_key)).is_equal("command.reject.precondition")
	assert_str(String(rejected[0].args["why"])).is_equal("authority.locked")
	assert_str(_item(h)["status"]).is_equal("open")
	Commands.submit(h.state(), AgendaRespondHandler.KIND, {"item_id": item["id"], "option_id": "listen"})
	h.facade.advance(1)
	assert_str(_item(h)["status"]).is_equal("resolved")
	assert_str(String(events_of(h, &"command.applied").back().message_key)).is_equal("event.command.applied")
	Commands.submit(h.state(), AgendaRespondHandler.KIND, {"item_id": "x", "option_id": 5})
	h.facade.advance(1)
	assert_str(String(events_of(h, &"command.rejected").back().message_key)).is_equal("command.reject.bad_param_type")


func test_the_agenda_respond_command_is_in_the_contract_catalog_and_goes_through_the_facade() -> void:
	var h := _protest_handle()
	assert_str(String(AgendaRespondHandler.KIND)).is_equal(String(SimCommand.KIND_AGENDA_RESPOND))
	var result := h.facade.submit_command(SimCommand.agenda_respond(_item(h)["id"], &"listen"))
	assert_bool(result.is_rejected()).override_failure_message(String(result.reason_key)).is_false()
	h.facade.advance(1)
	assert_str(_item(h)["status"]).is_equal("resolved")


func test_no_option_ever_places_a_private_building() -> void:
	var cfg := politics_config()
	for template in cfg.templates:
		for option: Dictionary in template["options"]:
			for effect: Dictionary in option["effects"]:
				assert_array(EventSpec.TARGETS).contains([effect["target"]])
				assert_bool(String(effect["target"]).contains("building") or String(effect["target"]).contains("spawn")) \
					.is_false()
