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
## Kartın asgari genişliği: düğmeler etiketin ALTINA dizilir; sığmazsa kart bildirim sütununun altına iner.
const MIN_WIDTH := 220.0

var _hud: HudRoot = null
var _facade: SimFacade = null
var _prefs: PlayableHintPrefs = null
var _shown_once: bool = false
var _remaining: float = 0.0
var _label: Label = null
var _faster: Button = null
var _close: Button = null
var _strip_rect: Rect2 = Rect2()


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


func hint_label() -> Label:
	return _label


func hint_text() -> String:
	return _label.text if _label != null else ""


## "Kapat": kalıcı kapatma.
func dismiss() -> void:
	_prefs.dismiss(HINT_ID)
	_shown_once = true
	_hide()
	dismissed.emit()


func _process(delta: float) -> void:
	# Bildirim şeridi olaylarla büyüyüp küçülür; yalnız "şeridin altına in" kipinde konum onun yüksekliğine bağlıdır.
	var strip_rect := Rect2(_hud.strip.position, _hud.strip.size)
	if strip_rect != _strip_rect:
		_strip_rect = strip_rect
		_place()
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
	var col := VBoxContainer.new()
	add_child(col)
	_label = UiFactory.label(UiText.t(&"tempo.hint"), &"", true)
	col.add_child(_label)
	var row := HBoxContainer.new()
	col.add_child(row)
	var paused := _facade.speed() == SimFacade.SPEED_PAUSED
	_faster = UiFactory.button(_hud.ctx, UiText.t(&"clock.resume" if paused else &"tempo.hint_faster"), true)
	_faster.pressed.connect(_on_faster_pressed)
	row.add_child(_faster)
	_close = UiFactory.button(_hud.ctx, UiText.t(&"common.close"), false)
	_close.pressed.connect(dismiss)
	row.add_child(_close)


## Kök neden (iPad 1024x768): eski kart etiket + iki düğmeyi TEK satıra koyuyor ve genişliği harita alanının %0.4'ü
## (~250 px) tutuyordu; düğmelerin asgari genişliği toplamı bunu aştığı için sarmalı etiket 1 harf genişliğine
## ezildi. Şimdi etiket üstte, düğmeler altta; genişlik bildirim sütununun SAĞINDAki boşluktan hesaplanır, MIN_WIDTH
## sığmazsa kart bildirim şeridinin ALTINA iner (çakışma yok).
func _place() -> void:
	if not visible or _hud.layout == null:
		return
	var area := _hud.free_map_rect()
	var notif_end := _hud.layout.notifications.end.x
	var free_right := area.end.x - MARGIN - (notif_end + MARGIN)
	var width := minf(MAX_WIDTH, free_right)
	var below_strip := width < MIN_WIDTH
	if below_strip:
		width = minf(MAX_WIDTH, maxf(0.0, area.size.x - 2.0 * MARGIN))
	custom_minimum_size = Vector2(width, 0.0)
	var inner := width - get_theme_stylebox(&"panel").get_minimum_size().x
	# Sarmalı etiketin asgari yüksekliği genişliğe bağlıdır ve konteyner yerleşimi bir kare geç yetişir; etiketi gerçek
	# genişliğe şimdi oturtup kartı ilk karede doğru boyda kuruyoruz.
	_label.custom_minimum_size = Vector2(maxf(inner, 0.0), 0.0)
	_label.size = Vector2(maxf(inner, 0.0), 0.0)
	size = Vector2(width, 0.0)
	size = Vector2(width, get_combined_minimum_size().y)
	var y := area.position.y + MARGIN
	if below_strip:
		y = maxf(y, _hud.strip.position.y + _hud.strip.size.y + MARGIN)
		y = minf(y, maxf(area.position.y, area.end.y - size.y - MARGIN))
	position = Vector2(area.end.x - width - MARGIN, y)
