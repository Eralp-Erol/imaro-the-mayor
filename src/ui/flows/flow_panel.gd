class_name FlowPanel
extends VBoxContainer
## Karar akışı panellerinin ortak tabanı (T-022): MOCK rozeti, durum bileşeni (kurulmamış/hata), içerik
## gövdesi, "yeniden çiz ama odağı koru" ve test/erişilebilirlik yardımcıları. Paneller `HudRoot.open_panel`
## içeriğidir; yerleşimi (yan panel / alt sayfa) `HudLayout` verir. Dokunmatik ve masaüstü AYNI bileşenler;
## hover'a bağlı bilgi yoktur.

## Gerekçe paneli isteği: `initial(panel: ReasonPanel)` ilk görünümü kurar (ana sahne paneli açar).
signal reason_requested(initial: Callable)
## Başka karar paneline geçiş isteği (`&"council"`, `&"budget"`).
signal navigate_requested(target: StringName)

const META_ROLE := &"role"

var badge: MockBadge = null
var state_view: StateView = null

var _ctx: UiContext = null
var _facade: SimFacade = null
var _body: VBoxContainer = null
var _signature: String = ""


func refresh() -> void:
	_render()


## Görünür tüm etiket ve düğme metinleri (test/erişilebilirlik).
func texts() -> PackedStringArray:
	var out := PackedStringArray()
	_collect_texts(self, out)
	return out


func joined_text() -> String:
	return " | ".join(texts())


## Rol önekiyle eşleşen görünür düğmeler.
func named_buttons(role_prefix: String) -> Array[Button]:
	var out: Array[Button] = []
	for b in buttons():
		if String(b.get_meta(META_ROLE, "")).begins_with(role_prefix):
			out.append(b)
	return out


func buttons() -> Array[Button]:
	var out: Array[Button] = []
	_collect_buttons(_body, out)
	return out


## Görünür "tahmin" çiplerinin sayısı (tahmin işareti testleri).
func estimate_chip_count() -> int:
	return _count_chips(_body)


func button_with_text(text: String) -> Button:
	for b in buttons():
		if b.text == text:
			return b
	return null


## `signature` değiştiyse yeniden çizer (tick başına gereksiz yeniden kurma ve odak kaybı yok).
func refresh_if_changed(signature: String) -> bool:
	if signature == _signature:
		return false
	_signature = signature
	_render()
	return true


func _setup_flow(ctx: UiContext, facade: SimFacade) -> void:
	_ctx = ctx
	_facade = facade
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	badge = MockBadge.create()
	badge.visible = facade != null and facade.is_mock()
	add_child(badge)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	state_view = StateView.create(ctx)
	state_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	state_view.set_content(_body)
	add_child(state_view)


## Gövdeyi temizler; odaktaki kontrolün rolünü döner (`_restore_focus` ile geri verilir).
func _begin_render() -> String:
	var focused := get_viewport().gui_get_focus_owner() if is_inside_tree() else null
	var role := ""
	if focused != null and is_ancestor_of(focused):
		role = String(focused.get_meta(META_ROLE, ""))
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	return role


func _restore_focus(role: String) -> void:
	if role.is_empty() or not is_inside_tree():
		return
	for b in buttons():
		if String(b.get_meta(META_ROLE, "")) == role and not b.disabled:
			b.grab_focus.call_deferred()
			return


func _render() -> void:
	pass


func _tag(node: Control, role: String) -> Control:
	node.set_meta(META_ROLE, role)
	return node


func _section(key: StringName) -> Label:
	return UiFactory.label(UiText.t(key), UiTheme.V_LABEL_TITLE, true)


func _muted(text: String) -> Label:
	return UiFactory.label(text, UiTheme.V_LABEL_MUTED, true)


func _pair(caption: String, value: String) -> Control:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var cap := UiFactory.label(caption, UiTheme.V_LABEL_MUTED, true)
	cap.size_flags_stretch_ratio = 0.8
	row.add_child(cap)
	var val := UiFactory.label(value, &"", true)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(val)
	return row


## Gruplanmış bilgi kartı; `inner` içine çocuk eklenir.
func _card() -> Array:
	var card := PanelContainer.new()
	card.theme_type_variation = UiTheme.V_INFO_CARD
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var inner := VBoxContainer.new()
	inner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.add_child(inner)
	return [card, inner]


func _estimate_chip() -> Control:
	var chip := PanelContainer.new()
	chip.theme_type_variation = UiTheme.V_ESTIMATE_CHIP
	chip.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(UiFactory.label(UiText.t(&"common.estimate")))
	return chip


## Yön simgesi + metin. `wrap` kapalıyken (dar yuvadaki kısa etiket: Evet/Hayır) metin sarılmaz ve boyu korunur.
func _direction_row(kind: ReasonGlyph.Kind, token: String, variation: StringName, text: String,
		wrap: bool = true) -> Control:
	var row := HBoxContainer.new()
	row.add_child(ReasonGlyph.create(_ctx, kind, _ctx.tokens.color(token), text))
	var label := UiFactory.label(text, variation, wrap)
	if not wrap:
		label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	row.add_child(label)
	return row


func _request_reason(initial: Callable) -> void:
	reason_requested.emit(initial)


func _count_chips(node: Node) -> int:
	var n := 0
	for child in node.get_children():
		var c := child as Control
		if c != null and not c.visible:
			continue
		if child is PanelContainer and (child as PanelContainer).theme_type_variation == UiTheme.V_ESTIMATE_CHIP:
			n += 1
		n += _count_chips(child)
	return n


func _collect_texts(node: Node, out: PackedStringArray) -> void:
	for child in node.get_children():
		var c := child as Control
		if c != null and not c.visible:
			continue
		if child is Label:
			out.append((child as Label).text)
		elif child is Button:
			out.append((child as Button).text)
		_collect_texts(child, out)


func _collect_buttons(node: Node, out: Array[Button]) -> void:
	for child in node.get_children():
		var c := child as Control
		if c != null and not c.visible:
			continue
		var b := child as Button
		if b != null:
			out.append(b)
		_collect_buttons(child, out)
