class_name NotificationStrip
extends VBoxContainer
## Bildirim şeridi (L1, sol-üst): `SimEvent` akışından SON birkaç olay. Boşsa görünmez. Kendiliğinden
## kaybolmaz
## (erişilebilirlik): yalnız yeni olay gelince en eskisi şeritten çıkar (geçmişte kalır).
## Metin: `UiText.event_text` (sim anahtar+argüman verir, UI çevirir). Gerekçe kaydı varsa "Nedenini gör"
## (SIM-12).
## Nedensellik paneli (`ReasonPanel`, T-021) sahibi tarafından açılır; burada yalnız `reason_requested` sinyali.

signal reason_requested(event: SimEvent)

const _EVENT_META := &"strip_event"
const _CODE_UNPLANNED := "zoning_unplanned"
## Şerit önceliği: oyuncunun eylemi ve inşaat > diğer parsel/çıkış olayları > arka plan vazgeçmeleri.
const PRIO_BACKGROUND := 0
const PRIO_NORMAL := 1
const PRIO_PLAYER := 2

var _ctx: UiContext = null
var _max_rows: int = 3
var _events: Array[SimEvent] = []
var _rows: Array[PanelContainer] = []
## Plansız yüzünden vazgeçilen (ve sonra değişmeyen) parseller: şeritte tek tek değil, gerçek sayıyla tek özet satırı.
var _unplanned: Dictionary = {}
var _summary: PanelContainer = null


static func create(ctx: UiContext) -> NotificationStrip:
	var s := NotificationStrip.new()
	s._ctx = ctx
	s._max_rows = maxi(1, int(UiConfig.value("hud.notification_rows", 3)))
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	s.visible = false
	s._summary = PanelContainer.new()
	s._summary.theme_type_variation = UiTheme.V_HUD_BAR
	s._summary.mouse_filter = Control.MOUSE_FILTER_IGNORE
	s._summary.add_child(UiFactory.label("", &"", true))
	return s


## Şerit YALNIZ gösterim süzgecidir: olay günlüğü, "Olaylar" akışı ve gerekçe ekranları tüm olayları almaya devam eder.
func push_events(events: Array[SimEvent]) -> void:
	if events.is_empty():
		return
	for e in events:
		_track_unplanned(e)
		if is_unplanned_decline(e):
			continue
		_add(e)
	_rebuild()


## Plansız arazi yüzünden toplu vazgeçme mi (`event.investor.declined`, kod `zoning_unplanned`)?
static func is_unplanned_decline(event: SimEvent) -> bool:
	return event.message_key == &"event.investor.declined" and str(event.args.get("code", "")) == _CODE_UNPLANNED


static func priority(event: SimEvent) -> int:
	var key := String(event.message_key)
	var kind := String(event.kind)
	if event.command_id != SimContract.NO_ID or kind.begins_with("command.") or kind.begins_with("public_work.") \
			or kind.begins_with("council.") or kind == String(SimEvent.KIND_GROUP_REACTED) \
			or key.begins_with("event.construction") or key == "event.investor.develop":
		return PRIO_PLAYER
	if key == "event.investor.declined":
		return PRIO_BACKGROUND
	return PRIO_NORMAL


func unplanned_count() -> int:
	return _unplanned.size()


func summary_text() -> String:
	return UiText.t(&"strip.unplanned_summary", {"n": _unplanned.size()}) if not _unplanned.is_empty() else ""


func _track_unplanned(e: SimEvent) -> void:
	var parcel := ""
	for subject in e.subjects:
		if str(subject).begins_with("parcel."):
			parcel = str(subject)
			break
	if parcel.is_empty():
		return
	if is_unplanned_decline(e):
		_unplanned[parcel] = true
	elif String(e.message_key).begins_with("event.investor") or String(e.message_key).begins_with("event.construction"):
		_unplanned.erase(parcel)


## Sakin şerit: aynı metin tekrar satır açmaz (arka plan olayları), doluyken düşük öncelik yüksek önceliği itmez.
func _add(e: SimEvent) -> void:
	var prio := priority(e)
	if prio < PRIO_PLAYER:
		var text := strip_text(e)
		for k in range(_events.size() - 1, -1, -1):
			if priority(_events[k]) < PRIO_PLAYER and strip_text(_events[k]) == text:
				_events.remove_at(k)
	if _events.size() >= _max_rows:
		var lowest := PRIO_PLAYER + 1
		var victim := -1
		for k in _events.size():
			var p := priority(_events[k])
			if p < lowest:
				lowest = p
				victim = k
		if prio < lowest:
			return
		_events.remove_at(victim)
	_events.append(e)


## Şerit metni: olay metni + (varsa) parsel adı/numarası. Üç özdeş "Yatırımcı yatırım yaptı" satırı hangi parsellerde
## olduğunu söylesin (T-042 sanat düzeltmesi). Parsel yoksa metin `UiText.event_text` ile aynıdır.
static func strip_text(event: SimEvent) -> String:
	var text := UiText.event_text(event)
	for subject in event.subjects:
		if str(subject).begins_with("parcel."):
			var label := UiText.humanize(subject)
			if not text.contains(label):
				text += " · " + label
			break
	return text


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _summary != null and is_instance_valid(_summary) \
			and _summary.get_parent() == null:
		_summary.free()


func clear() -> void:
	_events.clear()
	_unplanned.clear()
	_rebuild()


func row_count() -> int:
	return _events.size()


func row_texts() -> PackedStringArray:
	var out := PackedStringArray()
	for e in _events:
		out.append(strip_text(e))
	return out


func _rebuild() -> void:
	visible = not _events.is_empty() or not _unplanned.is_empty()
	var shown := _events.size()
	# Satırlar yeniden kullanılır: her tick'te düğüm silip yaratmak (60 olay/gün rejiminde) kareyi ~2 ms uzatıyordu.
	while _rows.size() < shown:
		var row := _make_row()
		_rows.append(row)
		add_child(row)
	while _rows.size() > shown:
		var extra: PanelContainer = _rows.pop_back()
		remove_child(extra)
		extra.queue_free()
	# Yeni olay üstte.
	for k in shown:
		_fill_row(_rows[k], _events[shown - 1 - k])
	# Özet satırı en altta; yalnız gerçek plansız-parsel sayısından.
	var want_summary := not _unplanned.is_empty()
	if want_summary:
		((_summary.get_child(0)) as Label).text = summary_text()
		_summary.visible = true
		if _summary.get_parent() == null:
			add_child(_summary)
		move_child(_summary, -1)
	elif _summary.get_parent() != null:
		remove_child(_summary)


func _make_row() -> PanelContainer:
	var row := PanelContainer.new()
	row.theme_type_variation = UiTheme.V_HUD_BAR
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	var box := HBoxContainer.new()
	row.add_child(box)
	box.add_child(UiFactory.label("", &"", true))
	var why := UiFactory.button(_ctx, UiText.t(&"alert.open_reason"), false)
	why.pressed.connect(func() -> void: reason_requested.emit(row.get_meta(_EVENT_META)))
	box.add_child(why)
	return row


func _fill_row(row: PanelContainer, event: SimEvent) -> void:
	var box := row.get_child(0) as HBoxContainer
	(box.get_child(0) as Label).text = strip_text(event)
	# Gerekçe kaydı olan olay, reddedilen komut ("neden kabul edilmedi", SIM-12) ya da yapılan oyuncu yolu (ayrıntı).
	var is_work := event.kind == SimEvent.KIND_PUBLIC_WORK_BUILT
	var why := box.get_child(1) as Button
	why.visible = not event.reason_ids.is_empty() or event.kind == SimEvent.KIND_COMMAND_REJECTED or is_work
	why.text = UiText.t(&"alert.open_work" if is_work else &"alert.open_reason")
	row.set_meta(_EVENT_META, event)
