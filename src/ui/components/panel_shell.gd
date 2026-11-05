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
## Çekmece kipi (D-021): başlık şeridi parmakla sürüklenir. `dragged` canlı Y farkı (negatif = yukarı), `drag_ended`
## bırakma hızı (px/sn, negatif = yukarı); `step_requested` ok düğmesi (+1 yukarı çek, -1 aşağı it).
signal drawer_drag_started
signal drawer_dragged(delta_y: float)
signal drawer_drag_ended(velocity_y: float)
signal drawer_step_requested(direction: int)

## Sürüklemeyi başlatmayan hareket (px): dokunuşun küçük titremesi sürükleme sayılmaz.
const DRAG_SLOP := 4.0
## Hız örneği için en kısa aralık (sn); daha sık olaylar tek örneğe katılır.
const VELOCITY_WINDOW := 0.02

var pinned: bool = false
var state_view: StateView = null
## Çekmece parçaları (dokunmatik): tutamaç, "Yukarı çek"/"Aşağı it" ok düğmeleri, kaydırma dışı altlık.
var grip: Control = null
var drawer_up: Button = null
var drawer_down: Button = null
var footer_box: VBoxContainer = null

var _ctx: UiContext = null
var _title: Label = null
var _pin: Button = null
var _close: Button = null
var _expand: Button = null
var _scroll: ScrollContainer = null
var _root: VBoxContainer = null
var _header: HBoxContainer = null
var _content: Control = null
var _drawer: bool = false
var _drawer_state: int = DrawerModel.State.HALF
var _dragging: bool = false
var _drag_pressed: bool = false
var _drag_travel: float = 0.0
var _vel_last_y: float = 0.0
var _vel_last_t: float = 0.0
var _velocity: float = 0.0


static func create(ctx: UiContext) -> PanelShell:
	var p := PanelShell.new()
	p._ctx = ctx
	p.theme_type_variation = UiTheme.V_PANEL_CARD
	var root := VBoxContainer.new()
	p._root = root
	p.add_child(root)
	var header := HBoxContainer.new()
	p._header = header
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
	p.grip = DrawerGrip.new()
	p.grip.custom_minimum_size = Vector2(0.0, ctx.px(14.0) if ctx.is_touch() else 0.0)
	p.grip.visible = false
	root.add_child(p.grip)
	root.move_child(p.grip, 0)
	p._scroll = ScrollContainer.new()
	p._scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	p._scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(p._scroll)
	p.state_view = StateView.create(ctx)
	p.state_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p._scroll.add_child(p.state_view)
	p.footer_box = VBoxContainer.new()
	p.footer_box.visible = false
	root.add_child(p.footer_box)
	return p


## Çekmece kipi (yalnız dokunmatik profilde, `HudRoot` açar): tutamaç + ok düğmeleri görünür, başlık şeridi sürüklenir.
func set_drawer(on: bool) -> void:
	_drawer = on and _ctx != null and _ctx.is_touch()
	grip.visible = _drawer
	clip_contents = _drawer
	z_index = 4 if _drawer else 0   # yüzen kartların (ipucu, bildirim) üstünde: tutamaç/başlık örtülmesin
	if _drawer and drawer_up == null:
		drawer_up = UiFactory.button(_ctx, UiText.t(&"panel.drawer_up"), false)
		drawer_up.tooltip_text = UiText.t(&"a11y.drawer_up")
		drawer_up.pressed.connect(func() -> void: drawer_step_requested.emit(1))
		drawer_down = UiFactory.button(_ctx, UiText.t(&"panel.drawer_down"), false)
		drawer_down.tooltip_text = UiText.t(&"a11y.drawer_down")
		drawer_down.pressed.connect(func() -> void: drawer_step_requested.emit(-1))
		_header.add_child(drawer_up)
		_header.add_child(drawer_down)
		_header.move_child(drawer_up, _close.get_index())
		_header.move_child(drawer_down, _close.get_index())
		for c: Control in [grip, _header]:
			c.mouse_filter = Control.MOUSE_FILTER_STOP
			c.gui_input.connect(_on_drag_input)
	if drawer_up != null:
		drawer_up.visible = _drawer
		drawer_down.visible = _drawer
	set_drawer_state(_drawer_state)


func content_node() -> Control:
	return _content


func is_drawer() -> bool:
	return _drawer


func set_drawer_state(state: int) -> void:
	_drawer_state = state
	if not _drawer:
		_scroll.visible = true
		footer_box.visible = false
		return
	var closed := state == DrawerModel.State.CLOSED
	_scroll.visible = not closed
	footer_box.visible = not closed and footer_box.get_child_count() > 0
	drawer_up.visible = DrawerModel.can_go_up(state)
	drawer_down.visible = DrawerModel.can_go_down(state)
	_expand.visible = false


## KAPALI konumda kabuğun gerçek asgari yüksekliği (tutamaç + başlık + dolgu); yerleşim bundan küçük vermez.
func drawer_peek_height() -> float:
	var style := get_theme_stylebox("panel")
	var pad := style.get_minimum_size().y if style != null else 0.0
	var sep := float(_root.get_theme_constant("separation"))
	return pad + grip.custom_minimum_size.y + sep + _header.get_combined_minimum_size().y + 2.0


## İçeriğin yapışık eylem alanını (`FlowPanel.enable_sticky_footer()`) çekmece altlığına alır: kaydırma alanı
## dışında, her zaman görünür ("Planı sun").
func adopt_footer(footer: Control) -> void:
	if footer.get_parent() != null:
		footer.get_parent().remove_child(footer)
	footer_box.add_child(footer)
	set_drawer_state(_drawer_state)


## İçeriğe sığan yükseklik (başlık + içerik + kabuk dolgusu). Yan panel yüksekliği buna uyar (boş alt yarı yok);
## tavan çağıranda (ekran yüksekliği), taşarsa içerik kaydırılır.
func content_height() -> float:
	var style := get_theme_stylebox("panel")
	var pad := style.get_minimum_size().y if style != null else 0.0
	var sep := float(_root.get_theme_constant("separation"))
	return pad + _header.get_combined_minimum_size().y + sep + state_view.get_combined_minimum_size().y + 4.0


func scroll_view_rect() -> Rect2:
	return _scroll.get_global_rect()


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
	_content = content
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


## Başlık şeridi/tutamaç sürükleme (fare veya parmak; dokunma Godot'da fareye çevrilir). Düğmeler kendi olaylarını
## tüketir, şerit yalnız boş alandaki basışı alır.
func _on_drag_input(event: InputEvent) -> void:
	if not _drawer:
		return
	var button := event as InputEventMouseButton
	if button != null and button.button_index == MOUSE_BUTTON_LEFT:
		if button.pressed:
			_drag_pressed = true
			_dragging = false
			_drag_travel = 0.0
			_velocity = 0.0
			_vel_last_y = button.global_position.y
			_vel_last_t = Time.get_ticks_usec() / 1000000.0
		elif _drag_pressed:
			_drag_pressed = false
			if _dragging:
				_dragging = false
				drawer_drag_ended.emit(_velocity)
		accept_event()
		return
	var motion := event as InputEventMouseMotion
	if motion != null and _drag_pressed:
		_drag_travel += absf(motion.relative.y)
		if not _dragging and _drag_travel >= DRAG_SLOP:
			_dragging = true
			drawer_drag_started.emit()
		if _dragging:
			drawer_dragged.emit(motion.relative.y)
			var now := Time.get_ticks_usec() / 1000000.0
			if now - _vel_last_t >= VELOCITY_WINDOW:
				_velocity = (motion.global_position.y - _vel_last_y) / (now - _vel_last_t)
				_vel_last_y = motion.global_position.y
				_vel_last_t = now
		accept_event()


func _on_expand_toggled(on: bool) -> void:
	_expand.text = UiText.t(&"panel.collapse" if on else &"panel.expand")
	expand_toggled.emit(on)


func _on_pin_toggled(on: bool) -> void:
	pinned = on
	_pin.text = UiText.t(&"panel.unpin") if on else UiText.t(&"panel.pin")
	pinned_changed.emit(on)
