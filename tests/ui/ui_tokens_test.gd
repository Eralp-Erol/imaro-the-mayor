extends GdUnitTestSuite
## T-019 ölçüt 2/6 · Belirteçler tek kaynaktan; PlatformProfile.ui_scale/min_touch_target_pt ile ölçeklenir;
## dokunmatik alt sınırları (44/56 pt, gövde 17, yardımcı 13) kullanıcı ölçeği küçültse de korunur;
## kontrast ≥ 4.5:1.
## Olumsuz: bilerek düşük kontrastlı çift ve küçültülmüş ölçek denetçide yakalanır.

const MIN_TEXT_CONTRAST := 4.5
const MIN_UI_CONTRAST := 3.0


func test_desktop_sizes_follow_tokens() -> void:
	var ctx := UiContext.for_profile_name(&"desktop")
	assert_float(ctx.ui_scale).is_equal(1.0)
	assert_int(ctx.font_body()).is_equal(14)
	assert_float(ctx.target_min()).is_equal(36.0)
	assert_bool(ctx.hover_available).is_true()


func test_touch_targets_meet_ipad_minimums() -> void:
	var ctx := UiContext.for_profile_name(&"touch")
	assert_float(ctx.target_min()).is_greater_equal(44.0)
	assert_float(ctx.target_primary()).is_greater_equal(56.0)
	assert_int(ctx.font_body()).is_greater_equal(17)
	assert_int(ctx.font_small()).is_greater_equal(13)
	assert_bool(ctx.hover_available).is_false()
	assert_float(ctx.spacing()).is_greater_equal(8.0)


func test_touch_floors_hold_even_when_user_shrinks_scale() -> void:
	var ctx := UiContext.for_profile_name(&"touch", 0.8)
	assert_float(ctx.ui_scale).is_equal(0.8)
	assert_float(ctx.target_min()).is_greater_equal(44.0)
	assert_float(ctx.target_primary()).is_greater_equal(56.0)
	assert_int(ctx.font_body()).is_greater_equal(17)


func test_scale_override_scales_desktop_sizes() -> void:
	var base := UiContext.for_profile_name(&"desktop")
	var big := UiContext.for_profile_name(&"desktop", 1.5)
	assert_float(big.target_min()).is_equal(base.target_min() * 1.5)
	assert_int(big.font_body()).is_greater(base.font_body())


func test_profile_min_touch_target_is_absolute_floor() -> void:
	var profile := UiTestSupport.platform(&"touch")
	profile.min_touch_target_pt = 60.0
	var ctx := UiContext.from_profile(profile)
	assert_float(ctx.target_min()).is_greater_equal(60.0)


func test_text_colors_have_enough_contrast_on_their_surfaces() -> void:
	var tk := UiTokens.load_default()
	var surfaces := ["panel_bg", "hud_bg", "panel_bg_alt", "button_bg", "button_hover"]
	for surface in surfaces:
		for fg in ["text", "text_muted", "danger"]:
			var ratio := UiTokens.contrast_ratio(tk.color(fg), _opaque(tk.color(surface)))
			assert_float(ratio).override_failure_message("%s on %s = %.2f" % [fg, surface, ratio]) \
				.is_greater_equal(MIN_TEXT_CONTRAST)
	for pair in [["text_on_accent", "accent"], ["text_on_accent", "button_pressed"], ["text_on_accent", "mock"]]:
		var ratio := UiTokens.contrast_ratio(tk.color(pair[0]), tk.color(pair[1]))
		assert_float(ratio).override_failure_message("%s on %s = %.2f" % [pair[0], pair[1], ratio]) \
			.is_greater_equal(MIN_TEXT_CONTRAST)


func test_focus_ring_contrasts_with_surfaces() -> void:
	var tk := UiTokens.load_default()
	for surface in ["panel_bg", "hud_bg", "button_bg"]:
		assert_float(UiTokens.contrast_ratio(tk.color("focus"), _opaque(tk.color(surface)))).is_greater_equal(
			MIN_UI_CONTRAST)


func test_contrast_checker_negative_control() -> void:
	# Düşük kontrastlı çift gerçekten eşiğin altında ölçülmeli (denetçi kör değil).
	var ratio := UiTokens.contrast_ratio(Color("777777"), Color("808080"))
	assert_float(ratio).is_less(MIN_TEXT_CONTRAST)
	assert_float(UiTokens.contrast_ratio(Color.WHITE, Color.BLACK)).is_greater(20.0)


func test_theme_uses_context_sizes_and_visible_focus() -> void:
	var ctx := UiContext.for_profile_name(&"touch")
	var theme := UiTheme.build(ctx)
	assert_int(theme.default_font_size).is_equal(ctx.font_body())
	assert_int(theme.get_font_size(&"font_size", &"Button")).is_equal(ctx.font_body())
	var focus := theme.get_stylebox(&"focus", &"Button") as StyleBoxFlat
	assert_object(focus).is_not_null()
	assert_bool(focus.draw_center).is_false()
	assert_int(focus.border_width_left).is_greater_equal(2)
	assert_bool(theme.has_stylebox(&"panel", UiTheme.V_PANEL_CARD)).is_true()


func test_theme_rebuilds_with_scale() -> void:
	var small := UiTheme.build(UiContext.for_profile_name(&"desktop"))
	var large := UiTheme.build(UiContext.for_profile_name(&"desktop", 2.0))
	assert_int(large.default_font_size).is_greater(small.default_font_size)


func test_tokens_and_config_contain_no_forbidden_currency() -> void:
	for path in ["res://data/ui/ui_tokens.json", "res://data/ui/ui_config.json"]:
		var text := FileAccess.get_file_as_string(path)
		for bad in ["₺", "lira", "Lira", " TL"]:
			assert_bool(text.contains(bad)).override_failure_message("%s içinde %s" % [path, bad]).is_false()
	assert_str(UiConfig.currency_symbol()).is_equal("¤")


func test_safe_area_extra_applies_only_to_touch() -> void:
	var touch := UiContext.for_profile_name(&"touch")
	touch.safe_insets = Vector4(0.0, 24.0, 0.0, 20.0)
	var ins := touch.frame_insets()
	assert_float(ins.y).is_equal(24.0 + 8.0)
	assert_float(ins.w).is_equal(20.0 + 8.0)
	var desktop := UiContext.for_profile_name(&"desktop")
	assert_float(desktop.frame_insets().y).is_equal(0.0)


func _opaque(c: Color) -> Color:
	# Yarı saydam zemin koyu dünya üzerinde çizilir; en kötü durum için opak kabul edilir.
	return Color(c.r, c.g, c.b, 1.0)
