extends Control
## ui_lab (T-019): HUD iskeleti + panel kabuğu + denetçi + mini imar akışı, `MockSimFacade` ile.
## UI yalnız `SimFacade` tipine bağlıdır; harita yer tutucusu (UiLabMap) dev amaçlıdır. MOCK her yerde
## işaretlidir.
##
## Açma:   tools/godot.sh --path . res://scenes/dev/ui_lab.tscn -- [--imaro-input-profile=touch]
## [--ui-lab-scenario=NAME]
##                         [--ui-lab-safe=ÜST,SAĞ,ALT,SOL] [--ui-lab-demo=ADIM]
## Senaryo: declined (varsayılan) | positive | groups | council | invalid
## Demo adımları (capture için, tick sürücüsü kapalı): home | inspect | zoning | reject | done | protected |
## states | reason (senaryonun gerekçe paneli) | reason_list | reason_parcel | reason_actor | reason_rejected |
## reason_bad (tutarsız kayıt, yalnız dev) | reason_chain (zincir gezinmesi, yalnız dev)
## Klavye (dev): N seçili parselin gerekçeleri · F5 aktör listesi (aktör girişi önizlemesi) · F1 masaüstü profili · F2 iPad yatay (1366x1024) · F3 iPad dikey (1024x1366) · F4 güvenli alan
## simülasyonu
##
## DEV metinleri aşağıdaki sabitlerdedir (oyuncu UI'ı değildir; oyun metinleri UiText'ten gelir).

const SCENARIO_FILES := {
	"declined": "res://tests/fixtures/mock_scenario_investment_declined.json",
	"positive": "res://tests/fixtures/mock_scenario_investment_positive.json",
	"groups": "res://tests/fixtures/mock_scenario_group_reactions.json",
	"council": "res://tests/fixtures/mock_scenario_council_budget_vote.json",
	"invalid": "res://tests/fixtures/mock_scenario_invalid_commands.json",
}
## Dev tick sürücüsü: hız basamağı -> saniyedeki tick (gerçek eşleme sim sürücü yapılandırması, ÇM).
const DEV_TICKS_PER_SECOND := {0: 0.0, 1: 1.0, 2: 2.0, 3: 4.0}
const SAFE_SIMULATION := Vector4(0.0, 24.0, 0.0, 20.0)

var facade: SimFacade = null
var hud: HudRoot = null
var map: UiLabMap = null

var scenario_name_in_use: String = "declined"
var _platform: PlatformProfile = null
var _selected: int = 0
var _inspector: ParcelInspector = null
var _zoning: UiLabZoning = null
var _reason_panel: ReasonPanel = null
var _reason_nav: Array[Dictionary] = []
var _reason_initial: Callable = Callable()
var _driver_on: bool = true
var _accum: float = 0.0
var _seen_tick: int = -1
var _event_cursor: int = 0


func _ready() -> void:
	var args := _parse_args()
	_driver_on = not args.has("demo")
	var scenario_name: String = args.get("scenario", "declined")
	scenario_name_in_use = scenario_name if SCENARIO_FILES.has(scenario_name) else "declined"
	facade = MockSimFacade.from_file(SCENARIO_FILES[scenario_name_in_use])
	_platform = PlatformProfile.detect()
	map = UiLabMap.new()
	add_child(map)
	hud = HudRoot.new()
	hud.simulated_safe = _parse_safe(str(args.get("safe", "")))
	add_child(hud)
	hud.layout_changed.connect(_on_layout_changed)
	hud.tool_selected.connect(_on_tool_selected)
	hud.reason_requested.connect(_on_event_reason)
	hud.panel_closed.connect(_on_panel_closed)
	hud.setup(facade, _platform)
	_after_profile()
	if args.has("demo"):
		await get_tree().process_frame
		await get_tree().process_frame
		_run_demo(str(args["demo"]))


func _process(delta: float) -> void:
	if _driver_on and facade != null:
		var rate: float = DEV_TICKS_PER_SECOND.get(facade.speed(), 0.0)
		_accum += delta * rate
		while _accum >= 1.0:
			_accum -= 1.0
			facade.advance(1)
	if facade != null and facade.last_event_seq() != _event_cursor:
		_dispatch_events()
	if facade != null and facade.current_tick() != _seen_tick:
		_seen_tick = facade.current_tick()
		map.reload()
		_refresh_inspector()
		if _reason_panel != null and is_instance_valid(_reason_panel):
			_reason_panel.refresh()


func _dispatch_events() -> void:
	for e in facade.events_since(_event_cursor):
		_event_cursor = e.seq
		if _zoning != null and is_instance_valid(_zoning):
			_zoning.handle_event(e)


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_F1:
			_switch_profile(PlatformProfile.INPUT_DESKTOP, Vector2i(1600, 900))
		KEY_F2:
			_switch_profile(PlatformProfile.INPUT_TOUCH, Vector2i(1366, 1024))
		KEY_F3:
			_switch_profile(PlatformProfile.INPUT_TOUCH, Vector2i(1024, 1366))
		KEY_N:
			_open_reason(func(p: ReasonPanel) -> void: p.show_subject(StringName("parcel.%d" % maxi(_selected, 1))))
		KEY_F5:
			open_actors()
		KEY_F4:
			hud.simulated_safe = Vector4.ZERO if hud.simulated_safe != Vector4.ZERO else SAFE_SIMULATION
			hud.apply_profile(_platform)
			_after_profile()


func select_parcel(parcel_id: int) -> void:
	_selected = parcel_id
	map.select(parcel_id)
	if parcel_id <= 0:
		if hud.panel_id() == &"inspector":
			hud.close_panel_soft()
		return
	hud.open_panel(&"inspector", &"inspector.title", _build_inspector)


func open_actors() -> void:
	hud.open_panel(&"actors", &"reason.open_actor", _build_actors)


func reason_panel() -> ReasonPanel:
	return _reason_panel if _reason_panel != null and is_instance_valid(_reason_panel) else null


func open_zoning() -> void:
	hud.open_panel(&"zoning", &"zoning.title", _build_zoning)


func state() -> Dictionary:
	return {"selected": _selected, "panel": hud.panel_id(), "tick": facade.current_tick()}


func zoning_flow() -> UiLabZoning:
	return _zoning


func _switch_profile(profile_name: StringName, window_size: Vector2i) -> void:
	_platform = PlatformProfile.from_tags(PackedStringArray(), {"input_profile": profile_name})
	get_window().size = window_size
	hud.apply_profile(_platform)
	_after_profile()


func _after_profile() -> void:
	map.bind(facade, hud.ctx)
	hud.input.select_requested.connect(_on_select_screen)
	# Masaüstü fare ile dokunmatik profili önizlemek için: fare -> dokunma olayı (yalnız bu dev sahnede).
	Input.emulate_touch_from_mouse = _platform.input_profile == PlatformProfile.INPUT_TOUCH
	get_window().title = "%s | %s" % [UiText.t(&"app.title"), _platform.describe()]
	_on_layout_changed()


func _on_layout_changed() -> void:
	if map != null and hud != null and hud.layout != null:
		map.set_fit_rect(hud.free_map_rect())


func _on_select_screen(screen_pos: Vector2) -> void:
	select_parcel(map.pick(screen_pos))


func _on_tool_selected(tool_id: StringName) -> void:
	if tool_id == ModeToolbar.TOOL_ZONE:
		open_zoning()
	elif tool_id == ModeToolbar.TOOL_INSPECT:
		hud.open_panel(&"inspector", &"inspector.title", _build_inspector)


func _on_panel_closed(_id: StringName) -> void:
	_inspector = null
	_zoning = null
	_reason_panel = null
	_reason_nav = []


func _on_event_reason(event: SimEvent) -> void:
	_open_reason(func(p: ReasonPanel) -> void: p.show_event(event))


func _on_inspector_reason(subject_ref: StringName) -> void:
	open_reason_for(subject_ref)


func open_reason_for(subject_ref: StringName) -> void:
	_open_reason(func(p: ReasonPanel) -> void: p.show_subject(subject_ref))


## Gerekçe panelini açar; `initial(panel)` ilk görünümü kurar. Profil değişince panel yeniden kurulur ve gezinti
## durumu geri yüklenir.
func _open_reason(initial: Callable) -> void:
	_reason_nav = []
	_reason_initial = initial
	hud.open_panel(&"reason", &"reason.title", _build_reason)


func _build_reason(c: UiContext) -> Control:
	var p := ReasonPanel.create(c, facade)
	p.map_enabled = true
	p.map_focus_requested.connect(_on_reason_map)
	_reason_panel = p
	if not _reason_nav.is_empty():
		p.restore_nav(_reason_nav)
	elif _reason_initial.is_valid():
		_reason_initial.call(p)
	p.nav_changed.connect(func() -> void: _reason_nav = p.nav_state())
	_reason_nav = p.nav_state()
	return p


func _on_reason_map(subject_ref: StringName) -> void:
	var parsed := SimContract.parse_ref(subject_ref)
	if parsed["kind"] == String(SimContract.REF_PARCEL):
		_selected = int(parsed["id"])
		map.select(_selected)


func _build_actors(c: UiContext) -> Control:
	var list := UiLabActors.create(c, facade)
	list.actor_chosen.connect(func(ref: StringName) -> void:
		_open_reason(func(p: ReasonPanel) -> void: p.show_subject(ref)))
	return list


func _build_inspector(c: UiContext) -> Control:
	_inspector = ParcelInspector.create(c)
	_inspector.reason_requested.connect(_on_inspector_reason)
	_refresh_inspector()
	return _inspector


func _build_zoning(c: UiContext) -> Control:
	_zoning = UiLabZoning.create(c, facade, _selected)
	return _zoning


func _refresh_inspector() -> void:
	if _inspector == null or not is_instance_valid(_inspector):
		return
	if _selected <= 0:
		_inspector.show_nothing()
		return
	var views := facade.parcel_views(PackedInt64Array([_selected]))
	if views.is_empty():
		_inspector.show_nothing()
	else:
		_inspector.show_parcel(views[0], facade.is_mock())


func _run_demo(step: String) -> void:
	facade.set_speed(SimFacade.SPEED_PAUSED)
	match step:
		"inspect":
			select_parcel(1)
		"zoning":
			select_parcel(1)
			open_zoning()
		"reject":
			select_parcel(1)
			open_zoning()
			_zoning.choose_use(&"zone.industrial")
		"done":
			select_parcel(1)
			open_zoning()
			_zoning.choose_use(&"zone.mixed")
			_zoning.send()
			facade.advance(6)
			_dispatch_events()
			hud.refresh()
			map.reload()
			_open_reason(func(p: ReasonPanel) -> void: p.show_reason_ids(_first_reason_ids()))
		"protected":
			select_parcel(2)
			open_zoning()
			_zoning.choose_use(&"zone.commercial")
			_zoning.send()
			facade.advance(3)
			_dispatch_events()
			hud.refresh()
			map.reload()
		"reason", "reason_list", "reason_parcel", "reason_actor", "reason_rejected", "reason_bad", "reason_chain":
			_demo_reason(step)
		"states":
			hud.set_agenda(2, 5, true)
			hud.open_panel(&"states", &"inspector.title", _build_state_gallery)
	hud.refresh()


## Gerekçe paneli capture demoları: senaryoyu gerekçe oluşana dek oynatır, sonra ilgili girişi açar.
func _demo_reason(step: String) -> void:
	_play_scenario()
	match step:
		"reason":
			_open_reason(func(p: ReasonPanel) -> void: p.show_reason_ids(_first_reason_ids()))
		"reason_list":
			var ids := _all_reason_ids()
			_open_reason(func(p: ReasonPanel) -> void:
				p.show_reason_ids(ids)
				if ids.size() == 1:
					return)
		"reason_parcel":
			select_parcel(1)
			_open_reason(func(p: ReasonPanel) -> void: p.show_subject(&"parcel.1"))
		"reason_actor":
			var ids2 := _all_reason_ids()
			var first := facade.reason(ids2[0]) if not ids2.is_empty() else null
			_open_reason(func(p: ReasonPanel) -> void:
				if first != null and first.actor != null:
					p.show_subject(first.actor.ref()))
		"reason_rejected":
			for e in facade.events_since(0):
				if e.kind == SimEvent.KIND_COMMAND_REJECTED:
					var rejected := e
					_open_reason(func(p: ReasonPanel) -> void: p.show_event(rejected))
					break
		"reason_bad":
			var good := facade.reason(1)
			var bad_list: Array[ReasonRecord] = []
			if good != null:
				bad_list.append(UiLabReasonFacade.corrupt(good, 450, true))
			_swap_facade(UiLabReasonFacade.with_records(SCENARIO_FILES[scenario_name_in_use], bad_list))
			_open_reason(func(p: ReasonPanel) -> void: p.show_record(1))
		"reason_chain":
			_swap_facade(UiLabReasonFacade.with_records(SCENARIO_FILES[scenario_name_in_use],
				UiLabReasonFacade.chain_records()))
			_open_reason(func(p: ReasonPanel) -> void: p.show_record(3))


func _swap_facade(next: SimFacade) -> void:
	facade = next
	hud.facade = next
	map.bind(next, hud.ctx)
	_event_cursor = 0


func _play_scenario() -> void:
	match scenario_name_in_use:
		"invalid":
			facade.submit_command(SimCommand.zoning_propose(PackedInt64Array([2]), &"zone.commercial"))
			facade.advance(3)
		"groups":
			facade.submit_command(SimCommand.zoning_propose(PackedInt64Array([2]), &"zone.commercial"))
			facade.advance(6)
		"council":
			facade.submit_command(SimCommand.budget_propose({&"budget.line.roads": 45000}))
			facade.advance(6)
		"positive":
			facade.submit_command(SimCommand.zoning_propose(PackedInt64Array([1]), &"zone.mixed"))
			facade.advance(8)
		_:
			facade.submit_command(SimCommand.zoning_propose(PackedInt64Array([1]), &"zone.mixed"))
			facade.advance(6)
	hud.refresh()
	map.reload()


func _all_reason_ids() -> PackedInt64Array:
	var ids := PackedInt64Array()
	var n := 1
	while facade.reason(n) != null:
		ids.append(n)
		n += 1
	return ids


func _first_reason_ids() -> PackedInt64Array:
	var ids := PackedInt64Array()
	for e in facade.events_since(0):
		if not e.reason_ids.is_empty():
			ids = e.reason_ids
	return ids


func _build_state_gallery(c: UiContext) -> Control:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var loading := StateView.create(c)
	loading.loading_delay_s = 0.0
	loading.show_loading(40)
	var empty := StateView.create(c)
	empty.show_empty(&"state.empty.no_events")
	var error := StateView.create(c)
	error.show_error(UiText.t(&"state.error.sim_unavailable"))
	var not_built := StateView.create(c)
	not_built.show_not_built(&"council.not_built")
	var disabled := ActionButton.create(c, UiText.t(&"zoning.send"))
	disabled.set_enabled(false, UiText.t(&"zoning.pick_use"))
	for v: Control in [loading, empty, error, not_built, disabled]:
		var card := PanelContainer.new()
		card.add_child(v)
		box.add_child(card)
	return box


func _parse_args() -> Dictionary:
	var out := {}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--ui-lab-") and arg.contains("="):
			out[arg.get_slice("=", 0).trim_prefix("--ui-lab-")] = arg.get_slice("=", 1)
	return out


## "ÜST,SAĞ,ALT,SOL" -> Vector4(sol, üst, sağ, alt); boş/bozuk -> sıfır.
func _parse_safe(text: String) -> Vector4:
	var parts := text.split(",")
	if parts.size() != 4:
		return Vector4.ZERO
	return Vector4(parts[3].to_float(), parts[0].to_float(), parts[1].to_float(), parts[2].to_float())
