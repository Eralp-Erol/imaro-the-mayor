class_name ResettlementQueueText
extends RefCounted
## Yeniden iskân BEKLEME LİSTESİ gösterimi (T-067 UI, D-019 E1; SIM-12, CAN-03). SAF: yalnız `PolicyView` alanlarını
## (`waiting_households`, `waiting_by_region`, `served_households`; sözleşme 1.9) okur, sayı uydurmaz.
## Nedenler: liste yatırımcının bitirdiği yeni evi bekler (belediye ev yapmaz); politika kapalıysa atama durur.


## "Bekleyen aile: N" (ya da "Bekleyen aile yok") satırı.
static func waiting_line(v: PolicyView) -> String:
	if v.waiting_households <= 0:
		return UiText.t(&"queue.none")
	return UiText.t(&"queue.waiting", {"n": v.waiting_households})


## Bölge kırılımı ("A: 3 · B: 2"); boşsa boş metin. Bölge kodları sim'in kendi kodlarıdır.
static func regions_line(v: PolicyView) -> String:
	if v.waiting_by_region.is_empty():
		return ""
	var codes: Array = v.waiting_by_region.keys()
	codes.sort()
	var items := PackedStringArray()
	for code: Variant in codes:
		items.append(UiText.t(&"queue.region_item", {"region": str(code), "n": int(v.waiting_by_region[code])}))
	return UiText.t(&"queue.regions", {"regions": " · ".join(items)})


## Sonradan ev verilen toplam; 0 ise boş (satır gizli).
static func served_line(v: PolicyView) -> String:
	return UiText.t(&"queue.served_total", {"n": v.served_households}) if v.served_households > 0 else ""


## Neden satırı: yalnız bekleyen aile varken (liste neyi bekliyor / neden duruyor).
static func reason_line(v: PolicyView) -> String:
	if v.waiting_households <= 0:
		return ""
	return UiText.t(&"queue.why_waiting" if v.enabled else &"queue.why_paused")


static func add_rows(parent: VBoxContainer, v: PolicyView) -> void:
	parent.add_child(UiFactory.label(waiting_line(v), &"" if v.waiting_households > 0 else UiTheme.V_LABEL_MUTED, true))
	for text: String in [regions_line(v), served_line(v), reason_line(v)]:
		if text != "":
			parent.add_child(UiFactory.label(text, &"", true))


## HUD şeridi metinleri (0 ise boş: satır yok).
static func strip_waiting(n: int) -> String:
	return UiText.t(&"strip.queue_waiting", {"n": n}) if n > 0 else ""


static func strip_served(n: int) -> String:
	return UiText.t(&"strip.queue_served", {"n": n}) if n > 0 else ""
