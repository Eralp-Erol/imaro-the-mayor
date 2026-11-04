extends GdUnitTestSuite
## T-047 ölçüt 2/3/6 · Dürüst arayüz: araç çubuğunda yalnız kayıtlı (çalışan) araçlar; her görünür düğme
## gerçek sonuç verir; alt yardım metni sade (--dev-notes ile geliştirici satırları); panel kapat/aç/yenile döngüsü
## SCRIPT ERROR vermez; yapılı parsel uyarısı panelde görünür (gönderimden önce).

const DESKTOP := Vector2(1600, 900)
const NARROW := Vector2(480, 800)


func before_test() -> void:
	UiText.reset()
	UiText.report_missing = false


func after_test() -> void:
	UiText.reset()


func _hud(facade: SimFacade, window: Vector2 = DESKTOP, profile: StringName = &"desktop") -> HudRoot:
	var hud := HudRoot.new()
	add_child(hud)
	hud.setup(facade, UiTestSupport.platform(profile))
	hud.set_anchors_preset(Control.PRESET_TOP_LEFT)
	hud.size = window
	hud.refresh()
	return auto_free(hud)


func _playable_like(facade: SimFacade, probe: Callable = Callable()) -> Dictionary:
	var hud := _hud(facade)
	var decisions := DecisionPanels.attach(hud, facade, probe, false)
	var results := M2Results.attach(hud, facade, decisions)
	return {"hud": hud, "decisions": decisions, "results": results}


func test_playable_toolbar_shows_only_working_tools_and_no_mode_buttons() -> void:
	var s := _playable_like(FlowTestSupport.real_economy(3))
	var tb: ModeToolbar = (s["hud"] as HudRoot).toolbar
	var texts := PackedStringArray()
	for b in tb.all_buttons():
		texts.append(b.text)
	assert_array(Array(texts)).is_equal([UiText.t(&"tool.zone"), UiText.t(&"tool.results")])
	for hidden in ["İnşa", "Yönetim", "Denetçi", "Bütçe", "Meclis", "Gündem", "Henüz kurulmadı"]:
		for t in texts:
			assert_bool(t.contains(hidden)).override_failure_message("'%s' görünmemeli" % hidden).is_false()
	assert_object(tb.mode_button(ModeToolbar.MODE_BUILD)).is_not_null()
	assert_bool(tb.mode_button(ModeToolbar.MODE_BUILD).visible).is_false()


func test_every_visible_toolbar_button_gives_a_real_result() -> void:
	var s := _playable_like(FlowTestSupport.real_economy(3))
	var hud: HudRoot = s["hud"]
	for b in hud.toolbar.all_buttons():
		hud.close_panel_hard()
		b.pressed.emit()
		assert_bool(hud.is_panel_open()).override_failure_message("'%s' panel açmadı" % b.text).is_true()
		assert_str(hud.panel.title_text()).is_not_equal("")


func test_zone_tool_opens_the_zoning_flow_asking_for_a_parcel() -> void:
	var s := _playable_like(FlowTestSupport.real_economy(3))
	var hud: HudRoot = s["hud"]
	hud.toolbar.tool_button(ModeToolbar.TOOL_ZONE).pressed.emit()
	assert_that(hud.panel_id()).is_equal(DecisionPanels.PANEL_ZONING)
	var panel := (s["decisions"] as DecisionPanels).zoning_panel()
	assert_object(panel).is_not_null()
	assert_that(panel.model.phase()).is_equal(ZoningFlowModel.Phase.PICK_AREA)


func test_structure_warning_is_visible_in_the_panel_before_sending() -> void:
	var facade := FlowTestSupport.real_economy(3)
	var s := _playable_like(facade, func(pid: int) -> bool: return pid == 1)
	var d: DecisionPanels = s["decisions"]
	d.open_zoning(PackedInt64Array([1]))
	d.zoning_panel().choose_use(&"zone.green")
	assert_str(d.zoning_panel().warning_text()).contains("mevcut yapıyı KALDIRMAZ")
	assert_str(d.zoning_panel().note_text()).contains("özel yatırım yapılmaz")
	d.open_zoning(PackedInt64Array([2]))  # yapısız parsel: uyarı yok
	d.zoning_panel().choose_use(&"zone.residential")
	assert_str(d.zoning_panel().warning_text()).is_equal("")


func test_panel_close_open_refresh_and_profile_cycle_keeps_working() -> void:
	var facade := FlowTestSupport.real_economy(3)
	var s := _playable_like(facade, func(pid: int) -> bool: return pid == 1)
	var hud: HudRoot = s["hud"]
	var d: DecisionPanels = s["decisions"]
	for round_i in 3:
		d.open_zoning(PackedInt64Array([1]))
		d.zoning_panel().choose_use(&"zone.green")
		hud.refresh()
		hud.apply_profile(UiTestSupport.platform(&"touch" if round_i % 2 == 0 else &"desktop"))
		assert_object(d.zoning_panel()).is_not_null()
		assert_str(d.zoning_panel().warning_text()).contains("KALDIRMAZ")
		hud.close_panel_hard()
		assert_object(d.zoning_panel()).is_null()
		s["results"].open()
		hud.close_panel_hard()
	assert_bool(hud.is_panel_open()).is_false()


func test_status_text_is_short_help_plus_day_and_dev_notes_only_when_asked() -> void:
	var plain := HudHelp.status_text(12, false, "BuildingView T0 sim'e aktarıldı")
	for jargon in ["BuildingView", "T0", "sim'e aktarıldı", "olay"]:
		assert_bool(plain.contains(jargon)).override_failure_message("jargon: " + jargon).is_false()
	assert_str(plain).contains("WASD")
	assert_str(plain).contains("Boşluk")
	assert_str(plain).contains("Z: imar önerisi")
	assert_str(plain).contains("Gün 12")
	assert_int(plain.split("\n").size()).is_equal(2)
	var dev := HudHelp.status_text(12, true, "BuildingView T0 sim'e aktarıldı")
	assert_str(dev).contains("BuildingView")
	assert_str(dev).contains("Gün 12")


func test_status_rect_stays_inside_free_map_for_480_to_1600() -> void:
	for w: float in [480.0, 800.0, 1024.0, 1366.0, 1600.0]:
		var hud := _hud(FlowTestSupport.real_economy(3), Vector2(w, 900.0 if w > 800.0 else 800.0),
				&"desktop" if w >= 1366.0 else &"touch")
		hud.open_panel(&"probe", &"inspector.title", func(_c: UiContext) -> Control: return Label.new())
		await await_idle_frame()
		var free := hud.free_map_rect()
		var r := HudHelp.status_rect(free, 40.0)
		assert_bool(free.grow(0.5).encloses(r)).override_failure_message("w=%d free=%s r=%s" % [w, free, r]).is_true()
		assert_bool(r.intersects(hud.toolbar.get_global_rect())).is_false()
		if hud.is_panel_open():
			assert_bool(r.intersects(hud.panel.get_global_rect())).is_false()
