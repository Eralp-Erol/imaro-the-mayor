class_name TopBar
extends PanelContainer
## Üst şerit (L1, ux-layout §2): zaman kontrolü | tarih | para | (ölçek göstergesi: kamera ölçek olayı
## gelince) | gündem.
## Her öğe yalnız gerçek sim verisinden:
##   tarih  <- ClockView.tick (+ UiConfig takvim eşlemesi, yer tutucu)      para <- BudgetView.balance (+ ¤
##   yapılandırma)
##   hız    <- ClockView.speed/available_speeds
## Veri yoksa öğe GİZLİ (sahte 0 yok). MOCK iken tarih ve paranın yanında MOCK rozeti.

signal speed_chosen(level: int)
signal agenda_pressed

var time_controls: TimeControls = null
var agenda: AgendaBadge = null

var _date: Label = null
var _money: Label = null
var _money_caption: Label = null
var _date_badge: MockBadge = null
var _money_badge: MockBadge = null
var _money_box: HBoxContainer = null
var _date_box: HBoxContainer = null
var _row_a: HBoxContainer = null
var _row_b: HBoxContainer = null
var _spacer: Control = null
var _wrapped: bool = false


static func create(ctx: UiContext) -> TopBar:
	var bar := TopBar.new()
	bar.theme_type_variation = UiTheme.V_HUD_BAR
	bar.mouse_filter = Control.MOUSE_FILTER_STOP
	var stack := VBoxContainer.new()
	bar.add_child(stack)
	bar._row_a = HBoxContainer.new()
	bar._row_a.add_theme_constant_override(&"separation", int(ctx.spacing() * 2.0))
	stack.add_child(bar._row_a)
	bar._row_b = HBoxContainer.new()
	bar._row_b.add_theme_constant_override(&"separation", int(ctx.spacing() * 2.0))
	stack.add_child(bar._row_b)
	bar.time_controls = TimeControls.create(ctx)
	bar.time_controls.speed_chosen.connect(bar.speed_chosen.emit)
	bar._date_box = HBoxContainer.new()
	bar._date = UiFactory.label("")
	bar._date_box.add_child(bar._date)
	bar._date_badge = MockBadge.create()
	bar._date_box.add_child(bar._date_badge)
	bar._money_box = HBoxContainer.new()
	bar._money_caption = UiFactory.label(UiText.t(&"budget.balance"), UiTheme.V_LABEL_MUTED)
	bar._money_box.add_child(bar._money_caption)
	bar._money = UiFactory.label("")
	bar._money_box.add_child(bar._money)
	bar._money_badge = MockBadge.create()
	bar._money_box.add_child(bar._money_badge)
	bar._spacer = UiFactory.spacer()
	bar.agenda = AgendaBadge.create(ctx)
	bar.agenda.pressed.connect(bar.agenda_pressed.emit)
	bar._arrange(false)
	return bar


## Tek satırda gereken asgari genişlik (düzen kararı için; düğümleri yeniden dizmez).
func single_row_min_width() -> float:
	var parts: Array[Control] = [time_controls, _date_box, _money_box]
	if agenda.visible:
		parts.append(agenda)
	var sep := float(_row_a.get_theme_constant(&"separation"))
	var total := get_theme_stylebox(&"panel").get_minimum_size().x
	for c in parts:
		if c.visible:
			total += c.get_combined_minimum_size().x + sep
	return total


## Dar çerçevede (dikey iPad) tarih/para ikinci satıra iner; yüksekliği `get_combined_minimum_size().y` verir.
func set_wrapped(wrapped: bool) -> void:
	if wrapped != _wrapped:
		_arrange(wrapped)


func is_wrapped() -> bool:
	return _wrapped


func _arrange(wrapped: bool) -> void:
	_wrapped = wrapped
	for c: Control in [time_controls, _date_box, _money_box, _spacer, agenda]:
		if c.get_parent() != null:
			c.get_parent().remove_child(c)
	_row_a.add_child(time_controls)
	if wrapped:
		_row_a.add_child(_spacer)
		_row_a.add_child(agenda)
		_row_b.add_child(_date_box)
		_row_b.add_child(_money_box)
	else:
		_row_a.add_child(_date_box)
		_row_a.add_child(_money_box)
		_row_a.add_child(_spacer)
		_row_a.add_child(agenda)
	_row_b.visible = wrapped


func update_from(snapshot: SimSnapshot, facade: SimFacade) -> void:
	time_controls.update_from(snapshot.clock)
	var dpy := UiConfig.days_per_year()
	var tick := snapshot.clock.tick
	_date.text = UiText.t(&"clock.date_ingame", {"year": tick / dpy + 1, "day": tick % dpy + 1})
	_date_badge.apply_facade(facade)
	# Bütçe dönemi yoksa (sim henüz bütçe kurmadı) para gizli: sahte 0 gösterilmez.
	var has_budget := snapshot.budget.period > 0 or not snapshot.budget.lines.is_empty()
	_money_box.visible = has_budget
	if has_budget:
		_money.text = UiText.money(snapshot.budget.balance)
		_money_badge.apply_facade(facade)


func date_text() -> String:
	return _date.text


func money_text() -> String:
	return _money.text if _money_box.visible else ""


func money_visible() -> bool:
	return _money_box.visible


func mock_badges_visible() -> int:
	var n := 0
	for b: MockBadge in [_date_badge, _money_badge]:
		if b.is_visible_in_tree():
			n += 1
	return n
