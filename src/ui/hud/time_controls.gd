class_name TimeControls
extends HBoxContainer
## Zaman kontrolü (L1): Duraklat/Sürdür + hız basamakları. Basamaklar `ClockView.available_speeds` ile
## `PlatformProfile.max_game_speed` (UiContext.max_game_speed) kesişimidir. Hız sim durumu değildir; seçim
## `speed_chosen`
## sinyaliyle HudRoot'a gider, o `SimFacade.set_speed` çağırır. Seçili basamak dolgu + çerçeve + metin
## etiketiyle
## (yalnız renk değil) gösterilir.

signal speed_chosen(level: int)

var _ctx: UiContext = null
var _pause: Button = null
var _speed_buttons: Dictionary = {}  # int -> Button
var _status: Label = null
var _levels: PackedInt32Array = PackedInt32Array()
var _last_running: int = SimFacade.SPEED_NORMAL
var _current: int = SimFacade.SPEED_PAUSED
var _capped: bool = false


static func create(ctx: UiContext) -> TimeControls:
	var tc := TimeControls.new()
	tc._ctx = ctx
	tc._pause = UiFactory.button(ctx, UiText.t(&"clock.pause"), true, true)
	tc._pause.pressed.connect(tc._on_pause_pressed)
	tc.add_child(tc._pause)
	tc._status = UiFactory.label("", UiTheme.V_LABEL_MUTED)
	return tc


## Her güncellemede çağrılır; basamak kümesi değiştiyse düğmeleri yeniden kurar.
func update_from(clock: ClockView) -> void:
	var allowed := _ctx.available_speeds(clock.available_speeds)
	var running := PackedInt32Array()
	for level in allowed:
		if level != SimFacade.SPEED_PAUSED:
			running.append(level)
	_capped = false
	for level in clock.available_speeds:
		if level > _ctx.max_game_speed and level != SimFacade.SPEED_PAUSED:
			_capped = true
	if running != _levels:
		_rebuild(running)
	_current = clock.speed
	if clock.speed != SimFacade.SPEED_PAUSED:
		_last_running = clock.speed
	_pause.set_pressed_no_signal(clock.is_paused())
	_pause.text = UiText.t(&"clock.resume") if clock.is_paused() else UiText.t(&"clock.pause")
	for level: int in _speed_buttons:
		(_speed_buttons[level] as Button).set_pressed_no_signal(level == clock.speed)
	_status.text = UiText.t(&"clock.paused") if clock.is_paused() else UiText.t(&"clock.speed_label",
		{"n": clock.speed})
	var hint := UiText.t(&"clock.speed_capped", {"n": _ctx.max_game_speed}) if _capped else ""
	for level: int in _speed_buttons:
		(_speed_buttons[level] as Button).tooltip_text = hint
	_status.tooltip_text = hint


func status_label() -> Label:
	return _status


func pause_button() -> Button:
	return _pause


func speed_button(level: int) -> Button:
	return _speed_buttons.get(level) as Button


func shown_levels() -> PackedInt32Array:
	return _levels


func speed_capped_hint_visible() -> bool:
	return _capped


func _rebuild(running: PackedInt32Array) -> void:
	for level: int in _speed_buttons:
		var old: Button = _speed_buttons[level]
		remove_child(old)
		old.queue_free()
	_speed_buttons.clear()
	if _status.get_parent() == self:
		remove_child(_status)
	_levels = running
	for level in running:
		var key := StringName("clock.speed_%d" % level)
		var text := UiText.t(key) if UiText.has(key) else UiText.t(&"clock.speed_label", {"n": level})
		var b := UiFactory.button(_ctx, text, true, true)
		b.pressed.connect(_on_speed_pressed.bind(level))
		_speed_buttons[level] = b
		add_child(b)
	add_child(_status)


func _on_pause_pressed() -> void:
	# Duraklatılmışsa son çalışan basamağa dön; çalışıyorsa duraklat.
	speed_chosen.emit(_last_running if _current == SimFacade.SPEED_PAUSED else SimFacade.SPEED_PAUSED)


func _on_speed_pressed(level: int) -> void:
	speed_chosen.emit(level)
