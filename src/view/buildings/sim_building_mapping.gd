class_name SimBuildingMapping
extends RefCounted
## SimBuildingProjector geçici eşleme verisi (T-040; `data/view/sim_building_mapping.json`). Yalnız KÖPRÜ sayıları:
## kit modülleri/aileleri/katlar manifestten, doku ağırlıkları `settlement.json`dan gelir (yeni sanat kararı yok).
## Görünüm tarafı verisidir: simülasyon bu dosyayı okumaz.

const DEFAULT_PATH := "res://data/view/sim_building_mapping.json"

var units_per_floor: int = 1
var max_buildings: int = 3
## Devam eden inşaatların ilerleme yoklama dönemi (gün): her gün 1/dönem kadarı okunur.
var progress_poll_days: int = 4
var fallback_zone: StringName = &"dense"
## Kullanım adı (String) -> {"families": PackedStringArray, "ground_shop": bool}.
var uses: Dictionary = {}
var error: String = ""


static func load_default() -> SimBuildingMapping:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DEFAULT_PATH))
	return from_dict(parsed as Dictionary if parsed is Dictionary else {})


static func from_dict(d: Dictionary) -> SimBuildingMapping:
	var m := SimBuildingMapping.new()
	if d.is_empty():
		m.error = "eşleme verisi okunamadı"
		return m
	m.units_per_floor = maxi(1, int(d.get("units_per_floor", 1)))
	m.max_buildings = clampi(int(d.get("max_buildings_per_parcel", 3)), 1, 8)
	m.progress_poll_days = maxi(1, int(d.get("progress_poll_days", 4)))
	m.fallback_zone = StringName(str(d.get("fallback_zone", "dense")))
	var uses_in: Dictionary = d.get("uses", {})
	for key: String in uses_in:
		if key.begins_with("_"):
			continue
		var entry: Dictionary = uses_in[key]
		var fams := PackedStringArray()
		for fam in entry.get("families", []):
			fams.append(str(fam))
		m.uses[key] = {"families": fams, "ground_shop": bool(entry.get("ground_shop", false))}
	if m.uses.is_empty():
		m.error = "uses boş"
	return m


func is_valid() -> bool:
	return error.is_empty()


func families_of(use: StringName) -> PackedStringArray:
	return (uses.get(String(use), {}) as Dictionary).get("families", PackedStringArray())


func wants_ground_shop(use: StringName) -> bool:
	return bool((uses.get(String(use), {}) as Dictionary).get("ground_shop", false))


func knows(use: StringName) -> bool:
	return uses.has(String(use))
