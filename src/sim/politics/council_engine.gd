class_name CouncilEngine
extends RefCounted
## Küçük meclis oylaması (T-017 ölçüt 2, characters-npc §5/§6.3, SIM-05/SIM-12, AS-8/Q-007/Q-014): oyuncunun imar/bütçe
## önerisi oturumda oylanır; her üye `council.vote` kararını (tek puanlama çatısı) gerekçeli verir. Üye sayısı
## roster'daki council aktörlerinden, usul (oturum aralığı, eşitlik, çekimser bandı, sürtünme)
## `data/politics/council.json`'dandır:
## hepsi veri, kanon değil. Oylama `requires_council` bayrağına göre açılır (Q-014 AÇIK: iki yol da var).
##
## Meclis belediyenin KOŞULUNU değiştirir: kabul edilen imar önerisi yalnız `pending_zone` yazar (CAN-03: özel bina
## yaratmaz). Tahmin (`forecast`) gürültüsüz, kayıt yazmadan hesaplanır ve sonuçtan AYRIDIR.
## Oylama kaydı: {id, kind, subject_ref, title_key, opened_tick, closes_tick, status, yes, no, abstain,
## positions [{member, position, reason_id}], reason_ids, proposal {…},
## context {axes, stakes, regions, topic, realism?}, resolved_tick, applied}.

const SCALE := 1000
const PENDING := "pending"
const PASSED := "passed"
const FAILED := "failed"
const YES := "yes"
const NO := "no"
const ABSTAIN := "abstain"
const UNDECIDED := "undecided"


# --- Öneri hazırlama ---

## `zoning.propose` parametrelerinden oylama belirtimi (öneri + bağlam). Bağlam tablolardan türer, durum okumaz.
static func zoning_spec(ctx: PoliticsContext, params: Dictionary, command_id: int, delay_days: int) -> Dictionary:
	var land_use := String(params["land_use"])
	var parcel_ids: Array = []
	var codes: Array[String] = []
	for id in params["parcel_ids"] as PackedInt64Array:
		parcel_ids.append(id)
		var code := ctx.regions.code_of(id)
		if not code.is_empty() and not codes.has(code):
			codes.append(code)
	codes.sort()
	var council: Dictionary = ctx.politics.council
	var stakes: Dictionary = council["proposal_effects"].get("zoning", {}).get(land_use, {})
	return {
		"kind": "zoning", "subject_ref": String(SimContract.ref(SimContract.REF_COMMAND, command_id)),
		"proposal": {"kind": "zoning", "parcel_ids": parcel_ids, "land_use": land_use, "command_id": command_id,
			"density": int(params.get("density", ParcelZoningSystem.NO_VALUE)),
			"max_height_m": int(params.get("max_height_m", ParcelZoningSystem.NO_VALUE)), "delay_days": delay_days},
		"context": {"axes": (council["proposal_axes"].get("zoning", {}).get(land_use, {}) as Dictionary).duplicate(),
			"stakes": stakes.duplicate(true), "regions": codes, "topic": dominant_topic(stakes)},
	}


## Bütçe önerisi belirtimi (T-014 bütçe sistemi kurulunca komut işleyicisi çağırır; şimdilik API/test). `context`:
## {axes, stakes, realism} isteğe bağlı; `lines` serbest veri ({satır: tamsayı}).
static func budget_spec(budget_id: int, lines: Dictionary, context: Dictionary = {}) -> Dictionary:
	return {
		"kind": "budget", "subject_ref": String(SimContract.ref(SimContract.REF_BUDGET, budget_id)),
		"proposal": {"kind": "budget", "budget_id": budget_id, "lines": lines.duplicate(true)},
		"context": {"axes": context.get("axes", {}).duplicate(), "stakes": context.get("stakes", {}).duplicate(true),
			"regions": [], "topic": dominant_topic(context.get("stakes", {})), "realism": int(context.get("realism", 0))},
	}


## Etkisi (mutlak toplam) en büyük konu; yoksa "".
static func dominant_topic(stakes: Dictionary) -> String:
	var totals := {}
	for cohort_id: String in stakes:
		for topic: String in stakes[cohort_id]:
			totals[topic] = int(totals.get(topic, 0)) + absi(int(stakes[cohort_id][topic]))
	var topics: Array = totals.keys()
	topics.sort()
	var best := ""
	var best_value := 0
	for topic: String in topics:
		if int(totals[topic]) > best_value:
			best_value = int(totals[topic])
			best = topic
	return best


## Bu parseli içeren bekleyen oylama kimliği; yoksa 0.
static func pending_vote_for_parcel(state: GameState, parcel_id: int) -> int:
	for vote: Dictionary in _votes(state):
		if vote["status"] == PENDING and (vote["proposal"].get("parcel_ids", []) as Array).has(parcel_id):
			return int(vote["id"])
	return 0


# --- Açma / çözme ---

## Oylamayı açar; oylama kimliğini döner. `spec`: zoning_spec / budget_spec çıktısı.
static func open_vote(state: GameState, ctx: PoliticsContext, spec: Dictionary) -> int:
	var council: Dictionary = PoliticsState.data(state)["council"]
	var cfg: Dictionary = ctx.politics.council
	var id: int = council["next_vote"]
	council["next_vote"] = id + 1
	var positions: Array = []
	for member: String in cfg["members"]:
		positions.append({"member": member, "position": UNDECIDED, "reason_id": 0})
	var kind: String = spec["kind"]
	var vote := {
		"id": id, "kind": kind, "subject_ref": spec["subject_ref"], "title_key": cfg["titles"][kind],
		"opened_tick": state.tick, "closes_tick": _closing_tick(state.tick, cfg), "status": PENDING, "yes": 0, "no": 0,
		"abstain": 0, "positions": positions, "reason_ids": [], "proposal": spec["proposal"],
		"context": spec["context"], "resolved_tick": -1, "applied": false,
	}
	(council["votes"] as Array).append(vote)
	SimEventLog.emit(state, SimEvent.KIND_COUNCIL_VOTE_OPENED, &"event.council.vote_opened",
		PackedStringArray([String(SimContract.ref(SimContract.REF_VOTE, id)), spec["subject_ref"]]),
		{"kind": kind, "closes_tick": vote["closes_tick"]}, PackedInt64Array(), _command_of(vote), StringName(cfg["body"]))
	PoliticsState.count(state, "events_emitted")
	_trim(council, int(cfg["history_limit"]))
	return id


## Oturum sınırı: acilistan en az `min_lead_days` sonraki ilk `session_days` katı.
@warning_ignore("integer_division")
static func _closing_tick(tick: int, cfg: Dictionary) -> int:
	var session := int(cfg["session_days"])
	var earliest := tick + int(cfg["min_lead_days"])
	return (earliest + session - 1) / session * session


## Günlük: vakti gelen oylamaları kimlik sırasıyla çözer.
static func resolve_due(state: GameState, ctx: PoliticsContext) -> void:
	for vote: Dictionary in _votes(state):
		if vote["status"] == PENDING and int(vote["closes_tick"]) <= state.tick:
			_resolve(state, ctx, vote)


static func _resolve(state: GameState, ctx: PoliticsContext, vote: Dictionary) -> void:
	var cfg: Dictionary = ctx.politics.council
	var player := ActorStore.protagonist_key(state, ctx.actors)
	var vote_ref := String(SimContract.ref(SimContract.REF_VOTE, int(vote["id"])))
	var subjects := PackedStringArray([vote_ref, vote["subject_ref"]])
	var yes := 0
	var no := 0
	var abstain := 0
	var reason_ids: Array = []
	for position: Dictionary in vote["positions"]:
		var factors := member_factors(state, ctx, position["member"], vote, player)
		var result := ActorDecision.evaluate(state, ctx.actors, position["member"], cfg["decision"], factors, subjects)
		if not result["ok"]:
			push_error("CouncilEngine: oy verilemedi (%s: %s)" % [position["member"], result["error"]])
			position["position"] = ABSTAIN
			abstain += 1
			continue
		var record: Dictionary = result["records"][0]
		position["reason_id"] = record["reason_id"]
		reason_ids.append(record["reason_id"])
		PoliticsState.count(state, "reason_records")
		if absi(int(record["margin"])) <= int(cfg["abstain_band"]):
			position["position"] = ABSTAIN
			abstain += 1
		elif record["outcome"] == ReasonLog.OUTCOME_POSITIVE:
			position["position"] = YES
			yes += 1
		else:
			position["position"] = NO
			no += 1
	vote["yes"] = yes
	vote["no"] = no
	vote["abstain"] = abstain
	vote["reason_ids"] = reason_ids
	vote["resolved_tick"] = state.tick
	var passed: bool = yes > no or (yes == no and cfg["tie_result"] == "pass")
	vote["status"] = PASSED if passed else FAILED
	if passed and vote["kind"] == "zoning":
		_apply_zoning(state, ctx, vote)
	SimEventLog.emit(state, SimEvent.KIND_COUNCIL_VOTE_RESOLVED,
		&"event.council.vote_passed" if passed else &"event.council.vote_failed", subjects,
		{"yes": yes, "no": no, "abstain": abstain, "kind": vote["kind"]}, PackedInt64Array(reason_ids), _command_of(vote),
		StringName(cfg["body"]))
	PoliticsState.count(state, "events_emitted")
	_queue_story(state, ctx, vote, vote_ref)
	_trim(PoliticsState.data(state)["council"], int(cfg["history_limit"]))


## Kabul edilen imar: yalnız koşul (pending_zone); yürürlük = şimdi + facade gecikmesi + meclis sürtünmesi.
static func _apply_zoning(state: GameState, ctx: PoliticsContext, vote: Dictionary) -> void:
	var proposal: Dictionary = vote["proposal"]
	var friction := maxi(int(ctx.politics.council["friction_days"])
		+ int(PoliticsState.data(state)["council"]["friction_adjust"]), 0)
	var due: int = state.tick + int(proposal["delay_days"]) + friction
	for id: int in proposal["parcel_ids"]:
		ParcelZoningSystem.set_pending(state, id, StringName(proposal["land_use"]), due, int(proposal["command_id"]),
			int(proposal["density"]), int(proposal["max_height_m"]))
	vote["applied"] = true


@warning_ignore("integer_division")
static func _queue_story(state: GameState, ctx: PoliticsContext, vote: Dictionary, vote_ref: String) -> void:
	var seats := maxi((vote["positions"] as Array).size(), 1)
	var passed: bool = vote["status"] == PASSED
	var realism := realism_of(state, ctx, vote)
	MediaEngine.queue_story(state, {
		"kind": "vote_passed" if passed else "vote_failed", "topic": vote["context"].get("topic", ""),
		"subject": vote_ref, "conflict": SCALE - absi(int(vote["yes"]) - int(vote["no"])) * SCALE / seats,
		"scale": SCALE / 2, "fact": realism if passed else -absi(realism),
		"parent_ids": (vote["reason_ids"] as Array).slice(0, int(ctx.politics.cadence["cause_cap"])),
		"key": "vote|%d" % int(vote["id"]),
	})


# --- Üye girdileri ---

## Üyenin `council.vote` faktörleri (hepsi -1000..1000 tamsayı; kaynak ref'li).
static func member_factors(state: GameState, ctx: PoliticsContext, member_key: String, vote: Dictionary,
		player: String) -> Dictionary:
	var factors := ActorInputs.relation_factors(state, ctx.actors, member_key, player)
	factors.erase("topic_memory")
	var actor := ActorStore.actor_ref(state, member_key)
	factors["stance_distance"] = stance_alignment(actor["stance"], vote["context"].get("axes", {}))
	factors["bloc_pressure"] = bloc_pressure(state, ctx, actor, vote["context"].get("stakes", {}))
	factors["lobby_pressure"] = 0
	factors["budget_realism"] = realism_of(state, ctx, vote)
	return factors


## Üye duruşu ile önerinin eksen konumu arasındaki uyum: 1000 - ortalama |fark| (-1000..1000); eksen yoksa 0.
@warning_ignore("integer_division")
static func stance_alignment(member_stance: Dictionary, axes: Dictionary) -> int:
	if axes.is_empty():
		return 0
	var keys: Array = axes.keys()
	keys.sort()
	var total := 0
	for axis: String in keys:
		total += absi(int(member_stance.get(axis, 0)) - int(axes[axis]))
	return clampi(SCALE - total / keys.size(), -SCALE, SCALE)


## Temsil ettiği kesimlerin öneriden payı: stake (öncelik ağırlıklı etki) x yoğunluk (taban + k x defter);
## kesimler eşit.
## Dönüş: {value, source_ref} (kaynak = en çok etkilenen kesim).
@warning_ignore("integer_division")
static func bloc_pressure(state: GameState, ctx: PoliticsContext, actor: Dictionary, stakes: Dictionary) -> Dictionary:
	var constituency: Array = actor["state"].get("constituency_blocs", [])
	var pol := PoliticsState.data(state)
	var total := 0
	var counted := 0
	var source := ""
	var strongest := 0
	for bloc_key: String in constituency:
		var bloc: Variant = pol["blocs"].get(bloc_key, null)
		if not (bloc is Dictionary):
			continue
		var effects: Dictionary = stakes.get(bloc["cohort"], {})
		var bloc_actor := ActorStore.actor_ref(state, bloc_key)
		var weight_sum := 0
		var weighted := 0
		var topics: Array = effects.keys()
		topics.sort()
		for topic: String in topics:
			var priority := int(bloc_actor["salience"].get(topic, 0))
			weighted += priority * int(effects[topic])
			weight_sum += priority
		var stake := 0 if weight_sum == 0 else weighted / weight_sum
		var intensity := mini(int(ctx.politics.council["pressure_base"])
			+ int(ctx.politics.council["pressure_k"]) * maxi(int(bloc["G"]), int(bloc["S"])) / SCALE, SCALE)
		var pressure := stake * intensity / SCALE
		total += pressure
		counted += 1
		if absi(pressure) > strongest:
			strongest = absi(pressure)
			source = bloc_key
	return {"value": 0 if counted == 0 else clampi(total / counted, -SCALE, SCALE), "source_ref": source}


## Uygulanabilirlik (budget_realism): bütçe için bağlamdaki değer; imar için etkilenen bölgelerin EN YÜKSEK altyapı
## yükünden (en kötü bölge belirleyici).
@warning_ignore("integer_division")
static func realism_of(state: GameState, ctx: PoliticsContext, vote: Dictionary) -> int:
	if vote["kind"] != "zoning":
		return int(vote["context"].get("realism", 0))
	var spec: Dictionary = ctx.politics.council["realism"].get("zoning", {})
	var codes: Array = vote["context"].get("regions", [])
	if spec.is_empty() or codes.is_empty():
		return 0
	var rows := EconomyQuery.region_stats(state, ctx.economy)
	var peak_load := -1
	for row in rows:
		if codes.has(String(row["code"])):
			peak_load = maxi(peak_load, int(row["infra_load_pm"]))
	if peak_load < 0:
		return 0
	var span := int(spec["hi"]) - int(spec["lo"])
	var ratio := clampi((peak_load - int(spec["lo"])) * SCALE / span, 0, SCALE)
	return SCALE - 2 * ratio


# --- Tahmin ---

## Gürültüsüz, kayıt yazmayan oy tahmini (sonuçtan ayrı): {yes, no, abstain, passes, swing}. `swing`: marjı gürültü
## genliğinden küçük, yani tahmini belirsiz üye sayısı.
@warning_ignore("integer_division")
static func forecast(state: GameState, ctx: PoliticsContext, vote: Dictionary) -> Dictionary:
	var cfg: Dictionary = ctx.politics.council
	var table := ctx.actors.table(cfg["decision"])
	var player := ActorStore.protagonist_key(state, ctx.actors)
	var yes := 0
	var no := 0
	var abstain := 0
	var swing := 0
	for position: Dictionary in vote["positions"]:
		var actor := ActorStore.actor_ref(state, position["member"])
		var result := ActorDecision.decide(member_factors(state, ctx, position["member"], vote, player), table, {
			"traits": actor["traits"], "draw": 0, "noise_trait": ctx.actors.noise_trait,
			"previous_positive": false})
		if not result["ok"]:
			abstain += 1
			continue
		var uncertainty: int = int(table["noise_amp"]) * int(actor["traits"].get(ctx.actors.noise_trait, 500)) / SCALE
		swing += 1 if absi(int(result["margin"])) <= uncertainty else 0
		if absi(int(result["margin"])) <= int(cfg["abstain_band"]):
			abstain += 1
		elif result["outcome"] == ReasonLog.OUTCOME_POSITIVE:
			yes += 1
		else:
			no += 1
	return {"yes": yes, "no": no, "abstain": abstain, "swing": swing,
		"passes": yes > no or (yes == no and cfg["tie_result"] == "pass")}


# --- Okuma / bakım ---

static func vote_by_id(state: GameState, vote_id: int) -> Dictionary:
	for vote: Dictionary in _votes(state):
		if int(vote["id"]) == vote_id:
			return vote
	return {}


## Oylamalar (canlı liste; salt okunur kullanın), kimlik artan.
static func _votes(state: GameState) -> Array:
	return PoliticsState.data(state).get("council", {}).get("votes", [])


static func _command_of(vote: Dictionary) -> int:
	return int(vote["proposal"].get("command_id", 0))


## Bekleyenler her zaman kalır; kapanmışlardan en yeni `limit` tanesi saklanır.
static func _trim(council: Dictionary, limit: int) -> void:
	var votes: Array = council["votes"]
	var closed := 0
	for vote: Dictionary in votes:
		closed += 0 if vote["status"] == PENDING else 1
	var drop := closed - limit
	var kept: Array = []
	for vote: Dictionary in votes:
		if vote["status"] != PENDING and drop > 0:
			drop -= 1
			continue
		kept.append(vote)
	council["votes"] = kept
