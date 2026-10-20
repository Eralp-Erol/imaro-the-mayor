class_name ParcelInspector
extends VBoxContainer
## Parsel denetçisi iskeleti (L2 içeriği, ux-ia §2). Yalnız `ParcelView` alanlarını gösterir:
##   id/ref, region_code, area_m2, zone, pending_zone, development, owner, land_value, reason_ids.
## `ParcelView`'de OLMAYAN bilgi (altyapı erişimi, yatırımcı ilgisi, nüfus) gösterilmez - sahte satır yok
## (sözleşme v1.1
## istekleri). Hover'a bağlı bilgi yok: dokunmatik ve masaüstü aynı satırları görür (seç -> denetçi).
## "Neden?" yalnız kayıtlı gerekçe varsa görünür (SIM-12); nedensellik paneli `ReasonPanel`dir -> `reason_requested`.

signal reason_requested(subject_ref: StringName)

var _ctx: UiContext = null
var _rows: VBoxContainer = null
var _why: Button = null
var _empty: Label = null
var _mock_badge: MockBadge = null
var _subject: StringName = &""


static func create(ctx: UiContext) -> ParcelInspector:
	var ins := ParcelInspector.new()
	ins._ctx = ctx
	ins.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var head := HBoxContainer.new()
	ins._mock_badge = MockBadge.create()
	ins._mock_badge.visible = false
	head.add_child(ins._mock_badge)
	ins.add_child(head)
	ins._empty = UiFactory.label(UiText.t(&"inspector.nothing_selected"), UiTheme.V_LABEL_MUTED, true)
	ins.add_child(ins._empty)
	ins._rows = VBoxContainer.new()
	ins.add_child(ins._rows)
	ins._why = UiFactory.button(ctx, UiText.t(&"reason.parcel_history"), true)
	ins._why.visible = false
	ins._why.pressed.connect(func() -> void: ins.reason_requested.emit(ins._subject))
	ins.add_child(ins._why)
	return ins


func show_nothing() -> void:
	_subject = &""
	_clear_rows()
	_empty.visible = true
	_why.visible = false
	_mock_badge.visible = false


func show_parcel(p: ParcelView, is_mock: bool) -> void:
	_subject = p.ref()
	_clear_rows()
	_empty.visible = false
	_mock_badge.visible = is_mock
	_add_row(UiText.t(&"inspector.parcel"), UiText.humanize(p.ref()))
	_add_row(UiText.t(&"inspector.region"), String(p.region_code))
	_add_row(UiText.t(&"inspector.area"), UiText.t(&"format.area_m2", {"value": UiText.number(p.area_m2)}))
	_add_row(UiText.t(&"inspector.zoning"), UiText.humanize(p.zone))
	_add_row(UiText.t(&"inspector.pending_zone"),
		UiText.humanize(p.pending_zone) if p.pending_zone != &"" else UiText.t(&"inspector.none_pending"))
	_add_row(UiText.t(&"inspector.development"), UiText.t(StringName("parcel.development.%s" % p.development)))
	_add_row(UiText.t(&"inspector.owner"), UiText.actor_name(p.owner))
	_add_row(UiText.t(&"inspector.land_value"), UiText.money(p.land_value))
	if not p.reason_ids.is_empty():
		_add_row(UiText.t(&"inspector.recorded_reasons"), UiText.number(p.reason_ids.size()))
	_why.visible = not p.reason_ids.is_empty()


func row_texts() -> PackedStringArray:
	var out := PackedStringArray()
	for row in _rows.get_children():
		var parts := PackedStringArray()
		for l in row.get_children():
			if l is Label:
				parts.append((l as Label).text)
		out.append(": ".join(parts))
	return out


func why_visible() -> bool:
	return _why.visible


func empty_visible() -> bool:
	return _empty.visible


func why_button() -> Button:
	return _why


func _clear_rows() -> void:
	for row in _rows.get_children():
		_rows.remove_child(row)
		row.queue_free()


func _add_row(caption: String, value: String) -> void:
	var row := HBoxContainer.new()
	var cap := UiFactory.label(caption, UiTheme.V_LABEL_MUTED, true)
	cap.size_flags_stretch_ratio = 0.9
	var val := UiFactory.label(value, &"", true)
	val.size_flags_stretch_ratio = 1.1
	row.add_child(cap)
	row.add_child(val)
	_rows.add_child(row)
