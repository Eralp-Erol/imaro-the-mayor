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
