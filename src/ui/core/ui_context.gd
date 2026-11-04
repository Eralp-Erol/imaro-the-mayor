class_name UiContext
extends RefCounted
## UI bağlamı: platform profili (`PlatformProfile`) + belirteçler (`UiTokens`) + güvenli alan → ölçülmüş
## boyutlar.
## Tüm bileşenler boyutu BURADAN alır (ham sayı yok): masaüstü ve dokunmatik aynı bileşen, farklı
## ölçü/yerleşim.
##
## Ölçek kuralı: boyut = max(taban × ui_scale, dokunmatik alt sınırı). Dokunmatik alt sınırları (gövde 17,
## küçük 13,
## hedef 44, sık hedef 56) ux-layout-v0 §3.2'den; kullanıcı ui_scale'i küçültse bile altına inilmez.
## `min_touch_target_pt` (PlatformProfile) ek bir mutlak taban olarak uygulanır.

const PROFILE_DESKTOP := &"desktop"
const PROFILE_TOUCH := &"touch"

var tokens: UiTokens = null
var profile_name: StringName = PROFILE_DESKTOP
var ui_scale: float = 1.0
var min_touch_target_pt: float = 0.0
var hover_available: bool = true
var max_game_speed: int = 1
## Güvenli alan iç boşlukları (mantıksal birim): x = sol, y = üst, z = sağ, w = alt. Ek 8 pt `frame_insets()`
## içindedir.
var safe_insets: Vector4 = Vector4.ZERO
var reduce_motion: bool = false


static func from_profile(profile: PlatformProfile, tokens_in: UiTokens = null) -> UiContext:
	var ctx := UiContext.new()
	ctx.tokens = tokens_in if tokens_in != null else UiTokens.load_default()
	ctx.profile_name = profile.ui_profile
	ctx.ui_scale = profile.ui_scale
	ctx.min_touch_target_pt = profile.min_touch_target_pt
	ctx.hover_available = profile.hover_available
	ctx.max_game_speed = profile.max_game_speed
	return ctx


## Test/önizleme kısayolu: etiketsiz saf profil üretimi (OS'a dokunmaz).
static func for_profile_name(name_in: StringName, scale_override: float = 0.0) -> UiContext:
	var overrides := {"input_profile": name_in}
	if scale_override > 0.0:
		overrides["ui_scale"] = scale_override
	return from_profile(PlatformProfile.from_tags(PackedStringArray(), overrides))


func is_touch() -> bool:
	return profile_name == PROFILE_TOUCH


func px(base: float) -> float:
	return roundf(base * ui_scale)


func font_body() -> int:
	return _font("body")


func font_small() -> int:
	return _font("small")


func font_title() -> int:
	return int(roundf(tokens.size("title") * ui_scale))


func font_heading() -> int:
	return int(roundf(tokens.size("heading") * ui_scale))


## Her etkileşimli kontrolün asgari kenarı.
func target_min() -> float:
	return _target("target_min", "target")


## Sık fiiller (Onayla, Vazgeç, Duraklat, mod sekmeleri).
func target_primary() -> float:
	return _target("target_primary", "target_primary")


func spacing() -> float:
	var base := px(tokens.size("spacing"))
	return maxf(base, tokens.floor_of("gap")) if is_touch() else base


func edge_margin() -> float:
	var base := px(tokens.size("map_margin"))
	return maxf(base, tokens.floor_of("edge_margin")) if is_touch() else base


## Üst şerit yüksekliği: tabandan ya da içerikten (sık hedef + dikey iç boşluk) büyük olanı.
func bar_top_height() -> float:
	return maxf(_floored(px(tokens.size("bar_top")), "bar_top"), target_primary() + spacing())


## Araç çubuğu satır yüksekliği: iki satırlı (devre dışı + "Henüz kurulmadı") düğmenin sığacağı kadar.
func bar_toolbar_height() -> float:
	var two_lines := ceilf(float(font_body()) * 2.0 * 1.3) + spacing() * 2.0
	return maxf(_floored(px(tokens.size("bar_toolbar")), "bar_toolbar"), two_lines)


func banner_height() -> float:
	return maxf(px(tokens.size("bar_banner")), float(font_small()) * 1.6)


## Güvenli alan + dokunmatikte ek iç boşluk (ev göstergesi, yuvarlak köşe): çerçevenin iç boşluğu.
func frame_insets() -> Vector4:
	var extra := tokens.safe_area_extra() if is_touch() else 0.0
	return Vector4(safe_insets.x + (extra if safe_insets.x > 0.0 else 0.0), safe_insets.y + extra,
		safe_insets.z + (extra if safe_insets.z > 0.0 else 0.0), safe_insets.w + extra)


## Pencere boyutundan çerçeve (güvenli alan içi) boyutu.
func frame_size(window_size: Vector2) -> Vector2:
	var ins := frame_insets()
	return Vector2(maxf(0.0, window_size.x - ins.x - ins.z), maxf(0.0, window_size.y - ins.y - ins.w))


func available_speeds(facade_speeds: PackedInt32Array) -> PackedInt32Array:
	var out := PackedInt32Array()
	for level in facade_speeds:
		if level <= max_game_speed:
			out.append(level)
	return out


func _font(token_name: String) -> int:
	var scaled := int(roundf(tokens.size(token_name) * ui_scale))
	return maxi(scaled, int(tokens.floor_of(token_name))) if is_touch() else scaled


func _target(token_name: String, floor_name: String) -> float:
	var scaled := px(tokens.size(token_name))
	if is_touch():
		scaled = maxf(scaled, tokens.floor_of(floor_name))
		scaled = maxf(scaled, min_touch_target_pt)
	return scaled


func _floored(value: float, floor_name: String) -> float:
	return maxf(value, tokens.floor_of(floor_name)) if is_touch() else value
