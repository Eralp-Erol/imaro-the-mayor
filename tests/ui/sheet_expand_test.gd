extends GdUnitTestSuite
## T-022 · iPad dikey alt sayfa "Genişlet/Küçült": karar akışlarında (imar, bütçe) birincil eylem ve gerekçe ilk
## yüksekliğin altında kalıyordu (T-021'de AÇIK bırakılan kısıt). Varsayılan %45 DEĞİŞMEZ; oyuncu isteğiyle yükselir.
## Olumsuz: masaüstü/yatay yan panelde düğme yok; genişlemiş sayfa araç çubuğunu örtmez ve çerçeve dışına taşmaz.

const IPAD_PORTRAIT := Vector2(1024, 1366)
const IPAD_LANDSCAPE := Vector2(1366, 1024)
const DESKTOP := Vector2(1600, 900)


func before_test() -> void:
	UiText.reset()
	UiText.report_missing = false


func after_test() -> void:
	UiText.reset()


func _hud(profile_name: StringName, window: Vector2) -> HudRoot:
	var hud := HudRoot.new()
	add_child(hud)
	hud.setup(UiTestSupport.mock(), UiTestSupport.platform(profile_name))
	hud.set_anchors_preset(Control.PRESET_TOP_LEFT)
	hud.size = window
	hud.refresh()
	return auto_free(hud)


func _probe(c: UiContext) -> Control:
	var l := UiFactory.label("içerik", &"", true)
	l.theme = UiTheme.build(c)
	return l


func test_layout_expanded_sheet_is_taller_but_stays_clear_of_toolbar_and_inside_frame() -> void:
	var ctx := UiContext.for_profile_name(&"touch")
	var frame := ctx.frame_size(IPAD_PORTRAIT)
	var normal := HudLayout.compute(ctx, frame, true, false, 0.0, false)
	var wide := HudLayout.compute(ctx, frame, true, false, 0.0, true)
	assert_float(wide.panel.size.y).is_greater(normal.panel.size.y * 1.5)
	assert_float(wide.panel.end.y).is_less_equal(wide.toolbar.position.y)  # araç çubuğunu örtmez
	assert_float(wide.panel.position.y).is_greater_equal(wide.top.end.y)  # üst şeridi örtmez
	assert_float(normal.panel.size.y + normal.toolbar.size.y).is_less_equal(frame.y * 0.45 + 1.0)  # varsayılan %45 sürer
	assert_float(wide.panel.size.y + wide.toolbar.size.y).is_less_equal(frame.y * 0.8 + 1.0)


func test_expand_has_no_effect_on_side_panel_layouts() -> void:
	var ctx := UiContext.for_profile_name(&"touch")
	var frame := ctx.frame_size(IPAD_LANDSCAPE)
	var a := HudLayout.compute(ctx, frame, true, false, 0.0, false)
	var b := HudLayout.compute(ctx, frame, true, false, 0.0, true)
	assert_that(b.panel).is_equal(a.panel)


func test_expand_button_only_in_portrait_touch_and_is_a_labelled_44pt_target() -> void:
	var portrait := _hud(&"touch", IPAD_PORTRAIT)
	portrait.open_panel(&"probe", &"inspector.title", _probe)
	await await_idle_frame()
	var button := portrait.panel.expand_button()
	assert_bool(button.visible).is_true()
	assert_str(button.text).is_equal("Genişlet")
	assert_float(minf(UiFactory.hit_size(button).x, UiFactory.hit_size(button).y)).is_greater_equal(44.0)
	for other: Array in [[&"touch", IPAD_LANDSCAPE], [&"desktop", DESKTOP]]:
		var hud := _hud(other[0], other[1])
		hud.open_panel(&"probe", &"inspector.title", _probe)
		await await_idle_frame()
		assert_bool(hud.panel.expand_button().visible).override_failure_message("yan panelde Genişlet olmamalı").is_false()


func test_toggle_grows_the_sheet_and_the_choice_survives_a_panel_swap() -> void:
	var hud := _hud(&"touch", IPAD_PORTRAIT)
	hud.open_panel(&"probe", &"inspector.title", _probe)
	await await_idle_frame()
	var before := hud.panel.size.y
	hud.panel.expand_button().button_pressed = true
	await await_idle_frame()
	assert_bool(hud.sheet_expanded).is_true()
	assert_float(hud.panel.size.y).is_greater(before * 1.5)
	assert_str(hud.panel.expand_button().text).is_equal("Küçült")
	hud.open_panel(&"probe2", &"inspector.title", _probe)  # başka panel: tercih kalır
	await await_idle_frame()
	assert_float(hud.panel.size.y).is_greater(before * 1.5)
	assert_bool(hud.panel.expand_button().button_pressed).is_true()
	hud.panel.expand_button().button_pressed = false
	await await_idle_frame()
	assert_float(hud.panel.size.y).is_equal_approx(before, 1.0)
	var whole := Rect2(Vector2.ZERO, IPAD_PORTRAIT).grow(1.0)
	assert_bool(whole.encloses(hud.panel.get_global_rect())).is_true()
