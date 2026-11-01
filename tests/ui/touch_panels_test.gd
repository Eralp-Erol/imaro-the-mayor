extends "res://tests/sim/politics/reaction_world_base.gd"
## Dokunmatik (iPad, ikincil profil; ADR-0004) denetimi · gündem seçenek kartları, meclis oylama nedenleri,
## M2 sonuç paneli
## ve yol çizim paneli GERÇEK yerleşim ölçümüyle: dar yuvada (iPad bölünmüş görünüm 320 .. yatay yan panel ~520 .. dikey
## sayfa 744 px) ve büyütülmüş yazıda (ui_scale 1.5, Türkçe uzun etiketler) yatay taşma / kesik etiket-düğme yok,
## hedefler >= 44, yan yana düğmeler arası >= 8 pt (yanlış dokunma), dokunma olayları panel üstünde dünya kamerasına
## geçmez. Ölçüm başsız yerleşimdir; GERÇEK parmak/cihaz denemesi DEĞİL (ADR-0004: cihaz doğrulaması ayrı).

const NORTH := Vector2(1100.0, 1000.0)
## Yuva genişlikleri (px): bölünmüş görünüm, dar yan panel, iPad yatay yan panel (%38), iPad dikey sayfa.
const WIDTHS := [320.0, 389.0, 520.0, 744.0]
const SCALES := [1.0, 1.5]
const MIN_TARGET := 44.0
const MIN_GAP := 8.0
## Dokunmatikte panel metninde geçmemesi gereken fare/klavye ifadeleri (masaüstü yönergesi sızması).
const DESKTOP_ONLY_WORDS := ["enter", "esc ", "esc,", "tıkla", "sağ tık", "fare", "imleç", "üzerine gel", "ctrl"]


func before_test() -> void:
	InspectorHost.default_interval_msec = 0
	M2Results.default_interval_msec = 0
	UiText.reset()
	UiText.report_missing = false


func after_test() -> void:
	UiText.reset()


func _holder(ctx: UiContext, width: float) -> Control:
	var holder := Control.new()
	holder.theme = UiTheme.build(ctx)
	holder.size = Vector2(width, 4000.0)
	add_child(holder)
	return auto_free(holder)


## Paneli `width` genişliğinde bir yuvaya koyar, yerleşimi bekler ve ihlalleri döner.
func _audit(make: Callable, width: float, ui_scale: float) -> PackedStringArray:
	var ctx := UiContext.for_profile_name(&"touch", ui_scale)
	var holder := _holder(ctx, width)
	var panel: FlowPanel = make.call(ctx)
	holder.add_child(panel)
	panel.size = Vector2(width, 4000.0)
	await await_idle_frame()
	await await_idle_frame()
	var found := TouchAudit.violations(panel, width, MIN_TARGET)
	var gap := TouchAudit.min_button_gap(panel)
	if gap < MIN_GAP:
		found.append("düğmeler arası boşluk %.1f < %.0f" % [gap, MIN_GAP])
	var low := panel.joined_text().to_lower()
	for word: String in DESKTOP_ONLY_WORDS:
		if low.contains(word):
			found.append("dokunmatik panelde masaüstü ifadesi '%s'" % word)
	return found


func _assert_clean(label: String, make: Callable) -> void:
	for width: float in WIDTHS:
		for ui_scale: float in SCALES:
			var found: PackedStringArray = await _audit(make, width, ui_scale)
			assert_array(Array(found)).override_failure_message("%s w=%s ölçek=%s: %s" % [
					label, width, ui_scale, "; ".join(found)]).is_empty()


# --- denetim aracının kendisi (başarısız olabilir) ---

func test_audit_flags_overflow_clipping_small_targets_and_tight_gaps() -> void:
	var ctx := UiContext.for_profile_name(&"touch")
	var holder := _holder(ctx, 320.0)
	var box := VBoxContainer.new()
	holder.add_child(box)
	var wide := UiFactory.button(ctx, "Çok uzun bir Türkçe düğme etiketi taşmaya zorlanıyor, gerçekten uzun", true)
	var tiny := Button.new()
	tiny.text = "x"
	tiny.custom_minimum_size = Vector2(20.0, 20.0)
	tiny.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		tiny.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	var clipped := Label.new()
	clipped.text = "Kesilen tek satır etiket, panelden geniş olacak kadar uzun yazılmış"
	box.add_child(wide)
	box.add_child(tiny)
	box.add_child(clipped)
	box.size = Vector2(320.0, 400.0)
	await await_idle_frame()
	var found := "; ".join(TouchAudit.violations(box, 320.0, MIN_TARGET))
	assert_str(found).contains("asgari genişliği")
	assert_str(found).contains("hedefi")
	assert_float(TouchAudit.min_button_gap(box)).is_less(MIN_GAP)


# --- gündem seçenek kartları (gerçek PE-01 öğesi) ---

func test_agenda_option_cards_fit_narrow_touch_slots_with_safe_spacing() -> void:
	var h: PoliticsHandle = _world()["handle"]
	h.facade.advance(14)
	var view: AgendaItemView = h.facade.agenda_items()[0]
	assert_int(view.options.size()).override_failure_message("sim seçenek vermedi").is_greater(0)
	await _assert_clean("gündem", func(ctx: UiContext) -> FlowPanel: return AgendaPanel.create(ctx, h.facade))


func test_agenda_locked_option_states_its_reason_in_text_not_in_a_tooltip() -> void:
	var h: PoliticsHandle = _world()["handle"]
	h.facade.advance(14)
	var ctx := UiContext.for_profile_name(&"touch")
	var holder := _holder(ctx, 520.0)
	var panel := AgendaPanel.create(ctx, h.facade)
	holder.add_child(panel)
	var view: AgendaItemView = h.facade.agenda_items()[0]
	for ov in view.options:
		if ov.available:
			continue
		var b := panel.named_buttons("choose_%s_%s" % [view.ref(), ov.option_id])[0]
		assert_bool(b.disabled).is_true()
		assert_str(b.tooltip_text).is_empty()   # bilgi hover'a bağlı değil
		assert_str(panel.joined_text()).contains("Kilitli")
	for b in panel.buttons():
		assert_str(b.text).is_not_empty()


# --- meclis oylama nedenleri ---

func _council(advance: int) -> MockSimFacade:
	var f := FlowTestSupport.mock("ui_mock_council_why")
	f.submit_command(SimCommand.budget_propose({&"budget.line.roads": 45000}))
	f.advance(advance)
	return f


func test_council_why_section_and_buttons_fit_narrow_touch_slots() -> void:
	var resolved := _council(6)
	await _assert_clean("meclis (sonuçlandı)", func(ctx: UiContext) -> FlowPanel:
			return CouncilPanel.create(ctx, resolved))
	var pending := _council(1)
	await _assert_clean("meclis (açık)", func(ctx: UiContext) -> FlowPanel:
			return CouncilPanel.create(ctx, pending))


func test_council_why_texts_are_all_visible_without_hover() -> void:
	var ctx := UiContext.for_profile_name(&"touch")
	var holder := _holder(ctx, 389.0)
	var panel := CouncilPanel.create(ctx, _council(6))
	holder.add_child(panel)
	var text := panel.joined_text()
	for needle in ["Hayıra çeken etkenler", "Evete çeken etkenler", "Mali kaygı", "5 üye aleyhine, 1 üye lehine",
			"altyapı doluluğu binde 940"]:
		assert_str(text).contains(needle)


# --- M2 sonuç paneli ---

func test_m2_result_panel_fits_narrow_touch_windows() -> void:
	for case: Array in [[Vector2(360, 900), 1.0], [Vector2(744, 1133), 1.0], [Vector2(1133, 744), 1.0],
			[Vector2(744, 1133), 1.5]]:
		var window: Vector2 = case[0]
		var h := M2RenderSupport.handle(M2RenderSupport.UNFAVORABLE)
		var f := h.facade
		var proj := M2RenderSupport.projector(f)
		var ids := M2RenderSupport.free_parcels(proj, 3, true)
		f.advance(2)
		var hud := HudRoot.new()
		add_child(hud)
		hud.set_anchors_preset(Control.PRESET_TOP_LEFT)
		hud.setup(f, UiTestSupport.platform(&"touch", {"ui_scale": case[1]}))
		hud.size = window
		hud.refresh()
		auto_free(hud)
		var results := M2Results.attach(hud, f)
		f.submit_command(SimCommand.zoning_propose(ids, &"zone.mixed"))
		results.track_parcels(ids)
		for i in 160:
			f.advance(1)
			if results.build_model().primary != null and results.build_model().primary.decision != 0:
				break
		hud.refresh()
		results.open()
		await await_idle_frame()
		await await_idle_frame()
		var panel := results.results_panel()
		assert_object(panel).is_not_null()
		var found := TouchAudit.violations(panel, panel.size.x, MIN_TARGET)
		var gap := TouchAudit.min_button_gap(panel)
		if gap < MIN_GAP:
			found.append("düğmeler arası boşluk %.1f" % gap)
		assert_array(Array(found)).override_failure_message("M2 %s ölçek %s: %s" % [
				window, case[1], "; ".join(found)]).is_empty()


# --- yol çizim paneli ---

func _road_tool() -> Array:
	var run := P.setup()
	var facade: SimFacadeImpl = run["facade"]
	var tool := RoadDrawTool.create(run["net"], facade)
	tool.activate()
	return [facade, tool]


func test_road_panel_steps_fit_narrow_touch_slots_with_safe_spacing() -> void:
	var rt := _road_tool()
	var facade: SimFacadeImpl = rt[0]
	var tool: RoadDrawTool = rt[1]
	var make := func(ctx: UiContext) -> FlowPanel: return RoadDrawPanel.create(ctx, facade, tool)
	await _assert_clean("yol (A seç)", make)
	tool.tap_at(P.GRID_ORIGIN, 5.0)
	tool.tap_at(NORTH, 1.0)
	assert_bool(tool.can_confirm()).override_failure_message("taslak onaylanabilir olmalı").is_true()
	await _assert_clean("yol (inceleme)", make)
	tool.cancel()
	tool.tap_at(P.GRID_ORIGIN, 5.0)
	tool.tap_at(P.GRID_ORIGIN + Vector2(3.0, 0.0), 1.0)
	assert_bool(tool.is_valid()).is_false()
	await _assert_clean("yol (geçersiz)", make)


func test_road_panel_expropriation_offer_fits_narrow_touch_slots() -> void:
	var facade := UiTestSupport.mock("mock_scenario_expropriation")
	var tool := RoadDrawTool.create(P.network(), facade)
	tool.activate()
	tool.start = Vector2(-450.0, 210.0)
	tool.end = Vector2(-450.0, 110.0)
	tool.step = RoadDrawTool.Step.REVIEW
	tool.refresh_if_graph_changed()
	assert_bool(tool.offer().is_empty()).override_failure_message("sim teklif vermedi").is_false()
	var make := func(ctx: UiContext) -> FlowPanel: return RoadDrawPanel.create(ctx, facade, tool)
	await _assert_clean("yol (kamulaştırma teklifi)", make)
	tool.accept_offer()
	await _assert_clean("yol (teklif kabul)", make)


# --- UI girdiyi dünyadan önce tüketir (dokunma) ---

## Dünya katmanının (`_unhandled_input`) duyduğu BASIŞ/SÜRÜKLEME olaylarını sayar. Eşleşmeyen bırakma sayılmaz: panel
## basışta yeniden çizilip düğmeyi attıysa bırakma dünyaya düşebilir; dokunmatik profil izlenmeyen bırakmayı yok sayar
## (`TouchInputProfile._on_touch`), yani seçim üretmez.
class InputProbe:
	extends Node
	var hits: int = 0
	var seen: PackedStringArray = PackedStringArray()

	func _unhandled_input(event: InputEvent) -> void:
		var touch := event as InputEventScreenTouch
		var mouse := event as InputEventMouseButton
		if (touch != null and touch.pressed) or event is InputEventScreenDrag or (mouse != null and mouse.pressed):
			hits += 1
			seen.append(event.as_text())


func _touch(pressed: bool, pos: Vector2) -> InputEventScreenTouch:
	var e := InputEventScreenTouch.new()
	e.index = 0
	e.pressed = pressed
	e.position = pos
	return e


func _drag(pos: Vector2) -> InputEventScreenDrag:
	var e := InputEventScreenDrag.new()
	e.index = 0
	e.position = pos
	e.relative = Vector2(0.0, -12.0)
	return e


func _mouse(pressed: bool, pos: Vector2) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = MOUSE_BUTTON_LEFT
	e.pressed = pressed
	e.position = pos
	e.global_position = pos
	return e


## Panelin kapladığı bölgede (başlık, boş/etiket alanı, düğme) dokunma/sürükleme/emüle fare dünyaya SIZMAZ; panel dışı
## boş harita noktası sızar (kontrol: probe çalışıyor).
func _assert_world_does_not_hear_panel(f: SimFacade, opener: Callable, window: Vector2, label: String) -> void:
	var sub: SubViewport = auto_free(SubViewport.new())
	sub.size = Vector2i(window)
	add_child(sub)
	var hud := HudRoot.new()
	hud.set_anchors_preset(Control.PRESET_TOP_LEFT)
	sub.add_child(hud)
	var probe := InputProbe.new()   # HUD'dan SONRA: dünya katmanı gibi, HUD'un tüketmediği girdiyi alır
	sub.add_child(probe)
	hud.setup(f, UiTestSupport.platform(&"touch"))
	hud.size = window
	hud.refresh()
	opener.call(hud)
	await get_tree().process_frame
	await get_tree().process_frame
	var panel_rect := hud.panel.get_global_rect()
	var points: Array[Vector2] = [panel_rect.position + Vector2(panel_rect.size.x * 0.5, 6.0),
			panel_rect.get_center(), panel_rect.end - Vector2(6.0, 6.0)]
	for b in UiTestSupport.visible_buttons(hud.panel):
		if panel_rect.encloses(b.get_global_rect()) and b != hud.panel.close_button():
			points.append(b.get_global_rect().get_center())
	for p in points:
		sub.push_input(_touch(true, p))
		sub.push_input(_drag(p + Vector2(0.0, -10.0)))
		sub.push_input(_touch(false, p))
		sub.push_input(_mouse(true, p))
		sub.push_input(_mouse(false, p))
	await get_tree().process_frame
	assert_int(probe.hits).override_failure_message("%s: panel üstü girdi dünyaya geçti (%d olay): %s" % [
			label, probe.hits, "; ".join(probe.seen)]).is_equal(0)
	var free_point := hud.free_map_rect().get_center()
	assert_bool(panel_rect.has_point(free_point)).override_failure_message("sınama noktası panelde").is_false()
	sub.push_input(_touch(true, free_point))
	sub.push_input(_touch(false, free_point))
	await get_tree().process_frame
	assert_int(probe.hits).override_failure_message("%s: boş harita dokunuşu dünyaya ulaşmadı" % label).is_greater(0)


func test_touch_on_every_panel_never_reaches_the_world() -> void:
	for window: Vector2 in [Vector2(1133, 744), Vector2(744, 1133)]:
		var council_f := _council(6)
		await _assert_world_does_not_hear_panel(council_f, func(hud: HudRoot) -> void:
				DecisionPanels.attach(hud, council_f).open_council(), window, "meclis %s" % window)
		await _assert_world_does_not_hear_panel(council_f, func(hud: HudRoot) -> void:
				DecisionPanels.attach(hud, council_f).open_agenda(), window, "gündem %s" % window)
		var m2_f := UiTestSupport.mock()
		await _assert_world_does_not_hear_panel(m2_f, func(hud: HudRoot) -> void:
				M2Results.attach(hud, m2_f).open(), window, "M2 %s" % window)
		var rt := _road_tool()
		var tool: RoadDrawTool = rt[1]
		tool.tap_at(P.GRID_ORIGIN, 5.0)
		tool.tap_at(NORTH, 1.0)
		await _assert_world_does_not_hear_panel(rt[0], func(hud: HudRoot) -> void:
				hud.open_panel(&"road_draw", &"road.title", func(ctx: UiContext) -> Control:
						return RoadDrawPanel.create(ctx, rt[0], tool)), window, "yol %s" % window)
