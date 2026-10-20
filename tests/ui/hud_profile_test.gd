extends GdUnitTestSuite
## T-019 ölçüt 4/6 · HUD profil eşliği: masaüstü ↔ dokunmatik aynı fiiller, ≥ 44 pt (sık fiiller ≥ 56
## pt) hedefler,
## komşu hedef boşluğu, yerleşim düğümleri çerçeve içinde, hız fiilleri InputProfile üzerinden, dokunmatik
## profil
## fare olaylarını yok sayar (çift tetik yok). Olumsuz: profil tavanı üstü hız yok.

const DESKTOP_SIZE := Vector2(1600, 900)
const IPAD_LANDSCAPE := Vector2(1366, 1024)
const IPAD_PORTRAIT := Vector2(1024, 1366)


func before_test() -> void:
	UiText.reset()
	UiText.report_missing = false


func after_test() -> void:
	UiText.reset()


func _hud(facade: SimFacade, profile_name: StringName, window: Vector2, extra: Dictionary = {}) -> HudRoot:
	var hud := HudRoot.new()
	add_child(hud)
	hud.setup(facade, UiTestSupport.platform(profile_name, extra))
	hud.set_anchors_preset(Control.PRESET_TOP_LEFT)
	hud.size = window
	hud.refresh()
	return auto_free(hud)


func _text_builder(c: UiContext) -> Control:
	var l := UiFactory.label("içerik", &"", true)
	l.theme = UiTheme.build(c)
	return l


# --- profil eşliği ve hedefler ---

func test_same_verbs_on_desktop_and_touch() -> void:
	var d := _hud(UiTestSupport.mock(), &"desktop", DESKTOP_SIZE)
	var t := _hud(UiTestSupport.mock(), &"touch", IPAD_LANDSCAPE)
	assert_array(Array(UiTestSupport.button_texts(d))).is_equal(Array(UiTestSupport.button_texts(t)))


func test_touch_targets_are_at_least_44pt_in_both_orientations() -> void:
	for window: Vector2 in [IPAD_LANDSCAPE, IPAD_PORTRAIT]:
		var hud := _hud(UiTestSupport.mock(), &"touch", window)
		hud.open_panel(&"probe", &"inspector.title", _text_builder)
		await await_idle_frame()
		for b in UiTestSupport.visible_buttons(hud):
			var hit := UiFactory.hit_size(b)
			assert_float(minf(hit.x, hit.y)).override_failure_message(
				"'%s' hedefi %s (%s)" % [b.text, hit, window]).is_greater_equal(44.0)


func test_primary_touch_controls_are_at_least_56pt() -> void:
	var hud := _hud(UiTestSupport.mock(), &"touch", IPAD_LANDSCAPE)
	await await_idle_frame()
	for b in [hud.top_bar.time_controls.pause_button(), hud.top_bar.time_controls.speed_button(1),
			hud.toolbar.mode_button(ModeToolbar.MODE_PLAN)]:
		assert_float(UiFactory.hit_size(b).y).is_greater_equal(56.0)


func test_desktop_targets_are_at_least_32pt() -> void:
	var hud := _hud(UiTestSupport.mock(), &"desktop", DESKTOP_SIZE)
	await await_idle_frame()
	for b in UiTestSupport.visible_buttons(hud):
		assert_float(minf(UiFactory.hit_size(b).x, UiFactory.hit_size(b).y)).is_greater_equal(32.0)


func test_touch_neighbouring_toolbar_targets_have_gap() -> void:
	var hud := _hud(UiTestSupport.mock(), &"touch", IPAD_LANDSCAPE)
	await await_idle_frame()
	var buttons := hud.toolbar.all_buttons()
	for i in buttons.size():
		for j in range(i + 1, buttons.size()):
			var a := buttons[i].get_global_rect()
			var b := buttons[j].get_global_rect()
			if a.grow(7.9).intersects(b) and not a.intersects(b):
				assert_bool(false).override_failure_message("%s ve %s arası < 8" % [buttons[i].text, buttons[j].text]).is_true()
			assert_bool(a.intersects(b)).is_false()


func test_layout_nodes_stay_inside_frame_for_all_profiles() -> void:
	var cases := [[&"desktop", DESKTOP_SIZE], [&"touch", IPAD_LANDSCAPE], [&"touch", IPAD_PORTRAIT]]
	for c in cases:
		var window: Vector2 = c[1]
		var hud := _hud(UiTestSupport.mock(), c[0], window)
		hud.open_panel(&"probe", &"inspector.title", _text_builder)
		await await_idle_frame()
		var whole := Rect2(Vector2.ZERO, window).grow(1.0)
		for node: Control in [hud.top_bar, hud.toolbar, hud.panel]:
			assert_bool(whole.encloses(node.get_global_rect())).override_failure_message(
				"%s %s dışında (%s)" % [node.get_class(), node.get_global_rect(), window]).is_true()
		assert_bool(hud.panel.get_global_rect().intersects(hud.toolbar.get_global_rect())).is_false()


func test_top_bar_wraps_on_narrow_portrait_and_every_item_stays_inside() -> void:
	var cases := [[&"touch", Vector2(834, 1194), true], [&"desktop", DESKTOP_SIZE, false]]
	for c in cases:
		var window: Vector2 = c[1]
		var hud := _hud(UiTestSupport.mock(), c[0], window)
		hud.set_agenda(2, 5, true)  # en geniş durum: gündem rozeti + iki MOCK rozeti
		hud.refresh()
		await await_idle_frame()
		await await_idle_frame()
		assert_bool(hud.top_bar.is_wrapped()).is_equal(c[2])
		var whole := Rect2(Vector2.ZERO, window).grow(1.0)
		for b in UiTestSupport.visible_buttons(hud.top_bar):
			assert_bool(whole.encloses(b.get_global_rect())).override_failure_message(
				"'%s' %s taştı (%s)" % [b.text, b.get_global_rect(), window]).is_true()
		assert_bool(whole.encloses(hud.top_bar.get_global_rect())).is_true()
		assert_float(hud.layout.top.size.y).is_greater_equal(hud.top_bar.get_combined_minimum_size().y - 0.5)


# --- hız / girdi profili ---

func test_speed_buttons_drive_facade_speed() -> void:
	var f := UiTestSupport.mock()
	var hud := _hud(f, &"desktop", DESKTOP_SIZE)
	hud.top_bar.time_controls.speed_button(3).pressed.emit()
	assert_int(f.speed()).is_equal(SimFacade.SPEED_FASTEST)
	hud.top_bar.time_controls.pause_button().pressed.emit()
	assert_int(f.speed()).is_equal(SimFacade.SPEED_PAUSED)
	hud.top_bar.time_controls.pause_button().pressed.emit()
	assert_int(f.speed()).is_equal(SimFacade.SPEED_FASTEST)


func test_input_profile_verbs_pause_and_step_speed() -> void:
	var f := UiTestSupport.mock()
	var hud := _hud(f, &"desktop", DESKTOP_SIZE)
	assert_int(f.speed()).is_equal(1)
	hud.input.pause_toggle_requested.emit()
	assert_int(f.speed()).is_equal(0)
	hud.input.pause_toggle_requested.emit()
	assert_int(f.speed()).is_equal(1)
	hud.input.speed_step_requested.emit(1)
	assert_int(f.speed()).is_equal(2)
	hud.input.speed_step_requested.emit(1)
	hud.input.speed_step_requested.emit(1)
	assert_int(f.speed()).is_equal(3)  # üst sınırda kalır
	hud.input.speed_step_requested.emit(-1)
	assert_int(f.speed()).is_equal(2)


func test_profile_speed_cap_limits_steps() -> void:
	var f := UiTestSupport.mock()
	var hud := _hud(f, &"touch", IPAD_LANDSCAPE, {"max_game_speed": 2})
	assert_array(Array(hud.top_bar.time_controls.shown_levels())).is_equal([1, 2])
	hud.input.speed_step_requested.emit(1)
	hud.input.speed_step_requested.emit(1)
	assert_int(f.speed()).is_equal(2)


func test_drag_slop_scales_with_ui_scale() -> void:
	var desktop := _hud(UiTestSupport.mock(), &"desktop", DESKTOP_SIZE)
	var touch := _hud(UiTestSupport.mock(), &"touch", IPAD_LANDSCAPE)
	assert_float(desktop.input.drag_slop_px).is_equal(8.0)
	assert_float(touch.input.drag_slop_px).is_equal(30.0)  # 24 × 1,25


func test_real_key_event_toggles_pause_through_input_profile() -> void:
	var f := UiTestSupport.mock()
	var hud := _hud(f, &"desktop", DESKTOP_SIZE)
	var key := InputEventKey.new()
	key.keycode = KEY_SPACE
	key.physical_keycode = KEY_SPACE
	key.pressed = true
	assert_bool(hud.input.handle_event(key)).is_true()
	assert_int(f.speed()).is_equal(SimFacade.SPEED_PAUSED)


func test_real_touch_tap_selects_through_input_profile_on_touch_only() -> void:
	var hud := _hud(UiTestSupport.mock(), &"touch", IPAD_LANDSCAPE)
	var taps := []
	hud.input.select_requested.connect(func(p: Vector2) -> void: taps.append(p))
	var down := InputEventScreenTouch.new()
	down.index = 0
	down.pressed = true
	down.position = Vector2(300, 400)
	var up := InputEventScreenTouch.new()
	up.index = 0
	up.pressed = false
	up.position = Vector2(300, 400)
	hud.input.handle_event(down)
	hud.input.handle_event(up)
	assert_array(taps).is_equal([Vector2(300, 400)])


func test_touch_profile_ignores_mouse_and_desktop_profile_uses_it() -> void:
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = Vector2(10, 10)
	var touch_hud := _hud(UiTestSupport.mock(), &"touch", IPAD_LANDSCAPE)
	assert_bool(touch_hud.input.handle_event(click)).is_false()
	var desktop_hud := _hud(UiTestSupport.mock(), &"desktop", DESKTOP_SIZE)
	assert_bool(desktop_hud.input.handle_event(click)).is_true()
	assert_bool(touch_hud.input.supports_hover).is_false()
	assert_bool(touch_hud.ctx.hover_available).is_false()



func _labels(node: Node) -> Array[Label]:
	var out: Array[Label] = []
	for child in node.get_children():
		if child is Label and (child as Label).is_visible_in_tree():
			out.append(child)
		out.append_array(_labels(child))
	return out
