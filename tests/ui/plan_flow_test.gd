extends GdUnitTestSuite
## T-043A UI payı (kabul 8): plan durumu etiketleri, plan teklifi akışı (kullanım + yoğunluk), önizleme = sim sorgusu
## "meclis" sözcüğü yalnız gerçek bayrak true iken, yolun ardından ipucu (yalnız plansız parsel varken), plansız nedeni
## "neden bina yok" nedeni düz Türkçe. GERÇEK facade (PoliticsBootstrap, oynanabilir ekonomi: unplanned_land açık).

const DESKTOP := Vector2(1600, 900)
const ISOLATE := M2RenderSupport.ISOLATE


func before_test() -> void:
	InspectorHost.default_interval_msec = 0
	UiText.reset()
	UiText.report_missing = false
	UiPrefs.set_zoning_requires_council(false)


func after_test() -> void:
	UiPrefs.set_zoning_requires_council(false)
	UiText.reset()


# --- kurulum ---

func _real(council_off: bool = true) -> SimFacadeImpl:
	var fx := M2RenderSupport.fixture()
	var source := ListParcelSource.create(&"m2_fixture", fx["views"])
	var cfg := PlayableEconomy.config_for(fx["views"], fx["stock"], ISOLATE)
	var politics: PoliticsConfig = PlayablePolitics.config() if council_off else null
	var h := PoliticsBootstrap.create(M2RenderSupport.SEED, source, cfg, fx["stock"], null, politics, null)
	assert_object(h).is_not_null()
	h.facade.advance(2)
	return h.facade


func _free_ids(f: SimFacade, count: int) -> PackedInt64Array:
	return M2RenderSupport.free_parcels(M2RenderSupport.projector(f), count, false)


func _hud(facade: SimFacade) -> HudRoot:
	var hud := HudRoot.new()
	add_child(hud)
	hud.setup(facade, UiTestSupport.platform(&"desktop"))
	hud.set_anchors_preset(Control.PRESET_TOP_LEFT)
	hud.size = DESKTOP
	hud.refresh()
	return auto_free(hud)


# --- etiketler ---

func test_plan_state_labels_read_the_sim_fields_and_hide_when_untracked() -> void:
	var p := PlanStateView.new()
	assert_str(PlanStateText.label(p)).is_equal("")  # untracked: satır yok
	p.state = PlanStateView.STATE_UNPLANNED
	assert_str(PlanStateText.label(p)).starts_with("Plansız")
	p.state = PlanStateView.STATE_PROPOSED
	p.due_tick = 12
	assert_str(PlanStateText.label(p)).is_equal("Teklif verildi (yürürlük gün 12)")
	p.due_tick = -1
	p.vote_ref = &"vote.3"
	assert_str(PlanStateText.label(p)).contains("oylama")
	p.state = PlanStateView.STATE_PLANNED
	p.zone = &"zone.mixed"
	p.density = -1
	assert_str(PlanStateText.label(p)).is_equal("Planlı (Karma, varsayılan yoğunluk)")
	p.density = 600
	assert_str(PlanStateText.label(p)).contains("%60")
	p.state = PlanStateView.STATE_EXISTING
	assert_str(PlanStateText.label(p)).contains("plan akışı yok")
	p.state = PlanStateView.STATE_REJECTED
	p.rejected_tick = 9
	assert_str(PlanStateText.label(p)).contains("reddedildi")
	assert_bool(PlanStateText.needs_plan(p)).is_true()


func test_unplanned_cause_is_mapped_and_has_plain_turkish_text() -> void:
	assert_that(M2ResultModel.cause_of_code(&"zoning_unplanned")).is_equal(M2ResultModel.CAUSE_UNPLANNED)
	for key in [&"m2.decline.unplanned", &"reason.factor.zoning_unplanned", &"event.zoning.plan_rejected"]:
		assert_bool(UiText.has(key)).override_failure_message(String(key)).is_true()
	assert_str(UiText.t(&"m2.decline.unplanned")).contains("imar planı yok")


# --- denetçi ---

func test_inspector_shows_unplanned_then_proposed_with_day_then_planned() -> void:
	var f := _real()
	var id := int(_free_ids(f, 1)[0])
	var host := InspectorHost.attach(_hud(f), f)
	host.set_band(&"street")
	host.select_parcel(id)
	var text := host.panel().joined_text()
	assert_str(text).contains(UiText.t(&"plan.state.unplanned"))
	assert_str(text).contains(UiText.t(&"plan.state.unplanned_why"))
	var r := f.submit_command(SimCommand.zoning_propose(PackedInt64Array([id]), &"zone.mixed"))
	assert_bool(r.is_rejected()).is_false()
	f.advance(1)
	var proposed := f.plan_state(id)
	assert_str(String(proposed.state)).is_equal("proposed")
	host.select_parcel(id)
	assert_str(host.panel().joined_text()).contains("Teklif verildi (yürürlük gün %d)" % proposed.due_tick)
	f.advance(maxi(proposed.due_tick - f.current_tick(), 0) + 1)
	assert_str(String(f.plan_state(id).state)).is_equal("planned")
	host.select_parcel(id)
	assert_str(host.panel().joined_text()).contains("Planlı (Karma")


# --- akış ---

func test_flow_preview_is_exactly_the_sim_query_and_density_goes_into_the_command() -> void:
	var f := _real()
	var ids := _free_ids(f, 2)
	var m := ZoningFlowModel.create(f)
	for id in ids:
		assert_bool(m.add_parcel(id)).is_true()
	assert_object(m.preview()).is_null()  # kullanım seçilmeden önizleme yok
	m.choose_use(&"zone.mixed")
	var pv := m.preview()
	var q := f.plan_preview(ids, &"zone.mixed", -1)
	assert_bool(pv.ok).is_true()
	assert_that(pv.to_dict()).is_equal(q.to_dict())
	assert_bool(m.command().params.has("density")).is_false()
	var opt := ZoningFlowModel.density_options()[0]
	m.choose_density(opt)
	assert_int(int(m.command().params["density"])).is_equal(opt)
	assert_that(m.preview().to_dict()).is_equal(f.plan_preview(ids, &"zone.mixed", opt).to_dict())
	m.choose_density(777)  # yapılandırmada olmayan seçenek kabul edilmez
	assert_int(m.density_pm).is_equal(opt)
	# Önizleme sayıları yoğunlukla gerçekten değişir (uydurma değil: sim hesabı)
	assert_int(m.preview().total_units).is_not_equal(f.plan_preview(ids, &"zone.mixed", -1).total_units)


func test_flow_panel_shows_only_sim_preview_numbers_and_no_council_word_without_the_flag() -> void:
	var f := _real(true)
	var ids := _free_ids(f, 2)
	var hud := _hud(f)
	var d := DecisionPanels.attach(hud, f, Callable(), false)
	d.open_zoning(ids)
	var panel := d.zoning_panel()
	panel.choose_use(&"zone.mixed")
	var pv := f.plan_preview(ids, &"zone.mixed", -1)
	var text := panel.joined_text()
	assert_str(text).contains(UiText.t(&"zoning.preview.units", {"n": UiText.number(pv.total_units)}))
	assert_str(text).contains(UiText.t(&"zoning.preview.infra", {"n": UiText.number(pv.total_infra_units)}))
	assert_str(text).contains(UiText.t(&"zoning.preview.effect"))  # yarar/zarar işareti kurulu değil
	assert_str(text).contains(UiText.t(&"plan.state.unplanned_short"))
	assert_bool(text.to_lower().contains("meclis")).override_failure_message(
			"meclis sözcüğü bayrak kapalıyken görünmemeli: " + text).is_false()
	var sent := panel.send_button()
	assert_bool(sent.is_enabled()).is_true()
	panel.send()
	f.advance(1)
	hud.refresh()
	assert_str(String(f.plan_state(ids[0]).state)).is_equal("proposed")
	panel.handle_event(f.events_since(0)[f.events_since(0).size() - 1])
	assert_str(panel.joined_text()).contains("Teklif verildi (yürürlük gün")


func test_council_word_appears_only_when_the_real_flag_is_true() -> void:
	var f_off := _real(true)
	var m_off := ZoningFlowModel.create(f_off)
	assert_bool(m_off.council_required()).is_false()
	var f_on := _real(false)  # sim varsayılan siyaseti: requires_council true
	var m_on := ZoningFlowModel.create(f_on)
	assert_bool(m_on.council_required()).is_true()
	assert_str(m_on.path_text()).contains("oylama")
	# Sim bayrağı ui_config yer tutucusunu ezer
	UiPrefs.set_zoning_requires_council(true)
	assert_bool(m_off.council_required()).is_false()


func test_area_is_capped_by_the_sim_limit() -> void:
	var f := _real()
	var limit := f.plan_preview(PackedInt64Array(), &"").max_parcels
	assert_int(limit).is_greater(0)
	var m := ZoningFlowModel.create(f)
	var all := f.parcel_ids()
	var added := 0
	for id in all:
		if m.add_parcel(id):
			added += 1
	assert_int(added).is_equal(mini(limit, all.size()))
	if all.size() > limit:
		assert_bool(m.at_parcel_limit()).is_true()


func test_mock_source_has_no_plan_state_or_preview_and_says_so() -> void:
	var f := FlowTestSupport.mock("mock_scenario_investment_declined")
	assert_str(PlanStateText.label(f.plan_state(1))).is_equal("")
	var m := ZoningFlowModel.create(f)
	m.add_parcel(1)
	m.choose_use(&"zone.mixed")
	assert_bool(m.preview().ok).is_false()
	var hud := _hud(f)
	var d := DecisionPanels.attach(hud, f, Callable(), false)
	d.open_zoning(PackedInt64Array([1]))
	d.zoning_panel().choose_use(&"zone.mixed")
	assert_str(d.zoning_panel().joined_text()).contains("Önizleme yok")


func test_map_selection_adds_to_the_open_zoning_area_instead_of_opening_the_inspector() -> void:
	var f := _real()
	var ids := _free_ids(f, 2)
	var hud := _hud(f)
	var d := DecisionPanels.attach(hud, f, Callable(), false)
	var host := InspectorHost.attach(hud, f, Callable(), Callable(), d.add_zoning_parcel)
	d.open_zoning(PackedInt64Array([ids[0]]))
	host.select_parcel(ids[1])
	assert_str(String(hud.panel_id())).is_equal("zoning")
	assert_bool(d.zoning.parcel_ids.has(ids[1])).is_true()


func test_structure_warning_is_taken_at_send_so_the_plans_own_building_is_not_called_existing() -> void:
	var f := _real()
	var ids := _free_ids(f, 1)
	var m := ZoningFlowModel.create(f)
	m.add_parcel(ids[0])
	m.choose_use(&"zone.mixed")
	assert_bool(m.structure_parcels().is_empty()).is_true()  # boş parsel: "mevcut yapı" uyarısı yok
	assert_bool(m.send()).is_true()
	# Yatırımcı planın yürürlüğünden sonra yapıyı diker; bu "mevcut yapı" değildir (gönderimdeki durum korunur).
	for i in 200:
		f.advance(1)
		if f.parcel_views(ids)[0].development != ParcelView.DEVELOPMENT_VACANT:
			break
	assert_bool(f.parcel_views(ids)[0].development != ParcelView.DEVELOPMENT_VACANT).override_failure_message(
			"planlı parselde 200 günde yapı başlamadı").is_true()
	assert_bool(m.structure_parcels().is_empty()).is_true()
