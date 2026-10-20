class_name InputProfile
extends RefCounted
## Girdi profili sözleşmesi (T-007, ADR-0004 §Karar 2; TEK-04, PLT-05). Tüketiciler: T-003 kamera rig'i, T-019/T-020 UI.
##
## Ham `InputEvent`'leri OYUNCU FİİLLERİNE çevirir; masaüstü (fare/klavye/trackpad) ve dokunmatik aynı fiilleri üretir,
## yalnız düzen farklıdır. Fiiller yalnız görünüm katmanına gider; simülasyona komut gönderimi UI/kamera sorumluluğudur
## (bu sınıf simülasyonu, dünyayı veya sahne ağacını bilmez; seçim için ekran konumu verir, ışın atmayı görünüm yapar).
##
## KULLANIM (kamera veya girdi düğümü):
##   var input := PlatformProfile.current().create_input_profile()
##   input.pan_requested.connect(_on_pan)            # vb. (aşağıdaki sinyaller)
##   func _unhandled_input(e): if input.handle_event(e): get_viewport().set_input_as_handled()
##   func _process(dt): input.process(dt); _camera_move(input.held_pan_axis(), input.held_zoom_axis(), ...)
##   pencere odağı kaybolunca: input.reset()
## `_unhandled_input` kullanın: UI (Control) olayı önce tüketir, "UI dünyadan önce" kuralı (ADR-0004) böylece sağlanır.
## UI'nin tükettiği bir basışın sonraki sürükleme/bırakma olayları da izlenmeyen olay olarak yok sayılır (durum izlenmez).
##
## FİİL SÖZLEŞMESİ (koordinatlar: viewport pikseli, y aşağı):
##   select_requested(screen_pos)       birincil eylem: tıklama / dokunma-bırakma (sürükleme olmadan)
##   context_requested(screen_pos)      bağlam eylemi: sağ tık / Ctrl+tık / uzun bas
##   pan_requested(screen_delta)        sahne içeriği ekranda bu kadar KAYSIN (içerik parmağı/imleci izler)
##   zoom_requested(factor, anchor)     çarpan; > 1 yakınlaş, < 1 uzaklaş; `anchor` ekran konumu sabit kalmalı
##   rotate_requested(radians, anchor)  POZİTİF = sahne ekranda SAAT YÖNÜNDE döner; `anchor` etrafında
##   pause_toggle_requested             Boşluk
##   speed_step_requested(direction)    +1 / -1 (= ve - tuşları, nümerik +/-); üst sınır `PlatformProfile.max_game_speed`
##   cancel_requested                   Esc
## SÜREKLİ (her karede yoklanır): held_pan_axis() (WASD/oklar, ekran yönü, y aşağı, uzunluk <= 1),
##   held_rotate_axis() (Q = -1, E = +1; saat yönü +), held_zoom_axis() (PageUp = +1 yakınlaş, PageDown = -1).
## Eğim (pitch) fiili tanımlı DEĞİL; T-003 gerekirse sözleşmeye ekletir (iki profile birden eklenir).
##
## Alt sınıflar yalnız işaretçiyi (fare/trackpad ya da dokunma) işler; klavye ve sürekli eksenler burada ortaktır
## (iPad'e harici klavye takılabilir). Bir profil diğerinin olaylarını YOK SAYAR (çift tetik olmasın: Godot dokunmadan
## fare olayı da üretir -- `emulate_mouse_from_touch` --, dokunmatik profil fare olaylarını görmezden gelir).

signal select_requested(screen_pos: Vector2)
signal context_requested(screen_pos: Vector2)
signal pan_requested(screen_delta: Vector2)
signal zoom_requested(factor: float, anchor: Vector2)
signal rotate_requested(radians: float, anchor: Vector2)
signal pause_toggle_requested
signal speed_step_requested(direction: int)
signal cancel_requested

const PROFILE_DESKTOP := &"desktop"
const PROFILE_TOUCH := &"touch"

const _HELD_KEYS: Array[Key] = [
	KEY_W, KEY_A, KEY_S, KEY_D, KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_Q, KEY_E, KEY_PAGEUP, KEY_PAGEDOWN,
]

const _SCRIPT_BY_PROFILE := {
	&"desktop": "res://src/app/input_profile_desktop.gd",
	&"touch": "res://src/app/input_profile_touch.gd",
}

## Sürükleme eşiği (viewport pikseli): bundan az hareket "tıklama/dokunma" sayılır.
var drag_slop_px: float = 8.0
## Profil adı (`desktop` / `touch`); alt sınıf ayarlar.
var profile_name: StringName = &""
## Hover (imleç üstünde bilgi) var mı; UI hover'sız eşdeğer sunmalı mı karar verir.
var supports_hover: bool = false

var _held: Dictionary = {}


## `desktop` -> DesktopInputProfile, `touch` -> TouchInputProfile; bilinmeyen ad -> null (çağıran kontrol eder).
static func create(profile: StringName) -> InputProfile:
	if not _SCRIPT_BY_PROFILE.has(profile):
		return null
	var script: GDScript = load(_SCRIPT_BY_PROFILE[profile])
	return script.new() as InputProfile


## Bir olayı işler; olay bu profil tarafından bir oyuncu fiiline katıldıysa `true` (çağıran `set_input_as_handled`).
func handle_event(event: InputEvent) -> bool:
	var key := event as InputEventKey
	if key != null:
		return _handle_key(key)
	return _handle_pointer_event(event)


## Her karede çağrılır (uzun basma gibi zamana bağlı fiiller için; gerçek saat okumaz, `delta` birikir).
func process(delta: float) -> void:
	_process_pointer(delta)


## Tüm izlenen durumu (basılı tuşlar, parmaklar, sürüklemeler) atar. Pencere odağı kaybında / UI devralınca çağırın.
func reset() -> void:
	_held.clear()
	_reset_pointer()


func held_pan_axis() -> Vector2:
	var v := Vector2(
		float(_is_held(KEY_D) or _is_held(KEY_RIGHT)) - float(_is_held(KEY_A) or _is_held(KEY_LEFT)),
		float(_is_held(KEY_S) or _is_held(KEY_DOWN)) - float(_is_held(KEY_W) or _is_held(KEY_UP))
	)
	return v.limit_length(1.0)


func held_rotate_axis() -> float:
	return float(_is_held(KEY_E)) - float(_is_held(KEY_Q))


func held_zoom_axis() -> float:
	return float(_is_held(KEY_PAGEUP)) - float(_is_held(KEY_PAGEDOWN))


## Alt sınıf: işaretçi olayı (fare/trackpad/dokunma). Fiile katıldıysa true.
func _handle_pointer_event(_event: InputEvent) -> bool:
	return false


func _process_pointer(_delta: float) -> void:
	pass


func _reset_pointer() -> void:
	pass


func _is_held(code: Key) -> bool:
	return _held.has(code)


func _handle_key(event: InputEventKey) -> bool:
	var code: Key = event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode
	if _HELD_KEYS.has(code):
		if not event.pressed:
			return _held.erase(code)
		if event.echo:
			return _held.has(code)
		if _has_command_modifier(event):
			return false
		_held[code] = true
		return true
	if not event.pressed or event.echo or _has_command_modifier(event):
		return false
	return _one_shot(event.keycode if event.keycode != KEY_NONE else code)


func _one_shot(code: Key) -> bool:
	match code:
		KEY_SPACE:
			pause_toggle_requested.emit()
		KEY_ESCAPE:
			cancel_requested.emit()
		KEY_EQUAL, KEY_PLUS, KEY_KP_ADD:
			speed_step_requested.emit(1)
		KEY_MINUS, KEY_KP_SUBTRACT:
			speed_step_requested.emit(-1)
		_:
			return false
	return true


## Cmd/Ctrl/Alt'lı tuşlar uygulama kısayoludur (Cmd+S gibi); hareket/hız fiili sayılmaz.
func _has_command_modifier(event: InputEventKey) -> bool:
	return event.ctrl_pressed or event.meta_pressed or event.alt_pressed
