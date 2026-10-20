class_name PanelShell
extends PanelContainer
## L2 panel kabuğu (ux-ia §2): başlık + Sabitle + Kapat ve takılabilir içerik yuvası (`StateView`). Nedensellik
## paneli
## (T-021), karar akışları (T-022), denetçi gibi içerikler `set_content` ile takılır. Yerleşim (yan panel /
## alt sayfa)
## `HudLayout` tarafından verilir; kabuk kendi konumunu bilmez.
## Sabitleme: sabitlenmiş panel Esc / seçim temizleme gibi DOLAYLI kapanmalarda kapanmaz; yalnız Kapat ile
## kapanır.
## Etiketler her zaman görünür (simge-tek düğme yok); dokunmatikte düğmeler ≥ hedef boyutu.

signal closed
signal pinned_changed(pinned: bool)
## Alt sayfa kipinde "Genişlet/Küçült" düğmesi (dikey dokunmatik; yalnız yerleşim kipi sayfaysa görünür).
signal expand_toggled(expanded: bool)

var pinned: bool = false
var state_view: StateView = null

var _ctx: UiContext = null
var _title: Label = null
var _pin: Button = null
var _close: Button = null
var _expand: Button = null
var _scroll: ScrollContainer = null


static func create(ctx: UiContext) -> PanelShell:
	var p := PanelShell.new()
	p._ctx = ctx
	p.theme_type_variation = UiTheme.V_PANEL_CARD
	var root := VBoxContainer.new()
	p.add_child(root)
	var header := HBoxContainer.new()
	root.add_child(header)
	p._title = UiFactory.label("", UiTheme.V_LABEL_TITLE)
	p._title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p._title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	header.add_child(p._title)
	p._pin = UiFactory.button(ctx, UiText.t(&"panel.pin"), false, true)
	p._pin.tooltip_text = UiText.t(&"a11y.pinned")
	p._pin.toggled.connect(p._on_pin_toggled)
	header.add_child(p._pin)
	p._expand = UiFactory.button(ctx, UiText.t(&"panel.expand"), false, true)
	p._expand.visible = false
	p._expand.toggled.connect(p._on_expand_toggled)
	header.add_child(p._expand)
	p._close = UiFactory.button(ctx, UiText.t(&"common.close"), true)
	p._close.tooltip_text = UiText.t(&"a11y.close_panel")
	p._close.pressed.connect(p.request_close)
	header.add_child(p._close)
	p._scroll = ScrollContainer.new()
	p._scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	p._scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(p._scroll)
	p.state_view = StateView.create(ctx)
	p.state_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p._scroll.add_child(p.state_view)
	return p


func set_title(text: String) -> void:
	_title.text = text


## Genişlet düğmesi yalnız alt sayfa kipinde görünür; durum HudRoot'tadır (paneller arası kalıcı).
func set_expand_available(available: bool, expanded: bool) -> void:
	_expand.visible = available
	_expand.set_pressed_no_signal(expanded)
	_expand.text = UiText.t(&"panel.collapse" if expanded else &"panel.expand")
	_expand.tooltip_text = UiText.t(&"a11y.collapse_sheet" if expanded else &"a11y.expand_sheet")


func expand_button() -> Button:
	return _expand


func title_text() -> String:
	return _title.text


func set_content(content: Control) -> void:
	state_view.set_content(content)
	state_view.show_normal()


## Kullanıcı eylemi olan kapatma (düğme): sabit olsa da kapanır.
func request_close() -> void:
	closed.emit()


## Dolaylı kapanma (Esc, seçimin kalkması): sabitlenmişse kapanmaz. Kapandıysa true.
func request_soft_close() -> bool:
	if pinned:
		return false
	closed.emit()
	return true


func close_button() -> Button:
	return _close


func pin_button() -> Button:
	return _pin


func _on_expand_toggled(on: bool) -> void:
	_expand.text = UiText.t(&"panel.collapse" if on else &"panel.expand")
	expand_toggled.emit(on)


func _on_pin_toggled(on: bool) -> void:
	pinned = on
	_pin.text = UiText.t(&"panel.unpin") if on else UiText.t(&"panel.pin")
	pinned_changed.emit(on)
