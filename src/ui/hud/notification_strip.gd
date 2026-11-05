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
const _CODE_INFRA := "infrastructure_exhausted"
## Şerit önceliği: oyuncunun eylemi ve inşaat > diğer parsel/çıkış olayları > arka plan vazgeçmeleri.
const PRIO_BACKGROUND := 0
const PRIO_NORMAL := 1
const PRIO_PLAYER := 2
## Satır metninin asgari genişliği (px, ölçekten önce).
const ROW_TEXT_MIN_WIDTH := 140.0

var _ctx: UiContext = null
var _max_rows: int = 3
var _events: Array[SimEvent] = []
var _rows: Array[PanelContainer] = []
## Plansız yüzünden vazgeçilen (ve sonra değişmeyen) parseller: şeritte tek tek değil, gerçek sayıyla tek özet satırı.
var _unplanned: Dictionary = {}
var _summary: PanelContainer = null
## Altyapı yetmediği için vazgeçilen parseller: tek özet satırı ("yol eklemek kapasiteyi artırır"); gerçek sayı.
var _infra: Dictionary = {}
var _infra_summary: PanelContainer = null
## T-067 · Yeniden iskân bekleme listesi (gerçek `PolicyView` sayıları): bekleyen aile / son ev verilen küme satırları.
var _queue_waiting: int = 0
var _queue_served: int = 0
var _queue_waiting_row: PanelContainer = null
var _queue_served_row: PanelContainer = null
## B-081 · Meclis güveni düşüşü (gerçek neden kaydından; `CouncilTrustNotice`): etkilenen üye sayısı, 0 = satır yok.
var _trust_members: int = 0
var _trust_row: PanelContainer = null
## T-042b · Aynı komutun `public_work.expropriated` olayı: "Yol yapıldı" satırına yıkım özeti olarak eklenir (iki satır
## yerine tek; komut kimliği -> olay). Yalnız şerit sunumudur; olay günlüğü ikisini de tutar.
var _demolition: Dictionary = {}
## B-019 · Yerleşimin verdiği en büyük yükseklik (0 = sınırsız). Sığmayan (eski) satırlar yalnız GÖSTERİMDE gizlenir;
## olay günlüğü ve gerekçe ekranları etkilenmez. Şerit hiçbir koşulda araç çubuğuna binmez/ekran dışına taşmaz.
var _max_height: float = 0.0
var _fit_hidden: Array[Control] = []


static func create(ctx: UiContext) -> NotificationStrip:
	var s := NotificationStrip.new()
	s._ctx = ctx
	s._max_rows = maxi(1, int(UiConfig.value("hud.notification_rows", 3)))
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	s.visible = false
	return s


## Şerit YALNIZ gösterim süzgecidir: olay günlüğü, "Olaylar" akışı ve gerekçe ekranları tüm olayları almaya devam eder.
func push_events(events: Array[SimEvent]) -> void:
	if events.is_empty():
		return
	for e in events:
		_track_unplanned(e)
		if is_unplanned_decline(e) or is_infra_decline(e):
			continue
		_track_demolition(e)
		_add(e)
	_rebuild()


## `public_work.built` aynı komutun kamulaştırma olayını bulursa o olayın satırını çıkarır (özeti `built` satırına
## `_row_text` ekler). Sıra tersse ya da built hiç gelmezse kamulaştırma olayı kendi satırında kalır.
func _track_demolition(e: SimEvent) -> void:
	if e.kind == SimEvent.KIND_PUBLIC_WORK_EXPROPRIATED and e.command_id != SimContract.NO_ID:
		_demolition[e.command_id] = e
	elif e.kind == SimEvent.KIND_PUBLIC_WORK_BUILT and _demolition.has(e.command_id):
		var at := _events.find(_demolition[e.command_id])
		if at >= 0:
			_events.remove_at(at)


## Satır metni: yol yapıldı satırına (varsa) aynı komutun yıkım özeti eklenir.
func _row_text(e: SimEvent) -> String:
	var text := strip_text(e)
	if e.kind == SimEvent.KIND_PUBLIC_WORK_BUILT and _demolition.has(e.command_id):
		text += " · " + ExpropriationText.strip_suffix(_demolition[e.command_id])
	return text


## Plansız arazi yüzünden toplu vazgeçme mi (`event.investor.declined`, kod `zoning_unplanned`)?
static func is_unplanned_decline(event: SimEvent) -> bool:
	return event.message_key == &"event.investor.declined" and str(event.args.get("code", "")) == _CODE_UNPLANNED


## Altyapı kapasitesi yetmediği için vazgeçme mi (`event.investor.declined`, kod `infrastructure_exhausted`)?
static func is_infra_decline(event: SimEvent) -> bool:
	return event.message_key == &"event.investor.declined" and str(event.args.get("code", "")) == _CODE_INFRA


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


func infra_count() -> int:
	return _infra.size()


func infra_summary_text() -> String:
	return UiText.t(&"strip.infra_summary", {"n": _infra.size()}) if not _infra.is_empty() else ""


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
		_infra.erase(parcel)
	elif is_infra_decline(e):
		_infra[parcel] = true
		_unplanned.erase(parcel)
	elif String(e.message_key).begins_with("event.investor") or String(e.message_key).begins_with("event.construction"):
		_unplanned.erase(parcel)
		_infra.erase(parcel)


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


## Bekleme listesi özetleri (0 ise satır yok). Kendiliğinden kaybolmaz; sayı değişince/sıfırlanınca değişir.
func set_queue_notice(waiting: int, served_batch: int) -> void:
	if waiting == _queue_waiting and served_batch == _queue_served:
		return
	_queue_waiting = waiting
	_queue_served = served_batch
	_rebuild()


func set_trust_notice(members: int) -> void:
	if members == _trust_members:
		return
	_trust_members = members
	_rebuild()


func trust_text() -> String:
	return CouncilTrustNotice.strip_text(_trust_members)


func queue_texts() -> PackedStringArray:
	var out := PackedStringArray()
	for t in [ResettlementQueueText.strip_served(_queue_served), ResettlementQueueText.strip_waiting(_queue_waiting)]:
		if t != "":
			out.append(t)
	return out


func clear() -> void:
	_events.clear()
	_unplanned.clear()
	_infra.clear()
	_demolition.clear()
	_rebuild()


func row_count() -> int:
	return _events.size()


func row_texts() -> PackedStringArray:
	var out := PackedStringArray()
	for e in _events:
		out.append(_row_text(e))
	return out


## Yerleşim yöneticisi (HudRoot) çağırır. Yeni olay üstte olduğundan sığmayan satırlar en alttakilerdir.
func set_max_height(h: float) -> void:
	if is_equal_approx(h, _max_height):
		return
	_max_height = h
	_fit_rows()


## Yüksekliğe sığmayan satırları gizler (en az bir satır kalır). Gerekçe düğmesi olan satır ("Nedenini gör", SIM-12)
## düğmesiz satırdan ÖNCE korunur (güven satırı, B-120, hepsinden önce): 800x600'de yıkım sonrası "Yol yıkıldı"
## satırının nedeni, üstündeki düğmesiz "Komut uygulandı" satırı yüzünden gizlenmesin (3B kare, B-019). Kalan satırlar
## özgün sırayla gösterilir.
## Satır asgari yüksekliği o anki genişliğe bağlıdır; genişlik/içerik değişince `minimum_size_changed` -> HudRoot
## yeniden yerleşimi bu işlevi tekrar çağırır.
func _fit_rows() -> void:
	for c in _fit_hidden:
		if is_instance_valid(c):
			c.visible = true
	_fit_hidden.clear()
	if _max_height <= 0.0:
		return
	var sep := float(get_theme_constant(&"separation"))
	var rows: Array[Control] = []
	for child in get_children():
		var c := child as Control
		if c != null and c.visible:
			rows.append(c)
	var order: Array[Control] = []
	# B-120: güven satırı sim'in kayıtlı nedenini taşıyan tek özet satırı; en sona itilip hep düşmesin.
	if _trust_row != null and rows.has(_trust_row):
		order.append(_trust_row)
	for r in rows:
		if _has_reason_button(r) and not order.has(r):
			order.append(r)
	for r in rows:
		if not order.has(r):
			order.append(r)
	var used := 0.0
	var keep: Array[Control] = []
	for c in order:
		var need := c.get_combined_minimum_size().y + (sep if not keep.is_empty() else 0.0)
		if not keep.is_empty() and used + need > _max_height:
			continue
		used += need
		keep.append(c)
	for c in rows:
		if not keep.has(c):
			c.visible = false
			_fit_hidden.append(c)


static func _has_reason_button(row: Control) -> bool:
	var box := row.get_child(0) as HBoxContainer if row.get_child_count() > 0 else null
	if box == null or box.get_child_count() < 2:
		return false   # özet satırları: düğmesiz
	var why := box.get_child(1) as Button
	return why != null and why.visible


func _rebuild() -> void:
	visible = not _events.is_empty() or not _unplanned.is_empty() or not _infra.is_empty() or _queue_waiting > 0 \
			or _queue_served > 0 or _trust_members > 0
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
	_summary = _sync_summary(_summary, not _unplanned.is_empty(), summary_text())
	_infra_summary = _sync_summary(_infra_summary, not _infra.is_empty(), infra_summary_text())
	_queue_served_row = _sync_summary(_queue_served_row, _queue_served > 0,
			ResettlementQueueText.strip_served(_queue_served))
	_queue_waiting_row = _sync_summary(_queue_waiting_row, _queue_waiting > 0,
			ResettlementQueueText.strip_waiting(_queue_waiting))
	_trust_row = _sync_summary(_trust_row, _trust_members > 0, CouncilTrustNotice.strip_text(_trust_members))
	_fit_rows()


## Kullanılmayan özet sahipsiz beklemez. HUD değişince silinecek üst düğümüne bağlı kalır.
func _sync_summary(row: PanelContainer, needed: bool, text: String) -> PanelContainer:
	if not needed:
		if row != null:
			remove_child(row)
			row.queue_free()
		return null
	if row == null:
		row = PanelContainer.new()
		row.theme_type_variation = UiTheme.V_HUD_BAR
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(UiFactory.label("", &"", true))
		add_child(row)
	(row.get_child(0) as Label).text = text
	row.visible = true
	move_child(row, -1)
	return row


func _make_row() -> PanelContainer:
	var row := PanelContainer.new()
	row.theme_type_variation = UiTheme.V_HUD_BAR
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	var box := HBoxContainer.new()
	row.add_child(box)
	var text := UiFactory.label("", &"", true)
	# Dar şeritte etiket 1-4 harf/satıra ezilmesin (B-019): asgari okunur genişlik; düğme sağda kalır.
	text.custom_minimum_size.x = _ctx.px(ROW_TEXT_MIN_WIDTH)
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(text)
	var why := UiFactory.button(_ctx, UiText.t(&"alert.open_reason"), false)
	why.pressed.connect(func() -> void: reason_requested.emit(row.get_meta(_EVENT_META)))
	box.add_child(why)
	return row


func _fill_row(row: PanelContainer, event: SimEvent) -> void:
	var box := row.get_child(0) as HBoxContainer
	(box.get_child(0) as Label).text = _row_text(event)
	# Gerekçe kaydı olan olay, reddedilen komut ("neden kabul edilmedi", SIM-12) ya da yapılan oyuncu yolu (ayrıntı).
	var is_work := event.kind == SimEvent.KIND_PUBLIC_WORK_BUILT
	var why := box.get_child(1) as Button
	why.visible = not event.reason_ids.is_empty() or event.kind == SimEvent.KIND_COMMAND_REJECTED or is_work
	why.text = UiText.t(&"alert.open_work" if is_work else &"alert.open_reason")
	row.set_meta(_EVENT_META, event)
