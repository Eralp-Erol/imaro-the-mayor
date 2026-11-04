class_name ActorStore
extends RefCounted
## Aktör sisteminin KALICI durumu (T-016 ölçüt 3): `state.systems["actors"]`. Sistem nesnesi durum tutmaz; her şey
## burada, dolayısıyla kayda ve durum hash'ine otomatik girer (GameState.to_dict/state_hash). Yalnız tamsayı,
## metin, dizi ve sözlük içerir (kayan nokta yok). Yineleme her yerde SIRALI anahtarlarla yapılır (TEK-01).
##
## Biçim:
##   schema            1
##   config_digest     başlatıldığı yapılandırmanın özeti (bilgi; `config_matches` ile karşılaştırılır)
##   actors            {aktör anahtarı: aktör}; aktör = characters-npc §3.1 + relations + memory (aşağıda)
##   spill_queue       bekleyen dedikodu: [{due_tick, to, toward, trust}] (tek sıçrama, zincir yok)
##   spill_dropped     kapasite aşımında atılan dedikodu sayısı
##   decisions         {"aktör|karar": {"recent": [+1/-1, ...]}}: histerez ve emsal (en çok n_prec)
## Aktör: {key, kind, campaign_id, name_key, lod, traits, stance, salience, resources, affiliations, state,
##   relations: {hedef: {trust, trust0, resentment, obligation, familiarity, scar_floor, peak_resentment, as_of}};
##     trust/resentment `as_of` tick'indeki değerlerdir; çürüme TEMBEL uygulanır (`decayed`/`rebase`): güven trust0'a,
##     kırgınlık scar_floor'a yarı ömürle yaklaşır. Doğrudan alan okumak yerine `relation(...)` kullanın.
##   memory: [{tick, topic_id, valence, magnitude, source_ref, attributed_to, decay_class, count}],
##   memory_dropped}.

const SYSTEM := &"actors"
const SYSTEM_KEY := "actors"
const SCHEMA := 1
const RELATION_KEYS: Array[String] = [
	"trust", "trust0", "resentment", "obligation", "familiarity", "scar_floor", "peak_resentment", "as_of",
]
const MEMORY_KEYS: Array[String] = [
	"tick", "topic_id", "valence", "magnitude", "source_ref", "attributed_to", "decay_class", "count",
]


## Aktör durumunu kadrodan kurar (idempotent: kuruluysa dokunmaz). Geçersiz yapılandırmada push_error + false.
## `rng.actors` akışını durumda oluşturur (tohum kayıtla taşınır).
static func ensure_initialized(state: GameState, config: ActorConfig) -> bool:
	if is_initialized(state):
		return true
	if config == null or not config.is_valid():
		push_error("ActorStore: invalid ActorConfig (%s)" % ("null" if config == null else config.error))
		return false
	var actors := {}
	for template in config.roster:
		actors[template["key"]] = template.duplicate(true)
	for entry in config.relation_overrides:
		actors[entry["from"]]["relations"][entry["to"]] = make_relation(config.relation_default, entry, state.tick)
	state.systems[SYSTEM_KEY] = {
		"schema": SCHEMA, "config_digest": config.digest, "actors": actors, "spill_queue": [], "spill_dropped": 0,
		"decisions": {},
	}
	state.rng.stream(SYSTEM)
	return true


static func is_initialized(state: GameState) -> bool:
	var data: Variant = state.systems.get(SYSTEM_KEY, null)
	return data is Dictionary and data.get("schema", null) == SCHEMA


## Durum, bu yapılandırmayla mı başlatıldı? (Veri sonradan ayarlandıysa false: bilgi amaçlı, yükleme engellenmez.)
static func config_matches(state: GameState, config: ActorConfig) -> bool:
	return is_initialized(state) and state.systems[SYSTEM_KEY]["config_digest"] == config.digest


## İlişki kaydı: `base` (varsayılan) üstüne `override` (yalnız verilen alanlar). trust aynı zamanda çürüme hedefidir.
static func make_relation(base: Dictionary, override: Dictionary, as_of: int = 0) -> Dictionary:
	var merged := base.duplicate()
	for field_name: String in ["trust", "resentment", "obligation", "familiarity", "scar_floor"]:
		if override.has(field_name):
			merged[field_name] = override[field_name]
	return {
		"trust": merged["trust"], "trust0": merged["trust"], "resentment": merged["resentment"],
		"obligation": merged["obligation"], "familiarity": merged["familiarity"], "scar_floor": merged["scar_floor"],
		"peak_resentment": merged["resentment"], "as_of": as_of,
	}


## Sıralı aktör anahtarları (boş: kurulu değil).
static func keys(state: GameState) -> Array[String]:
	var out: Array[String] = []
	if not is_initialized(state):
		return out
	for key: String in state.systems[SYSTEM_KEY]["actors"]:
		out.append(key)
	out.sort()
	return out


static func has_actor(state: GameState, key: String) -> bool:
	return is_initialized(state) and (state.systems[SYSTEM_KEY]["actors"] as Dictionary).has(key)


## Aktörün DEĞER kopyası; yoksa boş sözlük.
static func actor(state: GameState, key: String) -> Dictionary:
	return actor_ref(state, key).duplicate(true)


## Aktörün CANLI kaydı (yazma yolu: yalnız ActorMemory/ActorDecision kullanır; dışarıya sızdırmayın).
static func actor_ref(state: GameState, key: String) -> Dictionary:
	if not is_initialized(state):
		return {}
	return state.systems[SYSTEM_KEY]["actors"].get(key, {})


## Canlı sistem verisi (yazma yolu; bkz. actor_ref).
static func data_ref(state: GameState) -> Dictionary:
	return state.systems.get(SYSTEM_KEY, {})


## `from` aktörünün `to` ilişkisinin DEĞER kopyası, çürüme `state.tick`e uygulanmış; yoksa `config.relation_default`
## (durum değişmez).
static func relation(state: GameState, config: ActorConfig, from_key: String, to_key: String) -> Dictionary:
	var rel: Variant = actor_ref(state, from_key).get("relations", {}).get(to_key, null)
	if not (rel is Dictionary):
		return make_relation(config.relation_default, {}, state.tick)
	var copy: Dictionary = rel.duplicate()
	rebase(copy, config, state.tick)
	return copy


## İlişkiyi (yoksa varsayılandan) oluşturup CANLI kaydı döndürür (`as_of` = şimdiki tick, değerler güncel DEĞİLSE
## çağıran `rebase` etmelidir).
static func ensure_relation(state: GameState, config: ActorConfig, from_key: String, to_key: String) -> Dictionary:
	var relations: Dictionary = actor_ref(state, from_key)["relations"]
	if not relations.has(to_key):
		relations[to_key] = make_relation(config.relation_default, {}, state.tick)
	return relations[to_key]


## Güven ve kırgınlığın `tick`teki değerleri: güven trust0'a, kırgınlık scar_floor'a üstel yaklaşır (tutma oranı
## yarı ömürden; tek kesme => hedefe tam varır, aşmaz).
static func decayed(rel: Dictionary, config: ActorConfig, tick: int) -> Dictionary:
	var age := maxi(tick - int(rel["as_of"]), 0)
	var trust_factor := ActorMath.pow_ppm(config.retention_ppm("trust"), age)
	var resentment_factor := ActorMath.pow_ppm(config.retention_ppm("resentment"), age)
	return {
		"trust": ActorMath.decay_toward(int(rel["trust"]), int(rel["trust0"]), trust_factor),
		"resentment": ActorMath.decay_toward(int(rel["resentment"]), int(rel["scar_floor"]), resentment_factor),
	}


## Canlı kaydı `tick`e taşır (değerleri çürütür, `as_of` = tick). Olay/dedikodu bundan sonra uygulanır.
static func rebase(rel: Dictionary, config: ActorConfig, tick: int) -> void:
	var now := decayed(rel, config, tick)
	rel["trust"] = now["trust"]
	rel["resentment"] = now["resentment"]
	rel["as_of"] = tick


## Tek `protagonist` türündeki (bare) aktörün anahtarı; kadroda yoksa "". Kod anahtar sabiti taşımaz.
static func protagonist_key(state: GameState, config: ActorConfig) -> String:
	for key in keys(state):
		if config.kind_spec(actor_ref(state, key)["kind"]).get("singleton", false):
			return key
	return ""


## Son kararlar (+1 olumlu / -1 olumsuz), eskiden yeniye; kayıt yoksa boş.
static func recent_outcomes(state: GameState, actor_key: String, decision_id: String) -> Array:
	var entry: Variant = data_ref(state).get("decisions", {}).get("%s|%s" % [actor_key, decision_id], null)
	return (entry["recent"] as Array).duplicate() if entry is Dictionary else []


static func push_outcome(state: GameState, config: ActorConfig, actor_key: String, decision_id: String,
		positive: bool) -> void:
	var decisions: Dictionary = data_ref(state)["decisions"]
	var key := "%s|%s" % [actor_key, decision_id]
	var recent: Array = decisions.get(key, {"recent": []})["recent"]
	recent.append(1 if positive else -1)
	while recent.size() > config.n_prec:
		recent.pop_front()
	decisions[key] = {"recent": recent}


## Kayıtlı aktör verisinin biçim hatası ("" = geçerli; veri yoksa da ""). GameState.validate_dict çağırabilir.
static func validate_data(data: Variant) -> String:
	if data == null:
		return ""
	if not (data is Dictionary) or data.get("schema", null) != SCHEMA:
		return "durum.systems.actors şeması geçersiz"
	for field_name in ["actors", "decisions"]:
		if not (data.get(field_name, null) is Dictionary):
			return "durum.systems.actors.%s sözlük değil" % field_name
	if not (data.get("spill_queue", null) is Array) or typeof(data.get("spill_dropped", null)) != TYPE_INT:
		return "durum.systems.actors.spill_queue/spill_dropped geçersiz"
	for key: String in data["actors"]:
		var problem := _actor_problem(key, data["actors"][key])
		if not problem.is_empty():
			return problem
	return ""


static func _actor_problem(key: String, a: Variant) -> String:
	if not (a is Dictionary) or a.get("key", null) != key:
		return "aktör '%s' kaydı bozuk" % key
	for field_name in ["traits", "stance", "salience", "resources", "relations", "state"]:
		if not (a.get(field_name, null) is Dictionary):
			return "aktör '%s'.%s sözlük değil" % [key, field_name]
	if not (a.get("memory", null) is Array) or typeof(a.get("memory_dropped", null)) != TYPE_INT:
		return "aktör '%s'.memory geçersiz" % key
	for target: String in a["relations"]:
		var rel: Variant = a["relations"][target]
		for field_name in RELATION_KEYS:
			if not (rel is Dictionary) or typeof(rel.get(field_name, null)) != TYPE_INT:
				return "aktör '%s' ilişki '%s'.%s tamsayı değil" % [key, target, field_name]
	for entry: Variant in a["memory"]:
		for field_name in MEMORY_KEYS:
			if not (entry is Dictionary) or not entry.has(field_name):
				return "aktör '%s' hafıza kaydında %s yok" % [key, field_name]
	return ""
