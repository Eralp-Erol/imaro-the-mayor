class_name HudRoot
extends Control
## HUD kökü (T-019): bir `SimFacade` + bir `PlatformProfile` ile çalışır; UI yalnız `SimFacade` tipine
## bağlıdır
## (gerçek sim'e geçişte kod değişmez). Her kare değil, `current_tick()`/`last_event_seq()`/`speed()`
## DEĞİŞİNCE
## snapshot okunur (ADR-0005 §9). `facade.is_mock()` -> MOCK bandı + rozetler (kodla sabitlenmez).
##
## Girdi: `PlatformProfile.create_input_profile()` ile `InputProfile`; HUD'un fiilleri (Boşluk = duraklat, +/- =
## hız,
## Esc = paneli kapat [sabit değilse]) buradadır; `select/pan/zoom` fiilleri dünyaya (kamera/harita) aittir ve
## `input` üzerinden dışarıdan bağlanır. `_unhandled_input` kullanılır: Control olayı önce tüketir (UI
## dünyadan önce).
##
## Yerleşim `HudLayout` (saf hesap) ile, güvenli alan `UiSafeArea` ile. Profil değişince (`apply_profile`) HUD
## yeniden kurulur
## ve açık panel aynı kurucu (`builder`) ile yeniden üretilir.

signal tool_selected(tool_id: StringName)
signal mode_changed(mode_id: StringName)
signal panel_closed(panel_id: StringName)
signal reason_requested(event: SimEvent)
signal agenda_requested
signal speed_changed(level: int)
signal layout_changed
## `refresh()` snapshot'ı yeniledi (tick/olay/hız değişti) ve sırada işlenmemiş yeni olaylar (varsa) şerite itildi.
signal refreshed
signal events_received(events: Array[SimEvent])

var ctx: UiContext = null
var input: InputProfile = null
var facade: SimFacade = null
var top_bar: TopBar = null
var banner: MockBanner = null
var strip: NotificationStrip = null
var toolbar: ModeToolbar = null
var panel: PanelShell = null
var layout: HudLayout = null
## Önizleme: simüle güvenli alan (sol, üst, sağ, alt); sıfır = cihazdan oku.
var simulated_safe: Vector4 = Vector4.ZERO
## Alt sayfa (dikey dokunmatik) genişletildi mi: oyuncu seçimidir, paneller arası ve yeniden kurmalarda kalır.
var sheet_expanded: bool = false

var _platform: PlatformProfile = null
var _safe: UiSafeArea = null
var _frame: Control = null
var _panel_id: StringName = &""
var _panel_title_key: StringName = &""
var _panel_builder: Callable = Callable()
var _seen_tick: int = -1
var _seen_seq: int = -1
var _seen_speed: int = -1
var _event_cursor: int = 0
var _last_snapshot: SimSnapshot = null
var _last_running_speed: int = SimFacade.SPEED_NORMAL
var _restore_pin: bool = false
var _relayout_queued: bool = false


func setup(facade_in: SimFacade, platform: PlatformProfile) -> void:
	facade = facade_in
	apply_profile(platform)


## Profil değiştirir (önizleme: masaüstü <-> dokunmatik) ve HUD'u yeniden kurar. Olay imleci korunur.
func apply_profile(platform: PlatformProfile) -> void:
	_platform = platform
	if panel != null:
		_restore_pin = panel.pinned
	ctx = UiContext.from_profile(platform)
	input = platform.create_input_profile()
	# Dokunma/sürükleme eşiği ui_scale ile ölçeklenir (ux-layout §3.4: tap slop 24, masaüstü 8).
	input.drag_slop_px = ctx.px(24.0 if ctx.is_touch() else 8.0)
	input.pause_toggle_requested.connect(_on_pause_toggle)
	input.speed_step_requested.connect(_on_speed_step)
	input.cancel_requested.connect(_on_cancel)
	_build()
	_seen_tick = -1
	refresh()
	if _panel_id != &"":
		_reopen_panel()


func is_panel_open() -> bool:
	return panel != null and panel.visible


func panel_id() -> StringName:
	return _panel_id


## Panel açar. `builder(ctx) -> Control` içeriği üretir (profil değişince yeniden çağrılır). Aynı kimlikse
## yerinde yeniler.
func open_panel(panel_id_in: StringName, title_key: StringName, builder: Callable) -> void:
	_panel_id = panel_id_in
	_panel_title_key = title_key
	_panel_builder = builder
	_reopen_panel()


## Dolaylı kapatma (Esc, seçim kalktı): sabit panel kapanmaz. Kapandıysa true.
func close_panel_soft() -> bool:
	if not is_panel_open():
		return false
	if panel.pinned:
		return false
	_close_panel()
	return true


func close_panel_hard() -> void:
	_close_panel()


func set_agenda(count: int, days_left: int, is_mock: bool) -> void:
	top_bar.agenda.set_data(count, days_left, is_mock)


## Facade değişimini (tick/olay/hız) yoklar; değiştiyse snapshot okuyup yüzeyi tazeler. Yoklama ucuzdur (üç
## tamsayı).
func poll() -> void:
	if facade == null:
		return
	if facade.current_tick() != _seen_tick or facade.last_event_seq() != _seen_seq or facade.speed() != _seen_speed:
		refresh()


func refresh() -> void:
	if facade == null or top_bar == null:
		return
	var snap := facade.snapshot()
	_last_snapshot = snap
	_seen_tick = snap.tick()
	_seen_seq = facade.last_event_seq()
	_seen_speed = facade.speed()
	if _seen_speed != SimFacade.SPEED_PAUSED:
		_last_running_speed = _seen_speed
	banner.apply_facade(facade)
	top_bar.update_from(snap, facade)
	var fresh := facade.events_since(_event_cursor)
	if not fresh.is_empty():
		_event_cursor = fresh[fresh.size() - 1].seq
		strip.push_events(fresh)
		events_received.emit(fresh)
	_relayout()
	refreshed.emit()


func snapshot() -> SimSnapshot:
	return _last_snapshot


func _process(_delta: float) -> void:
	if input != null:
		input.process(_delta)
	poll()


func _unhandled_input(event: InputEvent) -> void:
	if input != null and input.handle_event(event):
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and layout != null:
		_relayout()
	elif what == NOTIFICATION_WM_WINDOW_FOCUS_OUT and input != null:
		input.reset()


func _build() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	panel = null
	theme = UiTheme.build(ctx)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_safe = UiSafeArea.new()
	_safe.simulated = simulated_safe
	add_child(_safe)
	_safe.setup(ctx)
	_frame = Control.new()
	_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_safe.add_child(_frame)
	top_bar = TopBar.create(ctx)
	top_bar.speed_chosen.connect(_on_speed_chosen)
	top_bar.agenda_pressed.connect(agenda_requested.emit)
	_frame.add_child(top_bar)
	banner = MockBanner.create()
	_frame.add_child(banner)
	strip = NotificationStrip.create(ctx)
	strip.reason_requested.connect(reason_requested.emit)
	_frame.add_child(strip)
	toolbar = ModeToolbar.create(ctx)
	toolbar.mode_changed.connect(mode_changed.emit)
	toolbar.tool_selected.connect(tool_selected.emit)
	_frame.add_child(toolbar)
	_frame.resized.connect(_relayout)
	# Otomatik satır kaydıran etiketler içerik değişince asgari boyutu oynatır; yerleşim kare sonunda yeniden uygulanır.
	for c: Control in [top_bar, strip, toolbar]:
		c.minimum_size_changed.connect(_queue_relayout)


func _reopen_panel() -> void:
	if panel != null:
		_restore_pin = panel.pinned
		_frame.remove_child(panel)
		panel.queue_free()
		panel = null
	panel = PanelShell.create(ctx)
	panel.closed.connect(_close_panel)
	panel.expand_toggled.connect(_on_expand_toggled)
	panel.minimum_size_changed.connect(_queue_relayout)
	panel.set_title(UiText.t(_panel_title_key))
	panel.set_content(_panel_builder.call(ctx))
	_frame.add_child(panel)
	if _restore_pin:
		panel.pin_button().button_pressed = true
		_restore_pin = false
	_relayout()


func _close_panel() -> void:
	var closed_id := _panel_id
	if panel != null:
		_frame.remove_child(panel)
		panel.queue_free()
		panel = null
	_panel_id = &""
	_relayout()
	panel_closed.emit(closed_id)


func _queue_relayout() -> void:
	if not _relayout_queued:
		_relayout_queued = true
		_relayout_now.call_deferred()


func _relayout_now() -> void:
	_relayout_queued = false
	_relayout()


func _relayout() -> void:
	if ctx == null or _frame == null or toolbar == null:
		return
	_safe.refresh()
	var frame_size := ctx.frame_size(size)
	_frame.position = Vector2.ZERO
	_frame.size = frame_size
	top_bar.set_wrapped(top_bar.single_row_min_width() > frame_size.x)
	layout = HudLayout.compute(ctx, frame_size, is_panel_open(), banner.visible,
		top_bar.get_combined_minimum_size().y, sheet_expanded)
	toolbar.set_rows(layout.toolbar_rows)
	_place(top_bar, layout.top)
	if banner.visible:
		_place(banner, layout.banner)
	_place(strip, layout.notifications)
	_place(toolbar, layout.toolbar)
	if is_panel_open():
		panel.set_expand_available(layout.panel_mode == HudLayout.MODE_SHEET, sheet_expanded)
		_place(panel, layout.panel)
	layout_changed.emit()


## Dünya/harita için kalan serbest dikdörtgen (HudRoot yerel koordinatı): üst şerit/bant ile araç çubuğu
## arasında,
## panelin yanında. Kamera/harita çerçevesini buna göre kurar (panel haritayı gömmez).
func free_map_rect() -> Rect2:
	if layout == null:
		return Rect2(Vector2.ZERO, size)
	var ins := ctx.frame_insets()
	var origin := Vector2(ins.x, ins.y)
	var region := layout.map_region
	var bottom := layout.toolbar.position.y
	if is_panel_open() and layout.panel_mode == HudLayout.MODE_SHEET:
		bottom = layout.panel.position.y
	return Rect2(origin + region.position, Vector2(region.size.x, maxf(0.0, bottom - region.position.y)))


func _place(c: Control, rect: Rect2) -> void:
	c.position = rect.position
	# Yüksekliği 0 verilen öğeler içeriğine göre büyür (set_size en az içerik boyutuna kenetler).
	c.size = Vector2(rect.size.x, maxf(rect.size.y, 0.0))


func _on_expand_toggled(expanded: bool) -> void:
	sheet_expanded = expanded
	_relayout()


func _on_speed_chosen(level: int) -> void:
	if facade.set_speed(level):
		speed_changed.emit(level)
	refresh()


func _on_pause_toggle() -> void:
	var paused := facade.speed() == SimFacade.SPEED_PAUSED
	_on_speed_chosen(_resume_level() if paused else SimFacade.SPEED_PAUSED)


func _on_speed_step(direction: int) -> void:
	var levels := _ctx_levels()
	if levels.is_empty():
		return
	var idx := levels.find(facade.speed())
	if idx < 0:
		idx = 0
	_on_speed_chosen(levels[clampi(idx + direction, 0, levels.size() - 1)])


func _on_cancel() -> void:
	close_panel_soft()


func _ctx_levels() -> PackedInt32Array:
	var out := PackedInt32Array()
	for level in ctx.available_speeds(facade.available_speeds()):
		if level != SimFacade.SPEED_PAUSED:
			out.append(level)
	return out


func _resume_level() -> int:
	var levels := _ctx_levels()
	if levels.has(_last_running_speed):
		return _last_running_speed
	return levels[0] if not levels.is_empty() else SimFacade.SPEED_NORMAL
