extends "res://tests/sim/politics/reaction_world_base.gd"
## D-028 / B-131 test boşlukları (QA): gündem TAM açılış yerleşim matrisi (başsız, GERÇEK iPad DEĞİL) ve "Nedenini gör"
## negatif durumu. Gerçek HUD + `DecisionPanels` + gerçek PE-01 öğesi; ek öğeler `set_item_provider` ile eklenir.
## Mevcut `agenda_drawer_height_test.gd` tek gerçek öğeyi (3 seçenek) sınar; burada: tek seçenekli tek öğe, 3 öğeli
## gündem, yerinden edilme nedeni olmayan öğe. Ölçüm düğümlerin `get_global_rect()` değerlerinden (kaydırma 0).

const WINDOWS: Array[Vector2] = [Vector2(1024, 768), Vector2(768, 1024)]


func before_test() -> void:
	UiText.reset()
	UiText.report_missing = false


func after_test() -> void:
	UiText.reset()


## Gerçek HUD'u (dokunmatik) kurar, gündemi açar, sonra `build_items(real_items)` ile öğe listesini değiştirir.
## Dönüş: {hud, dp, items}. `build_items` null ise gerçek öğe listesi aynen kalır.
func _open(window: Vector2, build_items: Callable = Callable()) -> Dictionary:
	var h: PoliticsHandle = _world()["handle"]
	h.facade.advance(14)
	var hud := HudRoot.new()
	add_child(hud)
	hud.setup(h.facade, UiTestSupport.platform(&"touch"))
	hud.set_anchors_preset(Control.PRESET_TOP_LEFT)
	hud.size = window
	hud.refresh()
	var dp := DecisionPanels.attach(hud, h.facade)
	dp.open_agenda()
	await await_idle_frame()
	var real_items := AgendaModel.derive_all(h.facade, h.facade.snapshot())
	if build_items.is_valid():
		var custom: Array[AgendaModel.Item] = build_items.call(real_items)
		dp.agenda_panel().set_item_provider(func(_s: SimSnapshot) -> Array[AgendaModel.Item]: return custom)
	await await_idle_frame()
	await await_idle_frame()
	await await_idle_frame()
	return {"hud": auto_free(hud), "dp": dp, "facade": h.facade, "real": real_items}


func _answer_buttons(hud: HudRoot) -> Array[Button]:
	var out: Array[Button] = []
	_collect_answers(hud.panel, out)
	return out


func _collect_answers(node: Node, out: Array[Button]) -> void:
	if node is Button and (node as Button).is_visible_in_tree() and (node as Button).text == UiText.t(&"agenda.choose"):
		out.append(node)
	for c in node.get_children():
		_collect_answers(c, out)


func _labels_starting(card: Node, prefix: String) -> Array[Label]:
	var out: Array[Label] = []
	for c in card.get_children():
		if c is Label and (c as Label).text.begins_with(prefix):
			out.append(c)
	return out


func _button_texts(hud: HudRoot) -> PackedStringArray:
	return UiTestSupport.button_texts(hud.panel)


## Ölçüm: ilk "Bu yanıtı ver" panelin görünür alanında mı, etki satırı düğmenin üstünde mi.
func _measure(hud: HudRoot) -> Dictionary:
	var buttons := _answer_buttons(hud)
	if buttons.is_empty():
		return {"has_button": false}
	var btn := buttons[0]
	var view := btn.get_global_rect()
	var area := hud.panel.get_global_rect()
	var effects := _labels_starting(btn.get_parent(), "• ")
	var above := not effects.is_empty()
	for l in effects:
		above = above and l.get_global_rect().end.y <= view.position.y
	return {"has_button": true, "view": view, "area": area, "enclosed": area.grow(1.0).encloses(view),
			"effects": effects.size(), "effects_above": above, "height": view.size.y, "count": buttons.size()}


func _assert_first_answer_in_panel(hud: HudRoot, tag: String) -> void:
	assert_int(hud.drawer_state).override_failure_message("gündem TAM açılmadı " + tag) \
			.is_equal(DrawerModel.State.FULL)
	var m := _measure(hud)
	assert_bool(bool(m["has_button"])).override_failure_message("'Bu yanıtı ver' yok " + tag).is_true()
	assert_bool(bool(m["enclosed"])).override_failure_message(
			"ilk 'Bu yanıtı ver' panelin görünür alanında değil (kaydırma gerekir) %s: düğme=%s panel=%s" % [
			tag, str(m["view"]), str(m["area"])]).is_true()
	assert_float(float(m["height"])).override_failure_message("dokunma hedefi < 44 " + tag).is_greater_equal(44.0)


# --- Yardımcılar: sentetik öğeler (yalnız yerleşim girdisi; sayı/komut uydurmaz, yanıt gönderilmez) ---

func _option(id: StringName, effect_count: int) -> AgendaModel.Option:
	var o := AgendaModel.Option.new()
	o.id = id
	o.verb = &"listen"
	o.label_key = &"event.pe01.opt.listen"
	var all: Array = [
		{"target": "complaints", "scope": "subject", "direction": -1, "delay_days": 7, "duration_days": 90},
		{"target": "investor_risk", "scope": "region", "direction": 1, "delay_days": 0, "duration_days": 180},
		{"target": "trust", "scope": "group", "direction": 1, "delay_days": 7, "duration_days": 0}]
	o.effects = all.slice(0, effect_count)
	return o


func _event_item(id: StringName, option_count: int, effect_count: int, days: int) -> AgendaModel.Item:
	var it := AgendaModel.Item.new()
	it.id = id
	it.kind = AgendaModel.KIND_EVENT
	it.title_key = &"event.pe01.reason"
	it.days_left = days
	it.deadline_tick = 100 + days
	it.agenda_item_id = 9000 + days
	for i in option_count:
		it.options.append(_option(StringName("opt%d" % i), effect_count))
	return it


# --- (a) tek seçenekli, tek öğeli gündem ---

func test_single_event_item_single_option_answer_button_in_panel_both_orientations() -> void:
	for window in WINDOWS:
		var ctx := await _open(window, func(_real: Array[AgendaModel.Item]) -> Array[AgendaModel.Item]:
			return [_event_item(&"agenda.9001", 1, 1, 30)] as Array[AgendaModel.Item])
		var hud: HudRoot = ctx["hud"]
		var tag := str(window)
		_assert_first_answer_in_panel(hud, tag)
		var m := _measure(hud)
		assert_int(int(m["count"])).override_failure_message("tam 1 yanıt düğmesi beklenir " + tag).is_equal(1)
		assert_int(int(m["effects"])).override_failure_message("etki satırı yok " + tag).is_equal(1)
		assert_bool(bool(m["effects_above"])).override_failure_message("etki yazısı düğmenin üstünde değil " + tag) \
				.is_true()
		# Yerinden edilme nedeni kaydı yok -> "Nedenini gör" ve hane satırı çıkmaz.
		assert_bool(_button_texts(hud).has("Nedenini gör")).override_failure_message("nedensiz öğede 'Nedenini gör' " + tag) \
				.is_false()


func test_single_real_displacement_item_with_one_option_why_button_below_answer_both_orientations() -> void:
	for window in WINDOWS:
		var ctx := await _open(window, func(real: Array[AgendaModel.Item]) -> Array[AgendaModel.Item]:
			var it: AgendaModel.Item = real[0]
			it.options = [it.options[0]] as Array[AgendaModel.Option]   # gerçek öğe, tek seçenek (kopya liste)
			return [it] as Array[AgendaModel.Item])
		var hud: HudRoot = ctx["hud"]
		var real: Array[AgendaModel.Item] = ctx["real"]
		var tag := str(window)
		assert_str(String(real[0].kind)).override_failure_message("gerçek öğe yerinden edilme değil " + tag) \
				.is_equal("displacement")
		_assert_first_answer_in_panel(hud, tag)
		var m := _measure(hud)
		assert_int(int(m["count"])).is_equal(1)
		assert_bool(bool(m["effects_above"])).is_true()
		var why := _find_button(hud.panel, "Nedenini gör")
		assert_object(why).override_failure_message("gerçek nedenli öğede 'Nedenini gör' yok " + tag).is_not_null()
		assert_float(why.get_global_rect().position.y).override_failure_message(
				"'Nedenini gör' cevap düğmesinin ALTINDA değil " + tag).is_greater_equal(
				(m["view"] as Rect2).end.y - 1.0)


func _find_button(node: Node, text: String) -> Button:
	if node is Button and (node as Button).is_visible_in_tree() and (node as Button).text == text:
		return node
	for c in node.get_children():
		var b := _find_button(c, text)
		if b != null:
			return b
	return null


# --- (b) çok öğeli (3) gündem ---

## İlk öğe gerçek PE-01 (başlık + hane + özet satırları + 3 seçenek + Nedenini gör = en yüksek başlık bloğu).
func test_three_item_agenda_real_displacement_first_answer_in_panel_both_orientations() -> void:
	for window in WINDOWS:
		var ctx := await _open(window, func(real: Array[AgendaModel.Item]) -> Array[AgendaModel.Item]:
			return [real[0], _event_item(&"agenda.9002", 3, 3, 40), _event_item(&"agenda.9003", 3, 3, 50)] \
					as Array[AgendaModel.Item])
		var hud: HudRoot = ctx["hud"]
		var tag := str(window)
		var panel: AgendaPanel = ctx["dp"].agenda_panel()
		assert_int(panel.items.size()).override_failure_message("3 öğe yerleşmedi (panel yeniden kuruldu mu?) " + tag) \
				.is_equal(3)
		_assert_first_answer_in_panel(hud, tag)
		var m := _measure(hud)
		assert_int(int(m["count"])).override_failure_message("3 öğe x 3 seçenek = 9 düğme " + tag).is_equal(9)
		assert_bool(bool(m["effects_above"])).override_failure_message("etki yazısı düğmenin üstünde değil " + tag) \
				.is_true()


## En kötü durum: ilk öğe nedensiz olay (kısa başlık bloğu) ama 3 seçenek x 3 etki; ikincisi gerçek öğe.
func test_three_item_agenda_event_first_with_three_effects_first_answer_in_panel_both_orientations() -> void:
	for window in WINDOWS:
		var ctx := await _open(window, func(real: Array[AgendaModel.Item]) -> Array[AgendaModel.Item]:
			return [_event_item(&"agenda.9002", 3, 3, 10), real[0], _event_item(&"agenda.9003", 3, 3, 50)] \
					as Array[AgendaModel.Item])
		var hud: HudRoot = ctx["hud"]
		var tag := str(window)
		assert_int((ctx["dp"].agenda_panel() as AgendaPanel).items.size()).is_equal(3)
		_assert_first_answer_in_panel(hud, tag)
		assert_bool(bool(_measure(hud)["effects_above"])).is_true()


## Olumsuz kontrol (ölçüm düzeneğinin düşebildiğini gösterir): çok küçük pencerede aynı gündemde ilk düğme panelin
## dışında kalmalı; `_measure` bunu `enclosed=false` bildirmeli. Düzenek hep true dönseydi bu test düşerdi.
func test_measurement_detects_a_clipped_answer_button_in_a_tiny_window() -> void:
	var ctx := await _open(Vector2(1024, 330), func(real: Array[AgendaModel.Item]) -> Array[AgendaModel.Item]:
		return [real[0], _event_item(&"agenda.9002", 3, 3, 40)] as Array[AgendaModel.Item])
	var m := _measure(ctx["hud"])
	assert_bool(bool(m["has_button"])).is_true()
	assert_bool(bool(m["enclosed"])).override_failure_message(
			"330 px yüksek pencerede de 'enclosed' diyor: ölçüm düzeneği kırılmayı yakalayamıyor: %s" % str(m)).is_false()


# --- (c) "Nedenini gör" yalnız yerinden edilme nedeni kayıtta varsa ---

func test_why_button_absent_when_item_has_no_reason_ids_and_present_with_the_real_ones() -> void:
	# Pozitif kontrol: gerçek reason_ids ile düğme VAR (test düşebilir); boş reason_ids ile YOK.
	var with_real := await _open(Vector2(1024, 768))
	assert_bool(_button_texts(with_real["hud"]).has("Nedenini gör")).override_failure_message(
			"kontrol: gerçek nedenli öğede düğme olmalı").is_true()
	var without := await _open(Vector2(1024, 768), func(real: Array[AgendaModel.Item]) -> Array[AgendaModel.Item]:
		var it: AgendaModel.Item = real[0]
		it.reason_ids = PackedInt64Array()
		return [it] as Array[AgendaModel.Item])
	var hud: HudRoot = without["hud"]
	assert_bool(_button_texts(hud).has("Nedenini gör")).override_failure_message("nedensiz öğede 'Nedenini gör'") \
			.is_false()
	var panel: AgendaPanel = without["dp"].agenda_panel()
	assert_bool(panel.joined_text().contains("hane yerinden edildi")).override_failure_message(
			"nedensiz öğede hane satırı (sayı uydurulmuş)").is_false()
	# Yanıt düğmesi yine de var: seçenekler sim'den, neden zincirinden bağımsız.
	assert_int(_answer_buttons(hud).size()).is_equal(3)


func test_why_button_absent_when_reason_chain_has_no_displaced_count_or_unknown_id() -> void:
	var probe := await _open(Vector2(1024, 768))
	var facade: SimFacade = probe["facade"]
	var real: Array[AgendaModel.Item] = probe["real"]
	# Bu dünyada yerinden edilme sayısı İÇERMEYEN gerçek bir kayıt bul (PE-01 zinciri dışı).
	var unrelated := PackedInt64Array()
	for rid in UiTestSupport.all_reason_ids(facade):
		if not bool(AgendaModel.displaced_cause(facade, PackedInt64Array([rid]))["found"]):
			unrelated = PackedInt64Array([rid])
			break
	assert_int(unrelated.size()).override_failure_message(
			"dünyada yerinden-edilmesiz gerçek kayıt yok: test girdisi kurulamadı").is_equal(1)
	assert_bool(bool(AgendaModel.displaced_cause(facade, real[0].reason_ids)["found"])).is_true()   # kontrol
	for ids: PackedInt64Array in [unrelated, PackedInt64Array([987654321])]:
		var ctx := await _open(Vector2(1024, 768), func(r: Array[AgendaModel.Item]) -> Array[AgendaModel.Item]:
			var it: AgendaModel.Item = r[0]
			it.reason_ids = ids
			return [it] as Array[AgendaModel.Item])
		var hud: HudRoot = ctx["hud"]
		var tag := str(ids)
		assert_bool(_button_texts(hud).has("Nedenini gör")).override_failure_message(
				"yerinden edilme nedeni olmayan zincirde 'Nedenini gör' çıktı " + tag).is_false()
		var panel: AgendaPanel = ctx["dp"].agenda_panel()
		assert_bool(panel.joined_text().contains("hane yerinden edildi")).override_failure_message(
				"neden yokken hane satırı çıktı " + tag).is_false()
		assert_array(Array(panel.named_buttons("why_"))).override_failure_message("why_ rolü var " + tag).is_empty()
