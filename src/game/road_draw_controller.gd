class_name RoadDrawController
extends RefCounted
## Yol çizim aracının oyun katmanı YAPIŞTIRICISI (T-042 adım 3): `RoadDrawTool` (durum makinesi) + HUD (araç düğmesi,
## `RoadDrawPanel`, imleç etiketi) + dünya içi önizleme (`RoadDraftPreview`) + girdi (tek paylaşılan `InputProfile`;
## UI dünyadan önce girdi tüketir, dünya tıklaması buraya yalnız UI geçirince gelir). Sim'e yazmaz: komut yalnız araçtan
## `SimFacade.submit_command` ile gider. Yol 3B'ye yansıması `RoadEditSync`tir (playable sürer).
##
## Dürüstlük kuralı: araç düğmesi YALNIZ facade'e yol komutları bağlıysa (`attach_public_works`) kaydedilir.
##
## Kullanıcı fiilleri (masaüstü = dokunmatik): "Yol çiz" düğmesi ya da Y -> yola/yol ucuna dokun (A) -> bitiş (B) ->
## Onayla; Esc / sağ tık = taslağı iptal, ikinci Esc aracı kapatır; "Son yolu geri al".

const PANEL_ID := &"road_draw"
## Yapışma yarıçapı (ekran pikseli): dokunmatik ≥ 44, masaüstü 26.
const SNAP_PX_DESKTOP := 26.0
const SNAP_PX_TOUCH := 44.0
const SNAP_MIN_M := 3.0
const SNAP_MAX_M := 150.0

var tool: RoadDrawTool = null
var preview: RoadDraftPreview = null
var tip: RoadCursorTip = null
## Dev/yakalama: imleç etiketi bu dünya noktasının ekran karşılığına oturur (fare konumu yerine).
var dev_tip_world: Variant = null

var _hud: HudRoot = null
var _camera: CameraRig = null
var _net: WorldNetwork = null
var _panel: RoadDrawPanel = null
var _cursor: Vector2 = Vector2.ZERO
var _touch: bool = false


## Yol komutları bağlı değilse (facade gerçek sim değil / `attach_public_works` yapılmadı) null: araç hiç görünmez.
static func attach(hud: HudRoot, camera: CameraRig, net: WorldNetwork, facade: SimFacade, view_root: Node3D,
		ground: Callable, overlay: CanvasLayer) -> RoadDrawController:
	var impl := facade as SimFacadeImpl
	if impl == null or impl.public_works_context() == null or net == null:
		return null
	var c := RoadDrawController.new()
	c._hud = hud
	c._camera = camera
	c._net = net
	c._touch = hud.ctx != null and hud.ctx.is_touch()
	c.tool = RoadDrawTool.create(net, facade)
	c.preview = RoadDraftPreview.new()
	c.preview.bind(camera, ground)
	view_root.add_child(c.preview)
	c.tip = RoadCursorTip.create()
	overlay.add_child(c.tip)
	# Görsel parçalar kurulduktan SONRA bağlanır (metro bandında açılış `changed` yayar).
	c.tool.changed.connect(c._on_tool_changed)
	c.tool.set_band(camera.scale_band)
	camera.scale_band_changed.connect(c.tool.set_band)
	hud.register_tool(ModeToolbar.MODE_BUILD, ModeToolbar.TOOL_ROAD_DRAW)
	hud.toolbar.select_mode(ModeToolbar.MODE_BUILD)
	hud.tool_selected.connect(c._on_tool_selected)
	hud.panel_closed.connect(c._on_panel_closed)
	hud.events_received.connect(c._on_events)
	hud.refreshed.connect(c._on_refreshed)
	hud.cancel_guard = c._cancel_guard
	camera.input_profile.context_requested.connect(c._on_context)
	return c


func is_active() -> bool:
	return tool.is_active()


func panel() -> RoadDrawPanel:
	return _panel if is_instance_valid(_panel) and _panel.is_inside_tree() else null


## Aracı açar (düğme / Y): paneli açar, araç çubuğunda seçili gösterir.
func activate() -> void:
	if tool.is_active():
		return
	tool.activate()
	_hud.open_panel(PANEL_ID, &"road.title", _build_panel)
	_hud.toolbar.set_active_tool(ModeToolbar.TOOL_ROAD_DRAW)


func deactivate() -> void:
	if not tool.is_active():
		return
	tool.deactivate()
	if _hud.panel_id() == PANEL_ID:
		_hud.close_panel_hard()
	_hud.toolbar.clear_active_tool()
	_sync_visuals()


## Y kısayolu: aç/kapat.
func toggle() -> void:
	if tool.is_active():
		deactivate()
	else:
		activate()


## Dünya tıklaması/dokunması (UI tüketmediyse). true = bu girdi araç tarafından kullanıldı (parsel seçimi YAPILMAZ).
func handle_select(screen_pos: Vector2) -> bool:
	if not tool.is_active():
		return false
	if _hud.panel_id() != PANEL_ID:
		# Başka panel (imar, denetçi) araç panelinin yerini aldı: araç kapanır, girdi normal akışa gider.
		tool.deactivate()
		_hud.toolbar.clear_active_tool()
		_sync_visuals()
		return false
	if tool.step == RoadDrawTool.Step.SENDING:
		return true
	_cursor = screen_pos
	var world := _ground_xz(screen_pos)
	if world.is_empty():
		return true
	tool.tap_at(world["p"], _snap_radius_m(screen_pos))
	return true


## Her kare (playable `_process`): ağ başka yoldan değiştiyse açık taslağı sim'e yeniden doğrulatır.
func process() -> void:
	if tool.is_active():
		tool.refresh_if_graph_changed()


## Masaüstü imleç önizlemesi: yalnız UI'nin tüketmediği fare hareketi (`_unhandled_input`) gelir, yani imleç panel/araç
## çubuğu üstündeyken önizleme güncellenmez. ~1 ms'lik denetim yalnız imleç `HOVER_EPSILON_M`den fazla oynayınca
## çalışır.
func handle_motion(event: InputEventMouseMotion) -> void:
	if _touch or not tool.is_active() or not tool.band_active:
		return
	if tool.step != RoadDrawTool.Step.PICK_A and tool.step != RoadDrawTool.Step.PICK_B:
		return
	_cursor = event.position
	var world := _ground_xz(_cursor)
	if world.is_empty():
		return
	tool.hover_at(world["p"], _snap_radius_m(_cursor))
	_place_tip()


## Esc kancası (HudRoot.cancel_guard): taslak varsa iptal eder (true = tüketildi), yoksa panel kapanır (araç da).
func _cancel_guard() -> bool:
	if not tool.is_active():
		return false
	return tool.cancel()


func _on_context(_screen_pos: Vector2) -> void:
	if tool.is_active() and not tool.cancel():
		deactivate()


func _on_tool_selected(tool_id: StringName) -> void:
	if tool_id == ModeToolbar.TOOL_ROAD_DRAW:
		activate()
	elif tool.is_active():
		# Başka bir araç seçildi: onun paneli açılır; araç kapanır.
		tool.deactivate()
		_sync_visuals()


func _on_panel_closed(panel_id: StringName) -> void:
	if panel_id == PANEL_ID:
		_panel = null
		if tool.is_active():
			tool.deactivate()
			_hud.toolbar.clear_active_tool()
			_sync_visuals()


func _on_events(events: Array[SimEvent]) -> void:
	tool.on_events(events)
	if panel() != null:
		panel().refresh()


func _on_refreshed() -> void:
	if panel() != null:
		panel().refresh()


func _on_tool_changed() -> void:
	_sync_visuals()
	if panel() != null:
		panel().refresh()


func _build_panel(ctx: UiContext) -> Control:
	_panel = RoadDrawPanel.create(ctx, _hud.facade, tool)
	return _panel


## Aracın durumundan dünya içi önizleme + imleç etiketi.
func _sync_visuals() -> void:
	match tool.step:
		RoadDrawTool.Step.PICK_A:
			if bool(tool.hover["snapped"]) and tool.band_active:
				preview.show_snap(tool.hover["pos"])
			else:
				preview.clear()
			tip.hide_tip()
		RoadDrawTool.Step.PICK_B, RoadDrawTool.Step.REVIEW, RoadDrawTool.Step.SENDING:
			if tool.verdict == null:
				preview.show_snap(tool.start)
				tip.hide_tip()
			else:
				preview.show_draft(tool.start, tool.end, _net.rules.width_of(RoadDrawTool.ROAD_CLASS), tool.is_valid())
				_show_tip()
		_:
			preview.clear()
			tip.hide_tip()


func _show_tip() -> void:
	if tool.step == RoadDrawTool.Step.SENDING or not tool.band_active:
		tip.hide_tip()
		return
	if tool.is_valid():
		var args := tool.preview_args()
		tip.show_text(UiText.t(&"road.tip_valid", {"length": int(args.get("length_m", 0)),
				"units": int(args.get("units_total", 0))}), true)
	else:
		tip.show_text(UiText.reject_reason(tool.verdict.reason_key, tool.verdict.args), false)
	_place_tip()


func _place_tip() -> void:
	if not tip.visible:
		return
	tip.theme = _hud.theme
	if dev_tip_world is Vector2:
		var w: Vector2 = dev_tip_world
		var o := _camera.rebase_origin
		var screen := _camera.camera.unproject_position(Vector3(w.x - o.x, 0.0, w.y - o.y))
		tip.place_near(screen, _hud.get_viewport().get_visible_rect().size)
	elif _touch:
		tip.place_at_top(_hud.free_map_rect())
	else:
		tip.place_near(_cursor, _hud.get_viewport().get_visible_rect().size)


func _ground_xz(screen_pos: Vector2) -> Dictionary:
	var g := _camera.screen_to_ground(screen_pos)
	if not bool(g.get("ok", false)):
		return {}
	return {"p": Vector2(float(g["x"]), float(g["z"]))}


## Yapışma yarıçapı (m) = ekran pikseli yarıçapının bu konumdaki dünya karşılığı.
func _snap_radius_m(screen_pos: Vector2) -> float:
	var px := SNAP_PX_TOUCH if _touch else SNAP_PX_DESKTOP
	var a := _camera.screen_to_ground(screen_pos)
	var b := _camera.screen_to_ground(screen_pos + Vector2(px, 0.0))
	if not (bool(a.get("ok", false)) and bool(b.get("ok", false))):
		return SNAP_MIN_M
	var meters := Vector2(float(a["x"]), float(a["z"])).distance_to(Vector2(float(b["x"]), float(b["z"])))
	return clampf(meters, SNAP_MIN_M, SNAP_MAX_M)
