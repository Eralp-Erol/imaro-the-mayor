class_name ActorMemory
extends RefCounted
## İlişki ve hafıza güncellemesi (T-016 ölçüt 4, characters-npc §4, SIM-05/SIM-11/SIM-12). Olay/karar bir aktörü
## etkilediğinde `apply_event` güven, kırgınlık ve hafızayı DETERMİNİSTİK günceller (tamsayı permille; sıfıra doğru
## kesme); `advance` tick başına bir kez vadesi gelen dedikoduyu uygular ve `cadence.maintenance_days` aralığında
## hafızayı budar.
##
## Kural özeti (impact 0..1000 = m * rho * alpha * fam; rho = aktörün konu duyarlılığı, fam = 0.5 + 0.5*tanıdıklık):
##   v >= 0: güven artar (k_gain, kalan boşluğa oranlı), kırgınlık `scar_floor`a kadar azalır (k_forgive; yukarı
##           yuvarlanır, yani telafi tamsayı kesmesiyle tabanın hemen üstünde takılmaz)
##   v <  0: güven düşer (k_loss = loss_aversion * k_gain), kırgınlık artar (k_resent); tepe kırgınlıktan
##           `scar_floor = max(scar_floor, scar_frac * tepe)` (yara izi: telafi bunun altına indiremez)
## Çürüme (yarı ömürden türeyen tamsayı tutma oranı): güven -> trust0, kırgınlık -> scar_floor (daha yavaş). TEMBEL
## uygulanır: değerler `as_of`ten bu yana geçen güne göre tek hamlede hesaplanır (tekrarlı kesme hatası birikmez);
## olay/dedikodu önce kaydı `rebase` eder.
## Hafıza: aktör başına en çok K_mem kayıt; aşılınca aynı konulu en düşük ağırlıklı iki kayıt birleşir (ağırlıklı
## ortalama; eşitlikte düşük indeks), ortak konusu yoksa en düşük ağırlıklı kayıt unutulur (`memory_dropped`).
## Dedikodu: tek sıçrama (zincir yok): olayı yaşayan aktörün bağlılık ağındaki komşulara `spill_delay_days` sonra,
## `spill_frac * kenar_ağırlığı * dTrust` kadar güven değişimi uygulanır. Ek yol yoktur: olay etkisi buradan geçer.

const SCALE := SimContract.FIXED_SCALE
const SCALE3 := SCALE * SCALE * SCALE
const EVENT_KEYS: Array[String] = [
	"topic_id", "valence", "magnitude", "attribution", "attributed_to", "source_ref", "decay_class",
]
const DEFAULT_DECAY_CLASS := "memory_short"


## Olayı `actor_key` aktörüne uygular. `event`: topic_id, valence (-1000..1000), magnitude (0..1000), attribution
## (0..1000, varsayılan 1000), attributed_to (sorumlu aktör; boşsa yalnız hafıza), source_ref (metin), decay_class
## (`memory_short` | `memory_long`). Dönüş: {ok:false, error} (durum DEĞİŞMEZ) ya da {ok:true, impact, trust_delta,
## resentment_delta, merged}.
@warning_ignore("integer_division")
static func apply_event(state: GameState, config: ActorConfig, actor_key: String, event: Dictionary) -> Dictionary:
	var problem := _event_problem(state, config, actor_key, event)
	if not problem.is_empty():
		return {"ok": false, "error": problem}
	var actor := ActorStore.actor_ref(state, actor_key)
	var target := str(event.get("attributed_to", ""))
	var result := {"ok": true, "impact": 0, "trust_delta": 0, "resentment_delta": 0}
	if not target.is_empty():
		var rel := ActorStore.ensure_relation(state, config, actor_key, target)
		ActorStore.rebase(rel, config, state.tick)
		var rho := int(actor["salience"].get(event["topic_id"], 0))
		var fam := SCALE / 2 + int(rel["familiarity"]) / 2
		var impact := int(event["magnitude"]) * rho * int(event.get("attribution", SCALE)) * fam / SCALE3
		result["impact"] = impact
		var before_trust := int(rel["trust"])
		var before_resentment := int(rel["resentment"])
		_shift_relation(rel, config, impact, int(event["valence"]))
		rel["familiarity"] = mini(SCALE, int(rel["familiarity"]) + int(config.memory["familiarity_gain"]))
		result["trust_delta"] = int(rel["trust"]) - before_trust
		result["resentment_delta"] = int(rel["resentment"]) - before_resentment
		_queue_spill(state, config, actor_key, target, int(result["trust_delta"]))
	result["merged"] = _push_memory(state, config, actor, event)
	return result


## Konu hafızası: Σ(ağırlık * değer * büyüklük) / Σ ağırlık, -1000..1000 (hafıza yoksa 0).
@warning_ignore("integer_division")
static func topic_memory(state: GameState, config: ActorConfig, actor_key: String, topic_id: String) -> int:
	var num := 0
	var den := 0
	for entry: Dictionary in ActorStore.actor_ref(state, actor_key).get("memory", []):
		if entry["topic_id"] != topic_id:
			continue
		var weight := weight_ppm(config, entry, state.tick)
		num += weight * (int(entry["valence"]) * int(entry["magnitude"]) / SCALE)
		den += weight
	return 0 if den == 0 else num / den


## Kaydın şimdiki ağırlığı (ppm): 2^(-yaş / yarı_ömür[decay_class]).
static func weight_ppm(config: ActorConfig, entry: Dictionary, tick: int) -> int:
	return ActorMath.pow_ppm(config.retention_ppm(entry["decay_class"]), maxi(tick - int(entry["tick"]), 0))


## Tick başına sistem adımı (ActorSystem.on_daily): vadesi gelen dedikodu, sonra aralıkta hafıza budama.
static func advance(state: GameState, config: ActorConfig) -> void:
	if not ActorStore.is_initialized(state):
		return
	_apply_due_spill(state, config)
	if state.tick > 0 and state.tick % config.maintenance_days == 0:
		_prune_all(state, config)


# --- Güncelleme kuralı ---

@warning_ignore("integer_division")
static func _shift_relation(rel: Dictionary, config: ActorConfig, impact: int, valence: int) -> void:
	var mem := config.memory
	var trust := int(rel["trust"])
	var resentment := int(rel["resentment"])
	if valence >= 0:
		trust += int(mem["k_gain"]) * impact * (SCALE - trust) * valence / SCALE3
		var forgiven := int(mem["k_forgive"]) * impact * (resentment - int(rel["scar_floor"])) * valence
		resentment = maxi(resentment - ActorMath.ceil_div(forgiven, SCALE3), int(rel["scar_floor"]))
	else:
		var loss := -valence
		trust -= int(mem["k_loss"]) * impact * (SCALE + trust) * loss / SCALE3
		resentment += int(mem["k_resent"]) * impact * (SCALE - resentment) * loss / SCALE3
		rel["peak_resentment"] = maxi(int(rel["peak_resentment"]), resentment)
		rel["scar_floor"] = maxi(int(rel["scar_floor"]), int(mem["scar_frac"]) * int(rel["peak_resentment"]) / SCALE)
	rel["trust"] = ActorMath.clamp_permille(trust)
	rel["resentment"] = clampi(resentment, 0, SCALE)


# --- Hafıza ---

static func _push_memory(state: GameState, config: ActorConfig, actor: Dictionary, event: Dictionary) -> bool:
	var memory: Array = actor["memory"]
	memory.append({
		"tick": state.tick, "topic_id": event["topic_id"], "valence": event["valence"],
		"magnitude": event["magnitude"], "source_ref": str(event.get("source_ref", "")),
		"attributed_to": str(event.get("attributed_to", "")),
		"decay_class": str(event.get("decay_class", DEFAULT_DECAY_CLASS)), "count": 1,
	})
	var merged := false
	while memory.size() > int(config.memory["K_mem"]):
		merged = _shrink(state, config, actor) or merged
	return merged


## Bir kayıt azaltır; birleştirdiyse true, unuttuysa false.
static func _shrink(state: GameState, config: ActorConfig, actor: Dictionary) -> bool:
	var memory: Array = actor["memory"]
	var weights: Array[int] = []
	for entry: Dictionary in memory:
		weights.append(weight_ppm(config, entry, state.tick))
	var pair := _lowest_pair(memory, weights)
	if pair.is_empty():
		var lowest := 0
		for i in memory.size():
			if weights[i] < weights[lowest]:
				lowest = i
		memory.remove_at(lowest)
		actor["memory_dropped"] = int(actor["memory_dropped"]) + 1
		return false
	var first: int = pair[0]
	var second: int = pair[1]
	memory[first] = _merged_entry(memory[first], memory[second], weights[first], weights[second])
	memory.remove_at(second)
	return true


## Ortak konulu kayıtlar arasında en düşük ağırlıklı kaydı ve onun en düşük ağırlıklı eşini bulur: [düşük indeks,
## yüksek indeks]. Ortak konu yoksa []. Eşitlikte düşük indeks.
static func _lowest_pair(memory: Array, weights: Array[int]) -> Array:
	var best := -1
	for i in memory.size():
		if _partner_of(memory, weights, i) < 0:
			continue
		if best < 0 or weights[i] < weights[best]:
			best = i
	if best < 0:
		return []
	var partner := _partner_of(memory, weights, best)
	return [mini(best, partner), maxi(best, partner)]


static func _partner_of(memory: Array, weights: Array[int], index: int) -> int:
	var best := -1
	for j in memory.size():
		if j == index or memory[j]["topic_id"] != memory[index]["topic_id"]:
			continue
		if best < 0 or weights[j] < weights[best]:
			best = j
	return best


## İki kaydın ağırlıklı ortalaması (değer, büyüklük, tick); kaynak/atıf/sınıf ağırlığı yüksek olandan.
@warning_ignore("integer_division")
static func _merged_entry(a: Dictionary, b: Dictionary, weight_a: int, weight_b: int) -> Dictionary:
	var total := weight_a + weight_b
	var keeper := a if weight_a >= weight_b else b
	var out := keeper.duplicate()
	if total == 0:
		total = 2
		weight_a = 1
		weight_b = 1
	for field_name in ["valence", "magnitude", "tick"]:
		out[field_name] = (int(a[field_name]) * weight_a + int(b[field_name]) * weight_b) / total
	out["count"] = int(a["count"]) + int(b["count"])
	return out


# --- Dedikodu ---

@warning_ignore("integer_division")
static func _queue_spill(state: GameState, config: ActorConfig, actor_key: String, target: String,
		trust_delta: int) -> void:
	if trust_delta == 0 or int(config.memory["spill_frac"]) == 0:
		return
	var actors: Dictionary = ActorStore.data_ref(state)["actors"]
	var mine: Array = actors[actor_key]["affiliations"]
	var queue: Array = ActorStore.data_ref(state)["spill_queue"]
	for other_key in ActorStore.keys(state):
		if other_key == actor_key or other_key == target:
			continue
		var other: Dictionary = actors[other_key]
		var shared := 0
		for tie: Variant in other["affiliations"]:
			shared += 1 if mine.has(tie) else 0
		if shared == 0 or other["campaign_id"] != actors[actor_key]["campaign_id"]:
			continue
		var edge := mini(SCALE, shared * int(config.memory["edge_weight_per_shared"]))
		var amount := int(config.memory["spill_frac"]) * edge * trust_delta / (SCALE * SCALE)
		if amount != 0:
			queue.append({"due_tick": state.tick + int(config.memory["spill_delay_days"]), "to": other_key,
				"toward": target, "trust": amount})
	_trim_queue(state, config)


static func _trim_queue(state: GameState, config: ActorConfig) -> void:
	var data := ActorStore.data_ref(state)
	var queue: Array = data["spill_queue"]
	while queue.size() > int(config.memory["spill_queue_max"]):
		queue.pop_front()
		data["spill_dropped"] = int(data["spill_dropped"]) + 1


static func _apply_due_spill(state: GameState, config: ActorConfig) -> void:
	var queue: Array = ActorStore.data_ref(state)["spill_queue"]
	var waiting: Array = []
	for entry: Dictionary in queue:
		if int(entry["due_tick"]) > state.tick:
			waiting.append(entry)
			continue
		var rel := ActorStore.ensure_relation(state, config, entry["to"], entry["toward"])
		ActorStore.rebase(rel, config, state.tick)
		rel["trust"] = ActorMath.clamp_permille(int(rel["trust"]) + int(entry["trust"]))
	ActorStore.data_ref(state)["spill_queue"] = waiting


# --- Bakım ---

## Ağırlığı `memory_min_weight` (permille) altına düşen hafızalar budanır (bellek sınırlı kalır).
@warning_ignore("integer_division")
static func _prune_all(state: GameState, config: ActorConfig) -> void:
	var min_weight := int(config.memory["memory_min_weight"]) * (ActorMath.PPM / SCALE)
	for key in ActorStore.keys(state):
		var actor := ActorStore.actor_ref(state, key)
		var kept: Array = []
		for entry: Dictionary in actor["memory"]:
			if weight_ppm(config, entry, state.tick) >= min_weight:
				kept.append(entry)
		actor["memory"] = kept


# --- Doğrulama ---

static func _event_problem(state: GameState, config: ActorConfig, actor_key: String, event: Dictionary) -> String:
	if not ActorStore.is_initialized(state):
		return "aktör sistemi başlatılmadı"
	var actor := ActorStore.actor_ref(state, actor_key)
	if actor.is_empty() or config.kind_spec(actor["kind"]).get("bare", false):
		return "olay yalnız kimlikten fazlasını taşıyan kadro aktörüne uygulanır: '%s'" % actor_key
	for given: Variant in event:
		if not EVENT_KEYS.has(str(given)):
			return "olayda bilinmeyen alan: '%s'" % str(given)
	if not config.topic_ids.has(event.get("topic_id", null)):
		return "bilinmeyen konu: '%s'" % str(event.get("topic_id", null))
	if not ActorSchema.in_range(event.get("valence", null), -SCALE, SCALE):
		return "valence -1000..1000 tamsayı olmalı"
	if not ActorSchema.in_range(event.get("magnitude", null), 0, SCALE):
		return "magnitude 0..1000 tamsayı olmalı"
	if not ActorSchema.in_range(event.get("attribution", SCALE), 0, SCALE):
		return "attribution 0..1000 tamsayı olmalı"
	var decay_class: Variant = event.get("decay_class", DEFAULT_DECAY_CLASS)
	if typeof(decay_class) != TYPE_STRING or not str(decay_class).begins_with("memory_") \
			or not config.is_half_life_class(decay_class):
		return "decay_class memory_short veya memory_long olmalı"
	return _target_problem(state, actor, str(event.get("attributed_to", "")))


static func _target_problem(state: GameState, actor: Dictionary, target: String) -> String:
	if target.is_empty():
		return ""
	var other := ActorStore.actor_ref(state, target)
	if other.is_empty() or target == actor["key"]:
		return "attributed_to kadroda olmayan ya da kendisi olan aktör: '%s'" % target
	if other["campaign_id"] != actor["campaign_id"]:
		return "kampanya sınırı aşılamaz (CAN-09): %s -> %s" % [actor["key"], target]
	return ""
