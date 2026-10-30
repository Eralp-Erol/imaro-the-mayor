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

var error: String = ""
## Sınıf (StringName) -> {"infra_units_per_km": int}.
var classes: Dictionary = {}
var cost_available: bool = false
var cost_reason_key: StringName = &"public_work.cost.not_built"


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


static func _is_whole(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or (typeof(value) == TYPE_FLOAT and value == floorf(value))
