extends GdUnitTestSuite
## D-021 genişletme: şehri örten TÜM gerçek paneller (meclis, bütçe, gündem, politika, denetçi, sonuç, nedensellik)
## dokunmatikte aynı alttan çekmece (kapalı/yarı/tam), masaüstü yan panel kalır. Başsız yerleşim ölçümü; GERÇEK
## parmak/iPad denemesi DEĞİL. İmar çekmecesinin ayrıntıları `drawer_test.gd`'de.

const IPAD_SMALL_LANDSCAPE := Vector2(1024, 768)
const IPAD_SMALL_PORTRAIT := Vector2(768, 1024)
const DESKTOP := Vector2(1600, 900)
const DRAWER_PANELS: Array[StringName] = [&"council", &"budget", &"agenda", &"policy", &"inspector", &"m2", &"reason"]


func before_test() -> void:
	UiText.reset()
	UiText.report_missing = false


func after_test() -> void:
	UiText.reset()

func _open_other(hud: HudRoot, which: StringName) -> void:
	var f := hud.facade
	var d := DecisionPanels.attach(hud, f)
	match which:
		&"council":
			d.open_council()
		&"budget":
			d.open_budget()
		&"agenda":
			d.open_agenda()
		&"policy":
			d.open_policy()
		&"inspector":
			InspectorHost.attach(hud, f).open()
		&"m2":
			M2Results.attach(hud, f, d).open()
		&"reason":
			M2Results.attach(hud, f, d).open_reason(func(_p: ReasonPanel) -> void: pass)
	await await_idle_frame()
	await await_idle_frame()


func _plain_hud(profile_name: StringName, window: Vector2) -> HudRoot:
	var hud := HudRoot.new()
	add_child(hud)
	hud.setup(UiTestSupport.mock(), UiTestSupport.platform(profile_name))
	hud.set_anchors_preset(Control.PRESET_TOP_LEFT)
	hud.size = window
	hud.refresh()
	return auto_free(hud)


func test_every_city_covering_panel_is_a_drawer_on_touch_and_closed_leaves_the_city() -> void:
	InspectorHost.default_interval_msec = 0
	for which in DRAWER_PANELS:
		for window: Vector2 in [IPAD_SMALL_LANDSCAPE, IPAD_SMALL_PORTRAIT]:
			var hud := _plain_hud(&"touch", window)
			await _open_other(hud, which)
			var tag := "%s %s" % [which, window]
			assert_bool(hud.is_drawer_active()).override_failure_message("çekmece değil: " + tag).is_true()
			assert_str(String(hud.layout.panel_mode)).is_equal("drawer")
			assert_int(hud.drawer_state).is_equal(DrawerModel.State.HALF)
			var half_h := hud.panel.size.y
			hud.set_drawer_state(DrawerModel.State.CLOSED)
			await await_idle_frame()
			await await_idle_frame()
			assert_float(hud.panel.size.y).override_failure_message("kapalı küçülmedi: " + tag).is_less(half_h * 0.5)
			assert_bool(hud.free_map_rect().get_area() > half_h * window.x * 0.4).is_true()
			assert_bool(hud.panel.get_global_rect().has_point(hud.free_map_rect().get_center())).is_false()
			hud.set_drawer_state(DrawerModel.State.FULL)
			await await_idle_frame()
			await await_idle_frame()
			assert_float(hud.panel.size.y).is_greater(half_h)
			# başlık şeridindeki düğmeler (Kapat, ok) 44 pt
			assert_float(minf(hud.panel.close_button().size.x, hud.panel.close_button().size.y)).is_greater_equal(44.0)
			assert_bool(hud.panel.get_global_rect().position.y >= hud.top_bar.get_global_rect().end.y - 0.5).is_true()


func test_other_panels_stay_side_or_sheet_on_desktop() -> void:
	InspectorHost.default_interval_msec = 0
	for which in DRAWER_PANELS:
		var hud := _plain_hud(&"desktop", DESKTOP)
		await _open_other(hud, which)
		assert_bool(hud.is_drawer_active()).override_failure_message("masaüstü çekmece: %s" % which).is_false()
		assert_str(String(hud.layout.panel_mode)).is_equal("side")
		assert_bool(hud.panel.grip.visible).is_false()


func test_switching_between_drawer_panels_resets_to_half() -> void:
	var hud := _plain_hud(&"touch", IPAD_SMALL_LANDSCAPE)
	var d := DecisionPanels.attach(hud, hud.facade)
	d.open_budget()
	hud.set_drawer_state(DrawerModel.State.FULL)
	d.open_policy()
	await await_idle_frame()
	assert_int(hud.drawer_state).is_equal(DrawerModel.State.HALF)


## D-022 (sahip: "C"): yol çizimi ve denetçi yarıda alçak (%45), karar panelleri %62.
func test_low_half_for_road_and_inspector_normal_for_decision_panels() -> void:
	var frame := IPAD_SMALL_LANDSCAPE
	var ctx := UiContext.for_profile_name(&"touch")
	var normal := HudLayout.compute(ctx, frame, true, false, 0.0, false, 0.0, DrawerModel.State.HALF)
	var low := HudLayout.compute(ctx, frame, true, false, 0.0, false, 0.0, DrawerModel.State.HALF, -1.0, 0.0, true)
	var half := DrawerModel.State.HALF
	assert_float(float(low.drawer_heights[half])).is_less(float(normal.drawer_heights[half]))
	assert_float(float(low.drawer_heights[DrawerModel.State.FULL])).is_equal(
			float(normal.drawer_heights[DrawerModel.State.FULL]))
	assert_float(low.panel.size.y / float(normal.panel.size.y)).is_less(0.8)
	for id: StringName in [&"road_draw", &"inspector"]:
		assert_bool(HudRoot.DRAWER_LOW_PANELS.has(id)).is_true()
	for id: StringName in [&"council", &"budget", &"agenda", &"policy", &"m2", &"reason", &"zoning"]:
		assert_bool(HudRoot.DRAWER_LOW_PANELS.has(id)).is_false()


## B-125: TAM çekmecede harita şeridi, bildirim şeridinin en az bir (2 satır) satırına yeter; YARI yüksekliği değişmez.
func test_full_drawer_leaves_a_map_strip_for_one_notification_row_and_half_is_unchanged() -> void:
	var ctx := UiContext.for_profile_name(&"touch")
	for frame: Vector2 in [IPAD_SMALL_LANDSCAPE, IPAD_SMALL_PORTRAIT]:
		var full := HudLayout.compute(ctx, frame, true, false, 0.0, false, 0.0, DrawerModel.State.FULL)
		var free_h := full.panel.position.y - full.top.end.y
		assert_float(free_h).override_failure_message("TAM: harita şeridi %.1f px (%s)" % [free_h, str(frame)]) \
				.is_greater_equal(ctx.px(ctx.tokens.size("drawer_map_strip_full")) - 0.5)
		assert_float(full.notifications.position.y + 65.0).is_less_equal(full.panel.position.y)
		var half := HudLayout.compute(ctx, frame, true, false, 0.0, false, 0.0, DrawerModel.State.HALF)
		var strip_px := ctx.px(ctx.tokens.size("drawer_map_strip"))
		var half_room := half.toolbar.position.y - ctx.spacing() - full.top.end.y - strip_px
		assert_float(float(half.drawer_heights[DrawerModel.State.HALF])).is_equal_approx(
				half_room * ctx.tokens.limit("drawer_frac_half"), 1.0)
