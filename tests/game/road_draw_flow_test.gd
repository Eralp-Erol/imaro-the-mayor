extends GdUnitTestSuite
## T-042 adım 3 (CAN-04, D-008/D-009, WLD-01) · Yol çizimi gerçek viewport yayılımıyla
## (`Viewport.push_input`): "Yol çiz" düğmesi -> yola dokun -> imleçle önizleme (geçerli/ret nedeni) -> ikinci
## dokunuş -> Onayla -> tick -> yol ağda ve 3B chunk'ta -> Geri al. Kamera + HUD düğüm sırası ve paylaşılan
## InputProfile playable.gd ile aynıdır; dünya tıklaması yalnız UI geçirince `RoadDrawController.handle_select`e
## gider (playable `_on_select_requested` ile aynı sıra). Sentetik olaylar gerçek fare/dokunma DEĞİLDİR (cihaz
## davranışı doğrulanmadı).

const P := preload("res://tests/sim/public_works/public_works_support.gd")
const VIEWPORT := Vector2(1600.0, 900.0)
const FOCUS := Vector2(1100.0, 1050.0)
const A := Vector2(1100.0, 1100.0)
const B_OK := Vector2(1100.0, 1000.0)
const B_LONG := Vector2(1100.0, 650.0)

var _scene: Dictionary = {}
var _fallthrough_selects: int = 0


## playable._unhandled_input gibi: UI'nin tüketmediği fare hareketini araca iletir.
class MotionForwarder:
	extends Node
	var ctrl: RoadDrawController = null

	func _unhandled_input(event: InputEvent) -> void:
		if event is InputEventMouseMotion and ctrl != null:
			ctrl.handle_motion(event)


func before_test() -> void:
	UiText.reset()
	UiText.report_missing = false
	_fallthrough_selects = 0
	_scene = {}


func after_test() -> void:
	UiText.reset()


func _build(start_in_metro: bool = false) -> Dictionary:
	get_window().size = Vector2i(VIEWPORT)
	var run := P.setup()
	var f: SimFacadeImpl = run["facade"]
	var net: WorldNetwork = run["net"]
	# Kamera dünyası: sim/ağ koordinatlarıyla AYNI, ama metro bandına erişecek kadar geniş
	# (3 km'lik dünya 1,5 km'de keser).
	var world := NetworkTestSupport.flat_world(60000.0, 1000.0)
	world.origin = Vector2(-30000.0, -30000.0)
	var ground := func(x: float, z: float) -> float: return maxf(world.height_at(x, z), world.sea_level)
	var rig: CameraRig = auto_free(CameraRig.new())
	rig.input_profile = InputProfile.create(&"desktop")
	rig.viewport_size_override = VIEWPORT
	rig.smoothing_enabled = false
	add_child(rig)
	rig.envelope.edge_margin_m = 50.0
	rig.set_world(world, ground)
	var layer: CanvasLayer = auto_free(CanvasLayer.new())
	add_child(layer)
	var hud := HudRoot.new()
	hud.set_anchors_preset(Control.PRESET_TOP_LEFT)
	layer.add_child(hud)
	hud.bind_input(rig.input_profile)
	hud.setup(f, UiTestSupport.platform(&"desktop"))
	hud.size = VIEWPORT
	hud.refresh()
	var view_root: Node3D = auto_free(Node3D.new())
	add_child(view_root)
	var style := RoadStyle.load_default()
	style.data["chunk_m"] = 400.0
	var roads: RoadView = auto_free(RoadView.new())
	view_root.add_child(roads)
	roads.build(net, style)
	var sync := RoadEditSync.create(net, roads)
	var overlay: CanvasLayer = auto_free(CanvasLayer.new())
	overlay.layer = 5
	add_child(overlay)
	if start_in_metro:
		_scene = {"rig": rig}
		_focus(FOCUS.x, FOCUS.y, _band_distance(rig, &"metro"))
	var ctrl := RoadDrawController.attach(hud, rig, net, f, view_root, ground, overlay)
	assert_object(ctrl).is_not_null()
	var fwd: MotionForwarder = auto_free(MotionForwarder.new())
	fwd.ctrl = ctrl
	add_child(fwd)
	rig.input_profile.select_requested.connect(func(p: Vector2) -> void:
		if not ctrl.handle_select(p):
			_fallthrough_selects += 1)
	_scene = {"rig": rig, "hud": hud, "ctrl": ctrl, "facade": f, "net": net, "sync": sync, "roads": roads}
	_focus(FOCUS.x, FOCUS.y, _street_distance(rig) if not start_in_metro else _band_distance(rig, &"metro"))
	await get_tree().process_frame
	return _scene


func _street_distance(rig: CameraRig) -> float:
	return _band_distance(rig, &"street")


func _band_distance(rig: CameraRig, band: StringName, fraction: float = 0.9) -> float:
	for b in rig.envelope.bands:
		if b["name"] == band:
			return float(b["min_m"]) + (float(b["max_m"]) - float(b["min_m"])) * fraction
	return -1.0


func _focus(x: float, z: float, distance: float) -> void:
	var rig: CameraRig = _scene["rig"]
	var s := rig.target_state()
	s.focus_x = x
	s.focus_z = z
	s.distance = distance
	rig.apply_state(s, true)
	rig._process(0.016)


func _screen(world_xz: Vector2) -> Vector2:
	var rig: CameraRig = _scene["rig"]
	var o := rig.rebase_origin
	return rig.camera.unproject_position(Vector3(world_xz.x - o.x, 0.0, world_xz.y - o.y))


func _click(pos: Vector2, button: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = button
		e.pressed = pressed
		e.position = pos
		e.global_position = pos
		get_viewport().push_input(e)


func _move(pos: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = pos
	e.global_position = pos
	get_viewport().push_input(e)


func _key(code: Key) -> void:
	for pressed in [true, false]:
		var e := InputEventKey.new()
		e.physical_keycode = code
		e.keycode = code
		e.pressed = pressed
		get_viewport().push_input(e)


func _center(c: Control) -> Vector2:
	return c.get_global_rect().get_center()


func _settle() -> void:
	for i in 3:
		await get_tree().process_frame


func _open_tool() -> void:
	var hud: HudRoot = _scene["hud"]
	var button := hud.toolbar.tool_button(ModeToolbar.TOOL_ROAD_DRAW)
	assert_object(button).override_failure_message("Yol çiz düğmesi araç çubuğunda yok").is_not_null()
	assert_bool(button.is_visible_in_tree()).is_true()
	_click(_center(button))
	await _settle()


func _tick_and_deliver(ticks: int = 1) -> void:
	(_scene["facade"] as SimFacadeImpl).advance(ticks)
	(_scene["hud"] as HudRoot).refresh()


func _draw_to_review(b: Vector2) -> void:
	await _open_tool()
	var ctrl: RoadDrawController = _scene["ctrl"]
	_click(_screen(A))
	assert_int(ctrl.tool.step).is_equal(RoadDrawTool.Step.PICK_B)
	_move(_screen(b))
	_click(_screen(b))


func test_toolbar_button_then_two_taps_and_confirm_builds_a_visible_road_from_the_same_net() -> void:
	await _build()
	var ctrl: RoadDrawController = _scene["ctrl"]
	var net: WorldNetwork = _scene["net"]
	var sync: RoadEditSync = _scene["sync"]
	var hud: HudRoot = _scene["hud"]
	assert_bool(ctrl.is_active()).is_false()
	await _open_tool()
	assert_bool(ctrl.is_active()).is_true()
	assert_object(ctrl.panel()).is_not_null()
	assert_bool(hud.free_map_rect().has_point(_screen(A))).override_failure_message("A harita boşluğunda değil").is_true()
	_click(_screen(A))
	assert_int(ctrl.tool.step).is_equal(RoadDrawTool.Step.PICK_B)
	assert_bool(ctrl.preview.has_mark()).is_true()
	_move(_screen(B_OK))
	assert_bool(ctrl.tool.is_valid()).override_failure_message(str(ctrl.tool.verdict)).is_true()
	assert_bool(ctrl.tip.visible).is_true()
	assert_bool(ctrl.tip.is_valid_state()).is_true()
	assert_str(ctrl.tip.text()).contains("+")
	_click(_screen(B_OK))
	assert_int(ctrl.tool.step).is_equal(RoadDrawTool.Step.REVIEW)
	var panel := ctrl.panel()
	assert_bool(panel.confirm_button().disabled).is_false()
	await _settle()
	var edges := net.edges.size()
	_click(_center(panel.confirm_button()))
	assert_int(ctrl.tool.step).is_equal(RoadDrawTool.Step.SENDING)
	assert_int(net.edges.size()).override_failure_message("ağ tick'ten önce değişmemeli").is_equal(edges)
	assert_bool(sync.pending()).is_false()
	_tick_and_deliver()
	assert_int(net.edges.size()).is_greater(edges)
	assert_int(ctrl.tool.step).is_equal(RoadDrawTool.Step.PICK_A)
	assert_bool(sync.pending()).is_true()
	var report := sync.sync()
	assert_bool(report["full"]).is_false()
	assert_int((report["keys"] as Array).size()).is_greater(0)
	assert_str(ctrl.panel().joined_text()).contains(UiText.t(&"road.step.done"))
	assert_int(_fallthrough_selects).override_failure_message("araç açıkken parsel seçilmemeli").is_equal(0)
	assert_array(Array(UiText.missing_keys())).is_empty()
	hud.refresh()


func test_too_long_draft_shows_the_reject_reason_at_the_cursor_and_in_the_panel_and_cannot_be_sent() -> void:
	await _build()
	var ctrl: RoadDrawController = _scene["ctrl"]
	var net: WorldNetwork = _scene["net"]
	await _open_tool()
	_focus(1100.0, 850.0, _band_distance(_scene["rig"], &"neighborhood", 0.5))
	_click(_screen(A))
	_move(_screen(B_LONG))
	assert_bool(ctrl.tool.is_valid()).is_false()
	var reason := UiText.reject_reason(ctrl.tool.verdict.reason_key, ctrl.tool.verdict.args)
	assert_str(String(ctrl.tool.verdict.reason_key)).is_equal("public_work.reject.too_long")
	assert_bool(ctrl.tip.visible).is_true()
	assert_bool(ctrl.tip.is_valid_state()).is_false()
	assert_str(ctrl.tip.text()).is_equal(reason)
	assert_str(ctrl.tip.text()).contains("400")
	assert_bool(ctrl.tip.text().begins_with("public_work.")).is_false()
	_click(_screen(B_LONG))
	assert_str(ctrl.panel().joined_text()).contains(reason)
	await _settle()
	var confirm := ctrl.panel().confirm_button()
	assert_bool(confirm == null or confirm.disabled).is_true()
	var edges := net.edges.size()
	if confirm != null:
		_click(_center(confirm))
	_tick_and_deliver()
	assert_int(net.edges.size()).is_equal(edges)
	assert_int(ctrl.tool.step).is_equal(RoadDrawTool.Step.REVIEW)
	assert_array(Array(UiText.missing_keys())).is_empty()


func test_start_on_free_land_is_refused_with_the_not_on_road_hint() -> void:
	await _build()
	var ctrl: RoadDrawController = _scene["ctrl"]
	await _open_tool()
	_click(_screen(Vector2(1100.0, 900.0)))
	assert_int(ctrl.tool.step).is_equal(RoadDrawTool.Step.PICK_A)
	assert_str(ctrl.panel().joined_text()).contains(UiText.t(RoadDrawTool.MSG_START_NOT_ON_ROAD))


func test_escape_cancels_the_draft_first_then_closes_the_tool_and_right_click_cancels_too() -> void:
	await _build()
	var ctrl: RoadDrawController = _scene["ctrl"]
	var hud: HudRoot = _scene["hud"]
	await _draw_to_review(B_OK)
	assert_int(ctrl.tool.step).is_equal(RoadDrawTool.Step.REVIEW)
	_key(KEY_ESCAPE)
	assert_int(ctrl.tool.step).is_equal(RoadDrawTool.Step.PICK_A)
	assert_bool(ctrl.is_active()).is_true()
	assert_bool(hud.panel_id() == RoadDrawController.PANEL_ID).is_true()
	_key(KEY_ESCAPE)
	assert_bool(ctrl.is_active()).override_failure_message("ikinci Esc aracı kapatmalı").is_false()
	assert_bool(hud.panel_id() == RoadDrawController.PANEL_ID).is_false()
	# Sağ tık: önce taslağı, sonra aracı kapatır.
	await _open_tool()
	_click(_screen(A))
	_click(_screen(Vector2(500.0, 900.0)), MOUSE_BUTTON_RIGHT)
	assert_int(ctrl.tool.step).is_equal(RoadDrawTool.Step.PICK_A)
	_click(_screen(Vector2(500.0, 900.0)), MOUSE_BUTTON_RIGHT)
	assert_bool(ctrl.is_active()).is_false()
	assert_bool(ctrl.preview.has_mark()).is_false()
	assert_bool(ctrl.tip.visible).is_false()


func test_undo_button_removes_the_last_road_from_the_net_and_the_view() -> void:
	await _build()
	var ctrl: RoadDrawController = _scene["ctrl"]
	var net: WorldNetwork = _scene["net"]
	var sync: RoadEditSync = _scene["sync"]
	await _open_tool()
	assert_object(ctrl.panel().undo_button()).override_failure_message("yapılmış yol yokken geri al görünmemeli").is_null()
	_click(_screen(A))
	_click(_screen(B_OK))
	await _settle()
	_click(_center(ctrl.panel().confirm_button()))
	_tick_and_deliver()
	sync.sync()
	var built_edges := net.edges.size()
	var undo := ctrl.panel().undo_button()
	assert_object(undo).is_not_null()
	await _settle()
	_click(_center(undo))
	_tick_and_deliver()
	assert_int(net.edges.size()).is_less(built_edges)
	assert_bool(sync.pending()).is_true()
	var report := sync.sync()
	assert_int((report["keys"] as Array).size()).is_greater(0)
	assert_object(ctrl.panel().undo_button()).is_null()
	assert_str(ctrl.panel().joined_text()).contains(UiText.t(RoadDrawTool.MSG_UNDONE))


func test_metro_band_locks_drawing_with_a_zoom_in_text_and_taps_do_not_draw() -> void:
	await _build()
	var ctrl: RoadDrawController = _scene["ctrl"]
	var rig: CameraRig = _scene["rig"]
	await _open_tool()
	_focus(FOCUS.x, FOCUS.y, _band_distance(rig, &"metro"))
	assert_str(String(rig.scale_band)).is_equal("metro")
	assert_bool(ctrl.tool.band_active).is_false()
	assert_str(ctrl.panel().joined_text()).contains(UiText.t(&"road.zoom_in"))
	_click(Vector2(800.0, 450.0))
	assert_int(ctrl.tool.step).is_equal(RoadDrawTool.Step.PICK_A)
	_focus(FOCUS.x, FOCUS.y, _street_distance(rig))
	assert_bool(ctrl.tool.band_active).is_true()


func test_taps_on_the_panel_and_toolbar_never_reach_the_world() -> void:
	await _build()
	var ctrl: RoadDrawController = _scene["ctrl"]
	await _open_tool()
	var panel := ctrl.panel()
	await _settle()
	_click((_scene["hud"] as HudRoot).panel.get_global_rect().get_center())
	assert_int(ctrl.tool.step).is_equal(RoadDrawTool.Step.PICK_A)
	assert_int(_fallthrough_selects).is_equal(0)
	assert_str(String(ctrl.tool.message)).is_equal("")


func test_without_attached_road_commands_the_tool_is_not_offered() -> void:
	await _build()
	var hud: HudRoot = _scene["hud"]
	var mock := UiTestSupport.mock()
	var overlay: CanvasLayer = auto_free(CanvasLayer.new())
	add_child(overlay)
	var view_root: Node3D = auto_free(Node3D.new())
	add_child(view_root)
	var ctrl := RoadDrawController.attach(hud, _scene["rig"], _scene["net"], mock, view_root, Callable(), overlay)
	assert_object(ctrl).is_null()


func test_attaching_while_the_camera_is_in_the_metro_band_is_safe_and_starts_locked() -> void:
	await _build(true)
	var ctrl: RoadDrawController = _scene["ctrl"]
	assert_bool(ctrl.tool.band_active).is_false()
	await _open_tool()
	assert_str(ctrl.panel().joined_text()).contains(UiText.t(&"road.zoom_in"))
	assert_bool(ctrl.preview.has_mark()).is_false()
