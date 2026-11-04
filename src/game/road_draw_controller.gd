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
## İmleç önizlemesinin en sık çalışma aralığı (ms). Her denetim sim kuru koşusu + panel yeniden çizimi + önizleme
## ağı kurar (ölçüm: tools/godot/road_ux_probe.gd, ~12 ms/adım); fare olayı başına değil ~20 Hz'de çalışır, aradaki
## hareketler birleştirilir (son konum `process`te uygulanır).
const HOVER_INTERVAL_MSEC := 50
## T-042b: kamulaştırma teklifi hesabı pahalıdır (~10 ms; sim `nearby` O(parsel)). Aralık son `hover_at` süresinin bu
## katı
## kadar uzar (görev döngüsü <= ~%15); ucuz denetimde (<~8 ms) aralık HOVER_INTERVAL_MSEC'te kalır.
const HOVER_COST_FACTOR := 7.0
## İmleç önizlemesinde yan panelin en sık yeniden çizilme aralığı (ms): panel düğüm kurar (~6,6 ms/çizim); imleçle aynı
## hızda gerekmez.
const PANEL_HOVER_INTERVAL_MSEC := 250
## B-012: panel "dünya hazırlanıyor" gösterirken sim'e bu aralıkla yeniden sorulur (olay gelmez; ~1 doğrulama/aralık).
const WORLD_POLL_INTERVAL_MSEC := 200

var tool: RoadDrawTool = null
var preview: RoadDraftPreview = null
var tip: RoadCursorTip = null
## Yolun bitiş ucuna bağlı büyük onay işareti (Adım 3/3, yol yapılabilirse).
var chip: RoadConfirmChip = null
## Dev/yakalama: imleç etiketi bu dünya noktasının ekran karşılığına oturur (fare konumu yerine).
var dev_tip_world: Variant = null

var _hud: HudRoot = null
var _camera: CameraRig = null
var _net: WorldNetwork = null
var _panel: RoadDrawPanel = null
var _cursor: Vector2 = Vector2.ZERO
var _touch: bool = false
var _last_hover_msec: int = -HOVER_INTERVAL_MSEC
var _hover_cost_msec: float = 0.0
var _hover_pending: bool = false
var _have_cursor: bool = false
var _last_panel_msec: int = -PANEL_HOVER_INTERVAL_MSEC
var _panel_pending: bool = false
## Son imleç önizlemesinin çalıştığı kare: panel yeniden çizimi (düğüm kurulumu ~6-13 ms) AYNI karede yapılmaz,
## sonraki kareye kayar (ilk imleç hareketi karesi: sim kuru koşusu + önizleme ağı + panel tek karede ~30-40 ms'ydi).
var _hover_frame: int = -1
var _click_in_progress: bool = false
## Sim olayı (yol yapıldı/geri alındı) panel yenilemesini SONRAKİ kareye bırakır: HUD yoklama karesi (tick'li
## kare) zaten
## sim + şerit + ipucu içerir; panelin düğüm kurulumu (~9 ms ölçüldü) aynı kareye binmesin.
var _panel_due: bool = false
var _in_events: bool = false
var _last_world_poll_msec: int = 0
var _owns_panel: bool = true


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
	c.tip.follow_hud(hud)   # B-019: yüzen kart değişince ipucu yeniden yerleşir (tek yerleşim mantığı)
	c.chip = RoadConfirmChip.create(hud.ctx)
	overlay.add_child(c.chip)
	c.chip.confirm_requested.connect(c.confirm)
	var keys := RoadDrawKeys.new()
	keys.ctrl = c
	overlay.add_child(keys)
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
		if _hud.panel_id() != PANEL_ID:   # başka panel yerimizi aldı: "Yol çiz"e yeniden dokunmak paneli geri getirir
			_hud.open_panel(PANEL_ID, &"road.title", _build_panel)
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
	_have_cursor = true
	_hover_pending = false   # tıklama kendi konumunu uygular; eski bekleyen hareket onu ezmesin
	var world := _ground_xz(screen_pos)
	if world.is_empty():
		return true
	_click_in_progress = true
	tool.tap_at(world["p"], _snap_radius_m(screen_pos))
	_click_in_progress = false
	return true


## Her kare (playable `_process`): ağ başka yoldan değiştiyse açık taslağı sim'e yeniden doğrulatır.
func process() -> void:
	_poll_world_ready()
	_follow_panel_ownership()
	if tool.is_active():
		tool.refresh_if_graph_changed()
		_place_chip()
		if _hover_pending and Time.get_ticks_msec() - _last_hover_msec >= hover_interval_msec():
			_apply_hover()
		if _panel_pending and Time.get_ticks_msec() - _last_panel_msec >= PANEL_HOVER_INTERVAL_MSEC \
				and Engine.get_process_frames() > _hover_frame:
			_refresh_panel()
		elif _panel_due:
			_refresh_panel()
		if panel() != null:
			panel().pump_hint()   # plan ipucu taraması kare dilimli (yol onayından sonraki ilk karede ~45 ms'ydi)


## B-014: yol paneli yerini başka bir panele (gündem, gerekçe) bırakınca araç dokunuş beklemez: imleç/ipucu etiketi ve
## onay işareti çekilir (bildirim düğmelerini örtmesin); panel geri gelince yeniden çizilir. `HudRoot` yer değişiminde
## sinyal vermez, bu yüzden her karede kimlik karşılaştırılır (ucuz).
func _follow_panel_ownership() -> void:
	var owns := _hud.panel_id() == PANEL_ID
	if owns == _owns_panel:
		return
	_owns_panel = owns
	if tool.is_active():
		_sync_visuals()


## B-012: panel sim'in "dünya hazırlanıyor" reddini gösterirken, görünüm işi bitince (olay yok, duraklatılmış oyunda da)
## paneli yeniden doğrulatır; imza değişmediyse düğüm kurulmaz.
func _poll_world_ready() -> void:
	var p := panel()
	if p == null or not p.awaiting_world():
		return
	var now := Time.get_ticks_msec()
	if now - _last_world_poll_msec < WORLD_POLL_INTERVAL_MSEC:
		return
	_last_world_poll_msec = now
	p.refresh()


## Masaüstü imleç önizlemesi: yalnız UI'nin tüketmediği fare hareketi (`_unhandled_input`) gelir, yani imleç panel/araç
## çubuğu üstündeyken önizleme güncellenmez. ~1 ms'lik denetim yalnız imleç `HOVER_EPSILON_M`den fazla oynayınca
## çalışır.
func handle_motion(event: InputEventMouseMotion) -> void:
	if _touch or not tool.is_active() or not tool.band_active:
		return
	if tool.step != RoadDrawTool.Step.PICK_A and tool.step != RoadDrawTool.Step.PICK_B:
		return
	_cursor = event.position
	_have_cursor = true
	if Time.get_ticks_msec() - _last_hover_msec < hover_interval_msec():
		_hover_pending = true   # son konum bir sonraki `process`te uygulanır
		return
	_apply_hover()


## Güncel imleç önizleme aralığı (ms): son denetim pahalıysa uzar (`HOVER_COST_FACTOR`).
func hover_interval_msec() -> int:
	return maxi(HOVER_INTERVAL_MSEC, int(_hover_cost_msec * HOVER_COST_FACTOR))


## Bekleyen/yeni imleç konumunu araca uygular (en çok `hover_interval_msec`te bir).
func _apply_hover() -> void:
	_hover_pending = false
	_last_hover_msec = Time.get_ticks_msec()
	if _touch or not tool.is_active() or not tool.band_active:
		return
	if tool.step != RoadDrawTool.Step.PICK_A and tool.step != RoadDrawTool.Step.PICK_B:
		return
	var world := _ground_xz(_cursor)
	if world.is_empty():
		return
	var t_cost := Time.get_ticks_usec()
	_hover_frame = Engine.get_process_frames()
	tool.hover_at(world["p"], _snap_radius_m(_cursor))
	_hover_cost_msec = (Time.get_ticks_usec() - t_cost) / 1000.0
	if not tip.visible:
		_sync_visuals()   # ilk imleç hareketi: adım yönergesi görünür
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
	_in_events = true
	tool.on_events(events)
	_in_events = false
	_panel_due = panel() != null


func _on_refreshed() -> void:
	if panel() != null:
		panel().refresh()


func _on_tool_changed() -> void:
	_sync_visuals()
	if panel() == null:
		return
	if _in_events:
		_panel_due = true   # olay kaynaklı değişim: panel sonraki karede çizilir (`process`)
		return
	# İmleç önizlemesinde panel her adımda yeniden kurulmaz (ölçüm: ~6,6 ms/adım); en çok PANEL_HOVER_INTERVAL_MSEC'te bir.
	# Dokunuş/onay/iptal adımlarında (PICK_B dışı ya da tıklama) hemen çizilir.
	if tool.step == RoadDrawTool.Step.PICK_B and not _click_in_progress \
			and (Time.get_ticks_msec() - _last_panel_msec < PANEL_HOVER_INTERVAL_MSEC
			or Engine.get_process_frames() == _hover_frame):
		_panel_pending = true
		return
	_refresh_panel()


func _refresh_panel() -> void:
	_panel_pending = false
	_panel_due = false
	_last_panel_msec = Time.get_ticks_msec()
	if panel() != null:
		panel().refresh()


func _build_panel(ctx: UiContext) -> Control:
	_panel = RoadDrawPanel.create(ctx, _hud.facade, tool)
	return _panel


## Aracın durumundan dünya içi önizleme + imleç etiketi + bitiş ucu onay işareti.
func _sync_visuals() -> void:
	match tool.step:
		RoadDrawTool.Step.PICK_A:
			if bool(tool.hover["snapped"]) and tool.band_active:
				preview.show_snap(tool.hover["pos"])
			else:
				preview.clear()
			# Adım 1/3 yönergesi imleç yanında (imleç henüz hareket etmediyse yer belli değil: görünmez).
			if tool.band_active and (_have_cursor or _touch or dev_tip_world is Vector2):
				tip.show_text("", true, _step_line(1))
				_place_tip()
			else:
				tip.hide_tip()
		RoadDrawTool.Step.PICK_B, RoadDrawTool.Step.REVIEW, RoadDrawTool.Step.SENDING:
			if tool.verdict == null:
				preview.show_snap(tool.start)
				if tool.step == RoadDrawTool.Step.PICK_B and tool.band_active and _have_cursor:
					tip.show_text("", true, _step_line(2))
					_place_tip()
				else:
					tip.hide_tip()
			else:
				preview.show_draft(tool.start, tool.end, _net.rules.width_of(RoadDrawTool.ROAD_CLASS), tool.is_valid(),
						conflict_outline())
				_show_tip()
		_:
			preview.clear()
			tip.hide_tip()
	_place_chip()


## Adım yönergesi (imleç etiketi): 1/3 başlangıç, 2/3 bitiş, 3/3 onay. Dokunmatikte "dokun", masaüstünde "tıkla".
func _step_line(n: int) -> String:
	return UiText.t(StringName("road.tip.step%d%s" % [n, "_touch" if _touch else ""]))


## Yol yapılabilirse (Adım 3/3) bitiş ucuna bağlı büyük onay işareti görünür; her karede kamerayla birlikte taşınır.
func _place_chip() -> void:
	if chip == null:
		return
	var show := tool.is_active() and tool.band_active and tool.step == RoadDrawTool.Step.REVIEW and tool.can_confirm() \
			and _hud.panel_id() == PANEL_ID
	if not show:
		chip.visible = false
		return
	chip.theme = _hud.theme
	chip.set_demolition(tool.demolishes())
	var o := _camera.rebase_origin
	var screen := _camera.camera.unproject_position(Vector3(tool.end.x - o.x, 0.0, tool.end.y - o.y))
	chip.visible = true
	chip.place_at(screen, _hud.free_map_rect())


## Dev/yakalama (`--road-preview`): kamerayı taslağın ortasına alır (oyun akışında kullanılmaz).
func dev_focus_draft(a: Vector2, b: Vector2, distance_m: float) -> void:
	var st := _camera.target_state()
	var mid := (a + b) * 0.5
	st.focus_x = mid.x
	st.focus_z = mid.y
	st.distance = distance_m
	_camera.apply_state(st, true)


## Onay (işarete tıklama / Enter / aynı noktaya yeniden tıklama): komut yalnız araçtan gider.
func confirm() -> void:
	if not tool.is_active() or not tool.can_confirm():
		return
	tool.confirm()
	if panel() != null:
		panel().refresh()


## Enter ile onay (Boşluk DEĞİL: Boşluk duraklatır). true = tüketildi. Odak bir düğmedeyse Godot kendi `ui_accept`ini
## işler ve bu çağrıya gelmez; yani çift onay olmaz.
func handle_key(event: InputEventKey) -> bool:
	if not event.pressed or event.echo or not tool.is_active():
		return false
	if event.keycode != KEY_ENTER and event.keycode != KEY_KP_ENTER:
		return false
	if not tool.can_confirm():
		return false
	confirm()
	return true


## Ret noktası bir parsele düşüyorsa o parselin sınırı (haritada "neden reddedildi"); yoksa boş. Yalnız OKUR.
func conflict_outline() -> PackedVector2Array:
	if tool.verdict == null or not tool.verdict.is_rejected():
		return PackedVector2Array()
	var args := tool.verdict.args
	if not (args.has("at_x_cm") and args.has("at_z_cm")):
		return PackedVector2Array()
	var at := Vector2(float(args["at_x_cm"]), float(args["at_z_cm"])) * 0.01
	var block := _net.block_at(at.x, at.y)
	if block == null:
		return PackedVector2Array()
	var best: WorldParcel = null
	var best_d := INF
	for pid in block.parcel_ids:
		var parcel := _net.parcel(pid)
		if parcel == null or parcel.outline.size() < 3:
			continue
		if Geometry2D.is_point_in_polygon(at, parcel.outline):
			return parcel.outline
		var d := parcel.centroid.distance_squared_to(at)
		if d < best_d:
			best_d = d
			best = parcel
	return best.outline if best != null else PackedVector2Array()


func _show_tip() -> void:
	if tool.step == RoadDrawTool.Step.SENDING or not tool.band_active:
		tip.hide_tip()
		return
	var step_line := _step_line(3) if tool.step == RoadDrawTool.Step.REVIEW and tool.is_valid() else _step_line(2)
	if tool.is_valid() and tool.demolishes():   # T-042b: yıkım sayıları sim önizlemesinden
		tip.show_text(ExpropriationText.tip_line(tool.preview_args()), true, step_line)
	elif tool.is_valid():
		var args := tool.preview_args()
		var tip_key := &"road.tip_valid_cost" if bool(args.get("cost_available", false)) else &"road.tip_valid"
		tip.show_text(UiText.t(tip_key, {"length": int(args.get("length_m", 0)),
				"units": int(args.get("units_total", 0)), "cost": UiText.number(int(args.get("cost", 0)))}),
				true, step_line)
	else:
		tip.show_text(UiText.reject_reason(tool.verdict.reason_key, tool.verdict.args), false, step_line)
	_place_tip()


func _place_tip() -> void:
	if not tip.visible:
		return
	if tool.is_active() and _hud.panel_id() != PANEL_ID:
		tip.hide_tip()   # başka panel yol panelinin yerini aldı: etiket kalmaz (B-014)
		return
	tip.theme = _hud.theme
	var obstacles := _hud.occupied_rects()   # bildirim satırları + hız ipucu: kart bunların üstüne binmez (B-014)
	if dev_tip_world is Vector2:
		var w: Vector2 = dev_tip_world
		var o := _camera.rebase_origin
		var screen := _camera.camera.unproject_position(Vector3(w.x - o.x, 0.0, w.y - o.y))
		tip.place_near(screen, _hud.get_viewport().get_visible_rect().size, _hud.free_map_rect(), obstacles)
	elif _touch:
		tip.place_at_top(_hud.free_map_rect(), obstacles)
	else:
		tip.place_near(_cursor, _hud.get_viewport().get_visible_rect().size, _hud.free_map_rect(), obstacles)


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
