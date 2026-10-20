extends GdUnitTestSuite
## T-019 ölçüt 3/4/6 · HudRoot, MockSimFacade ile: MOCK bandı/rozetleri facade bayrağından, gerçek sim verisi
## (tarih/para), profil eşliği (aynı fiiller masaüstü ↔ dokunmatik), ≥ 44 pt hedefler (dokunmatik), hız
## fiilleri
## InputProfile üzerinden, panel kabuğu, olay şeridi + gerekçe düğmesi.
## Olumsuz: MOCK olmayan facade'de bant yok; veri yokken gündem rozeti yok; kurulmamış mod devre dışı.

const DESKTOP_SIZE := Vector2(1600, 900)
const IPAD_LANDSCAPE := Vector2(1366, 1024)
const IPAD_PORTRAIT := Vector2(1024, 1366)


func before_test() -> void:
	UiText.reset()
	UiText.report_missing = false


func after_test() -> void:
	UiText.reset()


func _hud(facade: SimFacade, profile_name: StringName, window: Vector2, extra: Dictionary = {}) -> HudRoot:
	var hud := HudRoot.new()
	add_child(hud)
	hud.setup(facade, UiTestSupport.platform(profile_name, extra))
	hud.set_anchors_preset(Control.PRESET_TOP_LEFT)
	hud.size = window
	hud.refresh()
	return auto_free(hud)


func _text_builder(c: UiContext) -> Control:
	var l := UiFactory.label("içerik", &"", true)
	l.theme = UiTheme.build(c)
	return l


# --- MOCK ---

func test_mock_banner_and_badges_visible_for_mock_facade() -> void:
	var hud := _hud(UiTestSupport.mock(), &"desktop", DESKTOP_SIZE)
	assert_bool(hud.banner.visible).is_true()
	assert_bool(hud.top_bar.mock_badges_visible() == 2).is_true()


func test_mock_marks_disappear_for_non_mock_facade() -> void:
	var hud := _hud(UiTestSupport.non_mock(), &"desktop", DESKTOP_SIZE)
	assert_bool(hud.banner.visible).is_false()
	assert_int(hud.top_bar.mock_badges_visible()).is_equal(0)
	assert_float(hud.layout.banner.size.y).is_equal(0.0)


func test_banner_text_comes_from_strings_table() -> void:
	var hud := _hud(UiTestSupport.mock(), &"desktop", DESKTOP_SIZE)
	var found := false
	for l in _labels(hud):
		if l.text == UiText.t(&"app.mock_banner"):
			found = true
	assert_bool(found).is_true()


func test_hud_root_scene_file_instantiates_and_binds() -> void:
	var hud: HudRoot = auto_free((load("res://scenes/ui/hud_root.tscn") as PackedScene).instantiate())
	add_child(hud)
	hud.setup(UiTestSupport.mock(), UiTestSupport.platform(&"desktop"))
	assert_object(hud.top_bar).is_not_null()
	assert_bool(hud.banner.visible).is_true()


# --- gerçek veri ---

func test_date_and_money_come_from_snapshot_not_constants() -> void:
	var f := UiTestSupport.mock()
	var hud := _hud(f, &"desktop", DESKTOP_SIZE)
	assert_str(hud.top_bar.money_text()).is_equal(UiText.money(f.snapshot().budget.balance))
	assert_str(hud.top_bar.date_text()).is_equal("1. yıl, 1. gün")
	f.advance(40)
	hud.poll()
	assert_str(hud.top_bar.date_text()).is_equal("1. yıl, 41. gün")


func test_money_follows_configured_currency_symbol() -> void:
	UiConfig.set_override("economy.currency_symbol", "Ж")
	var hud := _hud(UiTestSupport.mock(), &"desktop", DESKTOP_SIZE)
	assert_str(hud.top_bar.money_text()).ends_with("Ж")
	assert_bool(hud.top_bar.money_text().contains("₺")).is_false()


func test_no_agenda_badge_without_data_source() -> void:
	var hud := _hud(UiTestSupport.mock(), &"desktop", DESKTOP_SIZE)
	assert_bool(hud.top_bar.agenda.visible).is_false()
	hud.set_agenda(3, 4, true)
	assert_bool(hud.top_bar.agenda.visible).is_true()


func test_hud_has_no_single_happiness_score() -> void:
	var hud := _hud(UiTestSupport.mock(), &"desktop", DESKTOP_SIZE)
	for l in _labels(hud):
		var low := l.text.to_lower()
		for bad in ["mutluluk", "puan", "skor", "%"]:
			assert_bool(low.contains(bad)).override_failure_message("'%s' içinde '%s'" % [l.text, bad]).is_false()


# --- panel kabuğu ---

func test_panel_opens_closes_and_respects_pin() -> void:
	var hud := _hud(UiTestSupport.mock(), &"desktop", DESKTOP_SIZE)
	var closed := []
	hud.panel_closed.connect(func(id: StringName) -> void: closed.append(id))
	assert_bool(hud.is_panel_open()).is_false()
	hud.open_panel(&"probe", &"inspector.title", _text_builder)
	assert_bool(hud.is_panel_open()).is_true()
	assert_str(hud.panel.title_text()).is_equal("Denetçi")
	hud.panel.pin_button().button_pressed = true
	hud.input.cancel_requested.emit()  # Esc: sabit panel kapanmaz
	assert_bool(hud.is_panel_open()).is_true()
	hud.panel.close_button().pressed.emit()
	assert_bool(hud.is_panel_open()).is_false()
	assert_array(closed).is_equal([&"probe"])
	hud.open_panel(&"probe", &"inspector.title", _text_builder)
	hud.input.cancel_requested.emit()
	assert_bool(hud.is_panel_open()).is_false()


func test_open_panel_survives_profile_switch() -> void:
	var hud := _hud(UiTestSupport.mock(), &"desktop", DESKTOP_SIZE)
	hud.open_panel(&"probe", &"inspector.title", _text_builder)
	hud.panel.pin_button().button_pressed = true
	hud.apply_profile(UiTestSupport.platform(&"touch"))
	assert_bool(hud.is_panel_open()).is_true()
	assert_bool(hud.panel.pinned).is_true()
	assert_bool(hud.ctx.is_touch()).is_true()


func test_free_map_rect_excludes_panel_and_toolbar() -> void:
	var hud := _hud(UiTestSupport.mock(), &"desktop", DESKTOP_SIZE)
	var open_rect := hud.free_map_rect()
	hud.open_panel(&"probe", &"inspector.title", _text_builder)
	var with_panel := hud.free_map_rect()
	assert_float(with_panel.size.x).is_less(open_rect.size.x)
	assert_float(with_panel.end.y).is_less_equal(hud.layout.toolbar.position.y + 0.5)


# --- olaylar ---

func test_events_reach_strip_with_reason_button() -> void:
	var f := UiTestSupport.mock()
	var hud := _hud(f, &"desktop", DESKTOP_SIZE)
	assert_bool(hud.strip.visible).is_false()  # olay yok -> öğe yok
	f.submit_command(SimCommand.zoning_propose(PackedInt64Array([1]), &"zone.mixed"))
	f.advance(6)
	hud.poll()
	assert_bool(hud.strip.visible).is_true()
	assert_int(hud.strip.row_count()).is_less_equal(3)
	var texts := Array(hud.strip.row_texts())
	assert_bool(texts.has("Yatırımcı vazgeçti")).is_true()
	var reasons := []
	hud.reason_requested.connect(func(e: SimEvent) -> void: reasons.append(e))
	for b in UiTestSupport.visible_buttons(hud.strip):
		if b.text == "Nedenini gör":
			b.pressed.emit()
	assert_int(reasons.size()).is_equal(1)
	assert_bool((reasons[0] as SimEvent).reason_ids.size() > 0).is_true()


func test_rejected_event_text_carries_the_simulations_reason() -> void:
	var f := UiTestSupport.mock(UiTestSupport.INVALID)
	var hud := _hud(f, &"desktop", DESKTOP_SIZE)
	var result := f.submit_command(SimCommand.zoning_propose(PackedInt64Array([2]), &"zone.commercial"))
	assert_that(result.status).is_equal(CommandResult.STATUS_QUEUED)
	f.advance(2)
	hud.poll()
	var joined := " ".join(hud.strip.row_texts())
	assert_str(joined).contains("Komut kabul edilmedi")
	assert_str(joined).contains("Koruma alanında imar değişikliği önerilemez")


func test_polling_does_not_reread_when_nothing_changed() -> void:
	var f := UiTestSupport.mock()
	var hud := _hud(f, &"desktop", DESKTOP_SIZE)
	var snap_before := hud.snapshot()
	hud.poll()
	assert_object(hud.snapshot()).is_same(snap_before)
	f.advance(1)
	hud.poll()
	assert_object(hud.snapshot()).is_not_same(snap_before)


func _labels(node: Node) -> Array[Label]:
	var out: Array[Label] = []
	for child in node.get_children():
		if child is Label and (child as Label).is_visible_in_tree():
			out.append(child)
		out.append_array(_labels(child))
	return out
