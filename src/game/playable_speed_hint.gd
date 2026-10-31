class_name PlayableSpeedHint
extends PanelContainer
## Tek seferlik, kapatılabilir hız ipucu (T-043B C): oyuncunun yol onayı (`public_work.built`) ya da imar planı
## yürürlüğü
## (`parcel.changed` + `event.zoning.applied`) sonrası "Zamanı hızlandırarak sonucu izle". Gerçek sim olayından doğar;
## sahte sayı yok. İki düğme de gerçek iş yapar: "Hızlandır" bir üst hız basamağını seçer (yalnız zaman katmanı, sim
## durumu değil), "Kapat" ipucuyu kalıcı kapatır (`PlayableHintPrefs`). Hız zaten izinli en yüksek basamaktaysa ipucu
## gösterilmez (öneri boş olurdu). Oturumda en çok bir kez görünür; açıkken `HIDE_AFTER_S` sonra kendiliğinden gizlenir
## (kalıcı kapatma sayılmaz). Konum: HUD'un boş harita dikdörtgeninin sağ-üstü (bildirim şeridi sol %45'te).

signal dismissed

const HINT_ID := &"speed_after_road_or_plan"
const ZONING_APPLIED_KEY := &"event.zoning.applied"
const HIDE_AFTER_S := 30.0
const MARGIN := 12.0
const MAX_WIDTH := 460.0

var _hud: HudRoot = null
var _facade: SimFacade = null
var _prefs: PlayableHintPrefs = null
var _shown_once: bool = false
var _remaining: float = 0.0
var _label: Label = null
var _faster: Button = null
var _close: Button = null


static func attach(hud: HudRoot, facade: SimFacade, prefs: PlayableHintPrefs = null) -> PlayableSpeedHint:
	var h := PlayableSpeedHint.new()
	h._hud = hud
	h._facade = facade
	h._prefs = prefs if prefs != null else PlayableHintPrefs.create()
	h.name = "SpeedHint"
	h.visible = false
	h.z_index = 20
	h.mouse_filter = Control.MOUSE_FILTER_STOP
	h.set_process(false)
	var layer: Node = hud.get_parent()
	if layer == null:
		layer = hud
	layer.add_child(h)
	hud.events_received.connect(h._on_events)
	hud.layout_changed.connect(h._place)
	hud.speed_changed.connect(h._on_speed_changed)
	return h


## Yol onayı ya da plan yürürlüğü olayı mı? (Saf; testler doğrudan çağırır.)
static func is_trigger(event: SimEvent) -> bool:
	if event.kind == SimEvent.KIND_PUBLIC_WORK_BUILT:
		return true
	return event.kind == SimEvent.KIND_PARCEL_CHANGED and event.message_key == ZONING_APPLIED_KEY


func is_dismissed() -> bool:
	return _prefs.is_dismissed(HINT_ID)


## Gösterme koşulu: kapatılmamış, bu oturumda gösterilmemiş ve hızlanacak yer var (ya da duraklatılmış).
func should_show() -> bool:
	if _shown_once or is_dismissed():
		return false
	return _next_level() != _facade.speed()


func faster_button() -> Button:
	return _faster


func close_button() -> Button:
	return _close


func hint_text() -> String:
	return _label.text if _label != null else ""


## "Kapat": kalıcı kapatma.
func dismiss() -> void:
	_prefs.dismiss(HINT_ID)
	_shown_once = true
	_hide()
	dismissed.emit()


func _process(delta: float) -> void:
	_remaining -= delta
	if _remaining <= 0.0:
		_hide()  # kalıcı kapatma değil: yalnız bu görünüm kapanır


func _on_events(events: Array[SimEvent]) -> void:
	if _shown_once:
		return
	for e in events:
		if is_trigger(e):
			_show()
			return


func _show() -> void:
	if not should_show():
		return
	_shown_once = true
	_build()
	visible = true
	_remaining = HIDE_AFTER_S
	set_process(true)
	_place()


func _hide() -> void:
	visible = false
	set_process(false)


func _on_speed_changed(_level: int) -> void:
	# Oyuncu hızı kendisi değiştirdi: öneri yerine geldi, kalıcı kapat.
	if visible:
		dismiss()


func _on_faster_pressed() -> void:
	var level := _next_level()
	if level != _facade.speed() and _facade.set_speed(level):
		dismiss()


func _next_level() -> int:
	var max_level := _hud.ctx.max_game_speed if _hud.ctx != null else SimFacade.SPEED_FASTEST
	return PlayableTempo.faster_than(_facade.speed(), _facade.available_speeds(), max_level)


func _build() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	if _hud.theme != null:
		theme = _hud.theme
	var row := HBoxContainer.new()
	add_child(row)
	_label = UiFactory.label(UiText.t(&"tempo.hint"), &"", true)
	row.add_child(_label)
	var paused := _facade.speed() == SimFacade.SPEED_PAUSED
	_faster = UiFactory.button(_hud.ctx, UiText.t(&"clock.resume" if paused else &"tempo.hint_faster"), true)
	_faster.pressed.connect(_on_faster_pressed)
	row.add_child(_faster)
	_close = UiFactory.button(_hud.ctx, UiText.t(&"common.close"), false)
	_close.pressed.connect(dismiss)
	row.add_child(_close)


func _place() -> void:
	if not visible or _hud.layout == null:
		return
	var area := _hud.free_map_rect()
	var width := minf(MAX_WIDTH, maxf(0.0, area.size.x * 0.4))
	custom_minimum_size = Vector2(width, 0.0)
	var h := get_combined_minimum_size().y
	size = Vector2(width, h)
	position = Vector2(area.end.x - width - MARGIN, area.position.y + MARGIN)
