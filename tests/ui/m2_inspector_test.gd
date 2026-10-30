extends GdUnitTestSuite
## T-041 ölçüt 1-6 (UI payı) · Parsel/bölge denetçisi GERÇEK facade ile (PoliticsBootstrap, küçük sentetik dünya;
## tests/game/m2_render_support.gd): karar -> gerekçe -> yapı -> tepki zinciri tek panelde, sokak/mahalle/ilçe
## bantlarında AYNI veri, olumsuz durumlar (boş seçim, olmayan parsel, budanmış gerekçe), ham anahtar yok,
## 480-1600 px yerleşim ve dokunmatik >= 44 hedef. Sentetik girdi gerçek dokunma denemesi DEĞİLDİR.

const DESKTOP := Vector2(1600, 900)
const ISOLATE := M2RenderSupport.ISOLATE
const STREET := &"street"
const NEIGHBORHOOD := &"neighborhood"
const DISTRICT := &"district"

var _reasons_asked: Array[Callable] = []
var _zoning_asked: Array[int] = []


func before_test() -> void:
	InspectorHost.default_interval_msec = 0
	M2Results.default_interval_msec = 0
	UiText.reset()
	UiText.report_missing = false
	_reasons_asked = []
	_zoning_asked = []


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


## Gerçek sim + HUD + denetçi sahibi. `proposals` > 0: boş parsellere imar önerisi verilir.
func _scene(patch: Dictionary, proposals: int, profile_name: StringName = &"desktop",
		window: Vector2 = DESKTOP, sim_config: SimConfig = null) -> Dictionary:
	var h := M2RenderSupport.handle(patch, M2RenderSupport.SEED, sim_config)
	var f := h.facade
	var ids := M2RenderSupport.free_parcels(M2RenderSupport.projector(f), proposals, true)
	f.advance(2)
	var hud := _hud(f, profile_name, window)
	var host := InspectorHost.attach(hud, f, func(c: Callable) -> void: _reasons_asked.append(c),
			func(id: int) -> void: _zoning_asked.append(id))
	if proposals > 0:
		var r := f.submit_command(SimCommand.zoning_propose(ids, &"zone.mixed"))
		assert_bool(r.is_rejected()).override_failure_message("imar önerisi reddedildi").is_false()
	return {"facade": f, "hud": hud, "host": host, "ids": ids}


func _step(scene: Dictionary, days: int) -> void:
	(scene["facade"] as SimFacade).advance(days)
	(scene["hud"] as HudRoot).refresh()


func _until_development(scene: Dictionary, development: StringName, max_days: int = 220) -> ParcelView:
	var f: SimFacade = scene["facade"]
	for i in max_days:
		for v in f.parcel_views(scene["ids"]):
			if v.development == development:
				return v
		_step(scene, 1)
	return null


func _show(scene: Dictionary, parcel_id: int, band: StringName) -> InspectorPanel:
	var host: InspectorHost = scene["host"]
	host.set_band(band)
	host.select_parcel(parcel_id)
	var p := host.panel()
	assert_object(p).override_failure_message("denetçi paneli açık değil").is_not_null()
	return p


func _rows(node: Node, role: String, out: Array[Control] = []) -> Array[Control]:
	for child in node.get_children():
		var c := child as Control
		if c == null or not c.visible:
			continue
		if String(c.get_meta(InspectorPanel.META_ROW, "")) == role:
			out.append(c)
		_rows(c, role, out)
	return out


# --- model: bant -> ayrıntı, boş / olmayan parsel ---

func test_band_maps_to_detail_and_unknown_bands_fall_back_to_the_region_summary() -> void:
	assert_int(InspectorModel.detail_for_band(STREET)).is_equal(InspectorModel.Detail.PARCEL)
	assert_int(InspectorModel.detail_for_band(NEIGHBORHOOD)).is_equal(InspectorModel.Detail.SUMMARY)
	assert_int(InspectorModel.detail_for_band(DISTRICT)).is_equal(InspectorModel.Detail.REGION)
	assert_int(InspectorModel.detail_for_band(&"metro")).is_equal(InspectorModel.Detail.REGION)
	assert_int(InspectorModel.detail_for_band(&"")).is_equal(InspectorModel.Detail.PARCEL)


func test_empty_selection_and_unknown_parcel_give_explanatory_states_without_errors() -> void:
	var scene := _scene(ISOLATE, 0)
	var f: SimFacade = scene["facade"]
	assert_int(InspectorModel.build(f, -1, STREET).state).is_equal(InspectorModel.State.EMPTY)
	assert_int(InspectorModel.build(f, 0, STREET).state).is_equal(InspectorModel.State.EMPTY)
	assert_int(InspectorModel.build(f, 987654321, STREET).state).is_equal(InspectorModel.State.MISSING)
	var host: InspectorHost = scene["host"]
	# kapalıyken boş tıklama paneli açmaz
	host.select_parcel(-1)
	assert_bool(host.is_open()).is_false()
	var some := f.parcel_ids()[0]
	var panel := _show(scene, some, STREET)
	host.select_parcel(-1)
	assert_str(panel.joined_text()).contains(UiText.t(&"inspector.empty_hint"))
	host.select_parcel(987654321)
	var text := host.panel().joined_text()
	assert_str(text).contains(UiText.t(&"inspector.missing", {"id": 987654321}))
	assert_int(host.panel().named_buttons("zoning").size()).override_failure_message(
			"olmayan parselde imar düğmesi olmamalı").is_equal(0)
	assert_array(Array(UiText.missing_keys())).is_empty()


func test_empty_click_does_not_steal_another_open_panel() -> void:
	var scene := _scene(ISOLATE, 0)
	var hud: HudRoot = scene["hud"]
	hud.open_panel(&"probe", &"inspector.title", func(_c: UiContext) -> Control: return Label.new())
	(scene["host"] as InspectorHost).select_parcel(-1)
	assert_str(String(hud.panel_id())).is_equal("probe")


# --- olumlu zincir ---

func test_street_band_reads_the_whole_chain_from_the_facade() -> void:
	var scene := _scene(ISOLATE, 6)
	var f: SimFacade = scene["facade"]
	var building := _until_development(scene, ParcelView.DEVELOPMENT_UNDER_CONSTRUCTION)
	assert_object(building).override_failure_message("hiçbir proje inşaata geçmedi").is_not_null()
	var panel := _show(scene, building.id, STREET)
	var text := panel.joined_text()
	var v: ParcelView = f.parcel_views(PackedInt64Array([building.id]))[0]
	# 1 imar + parsel gerçekleri
	assert_str(text).contains(UiText.t(&"m2.zoning.effective", {"zone": UiText.humanize(String(v.zone))}))
	var land := UiText.money(v.land_value) if v.land_value > 0 else UiText.t(&"inspector.land_value.unset")
	assert_str(text).contains(land)
	if v.land_value <= 0:
		assert_bool(text.contains(UiText.money(0))).override_failure_message("0 arsa değeri para gibi yazılmamalı").is_false()
	assert_str(text).contains(UiText.actor_name(v.owner))
	assert_str(text).contains(UiText.t(&"format.area_m2", {"value": UiText.number(v.area_m2)}))
	# 2 karar + gerekçe etkenleri (kayıttan)
	assert_str(text).contains(UiText.t(&"m2.investor.approved", {"date": UiText.tick_date(v.decision_tick)}))
	var model := panel.model
	assert_object(model.record).override_failure_message("yatırımcı kararı kaydı okunamadı").is_not_null()
	assert_str(String(model.record.decision_key)).is_equal("decision.investor.develop")
	assert_int(model.record.id).is_equal(v.decision_reason_id)
	assert_int(_rows(panel, InspectorPanel.ROW_FACTOR).size()).is_between(1, InspectorModel.MAX_FACTORS)
	for fr in model.factors:
		assert_str(text).contains(UiText.t(fr.name_key))
	# 3 yapı + ilerleme
	assert_str(text).contains(UiText.t(M2ResultModel.stage_key(v.development)))
	assert_str(text).contains(UiText.t(&"format.percent", {"value": UiText.number(v.progress_pm / 10)}))
	assert_str(text).contains(UiText.t(&"m2.stage.line", {"stage": UiText.t(M2ResultModel.stage_key(v.development)),
			"use": UiText.t(StringName("zoning.use.%s" % v.use)), "units": v.units}))
	# 4 sonuç: bölge ölçümü sim ile birebir
	var region := f.economy_outcome().metrics(v.region_code)
	assert_str(text).contains(UiText.t(&"m2.row.housed_value",
			{"housed": UiText.number(int(region["housed_households"])), "total": UiText.number(int(region["households"]))}))
	# belediye geliri (bölge özeti = ilçe bandı): kurulu değilse dürüst satır, sahte para yok
	var far := _show(scene, building.id, DISTRICT).joined_text()
	assert_str(far).contains(UiText.t(&"m2.row.municipal"))
	if not f.economy_outcome().municipal_revenue_available:
		assert_str(far).contains(UiText.t(&"state.not_built_short"))
		assert_str(far).contains(UiText.t(f.economy_outcome().municipal_revenue_reason_key))
	for bad in ["₺", " TL", "mutluluk", "skor", "puan"]:
		assert_bool(text.to_lower().contains(bad.to_lower())).override_failure_message(bad).is_false()
	assert_array(Array(UiText.missing_keys())).is_empty()


func test_same_selection_shows_the_same_data_in_street_neighborhood_and_district_bands() -> void:
	var scene := _scene(ISOLATE, 6)
	var f: SimFacade = scene["facade"]
	var building := _until_development(scene, ParcelView.DEVELOPMENT_UNDER_CONSTRUCTION)
	assert_object(building).is_not_null()
	var v: ParcelView = f.parcel_views(PackedInt64Array([building.id]))[0]
	var approved := UiText.t(&"m2.investor.approved", {"date": UiText.tick_date(v.decision_tick)})
	var stage := UiText.t(M2ResultModel.stage_key(v.development))
	var pct := UiText.t(&"format.percent", {"value": UiText.number(v.progress_pm / 10)})
	var region := f.economy_outcome().metrics(v.region_code)
	var housed := UiText.t(&"m2.row.housed_value",
			{"housed": UiText.number(int(region["housed_households"])), "total": UiText.number(int(region["households"]))})
	var street := _show(scene, building.id, STREET)
	var street_text := street.joined_text()
	var mid_text := _show(scene, building.id, NEIGHBORHOOD).joined_text()
	var far_panel := _show(scene, building.id, DISTRICT)
	var far_text := far_panel.joined_text()
	# aynı seçim: karar + aşama + bölge hane değeri her bantta aynı
	for text in [street_text, mid_text, far_text]:
		assert_str(text).contains(approved)
		assert_str(text).contains(stage)
		assert_str(text).contains(housed)
		assert_str(text).contains(UiText.humanize(String(v.ref())))
	# sadeleştirme: arsa değeri/sahip yalnız sokakta; ilerleme çubuğu sokak+mahalle; etkenler yalnız sokakta
	assert_str(street_text).contains(UiText.t(&"inspector.land_value"))
	assert_str(street_text).contains(UiText.t(&"inspector.owner"))
	for text in [mid_text, far_text]:
		assert_bool(text.contains(UiText.t(&"inspector.land_value"))).is_false()
		assert_bool(text.contains(UiText.t(&"inspector.owner"))).is_false()
	assert_str(mid_text).contains(pct)
	assert_int(_rows(far_panel, InspectorPanel.ROW_FACTOR).size()).is_equal(0)
	assert_int(_rows(far_panel, InspectorPanel.ROW_SELECTED).size()).is_equal(1)
	assert_str(far_text).contains(UiText.t(&"inspector.zoom_hint"))
	# ilçe bandı bölge özetini tam gösterir (yapımı süren birim + şehir sayaçları)
	assert_str(far_text).contains(UiText.t(&"m2.row.pipeline"))
	assert_str(far_text).contains(UiText.t(&"m2.metric.investments_approved"))
	assert_bool(street_text.contains(UiText.t(&"m2.row.pipeline"))).is_false()


# --- olumsuz zincir: kodlu neden ---

func test_declined_parcel_shows_the_coded_cause_in_every_band() -> void:
	var patch := ISOLATE.duplicate(true)
	patch.merge(M2RenderSupport.UNFAVORABLE, true)
	var scene := _scene(patch, 3)
	_step(scene, 60)
	var f: SimFacade = scene["facade"]
	var declined: ParcelView = null
	for v in f.parcel_views(scene["ids"]):
		if v.decision == ParcelView.DECISION_DECLINED:
			declined = v
			break
	assert_object(declined).override_failure_message("ret kararı oluşmadı").is_not_null()
	var cause := M2ResultModel.cause_of_code(declined.decision_code)
	var cause_line := UiText.t(&"m2.decline.cause", {"cause": UiText.t(StringName("m2.decline.%s" % cause))})
	for band in [STREET, NEIGHBORHOOD, DISTRICT]:
		var text := _show(scene, declined.id, band).joined_text()
		assert_str(text).override_failure_message(String(band)).contains(cause_line)
		assert_str(text).contains(UiText.t(&"m2.investor.declined", {"date": UiText.tick_date(declined.decision_tick)}))
	# sokak bandında reddin etkenleri kayıttan okunur (en az bir)
	var street := _show(scene, declined.id, STREET)
	assert_object(street.model.record).is_not_null()
	assert_int(street.model.factors.size()).is_greater(0)
	assert_array(Array(UiText.missing_keys())).is_empty()


func test_no_decision_yet_is_an_honest_not_yet_not_a_blank() -> void:
	var scene := _scene(ISOLATE, 0)
	var f: SimFacade = scene["facade"]
	var free := M2RenderSupport.free_parcels(M2RenderSupport.projector(f), 1)
	var text := _show(scene, free[0], STREET).joined_text()
	assert_str(text).contains(UiText.t(&"m2.investor.none"))
	assert_str(text).contains(UiText.t(&"inspector.reactions.none"))
	assert_str(text).contains(UiText.t(&"parcel.development.vacant"))
	assert_array(Array(UiText.missing_keys())).is_empty()


func test_pruned_reason_keeps_the_decision_and_hides_the_why_button() -> void:
	var scene := _scene({}, 4, &"desktop", DESKTOP, M2RenderSupport.tiny_log_config(20))
	var f: SimFacade = scene["facade"]
	var shown: ParcelView = null
	for i in 40:
		_step(scene, 1)
		for v in f.parcel_views(scene["ids"]):
			if v.decision != ParcelView.DECISION_NONE and v.decision_reason_id == 0:
				shown = v
		if shown != null:
			break
	assert_object(shown).override_failure_message("gerekçesi budanmış karar oluşmadı").is_not_null()
	var panel := _show(scene, shown.id, STREET)
	var text := panel.joined_text()
	assert_bool(panel.model.reason_pruned).is_true()
	assert_str(text).contains(UiText.t(&"m2.investor.pruned"))
	assert_bool(text.contains(UiText.t(&"m2.investor.none"))).is_false()
	assert_int(panel.named_buttons("why_decision").size()).is_equal(0)
	assert_int(_rows(panel, InspectorPanel.ROW_FACTOR).size()).is_equal(0)
	var key := &"m2.investor.approved" if shown.decision == ParcelView.DECISION_APPROVED else &"m2.investor.declined"
	assert_str(text).contains(UiText.t(key, {"date": UiText.tick_date(shown.decision_tick)}))


# --- tepki zinciri ---

func test_group_reaction_linked_by_cause_refs_is_shown_with_its_reason_button() -> void:
	var f := M2Support.stress_run(M2Support.SEED, 120)
	var linked: GroupReactionView = null
	var ref := &""
	for g in f.snapshot().group_reactions:
		for r in g.cause_refs:
			if r.begins_with("parcel."):
				linked = g
				ref = StringName(r)
		if linked != null:
			break
	if linked == null:
		# Bu tohum/uzunlukta parsele bağlı tepki yoksa test koşulu yok: sessiz geçme, açıkça başarısız ol.
		fail("stress_run parsele bağlı grup tepkisi üretmedi (cause_refs)")
		return
	var hud := _hud(f)
	var host := InspectorHost.attach(hud, f, func(c: Callable) -> void: _reasons_asked.append(c))
	host.set_band(STREET)
	host.select_parcel(int(String(ref).trim_prefix("parcel.")))
	var panel := host.panel()
	var text := panel.joined_text()
	assert_str(text).contains(UiText.actor_name(linked.group))
	assert_str(text).contains(UiText.t(StringName("m2.reaction.%s" % linked.reaction)))
	assert_bool(_rows(panel, InspectorPanel.ROW_REACTION).size() > 0).is_true()
	if not linked.reason_ids.is_empty():
		var why := panel.named_buttons("why_group_")
		assert_int(why.size()).is_greater(0)
		why[0].pressed.emit()
		assert_int(_reasons_asked.size()).is_equal(1)
	assert_array(Array(UiText.missing_keys())).is_empty()


# --- fiiller ---

func test_why_button_requests_the_recorded_reason_and_zoning_button_requests_the_flow() -> void:
	var scene := _scene(ISOLATE, 6)
	var building := _until_development(scene, ParcelView.DEVELOPMENT_UNDER_CONSTRUCTION)
	var panel := _show(scene, building.id, STREET)
	panel.named_buttons("why_decision")[0].pressed.emit()
	assert_int(_reasons_asked.size()).is_equal(1)
	panel.named_buttons("zoning")[0].pressed.emit()
	assert_array(_zoning_asked).is_equal([building.id])


func test_panel_refreshes_with_the_sim_progress_but_not_when_nothing_changed() -> void:
	var scene := _scene(ISOLATE, 6)
	var building := _until_development(scene, ParcelView.DEVELOPMENT_UNDER_CONSTRUCTION)
	var panel := _show(scene, building.id, STREET)
	var sig := panel.model.signature()
	_step(scene, 0)
	assert_str(panel.model.signature()).is_equal(sig)
	_step(scene, 2)
	panel = (scene["host"] as InspectorHost).panel()
	var v: ParcelView = (scene["facade"] as SimFacade).parcel_views(PackedInt64Array([building.id]))[0]
	assert_str(panel.joined_text()).contains(UiText.t(&"format.percent", {"value": UiText.number(v.progress_pm / 10)}))


# --- yerleşim ---

func test_layout_stays_inside_and_touch_targets_hold_at_480_to_1600_px() -> void:
	for case: Array in [[&"desktop", Vector2(1600, 900)], [&"desktop", Vector2(1024, 700)],
			[&"touch", Vector2(480, 900)], [&"touch", Vector2(1024, 768)], [&"touch", Vector2(834, 1194)],
			[&"touch", Vector2(1366, 1024)]]:
		var window: Vector2 = case[1]
		var scene := _scene(ISOLATE, 6, case[0], window)
		var building := _until_development(scene, ParcelView.DEVELOPMENT_UNDER_CONSTRUCTION)
		var hud: HudRoot = scene["hud"]
		var min_target := 44.0 if case[0] == &"touch" else 32.0
		for band in [STREET, NEIGHBORHOOD, DISTRICT]:
			var panel := _show(scene, building.id, band)
			await await_idle_frame()
			await await_idle_frame()
			assert_bool(Rect2(Vector2.ZERO, window).grow(1.0).encloses(hud.panel.get_global_rect())) \
					.override_failure_message("panel çerçeve dışında %s (%s %s)" % [hud.panel.get_global_rect(),
					window, band]).is_true()
			for b in UiTestSupport.visible_buttons(panel):
				var hit := UiFactory.hit_size(b)
				assert_float(minf(hit.x, hit.y)).override_failure_message(
						"'%s' hedefi %s (%s %s)" % [b.text, hit, window, band]).is_greater_equal(min_target)
			# Etiketler panel genişliğini aşmaz (yatay taşma yok; dikey taşma kaydırmadır)
			var panel_rect := hud.panel.get_global_rect().grow(1.0)
			for l in _all_labels(panel):
				var r := l.get_global_rect()
				assert_bool(r.position.x >= panel_rect.position.x and r.end.x <= panel_rect.end.x) \
						.override_failure_message(
						"etiket taşıyor '%s' %s (%s %s)" % [l.text, l.get_global_rect(), window, band]).is_true()


func _all_labels(node: Node, out: Array[Label] = []) -> Array[Label]:
	for child in node.get_children():
		var c := child as Control
		if c != null and not c.visible:
			continue
		if child is Label and (child as Label).text != "":
			out.append(child)
		_all_labels(child, out)
	return out
