class_name ReasonPreview
extends VBoxContainer
## GEÇİCİ gerekçe özeti (T-021'in nedensellik paneli bunun yerine geçer): bir `ReasonRecord`'un kararını, etkenlerini
## (lehte/aleyhte) ve eşiğe ulaşıp ulaşmadığını gösterir. SIM-12: sim'in kaydettiği neden gösterilir, UI neden UYDURMAZ;
## SIM-09: tek toplam gösterge yoktur. Sayısal etken ağırlığı gösterilmez (sabit nokta değerler oyuncu sayısı değildir).
## Anahtar tabloda yoksa satırda anahtar adı görünür (UiText kuralı).

var _ctx: UiContext = null


static func create(ctx: UiContext) -> ReasonPreview:
	var r := ReasonPreview.new()
	r._ctx = ctx
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return r


func show_records(records: Array[ReasonRecord], is_mock: bool) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	if is_mock:
		add_child(MockBadge.create())
	if records.is_empty():
		add_child(UiFactory.label(UiText.t(&"reason.none_recorded"), UiTheme.V_LABEL_MUTED, true))
		return
	for record in records:
		add_child(_record_box(record))
	add_child(UiFactory.label(UiText.t(&"reason.preview_note"), UiTheme.V_LABEL_MUTED, true))


func texts() -> PackedStringArray:
	var out := PackedStringArray()
	_collect(self, out)
	return out


func _record_box(record: ReasonRecord) -> Control:
	var box := VBoxContainer.new()
	var decision := StringName("%s.%s" % [record.decision_key, record.outcome])
	box.add_child(UiFactory.label(UiText.t(&"reason.outcome") + ": " + UiText.t(decision), UiTheme.V_LABEL_TITLE, true))
	box.add_child(UiFactory.label(UiText.actor_name(record.actor), UiTheme.V_LABEL_MUTED, true))
	box.add_child(UiFactory.label(UiText.t(&"reason.factors"), UiTheme.V_LABEL_MUTED))
	for f in record.factors:
		var direction := &"reason.direction.for" if f.contribution() >= 0 else &"reason.direction.against"
		var line := "%s — %s" % [UiText.t(f.name_key), UiText.t(direction)]
		if f.is_estimate:
			line += " (%s)" % UiText.t(&"common.estimate")
		box.add_child(UiFactory.label(line, &"", true))
	var passed := record.outcome == ReasonRecord.OUTCOME_POSITIVE
	box.add_child(UiFactory.label(UiText.t(&"reason.sum_reached" if passed else &"reason.sum_short"), &"", true))
	return box


func _collect(node: Node, out: PackedStringArray) -> void:
	for child in node.get_children():
		if child is Label:
			out.append((child as Label).text)
		_collect(child, out)
