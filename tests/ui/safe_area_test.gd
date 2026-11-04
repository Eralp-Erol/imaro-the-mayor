extends GdUnitTestSuite
## T-019 ölçüt 2 · Güvenli alan hesabı (iPad): ekran güvenli dikdörtgeni → pencere iç boşlukları.
## Olumsuz: güvenli alan = ekran ise boşluk yok; bozuk girdi (sıfır boyut) çökertmez.


func test_notch_and_home_indicator_insets() -> void:
	# 1366x1024 ekran; üstte 24, altta 20 piksel güvenli değil.
	var ins := UiSafeArea.insets_from(Rect2i(0, 24, 1366, 980), Vector2i(1366, 1024), Vector2i(1366, 1024))
	assert_vector(Vector2(ins.y, ins.w)).is_equal(Vector2(24.0, 20.0))
	assert_float(ins.x).is_equal(0.0)
	assert_float(ins.z).is_equal(0.0)


func test_landscape_side_cutout_insets() -> void:
	var ins := UiSafeArea.insets_from(Rect2i(40, 0, 1286, 1024), Vector2i(1366, 1024), Vector2i(1366, 1024))
	assert_float(ins.x).is_equal(40.0)
	assert_float(ins.z).is_equal(40.0)


func test_insets_scale_to_window_size() -> void:
	var ins := UiSafeArea.insets_from(Rect2i(0, 40, 2000, 1960), Vector2i(2000, 2000), Vector2i(1000, 1000))
	assert_float(ins.y).is_equal(20.0)


func test_full_safe_area_means_no_insets() -> void:
	var ins := UiSafeArea.insets_from(Rect2i(0, 0, 1600, 900), Vector2i(1600, 900), Vector2i(1600, 900))
	assert_vector(Vector2(ins.x, ins.y)).is_equal(Vector2.ZERO)
	assert_vector(Vector2(ins.z, ins.w)).is_equal(Vector2.ZERO)


func test_degenerate_input_returns_zero() -> void:
	assert_object(UiSafeArea.insets_from(Rect2i(), Vector2i(0, 0), Vector2i(100, 100))).is_equal(Vector4.ZERO)
	assert_object(UiSafeArea.insets_from(Rect2i(0, 0, 10, 10), Vector2i(100, 100), Vector2i(0, 0))).is_not_null()


func test_container_applies_simulated_insets_as_margins() -> void:
	var ctx := UiContext.for_profile_name(&"touch")
	var safe := auto_free(UiSafeArea.new()) as UiSafeArea
	safe.simulated = Vector4(0.0, 24.0, 0.0, 20.0)
	add_child(safe)
	safe.setup(ctx)
	assert_int(safe.get_theme_constant(&"margin_top")).is_equal(32)
	assert_int(safe.get_theme_constant(&"margin_bottom")).is_equal(28)
	assert_int(safe.get_theme_constant(&"margin_left")).is_equal(0)
