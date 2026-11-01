class_name EventEngine
extends RefCounted
## Siyasi olaylar (T-017 ölçüt 4, political-events §1-§4/§7, SIM-05/SIM-11/SIM-12): olay YAZILMAZ, TETİKLENİR. Haftalık
## tarayıcı şablonları kimlik sırasıyla gezer; baskı (drivers), hazard ve tohumlu çekilişle ateşler; ateşleme de bir
## gerekçedir (`decision.event.fire`, skor = hazard - çekiliş, eşik 0). Teslim düzeyi `agenda`: modal olmayan, geri
## sayımlı gündem öğesi (otomatik duraklatma yalnız ayar). `decision` düzeyi çeyrek başına kesinti bütçesiyle sınırlı.
##
## Seçenekler `requires.authority` ile yetki kapılıdır: yetki yoksa seçenek GİZLENMEZ, kilitli ve nedeniyle görünür;
## `defer` her zaman kalır. Seçenek etkileri gecikme + süre + eğri ile zamana yayılır (SIM-08); etki yalnız mevcut
## sistem durumlarına (şikâyet/memnuniyet defteri, ilişki, medya tonu, yatırımcı riski, meclis sürtünmesi) yazar. Hiçbir
## seçenek özel bina yerleştirmez (CAN-03). Şablonlar `corruption` gibi KAPALI etiketleri taşıyorsa hiç seçilmez.
##
## Öğe: {id, template, status (open|resolved|expired|lapsed), delivery, pauses, opened_tick, deadline, stage, bloc,
## region, topic, affected [bloc anahtarları], reason_id, deferred, chosen, resolved_tick}. Bekleyen etki: {item_id,
## option_id, target, curve, magnitude, attribution, start, duration, applied, blocs, topic, region, members}.

const SCALE := 1000
const OPEN := "open"
const RESOLVED := "resolved"
const EXPIRED := "expired"
const LAPSED := "lapsed"
## Gündem olay türleri (sözleşme v1.0 kataloğunda yok: MINOR v1.1 isteği).
const AGENDA_OPENED := &"politics.agenda_opened"
const AGENDA_RESOLVED := &"politics.agenda_resolved"
const DEFER_VERB := "defer"
const FIRE_DECISION := "decision.event.fire"
const FACTOR_PREFIX := "reason.factor."


# --- Tarama ---

## Haftalık tarama: kaynakları hesaplar, şablonları kimlik sırasıyla değerlendirir, ateşlenenleri açar.
static func scan(state: GameState, ctx: PoliticsContext) -> void:
	var rows := EconomyQuery.region_stats(state, ctx.economy)
	if rows.is_empty():
		return
	EventSources.track(state, ctx)
	EventSources.update_risk(state, ctx, rows)
	var sources := EventSources.compute(state, ctx, rows)
	var events: Dictionary = PoliticsState.data(state)["events"]
	var candidates: Array = []
	for template in ctx.politics.templates:
		var evaluated := _evaluate_template(state, ctx, template, sources, events)
		if evaluated["fire"]:
			candidates.append(evaluated)
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["weight"] > b["weight"] or (a["weight"] == b["weight"] and a["id"] < b["id"]))
	var opened := 0
	for candidate: Dictionary in candidates:
		if opened >= int(ctx.politics.events["max_new_per_scan"]):
			break
		var template := ctx.politics.template(candidate["id"])
		if _mutex_active(events, ctx, template):  # bu taramada az önce açılan öğe de konuyu tutar
			continue
		_fire(state, ctx, template, candidate)
		opened += 1


## Şablonu değerlendirir: {id, weight, fire, pressure, hazard, draw, parts}. Yalnız tarayıcı durumunu (son baskı,
## silahlanma) günceller.
@warning_ignore("integer_division")
static func _evaluate_template(state: GameState, ctx: PoliticsContext, template: Dictionary, sources: Dictionary,
		events: Dictionary) -> Dictionary:
	var id: String = template["id"]
	var result := {"id": id, "weight": int(template["weight"]), "fire": false, "pressure": 0, "hazard": 0, "draw": 0,
		"parts": []}
	if not ctx.politics.milestone_open(template["min_milestone"]) or _blocked(ctx, template):
		return result
	var pressure_total := 0
	var weight_total := 0
	for driver: Dictionary in template["drivers"]:
		var span: int = int(driver["hi"]) - int(driver["lo"])
		var part := clampi((int(sources[driver["src"]]) - int(driver["lo"])) * SCALE / span, 0, SCALE)
		pressure_total += int(driver["weight"]) * part
		weight_total += int(driver["weight"])
		result["parts"].append({"name": driver["name"], "value": part})
	var pressure := pressure_total / weight_total
	result["pressure"] = pressure
	var last_pressure: Dictionary = events["last_pressure"]
	var armed := _is_armed(state, events, template, pressure)
	var rising: bool = not last_pressure.has(id) \
		or pressure + int(ctx.politics.events["rising_slack"]) >= int(last_pressure[id])
	last_pressure[id] = pressure
	if not armed or not rising or _mutex_active(events, ctx, template) or not _hard_ok(ctx, template, sources):
		return result
	result["hazard"] = int(template["weight"]) * _pow_pm(pressure, int(template["gamma"])) / SCALE
	result["draw"] = event_draw(state, id)
	result["fire"] = int(result["hazard"]) >= int(result["draw"])
	return result


## Çekiliş 1..1000, (tick, şablon) anahtarlı; `rng.events` akışının tohumundan türer, akışı tüketmez.
static func event_draw(state: GameState, template_id: String) -> int:
	var stream_seed := RngStreams.derive_seed(state.world_seed, &"events")
	var key := StringName("%d|%s" % [state.tick, template_id])
	return RngStreams.derive_seed(stream_seed, key) % SCALE + 1


## p^gamma / 1000^(gamma-1) (pm).
@warning_ignore("integer_division")
static func _pow_pm(pressure: int, gamma: int) -> int:
	var out := pressure
	for i in gamma - 1:
		out = out * pressure / SCALE
	return out


static func _blocked(ctx: PoliticsContext, template: Dictionary) -> bool:
	for tag: String in template["tone_tags"]:
		if (ctx.politics.events["blocked_tags"] as Array).has(tag):
			return true
	return false


## Silahlanma (histerez): ateşlemeden sonra baskı `rearm_below` altına inene ya da bekleme bitene dek kapalı.
static func _is_armed(state: GameState, events: Dictionary, template: Dictionary, pressure: int) -> bool:
	var id: String = template["id"]
	var until := int(events["cooldown_until"].get(id, -1))
	if until < 0:
		return true
	if state.tick >= until or pressure < int(template["rearm_below"]):
		events["cooldown_until"].erase(id)
		return true
	return false


static func _mutex_active(events: Dictionary, ctx: PoliticsContext, template: Dictionary) -> bool:
	for item: Dictionary in events["agenda"]:
		if item["status"] != OPEN:
			continue
		for group: String in ctx.politics.template(item["template"])["mutex"]:
			if (template["mutex"] as Array).has(group):
				return true
	return false


static func _hard_ok(ctx: PoliticsContext, template: Dictionary, sources: Dictionary) -> bool:
	for cond: Dictionary in template["hard"]:
		if not compare(int(sources[cond["src"]]), cond["op"], EventSources.threshold_value(ctx, cond["value"])):
			return false
	return true


static func compare(value: int, op: String, threshold: int) -> bool:
	match op:
		">=":
			return value >= threshold
		">":
			return value > threshold
		"<=":
			return value <= threshold
		"<":
			return value < threshold
	return value == threshold


# --- Ateşleme ---

static func _fire(state: GameState, ctx: PoliticsContext, template: Dictionary, evaluated: Dictionary,
		trigger_bloc: String = "", direct_causes: PackedInt64Array = PackedInt64Array()) -> void:
	var pol := PoliticsState.data(state)
	var events: Dictionary = pol["events"]
	var item_id: int = events["next_item"]
	events["next_item"] = item_id + 1
	events["fired"] = int(events["fired"]) + 1
	var trigger := trigger_bloc if not trigger_bloc.is_empty() else EventSources.trigger_bloc(state, ctx)
	var bloc: Dictionary = pol["blocs"].get(trigger, {})
	var factors: Array = []
	for part: Dictionary in evaluated["parts"]:
		factors.append({"name": StringName(FACTOR_PREFIX + part["name"]), "value": part["value"], "weight": 0})
	factors.append({"name": StringName(FACTOR_PREFIX + "hazard"), "value": evaluated["hazard"], "weight": SCALE})
	factors.append({"name": StringName(FACTOR_PREFIX + "rng_draw"), "value": -int(evaluated["draw"]), "weight": SCALE})
	var agenda_ref := "agenda.%d" % item_id
	var subjects := PackedStringArray([agenda_ref])
	if not trigger.is_empty():
		subjects.append(trigger)
	var causes := direct_causes if not direct_causes.is_empty() else _cause_ids(state, ctx, template, trigger)
	var reason_id := state.record_reason(StringName(ctx.politics.events["system_actor"]), StringName(FIRE_DECISION),
		factors, 0, StringName(template["id"].to_lower()), subjects, causes)
	if reason_id < 0:
		events["fired"] = int(events["fired"]) - 1
		events["next_item"] = item_id
		return
	PoliticsState.count(state, "reason_records")
	var delivery := _delivery_for(state, ctx, template, events)
	var item := {
		"id": item_id, "template": template["id"], "status": OPEN, "delivery": delivery,
		"pauses": ctx.politics.cadence["autopause"] == true and delivery == "decision",
		"opened_tick": state.tick, "deadline": state.tick + int(template["expiry_days"]), "stage": 0, "bloc": trigger,
		"region": _region_of_event(state, ctx, bloc, causes), "topic": str(bloc.get("eval", {}).get("topic", "")),
		"affected": _affected(state, template, trigger), "reason_id": reason_id, "deferred": 0, "chosen": "",
		"resolved_tick": -1,
	}
	(events["agenda"] as Array).append(item)
	events["cooldown_until"][template["id"]] = state.tick + int(template["cooldown_days"])
	SimEventLog.emit(state, AGENDA_OPENED, StringName(template["reason_key"]), subjects,
		{"template": template["id"], "delivery": delivery, "expires_tick": item["deadline"]},
		PackedInt64Array([reason_id]), 0, StringName(ctx.politics.events["system_actor"]))
	PoliticsState.count(state, "events_emitted")


## T-042b · DOĞRUDAN nedenle (yerinden edilme) gündem öğesi açılabilir mi: tepki basamağı şartı aranmaz, ama kilometre
## taşı, kapalı etiket, silahlanma/bekleme ve karşılıklı dışlama kapıları aynıdır. Durumu (silahlanma kaydı hariç)
## değiştirmez.
## `independent` (B-008): her yolun öğesi diğerinden bağımsızdır; silahlanma/bekleme ve karşılıklı dışlama aranmaz
## (art arda iki yıkımlı yol = iki ayrı tepki, ikincisi ilk öğenin kapanmasını beklemez).
static func can_open_direct(state: GameState, ctx: PoliticsContext, template_id: String, pressure: int,
		independent: bool = false) -> bool:
	var template := ctx.politics.template(template_id)
	if template.is_empty() or not ctx.politics.milestone_open(template["min_milestone"]) or _blocked(ctx, template):
		return false
	if independent:
		return true
	var events: Dictionary = PoliticsState.data(state)["events"]
	return _is_armed(state, events, template, pressure) and not _mutex_active(events, ctx, template)


## T-042b · Doğrudan nedenli öğeyi açar (`can_open_direct` doğruysa). Çekiliş yok: neden doğrudan ve görünür (yerinden
## edilen hane); ateşleme gerekçesi `causes` (önceden yazılmış neden kaydı) ebeveynli yazılır. Dönüş: açıldı mı.
static func open_direct(state: GameState, ctx: PoliticsContext, template_id: String, trigger_bloc: String,
		pressure: int, source: String, causes: PackedInt64Array, independent: bool = false) -> bool:
	if not can_open_direct(state, ctx, template_id, pressure, independent):
		return false
	var template := ctx.politics.template(template_id)
	var events: Dictionary = PoliticsState.data(state)["events"]
	var before := int(events["next_item"])
	_fire(state, ctx, template, {"id": template_id, "weight": int(template["weight"]), "fire": true,
		"pressure": pressure, "hazard": pressure, "draw": 0, "parts": [{"name": source, "value": pressure}]},
		trigger_bloc, causes)
	return int(events["next_item"]) > before


## `decision` düzeyi çeyrek kesinti bütçesini aşarsa `agenda`ya düşer.
static func _delivery_for(state: GameState, ctx: PoliticsContext, template: Dictionary, events: Dictionary) -> String:
	if template["delivery"] != "decision":
		return template["delivery"]
	var quarter := str(state.quarter_index())
	var used := int(events["interrupts"].get(quarter, 0))
	if used >= int(ctx.politics.events["interrupt_budget_per_quarter"]):
		return "agenda"
	events["interrupts"][quarter] = used + 1
	return "decision"


## Olayın bölgesi: nedenin (olumsuz yatırımcı kararı) parselinin bölgesi; yoksa tetikleyen kesimin sıcak bölgesi; o da
## yoksa altyapı yükü en yüksek bölge (eşitlikte kod sırası); hiçbiri yoksa "".
static func _region_of_event(state: GameState, ctx: PoliticsContext, bloc: Dictionary,
		causes: PackedInt64Array) -> String:
	for i in range(causes.size() - 1, -1, -1):
		var record := state.reasons.peek(causes[i])  # kopyasız; yalnız okunur
		for subject: String in record.get("subjects", PackedStringArray()):
			var code := ctx.regions.code_of(int(SimContract.parse_ref(StringName(subject))["id"])) \
				if subject.begins_with("parcel.") else ""
			if not code.is_empty():
				return code
	var hot := _trigger_region(bloc)
	if not hot.is_empty():
		return hot
	var best := ""
	var best_load := -1
	for row in EconomyQuery.region_stats(state, ctx.economy):
		if int(row["infra_load_pm"]) > best_load:
			best_load = int(row["infra_load_pm"])
			best = String(row["code"])
	return best


## Tetikleyen kesimin en sıcak bölgesi (baskının en yüksek olduğu); yoksa en büyük paylısı, o da yoksa "".
static func _trigger_region(bloc: Dictionary) -> String:
	if not str(bloc.get("hot_region", "")).is_empty():
		return bloc["hot_region"]
	var best := ""
	var best_share := 0
	var shares: Dictionary = bloc.get("exposure", {})
	var codes: Array = shares.keys()
	codes.sort()
	for code: String in codes:
		if int(shares[code]) > best_share:
			best_share = int(shares[code])
			best = code
	return best


## Etkilenen kesimler: `bloc` türünde tetikleyen kesim (ya da hepsi), diğer türlerde kesimlerin tümü.
static func _affected(state: GameState, template: Dictionary, trigger: String) -> Array:
	var out: Array = []
	if template["affected"]["type"] == "bloc" and template["affected"]["from"] == "trigger" and not trigger.is_empty():
		out.append(trigger)
		return out
	for key in PoliticsState.bloc_keys(state):
		out.append(key)
	return out


static func _cause_ids(state: GameState, ctx: PoliticsContext, template: Dictionary,
		trigger: String) -> PackedInt64Array:
	var pol := PoliticsState.data(state)
	var cap := int(ctx.politics.cadence["cause_cap"])
	var ids := PackedInt64Array()
	match template["cause"]:
		"bloc_react":
			var eval_data: Dictionary = pol["blocs"].get(trigger, {}).get("eval", {})
			for id: int in eval_data.get("reason_ids", []):
				ids.append(id)
		"investor_decline":
			ids = EventCauses.recent_declines(state, ctx, int(ctx.politics.events["declines_days"]), cap)
		"council_vote":
			var votes: Array = pol["council"]["votes"]
			for i in range(votes.size() - 1, -1, -1):
				if votes[i]["status"] != CouncilEngine.PENDING:
					for id: int in votes[i]["reason_ids"]:
						ids.append(id)
					break
		"media_story":
			var last_id := int(pol["media"]["last"].get("reason_id", 0))
			if last_id >= 1:
				ids.append(last_id)
	var out := PackedInt64Array()
	for id in ids:
		if id >= 1 and id <= state.reasons.last_id() and out.size() < cap:
			out.append(id)
	return out


# --- Yanıt ---

## Öğenin seçenek görünümü: {id, verb, label_key, available, locked_by, costs}. Kilitli seçenek gizlenmez.
static func option_views(ctx: PoliticsContext, item: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for option: Dictionary in ctx.politics.template(item["template"])["options"]:
		var authority := str(option["requires"].get("authority", ""))
		var locked: bool = not authority.is_empty() and not ctx.politics.is_granted(authority)
		out.append({"id": option["id"], "verb": option["verb"], "label_key": option["label_key"],
			"available": not locked, "locked_by": authority if locked else "", "costs": option["costs"].duplicate()})
	return out


## Öğeyi bul (canlı kayıt); yoksa boş sözlük.
static func item_by_id(state: GameState, item_id: int) -> Dictionary:
	for item: Dictionary in PoliticsState.data(state).get("events", {}).get("agenda", []):
		if int(item["id"]) == item_id:
			return item
	return {}


## Yanıt ön doğrulaması (durumu değiştirmez): {code, args}; code "" = geçerli. Kodlar sözleşme ret kodlarıdır
## (`invalid_target`, `invalid_value`, `precondition`).
static func check_response(state: GameState, ctx: PoliticsContext, item_id: int, option_id: String) -> Dictionary:
	var item := item_by_id(state, item_id)
	if item.is_empty():
		return {"code": &"invalid_target", "args": {"ref": "agenda.%d" % item_id}}
	if item["status"] != OPEN:
		return {"code": &"precondition", "args": {"why": "agenda.closed", "ref": "agenda.%d" % item_id}}
	for view in option_views(ctx, item):
		if view["id"] == option_id:
			if not view["available"]:
				return {"code": &"precondition", "args": {"why": "authority.locked", "authority": view["locked_by"]}}
			return {"code": &"", "args": {}}
	return {"code": &"invalid_value", "args": {"param": "option_id"}}


## Yanıtı uygular: seçenek etkileri zamana yayılmak üzere kuyruğa girer. `defer` yalnız not eder (öğe açık kalır,
## yükselme/süre dolumu sürer: görmezden gelmek bedelsiz değildir, PH-5).
static func respond(state: GameState, ctx: PoliticsContext, item_id: int, option_id: String) -> Dictionary:
	var check := check_response(state, ctx, item_id, option_id)
	if check["code"] != &"":
		return {"ok": false, "code": check["code"], "args": check["args"]}
	var item := item_by_id(state, item_id)
	var template := ctx.politics.template(item["template"])
	var option := {}
	for candidate: Dictionary in template["options"]:
		if candidate["id"] == option_id:
			option = candidate
	if option["verb"] == DEFER_VERB:
		item["deferred"] = int(item["deferred"]) + 1
		return {"ok": true, "code": &"", "args": {}, "scheduled": 0}
	item["status"] = RESOLVED
	item["chosen"] = option_id
	item["resolved_tick"] = state.tick
	var scheduled := _schedule(state, ctx, item, option["effects"], option_id)
	_close_event(state, ctx, item, option_id)
	return {"ok": true, "code": &"", "args": {}, "scheduled": scheduled}


static func _close_event(state: GameState, ctx: PoliticsContext, item: Dictionary, detail: String) -> void:
	SimEventLog.emit(state, AGENDA_RESOLVED, StringName("event.agenda.%s" % item["status"]),
		PackedStringArray(["agenda.%d" % int(item["id"])]), {"template": item["template"], "option": detail},
		PackedInt64Array([int(item["reason_id"])]), 0, StringName(ctx.politics.events["system_actor"]))
	PoliticsState.count(state, "events_emitted")


# --- Etkiler ---

## Etkileri kuyruğa alır (kapsam şimdi çözülür); eklenen sayıyı döner.
static func _schedule(state: GameState, ctx: PoliticsContext, item: Dictionary, effects: Array,
		option_id: String) -> int:
	var queue: Array = PoliticsState.data(state)["events"]["effects"]
	for effect: Dictionary in effects:
		var scope := _resolve_scope(state, ctx, item, effect)
		queue.append({
			"item_id": item["id"], "option_id": option_id, "target": effect["target"], "curve": effect["curve"],
			"magnitude": effect["magnitude"], "attribution": effect["attribution"],
			"start": state.tick + int(effect["delay_days"]), "duration": maxi(int(effect["duration_days"]), 1),
			"applied": 0, "blocs": scope["blocs"], "members": scope["members"], "topic": item["topic"],
			"region": item["region"],
		})
	return effects.size()


## Kapsam çözümü, salt okunur (yanıt önizlemesi ve komut doğrulaması `_schedule` ile AYNI çözümü kullanır).
static func scope_of(state: GameState, ctx: PoliticsContext, item: Dictionary, effect: Dictionary) -> Dictionary:
	return _resolve_scope(state, ctx, item, effect)


## Kapsam -> {blocs [anahtar], members [anahtar]}.
static func _resolve_scope(state: GameState, ctx: PoliticsContext, item: Dictionary, effect: Dictionary) -> Dictionary:
	var blocs: Array = []
	var members: Array = []
	match effect["scope"]:
		"trigger_bloc", "trigger_topic":
			if not str(item["bloc"]).is_empty():
				blocs.append(item["bloc"])
		"beneficiary_blocs":
			for key in PoliticsState.bloc_keys(state):
				if key != item["bloc"] and PoliticsState.data(state)["blocs"][key]["eval"]["reaction"] == "support":
					blocs.append(key)
		"all":
			blocs = PoliticsState.bloc_keys(state)
			members = ctx.politics.council["members"].duplicate()
		"district":
			pass
	return {"blocs": blocs, "members": members}


## Günlük: bekleyen etkiler (kümülatif eğri farkı), aşama/süre dolumu.
static func step_daily(state: GameState, ctx: PoliticsContext) -> void:
	_apply_effects(state, ctx)
	_advance_items(state, ctx)


@warning_ignore("integer_division")
static func _apply_effects(state: GameState, ctx: PoliticsContext) -> void:
	var events: Dictionary = PoliticsState.data(state)["events"]
	var queue: Array = events["effects"]
	if queue.is_empty():
		return
	var remaining: Array = []
	for effect: Dictionary in queue:
		if int(effect["start"]) > state.tick:
			remaining.append(effect)
			continue
		var step := state.tick - int(effect["start"]) + 1
		var done := step >= (1 if effect["curve"] == "step" else int(effect["duration"]))
		var cumulative := cumulative_amount(effect["curve"], int(effect["magnitude"]), step, int(effect["duration"]))
		var change := cumulative - int(effect["applied"])
		effect["applied"] = cumulative
		if change != 0:
			_apply_change(state, ctx, effect, change)
		if not done:
			remaining.append(effect)
	events["effects"] = remaining


## Eğrinin `step`inci günde ulaştığı kümülatif miktar (tamsayı): step = hepsi; linear = eşit dilim; decay = öne
## yüklü (1 - (1 - x/D)^2).
@warning_ignore("integer_division")
static func cumulative_amount(curve: String, magnitude: int, step: int, duration: int) -> int:
	if curve == "step" or step >= duration:
		return magnitude
	if curve == "linear":
		return magnitude * step / duration
	return magnitude * (2 * step * duration - step * step) / (duration * duration)


@warning_ignore("integer_division")
static func _apply_change(state: GameState, ctx: PoliticsContext, effect: Dictionary, change: int) -> void:
	var scaled: int = change * int(effect["attribution"]) / SCALE
	match effect["target"]:
		"bloc.grievance", "bloc.satisfaction":
			var book_name := "grievances" if effect["target"] == "bloc.grievance" else "satisfaction"
			for key: String in effect["blocs"]:
				var book: Dictionary = ActorStore.actor_ref(state, key)["state"][book_name]
				var topic: String = effect["topic"]
				if not topic.is_empty():
					book[topic] = clampi(int(book.get(topic, 0)) + scaled, 0, SCALE)
		"relation.trust":
			_apply_relation(state, ctx, effect, scaled)
		"investor.political_risk":
			var risk: Dictionary = PoliticsState.data(state)["risk"]["adjust"]
			var region: String = effect["region"]
			if not region.is_empty():
				risk[region] = clampi(int(risk.get(region, 0)) + scaled, -SCALE, SCALE)
		"media.tone":
			MediaEngine.shift_tone(state, ctx, effect["topic"], scaled)
		"council.friction":
			var council: Dictionary = PoliticsState.data(state)["council"]
			council["friction_adjust"] = clampi(int(council["friction_adjust"]) + scaled,
				-int(ctx.politics.council["friction_days"]), 3650)


## `relation.trust` hafıza kuralından geçer (characters-npc §4.2): işaret valence, büyüklük |etki|.
static func _apply_relation(state: GameState, ctx: PoliticsContext, effect: Dictionary, scaled: int) -> void:
	var player := ActorStore.protagonist_key(state, ctx.actors)
	if player.is_empty() or scaled == 0:
		return
	var topic: String = effect["topic"] if ctx.actors.topic_ids.has(effect["topic"]) else ctx.actors.topic_ids[0]
	var targets: Array = []
	targets.append_array(effect["blocs"])
	targets.append_array(effect["members"])
	for key: String in targets:
		ActorMemory.apply_event(state, ctx.actors, key, {"topic_id": topic, "valence": signi(scaled) * SCALE,
			"magnitude": mini(absi(scaled), SCALE), "attribution": SCALE, "attributed_to": player,
			"source_ref": "agenda.%d" % int(effect["item_id"])})


## Aşama ve süre dolumu: koşul sürerse aşama etkileri uygulanır; koşul bittiyse öğe kapanır (`lapsed`); süre
## dolarsa `expired` (varsayılan `defer`).
static func _advance_items(state: GameState, ctx: PoliticsContext) -> void:
	var events: Dictionary = PoliticsState.data(state)["events"]
	var sources := {}
	for item: Dictionary in events["agenda"]:
		if item["status"] != OPEN:
			continue
		var template := ctx.politics.template(item["template"])
		if state.tick >= int(item["deadline"]):
			item["status"] = EXPIRED
			item["resolved_tick"] = state.tick
			_close_event(state, ctx, item, "")
			continue
		var stages: Array = template["stages"]
		var index := int(item["stage"])
		if index >= stages.size() or state.tick - int(item["opened_tick"]) < int(stages[index]["after_days"]):
			continue
		if sources.is_empty():
			sources = EventSources.compute(state, ctx, EconomyQuery.region_stats(state, ctx.economy))
		var stage: Dictionary = stages[index]
		var cond: Dictionary = stage["if"]
		if not cond.is_empty() and not compare(int(sources[cond["src"]]), cond["op"],
				EventSources.threshold_value(ctx, cond["value"])):
			item["status"] = LAPSED
			item["resolved_tick"] = state.tick
			_close_event(state, ctx, item, "")
			continue
		item["stage"] = index + 1
		_schedule(state, ctx, item, stage["effects"], "stage")
	_prune(events)


## Kapanmış öğelerden en eski olanlar budanır (bekleyen ve açık öğeler kalır); sınır 32.
static func _prune(events: Dictionary) -> void:
	var agenda: Array = events["agenda"]
	var closed := 0
	for item: Dictionary in agenda:
		closed += 0 if item["status"] == OPEN else 1
	var drop := closed - 32
	if drop <= 0:
		return
	var kept: Array = []
	for item: Dictionary in agenda:
		if item["status"] != OPEN and drop > 0:
			drop -= 1
			continue
		kept.append(item)
	events["agenda"] = kept
