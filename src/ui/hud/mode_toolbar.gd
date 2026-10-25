class_name ModeToolbar
extends VBoxContainer
## Mod/araç çubuğu (L1, altta): [İnşa | İmar | Yönetim] + seçili modun araçları. Yalnız belediye başkanı
## fiilleri (CAN-03): "özel bina yerleştir" aracı hiçbir modda yoktur.
## T-047 DÜRÜSTLÜK KURALI: bir araç yalnız yeteneği gerçekten bağlayan sahip `add_tool` (HudRoot.register_tool) ile
## kaydedince görünür; hiç aracı kayıtlı olmayan mod da görünmez (ölü düğme yok, "Henüz kurulmadı" etiketli düğme de
## yok). Tek görünür mod varsa mod düğmesi gizlenir (seçilecek bir şey yok).
## `MODES` yalnız KATALOGdur (hangi araç hangi moda aittir); görünürlüğü kayıt belirler.
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
## Sonuç paneli (T-040): yalnız bir sahip `add_tool` ile kaydederse görünür (ölü düğme yok).
const TOOL_RESULTS := &"tool.results"

## Katalog: mod -> {tools: [tool_id]} (kayıtlı olanlar görünür).
const MODES := {
	&"mode.build": {"tools": []},
	&"mode.plan": {"tools": [&"tool.inspect", &"tool.zone"]},
	&"mode.manage": {"tools": [&"tool.budget", &"tool.council", &"tool.agenda"]},
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
## Sahiplerce eklenen araçlar: mod -> [tool_id].
var _extra_tools: Dictionary = {}


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
		var b := UiFactory.button(ctx, UiText.t(mode_id), true, true)
		b.tooltip_text = UiText.t(StringName(String(mode_id) + ".hint"))
		b.pressed.connect(tb._on_mode_pressed.bind(mode_id))
		tb._mode_buttons[mode_id] = b
		tb._row_modes.add_child(b)
	tb._sep = VSeparator.new()
	tb._row_modes.add_child(tb._sep)
	tb._rebuild_tools()
	tb._sync()
	tb._refresh_modes()
	tb.set_rows(1)
	return tb


## 1: araçlar modların yanında; 2: araçlar ikinci satırda (dikey dokunmatik).
func set_rows(rows: int) -> void:
	if rows == _rows:
		return
	_rows = rows
	_sep.visible = rows == 1 and _visible_modes().size() > 1
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


## Görünür (gösterilen) düğmeler.
func all_buttons() -> Array[Button]:
	var out: Array[Button] = []
	for b: Button in _mode_buttons.values():
		if b.visible:
			out.append(b)
	for b: Button in _tool_buttons.values():
		out.append(b)
	return out


## Bir mod'a, yeteneği gerçekten bağlayan sahip tarafından araç ekler (kaydı olmayan araç hiç görünmez).
func add_tool(mode_id: StringName, tool_id: StringName) -> void:
	if not MODES.has(mode_id):
		return
	var list: Array = _extra_tools.get(mode_id, [])
	if list.has(tool_id):
		return
	list.append(tool_id)
	_extra_tools[mode_id] = list
	_refresh_modes()
	if mode_id == current_mode:
		var keep := current_tool
		_rebuild_tools()
		current_tool = keep
		_sync()


## Aracı olan (görünür) modlar, katalog sırasıyla.
func _visible_modes() -> Array[StringName]:
	var out: Array[StringName] = []
	for mode_id: StringName in MODES:
		if not (_extra_tools.get(mode_id, []) as Array).is_empty():
			out.append(mode_id)
	return out


func _refresh_modes() -> void:
	var visible_modes := _visible_modes()
	if not visible_modes.is_empty() and not visible_modes.has(current_mode):
		current_mode = visible_modes[0]
		current_tool = &""
		_rebuild_tools()
	for mode_id: StringName in _mode_buttons:
		(_mode_buttons[mode_id] as Button).visible = visible_modes.size() > 1 and visible_modes.has(mode_id)
	if _sep != null:
		_sep.visible = _rows == 1 and visible_modes.size() > 1
	_sync()


func select_mode(mode_id: StringName) -> void:
	if not _visible_modes().has(mode_id):
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
	var tools: Array = (_extra_tools.get(current_mode, []) as Array).duplicate()
	for tool_id: StringName in tools:
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
