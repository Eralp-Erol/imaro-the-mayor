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
##          D-014 §3 (2026-11-01) EK ALANLAR (hepsi KOD varsayılanı kapalı/0 = eski davranış):
##          `floor_pressure_pm`: yerinden edilen hane varken öğe baskısının tabanı (evi yıkılan: yüksek tepki).
##          `district_floor` / `district_gain`: ilçe geneli, yerinden edilme sürerken haftalık küçük şikâyet
##          (puan/tarama) = max(district_floor, hane x district_gain / bölge hanesi); 0 = kapalı.
##          `independent_items` (B-008): her yolun öğesi diğer açık PE-01 öğesinden ve bekleme süresinden
##          bağımsız açılır (art arda iki yol = iki ayrı tepki, ikincisi gecikmeden); false = eski mutex/bekleme.
##   council_trust {enabled, decision, cohorts, window_days, threshold_households, drop_per_household_pm, cap_pm,
##          recover_per_scan_pm} (D-021, `CouncilTrust`): yerinden edilme meclis üyelerinin güvenini düşürür. KOD
##          varsayılanı KAPALI (yalnız `reactions.json` açar). `cohorts`: temsil ettiği kesim bu kohortlardansa üye
##          etkilenir; `window_days`: etkinin doğrusal söndüğü süre; `threshold_households`: bunun altındaki (sönmüş)
##          yerinden edilen hanede etki yok; `drop_per_household_pm`: eşiği aşan hane başına güven kesintisi (pm);
##          `cap_pm`: toplam kesinti tavanı; `recover_per_scan_pm`: hedef düştüğünde haftalık en çok toparlanma.
##          Hepsi ÇALIŞMA MODELİ (F05-C), sahibin sözü değil.
##          "Yeni ev sunuldu mu" kararı burada DEĞİL, tek noktada: `ReactionRehousing.still_unhoused` (şimdilik hep
##          "hâlâ barınamıyor": sim'de yeniden iskân mekanizması yok; sahip ayrıca karar verecek).

const KEYS: Array[String] = ["schema", "window_days", "cohorts", "cause", "agenda", "local", "council_trust"]
const COUNCIL_TRUST_KEYS: Array[String] = ["enabled", "decision", "cohorts", "window_days", "threshold_households",
	"drop_per_household_pm", "cap_pm", "recover_per_scan_pm"]
const LOCAL_KEYS: Array[String] = ["enabled", "cohort", "neighborhood_households", "min_displacement_pm",
	"full_displacement_pm", "proximity_share_pm", "floor_pressure_pm", "district_floor", "district_gain",
	"independent_items"]
## Yüksek tepki / ilçe şikâyeti alanlarının KOD varsayılanı (eski davranış; yalnız `reactions.json` açar).
const LOCAL_EXTRA_DEFAULTS := {"floor_pressure_pm": 0, "district_floor": 0, "district_gain": 0,
	"independent_items": false}
const CAUSE_FACTORS: Array[String] = ["displaced_households", "road_proximity"]


static func defaults() -> Dictionary:
	return {
		"cause": {"decision": "decision.bloc.expropriation_cause", "threshold": 10,
			"weights": {"displaced_households": 700, "road_proximity": 300}},
		"agenda": {"template": "PE-01", "min_displacement_pm": 20, "full_displacement_pm": 100},
		"local": {"enabled": false, "cohort": "housed", "neighborhood_households": 200, "min_displacement_pm": 20,
			"full_displacement_pm": 200, "proximity_share_pm": 250}.merged(LOCAL_EXTRA_DEFAULTS),
		"council_trust": {"enabled": false, "decision": "decision.council.displacement_trust", "cohorts": ["housed"],
			"window_days": 180, "threshold_households": 10, "drop_per_household_pm": 4, "cap_pm": 150,
			"recover_per_scan_pm": 25},
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
	if section.has("council_trust"):
		out["council_trust"] = _council_trust(section["council_trust"], errors)
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
	if raw.has("floor_pressure_pm"):
		out["floor_pressure_pm"] = ActorSchema.required_int(raw, "floor_pressure_pm", 0, 1000, path, errors)
	if raw.has("independent_items"):
		if typeof(raw["independent_items"]) != TYPE_BOOL:
			errors.append("%s.independent_items: true/false olmalı" % path)
		else:
			out["independent_items"] = raw["independent_items"]
	for name: String in ["district_floor", "district_gain"]:
		if raw.has(name):
			out[name] = ActorSchema.required_int(raw, name, 0, 100000, path, errors)
	return out


static func _council_trust(raw: Variant, errors: PackedStringArray) -> Dictionary:
	var path := "reactions.council_trust"
	var out: Dictionary = defaults()["council_trust"]
	if not (raw is Dictionary):
		errors.append("%s: sözlük olmalı" % path)
		return out
	ActorSchema.check_unknown(raw, COUNCIL_TRUST_KEYS, path, errors)
	if typeof(raw.get("enabled", null)) != TYPE_BOOL:
		errors.append("%s.enabled: true/false olmalı" % path)
	else:
		out["enabled"] = raw["enabled"]
	var decision: Variant = raw.get("decision", null)
	if typeof(decision) != TYPE_STRING or not (decision as String).begins_with("decision."):
		errors.append("%s.decision: 'decision.' ile başlayan dizge olmalı" % path)
	else:
		out["decision"] = decision
	var cohorts: Variant = raw.get("cohorts", null)
	if not (cohorts is Array) or (cohorts as Array).is_empty():
		errors.append("%s.cohorts: boş olmayan kohort kimliği dizisi olmalı" % path)
	else:
		var ids: Array = []
		for cohort_id: Variant in cohorts:
			if typeof(cohort_id) != TYPE_STRING or (cohort_id as String).is_empty():
				errors.append("%s.cohorts: kohort kimlikleri dizge olmalı" % path)
			else:
				ids.append(cohort_id)
		out["cohorts"] = ids
	out["window_days"] = ActorSchema.required_int(raw, "window_days", 1, 100000, path, errors)
	out["threshold_households"] = ActorSchema.required_int(raw, "threshold_households", 0, 1000000, path, errors)
	out["drop_per_household_pm"] = ActorSchema.required_int(raw, "drop_per_household_pm", 0, 2000, path, errors)
	out["cap_pm"] = ActorSchema.required_int(raw, "cap_pm", 0, 2000, path, errors)
	out["recover_per_scan_pm"] = ActorSchema.required_int(raw, "recover_per_scan_pm", 0, 2000, path, errors)
	return out
