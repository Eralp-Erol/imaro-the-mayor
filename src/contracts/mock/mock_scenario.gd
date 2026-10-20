class_name MockScenario
extends RefCounted
## MOCK senaryo verisi (`tests/fixtures/mock_scenario_*.json`) yükleyici ve doğrulayıcısı (ADR-0005 §mock).
## Senaryo SAHTE veridir: `provenance` alanı "MOCK" olmak, açıklama "MOCK" ile başlamak ZORUNDADIR; aksi hâlde
## yüklenmez. Gerekçelerin aritmetiği de denetlenir (beyan edilen sonuç = etkenlerin doğrusal puanı vs eşik), böylece
## mock bile tutarsız "neden" göstermez. Biçim: ADR-0005 Ek A.
## Not: dosya okuma yalnız bu sınıftadır (geliştirme aracı; tick içinde değil). Sözleşme tarama testi bunu sınırlar.

const FORMAT := "imaro.mock_scenario"
const FORMAT_VERSION := 1
const PROVENANCE_MARK := "MOCK"
const EFFECT_TYPES: Array[String] = ["reason", "event", "parcel", "group", "budget", "council_vote"]

var id: StringName = &""
var description: String = ""
## Doğrulanmış ham veri (MockSimFacade okur; değiştirmez).
var data: Dictionary = {}
var errors: PackedStringArray = PackedStringArray()


func is_valid() -> bool:
	return errors.is_empty()


static func load_file(path: String) -> MockScenario:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		var failed := MockScenario.new()
		failed.errors.append("cannot read %s (error %d)" % [path, FileAccess.get_open_error()])
		return failed
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		var bad := MockScenario.new()
		bad.errors.append("%s: not a JSON object" % path)
		return bad
	return from_dict(parsed)


static func from_dict(d: Dictionary) -> MockScenario:
	var s := MockScenario.new()
	s.data = d.duplicate(true)
	s.id = SimContract.to_name(d.get("id", ""))
	s.description = str(d.get("description", ""))
	s._validate_header()
	s._validate_initial()
	var rules: Array = d.get("rules", []) if d.get("rules") is Array else []
	for i in rules.size():
		s._validate_rule(rules[i], "rules[%d]" % i)
	var timeline: Array = d.get("timeline", []) if d.get("timeline") is Array else []
	s._validate_effects(timeline, "timeline", true)
	return s


func _validate_header() -> void:
	if str(data.get("format", "")) != FORMAT or SimContract.to_int(data.get("format_version")) != FORMAT_VERSION:
		errors.append("format must be %s v%d" % [FORMAT, FORMAT_VERSION])
	if str(data.get("provenance", "")) != PROVENANCE_MARK:
		errors.append("provenance must be \"%s\" (mock data is never presented as simulation data)" % PROVENANCE_MARK)
	if not description.begins_with(PROVENANCE_MARK):
		errors.append("description must start with \"%s\"" % PROVENANCE_MARK)
	if id == &"":
		errors.append("id is required")
	if not SimContract.is_compatible(str(data.get("contract_version", ""))):
		errors.append("contract_version %s incompatible with %s" % [data.get("contract_version"), SimContract.VERSION])


func _validate_initial() -> void:
	var initial: Dictionary = data.get("initial", {}) if data.get("initial") is Dictionary else {}
	var seen := {}
	for p: Variant in initial.get("parcels", []):
		var pid := SimContract.to_int((p as Dictionary).get("id")) if p is Dictionary else 0
		if pid <= SimContract.NO_ID or seen.has(pid):
			errors.append("initial.parcels: invalid or duplicate id %s" % pid)
		seen[pid] = true


func _validate_rule(rule: Variant, path: String) -> void:
	if not rule is Dictionary or not (rule as Dictionary).get("when") is Dictionary:
		errors.append("%s: rule needs a 'when' object" % path)
		return
	var when: Dictionary = rule["when"]
	if SimContract.to_name(when.get("kind", "")) == &"":
		errors.append("%s.when.kind is required" % path)
	var reject: Variant = (rule as Dictionary).get("reject")
	if reject != null and (not reject is Dictionary or SimContract.to_name(reject.get("reason_key", "")) == &""):
		errors.append("%s.reject needs reason_key" % path)
	var effects: Array = rule.get("effects", []) if rule.get("effects") is Array else []
	_validate_effects(effects, path + ".effects", false)


## Etkiler: tür bilinir, zaman ≥ 0, etiketler önce tanımlanır ve daha erken/aynı anda yürür, gerekçe aritmetiği tutar.
func _validate_effects(effects: Array, path: String, absolute: bool) -> void:
	var label_due := {}
	for i in effects.size():
		var where := "%s[%d]" % [path, i]
		if not effects[i] is Dictionary:
			errors.append("%s: effect must be an object" % where)
			continue
		var e: Dictionary = effects[i]
		var due := SimContract.to_int(e.get("at_tick" if absolute else "after_ticks", -1), -1)
		if due < (1 if absolute else 0):
			errors.append("%s: %s must be >= %d" % [where, "at_tick" if absolute else "after_ticks", 1 if absolute else 0])
		if not EFFECT_TYPES.has(str(e.get("type", ""))):
			errors.append("%s: unknown effect type '%s'" % [where, e.get("type")])
			continue
		for label: String in _labels_used(e):
			if not label_due.has(label) or int(label_due[label]) > due:
				errors.append("%s: label '%s' must be defined by an earlier reason effect due no later" % [where, label])
		if str(e["type"]) == "reason":
			_validate_reason_effect(e, where)
			label_due[str(e.get("label", ""))] = due


func _validate_reason_effect(e: Dictionary, where: String) -> void:
	if str(e.get("label", "")).is_empty() or not e.get("reason") is Dictionary:
		errors.append("%s: reason effect needs label and reason" % where)
		return
	var rd: Dictionary = e["reason"]
	var r := ReasonRecord.from_dict(rd)
	var declared := r.outcome
	var declared_score: Variant = rd.get("score")
	r.finalize()
	if r.decision_key == &"" or r.factors.is_empty() or r.actor == null or not r.actor.is_valid() \
			or not rd.has("outcome"):
		errors.append("%s: reason needs actor, decision_key, factors and a declared outcome" % where)
	if declared != r.outcome:
		errors.append("%s: declared outcome '%s' but factors score %d vs threshold %d give '%s'"
			% [where, declared, r.score, r.threshold, r.outcome])
	if declared_score != null and SimContract.to_int(declared_score) != r.score:
		errors.append("%s: declared score %s != linear score %d" % [where, declared_score, r.score])


## Bir etkinin başvurduğu gerekçe etiketleri.
static func _labels_used(e: Dictionary) -> PackedStringArray:
	var out := SimContract.to_string_array(e.get("reason_labels", []))
	if e.get("reason") is Dictionary:
		out.append_array(SimContract.to_string_array(e["reason"].get("parent_labels", [])))
	if e.get("event") is Dictionary:
		out.append_array(SimContract.to_string_array(e["event"].get("reason_labels", [])))
	if e.get("vote") is Dictionary:
		for pos: Variant in e["vote"].get("positions", []):
			if pos is Dictionary and pos.has("reason_label"):
				out.append(str(pos["reason_label"]))
	return out
