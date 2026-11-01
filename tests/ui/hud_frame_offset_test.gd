extends GdUnitTestSuite
## B-014 (madde 3 + iPad "Gün N" şeridi): güvenli alan iç boşluğu olan (dokunmatik) HUD'da çerçeve GERÇEKTEN o kadar
## kaydırılır; `free_map_rect()` (alt yardım satırı, ipucu kartı, onay işareti bunu kullanır) araç çubuğunun/panelin
## gerçek yerleriyle tutarlıdır. Kök neden: `HudRoot._relayout` çerçeve konumunu sıfırlıyordu (UiSafeArea'nın verdiği
## kaydırmayı siliyor), `free_map_rect` ise kaydırmayı ekliyordu: serbest dikdörtgen araç çubuğunun üzerine ~üst güvenli
## alan kadar taşıyordu ("Gün N" yardım satırı araç çubuğuna biniyordu).

const WINDOWS := [Vector2(1024, 768), Vector2(1194, 834), Vector2(834, 1194)]
const IPAD_SAFE := Vector4(0.0, 24.0, 0.0, 20.0)


func before_test() -> void:
	UiText.reset()
	UiText.report_missing = false


func after_test() -> void:
	UiText.reset()


func _hud(window: Vector2, simulated: Vector4) -> HudRoot:
	var hud := HudRoot.new()
	hud.simulated_safe = simulated
	add_child(hud)
	hud.setup(UiTestSupport.non_mock(), UiTestSupport.platform(&"touch"))
	hud.set_anchors_preset(Control.PRESET_TOP_LEFT)
	hud.size = window
	hud.refresh()
	return auto_free(hud)


func test_touch_frame_is_shifted_by_the_safe_area_so_the_top_bar_clears_the_status_bar() -> void:
	for window: Vector2 in WINDOWS:
		var hud := _hud(window, IPAD_SAFE)
		await get_tree().process_frame
		await get_tree().process_frame
		var ins := hud.ctx.frame_insets()
		assert_float(hud.top_bar.get_global_rect().position.y).override_failure_message(
			"üst şerit güvenli alanın altından başlamalı (%s)" % window).is_greater_equal(ins.y - 0.01)
		assert_float(hud.toolbar.get_global_rect().end.y).override_failure_message(
			"araç çubuğu alt güvenli alana girmemeli (%s)" % window).is_less_equal(window.y - ins.w + 0.01)


func test_free_map_rect_never_reaches_into_the_toolbar_or_the_panel() -> void:
	for window: Vector2 in WINDOWS:
		for simulated: Vector4 in [IPAD_SAFE, Vector4.ZERO]:
			var hud := _hud(window, simulated)
			hud.open_panel(&"probe", &"hud.toolbar", func(c: UiContext) -> Control:
				var l := UiFactory.label("içerik", &"", true)
				l.theme = UiTheme.build(c)
				return l)
			await get_tree().process_frame
			await get_tree().process_frame
			var free := hud.free_map_rect()
			var tag := "%s %s" % [window, simulated]
			assert_float(free.end.y).override_failure_message(
				"serbest alan araç çubuğuna taşıyor " + tag).is_less_equal(hud.toolbar.get_global_rect().position.y + 0.01)
			assert_float(free.position.y).override_failure_message(
				"serbest alan üst şeridin üstünde " + tag).is_greater_equal(hud.top_bar.get_global_rect().end.y - 0.01)
			if hud.is_panel_open():
				assert_bool(free.intersects(hud.panel.get_global_rect().grow(-1.0))).override_failure_message(
					"serbest alan panelle çakışıyor " + tag).is_false()


func test_bottom_help_line_clears_the_toolbar_by_at_least_8pt() -> void:
	for window: Vector2 in WINDOWS:
		var hud := _hud(window, IPAD_SAFE)
		await get_tree().process_frame
		await get_tree().process_frame
		var help := HudHelp.status_rect(hud.free_map_rect(), 26.0)
		var gap := hud.toolbar.get_global_rect().position.y - help.end.y
		assert_float(gap).override_failure_message("yardım satırı araç çubuğuna %s px yakın (%s)" % [gap, window]) \
			.is_greater_equal(8.0)


## Gerçek cihaz/pencere sırası: güvenli alan değerleri HUD kurulduktan SONRA gelir (ilk kare sıfır, sonra ekran
## okuması); çerçeve yine de kaymış olmalı ve serbest alan araç çubuğuna taşmamalı.
func test_insets_arriving_after_setup_still_shift_the_frame_and_keep_the_rects_consistent() -> void:
	var hud := _hud(Vector2(1024, 768), Vector4.ZERO)
	await get_tree().process_frame
	hud._safe.simulated = Vector4(0.0, 26.0, 0.0, 46.0)
	hud._safe.refresh()  # çerçeveyi UiSafeArea (MarginContainer) yeniden boyutlar; `resized` -> HudRoot yerleşimi
	await get_tree().process_frame
	hud.size = Vector2(1100, 800)  # pencere boyutu değişir (yön/pencere): çerçeve yine kaymış kalmalı
	await get_tree().process_frame
	hud.size = Vector2(1024, 768)
	await get_tree().process_frame
	await get_tree().process_frame
	# Sonraki her yerleşim geçişi (panel açılması, bildirim, sekme) çerçeveyi yine kaydırılmış bırakmalı.
	for i in 3:
		hud._relayout()
		await get_tree().process_frame
	var ins := hud.ctx.frame_insets()
	assert_float(hud.top_bar.get_global_rect().position.y).is_greater_equal(ins.y - 0.01)
	assert_float(hud.free_map_rect().end.y).is_less_equal(hud.toolbar.get_global_rect().position.y + 0.01)


## Kök neden doğrudan: yerleşim geçişi (`resized` -> `_relayout`, container sıralaması sırasında da çağrılır) çerçeve
## konumunu güvenli alan kaydırmasında bırakır; sonraki bir sıralama beklenmez. (Oyunda: `frame.position == 0` iken
## `margin_top == 26`, üst şerit 0'da, serbest alan araç çubuğuna 26 px taşıyordu.)
func test_relayout_itself_keeps_the_safe_area_shift_without_waiting_for_a_container_sort() -> void:
	var hud := _hud(Vector2(1024, 768), Vector4(0.0, 18.0, 0.0, 38.0))
	await get_tree().process_frame
	await get_tree().process_frame
	var ins := hud.ctx.frame_insets()
	hud._frame.position = Vector2.ZERO  # container sıralaması araya girmeden önceki an
	hud._relayout()
	assert_vector(hud._frame.position).is_equal(Vector2(ins.x, ins.y))
	assert_float(hud.free_map_rect().end.y).is_less_equal(hud.toolbar.get_global_rect().position.y + 0.01)
