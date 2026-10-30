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


## Ekran noktasının araca giden zemin karşılığı (kamera ışını); `_screen`in tersi yaklaşıktır, bu tam eşleşir.
func _ground(screen_pos: Vector2) -> Vector2:
	var g: Dictionary = (_scene["rig"] as CameraRig).screen_to_ground(screen_pos)
	return Vector2(float(g["x"]), float(g["z"]))


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


## Kullanıcı denemesi: araç açıkken kare süresi 28 -> 69 ms. Ölçüm (tools/godot/road_ux_probe.gd): imleç adımı başına
## ~12 ms (sim kuru koşusu + panel yeniden çizimi). Hareketler en çok HOVER_INTERVAL_MSEC'te bir uygulanır;
## son konum kazanır.
func test_rapid_mouse_motion_is_coalesced_and_the_last_position_wins() -> void:
	await _build()
	var ctrl: RoadDrawController = _scene["ctrl"]
	await _open_tool()
	_click(_screen(A))
	assert_int(ctrl.tool.step).is_equal(RoadDrawTool.Step.PICK_B)
	var changes := [0]
	ctrl.tool.changed.connect(func() -> void: changes[0] += 1)
	var last_screen := _screen(Vector2(1100.0, 1090.0 - 2.0 * 29.0))
	var last := _ground(last_screen)
	for i in 30:
		_move(_screen(Vector2(1100.0, 1090.0 - 2.0 * float(i))))
	assert_int(changes[0]).override_failure_message("30 hareket bir karede en çok 1 denetim yapmalı").is_less_equal(1)
	await get_tree().create_timer(float(RoadDrawController.HOVER_INTERVAL_MSEC + 30) / 1000.0).timeout
	ctrl.process()
	assert_int(changes[0]).is_less_equal(2)
	assert_float(ctrl.tool.end.distance_to(last)) \
		.override_failure_message("son imleç konumu uygulanmalı: %s" % [ctrl.tool.end]) \
		.is_less(1.5)
	# Tıklama bekleyen eski hareketi ezmez: tıklanan nokta bitiş olur.
	_move(_screen(Vector2(1100.0, 1050.0)))
	_click(_screen(B_OK))
	assert_float(ctrl.tool.end.distance_to(_ground(_screen(B_OK)))).is_less(1.5)
	ctrl.process()
	assert_float(ctrl.tool.end.distance_to(_ground(_screen(B_OK)))) \
		.override_failure_message("bekleyen hareket tıklamayı ezmemeli") \
		.is_less(1.5)


# --- Onay görünürlüğü (kullanıcı denemesi: "Onayla yalnız sağ paneldeki küçük kutuda, çok zor anladım") ---

func test_enter_confirms_the_reviewed_road_but_space_does_not() -> void:
	await _build()
	var ctrl: RoadDrawController = _scene["ctrl"]
	await _draw_to_review(B_OK)
	assert_int(ctrl.tool.step).is_equal(RoadDrawTool.Step.REVIEW)
	_key(KEY_SPACE)
	assert_int(ctrl.tool.step) \
		.override_failure_message("Boşluk onaylamamalı (duraklatır)") \
		.is_equal(RoadDrawTool.Step.REVIEW)
	_key(KEY_ENTER)
	assert_int(ctrl.tool.step).override_failure_message("Enter onaylamalı").is_equal(RoadDrawTool.Step.SENDING)
	_tick_and_deliver()
	assert_int(ctrl.tool.step).is_equal(RoadDrawTool.Step.PICK_A)


func test_enter_does_nothing_when_the_draft_is_rejected_or_before_the_second_tap() -> void:
	await _build()
	var ctrl: RoadDrawController = _scene["ctrl"]
	var edges := (_scene["net"] as WorldNetwork).edges.size()
	await _open_tool()
	_key(KEY_ENTER)
	assert_int(ctrl.tool.step).is_equal(RoadDrawTool.Step.PICK_A)
	_click(_screen(A))
	_key(KEY_ENTER)
	assert_int(ctrl.tool.step) \
		.override_failure_message("bitiş seçilmeden Enter onaylamaz") \
		.is_equal(RoadDrawTool.Step.PICK_B)
	_focus(1100.0, 850.0, _band_distance(_scene["rig"], &"neighborhood", 0.5))
	_move(_screen(B_LONG))
	_click(_screen(B_LONG))
	assert_bool(ctrl.tool.is_valid()).is_false()
	_key(KEY_ENTER)
	_tick_and_deliver()
	assert_int(ctrl.tool.step).is_equal(RoadDrawTool.Step.REVIEW)
	assert_int((_scene["net"] as WorldNetwork).edges.size()).is_equal(edges)


func test_clicking_the_same_end_point_again_confirms_and_a_new_point_moves_the_end() -> void:
	await _build()
	var ctrl: RoadDrawController = _scene["ctrl"]
	await _draw_to_review(B_OK)
	var other := Vector2(1100.0, 1030.0)
	_click(_screen(other))
	assert_int(ctrl.tool.step) \
		.override_failure_message("başka yere tıklamak bitişi değiştirir, onaylamaz") \
		.is_equal(RoadDrawTool.Step.REVIEW)
	assert_float(ctrl.tool.end.distance_to(_ground(_screen(other)))).is_less(1.5)
	_click(_screen(other))
	assert_int(ctrl.tool.step) \
		.override_failure_message("aynı noktaya yeniden tıklamak onaylar") \
		.is_equal(RoadDrawTool.Step.SENDING)


func test_a_big_confirm_chip_sits_at_the_road_end_with_the_enter_hint_and_clicking_it_confirms() -> void:
	await _build()
	var ctrl: RoadDrawController = _scene["ctrl"]
	var hud: HudRoot = _scene["hud"]
	await _open_tool()
	_click(_screen(A))
	_move(_screen(B_OK))
	assert_bool(ctrl.chip.visible).override_failure_message("bitiş seçilmeden işaret görünmemeli").is_false()
	_click(_screen(B_OK))
	await _settle()
	assert_bool(ctrl.chip.visible).override_failure_message("Adım 3/3'te bitiş ucunda onay işareti görünmeli").is_true()
	assert_str(ctrl.chip.text).is_equal("Onaylamak için Enter ya da buraya tıkla · Esc iptal")
	assert_float(ctrl.chip.size.y).is_greater_equal(44.0)
	var rect := ctrl.chip.get_global_rect()
	assert_bool(hud.free_map_rect().encloses(rect)) \
		.override_failure_message("işaret harita boşluğunda olmalı: %s / %s" % [rect, hud.free_map_rect()]) \
		.is_true()
	assert_float(rect.get_center().distance_to(_screen(B_OK))) \
		.override_failure_message("işaret bitiş ucuna yakın olmalı") \
		.is_less(400.0)
	_click(_center(ctrl.chip))
	assert_int(ctrl.tool.step).is_equal(RoadDrawTool.Step.SENDING)
	assert_bool(ctrl.chip.visible).is_false()
	assert_int(_fallthrough_selects).override_failure_message("işarete tıklamak parsel seçtirmemeli").is_equal(0)


func test_confirm_chip_hides_for_rejected_drafts_cancel_and_tool_off() -> void:
	await _build()
	var ctrl: RoadDrawController = _scene["ctrl"]
	await _open_tool()
	_focus(1100.0, 850.0, _band_distance(_scene["rig"], &"neighborhood", 0.5))
	_click(_screen(A))
	_click(_screen(B_LONG))
	assert_bool(ctrl.tool.is_valid()).is_false()
	await _settle()
	assert_bool(ctrl.chip.visible).override_failure_message("yapılamaz taslakta onay işareti yok").is_false()
	_focus(1100.0, 1050.0, _street_distance(_scene["rig"]))
	_click(_screen(B_OK))
	await _settle()
	assert_bool(ctrl.chip.visible).is_true()
	_key(KEY_ESCAPE)
	await _settle()
	assert_bool(ctrl.chip.visible).override_failure_message("Esc taslağı iptal edince işaret kaybolur").is_false()
	_click(_screen(B_OK))
	ctrl.deactivate()
	assert_bool(ctrl.chip.visible).is_false()


func test_cursor_label_names_the_step_at_every_step() -> void:
	await _build()
	var ctrl: RoadDrawController = _scene["ctrl"]
	await _open_tool()
	_move(_screen(Vector2(1100.0, 1090.0)))
	assert_bool(ctrl.tip.visible).is_true()
	assert_str(ctrl.tip.step_text()).is_equal("1/3 · Yola ya da yol ucuna tıkla")
	_click(_screen(A))
	await get_tree().create_timer(float(RoadDrawController.HOVER_INTERVAL_MSEC + 30) / 1000.0).timeout
	_move(_screen(B_OK))
	assert_str(ctrl.tip.step_text()).is_equal("2/3 · Bitişi tıkla")
	assert_str(ctrl.tip.text()).contains("+")
	_click(_screen(B_OK))
	assert_str(ctrl.tip.step_text()).is_equal("3/3 · Onayla: Enter ya da işarete tıkla")


## Panel imleç önizlemesinde her adımda yeniden kurulmaz (ölçüm: ~6,6 ms/adım); en çok PANEL_HOVER_INTERVAL_MSEC'te bir.
func test_side_panel_is_not_rebuilt_on_every_hover_step_but_catches_up() -> void:
	await _build()
	var ctrl: RoadDrawController = _scene["ctrl"]
	await _open_tool()
	_click(_screen(A))
	var before := ctrl.panel().confirm_button()
	var builds := {before.get_instance_id(): true}
	for i in 20:
		await get_tree().create_timer(float(RoadDrawController.HOVER_INTERVAL_MSEC + 5) / 1000.0).timeout
		_move(_screen(Vector2(1100.0, 1090.0 - 3.0 * float(i))))
		builds[ctrl.panel().confirm_button().get_instance_id()] = true
	assert_bool(ctrl.tool.is_valid()).is_true()
	# 20 hareket ~1,1 sn sürdü: her biri panel kursaydı 21 çizim olurdu; 250 ms aralıkla en çok ~6.
	assert_int(builds.size()) \
			.override_failure_message("panel hareket başına kuruluyor: %d çizim" % builds.size()) \
			.is_less_equal(8)
	await get_tree().create_timer(float(RoadDrawController.PANEL_HOVER_INTERVAL_MSEC + 30) / 1000.0).timeout
	ctrl.process()
	assert_object(ctrl.panel().confirm_button()).override_failure_message("bekleyen çizim yetişmeli").is_not_same(before)
	assert_str(ctrl.panel().joined_text()).contains(UiText.t(&"road.valid"))
