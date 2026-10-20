class_name TouchInputProfile
extends InputProfile
## Dokunmatik girdi profili (iPad), ADR-0004 §Karar 2. Sözleşme: `InputProfile`.
##
## Tek parmak: dokun-bırak = seç; sürükle (eşik sonrası) = pan; hareketsiz uzun bas = bağlam.
## İki parmak: kıstır = zoom, bükül = döndür (küçük bir eşikten sonra, kıstırırken titreyen dönüş olmasın), merkez
## kayması = pan. İkinci parmak bir kez gelince jest bitene kadar tek parmak pan/seçme geri dönmez (zıplama ve
## yanlış seçim olmasın). Üç ve daha fazla parmak: ilk ikisi kullanılır.
## Fare ve trackpad olayları YOK SAYILIR (Godot dokunmadan fare olayı da üretir; çift tetik olmasın).
## Klavye (harici klavye) ortak sınıftan gelir.
##
## DOĞRULANMADI (cihaz yok): gerçek iPad parmak ölçekleri, eşik değerleri, `canceled` davranışı (sistem jestleri).
## Eşikler yer tutucudur (iOS uzun basma ≈ 0,5 sn).

enum Mode { IDLE, PENDING, PANNING, LONG_FIRED, MULTI, BLOCKED }

## Uzun basma süresi (sn); `process(delta)` ile biriken süre.
var long_press_s: float = 0.5
## İki parmak dönüşü bu açıyı (radyan) aşmadan dönüş fiili üretilmez (~6 derece).
var rotate_threshold_rad: float = 0.105

var _mode: Mode = Mode.IDLE
var _touches: Dictionary = {}
var _order: Array[int] = []
var _origin: Vector2 = Vector2.ZERO
var _last_single: Vector2 = Vector2.ZERO
var _press_time: float = 0.0
var _prev_center: Vector2 = Vector2.ZERO
var _prev_dist: float = 0.0
var _prev_angle: float = 0.0
var _rot_accum: float = 0.0
var _rot_active: bool = false


func _init() -> void:
	profile_name = InputProfile.PROFILE_TOUCH
	supports_hover = false


## Test/hata ayıklama: şu anki jest durumu (`Mode`).
func mode() -> Mode:
	return _mode


func _handle_pointer_event(event: InputEvent) -> bool:
	var touch := event as InputEventScreenTouch
	if touch != null:
		return _on_touch(touch)
	var drag := event as InputEventScreenDrag
	if drag != null:
		return _on_drag(drag)
	return false


func _process_pointer(delta: float) -> void:
	if _mode != Mode.PENDING:
		return
	_press_time += delta
	if _press_time >= long_press_s:
		_mode = Mode.LONG_FIRED
		context_requested.emit(_origin)


func _reset_pointer() -> void:
	_mode = Mode.IDLE
	_touches.clear()
	_order.clear()
	_rot_accum = 0.0
	_rot_active = false


func _on_touch(event: InputEventScreenTouch) -> bool:
	if event.pressed:
		_touches[event.index] = event.position
		if not _order.has(event.index):
			_order.append(event.index)
		if _order.size() == 1:
			_mode = Mode.PENDING
			_origin = event.position
			_last_single = event.position
			_press_time = 0.0
		elif _order.size() == 2:
			_begin_multi()
		return true
	if not _touches.has(event.index):
		return false  # izlenmeyen bırakma (basışı UI tüketmişti): yok say
	if event.canceled:
		_reset_pointer()  # sistem jesti girdi: yarım jest atılır, seçim üretilmez
		return true
	_touches.erase(event.index)
	_order.erase(event.index)
	if _order.is_empty():
		var was_tap := _mode == Mode.PENDING
		_mode = Mode.IDLE
		if was_tap:
			select_requested.emit(event.position)
	elif _order.size() == 1:
		_mode = Mode.BLOCKED
	else:
		_begin_multi()
	return true


func _on_drag(event: InputEventScreenDrag) -> bool:
	if not _touches.has(event.index):
		return false
	_touches[event.index] = event.position
	match _mode:
		Mode.PENDING:
			if event.index == _order[0] and event.position.distance_to(_origin) > drag_slop_px:
				_mode = Mode.PANNING
				_last_single = _origin
				_pan_single(event.position)
		Mode.PANNING:
			if event.index == _order[0]:
				_pan_single(event.position)
		Mode.MULTI:
			_update_multi()
	return true


func _pan_single(pos: Vector2) -> void:
	pan_requested.emit(pos - _last_single)
	_last_single = pos


func _begin_multi() -> void:
	_mode = Mode.MULTI
	_rot_accum = 0.0
	_rot_active = false
	var a: Vector2 = _touches[_order[0]]
	var b: Vector2 = _touches[_order[1]]
	_prev_center = (a + b) * 0.5
	_prev_dist = a.distance_to(b)
	_prev_angle = (b - a).angle()


func _update_multi() -> void:
	var a: Vector2 = _touches[_order[0]]
	var b: Vector2 = _touches[_order[1]]
	var center := (a + b) * 0.5
	var dist := a.distance_to(b)
	var angle := (b - a).angle()
	if center != _prev_center:
		pan_requested.emit(center - _prev_center)
	if _prev_dist > 1.0 and dist > 1.0 and not is_equal_approx(dist, _prev_dist):
		zoom_requested.emit(dist / _prev_dist, center)
	_emit_rotation(wrapf(angle - _prev_angle, -PI, PI), center)
	_prev_center = center
	_prev_dist = dist
	_prev_angle = angle


func _emit_rotation(delta_angle: float, center: Vector2) -> void:
	if _rot_active:
		if delta_angle != 0.0:
			rotate_requested.emit(delta_angle, center)
		return
	_rot_accum += delta_angle
	if absf(_rot_accum) >= rotate_threshold_rad:
		_rot_active = true
		rotate_requested.emit(_rot_accum - signf(_rot_accum) * rotate_threshold_rad, center)
