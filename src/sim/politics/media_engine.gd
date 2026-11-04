class_name MediaEngine
extends RefCounted
## Medya organı (T-017 ölçüt 3, characters-npc §6.3/§6.5, SIM-12): haber adaylarını `media.coverage` kararıyla
## değerlendirir, yayımlanan haberin konu tonunu `lag_days` gecikmeyle yazar ve kesimin şikâyetini büyüten
## `media_amplification`ı türetir. Tek yer tutucu organ (AS-7), bağımsız; ad/eğilim verisi roster'dadır.
## Haber adayı: {kind, topic, subject (ref), conflict, scale, fact, parent_ids, key}; kuyruk durumdadır
## (`media.queue`), tarama başına en çok `max_stories` aday değerlendirilir (ReasonLog hacmi).
## `corruption` etiketli şablonlar bu motoru ilgilendirmez (olay tarayıcısı keser).

const SCALE := 1000
const STORY_KINDS: Array[String] = ["protest", "support", "vote_passed", "vote_failed"]
const NOVELTY_REPEAT := 300


static func organ_key(ctx: PoliticsContext) -> String:
	return ctx.politics.media["organ"]


## Haber adayı ekler (kesim tepkisi / meclis sonucu üretir); aynı anahtarlı bekleyen aday tekrar eklenmez.
static func queue_story(state: GameState, story: Dictionary) -> void:
	var queue: Array = PoliticsState.data(state)["media"]["queue"]
	for waiting: Dictionary in queue:
		if waiting["key"] == story["key"]:
			return
	queue.append(story)


## Kesimin gördüğü ton: organın erişim payı x konu tonlarının kesim önceliğiyle ağırlıklı ortalaması (-1000..1000).
@warning_ignore("integer_division")
static func tone_for(state: GameState, ctx: PoliticsContext, bloc_key: String) -> int:
	var organ := ActorStore.actor_ref(state, organ_key(ctx))
	var bloc := ActorStore.actor_ref(state, bloc_key)
	if organ.is_empty() or bloc.is_empty():
		return 0
	var reach := int(organ["state"].get("reach", {}).get(bloc_key, 0))
	var tone: Dictionary = PoliticsState.data(state)["media"]["tone"]
	var topics: Array = bloc["salience"].keys()
	topics.sort()
	var num := 0
	var den := 0
	for topic: String in topics:
		num += int(bloc["salience"][topic]) * int(tone.get(topic, 0))
		den += int(bloc["salience"][topic])
	return 0 if den == 0 else clampi(num / den * reach / SCALE, -SCALE, SCALE)


## Olumsuz tonun şikâyeti büyütme gücü (0..amp_cap): kesim tepkisinin `media_amplification` faktörü.
@warning_ignore("integer_division")
static func amp_for(state: GameState, ctx: PoliticsContext, bloc_key: String) -> int:
	var negative := maxi(-tone_for(state, ctx, bloc_key), 0)
	return mini(negative * int(ctx.politics.media["k_media"]) / SCALE, int(ctx.politics.media["amp_cap"]))


## Konu tonunu kaydırır (olay etkisi `media.tone`); yalnız geçerli konu.
static func shift_tone(state: GameState, ctx: PoliticsContext, topic: String, change: int) -> void:
	if not ctx.actors.topic_ids.has(topic):
		return
	var tone: Dictionary = PoliticsState.data(state)["media"]["tone"]
	tone[topic] = clampi(int(tone.get(topic, 0)) + change, -SCALE, SCALE)


## Her gün: vadesi gelen ton yazılır.
static func apply_due(state: GameState, ctx: PoliticsContext) -> void:
	var media: Dictionary = PoliticsState.data(state)["media"]
	var waiting: Array = []
	for entry: Dictionary in media["pending"]:
		if int(entry["due"]) > state.tick:
			waiting.append(entry)
		else:
			shift_tone(state, ctx, entry["topic"], int(entry["tone"]))
	media["pending"] = waiting


## Haftalık: ton çürür, kuyruktaki adaylar değerlendirilir.
@warning_ignore("integer_division")
static func scan(state: GameState, ctx: PoliticsContext) -> void:
	var media: Dictionary = PoliticsState.data(state)["media"]
	var tone: Dictionary = media["tone"]
	for topic: String in tone:
		tone[topic] = int(tone[topic]) * (SCALE - int(ctx.politics.media["tone_decay"])) / SCALE
	var queue: Array = media["queue"]
	media["queue"] = []
	var limit := int(ctx.politics.media["max_stories"])
	for i in queue.size():
		if i >= limit:
			break
		_evaluate(state, ctx, queue[i])


@warning_ignore("integer_division")
static func _evaluate(state: GameState, ctx: PoliticsContext, story: Dictionary) -> void:
	var cfg: Dictionary = ctx.politics.media
	var media: Dictionary = PoliticsState.data(state)["media"]
	var organ := organ_key(ctx)
	var actor := ActorStore.actor_ref(state, organ)
	if actor.is_empty():
		return
	var seen: Dictionary = media["stories_seen"]
	var novelty := NOVELTY_REPEAT if seen.has(story["key"]) else SCALE
	var newsworthiness := clampi((int(cfg["n_conflict"]) * int(story["conflict"])
		+ int(cfg["n_scale"]) * int(story["scale"]) + int(cfg["n_novelty"]) * novelty) / SCALE, 0, SCALE)
	var lean := _lean_alignment(actor, cfg["story_axes"].get(story["kind"], {}))
	var credibility := int(actor["state"].get("credibility", SCALE))
	# Yayın kararında gerçek sinyalin GÜCÜ sayılır (kötü haber de haberdir); işareti yalnız tonu belirler.
	var factors := {
		"newsworthiness": newsworthiness, "lean_alignment": lean,
		"fact_signal": {"value": clampi(absi(int(story["fact"])), 0, SCALE), "is_estimate": true,
			"source_ref": story["subject"]},
		"credibility_cost": SCALE - credibility,
	}
	var parents := PackedInt64Array()
	for pid: int in story["parent_ids"]:
		parents.append(pid)
	var result := ActorDecision.evaluate(state, ctx.actors, organ, cfg["decision"], factors,
		PackedStringArray([story["subject"]]), _valid_parents(state, parents))
	if not result["ok"]:
		return
	PoliticsState.count(state, "reason_records", result["records"].size())
	seen[story["key"]] = state.tick
	if result["outcome"] != ReasonLog.OUTCOME_POSITIVE:
		return
	var reason_id: int = result["records"][0]["reason_id"]
	var tone_value := _tone_of(cfg, actor, int(story["fact"]), lean, int(story["conflict"]))
	if not str(story["topic"]).is_empty():
		media["pending"].append({"due": state.tick + int(cfg["lag_days"]), "topic": story["topic"], "tone": tone_value})
	media["published"] = int(media["published"]) + 1
	media["last_tick"] = state.tick
	media["last"] = {"tick": state.tick, "kind": story["kind"], "topic": story["topic"], "subject": story["subject"],
		"newsworthiness": newsworthiness, "lean": lean, "fact": int(story["fact"]), "tone": tone_value,
		"reason_id": reason_id}
	SimEventLog.emit(state, SimEvent.KIND_ACTOR_DECIDED, &"event.media.published", PackedStringArray([story["subject"]]),
		{"topic": story["topic"], "tone": tone_value}, PackedInt64Array([reason_id]), 0, StringName(organ))
	PoliticsState.count(state, "events_emitted")


## Haber aksları ile organın eğilimi (lean) arasında -1000..1000 uyum: ortak eksenlerde çarpımların ortalaması.
@warning_ignore("integer_division")
static func _lean_alignment(actor: Dictionary, story_axes: Dictionary) -> int:
	var lean: Dictionary = actor["state"].get("lean", {})
	var axes: Array = story_axes.keys()
	axes.sort()
	var total := 0
	var count := 0
	for axis: String in axes:
		total += int(lean.get(axis, 0)) * int(story_axes[axis]) / SCALE
		count += 1
	return 0 if count == 0 else clampi(total / count, -SCALE, SCALE)


## Ton (§6.5): w_fact*gerçek + w_lean*uyum + w_sens*hassasiyet*çatışma (işaret gerçek sinyalin işareti).
@warning_ignore("integer_division")
static func _tone_of(cfg: Dictionary, actor: Dictionary, fact: int, lean: int, conflict: int) -> int:
	var base: int = (int(cfg["w_fact"]) * fact + int(cfg["w_lean"]) * lean) / SCALE
	var sensational: int = int(cfg["w_sens"]) * int(actor["state"].get("sensationalism", 0)) * conflict / (SCALE * SCALE)
	var direction := signi(fact) if fact != 0 else signi(base)
	return clampi(base + direction * sensational, -SCALE, SCALE)


## Yalnız hâlâ saklanan (1..son) gerekçe kimlikleri (budanmış ebeveyn karar kaydını bozmasın).
static func _valid_parents(state: GameState, ids: PackedInt64Array) -> PackedInt64Array:
	var out := PackedInt64Array()
	for id in ids:
		if id >= 1 and id <= state.reasons.last_id():
			out.append(id)
	return out
