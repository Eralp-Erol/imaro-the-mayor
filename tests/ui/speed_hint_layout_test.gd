extends GdUnitTestSuite
## Hız ipucu kartı yerleşimi (iPad 1024x768 hatası): "Zamanı hızlandırarak sonucu izle" dikey harflere sıkışıyordu ve
## bildirim sütunuyla çakışıyordu. Ölçüt: etiket okunur genişlikte sarılır (en çok 3 satır), kart asgari genişliğin
## altına inmez, bildirim sütunu/şeridi, açık panel ve araç çubuğuyla çakışmaz, harita dikdörtgeninde kalır, dokunmatik
## hedef >= 44 pt ve düğme aralığı >= 8 pt. Desktop 1600x900, iPad 1024x768, dar 800x600.

const CASES := [
	[&"desktop", Vector2(1600.0, 900.0)],
	[&"touch", Vector2(1024.0, 768.0)],
	[&"touch", Vector2(800.0, 600.0)],
	[&"desktop", Vector2(800.0, 600.0)],
	[&"touch", Vector2(640.0, 480.0)],  # bildirim sütununun sağında yer kalmaz: kart şeridin altına iner
]


func before_test() -> void:
	UiText.reset()
	UiText.report_missing = false


func after_test() -> void:
	UiText.reset()


func _body(c: UiContext) -> Control:
	var l := UiFactory.label("içerik", &"", true)
	l.theme = UiTheme.build(c)
	return l


func _scene(profile: StringName, viewport: Vector2, panel_open: bool) -> Dictionary:
	var f := M2RenderSupport.handle(M2RenderSupport.ISOLATE).facade
	var layer: CanvasLayer = auto_free(CanvasLayer.new())
	add_child(layer)
	var hud := HudRoot.new()
	hud.set_anchors_preset(Control.PRESET_TOP_LEFT)
	layer.add_child(hud)
	hud.bind_input(InputProfile.create(profile))
	hud.setup(f, UiTestSupport.platform(profile, {"max_game_speed": 4}))
	hud.size = viewport
	hud.refresh()
	if panel_open:
		hud.open_panel(&"probe", &"inspector.title", _body)
	var rows: Array[SimEvent] = []
	for i in 4:  # dolu bildirim şeridi: çakışma ölçüsü gerçek şerit yüksekliğine karşı alınır
		var r := SimEvent.new()
		r.kind = SimEvent.KIND_PARCEL_CHANGED
		r.message_key = &"event.zoning.applied"
		r.seq = 100 + i
		rows.append(r)
	hud.strip.push_events(rows)
	var path := "user://test_speed_hint_layout_%d.cfg" % Time.get_ticks_usec()
	var hint := PlayableTempo.attach(hud, f, PlayableHintPrefs.create(path))
	var e := SimEvent.new()
	e.kind = SimEvent.KIND_PUBLIC_WORK_BUILT
	var events: Array[SimEvent] = [e]
	hud.events_received.emit(events)
	await get_tree().process_frame  # sarmalı etiketin asgari yüksekliği genişlik bilinince bir kare sonra oturur
	await get_tree().process_frame
	return {"hud": hud, "hint": hint}


func _check(profile: StringName, viewport: Vector2, panel_open: bool) -> void:
	var s: Dictionary = await _scene(profile, viewport, panel_open)
	var hud: HudRoot = s["hud"]
	var hint: PlayableSpeedHint = s["hint"]
	var tag := "%s %s panel=%s" % [profile, viewport, panel_open]
	assert_bool(hint.visible).override_failure_message("ipucu görünmüyor: " + tag).is_true()
	var rect := Rect2(hint.position, hint.size)
	assert_bool(hud.free_map_rect().encloses(rect)).override_failure_message("harita dışına taşıyor " + tag).is_true()
	var label := hint.hint_label()
	var lines := label.get_line_count()
	assert_bool(lines <= 3).override_failure_message("etiket %d satıra sarıldı: %s" % [lines, tag]).is_true()
	assert_bool(label.size.x >= PlayableSpeedHint.MIN_WIDTH * 0.6).override_failure_message(
			"etiket genişliği %.0f: %s" % [label.size.x, tag]).is_true()
	assert_bool(rect.size.x >= PlayableSpeedHint.MIN_WIDTH).override_failure_message("kart dar: " + tag).is_true()
	var strip := Rect2(hud.strip.position, hud.strip.size)
	assert_bool(hud.strip.row_count() > 0 and strip.size.y > 0.0).override_failure_message(
			"şerit boş, çakışma ölçülemez: " + tag).is_true()
	assert_bool(rect.intersects(strip)).override_failure_message("bildirim şeridiyle çakışıyor " + tag).is_false()
	if panel_open:
		assert_bool(rect.intersects(hud.layout.panel)).override_failure_message("panelle çakışıyor " + tag).is_false()
	assert_bool(rect.intersects(hud.layout.toolbar)).override_failure_message("araç çubuğuyla çakışıyor " + tag).is_false()
	var faster := hint.faster_button()
	var close := hint.close_button()
	var min_target := 44.0 if profile == &"touch" else 0.0
	for b: Button in [faster, close]:
		var sz := UiFactory.hit_size(b)
		assert_bool(sz.x >= min_target and sz.y >= min_target).override_failure_message("hedef küçük " + tag).is_true()
		assert_bool(b.get_global_rect().end.x <= hint.get_global_rect().end.x + 0.5).override_failure_message(
				"düğme kart dışında " + tag).is_true()
	assert_bool(faster.get_global_rect().intersects(close.get_global_rect())).is_false()
	if profile == &"touch":
		var gap := close.get_global_rect().position.x - faster.get_global_rect().end.x
		assert_bool(gap >= 8.0).override_failure_message("düğme aralığı %.1f: %s" % [gap, tag]).is_true()


func test_hint_is_readable_and_clear_of_other_hud_with_panel_open() -> void:
	for c in CASES:
		await _check(c[0], c[1], true)


func test_hint_is_readable_with_panel_closed() -> void:
	for c in CASES:
		await _check(c[0], c[1], false)
