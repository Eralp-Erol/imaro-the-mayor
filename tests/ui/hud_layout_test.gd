extends GdUnitTestSuite
## T-019 ölçüt 2/6 · Yerleşim değişmezleri (masaüstü / iPad yatay / iPad dikey): hiçbir parça çerçeve
## dışına taşmaz,
## L2 genişlik/yükseklik sınırları, panel açıkken harita merkezi ≥ yarı görünür, araç çubuğu ile panel
## çakışmaz,
## ultra geniş ekranda panel BÜYÜMEZ, dikeyde araç çubuğu iki satır + alt sayfa.
## Olumsuz: gömen bir panel düzeni gerçekten ölçütü ihlal edecek şekilde hesaplanır (denetçi kör değil).

const DESKTOP_SIZES := [
	Vector2(1280, 720), Vector2(1600, 900), Vector2(1920, 1080), Vector2(2560, 1440), Vector2(3440, 1440),
]
const TOUCH_LANDSCAPE := [Vector2(1194, 834), Vector2(1366, 1024)]
const TOUCH_PORTRAIT := [Vector2(834, 1194), Vector2(1024, 1366)]


func _layout(ctx: UiContext, window: Vector2, open: bool = true, mock: bool = true) -> HudLayout:
	return HudLayout.compute(ctx, ctx.frame_size(window), open, mock)


func _inside(l: HudLayout, frame: Vector2) -> void:
	var whole := Rect2(Vector2.ZERO, frame)
	for r: Rect2 in [l.top, l.toolbar, l.panel, l.banner]:
		if r.size.x > 0.0:
			assert_bool(whole.grow(0.01).encloses(r)).override_failure_message("taşma: %s / %s" % [r, whole]).is_true()


func test_desktop_layouts_fit_and_keep_center_visible() -> void:
	var ctx := UiContext.for_profile_name(&"desktop")
	for window: Vector2 in DESKTOP_SIZES:
		var l := _layout(ctx, window)
		_inside(l, window)
		assert_that(l.panel_mode).is_equal(HudLayout.MODE_SIDE)
		assert_float(l.panel.size.x).is_less_equal(window.x * 0.28 + 0.01)
		assert_float(l.center_visible_fraction(window)).is_greater_equal(0.5)
		assert_bool(l.panel.intersects(l.toolbar)).is_false()


func test_desktop_panel_does_not_grow_on_ultrawide() -> void:
	var ctx := UiContext.for_profile_name(&"desktop")
	var a := _layout(ctx, Vector2(1920, 1080))
	var b := _layout(ctx, Vector2(3440, 1440))
	assert_float(a.panel.size.x).is_equal(400.0)
	assert_float(b.panel.size.x).is_equal(400.0)


func test_desktop_minimum_window_panel_width_follows_28_percent_cap() -> void:
	var ctx := UiContext.for_profile_name(&"desktop")
	var l := _layout(ctx, Vector2(1280, 720))
	assert_float(l.panel.size.x).is_between(350.0, 360.0)


func test_touch_landscape_uses_side_panel_up_to_38_percent() -> void:
	var ctx := UiContext.for_profile_name(&"touch")
	for window: Vector2 in TOUCH_LANDSCAPE:
		var l := _layout(ctx, window)
		var frame := ctx.frame_size(window)
		_inside(l, frame)
		assert_that(l.panel_mode).is_equal(HudLayout.MODE_SIDE)
		assert_that(l.toolbar_rows).is_equal(1)
		assert_float(l.panel.size.x).is_less_equal(frame.x * 0.38 + 0.01)
		assert_float(l.center_visible_fraction(frame)).is_greater_equal(0.5)


func test_touch_portrait_uses_bottom_sheet_and_two_toolbar_rows() -> void:
	var ctx := UiContext.for_profile_name(&"touch")
	for window: Vector2 in TOUCH_PORTRAIT:
		var l := _layout(ctx, window)
		var frame := ctx.frame_size(window)
		_inside(l, frame)
		assert_that(l.panel_mode).is_equal(HudLayout.MODE_SHEET)
		assert_that(l.toolbar_rows).is_equal(2)
		assert_float(l.panel.size.y).is_less_equal(frame.y * 0.45 + 0.01)
		assert_float(l.panel.end.y).is_less_equal(l.toolbar.position.y)
		assert_float(l.center_visible_fraction(frame)).is_greater_equal(0.5)
		assert_bool(l.panel.has_point(frame * 0.5)).is_false()


func test_touch_edges_keep_16pt_margin_for_critical_buttons() -> void:
	var ctx := UiContext.for_profile_name(&"touch")
	for window: Vector2 in TOUCH_LANDSCAPE + TOUCH_PORTRAIT:
		var l := _layout(ctx, window)
		var frame := ctx.frame_size(window)
		assert_float(l.toolbar.position.x).is_greater_equal(16.0)
		assert_float(frame.y - l.toolbar.end.y).is_greater_equal(16.0)


func test_safe_area_shrinks_frame_and_keeps_layout_inside() -> void:
	var ctx := UiContext.for_profile_name(&"touch")
	ctx.safe_insets = Vector4(0.0, 24.0, 0.0, 20.0)
	var window := Vector2(1366, 1024)
	var frame := ctx.frame_size(window)
	assert_float(frame.y).is_equal(1024.0 - 32.0 - 28.0)
	_inside(HudLayout.compute(ctx, frame, true, true), frame)


func test_closed_panel_has_no_footprint_and_map_is_full_width() -> void:
	var ctx := UiContext.for_profile_name(&"desktop")
	var l := _layout(ctx, Vector2(1600, 900), false)
	assert_float(l.panel.size.x).is_equal(0.0)
	assert_float(l.map_region.size.x).is_equal(1600.0)


func test_banner_only_takes_space_when_shown() -> void:
	var ctx := UiContext.for_profile_name(&"desktop")
	var with_banner := _layout(ctx, Vector2(1600, 900), true, true)
	var without := _layout(ctx, Vector2(1600, 900), true, false)
	assert_float(with_banner.banner.size.y).is_greater(0.0)
	assert_float(without.banner.size.y).is_equal(0.0)
	assert_float(without.map_region.position.y).is_less(with_banner.map_region.position.y)


func test_negative_control_a_panel_that_buries_the_city_is_detected() -> void:
	var frame := Vector2(1600, 900)
	var l := HudLayout.new()
	l.top = Rect2(0, 0, 1600, 48)
	l.panel = Rect2(300, 48, 1300, 852)  # haritanın çoğunu gömen panel
	assert_float(l.center_visible_fraction(frame)).is_less(0.5)
