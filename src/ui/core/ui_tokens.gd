class_name UiTokens
extends RefCounted
## Tasarım belirteçleri: renk / aralık / yazı boyu / hedef boyutu için TEK KAYNAK (`data/ui/ui_tokens.json`).
## Boyutlar taban değerdir; `UiContext` bunları `ui_scale` ile çarpar ve dokunmatik alt sınırlarını (`floors`)
## uygular.
## Görsel kimlik KANON DEĞİL (HUD stili AÇIK, Q-011): dosyayı değiştirmek tüm temayı değiştirir.

const PATH := "res://data/ui/ui_tokens.json"

var _data: Dictionary = {}


static func load_default() -> UiTokens:
	return from_dict(_read(PATH))


static func from_dict(data: Dictionary) -> UiTokens:
	var tokens := UiTokens.new()
	tokens._data = data.duplicate(true)
	return tokens


func size(token_name: String) -> float:
	return _number("sizes", token_name)


func limit(token_name: String) -> float:
	return _number("limits", token_name)


func floor_of(token_name: String) -> float:
	return _number("floors", token_name)


func safe_area_extra() -> float:
	return float(_data.get("safe_area_extra", 0.0))


func color(token_name: String) -> Color:
	var group: Dictionary = _data.get("colors", {})
	if not group.has(token_name):
		push_error("UiTokens: unknown color token '%s'" % token_name)
		return Color.MAGENTA
	return Color.html(str(group[token_name]))


func color_names() -> PackedStringArray:
	return PackedStringArray((_data.get("colors", {}) as Dictionary).keys())


## WCAG göreli parlaklık oranı (ön plan opak varsayılır; arka plan alfa'sı beyaz yerine koyu zemine
## karıştırılmaz).
static func contrast_ratio(a: Color, b: Color) -> float:
	var la := _luminance(a)
	var lb := _luminance(b)
	return (maxf(la, lb) + 0.05) / (minf(la, lb) + 0.05)


func _number(group_name: String, token_name: String) -> float:
	var group: Dictionary = _data.get(group_name, {})
	if not group.has(token_name):
		push_error("UiTokens: unknown %s token '%s'" % [group_name, token_name])
		return 0.0
	return float(group[token_name])


static func _luminance(c: Color) -> float:
	return 0.2126 * _lin(c.r) + 0.7152 * _lin(c.g) + 0.0722 * _lin(c.b)


static func _lin(v: float) -> float:
	return v / 12.92 if v <= 0.03928 else pow((v + 0.055) / 1.055, 2.4)


static func _read(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary:
		return parsed
	push_error("UiTokens: cannot parse %s" % path)
	return {}
