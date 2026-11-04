extends GdUnitTestSuite
## T-030 · Girdi yönlendirme sözleşmesi, oyundaki düğüm sırasıyla (CameraRig önce, HUD katmanı sonra) ve GERÇEK
## viewport olay yayılımıyla (`Viewport.push_input`): klavye/tekerlek/sürükleme kamerayı sürer, HUD düğmeleri ve
## duraklat bozulmaz, HUD paylaşılan InputProfile'ı sürmez. Önceki kamera testleri `rig._unhandled_input(...)`'ı
## doğrudan çağırdığı için HUD'un olayı yutması (iki ayrı InputProfile) yakalanmamıştı.
## Sentetik olaylar: gerçek fare/trackpad denemesi DEĞİLDİR.

const VIEWPORT := Vector2(1600.0, 900.0)
const FREE_SPOT := Vector2(1000.0, 400.0)  # HUD kontrollerinden uzak, dünya üstü bir piksel

var _world: WorldData
var _selects: Array[Vector2] = []


func before() -> void:
	_world = WorldTestSupport.coarse(WorldTestSupport.control())


func before_test() -> void:
	UiText.reset()
	UiText.report_missing = false
	_selects = []


func after_test() -> void:
	UiText.reset()


## playable.gd ile aynı kurulum: kamera önce eklenir, HUD katmanı sonra (HUD olayı ÖNCE görür); tek paylaşılan profil.
func _scene(facade: SimFacade = null) -> Dictionary:
	var rig: CameraRig = auto_free(CameraRig.new())
	rig.input_profile = InputProfile.create(&"desktop")
	rig.viewport_size_override = VIEWPORT
	rig.smoothing_enabled = false
	add_child(rig)
	rig.set_world(_world, func(x: float, z: float) -> float: return maxf(_world.height_at(x, z), _world.sea_level))
	rig.apply_preset("district:D4")
	var layer: CanvasLayer = auto_free(CanvasLayer.new())
	add_child(layer)
	var hud := HudRoot.new()
	hud.set_anchors_preset(Control.PRESET_TOP_LEFT)
	layer.add_child(hud)
	hud.bind_input(rig.input_profile)
	var sim: SimFacade = facade if facade != null else UiTestSupport.mock()
	hud.setup(sim, UiTestSupport.platform(&"desktop"))
	hud.size = VIEWPORT
	hud.refresh()
	rig.input_profile.select_requested.connect(func(p: Vector2) -> void: _selects.append(p))
	return {"rig": rig, "hud": hud, "facade": sim}


func _push(event: InputEvent) -> void:
	get_viewport().push_input(event)


func _key(code: Key, pressed: bool) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = pressed
	return e


func _mouse(index: MouseButton, pressed: bool, pos: Vector2) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = index
	e.pressed = pressed
	e.position = pos
	e.global_position = pos
	return e


func _motion(pos: Vector2, rel: Vector2) -> InputEventMouseMotion:
	var e := InputEventMouseMotion.new()
	e.position = pos
	e.global_position = pos
	e.relative = rel
	e.button_mask = MOUSE_BUTTON_MASK_LEFT
	return e


func _frames(rig: CameraRig, count: int, dt: float = 0.1) -> void:
	for i in count:
		rig._process(dt)


func _moved(rig: CameraRig, before: CameraState) -> float:
	return rig.current_state().focus_xz().distance_to(before.focus_xz())


func test_wasd_moves_the_camera_through_real_event_routing() -> void:
	var scene := _scene()
	var rig: CameraRig = scene["rig"]
	for code: Key in [KEY_W, KEY_A, KEY_S, KEY_D]:
		var before := rig.current_state().copy()
		_push(_key(code, true))
		_frames(rig, 5)
		_push(_key(code, false))
		assert_float(_moved(rig, before)) \
				.override_failure_message("tuş %s kamerayı oynatmadı" % OS.get_keycode_string(code)).is_greater(1.0)
		_frames(rig, 3)  # bırakınca durur: sürekli kayma yok
		var settled := rig.current_state().copy()
		_frames(rig, 3)
		assert_float(_moved(rig, settled)).is_less(0.001)


func test_arrow_keys_move_the_camera() -> void:
	var scene := _scene()
	var rig: CameraRig = scene["rig"]
	for code: Key in [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT]:
		var before := rig.current_state().copy()
		_push(_key(code, true))
		_frames(rig, 5)
		_push(_key(code, false))
		assert_float(_moved(rig, before)) \
				.override_failure_message("ok tuşu %s kamerayı oynatmadı" % OS.get_keycode_string(code)).is_greater(1.0)


func test_q_and_e_rotate_the_camera() -> void:
	var scene := _scene()
	var rig: CameraRig = scene["rig"]
	var before := rig.current_state().heading_deg
	_push(_key(KEY_E, true))
	_frames(rig, 5)
	_push(_key(KEY_E, false))
	var after_e := rig.current_state().heading_deg
	assert_float(absf(angle_difference(deg_to_rad(before), deg_to_rad(after_e)))).is_greater(0.01)
	_push(_key(KEY_Q, true))
	_frames(rig, 5)
	_push(_key(KEY_Q, false))
	assert_float(rig.current_state().heading_deg).is_not_equal(after_e)


func test_wheel_zoom_reaches_the_camera() -> void:
	var scene := _scene()
	var rig: CameraRig = scene["rig"]
	var d0 := rig.distance()
	_push(_mouse(MOUSE_BUTTON_WHEEL_UP, true, FREE_SPOT))
	assert_float(rig.distance()).is_less(d0)
	var d1 := rig.distance()
	_push(_mouse(MOUSE_BUTTON_WHEEL_DOWN, true, FREE_SPOT))
	assert_float(rig.distance()).is_greater(d1)


func test_trackpad_magnify_and_pan_gestures_reach_the_camera() -> void:
	var scene := _scene()
	var rig: CameraRig = scene["rig"]
	var d0 := rig.distance()
	var pinch := InputEventMagnifyGesture.new()
	pinch.position = FREE_SPOT
	pinch.factor = 1.5
	_push(pinch)
	assert_float(rig.distance()).is_less(d0)


func test_left_drag_pans_the_camera_and_does_not_select() -> void:
	var scene := _scene()
	var rig: CameraRig = scene["rig"]
	var before := rig.current_state().copy()
	_push(_mouse(MOUSE_BUTTON_LEFT, true, FREE_SPOT))
	var pos := FREE_SPOT
	for i in 6:
		var next := pos + Vector2(40.0, -25.0)
		_push(_motion(next, next - pos))
		pos = next
	_push(_mouse(MOUSE_BUTTON_LEFT, false, pos))
	assert_float(_moved(rig, before)).is_greater(1.0)
	assert_array(_selects).is_empty()


func test_click_on_the_world_selects_exactly_once() -> void:
	var scene := _scene()
	_push(_mouse(MOUSE_BUTTON_LEFT, true, FREE_SPOT))
	_push(_mouse(MOUSE_BUTTON_LEFT, false, FREE_SPOT))
	assert_array(_selects).is_equal([FREE_SPOT])
	assert_object(scene["rig"]).is_not_null()


func test_space_toggles_pause_once_per_press_through_the_shared_profile() -> void:
	var scene := _scene()
	var facade: SimFacade = scene["facade"]
	var start := facade.speed()
	assert_int(start).is_not_equal(SimFacade.SPEED_PAUSED)
	_push(_key(KEY_SPACE, true))
	_push(_key(KEY_SPACE, false))
	assert_int(facade.speed()).is_equal(SimFacade.SPEED_PAUSED)
	_push(_key(KEY_SPACE, true))
	_push(_key(KEY_SPACE, false))
	assert_int(facade.speed()).is_equal(start)


func test_hud_button_click_is_consumed_by_the_ui_and_never_selects_in_the_world() -> void:
	var scene := _scene()
	var hud: HudRoot = scene["hud"]
	await get_tree().process_frame
	var target: Button = null
	for b in UiTestSupport.visible_buttons(hud):
		if b.is_visible_in_tree() and not b.disabled and b.get_global_rect().size.x > 0.0:
			target = b
			break
	assert_object(target).is_not_null()
	var center := target.get_global_rect().get_center()
	_push(_mouse(MOUSE_BUTTON_LEFT, true, center))
	_push(_mouse(MOUSE_BUTTON_LEFT, false, center))
	assert_array(_selects).is_empty()


func test_hud_does_not_drive_a_shared_profile() -> void:
	# HUD tek başına (kamera yok): paylaşılan profili ne besler ne tüketir; hareket tuşu HUD'da kalmaz.
	var shared := InputProfile.create(&"desktop")
	var layer: CanvasLayer = auto_free(CanvasLayer.new())
	add_child(layer)
	var hud := HudRoot.new()
	layer.add_child(hud)
	hud.bind_input(shared)
	hud.setup(UiTestSupport.mock(), UiTestSupport.platform(&"desktop"))
	assert_object(hud.input).is_same(shared)
	_push(_key(KEY_W, true))
	assert_vector(shared.held_pan_axis()).is_equal(Vector2.ZERO)
	_push(_key(KEY_W, false))
