extends GdUnitTestSuite
## T-047 ölçüt 1/6 · Dürüst imar akışı, GERÇEK sim (PoliticsBootstrap) ve gerçek T0 yerleşimiyle: yapılı/T0 stoklu
## parselde
## "yapıyı kaldırmaz" uyarısı (onay adımında ve gönderim sonrası), boş parselde yok; yeşil alanda "özel yatırım
## yapılmaz" notu. Olumsuz: boş parsel + konutta uyarı/not yok.

func before_test() -> void:
	UiText.reset()
	UiText.report_missing = false


func after_test() -> void:
	UiText.reset()


func _t0_and_empty() -> Array:
	var fx := M2RenderSupport.fixture()
	var occupied: PackedInt32Array = (fx["settlement"] as SettlementResult).columns.occupied_parcels()
	var occ := {}
	for pid in occupied:
		occ[int(pid)] = true
	var empty := -1
	var t0 := -1
	for v: ParcelView in fx["views"]:
		if occ.has(v.id) and t0 < 0:
			t0 = v.id
		if not occ.has(v.id) and empty < 0:
			empty = v.id
	return [t0, empty, occ]


func _model(facade: SimFacade, occ: Dictionary, with_probe: bool) -> ZoningFlowModel:
	var probe := (func(pid: int) -> bool: return occ.has(pid)) if with_probe else Callable()
	return ZoningFlowModel.create(facade, probe)


func test_t0_parcel_before_first_tick_warns_via_probe_and_after_tick_via_sim() -> void:
	var ids := _t0_and_empty()
	var t0: int = ids[0]
	var empty: int = ids[1]
	assert_int(t0).is_greater(0)
	assert_int(empty).is_greater(0)
	var facade := M2RenderSupport.handle(M2RenderSupport.ISOLATE).facade
	# Sonda yok: ilk tick'ten önce sim T0 parselini boş görür -> uyarı yok (neden sonda enjekte edilir).
	var bare := _model(facade, ids[2], false)
	bare.add_parcel(t0)
	bare.choose_use(&"zone.green")
	var with_probe := _model(facade, ids[2], true)
	with_probe.add_parcel(t0)
	with_probe.choose_use(&"zone.green")
	assert_str(with_probe.structure_warning()).contains("mevcut yapıyı KALDIRMAZ")
	assert_str(with_probe.structure_warning()).contains("yıkım/yeniden yapılaşma henüz modellenmiyor")
	# Ekonomi kurulunca T0 stoku sim'de de yapılı görünür: sondasız da uyarı.
	facade.advance(2)
	assert_str(bare.structure_warning()).contains("KALDIRMAZ")
	var empty_model := _model(facade, ids[2], true)
	empty_model.add_parcel(empty)
	empty_model.choose_use(&"zone.residential")
	assert_str(empty_model.structure_warning()).is_equal("")
	assert_str(empty_model.no_private_use_note()).is_equal("")


func test_green_on_empty_parcel_says_no_private_investment_and_no_structure_warning() -> void:
	var ids := _t0_and_empty()
	var facade := M2RenderSupport.handle(M2RenderSupport.ISOLATE).facade
	var m := _model(facade, ids[2], true)
	m.add_parcel(ids[1])
	m.choose_use(&"zone.green")
	assert_str(m.no_private_use_note()).is_equal("Yeşil alan: özel yatırım yapılmaz; boş parselde yeni yapı gelmez.")
	assert_str(m.structure_warning()).is_equal("")


func test_status_after_send_repeats_the_structure_warning_and_never_claims_removal() -> void:
	var ids := _t0_and_empty()
	var facade := M2RenderSupport.handle(M2RenderSupport.ISOLATE).facade
	var m := _model(facade, ids[2], true)
	m.add_parcel(ids[0])
	m.choose_use(&"zone.green")
	assert_bool(m.can_send()).is_true()
	assert_bool(m.send()).is_true()
	assert_str(m.status_text()).contains("Bu parselde yapı var")
	var cursor := 0
	for _i in 6:
		facade.advance(5)
		cursor = FlowTestSupport.pump(facade, cursor, m.handle_event)
		if m.phase() == ZoningFlowModel.Phase.EFFECTIVE:
			break
	assert_that(m.phase()).is_equal(ZoningFlowModel.Phase.EFFECTIVE)
	var text := m.status_text()
	assert_str(text).contains("mevcut yapı yerinde kalır")
	assert_str(text).contains("KALDIRMAZ")
	assert_bool(text.contains("{")).is_false()
