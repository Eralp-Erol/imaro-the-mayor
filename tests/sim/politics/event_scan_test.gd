extends PoliticsTestBase
## T-017 ölçüt 4 · Siyasi olaylar PE-01/02/03/04/07, `agenda` düzeyi (political-events §1-§4): olay YAZILMAZ,
## sistem durumundan tetiklenir; tarayıcı deterministik ve tohumludur; ateşleme `decision.event.fire` gerekçesidir
## (skor = hazard - çekiliş, eşik 0); cooldown/silahlanma/mutex/üst sınırlar; kapalı etiket ve kademe kapıları.

const ANGRY := {"mobility": 1000, "environment_health": 1000, "services_utilities": 1000}
const TEMPLATES := ["pe-01", "pe-02", "pe-03", "pe-04", "pe-07"]


## Şablon baskısını 1000'e, ağırlığı 1000'e kilitler (olasılık 1): sistem durumu tetiğin tek belirleyicisi olur.
func _certain(f: Dictionary, template_id: String) -> void:
	var t: Dictionary = f["templates"][template_id]
	t["weight"] = 1000
	for driver: Dictionary in t["drivers"]:
		driver["lo"] = -100000
		driver["hi"] = -99999


func _all_certain(f: Dictionary) -> void:
	for template_id in TEMPLATES:
		_certain(f, template_id)


func _certain_only(ids: Array) -> Callable:
	return func(f: Dictionary) -> void:
		for template_id: String in TEMPLATES:
			if ids.has(template_id):
				_certain(f, template_id)
			else:
				f["templates"][template_id]["weight"] = 0


func _ready_handle(edit: Callable = Callable(), economy: Dictionary = {}) -> PoliticsHandle:
	var h := handle(E.merge(economy, E.regions(STRESS)) if economy.is_empty() else economy, 6, SEED, edit)
	tick(h, 1)
	return h


func _scan(h: PoliticsHandle) -> void:
	EventEngine.scan(h.state(), h.context)


func _items(h: PoliticsHandle, template_id: String = "") -> Array[Dictionary]:
	return PoliticsQuery.agenda(h.state(), h.context, false).filter(
		func(item: Dictionary) -> bool: return template_id.is_empty() or item["template"] == template_id)


## PE-01 durumu: yüksek şikâyet + olumsuz basın + düşük güven -> protesto basamağı.
func _protest(h: PoliticsHandle) -> void:
	set_books(h, BLOC_HOUSED, ANGRY, {})
	pol(h)["media"]["tone"] = {"mobility": -1000, "services_utilities": -1000, "environment_health": -1000}
	ActorStore.ensure_relation(h.state(), h.context.actors, BLOC_HOUSED, PLAYER)["trust"] = -800
	scan_blocs(h)
	assert_str(String(view_of(h, BLOC_HOUSED).reaction)).override_failure_message("ön koşul: protesto").is_equal("protest")


func test_pe01_fires_from_a_protesting_bloc_with_a_reasoned_causal_record() -> void:
	var h := _ready_handle(_certain_only(["pe-01"]))
	_protest(h)
	_scan(h)
	var items := _items(h, "PE-01")
	assert_int(items.size()).is_equal(1)
	var item: Dictionary = items[0]
	assert_str(item["status"]).is_equal("open")
	assert_str(item["delivery"]).is_equal("agenda")
	assert_str(item["bloc"]).is_equal(BLOC_HOUSED)
	assert_array(item["affected"]).is_equal([BLOC_HOUSED])
	var fire := h.facade.reason(item["reason_id"])
	assert_str(String(fire.decision_key)).is_equal("decision.event.fire")
	assert_str(String(fire.actor.ref())).is_equal(h.context.politics.events["system_actor"])
	assert_bool(fire.is_consistent()).is_true()
	assert_int(fire.threshold).is_equal(0)
	assert_str(String(fire.outcome)).is_equal("positive")
	var by_name := {}
	for factor in fire.factors:
		by_name[String(factor.name_key).trim_prefix("reason.factor.")] = factor
	assert_int(by_name["hazard"].weight).is_equal(1000)
	assert_int(by_name["rng_draw"].weight).is_equal(1000)
	assert_int(fire.score).is_equal(by_name["hazard"].value + by_name["rng_draw"].value)
	assert_int(by_name["weighted_grievance"].weight) \
		.override_failure_message("baskı bileşenleri yalnız gösterim").is_equal(0)
	assert_array(Array(fire.subjects)).contains(["agenda.%d" % item["id"], BLOC_HOUSED])
	assert_bool(fire.parent_ids.size() > 0).override_failure_message("neden zinciri: kesim tepkisi gerekçesi").is_true()
	assert_bool(Array(fire.parent_ids).has(view_of(h, BLOC_HOUSED).reason_ids[0])).is_true()
	var opened := events_of(h, &"politics.agenda_opened")
	assert_int(opened.size()).is_equal(1)
	assert_str(String(opened[0].message_key)).is_equal("event.pe01.reason")
	assert_int(opened[0].reason_ids[0]).is_equal(item["reason_id"])


func test_pe02_fires_after_a_reasoned_investment_decline() -> void:
	var patch := E.regions({"F1": E.unfavorable(), "F2": E.unfavorable()})
	var h := _ready_handle(_certain_only(["pe-02"]), patch)
	h.facade.submit_command(SimCommand.zoning_propose(h.facade.parcel_ids(), &"zone.mixed"))
	tick(h, 20)  # meclis oylaması + yatırımcı kararları (olumsuz)
	assert_int(EconomyQuery.totals(h.state())["declines_recorded"]).override_failure_message("ön koşul").is_greater(0)
	_scan(h)
	var items := _items(h, "PE-02")
	assert_int(items.size()).is_equal(1)
	var fire := h.facade.reason(items[0]["reason_id"])
	assert_bool(fire.parent_ids.size() > 0).is_true()
	for parent in fire.parent_ids:
		assert_str(String(h.facade.reason(parent).decision_key)).is_equal("decision.investor.develop")
		assert_str(String(h.facade.reason(parent).outcome)).is_equal("negative")


func test_pe03_fires_after_a_failed_budget_vote() -> void:
	var h := _ready_handle(_certain_only(["pe-03"]))
	for member in [COUNCIL_1, COUNCIL_2, COUNCIL_3, COUNCIL_4, COUNCIL_5]:
		ActorStore.actor_ref(h.state(), member)["stance"]["growth_vs_preservation"] = 1000
	CouncilEngine.open_vote(h.state(), h.context,
		CouncilEngine.budget_spec(1, {}, {"axes": {"growth_vs_preservation": -1000}, "realism": 0}))
	tick(h, 20)
	assert_str(pol(h)["council"]["votes"][0]["status"]).is_equal("failed")
	_scan(h)
	var items := _items(h, "PE-03")
	assert_int(items.size()).is_equal(1)
	var fire := h.facade.reason(items[0]["reason_id"])
	assert_int(fire.parent_ids.size()).override_failure_message("oylama nedenleri, cause_cap ile sınırlı") \
		.is_equal(int(h.context.politics.cadence["cause_cap"]))
	for parent in fire.parent_ids:
		assert_str(String(h.facade.reason(parent).decision_key)).is_equal("decision.council.vote")
	assert_array(items[0]["affected"]).is_equal([BLOC_HOUSED, BLOC_SEEKING])


func test_pe04_fires_after_the_media_publishes() -> void:
	var h := _ready_handle(_certain_only(["pe-04"]))
	MediaEngine.queue_story(h.state(), {"kind": "protest", "topic": "mobility", "subject": BLOC_HOUSED,
		"conflict": 900, "scale": 800, "fact": -900, "parent_ids": [], "key": "k"})
	MediaEngine.scan(h.state(), h.context)
	assert_int(pol(h)["media"]["published"]).override_failure_message("ön koşul").is_equal(1)
	_scan(h)
	var items := _items(h, "PE-04")
	assert_int(items.size()).is_equal(1)
	assert_int(h.facade.reason(items[0]["reason_id"]).parent_ids.size()).is_equal(1)
	assert_str(String(h.facade.reason(h.facade.reason(items[0]["reason_id"]).parent_ids[0]).decision_key)) \
		.is_equal("decision.media.coverage")


func test_pe07_fires_after_sustained_service_overload() -> void:
	var h := _ready_handle(_certain_only(["pe-07"]), {"regions": {"defaults": {"initial_households": 600,
		"infra_capacity_units": 5000}}})
	h.facade.submit_command(SimCommand.zoning_propose(h.facade.parcel_ids(), &"zone.mixed"))
	tick(h, 30)
	var caps: PackedInt64Array = EconomyState.data(h.state())["regions"]["infra_cap"]
	for i in caps.size():
		caps[i] = 20  # altyapı kapasitesi düştü (T-014 yazma noktası): yük kapasiteyi aştı
	assert_array(_items(h, "PE-07")).override_failure_message("aşırı yük öncesi olay çıkmamalı").is_empty()
	tick(h, 28)
	var items := _items(h, "PE-07")
	assert_int(items.size()).override_failure_message("14+ gün aşım olay doğurmalı").is_equal(1)
	assert_bool(EventSources.compute(h.state(), h.context, EconomyQuery.region_stats(h.state(), h.context.economy)) \
		["service.overload_days"] >= 14).is_true()


func test_a_calm_city_fires_nothing_and_raises_no_error() -> void:
	var h := handle(E.regions({"F1": {"initial_households": 0}, "F2": {"initial_households": 0}}), 6, SEED,
		_all_certain)
	tick(h, 120)
	assert_array(_items(h)).is_empty()
	assert_array(reasons_of(h, "decision.event.fire")).is_empty()
	assert_array(events_of(h, &"politics.agenda_opened")).is_empty()


func test_zero_weight_never_fires_and_the_draw_is_seeded_bounded_and_uniform() -> void:
	var h := _ready_handle()
	var seen := {}
	var total := 0
	var samples := 6000
	for t in range(1, samples + 1):
		h.state().tick = t
		var draw := EventEngine.event_draw(h.state(), "PE-01")
		assert_int(draw).is_between(1, 1000)
		assert_int(EventEngine.event_draw(h.state(), "PE-01")) \
			.override_failure_message("aynı anahtar aynı çekiliş").is_equal(draw)
		total += draw
		seen[draw] = true
	assert_int(total / samples).override_failure_message("ortalama ~500").is_between(480, 520)
	assert_int(seen.size()).is_greater(900)
	assert_bool(seen.has(1) and seen.has(1000)).override_failure_message("aralık uçları 1 ve 1000 (0 çekilişi yok)") \
		.is_true()
	assert_bool(seen.has(0)).is_false()
	assert_bool(EventEngine.event_draw(h.state(), "PE-01") != EventEngine.event_draw(h.state(), "PE-02") \
		or EventEngine.event_draw(h.state(), "PE-01") != EventEngine.event_draw(h.state(), "PE-03")).is_true()
	var other := handle({}, 6, 77)
	other.state().tick = 5
	h.state().tick = 5
	assert_int(EventEngine.event_draw(other.state(), "PE-01")).override_failure_message("tohum çekilişi değiştirmeli") \
		.is_not_equal(EventEngine.event_draw(h.state(), "PE-01"))
	var zero := _ready_handle(func(f: Dictionary) -> void:
		_certain(f, "pe-04")
		f["templates"]["pe-04"]["weight"] = 0
		f["templates"]["pe-04"]["hard"] = [])
	for week in 8:
		tick(zero, 7)
		pol(zero)["media"]["last_tick"] = zero.state().tick
		pol(zero)["media"]["last"] = {"tick": zero.state().tick, "newsworthiness": 1000, "lean": 1000, "fact": 1000}
	assert_array(_items(zero, "PE-04")).override_failure_message("hazard 0 asla ateşlemez").is_empty()


func test_fire_condition_is_hazard_at_least_draw_exactly() -> void:
	var probe := _ready_handle()
	probe.state().tick = 7
	var draw := EventEngine.event_draw(probe.state(), "PE-04")
	for case: Array in [[draw, 1], [draw - 1, 0]]:
		var edit := func(f: Dictionary) -> void:
			_certain(f, "pe-04")
			f["templates"]["pe-04"]["weight"] = case[0]
			f["templates"]["pe-04"]["hard"] = []
		var h := handle({}, 6, SEED, edit)
		tick(h, 6)
		pol(h)["media"]["last_tick"] = 6
		pol(h)["media"]["last"] = {"tick": 6, "newsworthiness": 1000, "lean": 1000, "fact": 1000}
		tick(h, 1)  # 7. gün: haftalık tarama
		assert_int(_items(h, "PE-04").size()) \
			.override_failure_message("hazard %d draw %d" % [case[0], draw]).is_equal(case[1])


func test_cooldown_blocks_refire_until_it_elapses_and_pressure_dip_rearms_early() -> void:
	var edit := func(f: Dictionary) -> void:
		var t: Dictionary = f["templates"]["pe-04"]
		t["weight"] = 1000
		t["hard"] = []
		t["cooldown_days"] = 100
		t["rearm_below"] = 300
		t["mutex"] = []
		t["drivers"] = [{"name": "newsworthiness", "src": "media.newsworthiness", "lo": 0, "hi": 1000, "weight": 1}]
	var h := _ready_handle(edit)
	var news := func(value: int) -> void:
		pol(h)["media"]["last_tick"] = h.state().tick
		pol(h)["media"]["last"] = {"tick": h.state().tick, "newsworthiness": value, "lean": 0, "fact": 0}
	news.call(1000)
	_scan(h)
	assert_int(_items(h, "PE-04").size()).is_equal(1)
	for week in 3:
		tick(h, 7)
		news.call(1000)
		_scan(h)
	assert_int(_items(h, "PE-04").size()).override_failure_message("cooldown içinde yeniden ateşlendi").is_equal(1)
	news.call(0)  # baskı çöktü (rearm_below altı) ...
	_scan(h)
	news.call(1000)  # ... sonra yeniden yükseldi: silahlanma erken gerçekleşir
	tick(h, 1)
	_scan(h)
	assert_int(_items(h, "PE-04").size()) \
		.override_failure_message("baskı rearm_below altına inince yeniden silahlanmalı") \
		.is_equal(2)


func test_cooldown_elapses_without_a_dip() -> void:
	var edit := func(f: Dictionary) -> void:
		_certain(f, "pe-04")
		f["templates"]["pe-04"]["hard"] = []
		f["templates"]["pe-04"]["cooldown_days"] = 14
		f["templates"]["pe-04"]["mutex"] = []
	var h := _ready_handle(edit)
	for week in 4:
		pol(h)["media"]["last_tick"] = h.state().tick
		pol(h)["media"]["last"] = {"tick": h.state().tick, "newsworthiness": 1000, "lean": 1000, "fact": 1000}
		_scan(h)
		tick(h, 7)
	assert_int(_items(h, "PE-04").size()) \
		.override_failure_message("14 günlük cooldown: ~haftada bir değil 2 haftada bir") \
		.is_between(2, 3)


func test_mutex_keeps_one_open_item_per_topic_group() -> void:
	var h := _ready_handle(func(f: Dictionary) -> void:
		_all_certain(f)
		f["templates"]["pe-04"]["mutex"] = ["bloc_unrest"]
		f["templates"]["pe-04"]["hard"] = [])
	_protest(h)
	pol(h)["media"]["last_tick"] = h.state().tick
	pol(h)["media"]["last"] = {"tick": h.state().tick, "newsworthiness": 1000, "lean": 1000, "fact": 1000}
	_scan(h)
	var open := _items(h).filter(func(i: Dictionary) -> bool: return i["template"] in ["PE-01", "PE-04"])
	assert_int(open.size()).override_failure_message("aynı mutex grubundan yalnız biri").is_equal(1)


func test_new_events_per_scan_are_capped_and_the_rest_wait() -> void:
	var h := _ready_handle(func(f: Dictionary) -> void:
		_all_certain(f)
		f["events"]["max_new_per_scan"] = 1
		for id: String in TEMPLATES:
			f["templates"][id]["hard"] = []
			f["templates"][id]["mutex"] = [])
	pol(h)["media"]["last_tick"] = h.state().tick
	pol(h)["media"]["last"] = {"tick": h.state().tick, "newsworthiness": 1000, "lean": 1000, "fact": 1000}
	_scan(h)
	assert_int(_items(h).size()).is_equal(1)
	_scan(h)
	assert_int(_items(h).size()).override_failure_message("ertelenenler sonraki taramada").is_equal(2)


func test_decision_level_interrupts_are_budgeted_per_quarter_and_fall_back_to_agenda() -> void:
	var h := _ready_handle(func(f: Dictionary) -> void:
		_all_certain(f)
		f["events"]["max_new_per_scan"] = 5
		f["events"]["interrupt_budget_per_quarter"] = 1
		for id: String in TEMPLATES:
			f["templates"][id]["hard"] = []
			f["templates"][id]["mutex"] = []
			f["templates"][id]["delivery"] = "decision")
	pol(h)["media"]["last_tick"] = h.state().tick
	pol(h)["media"]["last"] = {"tick": h.state().tick, "newsworthiness": 1000, "lean": 1000, "fact": 1000}
	_scan(h)
	var deliveries := _items(h).map(func(i: Dictionary) -> String: return i["delivery"])
	assert_int(deliveries.size()).is_greater(1)
	assert_int(deliveries.count("decision")).override_failure_message(str(deliveries)).is_equal(1)
	assert_int(deliveries.count("agenda")).is_equal(deliveries.size() - 1)
	for item in _items(h):
		assert_bool(item["pauses"]).override_failure_message("otomatik duraklatma varsayılan kapalı").is_false()


func test_autopause_is_only_a_user_setting() -> void:
	var h := _ready_handle(func(f: Dictionary) -> void:
		_certain(f, "pe-04")
		f["templates"]["pe-04"]["hard"] = []
		f["templates"]["pe-04"]["delivery"] = "decision"
		f["cadence"]["autopause"] = true)
	pol(h)["media"]["last_tick"] = h.state().tick
	pol(h)["media"]["last"] = {"tick": h.state().tick, "newsworthiness": 1000, "lean": 1000, "fact": 1000}
	_scan(h)
	assert_bool(_items(h, "PE-04")[0]["pauses"]).is_true()


func test_milestone_gate_hides_later_milestone_templates() -> void:
	var closed := _ready_handle(func(f: Dictionary) -> void:
		_certain(f, "pe-04")
		f["templates"]["pe-04"]["hard"] = []
		f["templates"]["pe-04"]["min_milestone"] = "M3")
	pol(closed)["media"]["last_tick"] = 1
	pol(closed)["media"]["last"] = {"tick": 1, "newsworthiness": 1000, "lean": 1000, "fact": 1000}
	_scan(closed)
	assert_array(_items(closed, "PE-04")).is_empty()
	var open := _ready_handle(func(f: Dictionary) -> void:
		_certain(f, "pe-04")
		f["templates"]["pe-04"]["hard"] = []
		f["templates"]["pe-04"]["min_milestone"] = "M3"
		f["cadence"]["milestone"] = "M3")
	pol(open)["media"]["last_tick"] = 1
	pol(open)["media"]["last"] = {"tick": 1, "newsworthiness": 1000, "lean": 1000, "fact": 1000}
	_scan(open)
	assert_int(_items(open, "PE-04").size()).is_equal(1)


func test_falling_pressure_does_not_fire_beyond_the_rising_slack() -> void:
	var edit := func(f: Dictionary) -> void:
		f["templates"]["pe-04"]["weight"] = 1000
		f["templates"]["pe-04"]["hard"] = []
		f["templates"]["pe-04"]["drivers"] = [{"name": "newsworthiness", "src": "media.newsworthiness", "lo": 0, "hi": 1000,
			"weight": 1}]
		f["events"]["rising_slack_pm"] = 100
	var h := _ready_handle(edit)
	var set_news := func(value: int) -> void:
		pol(h)["media"]["last_tick"] = h.state().tick
		pol(h)["media"]["last"] = {"tick": h.state().tick, "newsworthiness": value, "lean": 0, "fact": 0}
		pol(h)["events"]["cooldown_until"].erase("PE-04")
		for item: Dictionary in pol(h)["events"]["agenda"]:
			item["status"] = "resolved"
	set_news.call(1000)
	pol(h)["events"]["last_pressure"]["PE-04"] = 1000
	set_news.call(700)  # 300 düşüş > 100 gevşeme: yükseliyor sayılmaz
	_scan(h)
	assert_array(_items(h, "PE-04")).is_empty()
	pol(h)["events"]["last_pressure"]["PE-04"] = 780
	set_news.call(700)  # 80 düşüş <= 100 gevşeme
	var fired_before := _items(h, "PE-04").size()
	_scan(h)
	assert_int(_items(h, "PE-04").size()).is_equal(fired_before + 1)


func test_scan_is_deterministic_for_the_same_seed_and_state() -> void:
	var first := _ready_handle(_certain_only(["pe-01"]))
	var second := _ready_handle(_certain_only(["pe-01"]))
	_protest(first)
	_protest(second)
	_scan(first)
	_scan(second)
	assert_str(first.state().state_hash()).is_equal(second.state().state_hash())


func test_events_are_born_from_the_unscripted_city_with_default_data() -> void:
	# E-P2: yoğunlaştırıcı imar -> kimsenin senaryolamadığı kesim tepkisi ve haber -> olay; veri varsayılanı, yama yok
	var h := stress_handle(14)
	tick(h, 400)
	var items := _items(h)
	assert_bool(items.is_empty()).override_failure_message("ölü senaryo: hiç olay doğmadı").is_false()
	var chains := 0
	for item in items:
		var fire := h.facade.reason(item["reason_id"])
		assert_str(String(fire.decision_key)).is_equal("decision.event.fire")
		assert_bool(fire.is_consistent()).is_true()
		assert_str(item["status"]).is_not_empty()
		for parent in fire.parent_ids:
			var cause := h.facade.reason(parent)
			assert_array(["bloc", "media", "council", "investor"]).contains([String(cause.decision_key).get_slice(".", 1)])
			chains += 1
	assert_int(chains).override_failure_message("nedensellik zinciri yok").is_greater(0)
	assert_array(SimContractChecks.check_facade(h.facade)).is_empty()
	for event in events_of(h, &"politics.agenda_opened"):
		assert_int(event.command_id).override_failure_message("olay oyuncu komutuna bağlı değildir").is_equal(0)


func test_the_political_layer_runs_without_an_economy_and_stays_calm() -> void:
	var actors := config()
	var pol_cfg := politics_config()
	var parcels := FacadeTestSupport.fixture_source(4)
	var ctx := PoliticsContext.create(actors, pol_cfg, E.config(), parcels)
	var systems: Array[SimSystem] = [ActorSystem.create(actors), PoliticsSystem.create(ctx)]
	var facade := SimFacadeImpl.create(SEED, parcels, null, null, systems, [], PoliticsGate.new(ctx),
		PoliticsSnapshot.new(ctx))
	facade.advance(60)
	var state := facade.game_state()
	assert_bool(PoliticsState.is_initialized(state)).is_true()
	assert_array(PoliticsQuery.agenda(state, ctx, false)).is_empty()
	assert_int(PoliticsState.data(state)["counters"]["scans"]).is_equal(8)
	CouncilEngine.open_vote(state, ctx, CouncilEngine.budget_spec(1, {}, {}))
	facade.advance(20)
	assert_str(PoliticsState.data(state)["council"]["votes"][0]["status"]).is_not_equal("pending")
	assert_array(SimContractChecks.check_facade(facade)).is_empty()


func test_the_source_vocabulary_templates_may_read_is_fully_implemented() -> void:
	var h := _ready_handle()
	var sources := EventSources.compute(h.state(), h.context, EconomyQuery.region_stats(h.state(), h.context.economy))
	var names: Array = sources.keys()
	names.sort()
	var declared: Array = EventSpec.SOURCES.duplicate()
	declared.sort()
	assert_array(names).override_failure_message("EventSpec.SOURCES ile EventSources.compute ayrıştı").is_equal(declared)
	for value in sources.values():
		assert_int(typeof(value)).is_equal(TYPE_INT)
