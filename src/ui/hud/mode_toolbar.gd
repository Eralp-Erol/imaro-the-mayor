class_name ModeToolbar
extends VBoxContainer
## Mod/araç çubuğu (L1, altta): [İnşa | İmar | Yönetim] + seçili modun araçları. Yalnız belediye başkanı
## fiilleri
## (CAN-03): "özel bina yerleştir" aracı hiçbir modda yoktur. Kurulmamış sistemin sekmesi GİZLENMEZ ama
## dürüstçe
## etiketlidir ("Henüz kurulmadı") ve devre dışıdır; sahte araç yok.
## Mevcut gerçek yetenek: İmar modu (imar önerisi + denetçi) ve Yönetim modu (bütçe, meclis, gündem panelleri;
## T-022). Panel açılır ama sim bölümü kurulmamışsa panel dürüstçe "Henüz kurulmadı" der (sahte içerik yok).
## İnşa (kamusal yol/park) komut/ekran bakımından kurulmamıştır.
## Dikey dokunmatikte iki satır: modlar üstte, araçlar altta; yatay/masaüstünde tek satır.

signal mode_changed(mode_id: StringName)
signal tool_selected(tool_id: StringName)

const MODE_BUILD := &"mode.build"
const MODE_PLAN := &"mode.plan"
const MODE_MANAGE := &"mode.manage"
const TOOL_INSPECT := &"tool.inspect"
const TOOL_ZONE := &"tool.zone"
const TOOL_BUDGET := &"tool.budget"
const TOOL_COUNCIL := &"tool.council"
const TOOL_AGENDA := &"tool.agenda"

## Mod → {built: bool, tools: [tool_id]}. Kurulu olmayan mod devre dışı etiketlidir.
const MODES := {
	&"mode.build": {"built": false, "tools": []},
	&"mode.plan": {"built": true, "tools": [&"tool.inspect", &"tool.zone"]},
	&"mode.manage": {"built": true, "tools": [&"tool.budget", &"tool.council", &"tool.agenda"]},
}

var current_mode: StringName = MODE_PLAN
var current_tool: StringName = &""

var _ctx: UiContext = null
var _rows: int = 0
var _row_modes: HBoxContainer = null
var _row_tools: HBoxContainer = null
var _sep: VSeparator = null
var _mode_buttons: Dictionary = {}
var _tool_buttons: Dictionary = {}


static func create(ctx: UiContext) -> ModeToolbar:
	var tb := ModeToolbar.new()
	tb._ctx = ctx
	tb.theme_type_variation = &""
	tb.mouse_filter = Control.MOUSE_FILTER_PASS
	tb._row_modes = HBoxContainer.new()
	tb._row_tools = HBoxContainer.new()
	tb.add_child(tb._row_modes)
	tb.add_child(tb._row_tools)
	for mode_id: StringName in MODES:
		var spec: Dictionary = MODES[mode_id]
		var label := UiText.t(mode_id)
		if not spec["built"]:
			label += "\n" + UiText.t(&"state.not_built_short")
		var b := UiFactory.button(ctx, label, true, true)
		b.disabled = not spec["built"]
		b.tooltip_text = UiText.t(StringName(String(mode_id) + ".hint"))
		b.pressed.connect(tb._on_mode_pressed.bind(mode_id))
		tb._mode_buttons[mode_id] = b
		tb._row_modes.add_child(b)
	tb._sep = VSeparator.new()
	tb._row_modes.add_child(tb._sep)
	tb._rebuild_tools()
	tb._sync()
	tb.set_rows(1)
	return tb


## 1: araçlar modların yanında; 2: araçlar ikinci satırda (dikey dokunmatik).
func set_rows(rows: int) -> void:
	if rows == _rows:
		return
	_rows = rows
	_sep.visible = rows == 1
	if _row_tools.get_parent() != null:
		_row_tools.get_parent().remove_child(_row_tools)
	if _rows == 1:
		_row_modes.add_child(_row_tools)
	else:
		add_child(_row_tools)


func rows() -> int:
	return _rows


func mode_button(mode_id: StringName) -> Button:
	return _mode_buttons.get(mode_id) as Button


func tool_button(tool_id: StringName) -> Button:
	return _tool_buttons.get(tool_id) as Button


func all_buttons() -> Array[Button]:
	var out: Array[Button] = []
	for b: Button in _mode_buttons.values():
		out.append(b)
	for b: Button in _tool_buttons.values():
		out.append(b)
	return out


func select_mode(mode_id: StringName) -> void:
	if not MODES.has(mode_id) or not MODES[mode_id]["built"]:
		return
	current_mode = mode_id
	current_tool = &""
	_rebuild_tools()
	_sync()
	mode_changed.emit(mode_id)


func _rebuild_tools() -> void:
	for b: Button in _tool_buttons.values():
		b.get_parent().remove_child(b)
		b.queue_free()
	_tool_buttons.clear()
	var spec: Dictionary = MODES[current_mode]
	for tool_id: StringName in spec["tools"]:
		var b := UiFactory.button(_ctx, UiText.t(tool_id), true, true)
		b.pressed.connect(_on_tool_pressed.bind(tool_id))
		_tool_buttons[tool_id] = b
		_row_tools.add_child(b)


func _sync() -> void:
	for mode_id: StringName in _mode_buttons:
		(_mode_buttons[mode_id] as Button).set_pressed_no_signal(mode_id == current_mode)
	for tool_id: StringName in _tool_buttons:
		(_tool_buttons[tool_id] as Button).set_pressed_no_signal(tool_id == current_tool)


func _on_mode_pressed(mode_id: StringName) -> void:
	select_mode(mode_id)


func _on_tool_pressed(tool_id: StringName) -> void:
	current_tool = tool_id
	_sync()
	tool_selected.emit(tool_id)
