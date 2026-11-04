class_name PlatformProfile
extends RefCounted
## Platform profili (T-007, ADR-0004 §Karar 1; PLT-01/02/04/05, TEK-04). YALNIZ görünüm/uygulama katmanı içindir.
##
## {platform, input_profile, ui_profile, graphics_profile, max_game_speed, tick_slicing} değerini özellik
## etiketlerinden (`OS.has_feature`) ve kullanıcı ayarından üretir. Öncelik (düşükten yükseğe):
##   platform varsayılanları < kayıtlı kullanıcı ayarı (`user://platform_settings.cfg`) < komut satırı
##   (`-- --imaro-input-profile=touch` ...) < çağıranın verdiği `extra_overrides`.
##
## SİMÜLASYONA SIZMAZ: `src/sim`, `src/world`, `src/contracts` bu sınıfı, `InputProfile` türlerini, `OS.has_feature`
## veya `DisplayServer` kullanamaz (ADR-0004 gerilim 1: sim sonuçları platformdan bağımsız). Bu kural
## `tests/app/sim_isolation_test.gd` ile denetlenir. Profil yalnız şunları değiştirir: girdi düzeni, UI
## ölçeği/yerleşimi, grafik kalitesi, en yüksek oyun hızı ve tick'in karelere bölünmesi.
##
## YER TUTUCU DEĞERLER: aşağıdaki tablo sayıları (UI ölçeği, grafik ön ayarları, en yüksek hız) ölçüm/karar
## değildir. Grafik ön ayarları T-010 renderer karşılaştırmasıyla, iPad hız/kapasite farkı cihaz ölçümüyle (T-008)
## yazılır; oyun zamanı oranı ÇM/AÇIK (F03 "Oyun temposu") olduğundan `max_game_speed` bir hız BASAMAĞIDIR
## (1 = normal), gerçek gün/sn karşılığı bu katmanda tanımlı değildir.

const PLATFORM_MACOS := &"macos"
const PLATFORM_WINDOWS := &"windows"
const PLATFORM_IOS := &"ios"
## Hedef olmayan (Linux, Android, Web...) sistemler: geliştirme kolaylığı için masaüstü kabul edilir.
const PLATFORM_OTHER := &"other"

const INPUT_DESKTOP := &"desktop"
const INPUT_TOUCH := &"touch"

const GRAPHICS_LOW := &"low"
const GRAPHICS_BALANCED := &"balanced"
const GRAPHICS_HIGH := &"high"

const SETTINGS_PATH := "user://platform_settings.cfg"
const SETTINGS_SECTION := "platform_override"

const UI_SCALE_MIN := 0.5
const UI_SCALE_MAX := 3.0
const MAX_SPEED_LIMIT := 16
const TICK_SLICING_LIMIT := 16

## `OS.has_feature` ile sorgulanan etiketler. Başka etiketler profile girmez.
const PROBED_FEATURES: PackedStringArray = [
	"macos", "windows", "ios", "android", "linux", "web", "mobile", "pc",
]

## Kullanıcı/komut satırı geçersiz kılma anahtarları (örnek: {"input_profile": &"touch", "ui_scale": 1.5}).
const OVERRIDE_KEYS: PackedStringArray = [
	"input_profile", "ui_scale", "graphics_profile", "max_game_speed", "tick_slicing",
]

## Grafik ön ayarları. Yer tutucu; T-010 ölçümünden sonra güncellenir. Simülasyon LOD'u DEĞİL, yalnız render:
## gölge, görünüm HLOD mesafe çarpanı, görünüm ayrıntı yarıçapı çarpanı, MSAA (0=kapalı, 2, 4).
const GRAPHICS_PRESETS := {
	&"low": {"shadows": false, "hlod_distance_scale": 0.6, "detail_radius_scale": 0.6, "msaa": 0},
	&"balanced": {"shadows": true, "hlod_distance_scale": 1.0, "detail_radius_scale": 1.0, "msaa": 0},
	&"high": {"shadows": true, "hlod_distance_scale": 1.5, "detail_radius_scale": 1.5, "msaa": 2},
}

## Platform varsayılanları (yer tutucu). `min_touch_target_pt`: ADR-0004 §3 (iPad ≥ 44 pt hedef).
const DEFAULTS := {
	&"desktop": {
		"ui_scale": 1.0, "hover_available": true, "min_touch_target_pt": 0.0,
		"graphics_profile": &"high", "max_game_speed": 4, "tick_slicing": 1,
	},
	&"touch": {
		"ui_scale": 1.25, "hover_available": false, "min_touch_target_pt": 44.0,
		"graphics_profile": &"balanced", "max_game_speed": 4, "tick_slicing": 1,
	},
}

static var _current: PlatformProfile = null

var platform: StringName = PLATFORM_OTHER
var input_profile: StringName = INPUT_DESKTOP
## UI profili şimdilik girdi profiliyle aynı iki değerdir (`desktop`/`touch`); ayrı alan, ileride ayrışabilsin diye.
var ui_profile: StringName = INPUT_DESKTOP
var ui_scale: float = 1.0
var hover_available: bool = true
var min_touch_target_pt: float = 0.0
var graphics_profile: StringName = GRAPHICS_BALANCED
## En yüksek oyun hızı basamağı (>= 1). Yalnız görünüm/komut katmanı kırpar; simülasyon bunu görmez.
var max_game_speed: int = 1
## Bir tick'in kaç kareye bölüneceği (1 = bölme yok). ADR-0004: platformlar yalnız bölme biçiminde ayrışır.
var tick_slicing: int = 1
## Uygulanan geçersiz kılma anahtarları (ayarlar ekranı "varsayılana dön" gösterebilsin).
var applied_overrides: PackedStringArray = PackedStringArray()
## Geçersiz değer yüzünden yok sayılan anahtarlar (elle bozulmuş ayar dosyası çökertmez).
var rejected_overrides: PackedStringArray = PackedStringArray()


## Gerçek makineden: `OS.has_feature` etiketleri + kayıtlı ayar + komut satırı + `extra_overrides`.
## `OS.has_feature` YALNIZ burada çağrılır.
static func detect(extra_overrides: Dictionary = {}) -> PlatformProfile:
	var tags := PackedStringArray()
	for tag in PROBED_FEATURES:
		if OS.has_feature(tag):
			tags.append(tag)
	var overrides: Dictionary = load_overrides()
	overrides.merge(overrides_from_args(OS.get_cmdline_user_args()), true)
	overrides.merge(extra_overrides, true)
	return from_tags(tags, overrides)


## Önbellekli profil (süreç boyunca bir kez `detect()`). Autoload gerekmez; testte `reset_current()`.
static func current() -> PlatformProfile:
	if _current == null:
		_current = detect()
	return _current


static func set_current(profile: PlatformProfile) -> void:
	_current = profile


static func reset_current() -> void:
	_current = null


## Saf üretim (OS'a dokunmaz; testlenebilir): etiket listesi + geçersiz kılmalar -> profil.
static func from_tags(tags: PackedStringArray, overrides: Dictionary = {}) -> PlatformProfile:
	var p := PlatformProfile.new()
	p.platform = _platform_of(tags)
	var is_touch := p.platform == PLATFORM_IOS or tags.has("android") or tags.has("mobile")
	p.input_profile = INPUT_TOUCH if is_touch else INPUT_DESKTOP
	p._apply_defaults(DEFAULTS[p.input_profile])
	var checked := validate_overrides(overrides)
	p.rejected_overrides = checked["rejected"]
	var valid: Dictionary = checked["valid"]
	for key in valid:
		p.applied_overrides.append(key)
	if valid.has("input_profile"):
		# Girdi profili değişince o profilin varsayılanları yeniden yüklenir, sonra diğer geçersiz kılmalar biner.
		p.input_profile = valid["input_profile"]
		p._apply_defaults(DEFAULTS[p.input_profile])
	p.ui_profile = p.input_profile
	for key in ["ui_scale", "graphics_profile", "max_game_speed", "tick_slicing"]:
		if valid.has(key):
			p.set(key, valid[key])
	return p


## Geçersiz kılma sözlüğünü doğrular: {"valid": Dictionary, "rejected": PackedStringArray}.
## Bilinmeyen anahtar, yanlış tür, aralık dışı değer reddedilir (kırpılmaz): sessizce başka değere çevrilmez.
static func validate_overrides(raw: Dictionary) -> Dictionary:
	var valid := {}
	var rejected := PackedStringArray()
	for key in raw:
		var key_name := String(key)
		var value: Variant = raw[key]
		var ok := false
		match key_name:
			"input_profile":
				ok = (value is StringName or value is String) and [INPUT_DESKTOP, INPUT_TOUCH].has(StringName(value))
				if ok:
					value = StringName(value)
			"graphics_profile":
				ok = (value is StringName or value is String) and GRAPHICS_PRESETS.has(StringName(value))
				if ok:
					value = StringName(value)
			"ui_scale":
				ok = (value is float or value is int) and float(value) >= UI_SCALE_MIN and float(value) <= UI_SCALE_MAX
				if ok:
					value = float(value)
			"max_game_speed":
				ok = value is int and int(value) >= 1 and int(value) <= MAX_SPEED_LIMIT
			"tick_slicing":
				ok = value is int and int(value) >= 1 and int(value) <= TICK_SLICING_LIMIT
		if ok:
			valid[key_name] = value
		else:
			rejected.append(key_name)
	return {"valid": valid, "rejected": rejected}


## Komut satırı kullanıcı argümanları: `--imaro-input-profile=touch`, `--imaro-ui-scale=1.5`,
## `--imaro-graphics=low`, `--imaro-max-speed=3`, `--imaro-tick-slicing=2`. Bozuk değerler `validate` aşamasında düşer.
static func overrides_from_args(args: PackedStringArray) -> Dictionary:
	var out := {}
	for arg in args:
		if not arg.begins_with("--imaro-") or not arg.contains("="):
			continue
		var key := arg.get_slice("=", 0).trim_prefix("--imaro-")
		var raw := arg.get_slice("=", 1)
		match key:
			"input-profile":
				out["input_profile"] = StringName(raw)
			"graphics":
				out["graphics_profile"] = StringName(raw)
			"ui-scale":
				out["ui_scale"] = raw.to_float() if raw.is_valid_float() else raw
			"max-speed":
				out["max_game_speed"] = raw.to_int() if raw.is_valid_int() else raw
			"tick-slicing":
				out["tick_slicing"] = raw.to_int() if raw.is_valid_int() else raw
	return out


## Kayıtlı kullanıcı ayarı (yoksa/bozuksa boş sözlük). Değerler `validate_overrides`'a verilir.
static func load_overrides(path: String = SETTINGS_PATH) -> Dictionary:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK or not cfg.has_section(SETTINGS_SECTION):
		return {}
	var out := {}
	for key in cfg.get_section_keys(SETTINGS_SECTION):
		out[key] = cfg.get_value(SETTINGS_SECTION, key)
	return out


## Yalnız GEÇERLİ geçersiz kılmaları yazar; boş sözlük = dosyayı varsayılana döndürür. Hata kodu döner.
static func save_overrides(overrides: Dictionary, path: String = SETTINGS_PATH) -> Error:
	var valid: Dictionary = validate_overrides(overrides)["valid"]
	var cfg := ConfigFile.new()
	for key in valid:
		cfg.set_value(SETTINGS_SECTION, key, valid[key])
	return cfg.save(path)


## `InputProfile` örneği (`desktop` -> DesktopInputProfile, `touch` -> TouchInputProfile).
func create_input_profile() -> InputProfile:
	return InputProfile.create(input_profile)


## Grafik ön ayarı (kopya). Yer tutucu değerler, bkz. GRAPHICS_PRESETS.
func graphics_settings() -> Dictionary:
	return (GRAPHICS_PRESETS[graphics_profile] as Dictionary).duplicate()


## Oyun hızı basamağını bu platformun tavanına kırpar (view/komut katmanı kullanır, sim görmez).
func clamp_game_speed(level: int) -> int:
	return clampi(level, 1, max_game_speed)


func to_dict() -> Dictionary:
	return {
		"platform": platform, "input_profile": input_profile, "ui_profile": ui_profile, "ui_scale": ui_scale,
		"hover_available": hover_available, "min_touch_target_pt": min_touch_target_pt,
		"graphics_profile": graphics_profile, "max_game_speed": max_game_speed, "tick_slicing": tick_slicing,
		"applied_overrides": applied_overrides, "rejected_overrides": rejected_overrides,
	}


func describe() -> String:
	return "platform=%s input=%s ui_scale=%.2f graphics=%s max_speed=%d tick_slicing=%d overrides=%s rejected=%s" % [
		platform, input_profile, ui_scale, graphics_profile, max_game_speed, tick_slicing,
		",".join(applied_overrides), ",".join(rejected_overrides),
	]


static func _platform_of(tags: PackedStringArray) -> StringName:
	if tags.has("ios"):
		return PLATFORM_IOS
	if tags.has("macos"):
		return PLATFORM_MACOS
	if tags.has("windows"):
		return PLATFORM_WINDOWS
	return PLATFORM_OTHER


func _apply_defaults(table: Dictionary) -> void:
	ui_scale = table["ui_scale"]
	hover_available = table["hover_available"]
	min_touch_target_pt = table["min_touch_target_pt"]
	graphics_profile = table["graphics_profile"]
	max_game_speed = table["max_game_speed"]
	tick_slicing = table["tick_slicing"]
