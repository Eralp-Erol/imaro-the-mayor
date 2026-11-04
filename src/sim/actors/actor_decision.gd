class_name ActorDecision
extends RefCounted
## Tek karar puanlama çatısı (T-016 ölçüt 1, characters-npc §6.1-§6.2, SIM-05/SIM-12). Her aktör türü AYNI
## fonksiyondan geçer: faktörler (1000 ölçekli tamsayı) + tablo (veri) -> skor, eşik, sonuç ve `ReasonLog` kaydı.
##
## Puanlama (sözleşme `ReasonRecord` v1.0 doğrusal toplamına KAYIPSIZ oturur):
##   w_i'   = w_i * (1 + mod[i,özellik] * (özellik - 500) / 500)    özellik kaydırması (tamsayı, 0'a kırpılır)
##   w_i''  = en büyük artık yöntemiyle Σ|w''| = 1000 (gürültü hariç); işaret w_i'nin işaretidir
##   eps    = noise_amp * volatility * çekiliş / 10^6               `reason.factor.noise` (ağırlık 1000) faktörü
##   skor   = Σ trunc(value * w'' / 1000) + eps ;  eşik = theta - (histerez, önceki karar olumluysa)
##   sonuç  = skor >= eşik ? positive : negative                    (ReasonLog da aynısını hesaplar)
## Spec §6.1'deki normalize S ile tek fark: tamsayı kesme (en çok faktör sayısı kadar permille) — kayıt değişmezi
## (`score == Σ trunc(value*weight/1000)`) kesin tutar; sonuç kayıtlı tamsayı skordan türer, karar ile kayıt ayrışamaz.
## Karar yalnız gerekçe YAZILABİLİRSE uygulanır (SIM-12): `evaluate` kayıt başarısızsa `ok=false` döner.
## Gürültü çekilişi (tick, aktör, karar) anahtarlıdır: çağrı sırasından bağımsız, başka karar kayıtları kaydırmaz.

const STREAM := &"actors"
const SCALE := SimContract.FIXED_SCALE
const NEUTRAL_TRAIT := 500
const FACTOR_PREFIX := "reason.factor."
const NOISE_FACTOR := &"reason.factor.noise"
const CODE_AT_OR_ABOVE := &"score_at_or_above_threshold"
const CODE_BELOW := &"score_below_threshold"
const DEFAULT_NOISE_TRAIT := "volatility"


## Saf karar. `factors`: {ad: int | {value, source_ref?, is_estimate?}} (değer -1000..1000; tablodaki TÜM faktörler,
## fazlası yok). `context`: traits {özellik: 0..1000}, draw (-1000..1000, varsayılan 0), previous_positive (bool),
## theta (tabloyu geçersiz kılar; basamaklı tablolarda zorunlu), noise_trait.
## Dönüş: {ok:false, error} ya da {ok:true, outcome, score, threshold, margin, noise, hysteresis_applied,
## factors:[{name,value,weight,is_estimate,source_ref}] (ReasonLog.record'a hazır), code}.
static func decide(factors: Dictionary, table: Dictionary, context: Dictionary = {}) -> Dictionary:
	var problem := _input_problem(factors, table, context)
	if not problem.is_empty():
		return {"ok": false, "error": problem}
	var traits: Dictionary = context.get("traits", {})
	var weights := normalized_weights(table, traits)
	var total := 0
	for w in weights:
		total += absi(w)
	if total != SCALE:
		return {"ok": false, "error": "tüm faktör ağırlıkları özellik kaydırmasıyla sıfıra kırpıldı"}
	var recorded: Array = []
	var score := 0
	for i in table["factors"].size():
		var name: String = table["factors"][i]["name"]
		var entry := _input_of(factors[name])
		recorded.append({
			"name": StringName(FACTOR_PREFIX + name), "value": entry["value"], "weight": weights[i],
			"is_estimate": entry["is_estimate"], "source_ref": StringName(entry["source_ref"]),
		})
		score += SimContract.contribution(entry["value"], weights[i])
	var noise := _noise_of(table, traits, context)
	if int(table["noise_amp"]) > 0:
		recorded.append({"name": NOISE_FACTOR, "value": noise, "weight": SCALE, "is_estimate": false,
			"source_ref": &""})
		score += noise
	var applied: bool = context.get("previous_positive", false) and int(table["hysteresis"]) > 0
	var threshold: int = int(context.get("theta", table["theta"])) - (int(table["hysteresis"]) if applied else 0)
	var positive := score >= threshold
	return {
		"ok": true, "outcome": ReasonLog.OUTCOME_POSITIVE if positive else ReasonLog.OUTCOME_NEGATIVE,
		"score": score, "threshold": threshold, "margin": score - threshold, "noise": noise,
		"hysteresis_applied": applied, "factors": recorded, "code": CODE_AT_OR_ABOVE if positive else CODE_BELOW,
	}


## Özellik kaydırmalı, Σ|w| = 1000 olan imzalı ağırlıklar (tablo faktör sırasıyla). Özellik yoksa nötr (500).
static func normalized_weights(table: Dictionary, traits: Dictionary) -> Array[int]:
	var raw: Array[int] = []
	var signs: Array[int] = []
	for f: Dictionary in table["factors"]:
		var shift: int = SCALE * NEUTRAL_TRAIT
		for trait_id: String in f["trait_mod"]:
			shift += int(f["trait_mod"][trait_id]) * (int(traits.get(trait_id, NEUTRAL_TRAIT)) - NEUTRAL_TRAIT)
		raw.append(absi(int(f["weight"])) * maxi(shift, 0))
		signs.append(signi(int(f["weight"])))
	var shares := ActorMath.apportion(raw, SCALE)
	var out: Array[int] = []
	for i in shares.size():
		out.append(shares[i] * signs[i])
	return out


## (tick, aktör, karar) anahtarlı çekiliş, -1000..1000. `rng.actors` akışının tohumundan türer (durumda saklıdır);
## akışı TÜKETMEZ: karar sayısı/sırası değişse de bir kararın gürültüsü değişmez.
static func noise_draw(state: GameState, actor_key: String, decision_id: String) -> int:
	var stream_seed := RngStreams.derive_seed(state.world_seed, STREAM)
	var key := StringName("%d|%s|%s" % [state.tick, actor_key, decision_id])
	return RngStreams.derive_seed(stream_seed, key) % (2 * SCALE + 1) - SCALE


@warning_ignore("integer_division")
static func _noise_of(table: Dictionary, traits: Dictionary, context: Dictionary) -> int:
	var amp := int(table["noise_amp"])
	if amp <= 0:
		return 0
	var volatility := int(traits.get(context.get("noise_trait", DEFAULT_NOISE_TRAIT), NEUTRAL_TRAIT))
	return amp * volatility * int(context.get("draw", 0)) / (SCALE * SCALE)


## {value, source_ref, is_estimate} ya da kabul edilmeyen girdide {}.
static func _input_of(raw: Variant) -> Dictionary:
	var value: Variant = raw
	var source_ref := ""
	var estimate := false
	if raw is Dictionary:
		value = raw.get("value", null)
		source_ref = str(raw.get("source_ref", ""))
		estimate = raw.get("is_estimate", false) == true
	if typeof(value) != TYPE_INT or value < -SCALE or value > SCALE:
		return {}
	return {"value": value, "source_ref": source_ref, "is_estimate": estimate}


static func _input_problem(factors: Dictionary, table: Dictionary, context: Dictionary) -> String:
	var defs: Array = table.get("factors", [])
	var weighted := 0
	for f: Dictionary in defs:
		weighted += 1 if int(f["weight"]) != 0 else 0
	if weighted < 2:
		return "karar tablosunda en az 2 ağırlıklı faktör gerekir (tek faktörlü karar gerekçe sayılmaz)"
	if not table.get("tiers", []).is_empty() and not context.has("theta"):
		return "basamaklı tablo için bağlamda 'theta' (basamak eşiği) gerekir"
	var draw: Variant = context.get("draw", 0)
	if typeof(draw) != TYPE_INT or draw < -SCALE or draw > SCALE:
		return "çekiliş -1000..1000 tamsayı olmalı (%s)" % str(draw)
	var wanted: Array[String] = []
	for f: Dictionary in defs:
		wanted.append(f["name"])
		if not factors.has(f["name"]):
			return "faktör eksik: '%s'" % f["name"]
		if _input_of(factors[f["name"]]).is_empty():
			return "faktör '%s' -1000..1000 tamsayı olmalı (%s)" % [f["name"], str(factors[f["name"]])]
	for given: Variant in factors:
		if not wanted.has(str(given)):
			return "tabloda olmayan faktör: '%s'" % str(given)
	return ""


## Karar ver + `ReasonLog`a yaz (SIM-12). Gerekçe yazılamazsa karar UYGULANMAZ (`ok=false`, geçmiş değişmez).
## `decision_id`: tablo kimliği (`council.vote`); aktörün türü tabloyla eşleşmeli. Aktörün özellikleri, anahtarlı
## gürültü çekilişi ve karar geçmişi (histerez) durumdan okunur. Basamaklı tabloda her basamak AYRI kayıt yazar
## (`decision.<id>.<basamak>`, alt basamak olumsuz çıkana kadar; basamaklar `parent_ids` ile bağlanır).
## `subjects` (`parcel.12`, `vote.1`...) ve `parent_ids` (daha önceki gerekçeler) çağıranın nedensellik bağıdır.
## Dönüş: {ok, error, outcome (ilk kaydın), reached_tier (olumlu en yüksek basamak ya da ""), records:[{reason_id,
## decision_key, tier, outcome, score, threshold, margin, noise}]}.
static func evaluate(state: GameState, config: ActorConfig, actor_key: String, decision_id: String, factors: Dictionary,
		subjects: PackedStringArray = PackedStringArray(),
		parent_ids: PackedInt64Array = PackedInt64Array()) -> Dictionary:
	var table := config.table(decision_id)
	var problem := _evaluate_problem(state, config, table, actor_key, subjects, parent_ids)
	if not problem.is_empty():
		return {"ok": false, "error": problem, "records": []}
	var traits: Dictionary = ActorStore.actor_ref(state, actor_key)["traits"]
	var draw := noise_draw(state, actor_key, decision_id)
	var tiers: Array = table["tiers"]
	var steps: Array = tiers if not tiers.is_empty() else [{"id": "", "theta": table["theta"]}]
	var records: Array = []
	var parents := parent_ids.duplicate()
	for step: Dictionary in steps:
		var tier: String = step["id"]
		var history_id := decision_id if tier.is_empty() else "%s.%s" % [decision_id, tier]
		var previous := ActorStore.recent_outcomes(state, actor_key, history_id)
		var result := decide(factors, table, {
			"traits": traits, "draw": draw, "theta": step["theta"], "noise_trait": config.noise_trait,
			"previous_positive": not previous.is_empty() and previous[previous.size() - 1] == 1,
		})
		if not result["ok"]:
			return {"ok": false, "error": result["error"], "records": records}
		var decision_key := StringName("decision." + history_id)
		var reason_id := state.record_reason(StringName(actor_key), decision_key, result["factors"],
			result["threshold"], result["code"], subjects, parents)
		if reason_id < 0:
			return {"ok": false, "error": "gerekçe kaydedilemedi: karar uygulanmaz", "records": records}
		var positive: bool = result["outcome"] == ReasonLog.OUTCOME_POSITIVE
		ActorStore.push_outcome(state, config, actor_key, history_id, positive)
		records.append({"reason_id": reason_id, "decision_key": decision_key, "tier": tier,
			"outcome": result["outcome"], "score": result["score"], "threshold": result["threshold"],
			"margin": result["margin"], "noise": result["noise"]})
		if not positive:
			break
		parents = parent_ids.duplicate()
		parents.append(reason_id)
	return {"ok": true, "error": "", "outcome": records[0]["outcome"], "reached_tier": _reached_tier(records),
		"records": records}


static func _reached_tier(records: Array) -> String:
	var reached := ""
	for rec: Dictionary in records:
		if rec["outcome"] == ReasonLog.OUTCOME_POSITIVE:
			reached = rec["tier"]
	return reached


static func _evaluate_problem(state: GameState, config: ActorConfig, table: Dictionary, actor_key: String,
		subjects: PackedStringArray, parent_ids: PackedInt64Array) -> String:
	if table.is_empty():
		return "bilinmeyen karar tablosu"
	var actor := ActorStore.actor_ref(state, actor_key)
	if actor.is_empty():
		return "bilinmeyen aktör: '%s'" % actor_key
	if actor["kind"] != table["kind"] or not config.kind_spec(actor["kind"]).get("decides", false):
		return "aktör '%s' (%s) bu kararı veremez (%s)" % [actor_key, actor["kind"], table["kind"]]
	var parsed := SimContract.parse_ref(StringName(actor_key))
	if int(parsed["id"]) < 1:
		return "aktör anahtarı karar kaydı için geçersiz: '%s'" % actor_key
	for subject in subjects:
		if int(SimContract.parse_ref(StringName(subject))["id"]) < 1:
			return "subjects '<tür>.<n>' biçiminde olmalı: '%s'" % subject
	for parent in parent_ids:
		if parent < 1 or parent > state.reasons.last_id():
			return "parent_ids daha önceki gerekçelere işaret etmeli: %d" % parent
	return ""

