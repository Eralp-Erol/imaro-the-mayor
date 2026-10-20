class_name UiSafeArea
extends MarginContainer
## Güvenli alan konteyneri (ux-layout-v0 §3.1): tüm L1/L2 köklerini sarar. İç boşluk
## `UiContext.frame_insets()`.
## Gerçek cihazda ekran güvenli alanı `DisplayServer.get_display_safe_area()` ile okunur (yalnız dokunmatik
## profil);
## önizlemede `simulated` ile elle verilir. Yeniden hesap: pencere boyutu/yön değişince
## (`NOTIFICATION_WM_SIZE_CHANGED`).

## Önizleme: (sol, üst, sağ, alt) mantıksal birim. Sıfır vektör = simülasyon yok.
var simulated: Vector4 = Vector4.ZERO

var _ctx: UiContext = null


## Saf hesap (test edilebilir): ekranın güvenli dikdörtgeni → pencere koordinatlarında iç boşluklar (sol,
## üst, sağ, alt).
## `screen` ve `window` piksel; pencere ekranı kaplıyorsa oran 1'dir. Güvenli alan ekrandan büyükse boşluk 0.
static func insets_from(safe: Rect2i, screen: Vector2i, window: Vector2i) -> Vector4:
	if screen.x <= 0 or screen.y <= 0 or safe.size.x <= 0 or safe.size.y <= 0:
		return Vector4.ZERO
	var sx := float(window.x) / float(screen.x)
	var sy := float(window.y) / float(screen.y)
	var left := maxf(0.0, float(safe.position.x)) * sx
	var top := maxf(0.0, float(safe.position.y)) * sy
	var right := maxf(0.0, float(screen.x - safe.end.x)) * sx
	var bottom := maxf(0.0, float(screen.y - safe.end.y)) * sy
	return Vector4(left, top, right, bottom)


func setup(ctx: UiContext) -> void:
	_ctx = ctx
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	refresh()


func refresh() -> void:
	if _ctx == null:
		return
	_ctx.safe_insets = _current_insets()
	var ins := _ctx.frame_insets()
	add_theme_constant_override(&"margin_left", int(ins.x))
	add_theme_constant_override(&"margin_top", int(ins.y))
	add_theme_constant_override(&"margin_right", int(ins.z))
	add_theme_constant_override(&"margin_bottom", int(ins.w))


func _current_insets() -> Vector4:
	if simulated != Vector4.ZERO:
		return simulated
	if _ctx == null or not _ctx.is_touch():
		return Vector4.ZERO
	var window := get_window()
	if window == null:
		return Vector4.ZERO
	var screen := DisplayServer.screen_get_size(window.current_screen)
	return insets_from(DisplayServer.get_display_safe_area(), screen, window.size)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_SIZE_CHANGED or what == NOTIFICATION_RESIZED:
		refresh()
