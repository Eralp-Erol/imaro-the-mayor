class_name UiConfig
extends RefCounted
## UI yapılandırması (data/ui/ui_config.json): para adı/simgesi (Q-003 AÇIK), takvim eşlemesi, imar listesi.
## Para simgesi/adı YALNIZ buradan okunur; kod ve metin tablosu para simgesi taşımaz. Varsayılan yer tutucu `¤`.

const PATH := "res://data/ui/ui_config.json"
const DEFAULT_CURRENCY_SYMBOL := "¤"

static var _data: Dictionary = {}
static var _loaded: bool = false
static var _overrides: Dictionary = {}


static func value(key: String, fallback: Variant = null) -> Variant:
	_ensure_loaded()
	if _overrides.has(key):
		return _overrides[key]
	return _data.get(key, fallback)


static func currency_symbol() -> String:
	return str(value("economy.currency_symbol", DEFAULT_CURRENCY_SYMBOL))


static func currency_name() -> String:
	return str(value("economy.currency_name", ""))


static func days_per_year() -> int:
	return maxi(1, int(value("calendar.days_per_year", 360)))


static func land_uses() -> Array[StringName]:
	var out: Array[StringName] = []
	var raw: Variant = value("zoning.land_uses", [])
	if raw is Array:
		for item: Variant in raw:
			out.append(StringName(str(item)))
	return out


## Test/önizleme: yapılandırma değerini geçici değiştirir (`reset()` geri alır).
static func set_override(key: String, new_value: Variant) -> void:
	_overrides[key] = new_value


static func reset() -> void:
	_overrides.clear()
	_data = {}
	_loaded = false


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if parsed is Dictionary:
		_data = parsed
	else:
		push_error("UiConfig: cannot parse %s" % PATH)
