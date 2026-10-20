class_name NotificationStrip
extends VBoxContainer
## Bildirim şeridi (L1, sol-üst): `SimEvent` akışından SON birkaç olay. Boşsa görünmez. Kendiliğinden
## kaybolmaz
## (erişilebilirlik): yalnız yeni olay gelince en eskisi şeritten çıkar (geçmişte kalır).
## Metin: `UiText.event_text` (sim anahtar+argüman verir, UI çevirir). Gerekçe kaydı varsa "Nedenini gör"
## (SIM-12).
## Nedensellik paneli (`ReasonPanel`, T-021) sahibi tarafından açılır; burada yalnız `reason_requested` sinyali.

signal reason_requested(event: SimEvent)

var _ctx: UiContext = null
var _max_rows: int = 3
var _events: Array[SimEvent] = []


static func create(ctx: UiContext) -> NotificationStrip:
	var s := NotificationStrip.new()
	s._ctx = ctx
	s._max_rows = maxi(1, int(UiConfig.value("hud.notification_rows", 3)))
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	s.visible = false
	return s


func push_events(events: Array[SimEvent]) -> void:
	if events.is_empty():
		return
	_events.append_array(events)
	while _events.size() > _max_rows:
		_events.pop_front()
	_rebuild()


func clear() -> void:
	_events.clear()
	_rebuild()


func row_count() -> int:
	return _events.size()


func row_texts() -> PackedStringArray:
	var out := PackedStringArray()
	for e in _events:
		out.append(UiText.event_text(e))
	return out


func _rebuild() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	visible = not _events.is_empty()
	# Yeni olay üstte.
	for i in range(_events.size() - 1, -1, -1):
		add_child(_make_row(_events[i]))


func _make_row(event: SimEvent) -> Control:
	var row := PanelContainer.new()
	row.theme_type_variation = UiTheme.V_HUD_BAR
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	var box := HBoxContainer.new()
	row.add_child(box)
	var text := UiFactory.label(UiText.event_text(event), &"", true)
	box.add_child(text)
	# Gerekçe kaydı olan olay ya da reddedilen komut ("neden kabul edilmedi", SIM-12).
	if not event.reason_ids.is_empty() or event.kind == SimEvent.KIND_COMMAND_REJECTED:
		var why := UiFactory.button(_ctx, UiText.t(&"alert.open_reason"), false)
		why.pressed.connect(func() -> void: reason_requested.emit(event))
		box.add_child(why)
	return row
