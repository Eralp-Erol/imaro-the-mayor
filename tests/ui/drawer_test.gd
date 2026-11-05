extends GdUnitTestSuite
## D-021 · Dokunmatik alttan çekmece (imar paneli): konumlar (kapalı/yarı/tam), parmakla sürükleme + ok düğmesi,
## yarı açıkken "Planı sun" ve kullanım düğmeleri görünür, 44 pt hedefler, güvenli alan, harita dokunuşu çekmece
## dışında, MASAÜSTÜ DEĞİŞMEZ. Başsız yerleşim ölçümü; GERÇEK parmak/iPad denemesi DEĞİL.

const FIXTURE := "mock_scenario_investment_declined"
const IPAD_SMALL_LANDSCAPE := Vector2(1024, 768)
const IPAD_SMALL_PORTRAIT := Vector2(768, 1024)
const DESKTOP := Vector2(1600, 900)


class AreaFacade extends MockSimFacade:
	var views: Dictionary = {}
	var lands: Array[MunicipalLandView] = []

	func municipal_lands() -> Array[MunicipalLandView]:
		return lands

	func parcel_views(ids: PackedInt64Array) -> Array[ParcelView]:
		var out: Array[ParcelView] = []
		for id in ids:
			if views.has(id):
				out.append(views[id])
		return out


func before_test() -> void:
	UiText.reset()
	UiText.report_missing = false


func after_test() -> void:
	UiText.reset()


func _facade() -> AreaFacade:
	var f := AreaFacade.new(MockScenario.load_file(FlowTestSupport.FIXTURES + FIXTURE + ".json"))
	for i in range(1, 16):
		var land := MunicipalLandView.new()
		land.id = 5000 + i
		land.available = true
		land.area_m2 = 300
		f.lands.append(land)
	for i in range(1, 8):
		var v := ParcelView.new()
		v.id = 19800 + i
		v.area_m2 = 100 + i
		v.region_code = &"R%d" % (1 + i % 2)
		f.views[v.id] = v
	return f


func _hud(profile_name: StringName, window: Vector2, parcels: int, drawer: bool = true,
		safe: Vector4 = Vector4.ZERO) -> HudRoot:
	var f := _facade()
	var hud := HudRoot.new()
	add_child(hud)
	hud.simulated_safe = safe
	hud.register_tool(ModeToolbar.MODE_PLAN, ModeToolbar.TOOL_ZONE)
	hud.setup(f, UiTestSupport.platform(profile_name))
	hud.set_anchors_preset(Control.PRESET_TOP_LEFT)
	hud.size = window
	hud.refresh()
	var model := ZoningFlowModel.create(f)
	for i in range(1, parcels + 1):
		model.add_parcel(19800 + i)
	hud.open_panel(&"zoning", &"zoning.title", func(c: UiContext) -> Control:
		return ZoningFlowPanel.create(c, f, model), drawer)
	# Sahte facade MOCK rozeti ekler (~30 px); gerçek sim'de rozet yoktur: yerleşim ölçümü gerçeğe yakın kalsın.
	(hud.panel.content_node() as FlowPanel).badge.visible = false
	await await_idle_frame()
	await await_idle_frame()
	return auto_free(hud)


func _zoning(hud: HudRoot) -> ZoningFlowPanel:
	return hud.panel.content_node() as ZoningFlowPanel


func _compute(ctx: UiContext, frame: Vector2, state: int) -> HudLayout:
	return HudLayout.compute(ctx, frame, true, false, 0.0, false, 0.0, state)


# --- saf mantık ---

func test_model_steps_snap_and_fling() -> void:
	var s := DrawerModel.State
	assert_int(DrawerModel.up_from(s.CLOSED)).is_equal(s.HALF)
	assert_int(DrawerModel.up_from(s.HALF)).is_equal(s.FULL)
	assert_int(DrawerModel.up_from(s.FULL)).is_equal(s.FULL)
	assert_int(DrawerModel.down_from(s.FULL)).is_equal(s.HALF)
	assert_int(DrawerModel.down_from(s.CLOSED)).is_equal(s.CLOSED)
	var heights := {s.CLOSED: 100.0, s.HALF: 300.0, s.FULL: 600.0}
	assert_int(DrawerModel.snap(340.0, heights, 0.0, s.HALF)).is_equal(s.HALF)
	assert_int(DrawerModel.snap(480.0, heights, 0.0, s.HALF)).is_equal(s.FULL)
	assert_int(DrawerModel.snap(150.0, heights, 0.0, s.HALF)).is_equal(s.CLOSED)
	# fırlatma: yönde bir adım
	assert_int(DrawerModel.snap(310.0, heights, -2000.0, s.HALF)).is_equal(s.FULL)
	assert_int(DrawerModel.snap(310.0, heights, 2000.0, s.HALF)).is_equal(s.CLOSED)
	assert_float(DrawerModel.clamp_height(9999.0, heights)).is_equal(600.0)
	assert_float(DrawerModel.clamp_height(-5.0, heights)).is_equal(100.0)


# --- yerleşim ---

func test_layout_positions_are_ordered_inside_frame_and_clear_of_toolbar_on_touch() -> void:
	for window: Vector2 in [IPAD_SMALL_LANDSCAPE, IPAD_SMALL_PORTRAIT, Vector2(1366, 1024), Vector2(1024, 1366)]:
		var ctx := UiContext.for_profile_name(&"touch")
		var frame := ctx.frame_size(window)
		var last := 0.0
		for state in [DrawerModel.State.CLOSED, DrawerModel.State.HALF, DrawerModel.State.FULL]:
			var l := _compute(ctx, frame, state)
			assert_str(String(l.panel_mode)).is_equal("drawer")
			assert_float(l.panel.size.y).is_greater_equal(last)
			last = l.panel.size.y
			assert_float(l.panel.end.y).is_less_equal(l.toolbar.position.y + 0.01)
			assert_float(l.panel.position.y).is_greater_equal(l.top.end.y)
			assert_float(l.panel.size.x).is_equal(frame.x)        # tam genişlik, yan şerit yok
			assert_float(l.map_region.size.x).is_equal(frame.x)   # şehir yandan örtülmez
		var half := _compute(ctx, frame, DrawerModel.State.HALF)
		var full := _compute(ctx, frame, DrawerModel.State.FULL)
		assert_float(half.panel.size.y).is_greater(_compute(ctx, frame, DrawerModel.State.CLOSED).panel.size.y * 1.8)
		assert_float(full.panel.size.y).is_greater(half.panel.size.y)
		# TAM'da bile üst şeridin altında harita şeridi kalır
		assert_float(full.panel.position.y - full.top.end.y).is_greater_equal(ctx.px(40.0))


func test_desktop_layout_is_unchanged_even_if_a_drawer_state_is_passed() -> void:
	var ctx := UiContext.for_profile_name(&"desktop")
	var frame := ctx.frame_size(DESKTOP)
	var plain := HudLayout.compute(ctx, frame, true, false)
	var asked := _compute(ctx, frame, DrawerModel.State.HALF)
	assert_str(String(asked.panel_mode)).is_equal("side")
	assert_that(asked.panel).is_equal(plain.panel)
	assert_that(asked.map_region).is_equal(plain.map_region)
	assert_that(asked.toolbar).is_equal(plain.toolbar)


func test_non_drawer_touch_panels_keep_the_old_layout() -> void:
	# Diğer karar panelleri henüz bağlı değil: dokunmatik yatayda yan panel, dikeyde alt sayfa kalır.
	var ctx := UiContext.for_profile_name(&"touch")
	var land := HudLayout.compute(ctx, ctx.frame_size(Vector2(1366, 1024)), true, false)
	var port := HudLayout.compute(ctx, ctx.frame_size(Vector2(1024, 1366)), true, false)
	assert_str(String(land.panel_mode)).is_equal("side")
	assert_str(String(port.panel_mode)).is_equal("sheet")


func test_hud_desktop_ignores_the_drawer_flag() -> void:
	var hud := await _hud(&"desktop", DESKTOP, 3)
	assert_bool(hud.is_drawer_active()).is_false()
	assert_str(String(hud.layout.panel_mode)).is_equal("side")
	assert_bool(hud.panel.grip.visible).is_false()
	var names := UiTestSupport.button_texts(hud)
	assert_bool(names.has(UiText.t(&"panel.drawer_up"))).is_false()
	assert_bool(names.has(UiText.t(&"panel.drawer_down"))).is_false()


# --- HUD: konumlar, ok düğmeleri, sürükleme ---

func test_opens_half_and_arrows_walk_the_three_positions() -> void:
	var hud := await _hud(&"touch", IPAD_SMALL_LANDSCAPE, 3)
	assert_bool(hud.is_drawer_active()).is_true()
	assert_int(hud.drawer_state).is_equal(DrawerModel.State.HALF)
	var h_half := hud.panel.size.y
	hud.panel.drawer_up.pressed.emit()
	await await_idle_frame()
	assert_int(hud.drawer_state).is_equal(DrawerModel.State.FULL)
	assert_float(hud.panel.size.y).is_greater(h_half)
	assert_bool(hud.panel.drawer_up.visible).is_false()
	hud.panel.drawer_down.pressed.emit()
	hud.panel.drawer_down.pressed.emit()
	await await_idle_frame()
	assert_int(hud.drawer_state).is_equal(DrawerModel.State.CLOSED)
	assert_bool(hud.panel.drawer_down.visible).is_false()
	assert_bool(hud.panel.drawer_up.visible).is_true()
	assert_float(hud.panel.size.y).is_less(h_half * 0.5)
	# kapalıda içerik gizli, yalnız başlık şeridi kalır; panel kapanmış sayılmaz
	assert_bool(hud.panel.state_view.is_visible_in_tree()).is_false()
	assert_bool(hud.is_panel_open()).is_true()


func test_finger_drag_follows_then_snaps() -> void:
	var hud := await _hud(&"touch", IPAD_SMALL_LANDSCAPE, 3)
	var shell := hud.panel
	var start_h := shell.size.y
	shell.drawer_drag_started.emit()
	shell.drawer_dragged.emit(-80.0)   # parmak 80 px yukarı
	await await_idle_frame()
	assert_float(hud.panel.size.y).is_equal_approx(start_h + 80.0, 1.0)  # canlı takip
	shell.drawer_drag_ended.emit(0.0)
	await await_idle_frame()
	assert_int(hud.drawer_state).is_equal(DrawerModel.State.HALF)  # küçük sürükleme geri oturur
	shell.drawer_drag_started.emit()
	shell.drawer_dragged.emit(-9999.0)
	shell.drawer_drag_ended.emit(0.0)
	await await_idle_frame()
	assert_int(hud.drawer_state).is_equal(DrawerModel.State.FULL)
	shell.drawer_drag_started.emit()
	shell.drawer_drag_ended.emit(-1500.0)  # yukarı fırlatma: zaten TAM
	await await_idle_frame()
	assert_int(hud.drawer_state).is_equal(DrawerModel.State.FULL)
	shell.drawer_drag_started.emit()
	shell.drawer_drag_ended.emit(1500.0)   # aşağı fırlatma: bir konum aşağı
	await await_idle_frame()
	assert_int(hud.drawer_state).is_equal(DrawerModel.State.HALF)


func test_real_mouse_events_on_grip_drag_the_drawer() -> void:
	# Dokunma Godot'da fareye çevrilir; tutamaç üstünde basış-sürükleme-bırakma gerçek GUI olayıyla çalışır.
	var hud := await _hud(&"touch", IPAD_SMALL_LANDSCAPE, 3)
	var grip := hud.panel.grip
	var from := grip.get_global_rect().get_center()
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = from
	down.global_position = from
	hud.get_viewport().push_input(down)
	var pos := from
	for i in 12:
		var m := InputEventMouseMotion.new()
		pos += Vector2(0, -40)
		m.position = pos
		m.global_position = pos
		m.relative = Vector2(0, -40)
		m.button_mask = MOUSE_BUTTON_MASK_LEFT
		hud.get_viewport().push_input(m)
		await await_idle_frame()
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = pos
	up.global_position = pos
	hud.get_viewport().push_input(up)
	await await_idle_frame()
	assert_int(hud.drawer_state).is_equal(DrawerModel.State.FULL)


func test_reopening_starts_at_half_and_close_resets() -> void:
	var hud := await _hud(&"touch", IPAD_SMALL_LANDSCAPE, 3)
	hud.set_drawer_state(DrawerModel.State.FULL)
	hud.close_panel_hard()
	assert_bool(hud.is_drawer_active()).is_false()
	hud.open_panel(&"zoning", &"zoning.title", func(_c: UiContext) -> Control: return UiFactory.label("x"), true)
	assert_int(hud.drawer_state).is_equal(DrawerModel.State.HALF)


# --- görünürlük ve hedefler (1, 3, 6 parsel; iki yön) ---

func test_half_shows_use_buttons_and_send_with_44pt_targets() -> void:
	for window: Vector2 in [IPAD_SMALL_LANDSCAPE, IPAD_SMALL_PORTRAIT]:
		for n in [1, 3, 6]:
			var hud := await _hud(&"touch", window, n)
			var z := _zoning(hud)
			z.choose_use(&"zone.residential")
			await await_idle_frame()
			await await_idle_frame()
			var panel_rect := hud.panel.get_global_rect()
			assert_bool(Rect2(Vector2.ZERO, window).encloses(panel_rect)).override_failure_message(
				"panel pencere dışı %s n=%d" % [window, n]).is_true()
			var send := z.send_button().button
			assert_bool(send.is_visible_in_tree()).is_true()
			assert_bool(panel_rect.encloses(send.get_global_rect())).override_failure_message(
				"'Planı sun' çekmece dışı: %s %s n=%d panel=%s" % [send.get_global_rect(), window, n, panel_rect]).is_true()
			var view := hud.panel.scroll_view_rect()
			for use in UiConfig.land_uses():
				var b := z.use_button(use)
				assert_object(b).is_not_null()
				var r := b.get_global_rect()
				assert_bool(view.encloses(r)).override_failure_message(
					"kullanım '%s' ilk ekranda değil: %s görünür=%s %s n=%d" % [b.text, r, view, window, n]).is_true()
				assert_float(minf(r.size.x, r.size.y)).is_greater_equal(44.0)
			assert_float(minf(send.size.x, send.size.y)).is_greater_equal(44.0)
			for b: Button in [hud.panel.drawer_up, hud.panel.drawer_down, hud.panel.close_button(),
					hud.panel.pin_button()]:
				var hit := UiFactory.hit_size(b)
				assert_float(minf(hit.x, hit.y)).override_failure_message("'%s' %s" % [b.text, hit]).is_greater_equal(44.0)


func test_half_leaves_a_real_part_of_the_city_visible() -> void:
	for window: Vector2 in [IPAD_SMALL_LANDSCAPE, IPAD_SMALL_PORTRAIT]:
		var hud := await _hud(&"touch", window, 6)
		var free := hud.free_map_rect()
		assert_float(free.size.y).is_greater(window.y * 0.24)
		assert_float(free.size.x).is_equal(window.x)   # şehir yandan örtülmez
		hud.set_drawer_state(DrawerModel.State.CLOSED)
		assert_float(hud.free_map_rect().size.y).is_greater(window.y * 0.55)


func test_safe_area_is_respected_in_every_position() -> void:
	var safe := Vector4(20.0, 24.0, 20.0, 34.0)
	for state in [DrawerModel.State.CLOSED, DrawerModel.State.HALF, DrawerModel.State.FULL]:
		var hud := await _hud(&"touch", IPAD_SMALL_LANDSCAPE, 3, true, safe)
		hud.set_drawer_state(state)
		await await_idle_frame()
		var inner := Rect2(safe.x, safe.y, IPAD_SMALL_LANDSCAPE.x - safe.x - safe.z,
			IPAD_SMALL_LANDSCAPE.y - safe.y - safe.w)
		assert_bool(inner.encloses(hud.panel.get_global_rect())).override_failure_message(
			"çekmece güvenli alan dışında: %s / %s" % [hud.panel.get_global_rect(), inner]).is_true()
		assert_bool(inner.encloses(hud.toolbar.get_global_rect())).is_true()


func test_map_area_is_outside_the_drawer_and_hud_does_not_swallow_it() -> void:
	var hud := await _hud(&"touch", IPAD_SMALL_LANDSCAPE, 3)
	var free := hud.free_map_rect()
	var panel_rect := hud.panel.get_global_rect()
	assert_float(free.end.y).is_less_equal(panel_rect.position.y + 0.5)
	# HUD kökü olayı geçirir; yalnız panel durdurur. Harita bölgesindeki bir nokta panele düşmez.
	assert_int(hud.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)
	assert_int(hud.panel.mouse_filter).is_equal(Control.MOUSE_FILTER_STOP)
	assert_bool(panel_rect.has_point(free.get_center())).is_false()


func test_sticky_footer_holds_the_send_button_outside_the_scroll_on_touch_only() -> void:
	var hud := await _hud(&"touch", IPAD_SMALL_LANDSCAPE, 3)
	var send := _zoning(hud).send_button().button
	assert_bool(hud.panel.footer_box.is_ancestor_of(send)).is_true()
	assert_bool(hud.panel.state_view.is_ancestor_of(send)).is_false()
	# aynı bileşen masaüstünde altlıksız: düğme kaydırılan içerikte
	var d := await _hud(&"desktop", DESKTOP, 3)
	assert_bool(d.panel.state_view.is_ancestor_of(_zoning(d).send_button().button)).is_true()


func test_wide_drawer_uses_two_columns_narrow_uses_one() -> void:
	var land := await _hud(&"touch", IPAD_SMALL_LANDSCAPE, 3)
	var narrow := await _hud(&"touch", Vector2(480, 900), 3)
	assert_bool(_zoning(land)._cols.vertical).is_false()
	assert_bool(_zoning(narrow)._cols.vertical).is_true()


func test_municipal_entry_is_the_sticky_primary_action_of_an_empty_area_and_flow_fits_half() -> void:
	for window: Vector2 in [IPAD_SMALL_LANDSCAPE, IPAD_SMALL_PORTRAIT]:
		var hud := await _hud(&"touch", window, 0)
		var z := _zoning(hud)
		var open_btns := z.named_buttons("municipal_open")
		assert_int(open_btns.size()).is_equal(1)
		var entry := open_btns[0]
		assert_bool(hud.panel.footer_box.is_ancestor_of(entry)).is_true()
		assert_bool(hud.panel.get_global_rect().encloses(entry.get_global_rect())).override_failure_message(
			"belediye girişi çekmece dışı %s" % window).is_true()
		assert_float(minf(entry.size.x, entry.size.y)).is_greater_equal(44.0)
		entry.pressed.emit()   # belediye arazisi akışı: 15 parsel, özet satırı
		await await_idle_frame()
		await await_idle_frame()
		z.choose_use(&"zone.residential")
		await await_idle_frame()
		await await_idle_frame()
		var send := z.send_button().button
		var panel_rect := hud.panel.get_global_rect()
		assert_bool(panel_rect.encloses(send.get_global_rect())).override_failure_message("sun %s" % window).is_true()
		for use in UiConfig.land_uses():
			assert_bool(hud.panel.scroll_view_rect().encloses(z.use_button(use).get_global_rect())).override_failure_message(
				"belediye akışı: '%s' ilk ekranda değil %s" % [use, window]).is_true()
