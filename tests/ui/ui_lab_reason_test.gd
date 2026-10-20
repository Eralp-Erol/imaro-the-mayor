extends GdUnitTestSuite
## T-021 ölçüt 2 · ui_lab'da nedensellik paneli giriş noktaları (olay şeridi, parsel denetçisi, aktör listesi,
## klavye N) ve profil değişiminde gezinti durumunun korunması. MockSimFacade ile uçtan uca.
## Olumsuz: gerekçesi olmayan parselde "Bu parselde ne oldu?" görünmez; olay şeridindeki geçici ön izleme
## sınıfı artık yok (panel ReasonPanel).

const LAB_SCENE := "res://scenes/dev/ui_lab.tscn"


func before_test() -> void:
	UiText.reset()
	UiText.report_missing = false


func after_test() -> void:
	UiText.reset()


func _lab() -> Node:
	var lab: Node = auto_free((load(LAB_SCENE) as PackedScene).instantiate())
	add_child(lab)
	return lab


func _play_declined(lab: Node) -> void:
	lab.facade.submit_command(SimCommand.zoning_propose(PackedInt64Array([1]), &"zone.mixed"))
	lab.facade.advance(6)
	lab.hud.poll()


func _button(root: Node, text: String) -> Button:
	for b in UiTestSupport.visible_buttons(root):
		if b.text == text:
			return b
	return null


func test_inspector_history_button_opens_the_reason_panel_for_that_parcel() -> void:
	var lab := _lab()
	await await_idle_frame()
	lab.select_parcel(2)
	assert_object(_button(lab.hud.panel, "Bu parselde ne oldu?")).is_null()  # kayıtsız parsel: uydurma düğme yok
	lab.select_parcel(1)
	assert_object(_button(lab.hud.panel, "Bu parselde ne oldu?")).is_null()  # henüz hiçbir şey olmadı
	_play_declined(lab)
	await await_idle_frame()
	var why := _button(lab.hud.panel, "Bu parselde ne oldu?")
	assert_object(why).is_not_null()
	why.pressed.emit()
	assert_that(lab.hud.panel_id()).is_equal(&"reason")
	var panel: ReasonPanel = lab.reason_panel()
	assert_object(panel).is_not_null()
	assert_str(" ".join(panel.texts())).contains("Yatırımcı vazgeçti")


func test_rejected_event_in_the_strip_opens_the_rejection_view() -> void:
	var lab := _lab_with(UiTestSupport.INVALID)
	await await_idle_frame()
	lab.facade.submit_command(SimCommand.zoning_propose(PackedInt64Array([2]), &"zone.commercial"))
	lab.facade.advance(2)
	lab.hud.poll()
	var why := _button(lab.hud.strip, "Nedenini gör")
	assert_object(why).is_not_null()
	why.pressed.emit()
	var panel: ReasonPanel = lab.reason_panel()
	assert_that(panel.current_mode()).is_equal(ReasonPanel.MODE_REJECTION)
	assert_str(" ".join(panel.texts())).contains("Koruma alanında imar değişikliği önerilemez")


## Senaryoyu değiştirilmiş lab (ui_lab bağımsız `--ui-lab-scenario` argümanı olmadan test içinde değişir).
func _lab_with(scenario_file_name: String) -> Node:
	var lab: Node = auto_free((load(LAB_SCENE) as PackedScene).instantiate())
	add_child(lab)
	lab.facade = MockSimFacade.from_file(UiTestSupport.FIXTURES + scenario_file_name + ".json")
	lab.hud.setup(lab.facade, UiTestSupport.platform(&"desktop"))
	return lab


func test_actor_list_entry_opens_that_actors_reasons() -> void:
	var lab := _lab()
	await await_idle_frame()
	_play_declined(lab)
	lab.open_actors()
	await await_idle_frame()
	var investor := _button(lab.hud.panel, "Yatırımcı 1")
	assert_object(investor).is_not_null()  # olay akışındaki aktörden
	investor.pressed.emit()
	assert_that(lab.hud.panel_id()).is_equal(&"reason")
	assert_str(" ".join((lab.reason_panel() as ReasonPanel).texts())).contains("Yatırımcı vazgeçti")


func test_n_key_opens_reasons_for_the_selected_parcel() -> void:
	var lab := _lab()
	await await_idle_frame()
	_play_declined(lab)
	lab.select_parcel(1)
	var key := InputEventKey.new()
	key.keycode = KEY_N
	key.pressed = true
	lab._unhandled_key_input(key)
	assert_that(lab.hud.panel_id()).is_equal(&"reason")
	assert_str(" ".join((lab.reason_panel() as ReasonPanel).texts())).contains("Yatırımcı vazgeçti")


func test_show_on_map_selects_the_parcel_without_closing_the_panel() -> void:
	var lab := _lab()
	await await_idle_frame()
	_play_declined(lab)
	lab.select_parcel(2)
	lab.open_reason_for(&"parcel.1")
	var map_button: Button = null
	for b in UiTestSupport.visible_buttons(lab.hud.panel):
		if b.text.begins_with("Haritada göster"):
			map_button = b
	assert_object(map_button).is_not_null()
	map_button.pressed.emit()
	assert_int(lab.state()["selected"]).is_equal(1)
	assert_that(lab.hud.panel_id()).is_equal(&"reason")


func test_navigation_state_survives_a_profile_switch() -> void:
	var lab := _lab()
	await await_idle_frame()
	_play_declined(lab)
	lab.open_reason_for(&"parcel.1")
	var before: ReasonPanel = lab.reason_panel()
	var depth := before.stack_depth()
	lab.hud.apply_profile(UiTestSupport.platform(&"touch"))
	await await_idle_frame()
	var after: ReasonPanel = lab.reason_panel()
	assert_bool(after != before).is_true()  # panel yeniden kuruldu
	assert_int(after.stack_depth()).is_equal(depth)
	assert_str(" ".join(after.texts())).contains("Yatırımcı vazgeçti")
