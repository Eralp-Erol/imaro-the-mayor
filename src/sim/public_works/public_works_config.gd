class_name PublicWorksConfig
extends RefCounted
## Oyuncu yolu işinin sim kuralı verisi (T-042 adım 2; `data/sim/public_works/road_works.json`). Tüm sayılar ÇALIŞMA
## MODELİdir (F05-C), kodda gömülü değildir. Etki formülü açıklanabilir: bölgeye düşen altyapı kapasitesi birimi =
## yolun o
## bölgedeki uzunluğu (km) x sınıf katsayısı (`infra_units_per_km`), tamsayı, sıfıra doğru kesme (float yok).
## Maliyet: bütçe sistemi (T-014) kurulu değil ve para birimi AÇIK (Q-003): maliyet "henüz kurulmadı", uydurma para yok.
## Dosya G/Ç yalnız `load_*` (kurulumda, tick dışında).

const DEFAULT_PATH := "res://data/sim/public_works/road_works.json"
const CM_PER_KM := 100000
const _EXPROPRIATION_KEYS: Array[String] = ["_note", "enabled", "protect_heritage", "household_fate",
	"proximity_radius_m", "reaction_keep_days", "resettlement"]

var error: String = ""
## Sınıf (StringName) -> {"infra_units_per_km": int}.
var classes: Dictionary = {}
var cost_available: bool = false
var cost_reason_key: StringName = &"public_work.cost.not_built"
## T-042b / D-011 kamulaştırma (hepsi ÇALIŞMA MODELİ; Q-017 ayrıntıları açık, kanon değil). Bölüm yoksa KAPALI.
var expropriation_enabled: bool = false
var protect_heritage: bool = true
var household_fate: StringName = ParcelExpropriation.FATE_RETURN
var proximity_radius_m: int = 0
var reaction_keep_days: int = 720
## T-065 · Yeniden iskân çalışma sayıları (`expropriation.resettlement`); bölüm yoksa `available == false`
## (özellik kurulu değil: `policy.set` `system.not_built`).
var resettlement: ResettlementConfig = ResettlementConfig.new()


static func load_default() -> PublicWorksConfig:
	return load_path(DEFAULT_PATH)


static func load_path(path: String) -> PublicWorksConfig:
	var text := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text) if not text.is_empty() else null
	if not (parsed is Dictionary):
		var failed := PublicWorksConfig.new()
		failed.error = "%s okunamadı veya sözlük değil" % path
		return failed
	return from_dict(parsed)


static func from_dict(data: Dictionary) -> PublicWorksConfig:
	var cfg := PublicWorksConfig.new()
	var raw: Variant = data.get("classes", null)
	if not (raw is Dictionary) or (raw as Dictionary).is_empty():
		cfg.error = "classes boş veya sözlük değil"
		return cfg
	for key: Variant in raw:
		var entry: Variant = raw[key]
		var value: Variant = entry.get("infra_units_per_km", null) if entry is Dictionary else null
		if not _is_whole(value) or int(value) < 0:
			cfg.error = "classes.%s.infra_units_per_km negatif olmayan tamsayı olmalı" % str(key)
			cfg.classes = {}
			return cfg
		cfg.classes[StringName(str(key))] = {"infra_units_per_km": int(value)}
	var cost: Variant = data.get("cost", {})
	if cost is Dictionary:
		cfg.cost_available = bool(cost.get("available", false))
		cfg.cost_reason_key = StringName(str(cost.get("reason_key", cfg.cost_reason_key)))
	if data.has("expropriation"):
		cfg.error = cfg._read_expropriation(data["expropriation"])
	return cfg


func is_valid() -> bool:
	return error.is_empty()


func has_class(road_class: StringName) -> bool:
	return classes.has(road_class)


## Sınıf kimlikleri, sıralı.
func class_names() -> Array[StringName]:
	var out: Array[StringName] = []
	for key: StringName in classes:
		out.append(key)
	out.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	return out


## `length_cm` santimetre yol uzunluğunun kapasite birimi: length_cm x katsayı / 100 000 (sıfıra doğru kesme). Sınıf
## verisi yoksa 0 (etki yok).
@warning_ignore("integer_division")
func infra_units(road_class: StringName, length_cm: int) -> int:
	if not classes.has(road_class) or length_cm <= 0:
		return 0
	return length_cm * int(classes[road_class]["infra_units_per_km"]) / CM_PER_KM


## `expropriation` bölümünü okur; hata metni ("" = geçerli). Bilinmeyen anahtar ve geçersiz değer hatadır.
func _read_expropriation(raw: Variant) -> String:
	if not (raw is Dictionary):
		return "expropriation sözlük olmalı"
	var section: Dictionary = raw
	for key: Variant in section:
		if not _EXPROPRIATION_KEYS.has(str(key)):
			return "expropriation.%s bilinmeyen anahtar" % str(key)
	var problem := _expropriation_value_problem(section)
	if not problem.is_empty():
		return problem
	var fate := StringName(str(section.get("household_fate", household_fate)))
	var radius: Variant = section.get("proximity_radius_m", 0)
	var keep: Variant = section.get("reaction_keep_days", reaction_keep_days)
	if section.has("resettlement"):
		var resettlement_cfg := ResettlementConfig.from_dict(section["resettlement"])
		if not resettlement_cfg.error.is_empty():
			return resettlement_cfg.error
		resettlement = resettlement_cfg
	expropriation_enabled = bool(section.get("enabled", false))
	protect_heritage = bool(section.get("protect_heritage", true))
	household_fate = fate
	proximity_radius_m = int(radius)
	reaction_keep_days = int(keep)
	return ""


static func _expropriation_value_problem(section: Dictionary) -> String:
	if typeof(section.get("enabled", false)) != TYPE_BOOL:
		return "expropriation.enabled bool olmalı"
	if typeof(section.get("protect_heritage", true)) != TYPE_BOOL:
		return "expropriation.protect_heritage bool olmalı"
	if not ParcelExpropriation.FATES.has(StringName(str(section.get("household_fate", household_fate_default())))):
		return "expropriation.household_fate bilinmeyen"
	var radius: Variant = section.get("proximity_radius_m", 0)
	if not _is_whole(radius) or int(radius) < 0:
		return "expropriation.proximity_radius_m negatif olmayan tamsayı olmalı"
	var keep: Variant = section.get("reaction_keep_days", 720)
	if not _is_whole(keep) or int(keep) < 1:
		return "expropriation.reaction_keep_days pozitif tamsayı olmalı"
	return ""


static func household_fate_default() -> StringName:
	return ParcelExpropriation.FATE_RETURN


static func _is_whole(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or (typeof(value) == TYPE_FLOAT and value == floorf(value))
