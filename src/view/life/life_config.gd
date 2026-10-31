class_name LifeConfig
extends RefCounted
## Yaşam belirtisi (araç + yaya) ayarları (T-050): `data/view/life.json`. Görünüm profil ayarıdır (ADR-0004); simülasyon
## OKUMAZ. Bütün sayılar ÇALIŞMA DEĞERİ (working-value): kanon veya AÇIK karar değil. Geçersiz dosya `errors` doldurur
## ve `valid()` false olur (çağıran görünümü kurmaz). Saf: node/zaman/RNG yok.

const PATH := "res://data/view/life.json"
const SCHEMA_VERSION := 1
const CLASS_KEYS: Array[String] = ["cars_per_activity", "cars_cap_per_100m", "people_per_activity",
		"people_cap_per_100m"]
const PROFILE_KEYS: Array[String] = ["density", "car_range_m", "human_range_m", "human_lod0_m", "max_cars",
		"max_people", "max_cells_built_per_frame"]

var errors: PackedStringArray = PackedStringArray()
var data: Dictionary = {}
var profile_name: StringName = &"desktop"


static func load_default(profile: StringName = &"desktop") -> LifeConfig:
	return load_path(PATH, profile)


static func load_path(path: String, profile: StringName = &"desktop") -> LifeConfig:
	var c := LifeConfig.new()
	c.profile_name = profile
	var parsed: Variant = null
	if FileAccess.file_exists(path):
		parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary):
		c.errors.append("%s: okunamadı ya da sözlük değil" % path)
		return c
	c.data = parsed
	c.errors = c._validate()
	return c


func valid() -> bool:
	return errors.is_empty()


func spill_share() -> float:
	return float(data.get("spill_share", 0.0))


## Ağırlık anahtarı: "res" | "com" | "con".
func weight(key: String) -> float:
	return float((data.get("weights", {}) as Dictionary).get(key, 0.0))


## Yol sınıfı katsayıları ({} = bu sınıfta yaşam yok).
func class_row(road_class: StringName) -> Dictionary:
	var row: Variant = (data.get("classes", {}) as Dictionary).get(String(road_class))
	return row if row is Dictionary else {}


func layout(key: String) -> float:
	return float((data.get("layout", {}) as Dictionary).get(key, 0.0))


func movement(key: String) -> float:
	return float((data.get("movement", {}) as Dictionary).get(key, 0.0))


func update_value(key: String) -> float:
	return float((data.get("update", {}) as Dictionary).get(key, 0.0))


func profile_value(key: String) -> float:
	var prof: Variant = (data.get("profiles", {}) as Dictionary).get(String(profile_name))
	if prof is Dictionary:
		return float((prof as Dictionary).get(key, 0.0))
	return 0.0


func density() -> float:
	return profile_value("density")


## Dokunmatik profilde (iPad) seyrek profil; aksi halde masaüstü (veri, ADR-0004).
static func profile_for(input_profile: StringName) -> StringName:
	return &"touch" if input_profile == &"touch" else &"desktop"


func _validate() -> PackedStringArray:
	var out := PackedStringArray()
	if int(data.get("schema_version", 0)) != SCHEMA_VERSION:
		out.append("schema_version != %d" % SCHEMA_VERSION)
	for key in ["spill_share"]:
		if not data.has(key) or float(data[key]) < 0.0 or float(data[key]) > 1.0:
			out.append("%s 0..1 olmalı" % key)
	var weights: Variant = data.get("weights")
	if not (weights is Dictionary):
		out.append("weights yok")
	else:
		for k in ["res", "com", "con"]:
			if not (weights as Dictionary).has(k) or float((weights as Dictionary)[k]) < 0.0:
				out.append("weights.%s >= 0 olmalı" % k)
	var classes: Variant = data.get("classes")
	if not (classes is Dictionary):
		out.append("classes yok")
	else:
		for cls in classes:
			var row: Variant = (classes as Dictionary)[cls]
			if not (row is Dictionary):
				out.append("classes.%s sözlük değil" % str(cls))
				continue
			for k in CLASS_KEYS:
				if not (row as Dictionary).has(k) or float((row as Dictionary)[k]) < 0.0:
					out.append("classes.%s.%s >= 0 olmalı" % [str(cls), k])
	for section in ["layout", "movement", "update"]:
		if not (data.get(section) is Dictionary):
			out.append("%s yok" % section)
	if (data.get("layout") is Dictionary) and float((data["layout"] as Dictionary).get("cell_m", 0.0)) < 32.0:
		out.append("layout.cell_m >= 32 olmalı")
	if (data.get("layout") is Dictionary) and float((data["layout"] as Dictionary).get("max_piece_m", 0.0)) < 10.0:
		out.append("layout.max_piece_m >= 10 olmalı")
	if (data.get("movement") is Dictionary):
		var mv := data["movement"] as Dictionary
		if float(mv.get("car_speed_mps", 0.0)) <= 0.0 or float(mv.get("person_speed_mps", 0.0)) <= 0.0:
			out.append("movement hızları > 0 olmalı")
		if float(mv.get("speed_spread", -1.0)) < 0.0 or float(mv.get("speed_spread", 2.0)) >= 1.0:
			out.append("movement.speed_spread 0..1 olmalı")
	var profiles: Variant = data.get("profiles")
	if not (profiles is Dictionary) or not (profiles as Dictionary).has(String(profile_name)):
		out.append("profiles.%s yok" % String(profile_name))
	else:
		var prof: Variant = (profiles as Dictionary)[String(profile_name)]
		if not (prof is Dictionary):
			out.append("profiles.%s sözlük değil" % String(profile_name))
		else:
			for k in PROFILE_KEYS:
				if not (prof as Dictionary).has(k) or float((prof as Dictionary)[k]) < 0.0:
					out.append("profiles.%s.%s >= 0 olmalı" % [String(profile_name), k])
	return out
