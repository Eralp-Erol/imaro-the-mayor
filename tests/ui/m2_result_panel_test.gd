extends GdUnitTestSuite
## T-040 ölçüt 2/5/6 (HUD payı) · "Döngü sonucu" paneli GERÇEK facade ile (PoliticsBootstrap: ekonomi + aktör + siyaset;
## küçük sentetik dünya, tests/game/m2_render_support.gd): olumlu karar (onay -> inşaat -> tamam) ve olumsuz karar
## (kodlu ret) metinleri, fark değerlerinin sim ile BİREBİR eşitliği, belediye geliri "kurulmadı" satırı, mock'ta
## dürüst durum, grup tepkisi satırı, "Nedenini gör" -> ReasonPanel, panel açıkken kamera/HUD girdisi (gerçek viewport
## push_input) ve 480/1024/1600 px yerleşim. Zorlanmış sonuç yok: yalnız başlangıç koşulları ve oyuncu komutu veridir.
## Sentetik girdi olayları gerçek fare/dokunma denemesi DEĞİLDİR.

const DESKTOP := Vector2(1600, 900)
const ISOLATE := M2RenderSupport.ISOLATE
const FREE_SPOT := Vector2(1000.0, 400.0)
const SIM_CODE_TO_CAUSE := {
	"zoning_not_buildable": &"zoning", "infrastructure_exhausted": &"infrastructure",
	"insufficient_financing": &"financing", "demand_too_low": &"demand", "return_too_low": &"return",
}

var _world: WorldData
var _selects: Array[Vector2] = []


func before() -> void:
	_world = WorldTestSupport.coarse(WorldTestSupport.control())


func before_test() -> void:
	M2Results.default_interval_msec = 0  # testler adım adım ilerler; yenileme sınırı kapalı
	UiText.reset()
	UiText.report_missing = false
	_selects = []


func after_test() -> void:
	UiText.reset()


# --- kurulum ---

func _hud(facade: SimFacade, profile_name: StringName = &"desktop", window: Vector2 = DESKTOP) -> HudRoot:
	var hud := HudRoot.new()
	add_child(hud)
	hud.setup(facade, UiTestSupport.platform(profile_name))
	hud.set_anchors_preset(Control.PRESET_TOP_LEFT)
	hud.size = window
	hud.refresh()
	return auto_free(hud)


## Gerçek sim + HUD + sahip. `proposals`: önerilecek boş parsel sayısı (0: öneri yok).
func _scene(patch: Dictionary, proposals: int, profile_name: StringName = &"desktop",
		window: Vector2 = DESKTOP) -> Dictionary:
	var h := M2RenderSupport.handle(patch)
	var f := h.facade
	var proj := M2RenderSupport.projector(f)
	var ids := M2RenderSupport.free_parcels(proj, proposals, true)
	f.advance(2)
	var hud := _hud(f, profile_name, window)
	var results := M2Results.attach(hud, f)
	if proposals > 0:
		var r := f.submit_command(SimCommand.zoning_propose(ids, &"zone.mixed"))
		assert_bool(r.is_rejected()).override_failure_message("imar önerisi reddedildi").is_false()
		results.track_parcels(ids)
	return {"facade": f, "hud": hud, "results": results, "ids": ids}


func _step(scene: Dictionary, days: int) -> void:
	var f: SimFacade = scene["facade"]
	f.advance(days)
	(scene["hud"] as HudRoot).refresh()


func _until(scene: Dictionary, development: StringName, max_days: int = 220) -> ParcelView:
	var f: SimFacade = scene["facade"]
	for i in max_days:
		for v in f.parcel_views(scene["ids"]):
			if v.development == development:
				return v
		_step(scene, 1)
	return null


func _panel(scene: Dictionary) -> M2ResultPanel:
	var p := (scene["results"] as M2Results).results_panel()
	assert_object(p).override_failure_message("sonuç paneli açık değil").is_not_null()
	return p


func _rows(panel: Node, role: String) -> Array[Control]:
	var out: Array[Control] = []
	_collect_rows(panel, role, out)
	return out


func _collect_rows(node: Node, role: String, out: Array[Control]) -> void:
	for child in node.get_children():
		var c := child as Control
		if c == null or not c.visible:
			continue
		if String(c.get_meta(M2ResultPanel.META_ROW, "")) == role:
			out.append(c)
		_collect_rows(c, role, out)


## Ölçüm satırının sağdaki değeri (sol başlık metne göre).
func _metric_text(panel: M2ResultPanel, caption_key: StringName) -> String:
	var caption := UiText.t(caption_key)
	for row in _rows(panel, M2ResultPanel.ROW_METRIC):
		var labels: Array[String] = []
		for child in row.get_children():
			if child is Label:
				labels.append((child as Label).text)
		if labels.size() >= 2 and labels[0] == caption:
			return labels[1]
	return ""


# --- olumlu yol ---

func test_positive_path_shows_approval_progress_and_exact_deltas() -> void:
	var scene := _scene(ISOLATE, 6)
	var f: SimFacade = scene["facade"]
	var results: M2Results = scene["results"]
	assert_bool(results.is_open()).override_failure_message("öneri sonrası panel kendiliğinden açılmalı").is_true()
	assert_bool(results.baseline != null).override_failure_message("ekonomi kuruluyken başlangıç alınmalı").is_true()
	assert_str(_panel(scene).joined_text()).contains(UiText.t(&"m2.investor.none"))
	# inşaat sürerken
	var building := _until(scene, ParcelView.DEVELOPMENT_UNDER_CONSTRUCTION)
	assert_object(building).override_failure_message("hiçbir proje inşaata geçmedi").is_not_null()
	var panel := _panel(scene)
	var m: M2ResultModel = panel.model
	assert_object(m.primary).is_not_null()
	var shown := m.primary.view
	assert_str(panel.joined_text()).contains(UiText.t(M2ResultModel.stage_key(shown.development)))
	assert_int(m.primary.decision).is_equal(M2ResultModel.Decision.APPROVED)
	var approved := UiText.t(&"m2.investor.approved", {"date": UiText.tick_date(m.primary.tick)})
	assert_str(panel.joined_text()).contains(approved)
	var pct := UiText.t(&"format.percent", {"value": UiText.number(shown.progress_pm / 10)})
	assert_str(panel.joined_text()).contains(pct)
	assert_str(panel.joined_text()).contains(UiText.t(&"m2.progress"))
	# yapımı süren birim sim ile aynı
	var o := f.economy_outcome()
	var reg := o.region(m.region_code)
	assert_int(m.pipeline_residential).is_equal(reg.residential_pipeline)
	assert_int(m.pipeline_commercial).is_equal(reg.commercial_pipeline)
	# tamam
	var done := _until(scene, ParcelView.DEVELOPMENT_BUILT)
	assert_object(done).override_failure_message("hiçbir proje tamamlanmadı").is_not_null()
	panel = _panel(scene)
	m = panel.model
	o = f.economy_outcome()
	var city := o.delta_since(results.baseline)
	var region := o.delta_since(results.baseline, m.region_code)
	assert_bool(m.baseline_valid).is_true()
	for key: StringName in [&"investments_approved", &"investments_declined", &"projects_completed", &"rent_income"]:
		assert_int(m.metric(key).delta).override_failure_message(str(key)).is_equal(city[String(key)])
	assert_int(m.metric(&"sim_residential_units").delta).is_equal(region["sim_residential_units"])
	assert_int(m.metric(&"sim_commercial_units").delta).is_equal(region["sim_commercial_units"])
	assert_int(m.metric(&"housed_households").delta).is_equal(region["housed_households"])
	assert_int(m.metric(&"housed_households").value).is_equal(o.metrics(m.region_code)["housed_households"])
	assert_int(m.metric(&"projects_completed").delta).is_greater(0)
	assert_int(m.metric(&"sim_residential_units").delta).is_greater(0)
	# ekranda görünen metin = sim farkı
	assert_str(_metric_text(panel, &"m2.metric.projects_completed")) \
			.is_equal(M2ResultPanel.delta_text(city["projects_completed"]))
	assert_str(_metric_text(panel, &"m2.metric.investments_approved")) \
			.is_equal(M2ResultPanel.delta_text(city["investments_approved"]))
	assert_str(_metric_text(panel, &"m2.metric.sim_residential_units")) \
			.is_equal(M2ResultPanel.delta_text(region["sim_residential_units"]))
	assert_str(_metric_text(panel, &"m2.metric.rent_income")).is_equal(M2ResultPanel.delta_money(city["rent_income"]))
	var base_text := UiText.t(&"m2.baseline.at", {"date": UiText.tick_date(results.baseline_tick)})
	assert_str(panel.joined_text()).contains(base_text)
	assert_array(Array(UiText.missing_keys())).is_empty()


func test_progress_bar_equals_sim_progress_for_the_shown_parcel() -> void:
	var scene := _scene(ISOLATE, 6)
	_until(scene, ParcelView.DEVELOPMENT_UNDER_CONSTRUCTION)
	_step(scene, 3)
	var panel := _panel(scene)
	var v: ParcelView = (scene["facade"] as SimFacade).parcel_views(PackedInt64Array([panel.model.primary.id()]))[0]
	var bars: Array[MeterBar] = []
	_collect_bars(panel, bars)
	var found := false
	for b in bars:
		if b.permille == v.progress_pm:
			found = true
	assert_bool(found).override_failure_message("ilerleme çubuğu progress_pm=%d ile eşleşmiyor" % v.progress_pm).is_true()


func _collect_bars(node: Node, out: Array[MeterBar]) -> void:
	for child in node.get_children():
		if child is MeterBar:
			out.append(child)
		_collect_bars(child, out)


# --- olumsuz yol ---

func test_negative_path_shows_coded_decline_cause_from_the_recorded_factors() -> void:
	var patch := ISOLATE.duplicate(true)
	patch.merge(M2RenderSupport.UNFAVORABLE, true)
	var scene := _scene(patch, 3)
	_step(scene, 60)
	var panel := _panel(scene)
	var m: M2ResultModel = panel.model
	assert_int(m.primary.decision).is_equal(M2ResultModel.Decision.DECLINED)
	var f: SimFacade = scene["facade"]
	var code := ""
	for e in f.events_since(0):
		if e.message_key == &"event.investor.declined" and e.subjects.has(String(m.primary.view.ref())):
			code = str(e.args.get("code", ""))
	assert_str(code).override_failure_message("sim ret olayı bulunamadı").is_not_empty()
	assert_str(String(m.primary.cause)).is_equal(String(SIM_CODE_TO_CAUSE[code]))
	var text := panel.joined_text()
	assert_str(text).contains(UiText.t(&"m2.investor.declined", {"date": UiText.tick_date(m.primary.tick)}))
	var cause_text := UiText.t(StringName("m2.decline.%s" % m.primary.cause))
	assert_str(text).contains(UiText.t(&"m2.decline.cause", {"cause": cause_text}))
	assert_str(text).contains(UiText.t(&"parcel.development.vacant"))
	assert_int(m.metric(&"investments_declined").delta).is_greater(0)
	assert_int(m.metric(&"projects_completed").delta).is_equal(0)


func test_decline_cause_matches_the_code_the_sim_recorded_in_real_runs() -> void:
	# Aynı koşullar sim kurallarından üç farklı ret kodu üretir (zorlama yok): talep, altyapı, imar. Neden artık
	# ParcelView.decision_code'dan okunur; sim'in `event.investor.declined` kodu ile eşit olmalı.
	var seen := {}
	for case: Array in [[&"zone.commercial", {}], [&"zone.mixed", M2RenderSupport.UNFAVORABLE],
			[&"zone.green", {}]]:
		var patch := ISOLATE.duplicate(true)
		patch.merge(case[1], true)
		var h := M2RenderSupport.handle(patch)
		var f := h.facade
		var ids := M2RenderSupport.free_parcels(M2RenderSupport.projector(f), 8)
		f.advance(2)
		assert_bool(f.submit_command(SimCommand.zoning_propose(ids, case[0])).is_rejected()).is_false()
		var cursor := 0
		for day in 60:
			f.advance(1)
			for e in f.events_since(cursor):
				cursor = e.seq
				if e.message_key != &"event.investor.declined":
					continue
				var code := str(e.args.get("code", ""))
				for v in f.parcel_views(ids):
					if not e.subjects.has(String(v.ref())):
						continue
					if v.decision != ParcelView.DECISION_DECLINED or v.decision_tick != e.tick:
						continue
					assert_str(String(v.decision_code)).is_equal(code)
					assert_str(String(M2ResultModel.cause_of_code(v.decision_code))).override_failure_message(
							"sim kodu %s, UI nedeni %s" % [code, M2ResultModel.cause_of_code(v.decision_code)]) \
							.is_equal(String(SIM_CODE_TO_CAUSE[code]))
					seen[code] = true
	assert_array(seen.keys()).contains_exactly_in_any_order(
			["demand_too_low", "infrastructure_exhausted", "zoning_not_buildable"])


func test_cause_of_code_table_covers_every_sim_code_and_never_invents() -> void:
	for code: String in SIM_CODE_TO_CAUSE:
		assert_str(String(M2ResultModel.cause_of_code(StringName(code)))).is_equal(String(SIM_CODE_TO_CAUSE[code]))
	assert_str(String(M2ResultModel.cause_of_code(&"approved"))).is_empty()
	assert_str(String(M2ResultModel.cause_of_code(&""))).is_empty()
	assert_str(String(M2ResultModel.cause_of_code(&"some_new_code"))).is_equal("unknown")


func test_decline_cause_is_empty_for_a_positive_decision() -> void:
	var scene := _scene(ISOLATE, 4)
	_until(scene, ParcelView.DEVELOPMENT_UNDER_CONSTRUCTION)
	var m: M2ResultModel = _panel(scene).model
	assert_int(m.primary.decision).is_equal(M2ResultModel.Decision.APPROVED)
	assert_str(String(m.primary.cause)).is_empty()
	assert_str(String(M2ResultModel.cause_of_code(m.primary.code))).is_empty()


# --- belediye geliri, mock, tepki ---

func test_municipal_revenue_row_is_honest_not_built() -> void:
	var scene := _scene(ISOLATE, 4)
	_step(scene, 5)
	var panel := _panel(scene)
	var o := (scene["facade"] as SimFacade).economy_outcome()
	assert_bool(o.municipal_revenue_available).is_false()
	var text := panel.joined_text()
	assert_str(text).contains(UiText.t(&"m2.row.municipal"))
	assert_str(text).contains(UiText.t(&"state.not_built_short"))
	assert_str(text).contains(UiText.t(o.municipal_revenue_reason_key))
	assert_str(text).contains(UiText.t(&"m2.row.rent_note"))
	for bad in ["₺", " TL"]:
		assert_bool(text.contains(bad)).is_false()
	assert_str(_metric_text(panel, &"m2.row.municipal")).is_equal(UiText.t(&"state.not_built_short"))


func test_mock_facade_gets_an_honest_state_and_no_invented_numbers() -> void:
	var mock := UiTestSupport.mock()
	var hud := _hud(mock)
	var results := M2Results.attach(hud, mock)
	results.open()
	var panel := results.results_panel()
	assert_object(panel).is_not_null()
	assert_bool(mock.economy_outcome().available).is_false()
	var text := panel.joined_text()
	assert_str(text).contains(UiText.t(&"m2.outcome.unavailable"))
	assert_str(text).contains(UiText.t(&"m2.parcel.none"))
	assert_bool(panel.badge.visible).is_true()
	assert_int(panel.model.metrics.size()).is_equal(0)
	assert_int(panel.model.counters.size()).is_equal(0)
	assert_array(Array(UiText.missing_keys())).is_empty()


func test_empty_state_before_any_proposal_shows_city_numbers_and_no_reaction() -> void:
	var scene := _scene(ISOLATE, 0)
	var results: M2Results = scene["results"]
	results.open()
	var panel := _panel(scene)
	assert_str(panel.joined_text()).contains(UiText.t(&"m2.parcel.none"))
	assert_str(panel.joined_text()).contains(UiText.t(&"m2.political.none"))
	assert_array(_rows(panel, M2ResultPanel.ROW_REACTION)).is_empty()


func test_group_reactions_are_listed_per_group_with_a_reason_button() -> void:
	var f := M2Support.stress_run(M2Support.SEED, 120)
	var hud := _hud(f)
	var results := M2Results.attach(hud, f)
	results.track_parcels(f.parcel_ids().slice(0, 3))
	var panel := results.results_panel()
	assert_object(panel).is_not_null()
	var snap := f.snapshot()
	var live := snap.group_reactions.filter(func(g: GroupReactionView) -> bool:
		return g.intensity > 0 or g.reaction != &"neutral")
	assert_int(live.size()).override_failure_message("sim grup tepkisi üretmedi").is_greater(0)
	var rows := _rows(panel, M2ResultPanel.ROW_REACTION)
	assert_int(rows.size()).is_equal(mini(live.size(), M2ResultModel.MAX_REACTION_ROWS))
	var text := panel.joined_text()
	for g: GroupReactionView in panel.model.reactions:
		assert_str(text).contains(UiText.actor_name(g.group))
		assert_str(text).contains(UiText.t(StringName("m2.reaction.%s" % g.reaction)))
		assert_str(text).contains(UiText.t(&"m2.political.stance", {"value": UiText.fixed(g.stance, true)}))
	# zıt yönde iki grup varsa ikisi de ayrı görünür; toplam skor yoktur
	for bad in ["mutluluk", "skor", "puan"]:
		assert_bool(text.to_lower().contains(bad)).is_false()
	var why := panel.named_buttons("why_group_")
	assert_int(why.size()).is_greater(0)
	why[0].pressed.emit()
	await await_idle_frame()
	assert_bool(results.reason_panel() != null).is_true()
	assert_str(String(results.hud.panel_id())).is_equal(String(M2Results.PANEL_REASON))
	assert_array(Array(UiText.missing_keys())).is_empty()


# --- gerekçe düğmesi ---

func test_why_button_opens_the_reason_panel_with_the_recorded_factors() -> void:
	var scene := _scene(ISOLATE, 6)
	_until(scene, ParcelView.DEVELOPMENT_UNDER_CONSTRUCTION)
	var results: M2Results = scene["results"]
	var sim: SimFacade = scene["facade"]
	var m: M2ResultModel = _panel(scene).model
	var why := _panel(scene).named_buttons("why_decision")
	assert_int(why.size()).is_equal(1)
	why[0].pressed.emit()
	await await_idle_frame()
	var rp := results.reason_panel()
	assert_object(rp).override_failure_message("ReasonPanel açılmadı").is_not_null()
	assert_str(String(results.hud.panel_id())).is_equal(String(M2Results.PANEL_REASON))
	var rec := sim.reason(m.primary.reason_id)
	assert_object(rec).override_failure_message("decision_reason_id günlükte yok").is_not_null()
	var texts: PackedStringArray = _all_texts(rp)
	var joined := " | ".join(texts)
	for f in rec.factors:
		assert_str(joined).override_failure_message("etken görünmüyor: %s" % f.name_key).contains(UiText.t(f.name_key))
	assert_array(Array(UiText.missing_keys())).is_empty()


func _all_texts(node: Node) -> PackedStringArray:
	var out := PackedStringArray()
	for child in node.get_children():
		var c := child as Control
		if c != null and not c.visible:
			continue
		if child is Label:
			out.append((child as Label).text)
		elif child is Button:
			out.append((child as Button).text)
		out.append_array(_all_texts(child))
	return out


# --- araç çubuğu ve açılış ---

func test_toolbar_tool_exists_only_when_registered_and_opens_the_panel() -> void:
	var mock := UiTestSupport.mock()
	var bare := _hud(mock)
	assert_object(bare.toolbar.tool_button(ModeToolbar.TOOL_RESULTS)) \
			.override_failure_message("kayıtsız araç görünmemeli").is_null()
	var hud := _hud(mock)
	var results := M2Results.attach(hud, mock)
	var button := hud.toolbar.tool_button(ModeToolbar.TOOL_RESULTS)
	assert_object(button).is_not_null()
	assert_str(button.text).is_equal(UiText.t(&"tool.results"))
	button.pressed.emit()
	assert_bool(results.is_open()).is_true()
	# profil değişince araç kalır
	hud.apply_profile(UiTestSupport.platform(&"touch"))
	assert_object(hud.toolbar.tool_button(ModeToolbar.TOOL_RESULTS)).is_not_null()


func test_an_open_panel_is_not_stolen_by_a_new_proposal() -> void:
	var scene := _scene(ISOLATE, 0)
	var hud: HudRoot = scene["hud"]
	var results: M2Results = scene["results"]
	hud.open_panel(&"probe", &"inspector.title", func(_c: UiContext) -> Control: return Label.new())
	var proj := M2RenderSupport.projector(scene["facade"])
	results.track_parcels(M2RenderSupport.free_parcels(proj, 2))
	assert_str(String(hud.panel_id())).is_equal("probe")
	assert_bool(results.is_open()).is_false()


# --- girdi ve yerleşim ---

func _rig_scene(facade: SimFacade) -> Dictionary:
	var rig: CameraRig = auto_free(CameraRig.new())
	rig.input_profile = InputProfile.create(&"desktop")
	rig.viewport_size_override = DESKTOP
	rig.smoothing_enabled = false
	add_child(rig)
	rig.set_world(_world, func(x: float, z: float) -> float: return maxf(_world.height_at(x, z), _world.sea_level))
	rig.apply_preset("district:D4")
	var layer: CanvasLayer = auto_free(CanvasLayer.new())
	add_child(layer)
	var hud := HudRoot.new()
	hud.set_anchors_preset(Control.PRESET_TOP_LEFT)
	layer.add_child(hud)
	hud.bind_input(rig.input_profile)
	hud.setup(facade, UiTestSupport.platform(&"desktop"))
	hud.size = DESKTOP
	hud.refresh()
	rig.input_profile.select_requested.connect(func(p: Vector2) -> void: _selects.append(p))
	return {"rig": rig, "hud": hud}


func _push(event: InputEvent) -> void:
	get_viewport().push_input(event)


func _key(code: Key, pressed: bool) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = code
	e.keycode = code
	e.pressed = pressed
	return e


func _mouse(index: MouseButton, pressed: bool, pos: Vector2) -> InputEventMouseButton:
	var e := InputEventMouseButton.new()
	e.button_index = index
	e.pressed = pressed
	e.position = pos
	e.global_position = pos
	return e


func test_camera_and_hud_input_keep_working_while_the_panel_is_open() -> void:
	var h := M2RenderSupport.handle(ISOLATE)
	var f := h.facade
	f.advance(2)
	var s := _rig_scene(f)
	var rig: CameraRig = s["rig"]
	var hud: HudRoot = s["hud"]
	var results := M2Results.attach(hud, f)
	results.open()
	await get_tree().process_frame
	assert_bool(results.is_open()).is_true()
	# kamera tuşu
	var before := rig.current_state().copy()
	_push(_key(KEY_W, true))
	for i in 5:
		rig._process(0.1)
	_push(_key(KEY_W, false))
	assert_float(rig.current_state().focus_xz().distance_to(before.focus_xz())).is_greater(1.0)
	# tekerlek
	var d0 := rig.distance()
	_push(_mouse(MOUSE_BUTTON_WHEEL_UP, true, FREE_SPOT))
	assert_float(rig.distance()).is_less(d0)
	# boş dünya tıklaması seçer; panel açık kalır
	_push(_mouse(MOUSE_BUTTON_LEFT, true, FREE_SPOT))
	_push(_mouse(MOUSE_BUTTON_LEFT, false, FREE_SPOT))
	assert_array(_selects).is_equal([FREE_SPOT])
	assert_bool(results.is_open()).is_true()
	# Boşluk duraklatır
	var start := f.speed()
	_push(_key(KEY_SPACE, true))
	_push(_key(KEY_SPACE, false))
	assert_int(f.speed()).is_not_equal(start)
	# Esc (iptal fiili) sabitlenmemiş paneli kapatır
	var cancel := _key(KEY_ESCAPE, true)
	_push(cancel)
	_push(_key(KEY_ESCAPE, false))
	hud.close_panel_soft()
	assert_bool(results.is_open()).is_false()


func test_layout_stays_inside_the_panel_at_480_1024_1600_px() -> void:
	for case: Array in [[&"desktop", Vector2(1600, 900)], [&"desktop", Vector2(1024, 700)],
			[&"touch", Vector2(480, 900)], [&"touch", Vector2(1024, 768)], [&"touch", Vector2(834, 1194)],
			[&"touch", Vector2(1366, 1024)]]:
		var window: Vector2 = case[1]
		var scene := _scene(ISOLATE, 6, case[0], window)
		_until(scene, ParcelView.DEVELOPMENT_UNDER_CONSTRUCTION)
		var hud: HudRoot = scene["hud"]
		await await_idle_frame()
		await await_idle_frame()
		var panel := _panel(scene)
		var shell := hud.panel.get_global_rect().grow(1.0)
		var whole := Rect2(Vector2.ZERO, window).grow(1.0)
		assert_bool(whole.encloses(hud.panel.get_global_rect())).override_failure_message(
				"panel çerçeve dışında %s (%s)" % [hud.panel.get_global_rect(), window]).is_true()
		var min_target := 44.0 if case[0] == &"touch" else 32.0
		for b in UiTestSupport.visible_buttons(panel):
			var hit := UiFactory.hit_size(b)
			assert_float(minf(hit.x, hit.y)).override_failure_message(
					"'%s' hedefi %s (%s)" % [b.text, hit, window]).is_greater_equal(min_target)
		# yatay taşma yok: panel içindeki her görünür kontrol panelin yatay aralığında
		var overflow := _horizontal_overflow(panel, shell)
		assert_str(overflow).override_failure_message("%s: %s" % [window, overflow]).is_empty()
		# etiketler kesilmiyor: otomatik satır sarma açık, tek satır etiketler sığıyor
		assert_str(_clipped_label(panel, shell)).override_failure_message(
				"%s: %s" % [window, _clipped_label(panel, shell)]).is_empty()


func _horizontal_overflow(node: Node, shell: Rect2) -> String:
	for child in node.get_children():
		var c := child as Control
		if c != null and c.is_visible_in_tree():
			var r := c.get_global_rect()
			if r.size.x > 0.0 and (r.position.x < shell.position.x or r.end.x > shell.end.x):
				return "%s %s panel %s dışına taştı" % [c.get_class(), r, shell]
		var inner := _horizontal_overflow(child, shell)
		if not inner.is_empty():
			return inner
	return ""


func _clipped_label(node: Node, shell: Rect2) -> String:
	for child in node.get_children():
		var l := child as Label
		if l != null and l.is_visible_in_tree() and l.text.length() > 0:
			var need := l.get_combined_minimum_size()
			if l.autowrap_mode == TextServer.AUTOWRAP_OFF and need.x > shell.size.x:
				return "'%s' tek satırda %s px, panel %s" % [l.text, need.x, shell.size.x]
			if l.size.x + 1.0 < need.x and l.autowrap_mode == TextServer.AUTOWRAP_OFF:
				return "'%s' kesik: boyut %s < gereken %s" % [l.text, l.size.x, need.x]
		var inner := _clipped_label(child, shell)
		if not inner.is_empty():
			return inner
	return ""


## Gerçek GUI olay yayılımı: ana test penceresi 64x64 olduğundan 1600x900'lük bir SubViewport içinde, düğme merkezine
## push_input (hover + basma + bırakma). Sentetik olay; gerçek fare/dokunma denemesi DEĞİLDİR.
func test_panel_buttons_work_through_real_gui_event_propagation() -> void:
	var h := M2RenderSupport.handle(ISOLATE)
	var f := h.facade
	var proj := M2RenderSupport.projector(f)
	var ids := M2RenderSupport.free_parcels(proj, 6, true)
	f.advance(2)
	var sub: SubViewport = auto_free(SubViewport.new())
	sub.size = Vector2i(1600, 900)
	add_child(sub)
	var hud := HudRoot.new()
	hud.set_anchors_preset(Control.PRESET_TOP_LEFT)
	sub.add_child(hud)
	hud.setup(f, UiTestSupport.platform(&"desktop"))
	hud.size = DESKTOP
	var results := M2Results.attach(hud, f)
	f.submit_command(SimCommand.zoning_propose(ids, &"zone.mixed"))
	results.track_parcels(ids)
	for i in 160:
		f.advance(1)
		if results.build_model().primary != null and results.build_model().primary.decision != 0:
			break
	hud.refresh()
	await get_tree().process_frame
	await get_tree().process_frame
	var why := results.results_panel().named_buttons("why_decision")
	assert_int(why.size()).is_equal(1)
	var center := why[0].get_global_rect().get_center()
	var hover := InputEventMouseMotion.new()
	hover.position = center
	hover.global_position = center
	sub.push_input(hover)
	await get_tree().process_frame
	var press := _mouse(MOUSE_BUTTON_LEFT, true, center)
	var release := _mouse(MOUSE_BUTTON_LEFT, false, center)
	sub.push_input(press)
	sub.push_input(release)
	await get_tree().process_frame
	assert_str(String(hud.panel_id())).override_failure_message("tıklama ReasonPanel'i açmadı").is_equal(
			String(M2Results.PANEL_REASON))
	# araç çubuğu düğmesi de aynı yoldan çalışır: İmar > Döngü sonucu
	var tool := hud.toolbar.tool_button(ModeToolbar.TOOL_RESULTS)
	var tc := tool.get_global_rect().get_center()
	var tover := InputEventMouseMotion.new()
	tover.position = tc
	tover.global_position = tc
	sub.push_input(tover)
	await get_tree().process_frame
	sub.push_input(_mouse(MOUSE_BUTTON_LEFT, true, tc))
	sub.push_input(_mouse(MOUSE_BUTTON_LEFT, false, tc))
	await get_tree().process_frame
	assert_bool(results.is_open()).override_failure_message("araç çubuğu tıklaması paneli açmadı").is_true()
