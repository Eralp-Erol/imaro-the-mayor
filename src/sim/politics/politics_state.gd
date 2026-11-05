class_name PoliticsState
extends RefCounted
## Siyasi sistemin KALICI durumu (T-017): `state.systems["politics"]`. Sistem/motor nesneleri durum tutmaz; her şey
## burada, dolayısıyla kayda ve durum hash'ine otomatik girer. Yalnız tamsayı, metin, dizi ve sözlük (kayan nokta yok);
## sözlük anahtarları metindir (bölge kodu, aktör anahtarı, şablon kimliği). Yineleme sıralı anahtarlarla yapılır.
##
## Biçim:
##   schema, config_digest, started_tick (-1 = henüz başlamadı)
##   blocs     {kesim anahtarı: {cohort, exposure {bölge: pm}, size, signals {ad: pm}, hot_region, G, S, amp, org,
##              eval {tick, G, S, amp, tier, reaction, intensity, stance, stance_delta, topic, reason_ids, cause_refs},
##              derived_tick}}
##   baselines {bölge: başlangıç konut arzı}
##   service   {overload_days {bölge: gün}, latent {bölge: önceki hane}, growth {bölge: pm}}
##   media     {tone {konu: -1000..1000}, pending [{due, topic, tone}], queue [haber adayı], published, last_tick,
##              last {…}, stories_seen {anahtar: tick}}
##   council   {next_vote, votes [oylama], friction_adjust}
##   risk      {adjust {bölge: pm}, level {bölge: pm}}
##   declines  {last_total, ticks [tick,…]}
##   events    {last_pressure {şablon: pm}, cooldown_until {şablon: tick}, next_item, agenda [öğe], effects [bekleyen],
##              fired, interrupts {çeyrek: sayı}}
##   council_trust {penalty {üye: pm}, changes}  (D-021, yalnız yerinden edilme meclis güvenini düşürünce yaratılır)
##   counters  {scans, reason_records, events_emitted}

const KEY := "politics"
const SCHEMA := 1
const NEUTRAL := "neutral"


static func data(state: GameState) -> Dictionary:
	var d: Variant = state.systems.get(KEY, null)
	return d if d is Dictionary and d.get("schema", null) == SCHEMA else {}


static func is_initialized(state: GameState) -> bool:
	return not data(state).is_empty()


## Durumu kurar (idempotent). Aktör durumu önce kurulmuş olmalıdır; değilse false.
static func ensure_initialized(state: GameState, ctx: PoliticsContext) -> bool:
	if is_initialized(state):
		return true
	if not ActorStore.ensure_initialized(state, ctx.actors):
		return false
	var blocs := {}
	for cohort: Dictionary in ctx.politics.blocs["cohorts"]:
		blocs[cohort["bloc"]] = new_bloc(cohort["id"])
	state.systems[KEY] = {
		"schema": SCHEMA, "config_digest": ctx.politics.digest, "started_tick": -1, "blocs": blocs,
		"baselines": {}, "service": {"overload_days": {}, "latent": {}, "growth": {}},
		"media": {"tone": {}, "pending": [], "queue": [], "published": 0, "last_tick": -1, "last": {},
			"stories_seen": {}},
		"council": {"next_vote": 1, "votes": [], "friction_adjust": 0},
		"risk": {"adjust": {}, "level": {}},
		"declines": {"last_total": 0, "ticks": []},
		"events": {"last_pressure": {}, "cooldown_until": {}, "next_item": 1, "agenda": [], "effects": [], "fired": 0,
			"interrupts": {}},
		"counters": {"scans": 0, "reason_records": 0, "events_emitted": 0},
	}
	return true


static func new_bloc(cohort_id: String) -> Dictionary:
	return {
		"cohort": cohort_id, "exposure": {}, "size": 0, "signals": {}, "hot_region": "", "G": 0, "S": 0, "amp": 0,
		"org": 0, "eval": new_eval(), "derived_tick": -1,
	}


static func new_eval() -> Dictionary:
	return {
		"tick": -1, "G": 0, "S": 0, "amp": 0, "tier": "", "reaction": NEUTRAL, "intensity": 0, "stance": 0,
		"stance_delta": 0, "topic": "", "reason_ids": [], "cause_refs": [],
	}


static func config_matches(state: GameState, ctx: PoliticsContext) -> bool:
	return is_initialized(state) and data(state)["config_digest"] == ctx.politics.digest


## Sıralı kesim anahtarları.
static func bloc_keys(state: GameState) -> Array[String]:
	var out: Array[String] = []
	for key: String in data(state).get("blocs", {}):
		out.append(key)
	out.sort()
	return out


## Sayaç artırır (ReasonLog hacmi ve olay ölçümü).
static func count(state: GameState, counter: String, amount: int = 1) -> void:
	var counters: Dictionary = data(state)["counters"]
	counters[counter] = int(counters.get(counter, 0)) + amount


## Kayıtlı politika verisinin biçim hatası ("" = geçerli; veri yoksa da ""). GameState.validate_dict çağırır.
static func validate_data(value: Variant) -> String:
	if value == null:
		return ""
	if not (value is Dictionary) or value.get("schema", null) != SCHEMA:
		return "durum.systems.politics şeması geçersiz"
	for field_name in ["blocs", "baselines", "service", "media", "council", "risk", "declines", "events", "counters"]:
		if not (value.get(field_name, null) is Dictionary):
			return "durum.systems.politics.%s sözlük değil" % field_name
	if typeof(value.get("started_tick", null)) != TYPE_INT or typeof(value.get("config_digest", null)) != TYPE_STRING:
		return "durum.systems.politics.started_tick/config_digest geçersiz"
	for key: String in value["blocs"]:
		var problem := _bloc_problem(key, value["blocs"][key])
		if not problem.is_empty():
			return problem
	var council: Dictionary = value["council"]
	if typeof(council.get("next_vote", null)) != TYPE_INT or not (council.get("votes", null) is Array) \
			or typeof(council.get("friction_adjust", null)) != TYPE_INT:
		return "durum.systems.politics.council geçersiz"
	for vote: Variant in council["votes"]:
		var vote_problem := _vote_problem(vote)
		if not vote_problem.is_empty():
			return vote_problem
	var trust_problem := _council_trust_problem(value.get(CouncilTrust.KEY, null))
	if not trust_problem.is_empty():
		return trust_problem
	var events: Dictionary = value["events"]
	for field_name in ["agenda", "effects"]:
		if not (events.get(field_name, null) is Array):
			return "durum.systems.politics.events.%s dizi değil" % field_name
	for field_name in ["last_pressure", "cooldown_until", "interrupts"]:
		if not (events.get(field_name, null) is Dictionary):
			return "durum.systems.politics.events.%s sözlük değil" % field_name
	if typeof(events.get("next_item", null)) != TYPE_INT or typeof(events.get("fired", null)) != TYPE_INT:
		return "durum.systems.politics.events.next_item/fired int değil"
	var media: Dictionary = value["media"]
	if not (media.get("tone", null) is Dictionary) or not (media.get("pending", null) is Array) \
			or not (media.get("queue", null) is Array) or typeof(media.get("published", null)) != TYPE_INT:
		return "durum.systems.politics.media geçersiz"
	return ""


## D-021 `council_trust` (yalnız ilk etkide yaratılır): {penalty {üye: int >= 0}, changes: int}.
static func _council_trust_problem(value: Variant) -> String:
	if value == null:
		return ""
	if not (value is Dictionary) or not (value.get("penalty", null) is Dictionary) \
			or typeof(value.get("changes", null)) != TYPE_INT:
		return "durum.systems.politics.council_trust geçersiz"
	for member: Variant in value["penalty"]:
		if typeof(member) != TYPE_STRING or typeof(value["penalty"][member]) != TYPE_INT or value["penalty"][member] < 0:
			return "durum.systems.politics.council_trust.penalty '%s' tamsayı >= 0 değil" % str(member)
	return ""


static func _bloc_problem(key: String, bloc: Variant) -> String:
	if not (bloc is Dictionary) or not (bloc.get("exposure", null) is Dictionary) \
			or not (bloc.get("eval", null) is Dictionary):
		return "politika kesimi '%s' kaydı bozuk" % key
	for field_name in ["size", "G", "S", "amp", "org", "derived_tick"]:
		if typeof(bloc.get(field_name, null)) != TYPE_INT:
			return "politika kesimi '%s'.%s tamsayı değil" % [key, field_name]
	var eval_data: Dictionary = bloc["eval"]
	for field_name in ["tick", "G", "S", "amp", "intensity", "stance", "stance_delta"]:
		if typeof(eval_data.get(field_name, null)) != TYPE_INT:
			return "politika kesimi '%s'.eval.%s tamsayı değil" % [key, field_name]
	if not (eval_data.get("reason_ids", null) is Array) or not (eval_data.get("cause_refs", null) is Array):
		return "politika kesimi '%s'.eval.reason_ids/cause_refs dizi değil" % key
	return ""


static func _vote_problem(vote: Variant) -> String:
	if not (vote is Dictionary):
		return "politika oylaması sözlük değil"
	for field_name in ["id", "opened_tick", "closes_tick", "yes", "no", "abstain"]:
		if typeof(vote.get(field_name, null)) != TYPE_INT:
			return "politika oylaması .%s tamsayı değil" % field_name
	if not (vote.get("positions", null) is Array) or not (vote.get("proposal", null) is Dictionary) \
			or not (vote.get("context", null) is Dictionary):
		return "politika oylaması positions/proposal/context geçersiz"
	return ""
