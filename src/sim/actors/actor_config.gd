class_name ActorConfig
extends RefCounted
## Aktör modeli yapılandırması (T-016 ölçüt 2, characters-npc §3, §7). Çalışma-modeli sayıları, eşikler, ağırlıklar,
## özellik/eksen/konu listeleri ve yer tutucu kadro KODDA değil `data/actors/*.json`'dadır (F05-C: ayarlanabilir,
## kanon DEĞİL). Kurulumda (tick dışında) okunur; tick kodu dosya G/Ç yapmaz.
##
## Dosyalar: traits, axes, topics, kinds, roster_m2, relations_init, memory_params, decision_tables, cadence.
## `load_default()` Godot kaynak yükleyicisiyle (`load`, JSON kaynağı) okur; `from_files` ham sözlükleri doğrular
## (testler bozuk veri verebilir). JSON sayıları float gelir: tam sayı değerli olanlar int'e çevrilir, kesirli olanlar
## reddedilir. Geçersiz yapılandırmada `errors` dolu, kadro/tablolar BOŞTUR (kısmi yapılandırma sızmaz).

const DIR := "res://data/actors/"
const FILE_NAMES: Array[String] = [
	"traits", "axes", "topics", "kinds", "roster_m2", "relations_init", "memory_params", "decision_tables", "cadence",
]
## Zorunlu `memory_params.json` tamsayıları: ad -> [alt, üst].
const MEMORY_INTS: Dictionary = {
	"k_gain": [0, 1000], "loss_aversion": [1000, 10000], "k_resent": [0, 1000], "k_forgive": [0, 1000],
	"scar_frac": [0, 1000], "K_mem": [1, 1024], "spill_frac": [0, 1000], "spill_delay_days": [0, 3650],
	"edge_weight_per_shared": [0, 1000], "familiarity_gain": [0, 1000], "memory_min_weight": [0, 1000],
	"spill_queue_max": [1, 65536],
}
const HALF_LIFE_CLASSES: Array[String] = ["trust", "resentment", "memory_short", "memory_long"]
const RESOURCE_KEYS: Array[String] = ["political", "money", "organization"]
const RELATION_FIELDS: Array[String] = ["trust", "resentment", "obligation", "familiarity", "scar_floor"]
const BARE_FORBIDDEN: Array[String] = ["traits", "stance", "salience", "resources", "affiliations"]
const ACTOR_COMMON_FIELDS: Array[String] = [
	"key", "kind", "campaign_id", "name_key", "lod", "traits", "stance", "salience", "resources", "affiliations",
]

var errors: PackedStringArray = PackedStringArray()
## İlk hata (+ kalan sayısı); geçerliyse "".
var error: String = ""
var digest: String = ""
var trait_ids: Array[String] = []
var axis_ids: Array[String] = []
var topic_ids: Array[String] = []
var kinds: Dictionary = {}
var campaign_template: String = ""
## Kadro şablonları, anahtara göre sıralı.
var roster: Array[Dictionary] = []
var relation_default: Dictionary = {}
var relation_overrides: Array[Dictionary] = []
## memory_params.json değerleri (tamsayı) + türetilen `k_loss`.
var memory: Dictionary = {}
var maintenance_days: int = 7
var noise_trait: String = "volatility"
var n_prec: int = 5
var _tables: Dictionary = {}
var _retention: Dictionary = {}


static func load_default() -> ActorConfig:
	var files := {}
	for file_name in FILE_NAMES:
		var res: Variant = load(DIR + file_name + ".json")
		files[file_name] = (res as JSON).data if res is JSON else null
	return from_files(files)


## `files`: {dosya adı: ayrıştırılmış JSON nesnesi}. Kopya üzerinde çalışır (girdi değişmez).
static func from_files(files: Dictionary) -> ActorConfig:
	var cfg := ActorConfig.new()
	cfg._build(files)
	return cfg


func is_valid() -> bool:
	return error.is_empty()


## Kadro şablonunun derin kopyası; yoksa boş sözlük.
func actor_template(key: String) -> Dictionary:
	for a in roster:
		if a["key"] == key:
			return a.duplicate(true)
	return {}


## Karar tablosu (`council.vote` biçimli kimlik); yoksa boş sözlük. Salt okunur kullanın.
func table(decision_id: String) -> Dictionary:
	return _tables.get(decision_id, {})


func table_ids() -> Array[String]:
	var ids: Array[String] = []
	for key: String in _tables:
		ids.append(key)
	ids.sort()
	return ids


## Günlük tutma oranı (ppm): `trust`, `resentment`, `memory_short`, `memory_long` (yarı ömürden türetilir).
func retention_ppm(half_life_class: String) -> int:
	return _retention.get(half_life_class, ActorMath.PPM)


func is_half_life_class(half_life_class: String) -> bool:
	return _retention.has(half_life_class)


func kind_spec(kind: String) -> Dictionary:
	return kinds.get(kind, {})


# --- Kurulum ---

func _build(files: Dictionary) -> void:
	var data := _load_sections(files)
	if not errors.is_empty():
		_finish(data)
		return
	trait_ids = ActorSchema.id_list(data["traits"], "traits", "traits", errors)
	axis_ids = ActorSchema.id_list(data["axes"], "axes", "axes", errors)
	topic_ids = ActorSchema.id_list(data["topics"], "topics", "topics", errors)
	_parse_kinds(data["kinds"])
	var base_ok := errors.is_empty()
	_parse_memory(data["memory_params"])
	_parse_cadence(data["cadence"])
	if base_ok:  # tablolar ve kadro tür/özellik/eksen/konu listelerine dayanır
		_parse_tables(data["decision_tables"])
		var before_roster := errors.size()
		_parse_roster(data["roster_m2"])
		if errors.size() == before_roster:
			_parse_relations(data["relations_init"])
	_finish(data)


func _load_sections(files: Dictionary) -> Dictionary:
	var data := {}
	for file_name in FILE_NAMES:
		var raw: Variant = files.get(file_name, null)
		if not (raw is Dictionary):
			errors.append("%s: dosya yok veya JSON nesnesi değil" % file_name)
			continue
		ActorSchema.float_problems(raw, file_name, errors)
		data[file_name] = ActorSchema.to_ints(raw)
		if (data[file_name] as Dictionary).get("schema", null) != ActorSchema.VERSION:
			errors.append("%s.schema: %d bekleniyor" % [file_name, ActorSchema.VERSION])
	return data


func _finish(data: Dictionary) -> void:
	if errors.is_empty():
		digest = StateHash.of(data)
		return
	roster.clear()
	_tables.clear()
	relation_overrides.clear()
	error = errors[0] if errors.size() == 1 else "%s (+%d hata daha)" % [errors[0], errors.size() - 1]


func _parse_kinds(section: Dictionary) -> void:
	var raw: Variant = section.get("kinds", null)
	if not (raw is Dictionary) or (raw as Dictionary).is_empty():
		errors.append("kinds.kinds: boş olmayan sözlük olmalı")
		return
	for kind_id: String in (raw as Dictionary).keys():
		var spec: Variant = raw[kind_id]
		var path := "kinds.kinds.%s" % kind_id
		if not ActorSchema.is_id(kind_id) or not (spec is Dictionary):
			errors.append("%s: geçersiz tür tanımı" % path)
			continue
		ActorSchema.check_unknown(spec, ["singleton", "regional", "bare", "decides", "traits", "state_fields"], path,
			errors)
		var kind_traits: Array[String] = []
		for t: Variant in spec.get("traits", []):
			if trait_ids.has(t):
				kind_traits.append(t)
			else:
				errors.append("%s.traits: bilinmeyen özellik '%s'" % [path, str(t)])
		var fields: Variant = spec.get("state_fields", {})
		if not (fields is Dictionary):
			errors.append("%s.state_fields: sözlük olmalı" % path)
			fields = {}
		for field_name: String in fields:
			if not ActorSchema.FIELD_TYPES.has(fields[field_name]):
				errors.append("%s.state_fields.%s: bilinmeyen tip '%s'" % [path, field_name, str(fields[field_name])])
		kinds[kind_id] = {
			"singleton": spec.get("singleton", false) == true, "regional": spec.get("regional", false) == true,
			"bare": spec.get("bare", false) == true, "decides": spec.get("decides", false) == true,
			"traits": kind_traits, "state_fields": (fields as Dictionary).duplicate(),
		}


@warning_ignore("integer_division")
func _parse_memory(section: Dictionary) -> void:
	for param: String in MEMORY_INTS:
		var bounds: Array = MEMORY_INTS[param]
		memory[param] = ActorSchema.required_int(section, param, bounds[0], bounds[1], "memory_params", errors)
	memory["k_loss"] = memory["k_gain"] * memory["loss_aversion"] / ActorSchema.SCALE
	var half_lives: Variant = section.get("half_life_days", null)
	if not (half_lives is Dictionary):
		errors.append("memory_params.half_life_days: sözlük olmalı")
		return
	ActorSchema.check_unknown(half_lives, HALF_LIFE_CLASSES, "memory_params.half_life_days", errors)
	for half_life_class in HALF_LIFE_CLASSES:
		var days := ActorSchema.required_int(half_lives, half_life_class, 1, 36500, "memory_params.half_life_days",
			errors)
		_retention[half_life_class] = ActorMath.retention_for_half_life(days)
		memory["half_life_" + half_life_class] = days
	if half_lives.get("resentment", 0) <= half_lives.get("trust", 0):
		errors.append("memory_params.half_life_days.resentment: kırgınlık güvenden uzun yaşamalı (resentment > trust)")


func _parse_cadence(section: Dictionary) -> void:
	maintenance_days = ActorSchema.required_int(section, "maintenance_days", 1, 365, "cadence", errors)


func _parse_tables(section: Dictionary) -> void:
	var defaults: Variant = section.get("defaults", null)
	if defaults is Dictionary:
		noise_trait = defaults.get("noise_trait", "")
		if not trait_ids.has(noise_trait):
			errors.append("decision_tables.defaults.noise_trait: bilinmeyen özellik '%s'" % noise_trait)
		n_prec = ActorSchema.required_int(defaults, "n_prec", 1, 32, "decision_tables.defaults", errors)
	else:
		errors.append("decision_tables.defaults: sözlük olmalı")
	var decisions: Variant = section.get("decisions", null)
	if not (decisions is Dictionary) or (decisions as Dictionary).is_empty():
		errors.append("decision_tables.decisions: boş olmayan sözlük olmalı")
		return
	for decision_id: String in (decisions as Dictionary).keys():
		var parsed := _parse_table(decision_id, decisions[decision_id])
		if not parsed.is_empty():
			_tables[decision_id] = parsed


func _parse_table(decision_id: String, raw: Variant) -> Dictionary:
	var path := "decision_tables.%s" % decision_id
	var split := decision_id.split(".")
	var kind := split[0]
	if split.size() != 2 or not ActorSchema.is_id(split[1]) or not (raw is Dictionary):
		errors.append("%s: karar kimliği '<tür>.<fiil>' biçiminde, tablo sözlük olmalı" % path)
		return {}
	if not kinds.has(kind) or not kinds[kind]["decides"]:
		errors.append("%s: '%s' türü karar vermez veya tanımsız" % [path, kind])
		return {}
	ActorSchema.check_unknown(raw, ["factors", "theta", "tiers", "hysteresis", "noise_amp"], path, errors)
	var table_data := {
		"kind": kind, "verb": split[1], "factors": _parse_factors(raw.get("factors", null), kind, path),
		"hysteresis": ActorSchema.optional_int(raw, "hysteresis", 0, 0, ActorSchema.SCALE, path, errors),
		"noise_amp": ActorSchema.optional_int(raw, "noise_amp", 0, 0, ActorSchema.SCALE, path, errors),
		"theta": 0, "tiers": [],
	}
	if raw.has("tiers"):
		table_data["tiers"] = _parse_tiers(raw["tiers"], path)
	else:
		table_data["theta"] = ActorSchema.required_int(raw, "theta", -ActorSchema.SCALE, ActorSchema.SCALE, path, errors)
	return table_data


func _parse_factors(raw: Variant, kind: String, path: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not (raw is Array):
		errors.append("%s.factors: dizi olmalı" % path)
		return out
	var names: Array[String] = []
	var weighted := 0
	for i in (raw as Array).size():
		var f: Variant = raw[i]
		var fpath := "%s.factors[%d]" % [path, i]
		if not (f is Dictionary) or not ActorSchema.is_id(f.get("name", null)):
			errors.append("%s: {name, weight, trait_mod?} biçiminde olmalı" % fpath)
			continue
		ActorSchema.check_unknown(f, ["name", "weight", "trait_mod"], fpath, errors)
		if names.has(f["name"]):
			errors.append("%s: yinelenen faktör adı '%s'" % [fpath, f["name"]])
		names.append(f["name"])
		var weight := ActorSchema.required_int(f, "weight", -ActorSchema.SCALE, ActorSchema.SCALE, fpath, errors)
		weighted += 1 if weight != 0 else 0
		ActorSchema.check_map(f.get("trait_mod", {}), kinds[kind]["traits"], -2000, 2000, fpath + ".trait_mod", errors)
		out.append({"name": f["name"], "weight": weight, "trait_mod": (f.get("trait_mod", {}) as Dictionary).duplicate()})
	if weighted < 2:
		errors.append("%s.factors: en az 2 ağırlıklı faktör gerekir (tek faktörlü karar gerekçe sayılmaz, SIM-12)" % path)
	return out


func _parse_tiers(raw: Variant, path: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not (raw is Array) or (raw as Array).is_empty():
		errors.append("%s.tiers: boş olmayan dizi olmalı" % path)
		return out
	var last := -ActorSchema.SCALE - 1
	for i in (raw as Array).size():
		var tier: Variant = raw[i]
		var tpath := "%s.tiers[%d]" % [path, i]
		if not (tier is Dictionary) or not ActorSchema.is_id(tier.get("id", null)):
			errors.append("%s: {id, theta} biçiminde olmalı" % tpath)
			continue
		var theta := ActorSchema.required_int(tier, "theta", -ActorSchema.SCALE, ActorSchema.SCALE, tpath, errors)
		if theta <= last:
			errors.append("%s.theta: basamak eşikleri kesin artan olmalı (%d <= %d)" % [tpath, theta, last])
		last = theta
		out.append({"id": tier["id"], "theta": theta})
	return out


func _parse_roster(section: Dictionary) -> void:
	campaign_template = str(section.get("campaign_template", ""))
	if campaign_template.is_empty():
		errors.append("roster_m2.campaign_template: boş olmayan metin olmalı")
	var raw: Variant = section.get("actors", null)
	if not (raw is Array) or (raw as Array).is_empty():
		errors.append("roster_m2.actors: boş olmayan dizi olmalı")
		return
	var seen: Array[String] = []
	var templates: Array[Dictionary] = []
	for i in (raw as Array).size():
		var template := _parse_actor(raw[i], i)
		if template.is_empty():
			continue
		if seen.has(template["key"]):
			errors.append("roster_m2.actors[%d]: yinelenen anahtar '%s'" % [i, template["key"]])
			continue
		seen.append(template["key"])
		templates.append(template)
	_check_roster_refs(templates, seen)
	templates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["key"] < b["key"])
	roster = templates


func _parse_actor(raw: Variant, index: int) -> Dictionary:
	var path := "roster_m2.actors[%d]" % index
	var shown_kind := str((raw as Dictionary).get("kind", "?")) if raw is Dictionary else "?"
	if not (raw is Dictionary) or typeof(raw.get("key", null)) != TYPE_STRING or not kinds.has(raw.get("kind", null)):
		errors.append("%s: {key, kind} gerekli; tür '%s' kinds.json'da tanımlı olmalı" % [path, shown_kind])
		return {}
	var kind: String = raw["kind"]
	var spec: Dictionary = kinds[kind]
	path = "roster_m2.actors[%d](%s)" % [index, raw["key"]]
	var key_error := ActorSchema.key_problem(raw["key"], kind, spec)
	if not key_error.is_empty():
		errors.append("%s: %s" % [path, key_error])
	var state_fields: Dictionary = spec["state_fields"]
	var allowed: Array = ACTOR_COMMON_FIELDS.duplicate()
	allowed.append_array(state_fields.keys())
	ActorSchema.check_unknown(raw, allowed, path, errors)
	if spec["bare"]:
		for forbidden in BARE_FORBIDDEN:
			if raw.has(forbidden):
				errors.append("%s: '%s' türü yalnız kimlik taşır, '%s' alanı yok (ad/geçmiş AÇIK)" % [path, kind, forbidden])
	return _build_actor(raw, spec, path)


func _build_actor(raw: Dictionary, spec: Dictionary, path: String) -> Dictionary:
	var ctx := {"axes": axis_ids, "topics": topic_ids}
	var traits: Variant = raw.get("traits", {})
	ActorSchema.check_map(traits, spec["traits"], 0, ActorSchema.SCALE, path + ".traits", errors)
	ActorSchema.check_map(raw.get("stance", {}), axis_ids, -ActorSchema.SCALE, ActorSchema.SCALE, path + ".stance", errors)
	ActorSchema.check_map(raw.get("salience", {}), topic_ids, 0, ActorSchema.SCALE, path + ".salience", errors)
	var name_key: Variant = raw.get("name_key", "%s.name" % raw["key"])
	if typeof(name_key) != TYPE_STRING or (name_key as String).is_empty() or (name_key as String).contains(" "):
		errors.append("%s.name_key: boşluksuz yerelleştirme anahtarı olmalı" % path)
	var lod: Variant = raw.get("lod", "full")
	if not ActorSchema.LODS.has(lod):
		errors.append("%s.lod: %s olmalı" % [path, "/".join(ActorSchema.LODS)])
	var state := {}
	for field_name: String in spec["state_fields"]:
		if raw.has(field_name):
			ActorSchema.check_state_field(spec["state_fields"][field_name], raw[field_name], ctx,
				"%s.%s" % [path, field_name], errors)
			state[field_name] = raw[field_name]
	return {
		"key": raw["key"], "kind": raw["kind"], "campaign_id": str(raw.get("campaign_id", campaign_template)),
		"name_key": str(name_key), "lod": str(lod), "traits": _copy_dict(traits),
		"stance": _copy_dict(raw.get("stance", {})), "salience": _copy_dict(raw.get("salience", {})),
		"resources": _resources_of(raw.get("resources", {}), path),
		"affiliations": _copy_array(raw.get("affiliations", [])), "state": state,
		"relations": {}, "memory": [], "memory_dropped": 0,
	}


## Şekli bozuk veride çökmeden boş kopya (hata zaten raporlandı).
static func _copy_dict(value: Variant) -> Dictionary:
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}


static func _copy_array(value: Variant) -> Array:
	return (value as Array).duplicate(true) if value is Array else []


func _resources_of(raw: Variant, path: String) -> Dictionary:
	var out := {}
	if not (raw is Dictionary):
		errors.append("%s.resources: sözlük olmalı" % path)
		return {"political": 0, "money": 0, "organization": 0}
	ActorSchema.check_unknown(raw, RESOURCE_KEYS, path + ".resources", errors)
	for resource in RESOURCE_KEYS:
		var upper := 1_000_000_000 if resource == "money" else ActorSchema.SCALE
		out[resource] = ActorSchema.optional_int(raw, resource, 0, 0, upper, path + ".resources", errors)
	return out


## Kadro kurulduktan sonra: bağlılık/ref alanları kadrodaki aktörlere işaret etmeli; bir sonra ikinci protagonist yok.
func _check_roster_refs(templates: Array[Dictionary], keys: Array[String]) -> void:
	for t in templates:
		var path := "roster_m2.%s" % t["key"]
		for ref: Variant in t["affiliations"]:
			if typeof(ref) != TYPE_STRING:
				errors.append("%s.affiliations: metin olmalı" % path)
			elif ref.begins_with(ActorSchema.KEY_PREFIX + ".") and not keys.has(ref):
				errors.append("%s.affiliations: kadroda olmayan aktör '%s'" % [path, ref])
		var fields: Dictionary = kinds[t["kind"]]["state_fields"]
		for field_name: String in t["state"]:
			var field_type: String = fields[field_name]
			if field_type == "ref_list":
				for ref: Variant in t["state"][field_name]:
					_report_ref(ActorSchema.ref_problem(ref, keys), "%s.%s" % [path, field_name])
			elif field_type == "ref_map":
				for ref: Variant in (t["state"][field_name] as Dictionary).keys():
					_report_ref(ActorSchema.ref_problem(ref, keys), "%s.%s" % [path, field_name])


func _report_ref(problem: String, path: String) -> void:
	if not problem.is_empty():
		errors.append("%s: %s" % [path, problem])


func _parse_relations(section: Dictionary) -> void:
	var defaults: Variant = section.get("default", null)
	relation_default = {"trust": 0, "resentment": 0, "obligation": 0, "familiarity": 0, "scar_floor": 0}
	if defaults is Dictionary:
		_check_relation_fields(defaults, "relations_init.default", relation_default, false)
	else:
		errors.append("relations_init.default: sözlük olmalı")
	var overrides: Variant = section.get("overrides", [])
	if not (overrides is Array):
		errors.append("relations_init.overrides: dizi olmalı")
		return
	var by_key := {}
	for t in roster:
		by_key[t["key"]] = t
	var pairs: Array[String] = []
	for i in (overrides as Array).size():
		var entry: Variant = overrides[i]
		var path := "relations_init.overrides[%d]" % i
		if not (entry is Dictionary):
			errors.append("%s: sözlük olmalı" % path)
			continue
		var parsed := _parse_override(entry, path, by_key)
		if parsed.is_empty():
			continue
		var pair := "%s>%s" % [parsed["from"], parsed["to"]]
		if pairs.has(pair):
			errors.append("%s: yinelenen ilişki %s" % [path, pair])
			continue
		pairs.append(pair)
		relation_overrides.append(parsed)
	relation_overrides.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return "%s>%s" % [a["from"], a["to"]] < "%s>%s" % [b["from"], b["to"]])


func _parse_override(entry: Dictionary, path: String, by_key: Dictionary) -> Dictionary:
	ActorSchema.check_unknown(entry, ["from", "to"] + RELATION_FIELDS, path, errors)
	var from_key: Variant = entry.get("from", null)
	var to_key: Variant = entry.get("to", null)
	for ref: Variant in [from_key, to_key]:
		if typeof(ref) != TYPE_STRING or not by_key.has(ref):
			errors.append("%s: kadroda olmayan aktör '%s'" % [path, str(ref)])
			return {}
	if from_key == to_key:
		errors.append("%s: aktör kendine ilişki kuramaz (%s)" % [path, from_key])
		return {}
	if kinds[by_key[from_key]["kind"]]["bare"]:
		errors.append("%s: '%s' yalnız kimlik taşır, ilişki sahibi olamaz" % [path, from_key])
	if by_key[from_key]["campaign_id"] != by_key[to_key]["campaign_id"]:
		errors.append("%s: campaign_id farklı, kampanya sınırı aşılamaz (CAN-09): %s -> %s" % [path, from_key, to_key])
	var merged := relation_default.duplicate()
	_check_relation_fields(entry, path, merged, true)
	merged["from"] = from_key
	merged["to"] = to_key
	return merged


## `source`taki ilişki alanlarını doğrular ve `target`a yazar (yalnız verilenler).
func _check_relation_fields(source: Dictionary, path: String, target: Dictionary, allow_pair: bool) -> void:
	var bounds := {
		"trust": [-ActorSchema.SCALE, ActorSchema.SCALE], "resentment": [0, ActorSchema.SCALE],
		"obligation": [-ActorSchema.SCALE, ActorSchema.SCALE], "familiarity": [0, ActorSchema.SCALE],
		"scar_floor": [0, ActorSchema.SCALE],
	}
	if allow_pair:
		ActorSchema.check_unknown(source, RELATION_FIELDS + ["from", "to"], path, errors)
	else:
		ActorSchema.check_unknown(source, RELATION_FIELDS, path, errors)
	for field_name: String in RELATION_FIELDS:
		if source.has(field_name):
			target[field_name] = ActorSchema.optional_int(source, field_name, target[field_name], bounds[field_name][0],
				bounds[field_name][1], path, errors)
	if target["scar_floor"] > target["resentment"]:
		errors.append("%s.scar_floor: kırgınlıktan büyük olamaz (%d > %d)" % [path, target["scar_floor"],
			target["resentment"]])
