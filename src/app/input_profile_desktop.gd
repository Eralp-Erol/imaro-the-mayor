class_name DesktopInputProfile
extends InputProfile
## Masaüstü girdi profili (fare + klavye + macOS trackpad), ADR-0004 §Karar 2. Sözleşme: `InputProfile`.
##
## Fare: sol tık = seç; sol sürükle (eşik sonrası) = pan; sağ tık veya Ctrl+sol tık (macOS bağlam tıklaması) = bağlam;
## orta tuş sürükle (yatay) = döndür; tekerlek = imleç noktasında yakınlaş/uzaklaş.
## Trackpad (macOS): iki parmak kaydırma (`InputEventPanGesture`) = pan; kıstırma (`InputEventMagnifyGesture`) = zoom.
## Klavye (ortak): WASD/oklar pan, Q/E döndür, PageUp/PageDown zoom, Boşluk duraklat, =/- hız, Esc iptal.
## Dokunma olayları (`InputEventScreenTouch/Drag`) YOK SAYILIR.
##
## DOĞRULANMADI (cihaz yok): trackpad kaydırma/kıstırma işaret ve ölçekleri gerçek trackpad ile denenmedi;
## `trackpad_pan_px` / `invert_trackpad_pan` ayarlanabilir bırakıldı.

## Tekerlek adımı çarpanı (tek çentik).
var wheel_zoom_step: float = 1.1
## Orta tuş yatay sürükleme: piksel başına radyan (saat yönü pozitif).
var rotate_rad_per_px: float = 0.008
## PanGesture birimi başına pan pikseli.
var trackpad_pan_px: float = 12.0
## true ise PanGesture yönü ters çevrilir (doğal kaydırma tercihi).
var invert_trackpad_pan: bool = false

var _left_down: bool = false
var _left_origin: Vector2 = Vector2.ZERO
var _left_last: Vector2 = Vector2.ZERO
var _left_dragging: bool = false
var _middle_down: bool = false


func _init() -> void:
	profile_name = InputProfile.PROFILE_DESKTOP
	supports_hover = true


func _handle_pointer_event(event: InputEvent) -> bool:
	var button := event as InputEventMouseButton
	if button != null:
		return _on_button(button)
	var motion := event as InputEventMouseMotion
	if motion != null:
		return _on_motion(motion)
	var magnify := event as InputEventMagnifyGesture
	if magnify != null:
		zoom_requested.emit(magnify.factor, magnify.position)
		return true
	var pan := event as InputEventPanGesture
	if pan != null:
		var sign_factor := 1.0 if invert_trackpad_pan else -1.0
		pan_requested.emit(pan.delta * trackpad_pan_px * sign_factor)
		return true
	return false


func _reset_pointer() -> void:
	_left_down = false
	_left_dragging = false
	_middle_down = false


func _on_button(event: InputEventMouseButton) -> bool:
	match event.button_index:
		MOUSE_BUTTON_LEFT:
			return _on_left(event)
		MOUSE_BUTTON_RIGHT:
			if event.pressed:
				context_requested.emit(event.position)
			return event.pressed
		MOUSE_BUTTON_MIDDLE:
			_middle_down = event.pressed
			return true
		MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN:
			if event.pressed:
				var amount := event.factor if event.factor > 0.0 else 1.0
				var factor := pow(wheel_zoom_step, amount)
				zoom_requested.emit(factor if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / factor, event.position)
			return event.pressed
	return false


func _on_left(event: InputEventMouseButton) -> bool:
	if event.pressed:
		if event.ctrl_pressed:
			context_requested.emit(event.position)
			return true
		_left_down = true
		_left_dragging = false
		_left_origin = event.position
		_left_last = event.position
		return true
	if not _left_down:
		return false
	var was_drag := _left_dragging
	_left_down = false
	_left_dragging = false
	if not was_drag:
		select_requested.emit(event.position)
	return true


func _on_motion(event: InputEventMouseMotion) -> bool:
	if _middle_down:
		rotate_requested.emit(event.relative.x * rotate_rad_per_px, event.position)
		return true
	if not _left_down:
		return false
	if not _left_dragging:
		if event.position.distance_to(_left_origin) <= drag_slop_px:
			return true
		_left_dragging = true
		_left_last = _left_origin  # eşik aşılınca birikmiş yer değiştirme tek seferde pan olur
	pan_requested.emit(event.position - _left_last)
	_left_last = event.position
	return true
