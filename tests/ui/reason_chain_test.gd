extends GdUnitTestSuite
## T-021 ölçüt 1/3/4/5 · ReasonPanel (2/2): neden zinciri gezinmesi, zaman çizelgesi, bağlantılar, tutarsız kaydın
## görünürde işaretlenmesi, v1.1 uzantılarının zarif düşüşü, dokunmatik hedefler ve erişilebilirlik.
## Olumsuz varyantlar: tutarlı kayıt işaretlenmez; haritada göster yalnız sahibi dinliyorsa; zincirde olmayan önceki
## kayıt dürüstçe "saklanmıyor"; tek kayıtlı aktör ölü bağlantı olmaz.

const DECLINED := "mock_scenario_investment_declined"
const POSITIVE := "mock_scenario_investment_positive"

## `sim` kaynaklı (MOCK olmayan) facade: kayıtlar da sim kaynaklı.
class SimSourced:
	extends UiLabReasonFacade

	func provenance() -> StringName:
		return SimContract.PROVENANCE_SIM


func before_test() -> void:
	UiText.reset()
	UiText.report_missing = false


func after_test() -> void:
	UiText.reset()


func _panel(facade: SimFacade, profile_name: StringName = &"desktop",
		window: Vector2 = Vector2(440, 1200)) -> ReasonPanel:
	var ctx := UiContext.for_profile_name(profile_name)
	var holder := Control.new()
	holder.theme = UiTheme.build(ctx)
	holder.size = window
	add_child(holder)
	auto_free(holder)
	var p := ReasonPanel.create(ctx, facade)
	holder.add_child(p)
	p.size = window
	return p


func _joined(p: ReasonPanel) -> String:
	return " | ".join(p.texts())


func _role(p: ReasonPanel, role: String) -> Control:
	var found := p.find_roles(role)
	return found[0] if not found.is_empty() else null


func _banner(p: ReasonPanel) -> Control:
	return _role(p, ReasonPanel.NAME_BANNER)


func _chain_facade() -> UiLabReasonFacade:
	return UiLabReasonFacade.with_records(UiTestSupport.FIXTURES + DECLINED + ".json",
		UiLabReasonFacade.chain_records())


func _press(b: Button) -> void:
	assert_object(b).is_not_null()
	b.pressed.emit()


# --- ölçüt 1: zincir gezinmesi, zaman çizelgesi, bağlantılar ---

func test_chain_navigation_goes_to_earlier_cause_and_back() -> void:
	var p := _panel(_chain_facade())
	p.show_record(3)
	assert_int(p.stack_depth()).is_equal(1)
	assert_bool(p.back_button.visible).is_false()
	var parents := p.named_buttons(ReasonPanel.NAME_PARENT)
	assert_int(parents.size()).is_equal(1)
	assert_str(parents[0].text).contains("Yatırımcı vazgeçti")
	_press(parents[0])  # 3 -> 2
	assert_int(p.stack_depth()).is_equal(2)
	assert_bool(p.back_button.visible).is_true()
	assert_str(_joined(p)).contains("Yatırımcı vazgeçti")
	_press(p.named_buttons(ReasonPanel.NAME_PARENT)[0])  # 2 -> 1
	assert_int(p.stack_depth()).is_equal(3)
	assert_str(_joined(p)).contains("Grup protesto etti")
	assert_int(p.named_buttons(ReasonPanel.NAME_PARENT).size()).is_equal(0)
	assert_str(_joined(p)).contains("Öncesinde kayıtlı bir neden yok")
	p.back()
	assert_str(_joined(p)).contains("Yatırımcı vazgeçti")
	p.back()
	assert_int(p.stack_depth()).is_equal(1)
	assert_bool(p.back_button.visible).is_false()
	p.back()  # taban: daha fazla geri yok, bozulmaz
	assert_int(p.stack_depth()).is_equal(1)


func test_back_button_and_backspace_key_step_back() -> void:
	var p := _panel(_chain_facade())
	p.show_record(3)
	_press(p.named_buttons(ReasonPanel.NAME_PARENT)[0])
	_press(p.back_button)
	assert_int(p.stack_depth()).is_equal(1)
	_press(p.named_buttons(ReasonPanel.NAME_PARENT)[0])
	var key := InputEventKey.new()
	key.keycode = KEY_BACKSPACE
	key.pressed = true
	p._unhandled_key_input(key)
	assert_int(p.stack_depth()).is_equal(1)


func test_timeline_lists_other_records_about_the_same_subject() -> void:
	var p := _panel(_chain_facade())
	p.show_record(3)
	var t := _joined(p)
	assert_str(t).contains("Zaman içinde")
	assert_str(t).contains("bu kayıt")
	assert_int(p.named_buttons(ReasonPanel.NAME_TIMELINE).size()).is_equal(2)  # diğer iki kayıt


func test_subject_link_opens_that_subjects_list_and_back_returns() -> void:
	var p := _panel(_chain_facade())
	p.show_record(3)
	var link := _role(p, ReasonPanel.NAME_SUBJECT + "_parcel.1") as Button
	_press(link)
	assert_that(p.current_mode()).is_equal(ReasonPanel.MODE_LIST)
	assert_str(_joined(p)).contains("Parsel 1")
	assert_int(p.named_buttons(ReasonPanel.NAME_ROW).size()).is_equal(3)  # zaman sıralı: tick 4, 6, 9
	var rows := p.named_buttons(ReasonPanel.NAME_ROW)
	assert_str(rows[0].text).contains("5. gün")
	assert_str(rows[2].text).contains("10. gün")
	p.back()
	assert_that(p.current_mode()).is_equal(ReasonPanel.MODE_DETAIL)


func test_actor_with_a_single_record_is_plain_text_not_a_dead_link() -> void:
	var p := _panel(UiTestSupport.played(DECLINED))
	p.show_record(1)
	assert_object(_role(p, ReasonPanel.NAME_SUBJECT + "_actor")).is_null()
	assert_str(_joined(p)).contains("Yatırımcı 1")  # yine de gösterilir


func test_missing_parent_record_is_reported_as_not_stored() -> void:
	var records := UiLabReasonFacade.chain_records()
	records[1].parent_ids = PackedInt64Array([77])  # var olmayan önceki kayıt
	var p := _panel(UiLabReasonFacade.with_records(UiTestSupport.FIXTURES + DECLINED + ".json", records))
	p.show_record(2)
	assert_int(p.named_buttons(ReasonPanel.NAME_PARENT).size()).is_equal(0)
	assert_str(_joined(p)).contains("Bu kayıt artık saklanmıyor")


func test_nav_state_survives_rebuild_for_profile_switch() -> void:
	var f := _chain_facade()
	var p := _panel(f)
	p.show_record(3)
	_press(p.named_buttons(ReasonPanel.NAME_PARENT)[0])
	var saved := p.nav_state()
	var p2 := _panel(f, &"touch", Vector2(1000, 700))
	p2.restore_nav(saved)
	assert_int(p2.stack_depth()).is_equal(2)
	assert_str(_joined(p2)).contains("Yatırımcı vazgeçti")
	assert_bool(p2.back_button.visible).is_true()


func test_show_on_map_button_only_when_owner_listens() -> void:
	var f := UiTestSupport.played(DECLINED)
	var p := _panel(f)
	p.show_record(1)
	assert_object(_role(p, "MapButton_parcel.1")).is_null()  # ölü düğme yok
	var p2 := _panel(f)
	p2.map_enabled = true
	var focused: Array = []
	p2.map_focus_requested.connect(func(ref: StringName) -> void: focused.append(ref))
	p2.show_record(1)
	_press(_role(p2, "MapButton_parcel.1") as Button)
	assert_array(focused).is_equal([&"parcel.1"])


# --- ölçüt 3: tutarsız kayıt görünürde işaretlenir ---

func test_inconsistent_record_is_flagged_visibly_with_numbers_and_list_marker() -> void:
	var f := UiTestSupport.played(DECLINED)
	var bad := UiLabReasonFacade.corrupt(f.reason(1), 450, true)
	var facade := UiLabReasonFacade.with_records(UiTestSupport.FIXTURES + DECLINED + ".json", [bad, f.reason(1)])
	var p := _panel(facade)
	p.show_record(1)
	assert_object(_banner(p)).is_not_null()
	var t := _joined(p)
	assert_str(t).contains("Kayıt tutarsız: veri hatası")
	assert_str(t).contains("Kayıtlı toplam 0,65, etkenlerden hesaplanan 0,20")
	assert_str(t).contains("uyuşmuyor")
	assert_str(t).contains("güvenilir sayılmamalı")
	# Liste satırında da işaret var.
	p.show_subject(&"parcel.1")
	assert_str(_joined(p)).contains("Tutarsız kayıt")


func test_consistent_sibling_record_in_same_list_is_not_flagged() -> void:
	var f := UiTestSupport.played(DECLINED)
	var bad := UiLabReasonFacade.corrupt(f.reason(1), 450, false)
	var good := f.reason(1)
	good.id = 2
	good.tick += 1
	var facade := UiLabReasonFacade.with_records(UiTestSupport.FIXTURES + DECLINED + ".json", [bad, good])
	var p := _panel(facade)
	p.show_subject(&"parcel.1")
	var rows := p.named_buttons(ReasonPanel.NAME_ROW)
	assert_int(rows.size()).is_equal(2)
	assert_str(rows[0].text).contains("Tutarsız kayıt")
	assert_str(rows[1].text).not_contains("Tutarsız kayıt")


# --- v1.1 uzantıları: yoksa düşer, varsa kullanılır ---

func test_v10_record_derives_summary_from_factors_instead_of_inventing() -> void:
	var p := _panel(UiTestSupport.played(DECLINED))
	p.show_record(1)
	assert_str(_joined(p)).contains("En çok etkileyen:")
	assert_str(_joined(p)).not_contains("Eğilim")


func test_v11_summary_trend_and_cause_refs_are_used_when_the_contract_provides_them() -> void:
	var r: ReasonRecord = ReasonTestSupport.ExtRecord.new()
	r.id = 1
	r.tick = 2
	r.actor = ActorRef.make(&"investor", 1)
	r.decision_key = &"decision.investor.develop"
	r.threshold = 0
	r.subjects = PackedStringArray(["parcel.1"])
	var f: ReasonFactor = ReasonTestSupport.ExtFactor.new()
	f.name_key = &"reason.factor.demand"
	f.value = 400
	f.weight = 500
	r.factors = [f]
	r.finalize()
	var p := _panel(UiLabReasonFacade.with_records(UiTestSupport.FIXTURES + DECLINED + ".json", [r]))
	p.show_record(1)
	var t := _joined(p)
	assert_str(t).contains("Yatırımcı vazgeçti")  # sim özet anahtarı (ExtRecord.summary_key) kullanıldı
	assert_str(t).contains("Azalıyor")  # trend = -1
	assert_str(t).contains("Parsel 7")  # cause_refs bağlantısı
	assert_str(t).not_contains("En çok etkileyen:")


# --- ölçüt 4/5: dokunmatik, klavye, erişilebilirlik ---

func test_touch_targets_are_at_least_44_in_every_view() -> void:
	var f := _chain_facade()
	var p := _panel(f, &"touch", Vector2(1000, 1400))
	p.map_enabled = true
	await await_idle_frame()
	for view in ["detail", "list", "back", "rejection"]:
		match view:
			"detail":
				p.show_record(3)
			"list":
				p.show_subject(&"parcel.1")
			"back":
				p.show_record(3)
				_press(p.named_buttons(ReasonPanel.NAME_PARENT)[0])
			"rejection":
				p.show_command_result(CommandResult.rejected(SimCommand.make(&"x"), &"command.reject.unknown_kind",
					{"kind": "x"}, 1, SimContract.PROVENANCE_MOCK))
		await await_idle_frame()
		var seen := 0
		for b in UiTestSupport.visible_buttons(p):
			seen += 1
			assert_float(UiFactory.hit_size(b).y).override_failure_message("%s: '%s'" % [view, b.text]) \
				.is_greater_equal(44.0)
			assert_int(b.focus_mode).is_equal(Control.FOCUS_ALL)  # klavye/odak gezinmesi
		if view != "rejection":
			assert_int(seen).is_greater(0)


func test_desktop_buttons_are_keyboard_focusable_and_labelled() -> void:
	var p := _panel(_chain_facade())
	p.show_record(3)
	for b in UiTestSupport.visible_buttons(p):
		assert_int(b.focus_mode).is_equal(Control.FOCUS_ALL)
		assert_str(b.text).is_not_empty()  # simge-tek düğme yok


func test_no_hover_dependency_all_information_visible_without_tooltips() -> void:
	# Etken satırının hesap metni tooltip'e DEĞİL görünür etikete yazılır (dokunmatikte hover yok).
	var p := _panel(UiTestSupport.played(DECLINED), &"touch", Vector2(1000, 1400))
	p.show_record(1)
	assert_str(_joined(p)).contains("Değer 0,30 × ağırlık 0,40 = +0,12")


func test_colours_used_for_meaning_meet_contrast_thresholds() -> void:
	var tk := UiTokens.load_default()
	var bg := tk.color("panel_bg")
	for token in ["text", "text_muted", "ok", "danger"]:  # metin: >= 4,5
		assert_float(UiTokens.contrast_ratio(tk.color(token), bg)).override_failure_message(token) \
			.is_greater_equal(4.5)
	for token in ["accent", "focus", "ok", "danger"]:  # çubuk/çizgi (grafik): >= 3 (panel_bg_alt zemini)
		assert_float(UiTokens.contrast_ratio(tk.color(token), tk.color("panel_bg_alt"))) \
			.override_failure_message(token).is_greater_equal(3.0)


func test_bars_have_opposite_sides_so_direction_is_not_colour_only() -> void:
	var p := _panel(UiTestSupport.played(DECLINED))
	p.show_record(1)
	await await_idle_frame()
	var bars := p.find_children("*", "ReasonFactorBar", true, false)
	assert_int(bars.size()).is_equal(4)
	var left := 0
	var right := 0
	for bar: ReasonFactorBar in bars:
		var fill := bar.fill_rect()
		if fill.position.x < bar.size.x * 0.5 - 0.5:
			left += 1
		else:
			right += 1
	assert_int(left).is_equal(1)  # aleyhte olan tek etken (inşaat maliyeti) eksenin soluna uzanır
	assert_int(right).is_equal(3)


func test_meter_puts_threshold_line_right_of_score_when_short_and_left_when_exceeded() -> void:
	var f := UiTestSupport.played(DECLINED)
	var m: ReasonMeter = auto_free(ReasonMeter.create(UiContext.for_profile_name(&"desktop"),
		ReasonModel.from_record(f.reason(1))))
	assert_float(m.score_position()).is_less(m.threshold_position())
	var g := UiTestSupport.played(POSITIVE)
	var m2: ReasonMeter = auto_free(ReasonMeter.create(UiContext.for_profile_name(&"desktop"),
		ReasonModel.from_record(g.reason(1))))
	assert_float(m2.score_position()).is_greater(m2.threshold_position())
