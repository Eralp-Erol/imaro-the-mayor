extends PoliticsTestBase
## T-017 ölçüt 3 · Medya tonu (`media.coverage`, characters-npc §6.3/§6.5, SIM-12): tek yer tutucu organ, haber
## adaylarını gerekçeli değerlendirir; yayımlanan haberin konu tonu `lag_days` sonra yazılır, çürür, kesim şikâyetini
## büyütür ve GroupReactionView'a (gerekçe/medya faktörü) yansır. `corruption` etiketli şablonlar kapalıdır.

const PROTEST_STORY := {"kind": "protest", "topic": "mobility", "subject": "actor.bloc.1", "conflict": 800,
	"scale": 600, "fact": -700, "parent_ids": [], "key": "story|1"}


func _ready_handle(edit: Callable = Callable(), actors_edit: Callable = Callable()) -> PoliticsHandle:
	var h := handle(E.regions(STRESS), 6, SEED, edit, actors_edit)
	tick(h, 1)
	return h


func _story(overrides: Dictionary = {}) -> Dictionary:
	var story := PROTEST_STORY.duplicate(true)
	story.merge(overrides, true)
	return story


func _publish(h: PoliticsHandle, story: Dictionary) -> void:
	MediaEngine.queue_story(h.state(), story)
	MediaEngine.scan(h.state(), h.context)


func test_a_newsworthy_story_is_published_with_a_reason_and_tone_arrives_after_the_lag() -> void:
	var h := _ready_handle()
	_publish(h, _story())
	var records := reasons_of(h, "decision.media.coverage")
	assert_int(records.size()).is_equal(1)
	assert_str(String(records[0]["outcome"])).is_equal("positive")
	assert_str(String(records[0]["actor"])).is_equal(h.context.politics.media["organ"])
	assert_array(Array(records[0]["subjects"])).contains(["actor.bloc.1"])
	assert_int(pol(h)["media"]["published"]).is_equal(1)
	assert_dict(PoliticsQuery.media_tone(h.state())).override_failure_message("ton gecikmeden önce görünmemeli").is_empty()
	var lag := int(h.context.politics.media["lag_days"])
	tick(h, lag - 1)
	assert_dict(PoliticsQuery.media_tone(h.state())).is_empty()
	tick(h, 1)
	assert_int(PoliticsQuery.media_tone(h.state())["mobility"]).override_failure_message("kötü haber ton düşürür") \
		.is_less(-200)
	# ton = w_fact*gerçek + w_lean*uyum (eğilim 0) - w_sens*hassasiyet*çatışma (işaret gerçek sinyalin işareti)
	var cfg: Dictionary = h.context.politics.media
	var sensationalism: int = ActorStore.actor_ref(h.state(), cfg["organ"])["state"]["sensationalism"]
	var expected: int = int(cfg["w_fact"]) * -700 / 1000 - int(cfg["w_sens"]) * sensationalism * 800 / 1_000_000
	assert_int(PoliticsQuery.media_tone(h.state())["mobility"]) \
		.override_failure_message("sansasyonellik haberin yönünde").is_equal(expected)
	var published := events_of(h, &"actor.decided").filter(
		func(e: SimEvent) -> bool: return e.message_key == &"event.media.published")
	assert_int(published.size()).is_equal(1)
	assert_str(String(published[0].actor.ref())).is_equal(h.context.politics.media["organ"])
	assert_bool(h.facade.reason(published[0].reason_ids[0]).is_consistent()).is_true()


func test_a_dull_story_is_declined_with_a_recorded_reason_and_changes_no_tone() -> void:
	var h := _ready_handle()
	_publish(h, _story({"conflict": 0, "scale": 0, "fact": 0}))
	var records := reasons_of(h, "decision.media.coverage")
	assert_int(records.size()).override_failure_message("yayımlanmayan haber de gerekçeli").is_equal(1)
	assert_str(String(records[0]["outcome"])).is_equal("negative")
	assert_int(pol(h)["media"]["published"]).is_equal(0)
	assert_array(pol(h)["media"]["pending"]).is_empty()
	tick(h, 20)
	assert_dict(PoliticsQuery.media_tone(h.state())).is_empty()


func test_good_news_raises_tone_and_bad_news_lowers_it_with_signed_fact() -> void:
	var good := _ready_handle()
	var bad := _ready_handle()
	_publish(good, _story({"kind": "support", "fact": 700, "key": "g"}))
	_publish(bad, _story({"fact": -700, "key": "b"}))
	tick(good, 8)
	tick(bad, 8)
	assert_int(PoliticsQuery.media_tone(good.state())["mobility"]).is_greater(0)
	assert_int(PoliticsQuery.media_tone(bad.state())["mobility"]).is_less(0)
	var story_record := good.facade.reason(reasons_of(good, "decision.media.coverage")[0]["id"])
	var fact_factor: ReasonFactor = story_record.factors.filter(
		func(f: ReasonFactor) -> bool: return f.name_key == &"reason.factor.fact_signal")[0]
	assert_bool(fact_factor.is_estimate).override_failure_message("gerçek sinyal tahmin etiketli").is_true()


func test_tone_decays_each_scan() -> void:
	var h := _ready_handle()
	pol(h)["media"]["tone"] = {"mobility": -800}
	MediaEngine.scan(h.state(), h.context)
	var after_one: int = PoliticsQuery.media_tone(h.state())["mobility"]
	MediaEngine.scan(h.state(), h.context)
	var after_two: int = PoliticsQuery.media_tone(h.state())["mobility"]
	assert_int(after_one).is_equal(-720)
	assert_int(after_two).is_greater(after_one)
	assert_int(after_two).is_less(0)


func test_amplification_depends_on_organ_reach_and_is_capped() -> void:
	var h := _ready_handle()
	var everything := {}
	for topic in h.context.actors.topic_ids:
		everything[topic] = -1000
	pol(h)["media"]["tone"] = everything
	var amp := MediaEngine.amp_for(h.state(), h.context, BLOC_HOUSED)
	assert_int(amp).is_greater(0)
	assert_int(amp).is_less_equal(int(h.context.politics.media["amp_cap"]))
	assert_int(MediaEngine.tone_for(h.state(), h.context, BLOC_HOUSED)).is_equal(-600)  # erişim payı 600
	var deaf := _ready_handle(Callable(), func(f: Dictionary) -> void:
		roster_actor(f, MEDIA_1)["reach"] = {BLOC_SEEKING: 600})
	pol(deaf)["media"]["tone"] = pol(h)["media"]["tone"].duplicate()
	assert_int(MediaEngine.amp_for(deaf.state(), deaf.context, BLOC_HOUSED)).override_failure_message("erişimsiz kesim") \
		.is_equal(0)
	var capped := _ready_handle(func(f: Dictionary) -> void: f["media"]["amp_cap_pm"] = 40)
	pol(capped)["media"]["tone"] = pol(h)["media"]["tone"].duplicate()
	assert_int(MediaEngine.amp_for(capped.state(), capped.context, BLOC_HOUSED)).is_equal(40)


func test_only_the_configured_number_of_stories_is_judged_per_scan() -> void:
	var h := _ready_handle()
	for i in 6:
		MediaEngine.queue_story(h.state(), _story({"key": "story|%d" % i}))
	MediaEngine.scan(h.state(), h.context)
	assert_int(reasons_of(h, "decision.media.coverage").size()).is_equal(int(h.context.politics.media["max_stories"]))
	assert_array(pol(h)["media"]["queue"]).override_failure_message("kuyruk her taramada boşalır").is_empty()


func test_the_same_pending_story_is_not_queued_twice_and_repeats_are_less_novel() -> void:
	var h := _ready_handle()
	MediaEngine.queue_story(h.state(), _story())
	MediaEngine.queue_story(h.state(), _story())
	assert_int(pol(h)["media"]["queue"].size()).is_equal(1)
	MediaEngine.scan(h.state(), h.context)
	MediaEngine.queue_story(h.state(), _story())
	MediaEngine.scan(h.state(), h.context)
	var records := reasons_of(h, "decision.media.coverage")
	var first := h.facade.reason(records[0]["id"])
	var second := h.facade.reason(records[1]["id"])
	assert_int(_factor(second, "newsworthiness")).override_failure_message("tekrar haber yenilik kaybeder") \
		.is_less(_factor(first, "newsworthiness"))


func test_organ_lean_changes_how_aligned_stories_score() -> void:
	var aligned := _ready_handle()
	var opposed := _ready_handle()
	ActorStore.actor_ref(aligned.state(), MEDIA_1)["state"]["lean"] = {"growth_vs_preservation": 1000}
	ActorStore.actor_ref(opposed.state(), MEDIA_1)["state"]["lean"] = {"growth_vs_preservation": -1000}
	_publish(aligned, _story())
	_publish(opposed, _story())
	var a := aligned.facade.reason(reasons_of(aligned, "decision.media.coverage")[0]["id"])
	var o := opposed.facade.reason(reasons_of(opposed, "decision.media.coverage")[0]["id"])
	assert_int(_factor(a, "lean_alignment")).is_greater(0)
	assert_int(_factor(o, "lean_alignment")).is_less(0)
	assert_int(a.score).is_greater(o.score)


func _factor(record: ReasonRecord, name: String) -> int:
	for f in record.factors:
		if f.name_key == StringName("reason.factor." + name):
			return f.value
	return -99999


func test_real_events_feed_the_media_and_tone_reaches_the_group_reaction() -> void:
	var h := stress_handle(14)
	tick(h, 200)
	var stories := reasons_of(h, "decision.media.coverage")
	assert_int(stories.size()).override_failure_message("kesim tepkisi/oylama haber üretmedi").is_greater(0)
	assert_int(pol(h)["media"]["published"]).is_greater(0)
	var subjects := {}
	for story in stories:
		for subject: String in story["subjects"]:
			subjects[subject] = true
	assert_bool(subjects.has("vote.1") or subjects.has(BLOC_HOUSED) or subjects.has(BLOC_SEEKING)).is_true()
	var tones := PoliticsQuery.media_tone(h.state())
	assert_bool(tones.values().any(func(t: int) -> bool: return t != 0)).override_failure_message(str(tones)).is_true()
	var seen := false
	for key in [BLOC_HOUSED, BLOC_SEEKING]:
		seen = seen or int(pol(h)["blocs"][key]["amp"]) > 0
	assert_bool(seen).override_failure_message("ton hiçbir kesimin tepkisini etkilemedi").is_true()


func test_closed_tone_tags_never_reach_the_event_scanner_even_when_pressure_is_total() -> void:
	var h := _ready_handle(func(f: Dictionary) -> void:
		f["templates"]["pe-04"]["tone_tags"] = ["corruption"]
		f["templates"]["pe-04"]["weight"] = 1000
		f["templates"]["pe-04"]["hard"] = [])
	pol(h)["media"]["last_tick"] = h.state().tick
	pol(h)["media"]["last"] = {"tick": h.state().tick, "newsworthiness": 1000, "lean": 1000, "fact": 1000}
	for week in 10:
		tick(h, 7)
		pol(h)["media"]["last_tick"] = h.state().tick
		pol(h)["media"]["last"] = {"tick": h.state().tick, "newsworthiness": 1000, "lean": 1000, "fact": 1000}
	var fired := PoliticsQuery.agenda(h.state(), h.context, false).filter(
		func(item: Dictionary) -> bool: return item["template"] == "PE-04")
	assert_array(fired).override_failure_message("KAPALI etiketli şablon seçildi").is_empty()
	var open := handle({}, 6, SEED, func(f: Dictionary) -> void:
		f["templates"]["pe-04"]["tone_tags"] = ["corruption"]
		f["templates"]["pe-04"]["weight"] = 1000
		f["templates"]["pe-04"]["hard"] = []
		f["events"]["content"]["blocked_tags"] = [])
	tick(open, 1)
	pol(open)["media"]["last_tick"] = 1
	pol(open)["media"]["last"] = {"tick": 1, "newsworthiness": 1000, "lean": 1000, "fact": 1000}
	tick(open, 7)
	var allowed := PoliticsQuery.agenda(open.state(), open.context, false).filter(
		func(item: Dictionary) -> bool: return item["template"] == "PE-04")
	assert_int(allowed.size()).override_failure_message("etiket listesi boşken şablon seçilebilmeli (test geçerli mi)") \
		.is_equal(1)
