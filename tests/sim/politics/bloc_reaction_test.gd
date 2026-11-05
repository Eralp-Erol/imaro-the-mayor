extends PoliticsTestBase
## T-017 ölçüt 1 · Kesim tepkisi (`bloc.react` basamaklı + `bloc.support`, SIM-05/SIM-09/SIM-12): en az iki kesim
## FARKLI yönde tepki verebilir (biri destek, biri protesto/itiraz); şikâyet ve memnuniyet ayrı defterlerdir; her tepki
## gerekçelidir (basamak başına kayıt, "neden boykot değil?"); gerekçe yalnız durum DEĞİŞİMİNDE/sakin değilse süresi
## dolunca yazılır (ReasonLog hacmi); ilişki/hafıza güncellenir; medya büyütür.

const ANGRY := {"mobility": 1000, "environment_health": 1000, "services_utilities": 1000}
const HAPPY := {"housing_cost": 1000, "jobs_income": 1000}


func _ready_handle(edit: Callable = Callable()) -> PoliticsHandle:
	var h := handle(E.regions(STRESS), 6, SEED, edit)
	tick(h, 1)  # ekonomi ve siyaset başladı (baseline), henüz haftalık tarama yok: taramaları testler elle çağırır
	return h


func _react_records(h: PoliticsHandle, bloc_key: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for rec: Dictionary in h.state().reasons.find({"actor": bloc_key}):
		if String(rec["decision"]).begins_with("decision.bloc."):
			out.append(rec)
	return out


func test_two_blocs_react_in_opposite_directions_from_separate_ledgers() -> void:
	var h := _ready_handle()
	set_books(h, BLOC_HOUSED, ANGRY, {})
	set_books(h, BLOC_SEEKING, {}, HAPPY)
	scan_blocs(h)
	var against := view_of(h, BLOC_HOUSED)
	var in_favor := view_of(h, BLOC_SEEKING)
	assert_array([&"oppose", &"protest"]).contains([against.reaction])
	assert_str(String(in_favor.reaction)).is_equal("support")
	assert_int(against.intensity).is_greater(0)
	assert_int(in_favor.intensity).is_greater(0)
	assert_int(against.stance).override_failure_message("itiraz eden kesimin tutumu olumsuz olmalı").is_less(0)
	assert_int(in_favor.stance).override_failure_message("destekleyen kesimin tutumu olumlu olmalı").is_greater(0)
	assert_array(SimContractChecks.check_facade(h.facade)).is_empty()


func test_strong_grievance_with_negative_press_and_low_trust_escalates_to_protest_but_not_boycott() -> void:
	var h := _ready_handle()
	set_books(h, BLOC_HOUSED, ANGRY, {})
	pol(h)["media"]["tone"] = {"mobility": -1000, "services_utilities": -1000, "environment_health": -1000}
	var rel := ActorStore.ensure_relation(h.state(), h.context.actors, BLOC_HOUSED, PLAYER)
	rel["trust"] = -800
	scan_blocs(h)
	var view := view_of(h, BLOC_HOUSED)
	assert_str(String(view.reaction)).is_equal("protest")
	var tiers := _react_records(h, BLOC_HOUSED).filter(
		func(r: Dictionary) -> bool: return String(r["decision"]).contains("bloc.react."))
	var outcome_by_tier := {}
	for rec in tiers:
		outcome_by_tier[String(rec["decision"]).get_slice(".", 3)] = String(rec["outcome"])
	assert_dict(outcome_by_tier).is_equal({"petition": "positive", "protest": "positive", "boycott": "negative"})


func test_grievance_and_satisfaction_are_separate_ledgers_a_bloc_can_hold_both() -> void:
	var h := _ready_handle()
	set_books(h, BLOC_HOUSED, ANGRY, {"services_utilities": 1000})
	scan_blocs(h)
	var bloc: Dictionary = pol(h)["blocs"][BLOC_HOUSED]
	assert_int(bloc["G"]).is_greater(800)
	assert_int(bloc["S"]).override_failure_message("memnuniyet şikâyetle net edilmemeli").is_greater(200)
	assert_int(bloc_book(h, BLOC_HOUSED, "grievances")["services_utilities"]).is_greater(800)
	assert_int(bloc_book(h, BLOC_HOUSED, "satisfaction")["services_utilities"]).is_greater(800)
	assert_array(SimContractChecks.check_no_aggregate_score(h.facade.snapshot().to_dict(), "snapshot")).is_empty()


func test_every_reaction_is_reasoned_with_one_record_per_evaluated_tier() -> void:
	var h := _ready_handle()
	set_books(h, BLOC_HOUSED, ANGRY, {})
	set_books(h, BLOC_SEEKING, {}, HAPPY)
	scan_blocs(h)
	var against := _react_records(h, BLOC_HOUSED)
	var tiers := against.filter(func(r: Dictionary) -> bool: return String(r["decision"]).contains("bloc.react."))
	assert_bool(tiers.size() >= 2).override_failure_message("petition + sonraki basamak değerlendirilmeli").is_true()
	assert_int(against.size()) \
		.override_failure_message("tek değerlendirme: basamaklar + destek kararı").is_equal(tiers.size() + 1)
	assert_str(String(tiers[0]["decision"])).is_equal("decision.bloc.react.petition")
	assert_str(String(tiers[0]["outcome"])).is_equal("positive")
	for i in range(1, tiers.size()):
		assert_array(Array(tiers[i]["parent_ids"])) \
			.override_failure_message("basamaklar zincirli").contains([tiers[i - 1]["id"]])
	assert_str(String(tiers[tiers.size() - 1]["outcome"])).override_failure_message("son basamak 'neden değil?' kaydı") \
		.is_equal("negative")
	var supports := _react_records(h, BLOC_SEEKING).filter(
		func(r: Dictionary) -> bool: return r["decision"] == &"decision.bloc.support")
	assert_int(supports.size()).is_equal(1)
	assert_str(String(supports[0]["outcome"])).is_equal("positive")
	for rec in against + _react_records(h, BLOC_SEEKING):
		var record := h.facade.reason(rec["id"])
		assert_bool(record.is_consistent()).is_true()
		assert_bool(ReasonModel.from_record(record).is_consistent()).is_true()
		assert_bool(record.factors.size() >= 4).is_true()
		assert_array(Array(record.subjects)).contains([rec["actor"]])


func test_quiet_blocs_write_no_records() -> void:
	var h := handle(E.regions({"F1": {"initial_households": 0}, "F2": {"initial_households": 0}}))
	tick(h, 1)
	set_books(h, BLOC_HOUSED, {"mobility": 50}, {"mobility": 50})
	scan_blocs(h)
	for key in [BLOC_HOUSED, BLOC_SEEKING]:
		assert_array(_react_records(h, key)).override_failure_message("%s sessizken kayıt yazdı" % key).is_empty()
		assert_int(pol(h)["blocs"][key]["eval"]["tick"]).is_equal(-1)
		assert_str(String(view_of(h, key).reaction)).is_equal("neutral")


func test_reasons_are_written_on_change_or_after_the_recheck_window_only() -> void:
	# defter çürümesi kapalı: durum hiç değişmez, yalnız recheck_days yeniden değerlendirmeyi tetikler
	var h := _ready_handle(func(f: Dictionary) -> void: f["blocs"]["decay_pm"]["grievance"] = 0)
	set_books(h, BLOC_HOUSED, ANGRY, {})
	scan_blocs(h)
	var after_first := _react_records(h, BLOC_HOUSED).size()
	assert_int(after_first).is_greater(1)
	tick(h, 14)  # kendi haftalık taramalar: değişim yok -> kayıt yok
	assert_int(_react_records(h, BLOC_HOUSED).size()).override_failure_message("değişmeyen durumda kayıt yazıldı") \
		.is_equal(after_first)
	tick(h, 28)  # sakin değil ve recheck_days doldu -> yeniden değerlendirilir
	assert_int(_react_records(h, BLOC_HOUSED).size()).override_failure_message("recheck yapılmadı") \
		.is_greater(after_first)


func test_evaluations_per_scan_are_capped_and_the_rest_wait_for_the_next_scan() -> void:
	var h := _ready_handle(func(f: Dictionary) -> void: f["cadence"]["max_react_records_per_scan"] = 1)
	set_books(h, BLOC_HOUSED, ANGRY, {})
	set_books(h, BLOC_SEEKING, {}, HAPPY)
	scan_blocs(h)
	assert_int(pol(h)["blocs"][BLOC_HOUSED]["eval"]["tick"]).is_greater(-1)
	assert_int(pol(h)["blocs"][BLOC_SEEKING]["eval"]["tick"]).override_failure_message("tavan aşıldı").is_equal(-1)
	scan_blocs(h)
	assert_int(pol(h)["blocs"][BLOC_SEEKING]["eval"]["tick"]) \
		.override_failure_message("ertelenen kesim değerlendirilmedi") \
		.is_greater(-1)


func test_calming_down_is_recorded_and_published() -> void:
	var h := _ready_handle()
	set_books(h, BLOC_HOUSED, ANGRY, {})
	scan_blocs(h)
	assert_bool(view_of(h, BLOC_HOUSED).reaction != &"neutral").is_true()
	set_books(h, BLOC_HOUSED, {}, {})
	scan_blocs(h)
	assert_str(String(view_of(h, BLOC_HOUSED).reaction)).is_equal("neutral")
	var keys := events_of(h, &"group.reacted").map(func(e: SimEvent) -> String: return String(e.message_key))
	assert_array(keys).contains(["event.group.calmed"])
	assert_int(events_of(h, &"group.reacted").size()).override_failure_message("her geçiş bir olay").is_equal(2)


func test_reaction_updates_relations_trust_falls_for_the_angry_and_rises_for_the_pleased() -> void:
	var h := _ready_handle()
	set_books(h, BLOC_HOUSED, ANGRY, {})
	set_books(h, BLOC_SEEKING, {}, HAPPY)
	var before_a := int(ActorStore.relation(h.state(), h.context.actors, BLOC_HOUSED, PLAYER)["trust"])
	var before_b := int(ActorStore.relation(h.state(), h.context.actors, BLOC_SEEKING, PLAYER)["trust"])
	scan_blocs(h)
	var after_a := ActorStore.relation(h.state(), h.context.actors, BLOC_HOUSED, PLAYER)
	var after_b := ActorStore.relation(h.state(), h.context.actors, BLOC_SEEKING, PLAYER)
	assert_int(int(after_a["trust"])).is_less(before_a)
	assert_int(int(after_a["resentment"])).is_greater(0)
	assert_int(int(after_b["trust"])).is_greater(before_b)
	assert_int(ActorStore.actor_ref(h.state(), BLOC_HOUSED)["memory"].size()).is_equal(1)


func test_negative_media_tone_amplifies_the_reaction_and_is_recorded_as_a_factor() -> void:
	var calm := _ready_handle()
	var heard := _ready_handle()
	set_books(calm, BLOC_HOUSED, ANGRY, {})
	set_books(heard, BLOC_HOUSED, ANGRY, {})
	pol(heard)["media"]["tone"] = {"mobility": -1000, "services_utilities": -1000, "environment_health": -1000}
	scan_blocs(calm)
	scan_blocs(heard)
	assert_int(pol(calm)["blocs"][BLOC_HOUSED]["amp"]).is_equal(0)
	var amp: int = pol(heard)["blocs"][BLOC_HOUSED]["amp"]
	assert_int(amp).is_greater(0)
	assert_int(amp).is_less_equal(int(heard.context.politics.media["amp_cap"]))
	assert_int(view_of(heard, BLOC_HOUSED).intensity).is_greater_equal(view_of(calm, BLOC_HOUSED).intensity)
	var record := heard.facade.reason(view_of(heard, BLOC_HOUSED).reason_ids[0])
	var amplification: ReasonFactor = record.factors.filter(
		func(f: ReasonFactor) -> bool: return f.name_key == &"reason.factor.media_amplification")[0]
	assert_int(amplification.value).is_equal(amp)
	assert_str(String(amplification.source_ref)).is_equal(String(heard.context.politics.media["organ"]))
	assert_bool(amplification.weight > 0).is_true()


func test_real_economy_pressure_makes_one_bloc_protest_and_another_support_with_a_causal_chain() -> void:
	var h := stress_handle(14)
	tick(h, 200)
	var messages := {}
	for e in events_of(h, &"group.reacted"):
		messages[String(e.actor.ref()) + "|" + String(e.message_key)] = e
	var against_key := BLOC_HOUSED + ("|event.group.protest" if messages.has(BLOC_HOUSED + "|event.group.protest")
		else "|event.group.oppose")
	assert_bool(messages.has(against_key)).override_failure_message(str(messages.keys())).is_true()
	assert_bool(messages.has(BLOC_SEEKING + "|event.group.support")) \
		.override_failure_message(str(messages.keys())).is_true()
	var protest: SimEvent = messages[against_key]
	var support: SimEvent = messages[BLOC_SEEKING + "|event.group.support"]
	assert_int(protest.reason_ids.size()).is_greater(1)
	# nedensellik: itirazın gerekçesi yatırımcı kararına, o da imar komutuna bağlanır (SIM-05, SIM-12)
	var first := h.facade.reason(protest.reason_ids[0])
	assert_int(first.parent_ids.size()).override_failure_message("itirazın nedeni yok").is_greater(0)
	for parent in first.parent_ids:
		var cause := h.facade.reason(parent)
		assert_str(String(cause.decision_key)).is_equal("decision.investor.develop")
		assert_array(Array(cause.subjects)).contains(["command.1"])
	assert_bool(support.reason_ids.size() >= 2).is_true()
	assert_array(SimContractChecks.check_facade(h.facade)).is_empty()
	var parcel_causes := Array(view_of(h, BLOC_HOUSED).cause_refs).filter(
		func(r: String) -> bool: return r.begins_with("parcel."))
	assert_array(parcel_causes) \
		.is_not_empty()


func test_reactions_need_a_triggering_change_not_every_scan_over_a_long_run() -> void:
	var h := stress_handle(14)
	tick(h, 280)  # 40 haftalık tarama x 2 kesim = 80 aday değerlendirme
	var first_tier := reasons_of(h, "decision.bloc.react.petition")
	assert_int(first_tier.size()).override_failure_message("değerlendirme olmadı").is_greater(0)
	# Üst sınır 80 adayın YARISI (B-130/D-026: petition eşiği 250 -> 190 oldu; tepki veren kesim `recheck_days`ta yeniden
	# değerlendirilir, ölçülen 26; eski sınır 25 eşik 250'ye göre kalibreydi). Amaç: "her taramada kayıt" (80) olmasın.
	assert_int(first_tier.size()) \
		.override_failure_message("her taramada kayıt yazıldı (%d)" % first_tier.size()).is_less(40)
