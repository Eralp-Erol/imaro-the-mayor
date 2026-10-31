class_name ReactionConfig
extends RefCounted
## T-042b · `data/politics/reactions.json`ın neden kaydı (`cause`) ve gündem (`agenda`) bölümleri: doğrulama ve
## varsayılanlar. Dosya `PoliticsConfig.digest` dışındadır (kamulaştırmasız koşuların hash'i değişmez); bu sayılar
## ÇALIŞMA MODELİdir (F05-C), kanon değil. Kesim kuralları (`cohorts`) `PoliticsConfig` içinde ayrıştırılır.
##
##   cause  {decision, threshold, weights {displaced_households, road_proximity}}: tepki gerekçe zincirine giren
##          "yerinden edilme/yakınlık" neden kaydının karar anahtarı, eşiği ve etken ağırlıkları (pm).
##   agenda {template, min_displacement_pm, full_displacement_pm}: kesimin yerinden edilme sinyali (pm) alt eşiğe
##          ulaşınca açılan gündem şablonu (PE-01 tipi); öğenin baskısı = sinyal / full_displacement_pm (en çok 1000).
##          `min_displacement_pm` sinyalin erişemeyeceği kadar büyükse (> 1000) yol kapalıdır.
##   local  {enabled, cohort, neighborhood_households, min_displacement_pm, full_displacement_pm, proximity_share_pm}:
##          MAHALLE ölçekli okuma (`ReactionAgenda.local_reading`). Yolun (komutun) kendi yerinden ettiği hane, bölge
##          hanesine DEĞİL `neighborhood_households` (bir mahallenin hane sayısı, çalışma değeri) oranlanır; oran
##          `min_displacement_pm` ve üstündeyse komut başına BİR gündem öğesi açılır (bölge payı kapıları aranmaz).
##          `full_displacement_pm`: baskının tavana (1000) çıktığı seviye. `proximity_share_pm`: yakındaki (yerinden
##          edilmeyen) hanelerin baskıya katkı payı (binde; yerinden edilenden hafif). `cohort`: öğeyi taşıyan kesimin
##          kohortu (blocs.json kimliği; yerinden edilenler barınan hanelerdi). `enabled` false ise yol kapalıdır;
##          KOD varsayılanı kapalıdır (bayrak: yalnız `reactions.json` açar), böylece dosyasız koşular ve GOLDEN A/B
##          etkilenmez.

const KEYS: Array[String] = ["schema", "window_days", "cohorts", "cause", "agenda", "local"]
const LOCAL_KEYS: Array[String] = ["enabled", "cohort", "neighborhood_households", "min_displacement_pm",
	"full_displacement_pm", "proximity_share_pm"]
const CAUSE_FACTORS: Array[String] = ["displaced_households", "road_proximity"]


static func defaults() -> Dictionary:
	return {
		"cause": {"decision": "decision.bloc.expropriation_cause", "threshold": 10,
			"weights": {"displaced_households": 700, "road_proximity": 300}},
		"agenda": {"template": "PE-01", "min_displacement_pm": 20, "full_displacement_pm": 100},
		"local": {"enabled": false, "cohort": "housed", "neighborhood_households": 200, "min_displacement_pm": 20,
			"full_displacement_pm": 200, "proximity_share_pm": 250},
	}


## Bölümleri doğrular ve birleşik sözlüğü döner (eksik bölüm varsayılandır). `templates`: events.json şablon kimlikleri.
static func parse(section: Dictionary, templates: Array, errors: PackedStringArray) -> Dictionary:
	var out := defaults()
	if section.has("cause"):
		out["cause"] = _cause(section["cause"], errors)
	if section.has("agenda"):
		out["agenda"] = _agenda(section["agenda"], templates, errors)
	if section.has("local"):
		out["local"] = _local(section["local"], errors)
	return out


static func _cause(raw: Variant, errors: PackedStringArray) -> Dictionary:
	var path := "reactions.cause"
	var out: Dictionary = defaults()["cause"]
	if not (raw is Dictionary):
		errors.append("%s: sözlük olmalı" % path)
		return out
	ActorSchema.check_unknown(raw, ["decision", "threshold", "weights"], path, errors)
	var decision: Variant = raw.get("decision", null)
	if typeof(decision) != TYPE_STRING or not (decision as String).begins_with("decision."):
		errors.append("%s.decision: 'decision.' ile başlayan dizge olmalı" % path)
	else:
		out["decision"] = decision
	out["threshold"] = ActorSchema.required_int(raw, "threshold", -1000, 1000, path, errors)
	var weights: Variant = raw.get("weights", null)
	if not (weights is Dictionary):
		errors.append("%s.weights: sözlük olmalı" % path)
		return out
	ActorSchema.check_unknown(weights, CAUSE_FACTORS, path + ".weights", errors)
	for factor in CAUSE_FACTORS:
		(out["weights"] as Dictionary)[factor] = ActorSchema.required_int(weights, factor, 0, 1000, path + ".weights",
			errors)
	return out


static func _agenda(raw: Variant, templates: Array, errors: PackedStringArray) -> Dictionary:
	var path := "reactions.agenda"
	var out: Dictionary = defaults()["agenda"]
	if not (raw is Dictionary):
		errors.append("%s: sözlük olmalı" % path)
		return out
	ActorSchema.check_unknown(raw, ["template", "min_displacement_pm", "full_displacement_pm"], path, errors)
	var template: Variant = raw.get("template", null)
	if typeof(template) != TYPE_STRING or not templates.has(str(template).to_lower()):
		errors.append("%s.template: events.json şablonlarından biri olmalı (%s)" % [path, str(template)])
	else:
		out["template"] = template
	out["min_displacement_pm"] = ActorSchema.required_int(raw, "min_displacement_pm", 1, 2000, path, errors)
	out["full_displacement_pm"] = ActorSchema.required_int(raw, "full_displacement_pm", 1, 2000, path, errors)
	return out


static func _local(raw: Variant, errors: PackedStringArray) -> Dictionary:
	var path := "reactions.local"
	var out: Dictionary = defaults()["local"]
	if not (raw is Dictionary):
		errors.append("%s: sözlük olmalı" % path)
		return out
	ActorSchema.check_unknown(raw, LOCAL_KEYS, path, errors)
	if typeof(raw.get("enabled", null)) != TYPE_BOOL:
		errors.append("%s.enabled: true/false olmalı" % path)
	else:
		out["enabled"] = raw["enabled"]
	var cohort: Variant = raw.get("cohort", null)
	if typeof(cohort) != TYPE_STRING or (cohort as String).is_empty():
		errors.append("%s.cohort: kohort kimliği (dizge) olmalı" % path)
	else:
		out["cohort"] = cohort
	out["neighborhood_households"] = ActorSchema.required_int(raw, "neighborhood_households", 1, 1000000, path, errors)
	out["min_displacement_pm"] = ActorSchema.required_int(raw, "min_displacement_pm", 1, 100000, path, errors)
	out["full_displacement_pm"] = ActorSchema.required_int(raw, "full_displacement_pm", 1, 100000, path, errors)
	out["proximity_share_pm"] = ActorSchema.required_int(raw, "proximity_share_pm", 0, 1000, path, errors)
	return out
