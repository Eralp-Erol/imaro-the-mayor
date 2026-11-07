extends "res://tests/sim/politics/reaction_world_base.gd"
## D-028 / B-123: dokunmatik 1024x768'de gündem (halk tepkisi yanıtı) çekmecesi yol onay kartı gibi yüksek açılır;
## "Bu yanıtı ver" kaydırmasız görünür ve etki yazısı düğmenin ÜSTÜNDE kalır. Başsız yerleşim ölçümü; GERÇEK iPad DEĞİL.

func before_test() -> void:
	UiText.reset()
	UiText.report_missing = false


func after_test() -> void:
	UiText.reset()


func _open_agenda_hud(window: Vector2) -> HudRoot:
	var h: PoliticsHandle = _world()["handle"]
	h.facade.advance(14)
	var hud := HudRoot.new()
	add_child(hud)
	hud.setup(h.facade, UiTestSupport.platform(&"touch"))
	hud.set_anchors_preset(Control.PRESET_TOP_LEFT)
	hud.size = window
	hud.refresh()
	DecisionPanels.attach(hud, h.facade).open_agenda()
	await await_idle_frame()
	await await_idle_frame()
	await await_idle_frame()
	return auto_free(hud)


func _first_answer(node: Node) -> Button:
	if node is Button and (node as Button).is_visible_in_tree() and (node as Button).text == UiText.t(&"agenda.choose"):
		return node
	for c in node.get_children():
		var b := _first_answer(c)
		if b != null:
			return b
	return null


## Düğmenin kartındaki etki satırları ("• ..." önizleme maddeleri).
func _effect_labels(card: Node) -> Array[Label]:
	var out: Array[Label] = []
	for c in card.get_children():
		if c is Label and (c as Label).text.begins_with("• "):
			out.append(c)
	return out


func _check(window: Vector2) -> void:
	var hud := await _open_agenda_hud(window)
	var tag := str(window)
	assert_int(hud.drawer_state).override_failure_message("gündem yüksek açılmadı " + tag) \
			.is_equal(DrawerModel.State.FULL)
	var btn := _first_answer(hud.panel)
	assert_object(btn).override_failure_message("'Bu yanıtı ver' yok " + tag).is_not_null()
	var view := btn.get_global_rect()
	var area := hud.panel.get_global_rect()
	assert_bool(area.grow(1.0).encloses(view)).override_failure_message(
			"düğme panelin görünür alanında değil (kaydırma gerekir) %s: düğme=%s panel=%s" % [tag, str(view), str(area)]) \
			.is_true()
	assert_float(view.size.y).is_greater_equal(44.0)
	var effects := _effect_labels(btn.get_parent())
	assert_int(effects.size()).override_failure_message("etki yazısı yok " + tag).is_greater(0)
	for l in effects:
		assert_float(l.get_global_rect().end.y).override_failure_message(
				"etki yazısı düğmenin ÜSTÜNDE değil " + tag).is_less_equal(view.position.y)
	assert_bool(area.grow(1.0).encloses(effects[0].get_global_rect())).override_failure_message(
			"etki yazısı görünür alanda değil " + tag).is_true()


func test_touch_1024x768_agenda_answer_button_is_visible_without_scrolling_and_effect_is_above_it() -> void:
	await _check(Vector2(1024, 768))


func test_touch_portrait_768x1024_agenda_answer_button_is_visible_without_scrolling() -> void:
	await _check(Vector2(768, 1024))


func test_only_agenda_opens_tall_and_player_can_still_lower_the_drawer() -> void:
	assert_bool(HudRoot.DRAWER_OPEN_TALL_PANELS.has(&"agenda")).is_true()
	for id: StringName in [&"council", &"budget", &"policy", &"zoning", &"road_draw", &"inspector"]:
		assert_bool(HudRoot.DRAWER_OPEN_TALL_PANELS.has(id)).is_false()
	var hud := await _open_agenda_hud(Vector2(1024, 768))
	hud.set_drawer_state(DrawerModel.State.HALF)
	await await_idle_frame()
	assert_int(hud.drawer_state).is_equal(DrawerModel.State.HALF)
