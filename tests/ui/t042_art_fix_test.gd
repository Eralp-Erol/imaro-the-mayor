extends GdUnitTestSuite
## T-042 sanat düzeltmesi (UI payı) · panel metinleri düz Türkçe ve tekrarsız, yer tutucu "0 ¤" yok, karar ana vurgu,
## yan panel içeriğe uyar, bildirim parsel adı taşır, araç çubuğunda tek vurgulu mod. Ret/gerekçe MANTIĞI değişmez.

const P := preload("res://tests/sim/public_works/public_works_support.gd")
const DESKTOP_SIZE := Vector2(1600, 900)


func before_test() -> void:
	UiText.reset()
	UiText.report_missing = false


func after_test() -> void:
	UiText.reset()


func _row(key: StringName, value: int, delta: int, delta_valid: bool) -> M2ResultModel.MetricRow:
	var r := M2ResultModel.MetricRow.new()
	r.key = key
	r.value = value
	r.delta = delta
	r.delta_valid = delta_valid
	return r


func test_cost_line_does_not_repeat_the_word_cost() -> void:
	var line := UiText.t(&"road.cost_line", {"cost": UiText.t(&"public_work.cost.not_built")})
	assert_str(line).is_equal("Maliyet: henüz kurulmadı")
	assert_int(line.to_lower().count("maliyet")).is_equal(1)


func test_band_subtitles_are_plain_turkish_without_scale_jargon() -> void:
	for band in ["street", "neighborhood", "district"]:
		var text := UiText.t(StringName("inspector.band.%s" % band), {"code": "D1"})
		assert_str(text).contains("D1")
		assert_str(text.to_lower()).not_contains("ölçeği")
		assert_str(text.to_lower()).not_contains("ayrıntısı")


func test_rent_income_without_income_shows_no_placeholder_currency_but_real_income_does() -> void:
	assert_str(M2ResultPanel.rent_text(_row(&"rent_income", 0, 0, true))).is_equal("Henüz yok")
	assert_str(M2ResultPanel.rent_text(_row(&"rent_income", 0, 0, false))).is_equal("Henüz yok")
	assert_str(M2ResultPanel.rent_text(_row(&"rent_income", 1200, 0, false))).contains("1.200")
	assert_str(M2ResultPanel.rent_text(_row(&"rent_income", 1200, 300, true))).contains("300")
	# gerçek tutarda simge yapılandırmadan gelir
	assert_str(M2ResultPanel.rent_text(_row(&"rent_income", 1200, 0, false))).contains("¤")


func test_municipal_not_built_reason_does_not_repeat_the_not_built_label() -> void:
	var reason := UiText.t(&"economy.municipal_revenue.not_built")
	assert_str(reason.to_lower()).not_contains("henüz kurulmadı")
	assert_str(UiText.t(&"state.not_built_short")).is_equal("Henüz kurulmadı")


func test_strip_text_adds_the_parcel_but_leaves_parcel_less_events_unchanged() -> void:
	var e := SimEvent.new()
	e.kind = SimEvent.KIND_ACTOR_DECIDED
	e.message_key = &"event.investor.develop"
	e.subjects = PackedStringArray(["parcel.18437"])
	assert_str(NotificationStrip.strip_text(e)).is_equal("Yatırımcı yatırım yaptı · Parsel 18437")
	var f := SimEvent.new()
	f.kind = SimEvent.KIND_ACTOR_DECIDED
	f.message_key = &"event.investor.develop"
	f.subjects = PackedStringArray(["region.D1"])
	assert_str(NotificationStrip.strip_text(f)).is_equal(UiText.event_text(f))
	# aynı metin farklı parsellerde ayırt edilir
	var g := SimEvent.new()
	g.kind = SimEvent.KIND_ACTOR_DECIDED
	g.message_key = &"event.investor.develop"
	g.subjects = PackedStringArray(["parcel.2"])
	assert_str(NotificationStrip.strip_text(g)).is_not_equal(NotificationStrip.strip_text(e))


func test_toolbar_highlights_only_the_active_tool_not_its_mode() -> void:
	var ctx := UiContext.for_profile_name(&"desktop")
	var tb := ModeToolbar.create(ctx)
	tb.theme = UiTheme.build(ctx)
	add_child(tb)
	auto_free(tb)
	tb.add_tool(ModeToolbar.MODE_PLAN, ModeToolbar.TOOL_ZONE)
	tb.add_tool(ModeToolbar.MODE_BUILD, ModeToolbar.TOOL_ROAD_DRAW)
	tb.select_mode(ModeToolbar.MODE_BUILD)
	assert_bool(tb.mode_button(ModeToolbar.MODE_BUILD).button_pressed).is_true()   # araç yok: mod vurgulu
	tb.set_active_tool(ModeToolbar.TOOL_ROAD_DRAW)
	assert_bool(tb.tool_button(ModeToolbar.TOOL_ROAD_DRAW).button_pressed).is_true()
	for mode_id: StringName in [ModeToolbar.MODE_BUILD, ModeToolbar.MODE_PLAN]:
		assert_bool(tb.mode_button(mode_id).button_pressed).override_failure_message(String(mode_id)).is_false()
	tb.clear_active_tool()
	assert_bool(tb.mode_button(ModeToolbar.MODE_BUILD).button_pressed).is_true()


func test_valid_road_card_leads_with_the_verdict_and_has_no_duplicate_region_or_cost_text() -> void:
	var run := P.setup()
	var tool := RoadDrawTool.create(run["net"], run["facade"])
	tool.activate()
	tool.tap_at(P.GRID_ORIGIN, 5.0)
	tool.tap_at(Vector2(1100.0, 1000.0), 1.0)
	assert_bool(tool.is_valid()).is_true()
	var ctx := UiContext.for_profile_name(&"desktop")
	var holder := Control.new()
	holder.theme = UiTheme.build(ctx)
	holder.size = Vector2(440.0, 1400.0)
	add_child(holder)
	auto_free(holder)
	var panel := RoadDrawPanel.create(ctx, run["facade"], tool)
	holder.add_child(panel)
	panel.size = holder.size
	var text := panel.joined_text()
	assert_str(text).contains("Bu yol yapılabilir")
	assert_str(text).contains("Maliyet: henüz kurulmadı")
	assert_str(text).not_contains("Maliyet: Maliyet")
	var args := tool.preview_args()
	var regions: Dictionary = args.get("regions", {})
	if regions.size() <= 1:
		for code: String in regions:
			assert_str(text).not_contains(UiText.t(&"road.capacity_region", {"region": code, "units": int(regions[code])}))
	# ana vurgu karar: başlık boyutunda ve ok renginde; kapasite sayısı ondan KÜÇÜK
	var verdict: Label = null
	var capacity: Label = null
	for node in panel.find_children("*", "Label", true, false):
		var l := node as Label
		if l.text == UiText.t(&"road.valid"):
			verdict = l
		elif l.text.begins_with(UiText.t(&"road.capacity", {"units": 0}).substr(0, 10)):
			capacity = l
	assert_object(verdict).is_not_null()
	assert_object(capacity).is_not_null()
	assert_int(verdict.get_theme_font_size("font_size")).is_greater(capacity.get_theme_font_size("font_size"))


func test_side_panel_height_fits_its_content_instead_of_filling_the_screen() -> void:
	var hud := HudRoot.new()
	add_child(hud)
	hud.setup(UiTestSupport.mock(), UiTestSupport.platform(&"desktop", {}))
	hud.set_anchors_preset(Control.PRESET_TOP_LEFT)
	hud.size = DESKTOP_SIZE
	auto_free(hud)
	hud.open_panel(&"probe", &"inspector.title", func(c: UiContext) -> Control:
		var l := UiFactory.label("kısa içerik", &"", true)
		l.theme = UiTheme.build(c)
		return l)
	hud.refresh()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_float(hud.panel.size.y).is_less(hud.layout.panel.size.y * 0.5)
	assert_float(hud.panel.size.y).is_greater_equal(hud.panel.content_height() - 1.0)
	# uzun içerik tavanı (ekran yüksekliği) aşmaz: kaydırılır
	hud.open_panel(&"probe2", &"inspector.title", func(c: UiContext) -> Control:
		var box := VBoxContainer.new()
		box.theme = UiTheme.build(c)
		for i in 80:
			box.add_child(UiFactory.label("satır %d" % i, &"", true))
		return box)
	hud.refresh()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_float(hud.panel.size.y).is_less_equal(hud.layout.panel.size.y + 0.5)
	assert_float(hud.panel.size.y).is_greater(hud.layout.panel.size.y * 0.9)
