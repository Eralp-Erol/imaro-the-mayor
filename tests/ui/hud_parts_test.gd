extends GdUnitTestSuite
## T-019 ölçüt 3/6 · HUD parçaları: TimeControls (profil hız tavanı), ModeToolbar (kurulmamış mod dürüst
## etiketli,
## özel bina aracı yok), AgendaBadge (veri yoksa gizli), ParcelInspector (yalnız ParcelView alanları).
## Olumsuz varyantlar: veri yokken sahte öğe, kurulmamış moda geçiş, kayıtsız "Neden?".

var _ctx: UiContext


func before_test() -> void:
	UiText.reset()
	UiText.report_missing = false
	_ctx = UiContext.for_profile_name(&"desktop")


func after_test() -> void:
	UiText.reset()


func _themed(node: Control) -> Control:
	node.theme = UiTheme.build(_ctx)
	add_child(node)
	return auto_free(node)


# --- TimeControls ---

func test_time_controls_levels_are_intersection_with_profile_cap() -> void:
	var capped_ctx := UiContext.from_profile(UiTestSupport.platform(&"desktop", {"max_game_speed": 2}))
	var tc := TimeControls.create(capped_ctx)
	tc.theme = UiTheme.build(capped_ctx)
	add_child(tc)
	auto_free(tc)
	var clock := ClockView.new()
	clock.available_speeds = PackedInt32Array([0, 1, 2, 3])
	clock.speed = 1
	tc.update_from(clock)
	assert_array(Array(tc.shown_levels())).is_equal([1, 2])
	assert_object(tc.speed_button(3)).is_null()
	assert_bool(tc.speed_capped_hint_visible()).is_true()


func test_time_controls_pause_toggle_and_selected_state() -> void:
	var tc := TimeControls.create(_ctx)
	tc.theme = UiTheme.build(_ctx)
	add_child(tc)
	auto_free(tc)
	var chosen := []
	tc.speed_chosen.connect(func(level: int) -> void: chosen.append(level))
	var clock := ClockView.new()
	clock.available_speeds = PackedInt32Array([0, 1, 2, 3])
	clock.speed = 2
	tc.update_from(clock)
	assert_bool(tc.speed_button(2).button_pressed).is_true()
	assert_bool(tc.speed_button(1).button_pressed).is_false()
	assert_str(tc.status_label().text).is_equal("Hız 2×")
	tc.pause_button().pressed.emit()
	assert_array(chosen).is_equal([0])
	clock.speed = 0
	tc.update_from(clock)
	assert_str(tc.status_label().text).is_equal("Duraklatıldı")
	assert_str(tc.pause_button().text).is_equal("Sürdür")
	tc.pause_button().pressed.emit()
	assert_array(chosen).is_equal([0, 2])  # son çalışan basamağa döner


# --- ModeToolbar ---

func test_mode_toolbar_unbuilt_modes_are_disabled_and_honestly_labelled() -> void:
	var tb := _themed(ModeToolbar.create(_ctx)) as ModeToolbar
	# Yönetim modu T-022 ile kuruldu (bütçe/meclis/gündem panelleri); yalnız İnşa kurulmamıştır.
	for mode_id in [ModeToolbar.MODE_BUILD]:
		var b := tb.mode_button(mode_id)
		assert_bool(b.disabled).is_true()
		assert_str(b.text).contains("Henüz kurulmadı")
	assert_bool(tb.mode_button(ModeToolbar.MODE_PLAN).disabled).is_false()
	tb.select_mode(ModeToolbar.MODE_BUILD)
	assert_that(tb.current_mode).is_equal(ModeToolbar.MODE_PLAN)  # kurulmamış moda geçilmez


func test_mode_toolbar_has_no_private_building_tool_and_only_mayor_verbs() -> void:
	var tb := _themed(ModeToolbar.create(_ctx)) as ModeToolbar
	var forbidden := ["bina", "yerleştir", "mutluluk", "puan", "skor"]
	for b in tb.all_buttons():
		for word in forbidden:
			assert_bool(b.text.to_lower().contains(word)).override_failure_message(b.text).is_false()
	assert_object(tb.tool_button(ModeToolbar.TOOL_ZONE)).is_not_null()
	assert_object(tb.tool_button(ModeToolbar.TOOL_INSPECT)).is_not_null()


func test_mode_toolbar_rows_switch_between_one_and_two() -> void:
	var tb := _themed(ModeToolbar.create(_ctx)) as ModeToolbar
	assert_int(tb.rows()).is_equal(1)
	tb.set_rows(2)
	assert_int(tb.rows()).is_equal(2)
	assert_object(tb.tool_button(ModeToolbar.TOOL_ZONE).get_parent().get_parent()).is_same(tb)
	tb.set_rows(1)
	assert_int(tb.rows()).is_equal(1)


func test_mode_toolbar_tool_signal() -> void:
	var tb := _themed(ModeToolbar.create(_ctx)) as ModeToolbar
	var tools := []
	tb.tool_selected.connect(func(t: StringName) -> void: tools.append(t))
	tb.tool_button(ModeToolbar.TOOL_ZONE).pressed.emit()
	assert_array(tools).is_equal([ModeToolbar.TOOL_ZONE])


# --- AgendaBadge ---

func test_agenda_badge_is_hidden_without_data_and_shows_real_counts() -> void:
	var a := _themed(AgendaBadge.create(_ctx)) as AgendaBadge
	assert_bool(a.visible).is_false()
	a.set_data(0, 3, false)
	assert_bool(a.visible).is_false()
	a.set_data(2, 5, true)
	assert_bool(a.visible).is_true()
	assert_str(a.text).contains("2")
	assert_str(a.text).contains("MOCK")
	a.set_data(0, 0, false)
	assert_bool(a.visible).is_false()


# --- ParcelInspector ---

func test_inspector_shows_only_parcel_view_fields_with_money_from_config() -> void:
	var f := UiTestSupport.mock()
	var ins := _themed(ParcelInspector.create(_ctx)) as ParcelInspector
	assert_bool(ins.empty_visible()).is_true()
	var parcel := f.parcel_views(PackedInt64Array([1]))[0]
	ins.show_parcel(parcel, true)
	var rows := ins.row_texts()
	assert_bool(rows.has("Parsel: Parsel 1")).is_true()
	assert_bool(rows.has("Arsa değeri: 2.600 ¤")).is_true()
	assert_bool(rows.has("Alan: 1.800 m²")).is_true()
	assert_bool(rows.has("İmar durumu: Konut")).is_true()
	for row in rows:
		for hidden_field in ["Altyapı", "Yatırımcı ilgisi", "Nüfus", "Mutluluk"]:
			assert_bool(row.contains(hidden_field)).is_false()
	assert_bool(ins.empty_visible()).is_false()
	ins.show_nothing()
	assert_bool(ins.empty_visible()).is_true()
	assert_int(ins.row_texts().size()).is_equal(0)


func test_inspector_why_button_only_when_reasons_exist() -> void:
	var f := UiTestSupport.mock()
	var ins := _themed(ParcelInspector.create(_ctx)) as ParcelInspector
	var parcel := f.parcel_views(PackedInt64Array([1]))[0]
	ins.show_parcel(parcel, true)
	assert_bool(ins.why_visible()).is_false()  # kayıtlı gerekçe yok: "Neden?" uydurulmaz
	parcel.reason_ids = PackedInt64Array([1])
	ins.show_parcel(parcel, true)
	assert_bool(ins.why_visible()).is_true()
	var subjects := []
	ins.reason_requested.connect(func(s: StringName) -> void: subjects.append(s))
	ins.why_button().pressed.emit()
	assert_array(subjects).is_equal([&"parcel.1"])
