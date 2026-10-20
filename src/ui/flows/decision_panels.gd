class_name DecisionPanels
extends RefCounted
## Karar akışları sahibi (T-022): imar önerisi, meclis, bütçe ve gündem panellerini `HudRoot.open_panel` ile açar,
## akış durumunu (`ZoningFlowModel`, `BudgetDraft`) panel yeniden kurulsa da (profil/yön değişimi) korur, sim
## olaylarını akışlara dağıtır, gündem rozetini gerçek (türetilmiş) veriden besler ve nedensellik paneli isteğini
## (`reason_wanted`) ana sahneye iletir. UI yalnız `SimFacade` tipine bağlıdır (mock <-> gerçek sim: kod değişmez).
##
## Ana sahne: `var decisions := DecisionPanels.attach(hud, facade)`; araç çubuğundaki Yönetim araçları ve gündem rozeti
## otomatik bağlanır. İmar aracı parsel seçimine bağlıdır: ana sahne `open_zoning(parcel_ids)` çağırır ve panel açıkken
## seçilen parselleri `add_zoning_parcel` ile alana ekler.

signal reason_wanted(initial: Callable)
signal auto_paused(item_id: StringName)

const PANEL_ZONING := &"zoning"
const PANEL_COUNCIL := &"council"
const PANEL_BUDGET := &"budget"
const PANEL_AGENDA := &"agenda"

var hud: HudRoot = null
var facade: SimFacade = null
var zoning: ZoningFlowModel = null
var budget_draft: BudgetDraft = BudgetDraft.new()

var _zoning_panel: ZoningFlowPanel = null
var _council_panel: CouncilPanel = null
var _budget_panel: BudgetPanel = null
var _agenda_panel: AgendaPanel = null
var _seen_agenda: Dictionary = {}
var _agenda_ready: bool = false


static func attach(hud_in: HudRoot, facade_in: SimFacade) -> DecisionPanels:
	var d := DecisionPanels.new()
	d.hud = hud_in
	d.facade = facade_in
	hud_in.refreshed.connect(d._on_refreshed)
	hud_in.events_received.connect(d._on_events)
	hud_in.panel_closed.connect(d._on_panel_closed)
	hud_in.agenda_requested.connect(d.open_agenda)
	hud_in.tool_selected.connect(d.on_tool_selected)
	d._on_refreshed()
	return d


## Facade değişti (geliştirme sahnesi): akış durumları sıfırlanır.
func rebind(facade_in: SimFacade) -> void:
	facade = facade_in
	zoning = null
	budget_draft = BudgetDraft.new()
	_seen_agenda = {}
	_agenda_ready = false


# --- Panel açma ---

## Yeni imar önerisi: önceki akış bitmiş ya da henüz gönderilmemişse alan `parcel_ids` ile yeniden başlar; gönderilmiş
## ve süren bir öneri varsa korunur (ilerleme görünür kalır).
func open_zoning(parcel_ids: PackedInt64Array = PackedInt64Array()) -> void:
	if zoning == null or not zoning.is_locked() or zoning.is_finished():
		zoning = ZoningFlowModel.create(facade)
		for id in parcel_ids:
			zoning.add_parcel(id)
	hud.open_panel(PANEL_ZONING, &"zoning.title", _build_zoning)


## Panel açıkken haritadan seçilen parseli alana ekler. Eklendiyse true.
func add_zoning_parcel(parcel_id: int) -> bool:
	if hud.panel_id() != PANEL_ZONING or zoning == null:
		return false
	if _zoning_panel != null and is_instance_valid(_zoning_panel):
		return _zoning_panel.add_parcel(parcel_id)
	return zoning.add_parcel(parcel_id)


func open_council() -> void:
	hud.open_panel(PANEL_COUNCIL, &"council.title", _build_council)


func open_budget() -> void:
	hud.open_panel(PANEL_BUDGET, &"budget.title", _build_budget)


func open_agenda() -> void:
	hud.open_panel(PANEL_AGENDA, &"agenda.title", _build_agenda)


## Yönetim araçları (bütçe, meclis, gündem). Ele alındıysa true.
func on_tool_selected(tool_id: StringName) -> bool:
	match tool_id:
		ModeToolbar.TOOL_BUDGET:
			open_budget()
		ModeToolbar.TOOL_COUNCIL:
			open_council()
		ModeToolbar.TOOL_AGENDA:
			open_agenda()
		_:
			return false
	return true


func zoning_panel() -> ZoningFlowPanel:
	return _zoning_panel if _alive(_zoning_panel) else null


func council_panel() -> CouncilPanel:
	return _council_panel if _alive(_council_panel) else null


func budget_panel() -> BudgetPanel:
	return _budget_panel if _alive(_budget_panel) else null


func agenda_panel() -> AgendaPanel:
	return _agenda_panel if _alive(_agenda_panel) else null


func _alive(panel: Control) -> bool:
	return panel != null and is_instance_valid(panel) and panel.is_inside_tree()


# --- İçerik kurucuları (profil değişince yeniden çağrılır) ---

func _build_zoning(ctx: UiContext) -> Control:
	var p := ZoningFlowPanel.create(ctx, facade, zoning)
	_wire(p)
	_zoning_panel = p
	return p


func _build_council(ctx: UiContext) -> Control:
	var p := CouncilPanel.create(ctx, facade)
	_wire(p)
	_council_panel = p
	return p


func _build_budget(ctx: UiContext) -> Control:
	var p := BudgetPanel.create(ctx, facade, budget_draft)
	_wire(p)
	_budget_panel = p
	return p


func _build_agenda(ctx: UiContext) -> Control:
	var p := AgendaPanel.create(ctx, facade)
	_wire(p)
	_agenda_panel = p
	return p


func _wire(panel: FlowPanel) -> void:
	panel.reason_requested.connect(reason_wanted.emit)
	panel.navigate_requested.connect(_on_navigate)


func _on_navigate(target: StringName) -> void:
	if target == PANEL_COUNCIL:
		open_council()
	elif target == PANEL_BUDGET:
		open_budget()


# --- Sim olayları ve yenileme ---

func _on_events(events: Array[SimEvent]) -> void:
	for e in events:
		if zoning_panel() != null:
			zoning_panel().handle_event(e)
		elif zoning != null:
			zoning.handle_event(e)
		budget_draft.handle_event(e)
		if budget_panel() != null:
			budget_panel().handle_event(e)


func _on_refreshed() -> void:
	var snap := hud.snapshot()
	if snap == null:
		return
	_update_agenda(snap)
	for panel: FlowPanel in [council_panel(), budget_panel(), agenda_panel()]:
		if panel != null:
			panel.refresh()


func _update_agenda(snap: SimSnapshot) -> void:
	var items := AgendaModel.derive(snap)
	hud.set_agenda(items.size(), AgendaModel.nearest_days(items), facade.is_mock())
	var fresh := AgendaModel.unseen(items, _seen_agenda)
	for it in items:
		_seen_agenda[it.id] = true
	if not _agenda_ready:
		_agenda_ready = true  # açılıştaki mevcut öğeler "yeni" sayılmaz (yüklemede duraklatma yok)
		return
	if not fresh.is_empty() and UiPrefs.auto_pause_agenda() and facade.speed() != SimFacade.SPEED_PAUSED:
		facade.set_speed(SimFacade.SPEED_PAUSED)
		auto_paused.emit(fresh[0])


func _on_panel_closed(panel_id: StringName) -> void:
	match panel_id:
		PANEL_ZONING:
			_zoning_panel = null
		PANEL_COUNCIL:
			_council_panel = null
		PANEL_BUDGET:
			_budget_panel = null
		PANEL_AGENDA:
			_agenda_panel = null
