class_name BuildingVariety
extends RefCounted
## Bina cephe/çatı çeşitliliği (D-021, art-director M2 bulgusu 3): onaylı hero mesh'leri ve atlaslar DEĞİŞMEZ; örnek
## başına küçük bir varyant kodu seçilir ve çizimde (shader / HLOD1 köşe rengi) çatı ve cephe tonuna uygulanır.
## GÖRÜNÜM tarafıdır: sütunlardan (parsel kimliği, modül) okur, sim durumuna yazmaz, sim RNG'si tüketmez.
## Oranlar çalışma değeridir (sahibin sözü değil): `data/view/building_variety.json`.
##
## Varyant kodu = roof_mode + ROOF_MODES * wall_light.  roof_mode: 0 kiremit (atlas olduğu gibi), 1 beton/sıva
## (açık gri), 2 çinko/kurşun (soğuk gri). wall_light: 0 atlas cephesi, 1 açık cephe (üst katlar).
## Yalnız EĞİMLİ çatılı modüller çatı modu alır (düz çatılar zaten beton/bitüm okunur).

const PATH := "res://data/view/building_variety.json"
const ROOF_MODES := 3
const CODES := ROOF_MODES * 2
## Eğimli çatı = yüzey normali Y bileşeni bu iki eşik arasında (düz çatı = 1,0; yatay saçak alt yüzü < 0).
const PITCH_NY_MIN := 0.5
const PITCH_NY_MAX := 0.985
## Yer katı (dükkân cephesi) üstü: açık cephe bu yükseklikten (m) başlar (smoothstep, shader ile aynı).
const WALL_LIGHT_Y0 := 3.0
const WALL_LIGHT_Y1 := 4.5

var seed_value: int = 0
var families: Dictionary = {}
var default_rule: Dictionary = {}
var roof_concrete: Color = Color(0.6, 0.57, 0.53)
var roof_zinc: Color = Color(0.5, 0.53, 0.55)
var wall_light: Color = Color(0.88, 0.85, 0.78)
var wall_light_mix: float = 0.55
var reroll_radius_m: float = 28.0
var reroll_tries: int = 5
var jitter: float = 0.05
var enabled: bool = false


static func load_default() -> BuildingVariety:
	var v := BuildingVariety.new()
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if d is Dictionary:
		v.apply(d as Dictionary)
	return v


func apply(d: Dictionary) -> void:
	seed_value = int(d.get("seed", 0))
	families = d.get("families", {})
	default_rule = d.get("default", {})
	roof_concrete = _srgb(d.get("roof_concrete_srgb", [153, 147, 137]))
	roof_zinc = _srgb(d.get("roof_zinc_srgb", [126, 133, 138]))
	wall_light = _srgb(d.get("wall_light_srgb", [226, 217, 198]))
	wall_light_mix = float(d.get("wall_light_mix", 0.55))
	reroll_radius_m = float(d.get("reroll_radius_m", 28.0))
	reroll_tries = int(d.get("reroll_tries", 5))
	jitter = float(d.get("brightness_jitter", 0.05))
	enabled = bool(d.get("enabled", true))


static func _srgb(a: Variant) -> Color:
	var arr: Array = a
	return Color(float(arr[0]) / 255.0, float(arr[1]) / 255.0, float(arr[2]) / 255.0, 1.0)


## Kural: aile için {roof_tile_keep, roof_concrete_share, wall_light_share}.
func rule_for(family: String) -> Dictionary:
	return families.get(family, default_rule)


## Deterministik [0,1) akışı (platform bağımsız tamsayı karıştırma; Godot hash()/randf kullanılmaz).
static func unit(a: int, b: int, salt: int) -> float:
	var x := ((a * 73856093) ^ (b * 19349663) ^ (salt * 83492791)) & 0xFFFFFFFF
	x = ((x ^ (x >> 15)) * 2246822519) & 0xFFFFFFFF
	x = ((x ^ (x >> 13)) * 3266489917) & 0xFFFFFFFF
	x = (x ^ (x >> 16)) & 0xFFFFFFFF
	return float(x) / 4294967296.0


## Varyant kodu; `pitched` false ise çatı modu 0.
func pick(family: String, parcel_id: int, module: int, pitched: bool, salt: int) -> int:
	if not enabled:
		return 0
	var rule := rule_for(family)
	var roof := 0
	if pitched:
		if unit(parcel_id, module + 1000 * salt, seed_value + 1) >= float(rule.get("roof_tile_keep", 1.0)):
			roof = 1 if unit(parcel_id, module + 1000 * salt, seed_value + 2) < float(rule.get("roof_concrete_share", 0.6)) \
					else 2
	var light_share := float(rule.get("wall_light_share", 0.0))
	var light := 1 if unit(parcel_id, module + 1000 * salt, seed_value + 3) < light_share else 0
	return roof + ROOF_MODES * light


## MultiMesh özel verisi: (çatı modu, açık cephe 0/1, parlaklık sapması, 0). Parlaklık `bright` (0..255) sütunundan.
func custom_data(code: int, bright: int) -> Color:
	return Color(float(code % ROOF_MODES), float(code / ROOF_MODES), (float(bright) / 255.0 - 0.5) * 2.0 * jitter, 0.0)


## Shader ile AYNI matematik (doğrusal uzay): bir köşe rengini (sRGB kodlu) varyant koduna göre değiştirir.
func recolor(c: Color, ny: float, y: float, code: int) -> Color:
	var roof_mode := code % ROOF_MODES
	var light := code / ROOF_MODES
	var lin := c.srgb_to_linear()
	var lum := lin.r * 0.2126 + lin.g * 0.7152 + lin.b * 0.0722
	var out := lin
	if roof_mode > 0 and ny > PITCH_NY_MIN and ny < PITCH_NY_MAX:
		var base := (roof_concrete if roof_mode == 1 else roof_zinc).srgb_to_linear()
		var k := roof_shade(lum)
		out = Color(base.r * k, base.g * k, base.b * k, 1.0)
	elif light == 1 and absf(ny) < PITCH_NY_MIN:
		var w := smoothstep(WALL_LIGHT_Y0, WALL_LIGHT_Y1, y)
		var pale := wall_light.srgb_to_linear()
		var k2 := wall_shade(lum)
		var target := Color(pale.r * k2, pale.g * k2, pale.b * k2, 1.0)
		out = lin.lerp(target, wall_light_mix * w * smoothstep(0.02, 0.1, lum))
	return Color(out.r, out.g, out.b, 1.0).linear_to_srgb()


## Atlas parlaklığından (doğrusal) çatı/cephe kazancı; shader ile aynı sabitler.
static func roof_shade(lum: float) -> float:
	return clampf(0.55 + lum * 1.6, 0.45, 1.15)


static func wall_shade(lum: float) -> float:
	return clampf(0.7 + lum * 0.9, 0.7, 1.1)
