class_name PoliticsConfig
extends RefCounted
## Siyasi aktörler yapılandırması (T-017). Çalışma-modeli sayıları, kesim/meclis/medya kuralları, yetki tablosu ve olay
## şablonları KODDA değil `data/politics/*.json` ve `data/politics/events/*.json`'dadır (F05-C: ayarlanabilir, kanon
## DEĞİL). Meclis büyüklüğü/usulü, `requires_council`, ton profili ve yetkiler yer tutucudur (AÇIK: Q-005..Q-014).
## Kurulumda (tick dışında) `load` ile okunur; `from_files` ham sözlükleri doğrular (testler bozuk veri verebilir).
## Geçersizde `errors` dolu; tüm hatalar tek seferde ("<dosya>.<yol>: açıklama"). `_` ile başlayan anahtarlar belgedir.
## Kod aktör anahtarı/karar kimliği gömmez: hepsi veriden gelir ve ActorConfig'e karşı doğrulanır.

const DIR := "res://data/politics/"
const EVENT_DIR := "res://data/politics/events/"
const FILE_NAMES: Array[String] = ["cadence", "blocs", "council", "media", "authority", "events"]
const REACTIONS: Array[String] = ["oppose", "protest"]
const PROPOSAL_KINDS: Array[String] = ["zoning", "budget"]
const COMMAND_KINDS: Array[String] = ["zoning.propose", "budget.propose"]
const OFFSET_LIMIT := 100000

var errors: PackedStringArray = PackedStringArray()
var error: String = ""
var digest: String = ""

var cadence: Dictionary = {}
var blocs: Dictionary = {}
var council: Dictionary = {}
var media: Dictionary = {}
var known_authority: Array[String] = []
var granted_authority: Array[String] = []
var events: Dictionary = {}
## Olay şablonları, kimliğe göre sıralı (şablon kimliği tarama sırasıdır; sıra anlamı taşımaz).
var templates: Array[Dictionary] = []

var _actors: ActorConfig


static func load_default(actors: ActorConfig) -> PoliticsConfig:
	var files := {}
	for file_name in FILE_NAMES:
		files[file_name] = _load_json(DIR + file_name + ".json")
	if ResourceLoader.exists(DIR + "reactions.json"):  # T-042b: isteğe bağlı, digest dışı
		files["reactions"] = _load_json(DIR + "reactions.json")
	var found := {}
	var index: Variant = files["events"]
	if index is Dictionary and index.get("templates", null) is Array:
		for template_id: Variant in index["templates"]:
			found[str(template_id)] = _load_json(EVENT_DIR + str(template_id) + ".json")
	files["templates"] = found
	return from_files(files, actors)


static func from_files(files: Dictionary, actors: ActorConfig) -> PoliticsConfig:
	var cfg := PoliticsConfig.new()
	cfg._actors = actors
	cfg._build(files)
	return cfg


static func _load_json(path: String) -> Variant:
	var res: Variant = load(path)
	return (res as JSON).data if res is JSON else null


func is_valid() -> bool:
	return error.is_empty()


func cohort(cohort_id: String) -> Dictionary:
	for c: Dictionary in blocs["cohorts"]:
		if c["id"] == cohort_id:
			return c
	return {}


func template(template_id: String) -> Dictionary:
	for t in templates:
		if t["id"] == template_id:
			return t
	return {}


func requires_council(command_kind: String) -> bool:
	return council.get("requires_council", {}).get(command_kind, false) == true


## D-011 Soru 4 (CALISMA DEGERI): imar planı için büyüklük eşikleri etkin mi? (`plan_council_min_*` > 0)
func plan_council_thresholds_active() -> bool:
	return int(council.get("plan_council_min_parcels", 0)) > 0 or int(council.get("plan_council_min_units", 0)) > 0


func is_granted(authority_key: String) -> bool:
	return granted_authority.has(authority_key)


func milestone_open(milestone: String) -> bool:
	var order: Array = events["milestones"]
	return order.has(milestone) and order.find(milestone) <= order.find(cadence["milestone"])


# --- Kurulum ---

func _build(files: Dictionary) -> void:
	var data := {}
	for file_name in FILE_NAMES:
		var raw: Variant = files.get(file_name, null)
		if not (raw is Dictionary):
			errors.append("%s: dosya yok veya JSON nesnesi değil" % file_name)
			continue
		data[file_name] = _prepare(raw, file_name)
	if not errors.is_empty() or _actors == null or not _actors.is_valid():
		if _actors == null or not _actors.is_valid():
			errors.append("aktör yapılandırması geçersiz ya da yok")
		_finish(data)
		return
	_parse_cadence(data["cadence"])
	_parse_events_index(data["events"])
	_parse_authority(data["authority"])
	_parse_blocs(data["blocs"])
	_parse_reactions(files.get("reactions", null))
	_parse_council(data["council"])
	_parse_media(data["media"])
	_parse_templates(files.get("templates", {}), data["events"])
	_finish(data)


func _prepare(raw: Dictionary, file_name: String) -> Dictionary:
	ActorSchema.float_problems(raw, file_name, errors)
	var out: Dictionary = _without_notes(ActorSchema.to_ints(raw))
	if out.get("schema", null) != ActorSchema.VERSION:
		errors.append("%s.schema: %d bekleniyor" % [file_name, ActorSchema.VERSION])
	return out


## Üst düzey `_` ile başlayan anahtarlar belgedir (yok sayılır).
static func _without_notes(raw: Dictionary) -> Dictionary:
	var out := {}
	for key: Variant in raw:
		if not str(key).begins_with("_"):
			out[key] = raw[key]
	return out


func _finish(data: Dictionary) -> void:
	if errors.is_empty():
		data["templates"] = templates
		digest = StateHash.of(data)
		return
	templates.clear()
	error = errors[0] if errors.size() == 1 else "%s (+%d hata daha)" % [errors[0], errors.size() - 1]


func _parse_cadence(section: Dictionary) -> void:
	var path := "cadence"
	ActorSchema.check_unknown(section, ["schema", "scan_days", "rederive_days", "milestone", "autopause",
		"react_trigger_min", "recheck_days", "max_react_records_per_scan", "activity_floor", "cause_cap"], path, errors)
	cadence = {
		"scan_days": ActorSchema.required_int(section, "scan_days", 1, 365, path, errors),
		"rederive_days": ActorSchema.required_int(section, "rederive_days", 1, 3650, path, errors),
		"react_trigger_min": ActorSchema.required_int(section, "react_trigger_min", 0, 1000, path, errors),
		"recheck_days": ActorSchema.required_int(section, "recheck_days", 1, 3650, path, errors),
		"max_react_records_per_scan": ActorSchema.required_int(section, "max_react_records_per_scan", 1, 1000, path,
			errors),
		"activity_floor": ActorSchema.required_int(section, "activity_floor", 0, 1000, path, errors),
		"cause_cap": ActorSchema.required_int(section, "cause_cap", 1, 16, path, errors),
		"milestone": str(section.get("milestone", "")),
		"autopause": section.get("autopause", false) == true,
	}


func _parse_events_index(section: Dictionary) -> void:
	var path := "events"
	ActorSchema.check_unknown(section, ["schema", "templates", "milestones", "max_new_per_scan", "rising_slack_pm",
		"interrupt_budget_per_quarter", "system_actor", "investor_decision", "content", "horizon", "risk"], path,
		errors)
	var milestones: Variant = section.get("milestones", null)
	if not (milestones is Array) or (milestones as Array).is_empty():
		errors.append("events.milestones: boş olmayan dizi olmalı")
		milestones = []
	var ids: Variant = section.get("templates", null)
	if not (ids is Array):
		errors.append("events.templates: dizi olmalı")
		ids = []
	var content: Variant = section.get("content", null)
	if not (content is Dictionary) or not (content.get("blocked_tags", null) is Array) \
			or typeof(content.get("tone_profile", null)) != TYPE_STRING:
		errors.append("events.content: {tone_profile, blocked_tags[]} olmalı")
		content = {"tone_profile": "", "blocked_tags": []}
	var horizon: Variant = section.get("horizon", null)
	if not (horizon is Dictionary):
		errors.append("events.horizon: sözlük olmalı")
		horizon = {}
	var risk: Variant = section.get("risk", null)
	var risk_weights: Variant = risk.get("weights", null) if risk is Dictionary else null
	if not (risk is Dictionary) or not (risk_weights is Dictionary):
		errors.append("events.risk: {weights, reversals_full, permit_full_days} olmalı")
		risk = {}
		risk_weights = {}
	events = {
		"templates": ids, "milestones": milestones,
		"max_new_per_scan": ActorSchema.required_int(section, "max_new_per_scan", 1, 100, path, errors),
		"rising_slack": ActorSchema.required_int(section, "rising_slack_pm", 0, 1000, path, errors),
		"interrupt_budget_per_quarter": ActorSchema.required_int(section, "interrupt_budget_per_quarter", 0, 100, path,
			errors),
		"system_actor": _actor_ref(section.get("system_actor", null), path + ".system_actor"),
		"investor_decision": str(section.get("investor_decision", "")),
		"tone_profile": content["tone_profile"], "blocked_tags": (content["blocked_tags"] as Array).duplicate(),
		"declines_days": ActorSchema.required_int(horizon, "declines_days", 1, 3650, path + ".horizon", errors),
		"reversals_days": ActorSchema.required_int(horizon, "reversals_days", 1, 3650, path + ".horizon", errors),
		"media_days": ActorSchema.required_int(horizon, "media_days", 1, 3650, path + ".horizon", errors),
		"risk_instability": ActorSchema.required_int(risk_weights, "council_instability", 0, 1000, path + ".risk.weights",
			errors),
		"risk_reversals": ActorSchema.required_int(risk_weights, "policy_reversals", 0, 1000, path + ".risk.weights",
			errors),
		"risk_unrest": ActorSchema.required_int(risk_weights, "unrest", 0, 1000, path + ".risk.weights", errors),
		"risk_permit": ActorSchema.required_int(risk_weights, "permit_delay", 0, 1000, path + ".risk.weights", errors),
		"reversals_full": ActorSchema.required_int(risk, "reversals_full", 1, 1000, path + ".risk", errors),
		"permit_full_days": ActorSchema.required_int(risk, "permit_full_days", 1, 3650, path + ".risk", errors),
	}
	if not (milestones as Array).has(cadence["milestone"]):
		errors.append("cadence.milestone: events.milestones içinde olmalı ('%s')" % cadence["milestone"])


## `actor.<tür>.<n>` biçiminde referans metni (kadroda olması gerekmez: sözde aktör/organ olabilir).
func _actor_ref(value: Variant, path: String) -> String:
	if typeof(value) != TYPE_STRING:
		errors.append("%s: aktör referansı (metin) olmalı" % path)
		return ""
	var parsed := SimContract.parse_ref(StringName(value))
	if not (value as String).begins_with(ActorSchema.KEY_PREFIX + ".") or int(parsed["id"]) < 1:
		errors.append("%s: 'actor.<tür>.<n>' biçiminde olmalı (%s)" % [path, value])
	return value


func _parse_authority(section: Dictionary) -> void:
	ActorSchema.check_unknown(section, ["schema", "known", "granted"], "authority", errors)
	known_authority = _string_list(section.get("known", null), "authority.known")
	granted_authority = _string_list(section.get("granted", null), "authority.granted")
	for key in granted_authority:
		if not known_authority.has(key):
			errors.append("authority.granted: bilinmeyen yetki '%s'" % key)


func _string_list(value: Variant, path: String) -> Array[String]:
	var out: Array[String] = []
	if not (value is Array):
		errors.append("%s: dizi olmalı" % path)
		return out
	for item: Variant in value:
		if not ActorSchema.is_id(item) or out.has(item):
			errors.append("%s: geçersiz ya da yinelenen kimlik (%s)" % [path, str(item)])
		else:
			out.append(item)
	return out


# --- Kesimler ---

func _parse_blocs(section: Dictionary) -> void:
	var path := "blocs"
	ActorSchema.check_unknown(section, ["schema", "decay_pm", "attribution_pm", "organizer", "react_decision",
		"support_decision", "tier_reactions", "cohorts", "blend"], path, errors)
	var decay: Variant = section.get("decay_pm", {})
	var organizer: Variant = section.get("organizer", {})
	if not (decay is Dictionary) or not (organizer is Dictionary):
		errors.append("blocs.decay_pm/organizer: sözlük olmalı")
		return
	var blend: Variant = section.get("blend", {})
	if not (blend is Dictionary):
		errors.append("blocs.blend: sözlük olmalı")
		blend = {}
	var react_id := _table_id(section.get("react_decision", null), path + ".react_decision", "bloc", true)
	blocs = {
		"reaction_window": BlocSignals.DEFAULT_WINDOW_DAYS,
		"decay_grievance": ActorSchema.required_int(decay, "grievance", 0, 1000, path + ".decay_pm", errors),
		"decay_satisfaction": ActorSchema.required_int(decay, "satisfaction", 0, 1000, path + ".decay_pm", errors),
		"attribution": ActorSchema.required_int(section, "attribution_pm", 0, 1000, path, errors),
		"organizer_base": ActorSchema.required_int(organizer, "base_pm", 0, 1000, path + ".organizer", errors),
		"organizer_k": ActorSchema.required_int(organizer, "size_share_k_pm", 0, 1000, path + ".organizer", errors),
		"blend_mode": _choice(blend.get("mode", null), ["peak", "mean"], path + ".blend.mode"),
		"min_share": ActorSchema.required_int(blend, "min_share_pm", 0, 1000, path + ".blend", errors),
		"react_decision": react_id,
		"support_decision": _table_id(section.get("support_decision", null), path + ".support_decision", "bloc",
			false),
		"tier_reactions": _tier_reactions(section.get("tier_reactions", null), path + ".tier_reactions", react_id),
		"cohorts": _parse_cohorts(section.get("cohorts", null), path + ".cohorts"),
	}


## Karar tablosu kimliği: tabloda var ve beklenen aktör türünde; `tiered` ise basamaklı olmalı.
func _table_id(value: Variant, path: String, kind: String, tiered: bool) -> String:
	if typeof(value) != TYPE_STRING or _actors.table(value).is_empty():
		errors.append("%s: bilinmeyen karar tablosu '%s'" % [path, str(value)])
		return ""
	var table := _actors.table(value)
	if table["kind"] != kind:
		errors.append("%s: '%s' tablosu '%s' türüne ait değil" % [path, value, kind])
	elif tiered != not (table["tiers"] as Array).is_empty():
		errors.append("%s: '%s' tablosu %s olmalı" % [path, value, "basamaklı" if tiered else "basamaksız"])
	return value


func _tier_reactions(value: Variant, path: String, react_id: String) -> Dictionary:
	var out := {}
	if not (value is Dictionary):
		errors.append("%s: sözlük olmalı" % path)
		return out
	var table := _actors.table(react_id)
	var tier_ids: Array[String] = []
	for tier: Dictionary in table.get("tiers", []):
		tier_ids.append(tier["id"])
	for tier_id: String in tier_ids:
		if not (value as Dictionary).has(tier_id):
			errors.append("%s.%s: eksik (her basamak bir tepkiye eşlenir)" % [path, tier_id])
	for key: Variant in value:
		if not tier_ids.has(key):
			errors.append("%s: bilinmeyen basamak '%s'" % [path, str(key)])
		elif not REACTIONS.has(value[key]):
			errors.append("%s.%s: %s olmalı" % [path, str(key), "/".join(REACTIONS)])
		else:
			out[key] = value[key]
	return out


func _parse_cohorts(value: Variant, path: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not (value is Dictionary) or (value as Dictionary).is_empty():
		errors.append("%s: boş olmayan sözlük olmalı" % path)
		return out
	var used: Array[String] = []
	var ids: Array = (value as Dictionary).keys()
	ids.sort()
	for cohort_id: String in ids:
		var parsed := _parse_cohort(cohort_id, value[cohort_id], "%s.%s" % [path, cohort_id])
		if parsed.is_empty():
			continue
		if used.has(parsed["bloc"]):
			errors.append("%s.%s.bloc: yinelenen kesim yuvası '%s'" % [path, cohort_id, parsed["bloc"]])
		used.append(parsed["bloc"])
		out.append(parsed)
	return out


func _parse_cohort(cohort_id: String, raw: Variant, path: String) -> Dictionary:
	if not ActorSchema.is_id(cohort_id) or not (raw is Dictionary):
		errors.append("%s: geçerli kimlik ve sözlük olmalı" % path)
		return {}
	ActorSchema.check_unknown(raw, ["bloc", "size_source", "priorities", "stances", "grievance_rules",
		"satisfaction_rules"], path, errors)
	var bloc_key: Variant = raw.get("bloc", null)
	var template := _actors.actor_template(str(bloc_key))
	if template.is_empty() or template["kind"] != "bloc":
		errors.append("%s.bloc: roster'da 'bloc' türünde olmayan aktör '%s'" % [path, str(bloc_key)])
	if not BlocSignals.SIZE_SOURCES.has(raw.get("size_source", null)):
		errors.append("%s.size_source: %s olmalı" % [path, "/".join(BlocSignals.SIZE_SOURCES)])
	return {
		"id": cohort_id, "bloc": str(bloc_key), "size_source": str(raw.get("size_source", "")),
		"priorities": _derive_rules(raw.get("priorities", null), "topic", _actors.topic_ids, 0, 1000, path + ".priorities"),
		"stances": _derive_rules(raw.get("stances", null), "axis", _actors.axis_ids, -1000, 1000, path + ".stances"),
		"grievance_rules": _impact_rules(raw.get("grievance_rules", null), path + ".grievance_rules"),
		"satisfaction_rules": _impact_rules(raw.get("satisfaction_rules", null), path + ".satisfaction_rules"),
	}


## [{topic|axis, base, source?, k?}] -> normalleştirilmiş liste (source yoksa k = 0).
func _derive_rules(value: Variant, id_field: String, allowed: Array[String], low: int, high: int,
		path: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not (value is Array):
		errors.append("%s: dizi olmalı" % path)
		return out
	for i in (value as Array).size():
		var rule: Variant = value[i]
		var rpath := "%s[%d]" % [path, i]
		if not (rule is Dictionary):
			errors.append("%s: sözlük olmalı" % rpath)
			continue
		ActorSchema.check_unknown(rule, [id_field, "base", "source", "k"], rpath, errors)
		if not allowed.has(rule.get(id_field, null)):
			errors.append("%s.%s: bilinmeyen kimlik '%s'" % [rpath, id_field, str(rule.get(id_field, null))])
		var source := str(rule.get("source", ""))
		if not source.is_empty() and not BlocSignals.ALL_NAMES.has(source):
			errors.append("%s.source: bilinmeyen sinyal '%s'" % [rpath, source])
		out.append({
			"id": str(rule.get(id_field, "")),
			"base": ActorSchema.required_int(rule, "base", low, high, rpath, errors),
			"source": source, "k": ActorSchema.optional_int(rule, "k", 0, -2000, 2000, rpath, errors),
		})
	return out


func _impact_rules(value: Variant, path: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not (value is Array):
		errors.append("%s: dizi olmalı" % path)
		return out
	for i in (value as Array).size():
		var rule: Variant = value[i]
		var rpath := "%s[%d]" % [path, i]
		if not (rule is Dictionary):
			errors.append("%s: sözlük olmalı" % rpath)
			continue
		ActorSchema.check_unknown(rule, ["signal", "topic", "lo", "hi", "gain"], rpath, errors)
		if not BlocSignals.ALL_NAMES.has(rule.get("signal", null)):
			errors.append("%s.signal: bilinmeyen sinyal '%s'" % [rpath, str(rule.get("signal", null))])
		if not _actors.topic_ids.has(rule.get("topic", null)):
			errors.append("%s.topic: bilinmeyen konu '%s'" % [rpath, str(rule.get("topic", null))])
		var lo := ActorSchema.required_int(rule, "lo", 0, 2000, rpath, errors)
		var hi := ActorSchema.required_int(rule, "hi", 0, 2000, rpath, errors)
		if hi <= lo:
			errors.append("%s: hi (%d) lo'dan (%d) büyük olmalı" % [rpath, hi, lo])
		out.append({"signal": str(rule.get("signal", "")), "topic": str(rule.get("topic", "")), "lo": lo, "hi": hi,
			"gain": ActorSchema.required_int(rule, "gain", 0, 1000, rpath, errors)})
	return out


# --- Yerinden edilme / yakınlık tepkisi (T-042b, D-011) ---

## İSTEĞE BAĞLI `reactions.json`: kamulaştırma tepkisinin kesim kuralları (`FILE_NAMES` DIŞINDA: `digest` ve dolayısıyla
## kamulaştırmasız koşuların durum hash'i, GOLDEN A/B, değişmez). Kurallar kesim kurallarının SONUNA eklenir; sinyal
## (`displacement`/`proximity`) yokken çalışmazlar (`BlocEngine`). Dosya yoksa tepki kuralı yoktur.
func _parse_reactions(raw: Variant) -> void:
	if raw == null:
		return
	if not (raw is Dictionary):
		errors.append("reactions: dosya JSON nesnesi değil")
		return
	var section := _prepare(raw, "reactions")
	ActorSchema.check_unknown(section, ["schema", "window_days", "cohorts"], "reactions", errors)
	blocs["reaction_window"] = ActorSchema.optional_int(section, "window_days", BlocSignals.DEFAULT_WINDOW_DAYS, 1, 3650,
		"reactions", errors)
	var cohorts: Variant = section.get("cohorts", {})
	if not (cohorts is Dictionary):
		errors.append("reactions.cohorts: sözlük olmalı")
		return
	var ids: Array = (cohorts as Dictionary).keys()
	ids.sort()
	for cohort_id: String in ids:
		var path := "reactions.cohorts.%s" % cohort_id
		var target := cohort(cohort_id)
		var entry: Variant = cohorts[cohort_id]
		if target.is_empty() or not (entry is Dictionary):
			errors.append("%s: blocs.json'da olmayan kohort ya da sözlük değil" % path)
			continue
		ActorSchema.check_unknown(entry, ["priorities", "grievance_rules", "satisfaction_rules"], path, errors)
		if entry.has("priorities"):
			target["priorities"].append_array(_derive_rules(entry["priorities"], "topic", _actors.topic_ids, 0, 1000,
				path + ".priorities"))
		for book in ["grievance_rules", "satisfaction_rules"]:
			if entry.has(book):
				target[book].append_array(_impact_rules(entry[book], "%s.%s" % [path, book]))


# --- Meclis ---

func _parse_council(section: Dictionary) -> void:
	var path := "council"
	ActorSchema.check_unknown(section, ["schema", "decision", "body", "requires_council", "session_days",
		"min_lead_days", "tie_result", "abstain_band", "friction_days", "history_limit", "bloc_pressure", "titles",
		"realism", "proposal_axes", "proposal_effects", "plan_council_min_parcels", "plan_council_min_units"],
		path, errors)
	var pressure: Variant = section.get("bloc_pressure", {})
	if not (pressure is Dictionary):
		errors.append("council.bloc_pressure: sözlük olmalı")
		pressure = {}
	var members := _council_members()
	if members.is_empty():
		errors.append("council: roster'da 'council' türünde aktör yok (meclis boş olamaz)")
	council = {
		"decision": _council_decision(section.get("decision", null)), "members": members,
		"body": _actor_ref(section.get("body", null), path + ".body"),
		"requires_council": _requires_council(section.get("requires_council", null)),
		# D-011 Soru 4: büyük imar planı eşikleri (0/yok = ölçüt kapalı; ikisi de kapalıysa bayrak tek başına karar verir).
		"plan_council_min_parcels": ActorSchema.optional_int(section, "plan_council_min_parcels", 0, 0, 100000, path, errors),
		"plan_council_min_units": ActorSchema.optional_int(section, "plan_council_min_units", 0, 0, 1000000000, path, errors),
		"session_days": ActorSchema.required_int(section, "session_days", 1, 365, path, errors),
		"min_lead_days": ActorSchema.required_int(section, "min_lead_days", 0, 365, path, errors),
		"tie_result": _choice(section.get("tie_result", null), ["fail", "pass"], path + ".tie_result"),
		"abstain_band": ActorSchema.required_int(section, "abstain_band", 0, 1000, path, errors),
		"friction_days": ActorSchema.required_int(section, "friction_days", 0, 3650, path, errors),
		"history_limit": ActorSchema.required_int(section, "history_limit", 1, 1000, path, errors),
		"pressure_base": ActorSchema.required_int(pressure, "base_pm", 0, 1000, path + ".bloc_pressure", errors),
		"pressure_k": ActorSchema.required_int(pressure, "grievance_k_pm", 0, 1000, path + ".bloc_pressure", errors),
		"titles": _titles(section.get("titles", null), path + ".titles"),
		"realism": _realism(section.get("realism", null), path + ".realism"),
		"proposal_axes": _proposal_axes(section.get("proposal_axes", null), path + ".proposal_axes"),
		"proposal_effects": _proposal_effects(section.get("proposal_effects", null), path + ".proposal_effects"),
	}


func _council_members() -> Array[String]:
	var out: Array[String] = []
	for template in _actors.roster:
		if template["kind"] == "council":
			out.append(template["key"])
	return out


func _council_decision(value: Variant) -> String:
	if typeof(value) != TYPE_STRING or _actors.table(value).is_empty() or _actors.table(value)["kind"] != "council":
		errors.append("council.decision: 'council' türünde karar tablosu olmalı (%s)" % str(value))
		return ""
	return value


func _requires_council(value: Variant) -> Dictionary:
	var out := {}
	if not (value is Dictionary):
		errors.append("council.requires_council: sözlük olmalı")
		return out
	for key: Variant in value:
		if not COMMAND_KINDS.has(key) or typeof(value[key]) != TYPE_BOOL:
			errors.append("council.requires_council.%s: komut türü (%s) ve bool olmalı" % [str(key), ", ".join(COMMAND_KINDS)])
		else:
			out[key] = value[key]
	for kind in COMMAND_KINDS:
		if not out.has(kind):
			errors.append("council.requires_council.%s: eksik" % kind)
	return out


func _choice(value: Variant, allowed: Array[String], path: String) -> String:
	if not allowed.has(value):
		errors.append("%s: %s olmalı (%s)" % [path, "/".join(allowed), str(value)])
		return allowed[0]
	return value


func _titles(value: Variant, path: String) -> Dictionary:
	var out := {}
	for kind in PROPOSAL_KINDS:
		var key: Variant = value.get(kind, null) if value is Dictionary else null
		if typeof(key) != TYPE_STRING or (key as String).is_empty() or (key as String).contains(" "):
			errors.append("%s.%s: boşluksuz yerelleştirme anahtarı olmalı" % [path, kind])
		out[kind] = str(key)
	return out


func _realism(value: Variant, path: String) -> Dictionary:
	var out := {}
	if not (value is Dictionary):
		errors.append("%s: sözlük olmalı" % path)
		return out
	for kind: Variant in value:
		var entry: Variant = value[kind]
		if not PROPOSAL_KINDS.has(kind) or not (entry is Dictionary):
			errors.append("%s.%s: bilinmeyen öneri türü ya da sözlük değil" % [path, str(kind)])
			continue
		var lo := ActorSchema.required_int(entry, "lo_pm", 0, 2000, "%s.%s" % [path, kind], errors)
		var hi := ActorSchema.required_int(entry, "hi_pm", 0, 2000, "%s.%s" % [path, kind], errors)
		if hi <= lo:
			errors.append("%s.%s: hi_pm lo_pm'den büyük olmalı" % [path, kind])
		out[kind] = {"lo": lo, "hi": hi}
	return out


## {tür: {kullanım: {eksen: pm}}}
func _proposal_axes(value: Variant, path: String) -> Dictionary:
	var out := {}
	if not (value is Dictionary):
		errors.append("%s: sözlük olmalı" % path)
		return out
	for kind: Variant in value:
		var by_use: Variant = value[kind]
		if not PROPOSAL_KINDS.has(kind) or not (by_use is Dictionary):
			errors.append("%s.%s: bilinmeyen öneri türü ya da sözlük değil" % [path, str(kind)])
			continue
		out[kind] = {}
		for use: Variant in by_use:
			ActorSchema.check_map(by_use[use], _actors.axis_ids, -1000, 1000, "%s.%s.%s" % [path, kind, str(use)],
				errors)
			out[kind][use] = (by_use[use] as Dictionary).duplicate() if by_use[use] is Dictionary else {}
	return out


## {tür: {kullanım: {kohort: {konu: pm}}}}
func _proposal_effects(value: Variant, path: String) -> Dictionary:
	var out := {}
	if not (value is Dictionary):
		errors.append("%s: sözlük olmalı" % path)
		return out
	var cohort_ids: Array[String] = []
	for c: Dictionary in blocs.get("cohorts", []):
		cohort_ids.append(c["id"])
	for kind: Variant in value:
		var by_use: Variant = value[kind]
		if not PROPOSAL_KINDS.has(kind) or not (by_use is Dictionary):
			errors.append("%s.%s: bilinmeyen öneri türü ya da sözlük değil" % [path, str(kind)])
			continue
		out[kind] = {}
		for use: Variant in by_use:
			var by_cohort: Variant = by_use[use]
			out[kind][use] = {}
			if not (by_cohort is Dictionary):
				errors.append("%s.%s.%s: sözlük olmalı" % [path, kind, str(use)])
				continue
			for cohort_id: Variant in by_cohort:
				if not cohort_ids.has(cohort_id):
					errors.append("%s.%s.%s: bilinmeyen kohort '%s'" % [path, kind, str(use), str(cohort_id)])
					continue
				ActorSchema.check_map(by_cohort[cohort_id], _actors.topic_ids, -1000, 1000,
					"%s.%s.%s.%s" % [path, kind, str(use), str(cohort_id)], errors)
				out[kind][use][cohort_id] = (by_cohort[cohort_id] as Dictionary).duplicate()
	return out


# --- Medya ---

func _parse_media(section: Dictionary) -> void:
	var path := "media"
	ActorSchema.check_unknown(section, ["schema", "organ", "decision", "lag_days", "tone_decay_pm", "k_media_pm",
		"amp_cap_pm", "weights", "news", "max_stories_per_scan", "story_axes"], path, errors)
	var organ: Variant = section.get("organ", null)
	var template := _actors.actor_template(str(organ))
	if template.is_empty() or template["kind"] != "media":
		errors.append("media.organ: roster'da 'media' türünde olmayan aktör '%s'" % str(organ))
	var decision: Variant = section.get("decision", null)
	if typeof(decision) != TYPE_STRING or _actors.table(decision).is_empty() or _actors.table(decision)["kind"] != "media":
		errors.append("media.decision: 'media' türünde karar tablosu olmalı (%s)" % str(decision))
	var weights: Variant = section.get("weights", {})
	var news: Variant = section.get("news", {})
	if not (weights is Dictionary) or not (news is Dictionary):
		errors.append("media.weights/news: sözlük olmalı")
		return
	media = {
		"organ": str(organ), "decision": str(decision),
		"lag_days": ActorSchema.required_int(section, "lag_days", 0, 3650, path, errors),
		"tone_decay": ActorSchema.required_int(section, "tone_decay_pm", 0, 1000, path, errors),
		"k_media": ActorSchema.required_int(section, "k_media_pm", 0, 10000, path, errors),
		"amp_cap": ActorSchema.required_int(section, "amp_cap_pm", 0, 1000, path, errors),
		"w_fact": ActorSchema.required_int(weights, "fact", 0, 1000, path + ".weights", errors),
		"w_lean": ActorSchema.required_int(weights, "lean", 0, 1000, path + ".weights", errors),
		"w_sens": ActorSchema.required_int(weights, "sens", 0, 1000, path + ".weights", errors),
		"n_conflict": ActorSchema.required_int(news, "conflict", 0, 1000, path + ".news", errors),
		"n_scale": ActorSchema.required_int(news, "scale", 0, 1000, path + ".news", errors),
		"n_novelty": ActorSchema.required_int(news, "novelty", 0, 1000, path + ".news", errors),
		"max_stories": ActorSchema.required_int(section, "max_stories_per_scan", 1, 100, path, errors),
		"story_axes": _story_axes(section.get("story_axes", null), path + ".story_axes"),
	}


func _story_axes(value: Variant, path: String) -> Dictionary:
	var out := {}
	if not (value is Dictionary):
		errors.append("%s: sözlük olmalı" % path)
		return out
	for story_kind: String in MediaEngine.STORY_KINDS:
		if not (value as Dictionary).has(story_kind):
			errors.append("%s.%s: eksik" % [path, story_kind])
			continue
		ActorSchema.check_map(value[story_kind], _actors.axis_ids, -1000, 1000, "%s.%s" % [path, story_kind], errors)
		out[story_kind] = (value[story_kind] as Dictionary).duplicate() if value[story_kind] is Dictionary else {}
	for key: Variant in value:
		if not MediaEngine.STORY_KINDS.has(key):
			errors.append("%s: bilinmeyen haber türü '%s'" % [path, str(key)])
	return out


# --- Olay şablonları ---

func _parse_templates(raw_templates: Variant, index: Dictionary) -> void:
	if not (raw_templates is Dictionary):
		errors.append("templates: sözlük olmalı")
		return
	var ids: Array = index.get("templates", [])
	var seen: Array[String] = []
	for template_id: Variant in ids:
		var raw: Variant = (raw_templates as Dictionary).get(str(template_id), null)
		if not (raw is Dictionary):
			errors.append("events/%s: dosya yok veya JSON nesnesi değil" % str(template_id))
			continue
		var parsed := _parse_template(_without_notes(ActorSchema.to_ints(raw)), "events/%s" % str(template_id))
		if parsed.is_empty():
			continue
		if seen.has(parsed["id"]):
			errors.append("events/%s: yinelenen şablon kimliği '%s'" % [str(template_id), parsed["id"]])
			continue
		seen.append(parsed["id"])
		templates.append(parsed)
	templates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["id"] < b["id"])


func _parse_template(raw: Dictionary, path: String) -> Dictionary:
	ActorSchema.float_problems(raw, path, errors)
	ActorSchema.check_unknown(raw, ["schema", "id", "category", "min_milestone", "hard", "drivers", "weight", "gamma",
		"cooldown_days", "rearm_below", "mutex", "affected", "delivery", "reason_key", "tone_tags", "cause", "options",
		"stages", "expiry_days"], path, errors)
	if raw.get("schema", null) != ActorSchema.VERSION:
		errors.append("%s.schema: %d bekleniyor" % [path, ActorSchema.VERSION])
	var template_id: Variant = raw.get("id", null)
	if typeof(template_id) != TYPE_STRING or (template_id as String).is_empty():
		errors.append("%s.id: boş olmayan metin olmalı" % path)
		return {}
	path = "%s(%s)" % [path, template_id]
	var milestone: Variant = raw.get("min_milestone", null)
	if not (events["milestones"] as Array).has(milestone):
		errors.append("%s.min_milestone: events.milestones içinde olmalı (%s)" % [path, str(milestone)])
	var affected: Variant = raw.get("affected", null)
	if not (affected is Dictionary) or not EventSpec.AFFECTED.has(affected.get("type", null)):
		errors.append("%s.affected.type: %s olmalı" % [path, "/".join(EventSpec.AFFECTED)])
		affected = {"type": "bloc", "from": "trigger"}
	var reason_key: Variant = raw.get("reason_key", null)
	if typeof(reason_key) != TYPE_STRING or (reason_key as String).is_empty() or (reason_key as String).contains(" "):
		errors.append("%s.reason_key: boşluksuz yerelleştirme anahtarı olmalı" % path)
	var out := {
		"id": str(template_id), "category": str(raw.get("category", "")), "min_milestone": str(milestone),
		"hard": _conditions(raw.get("hard", null), path + ".hard"),
		"drivers": _drivers(raw.get("drivers", null), path + ".drivers"),
		"weight": ActorSchema.required_int(raw, "weight", 0, 1000, path, errors),
		"gamma": ActorSchema.required_int(raw, "gamma", 1, 4, path, errors),
		"cooldown_days": ActorSchema.required_int(raw, "cooldown_days", 0, 3650, path, errors),
		"rearm_below": ActorSchema.required_int(raw, "rearm_below", 0, 1000, path, errors),
		"mutex": _string_list(raw.get("mutex", []), path + ".mutex"),
		"affected": {"type": str(affected.get("type", "")), "from": str(affected.get("from", "trigger"))},
		"delivery": _choice(raw.get("delivery", null), EventSpec.DELIVERIES, path + ".delivery"),
		"reason_key": str(reason_key),
		"tone_tags": _tags(raw.get("tone_tags", []), path + ".tone_tags"),
		"cause": _choice(raw.get("cause", null), EventSpec.CAUSES, path + ".cause"),
		"options": _options(raw.get("options", null), path + ".options"),
		"stages": _stages(raw.get("stages", []), path + ".stages"),
		"expiry_days": ActorSchema.required_int(raw, "expiry_days", 1, 3650, path, errors),
	}
	return out


func _tags(value: Variant, path: String) -> Array[String]:
	var out: Array[String] = []
	if not (value is Array):
		errors.append("%s: dizi olmalı" % path)
		return out
	for tag: Variant in value:
		if typeof(tag) != TYPE_STRING or (tag as String).is_empty():
			errors.append("%s: boş olmayan metin olmalı" % path)
		else:
			out.append(tag)
	return out


func _conditions(value: Variant, path: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not (value is Array):
		errors.append("%s: dizi olmalı" % path)
		return out
	for i in (value as Array).size():
		var cond: Variant = value[i]
		var cpath := "%s[%d]" % [path, i]
		if not (cond is Dictionary):
			errors.append("%s: sözlük olmalı" % cpath)
			continue
		ActorSchema.check_unknown(cond, ["src", "op", "value"], cpath, errors)
		if not EventSpec.SOURCES.has(cond.get("src", null)):
			errors.append("%s.src: bilinmeyen kaynak '%s'" % [cpath, str(cond.get("src", null))])
		if not EventSpec.OPS.has(cond.get("op", null)):
			errors.append("%s.op: %s olmalı" % [cpath, " ".join(EventSpec.OPS)])
		var threshold: Variant = cond.get("value", null)
		if typeof(threshold) != TYPE_INT and not _is_tier(threshold):
			errors.append("%s.value: tamsayı ya da bloc.react basamak adı olmalı (%s)" % [cpath, str(threshold)])
		out.append({"src": str(cond.get("src", "")), "op": str(cond.get("op", "")), "value": threshold})
	return out


func _is_tier(value: Variant) -> bool:
	if typeof(value) != TYPE_STRING:
		return false
	for tier: Dictionary in _actors.table(str(blocs.get("react_decision", ""))).get("tiers", []):
		if tier["id"] == value:
			return true
	return false


func _drivers(value: Variant, path: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not (value is Array) or (value as Array).is_empty():
		errors.append("%s: boş olmayan dizi olmalı" % path)
		return out
	var total := 0
	for i in (value as Array).size():
		var driver: Variant = value[i]
		var dpath := "%s[%d]" % [path, i]
		if not (driver is Dictionary) or not ActorSchema.is_id(driver.get("name", null)):
			errors.append("%s: {name, src, lo, hi, weight} olmalı" % dpath)
			continue
		ActorSchema.check_unknown(driver, ["name", "src", "lo", "hi", "weight"], dpath, errors)
		if not EventSpec.SOURCES.has(driver.get("src", null)):
			errors.append("%s.src: bilinmeyen kaynak '%s'" % [dpath, str(driver.get("src", null))])
		var lo := ActorSchema.required_int(driver, "lo", -OFFSET_LIMIT, OFFSET_LIMIT, dpath, errors)
		var hi := ActorSchema.required_int(driver, "hi", -OFFSET_LIMIT, OFFSET_LIMIT, dpath, errors)
		if hi <= lo:
			errors.append("%s: hi (%d) lo'dan (%d) büyük olmalı" % [dpath, hi, lo])
		var weight := ActorSchema.required_int(driver, "weight", 1, 1000, dpath, errors)
		total += weight
		out.append({"name": str(driver.get("name", "")), "src": str(driver.get("src", "")), "lo": lo, "hi": hi,
			"weight": weight})
	if total <= 0:
		errors.append("%s: toplam ağırlık pozitif olmalı" % path)
	return out


func _options(value: Variant, path: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not (value is Array) or (value as Array).is_empty():
		errors.append("%s: boş olmayan dizi olmalı" % path)
		return out
	var ids: Array[String] = []
	var has_defer := false
	for i in (value as Array).size():
		var option: Variant = value[i]
		var opath := "%s[%d]" % [path, i]
		if not (option is Dictionary) or not ActorSchema.is_id(option.get("id", null)):
			errors.append("%s: {id, verb, label_key, effects} olmalı" % opath)
			continue
		ActorSchema.check_unknown(option, ["id", "verb", "label_key", "requires", "costs", "effects", "risk",
			"preview_key"], opath, errors)
		if ids.has(option["id"]):
			errors.append("%s.id: yinelenen seçenek '%s'" % [opath, option["id"]])
		ids.append(option["id"])
		has_defer = has_defer or option.get("verb", null) == "defer"
		out.append({
			"id": option["id"], "verb": str(option.get("verb", "")), "label_key": str(option.get("label_key", "")),
			"requires": _requires(option.get("requires", {}), opath + ".requires"),
			"costs": _costs(option.get("costs", {}), opath + ".costs"),
			"effects": _effects(option.get("effects", null), opath + ".effects"),
		})
	if not has_defer:
		errors.append("%s: 'defer' fiilli bir seçenek zorunlu (olay hiçbir zaman çıkmazsız olmaz)" % path)
	return out


func _requires(value: Variant, path: String) -> Dictionary:
	if not (value is Dictionary):
		errors.append("%s: sözlük olmalı" % path)
		return {}
	ActorSchema.check_unknown(value, ["authority"], path, errors)
	var authority: Variant = value.get("authority", "")
	if authority != "" and not known_authority.has(authority):
		errors.append("%s.authority: bilinmeyen yetki '%s' (authority.known)" % [path, str(authority)])
	return {"authority": str(authority)}


func _costs(value: Variant, path: String) -> Dictionary:
	var out := {}
	if not (value is Dictionary):
		errors.append("%s: sözlük olmalı" % path)
		return out
	ActorSchema.check_unknown(value, ["budget", "political_capital", "time_days"], path, errors)
	for key: Variant in value:
		out[str(key)] = ActorSchema.optional_int(value, str(key), 0, 0, 1000000000, path, errors)
	return out


func _effects(value: Variant, path: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not (value is Array):
		errors.append("%s: dizi olmalı" % path)
		return out
	for i in (value as Array).size():
		var effect: Variant = value[i]
		var epath := "%s[%d]" % [path, i]
		if not (effect is Dictionary):
			errors.append("%s: sözlük olmalı" % epath)
			continue
		ActorSchema.check_unknown(effect, ["target", "scope", "magnitude", "delay_days", "duration_days", "curve",
			"attribution"], epath, errors)
		var target := str(effect.get("target", ""))
		if not EventSpec.TARGETS.has(target):
			errors.append("%s.target: desteklenmeyen hedef '%s' (%s)" % [epath, target, ", ".join(EventSpec.TARGETS)])
		if not EventSpec.SCOPES.has(effect.get("scope", null)):
			errors.append("%s.scope: %s olmalı" % [epath, "/".join(EventSpec.SCOPES)])
		var curve := _choice(effect.get("curve", null), EventSpec.CURVES, epath + ".curve")
		if EventSpec.STEP_ONLY.has(target) and curve != "step":
			errors.append("%s.curve: '%s' etkisi yalnız 'step' olabilir (hafıza kuralından geçer)" % [epath, target])
		var duration := ActorSchema.required_int(effect, "duration_days", 0, 3650, epath, errors)
		if curve != "step" and duration < 1:
			errors.append("%s.duration_days: '%s' eğrisi için >= 1 olmalı" % [epath, curve])
		out.append({
			"target": target, "scope": str(effect.get("scope", "")), "curve": curve, "duration_days": duration,
			"magnitude": ActorSchema.required_int(effect, "magnitude", -1000, 1000, epath, errors),
			"delay_days": ActorSchema.required_int(effect, "delay_days", 0, 3650, epath, errors),
			"attribution": ActorSchema.optional_int(effect, "attribution", 1000, 0, 1000, epath, errors),
		})
	return out


func _stages(value: Variant, path: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not (value is Array):
		errors.append("%s: dizi olmalı" % path)
		return out
	var last := -1
	for i in (value as Array).size():
		var stage: Variant = value[i]
		var spath := "%s[%d]" % [path, i]
		if not (stage is Dictionary):
			errors.append("%s: sözlük olmalı" % spath)
			continue
		ActorSchema.check_unknown(stage, ["after_days", "if", "effects", "next"], spath, errors)
		var after := ActorSchema.required_int(stage, "after_days", 1, 3650, spath, errors)
		if after <= last:
			errors.append("%s.after_days: kesin artan olmalı (%d <= %d)" % [spath, after, last])
		last = after
		var conditions := _conditions([stage.get("if", null)], spath + ".if")
		out.append({"after_days": after, "if": conditions[0] if not conditions.is_empty() else {},
			"effects": _effects(stage.get("effects", []), spath + ".effects"), "next": str(stage.get("next", ""))})
	return out
