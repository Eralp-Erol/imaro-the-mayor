extends GdUnitTestSuite
## B-019 · Tek yerleşim mantığı: dolu bildirim şeridi + hız ipucu kartı + yol ipucu kartı + (yan panel / alt sayfada)
## yıkım onayı birlikte açıkken görünür HUD dikdörtgenlerinin hiçbir çifti kesişmez, hiçbiri ekran dışında değildir;
## dokunmatikte her düğmenin dokunma hedefi >= 44 pt ve düğmeler arası boşluk >= 8 pt; "Evet, yık" ve "Vazgeç" panel
## kaydırılmadan tam görünür. Çözünürlükler: 1600x900 (masaüstü), 1024x768 ve 800x600 (dokunmatik, masaüstü).
## Gerçek sim facade'i (P.setup), gerçek HudRoot/NotificationStrip/PlayableSpeedHint/RoadCursorTip/RoadDrawPanel.

const P := preload("res://tests/sim/public_works/public_works_support.gd")
const NORTH := Vector2(1100.0, 1000.0)
const CASES := [
	[&"desktop", Vector2(1600.0, 900.0)],
	[&"touch", Vector2(1024.0, 768.0)],
	[&"touch", Vector2(800.0, 600.0)],
	[&"desktop", Vector2(800.0, 600.0)],
	[&"touch", Vector2(768.0, 1024.0)],
]
const MIN_TARGET := 44.0
const MIN_GAP := 8.0


func before_test() -> void:
	UiText.reset()
	UiText.report_missing = false


func after_test() -> void:
	UiText.reset()


func _scene(profile: StringName, viewport: Vector2, with_tip: bool, confirm: bool) -> Dictionary:
	var run := P.setup()
	var facade: SimFacadeImpl = run["facade"]
	var tool := RoadDrawTool.create(run["net"], facade)
	tool.activate()
	tool.tap_at(P.GRID_ORIGIN, 5.0)
	tool.tap_at(NORTH, 1.0)
	tool.confirm()
	facade.advance(1)
	tool.on_events(facade.events_since(0))
	var layer: CanvasLayer = auto_free(CanvasLayer.new())
	add_child(layer)
	var hud := HudRoot.new()
	hud.set_anchors_preset(Control.PRESET_TOP_LEFT)
	layer.add_child(hud)
	hud.bind_input(InputProfile.create(profile))
	if profile == &"touch":
		hud.simulated_safe = Vector4(0.0, 24.0, 0.0, 20.0)   # iPad üst durum çubuğu + alt ev çubuğu
	hud.setup(facade, UiTestSupport.platform(profile, {"max_game_speed": 4}))
	hud.size = viewport
	var panel_ref: Array = [null]
	hud.open_panel(&"road_draw", &"road.title", func(c: UiContext) -> Control:
		var p := RoadDrawPanel.create(c, facade, tool)
		panel_ref[0] = p
		return p)
	hud.refresh()
	var rows: Array[SimEvent] = []
	for i in 5:   # dolu şerit: oyuncu eylemi ağırlıklı, uzun metinli satırlar
		var r := SimEvent.new()
		r.kind = SimEvent.KIND_PUBLIC_WORK_BUILT
		r.command_id = 900 + i
		r.message_key = &"event.road.built"
		r.args = {"length_m": 134 + i, "units_total": 13}
		r.seq = 100 + i
		rows.append(r)
	hud.strip.push_events(rows)
	var path := "user://test_hud_float_layout_%d.cfg" % Time.get_ticks_usec()
	var hint := PlayableTempo.attach(hud, facade, PlayableHintPrefs.create(path))
	var built := SimEvent.new()
	built.kind = SimEvent.KIND_PUBLIC_WORK_BUILT
	var evs: Array[SimEvent] = [built]
	hud.events_received.emit(evs)
	var tip: RoadCursorTip = null
	if with_tip:
		tip = RoadCursorTip.create()
		layer.add_child(tip)
		tip.theme = hud.theme
		tip.follow_hud(hud)
		tip.show_text(UiText.t(&"road.tip_valid", {"length": 134, "units": 13, "cost": "0"}), true,
				UiText.t(&"road.tip.step1_touch" if profile == &"touch" else &"road.tip.step1"))
		if profile == &"touch":
			tip.place_at_top(hud.free_map_rect(), hud.occupied_rects())
		else:
			tip.place_near(Vector2(60.0, 130.0), viewport, hud.free_map_rect(), hud.occupied_rects())
	if confirm:
		var p: RoadDrawPanel = panel_ref[0]
		p.demolish_button().pressed.emit()
	for i in 12:
		await get_tree().process_frame
	return {"hud": hud, "hint": hint, "tip": tip, "panel": panel_ref[0], "viewport": viewport}


func _rects(s: Dictionary) -> Dictionary:
	var hud: HudRoot = s["hud"]
	var out := {}
	out["top_bar"] = hud.top_bar.get_global_rect()
	out["toolbar"] = hud.toolbar.get_global_rect()
	if hud.is_panel_open():
		out["panel"] = hud.panel.get_global_rect()
	var k := 0
	for c in hud.strip.get_children():
		var ctrl := c as Control
		if ctrl != null and ctrl.visible and ctrl.size.y > 0.0:
			out["strip_row_%d" % k] = ctrl.get_global_rect()
			k += 1
	var hint: PlayableSpeedHint = s["hint"]
	if hint.visible:
		out["speed_hint"] = hint.get_global_rect()
	var tip: RoadCursorTip = s["tip"]
	if tip != null and tip.visible:
		out["road_tip"] = tip.get_global_rect()
	return out


func _check_rects(s: Dictionary, tag: String) -> void:
	var rects := _rects(s)
	var screen := Rect2(Vector2.ZERO, s["viewport"])
	var names: Array = rects.keys()
	for n: String in names:
		var r: Rect2 = rects[n]
		assert_bool(screen.grow(0.5).encloses(r)).override_failure_message(
				"%s: %s ekran dışında %s" % [tag, n, r]).is_true()
	for i in names.size():
		for j in range(i + 1, names.size()):
			var a: Rect2 = rects[names[i]]
			var b: Rect2 = rects[names[j]]
			assert_bool(a.intersects(b)).override_failure_message(
					"%s: %s %s ile %s %s kesişiyor" % [tag, names[i], a, names[j], b]).is_false()


func _check_touch(s: Dictionary, tag: String) -> void:
	var hud: HudRoot = s["hud"]
	var buttons: Array[Button] = UiTestSupport.visible_buttons(hud)
	for b in buttons:
		var hit := UiFactory.hit_size(b)
		assert_bool(hit.x >= MIN_TARGET and hit.y >= MIN_TARGET).override_failure_message(
				"%s: düğme '%s' hedefi %s < 44" % [tag, b.text, hit]).is_true()


func _check_confirm_visible(s: Dictionary, tag: String) -> void:
	var p: RoadDrawPanel = s["panel"]
	var hud: HudRoot = s["hud"]
	var yes := p.demolish_confirm_button()
	var keep := p.demolish_keep_button()
	assert_object(yes).override_failure_message(tag + ": onay düğmesi yok").is_not_null()
	var view: Rect2 = hud.panel.scroll_view_rect()
	var screen := Rect2(Vector2.ZERO, s["viewport"])
	for b: Button in [yes, keep]:
		var r := b.get_global_rect()
		assert_bool(view.grow(0.5).encloses(r)).override_failure_message(
				"%s: '%s' %s kaydırmadan görünmüyor (görünür alan %s)" % [tag, b.text, r, view]).is_true()
		assert_bool(screen.grow(0.5).encloses(r)).override_failure_message(
				"%s: '%s' ekran dışında %s" % [tag, b.text, r]).is_true()


## 3B karede bulundu (800x600 dokunmatik): uzun planlama ipucu "Yolu yık" düğmesini kaydırma çizgisinin altına itiyordu.
## Yönetim fiili (yol çizilmiş, yeni çizim bekleniyor) panel kaydırılmadan görünür olmalı (yatay + dikey dokunmatik).
func test_demolish_verb_visible_without_scrolling_when_plan_hint_is_shown() -> void:
	for c: Array in CASES:
		if c[0] != &"touch":
			continue
		var tag := "yık düğmesi %s" % c[1]
		var s: Dictionary = await _scene(c[0], c[1], true, false)
		var p: RoadDrawPanel = s["panel"]
		var hud: HudRoot = s["hud"]
		var btn := p.demolish_button()
		assert_object(btn).override_failure_message(tag + ": 'Yolu yık' düğmesi yok").is_not_null()
		var view: Rect2 = hud.panel.scroll_view_rect()
		var r := btn.get_global_rect()
		assert_bool(view.grow(0.5).encloses(r)).override_failure_message(
				"%s: %s kaydırmadan görünmüyor (görünür alan %s)" % [tag, r, view]).is_true()


func test_no_overlap_nothing_offscreen_with_strip_hint_and_tip() -> void:
	for c: Array in CASES:
		var tag := "%s %s" % [c[0], c[1]]
		var s: Dictionary = await _scene(c[0], c[1], true, false)
		assert_bool(s["hud"].strip.row_count() >= 3).override_failure_message(tag + ": şerit dolu değil").is_true()
		assert_bool(s["hint"].visible).override_failure_message(tag + ": hız ipucu yok").is_true()
		_check_rects(s, tag)


func test_no_overlap_with_demolish_confirm_open() -> void:
	for c: Array in CASES:
		var tag := "onay %s %s" % [c[0], c[1]]
		var s: Dictionary = await _scene(c[0], c[1], true, true)
		_check_rects(s, tag)
		# Dikey dokunmatik alt sayfada da (196 px görünür alan) "Evet, yık / Vazgeç" kaydırmadan görünür (B-019 açık not).
		if s["hud"].layout.panel_mode == HudLayout.MODE_SIDE or s["hud"].layout.panel_mode == HudLayout.MODE_SHEET:
			_check_confirm_visible(s, tag)


func test_touch_targets_44_and_gaps_8() -> void:
	for c: Array in CASES:
		if c[0] != &"touch":
			continue
		var tag := "dokunmatik %s" % c[1]
		var s: Dictionary = await _scene(c[0], c[1], true, true)
		_check_touch(s, tag)
		var gap := TouchAudit.min_button_gap(s["hud"])
		assert_bool(gap >= MIN_GAP).override_failure_message("%s: düğme aralığı %.1f < 8" % [tag, gap]).is_true()


func test_strip_never_overlaps_toolbar_even_when_overfull() -> void:
	for c: Array in CASES:
		var tag := "şerit %s %s" % [c[0], c[1]]
		var s: Dictionary = await _scene(c[0], c[1], false, false)
		var hud: HudRoot = s["hud"]
		var strip := Rect2(hud.strip.global_position, hud.strip.size)
		assert_bool(strip.end.y <= hud.toolbar.global_position.y).override_failure_message(
				"%s: şerit %s araç çubuğunu %s örtüyor" % [tag, strip, hud.toolbar.get_global_rect()]).is_true()
		var avail_w := hud.layout.map_region.size.x - 2.0 * hud.ctx.edge_margin() - 1.0
		assert_bool(strip.size.x >= hud.ctx.px(240.0) - 0.5 or strip.size.x >= avail_w) \
			.override_failure_message("%s: şerit genişliği %.0f" % [tag, strip.size.x]).is_true()
		for child in hud.strip.get_children():
			var row := child as Control
			if row != null and row.visible:
				assert_bool(row.size.y <= 130.0).override_failure_message(
						"%s: şerit satırı %.0f px yüksek (harf harf sarma)" % [tag, row.size.y]).is_true()


## 3B karede bulundu (800x600): şerit yüksekliği dar olunca üstteki düğmesiz "Komut uygulandı" satırı, altındaki
## "Nedenini gör" düğmeli satırı gizliyordu. Gerekçe düğmeli satır korunur (SIM-12), düğmesizler önce gizlenir.
func test_strip_height_cap_keeps_the_row_with_the_reason_button() -> void:
	var strip := NotificationStrip.create(UiContext.for_profile_name(&"touch"))
	add_child(strip)
	auto_free(strip)
	var why_row := SimEvent.new()
	why_row.kind = SimEvent.KIND_PUBLIC_WORK_BUILT
	why_row.command_id = 11
	why_row.message_key = &"event.road.built"
	why_row.args = {"length_m": 134, "units_total": 13}
	why_row.seq = 1
	var plain := SimEvent.new()
	plain.kind = &"command.applied"
	plain.command_id = 12
	plain.message_key = &"event.command.applied"
	plain.seq = 2
	strip.push_events([why_row, plain] as Array[SimEvent])
	await get_tree().process_frame
	var heights: Array[float] = []
	for c in strip.get_children():
		heights.append((c as Control).get_combined_minimum_size().y)
	assert_int(heights.size()).is_equal(2)
	strip.set_max_height(maxf(heights[0], heights[1]) + 1.0)   # yalnız bir satır sığar
	var shown := 0
	var why_visible := false
	for c in strip.get_children():
		var row := c as Control
		if row.visible:
			shown += 1
			why_visible = why_visible or NotificationStrip._has_reason_button(row)
	assert_int(shown).is_equal(1)
	assert_bool(why_visible).override_failure_message("yalnız bir satır sığarken gerekçe düğmeli satır gizlendi").is_true()
