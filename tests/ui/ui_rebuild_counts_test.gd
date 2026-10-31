extends GdUnitTestSuite
## Kare takılması düzeltmeleri (production/log/2026-10-31-kare-sicramalari.md satır 3 ve 4): UI DAVRANIŞI AYNI,
## yeniden kurma/türetme sayıları ölçülür.
## (3) M2 sonuç paneli: yapı imzası aynıysa HİÇ yeniden kurma yok; yalnız bir bölümün imzası değişince yalnız o bölüm
##     yeniden kurulur; her adımda görünen metin, taze kurulmuş panelle BİREBİR aynıdır. Gerçek sim (M2RenderSupport).
## (4) Gündem türetmesi: öğe kümesi imzası aynıysa `derive_all` yeniden koşmaz, kalan gün yine doğru; imza değişince
##     yeniden türetilir. Kaynak: MOCK fixture (sayılar SAHTE; yalnız önbellek davranışı sınanır).

const DESKTOP := Vector2(1600, 900)
const P := preload("res://tests/sim/public_works/public_works_support.gd")
const SCENARIO := "mock_scenario_expropriation"

func before_test() -> void:
	M2Results.default_interval_msec = 0
	InspectorHost.default_interval_msec = 0
	UiText.reset()
	UiText.report_missing = false


func after_test() -> void:
	UiText.reset()


func _scene(proposals: int) -> Dictionary:
	var h := M2RenderSupport.handle({})
	var f := h.facade
	var proj := M2RenderSupport.projector(f)
	var ids := M2RenderSupport.free_parcels(proj, proposals, true)
	f.advance(2)
	var hud := HudRoot.new()
	add_child(hud)
	hud.setup(f, UiTestSupport.platform(&"desktop"))
	hud.set_anchors_preset(Control.PRESET_TOP_LEFT)
	hud.size = DESKTOP
	hud.refresh()
	auto_free(hud)
	var results := M2Results.attach(hud, f)
	var r := f.submit_command(SimCommand.zoning_propose(ids, &"zone.mixed"))
	assert_bool(r.is_rejected()).override_failure_message("imar önerisi reddedildi").is_false()
	results.track_parcels(ids)
	return {"facade": f, "hud": hud, "results": results, "ids": ids}


func _step(scene: Dictionary, days: int) -> void:
	(scene["facade"] as SimFacade).advance(days)
	(scene["hud"] as HudRoot).refresh()


func _fresh_texts(scene: Dictionary, panel: M2ResultPanel) -> String:
	var fresh := M2ResultPanel.create(panel._ctx, scene["facade"], scene["results"])
	add_child(fresh)
	auto_free(fresh)
	return fresh.joined_text()


# --- (3) M2 sonuç paneli ---

func test_same_signature_refresh_rebuilds_nothing() -> void:
	var scene := _scene(8)
	var panel := (scene["results"] as M2Results).results_panel()
	assert_object(panel).is_not_null()
	var full := panel.full_rebuilds
	var sect := panel.section_rebuilds
	var first := panel._body.get_child(0)
	var texts_before := panel.joined_text()
	for i in 5:
		panel.refresh()  # sim ilerlemedi: imza aynı
	assert_int(panel.full_rebuilds).is_equal(full)
	assert_int(panel.section_rebuilds).is_equal(sect)
	assert_bool(panel._body.get_child(0) == first).is_true()
	assert_str(panel.joined_text()).is_equal(texts_before)


func test_only_changed_sections_rebuild_and_text_equals_a_fresh_panel() -> void:
	var scene := _scene(12)
	var panel := (scene["results"] as M2Results).results_panel()
	var rebuilt_days := 0
	var kept_days := 0
	var section_changes_expected := 0
	for day in 140:
		var before_sigs: Array[String] = panel._sec_sigs.duplicate()
		var kept_node := panel._body.get_child(0)
		var section_before := panel.section_rebuilds
		var full_before := panel.full_rebuilds
		_step(scene, 1)
		var now_sigs := panel.model.section_structure_signatures()
		var changed := 0
		for i in before_sigs.size():
			if now_sigs[i] != before_sigs[i]:
				changed += 1
		# Yeniden kurma sayısı = imzası değişen bölüm sayısı (ne eksik ne fazla); tam kurma hiç yok.
		assert_int(panel.full_rebuilds).override_failure_message("gün %d: tam yeniden kurma" % day).is_equal(full_before)
		assert_int(panel.section_rebuilds - section_before).override_failure_message(
				"gün %d: bölüm yeniden kurma sayısı imza değişimiyle uyuşmuyor" % day).is_equal(changed)
		section_changes_expected += changed
		if now_sigs[0] == before_sigs[0]:
			assert_bool(panel._body.get_child(0) == kept_node).override_failure_message(
					"gün %d: parsel bölümü değişmedi ama düğümleri yeniden kuruldu" % day).is_true()
		if changed > 0:
			rebuilt_days += 1
		else:
			kept_days += 1
		# Davranış aynı: görünen metin (sıra dahil) taze kurulmuş panelle birebir.
		assert_str(panel.joined_text()).override_failure_message(
				"gün %d: artımlı panel metni taze panelden farklı" % day).is_equal(_fresh_texts(scene, panel))
	assert_int(panel.section_rebuilds).is_equal(section_changes_expected)
	assert_int(kept_days).override_failure_message("hiç 'yeniden kurma yok' günü görülmedi").is_greater(0)
	assert_int(rebuilt_days).override_failure_message(
			"yapı değişimi hiç görülmedi (negatif durum sınanmadı)").is_greater(0)
	# Tam yeniden kurma yalnız ilk kurulumdur.
	assert_int(panel.full_rebuilds).is_equal(1)


func test_changed_others_counts_update_text_without_rebuilding_the_parcel_section() -> void:
	var scene := _scene(12)
	var panel := (scene["results"] as M2Results).results_panel()
	var seen_text_change := false
	for day in 200:
		var text_before := panel.joined_text()
		var sigs: Array[String] = panel._sec_sigs.duplicate()
		var section_before := panel.section_rebuilds
		_step(scene, 1)
		var now := panel.model.section_structure_signatures()
		if now[0] == sigs[0] and panel.section_rebuilds == section_before and panel.joined_text() != text_before:
			seen_text_change = true
			break
	assert_bool(seen_text_change).override_failure_message(
			"yapı aynıyken metin değişimi (sayaç/ilerleme) görülmedi").is_true()


# --- (4) Gündem önbelleği ---

func _road_reaction(facade: MockSimFacade) -> void:
	var tool := RoadDrawTool.create(P.network(), facade)
	tool.activate()
	tool.start = Vector2(-450.0, 210.0)
	tool.end = Vector2(-450.0, 110.0)
	tool.step = RoadDrawTool.Step.REVIEW
	tool.refresh_if_graph_changed()
	tool.accept_offer()
	tool.confirm()


func _same_items(a: Array[AgendaModel.Item], b: Array[AgendaModel.Item]) -> void:
	assert_int(a.size()).is_equal(b.size())
	for i in a.size():
		assert_str(String(a[i].id)).is_equal(String(b[i].id))
		assert_str(String(a[i].kind)).is_equal(String(b[i].kind))
		assert_int(a[i].deadline_tick).is_equal(b[i].deadline_tick)
		assert_int(a[i].days_left).is_equal(b[i].days_left)
		assert_int(a[i].options.size()).is_equal(b[i].options.size())
		assert_array(Array(a[i].reason_ids)).is_equal(Array(b[i].reason_ids))


func test_agenda_cache_hits_on_same_set_keeps_days_left_exact_and_rebuilds_on_change() -> void:
	var facade: MockSimFacade = UiTestSupport.mock(SCENARIO)
	var cache := AgendaModel.Cache.new()
	# Boş küme: ilk çağrı kurar, sonrakiler önbellekten; sonuç derive_all ile aynı.
	_same_items(cache.items_for(facade, facade.snapshot()), AgendaModel.derive_all(facade, facade.snapshot()))
	assert_int(cache.builds).is_equal(1)
	facade.advance(1)
	_same_items(cache.items_for(facade, facade.snapshot()), AgendaModel.derive_all(facade, facade.snapshot()))
	assert_int(cache.builds).is_equal(1)
	assert_int(cache.hits).is_equal(1)
	# Küme değişir (yol -> yerinden edilme öğesi): yeniden türetilir.
	_road_reaction(facade)
	facade.advance(12)
	var items := cache.items_for(facade, facade.snapshot())
	assert_int(cache.builds).is_equal(2)
	assert_int(items.size()).is_greater(0)
	_same_items(items, AgendaModel.derive_all(facade, facade.snapshot()))
	# Küme aynı, gün ilerler: yeniden türetme yok, kalan gün yine derive_all ile birebir.
	var builds := cache.builds
	for i in 3:
		facade.advance(1)
		_same_items(cache.items_for(facade, facade.snapshot()), AgendaModel.derive_all(facade, facade.snapshot()))
	assert_int(cache.builds).override_failure_message("imza aynıyken yeniden türetildi").is_equal(builds)
	assert_int(cache.hits).is_greater_equal(4)
	# Negatif: geçersiz kılma sonrası tekrar kurar.
	cache.invalidate()
	cache.items_for(facade, facade.snapshot())
	assert_int(cache.builds).is_equal(builds + 1)
