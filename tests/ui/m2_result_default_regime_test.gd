extends GdUnitTestSuite
## B-001 (T-040 HUD 3. tur) · "Döngü sonucu" paneli VARSAYILAN (otonom, review_enabled=1) rejimde ve gerekçe günlüğü
## döndükten sonra: karar `ParcelView.decision*`dan okunur (günlük dönse de doğru), gerekçe budandıysa dürüst metin ve
## "Nedenini gör" yok, öneri öncesi otonom ret "vazgeçildi" sayılmaz, özet sayıları sim kararlarıyla birebir.
## İzole rejim testleri (m2_result_panel_test.gd) günlük dönmediği için bunu yakalamıyordu.

const DESKTOP := Vector2(1600, 900)
const SIM_CODE_TO_CAUSE := {
	"zoning_not_buildable": &"zoning", "infrastructure_exhausted": &"infrastructure",
	"insufficient_financing": &"financing", "demand_too_low": &"demand", "return_too_low": &"return",
}


func before_test() -> void:
	M2Results.default_interval_msec = 0  # testler adım adım ilerler; yenileme sınırı kapalı
	UiText.reset()
	UiText.report_missing = false


func after_test() -> void:
	UiText.reset()


func _hud(facade: SimFacade) -> HudRoot:
	var hud := HudRoot.new()
	add_child(hud)
	hud.setup(facade, UiTestSupport.platform(&"desktop"))
	hud.set_anchors_preset(Control.PRESET_TOP_LEFT)
	hud.size = DESKTOP
	hud.refresh()
	return auto_free(hud)


func _step(scene: Dictionary, days: int) -> void:
	(scene["facade"] as SimFacade).advance(days)
	(scene["hud"] as HudRoot).refresh()


func _panel(scene: Dictionary) -> M2ResultPanel:
	var p := (scene["results"] as M2Results).results_panel()
	assert_object(p).override_failure_message("sonuç paneli açık değil").is_not_null()
	return p


## Varsayılan rejim (review_enabled=1) gerçek sim: öneri verilir, gün ilerler, panel kurulur.
func _default_scene(patch: Dictionary, proposals: int, warmup_days: int, sim_config: SimConfig = null) -> Dictionary:
	var h := M2RenderSupport.handle(patch, M2RenderSupport.SEED, sim_config)
	var f := h.facade
	var proj := M2RenderSupport.projector(f)
	f.advance(warmup_days)
	var ids := M2RenderSupport.free_parcels(proj, proposals, true)
	var hud := _hud(f)
	var results := M2Results.attach(hud, f)
	return {"facade": f, "hud": hud, "results": results, "ids": ids}


func _propose(scene: Dictionary) -> void:
	var f: SimFacade = scene["facade"]
	var r := f.submit_command(SimCommand.zoning_propose(scene["ids"], &"zone.mixed"))
	assert_bool(r.is_rejected()).override_failure_message("imar önerisi reddedildi").is_false()
	(scene["results"] as M2Results).track_parcels(scene["ids"])


## Gerekçe günlüğü bu koşuda gerçekten döndü mü (en eski kayıt artık yok).
func _log_rotated(f: SimFacade) -> bool:
	return f.reason(1) == null


func _expected_counts(f: SimFacade, ids: PackedInt64Array, proposed: int) -> Dictionary:
	var out := {"approved": 0, "declined": 0, "waiting": 0}
	for v in f.parcel_views(ids):
		if v.decision != "" and v.decision_tick > proposed:
			out["approved" if v.decision == ParcelView.DECISION_APPROVED else "declined"] += 1
		else:
			out["waiting"] += 1
	return out


func test_default_regime_with_rotated_log_shows_the_sim_decision_and_exact_summary() -> void:
	# Fixture dünyası 1000 kayda ulaşmaz; küçük günlük (40) ≥60 günde birçok kez döner. Gerçek Ismeral'de varsayılan
	# kapasite ile dönme yakalama kanıtındadır (B-001 Düzeltme).
	var scene := _default_scene({}, 8, 2, M2RenderSupport.tiny_log_config(40))
	var f: SimFacade = scene["facade"]
	_propose(scene)
	var results: M2Results = scene["results"]
	var proposed := results.proposed_tick
	for step in 12:
		_step(scene, 5)  # 60 gün
	assert_bool(_log_rotated(f)).override_failure_message("gerekçe günlüğü dönmedi; senaryo B-001'i yakalamaz").is_true()
	var panel := _panel(scene)
	var m: M2ResultModel = panel.model
	assert_object(m.primary).is_not_null()
	var v := f.parcel_views(PackedInt64Array([m.primary.id()]))[0]
	assert_str(String(v.decision)).override_failure_message("birincil parselde sim kararı yok").is_not_equal("")
	var text := panel.joined_text()
	assert_bool(text.contains(UiText.t(&"m2.investor.none"))).override_failure_message(
			"günlük dönse de 'Henüz karar yok' yazmamalı").is_false()
	var date := UiText.tick_date(v.decision_tick)
	if v.decision == ParcelView.DECISION_APPROVED:
		assert_str(text).contains(UiText.t(&"m2.investor.approved", {"date": date}))
	else:
		assert_str(text).contains(UiText.t(&"m2.investor.declined", {"date": date}))
		var cause_text := UiText.t(StringName("m2.decline.%s" % SIM_CODE_TO_CAUSE[String(v.decision_code)]))
		assert_str(text).contains(UiText.t(&"m2.decline.cause", {"cause": cause_text}))
	# gerekçe kimliği: >0 ise düğme var, 0 ise dürüst "budandı" ve düğme yok
	var why := panel.named_buttons("why_decision")
	if v.decision_reason_id > 0:
		assert_int(why.size()).is_equal(1)
		assert_bool(text.contains(UiText.t(&"m2.investor.pruned"))).is_false()
	else:
		assert_int(why.size()).is_equal(0)
		assert_str(text).contains(UiText.t(&"m2.investor.pruned"))
	# özet sayıları sim kararlarıyla birebir
	var exp := _expected_counts(f, scene["ids"], proposed)
	assert_dict(m.counts_decided()).is_equal(exp)
	assert_str(text).contains(UiText.t(&"m2.others", {"n": 8, "approved": exp["approved"],
			"declined": exp["declined"], "waiting": exp["waiting"]}))
	assert_int(exp["approved"] + exp["declined"]).override_failure_message("hiçbir karar sayılmadı").is_greater(0)
	assert_array(Array(UiText.missing_keys())).is_empty()


func test_pruned_reason_shows_honest_text_and_hides_the_why_button() -> void:
	# Çok küçük günlük: önerilen parselin gerekçesi kesin budanır (B-001 çekirdek durumu).
	var scene := _default_scene({}, 4, 2, M2RenderSupport.tiny_log_config(20))
	var f: SimFacade = scene["facade"]
	_propose(scene)
	var shown: ParcelView = null
	for i in 40:
		_step(scene, 1)
		var m: M2ResultModel = _panel(scene).model
		if m.primary != null and m.primary.decision != M2ResultModel.Decision.NONE and m.primary.reason_id == 0:
			shown = f.parcel_views(PackedInt64Array([m.primary.id()]))[0]
			break
	assert_object(shown).override_failure_message("gerekçesi budanmış karar oluşmadı").is_not_null()
	assert_int(shown.decision_reason_id).is_equal(0)
	var panel := _panel(scene)
	var text := panel.joined_text()
	assert_str(text).contains(UiText.t(&"m2.investor.pruned"))
	assert_bool(text.contains(UiText.t(&"m2.investor.none"))).is_false()
	assert_int(panel.named_buttons("why_decision").size()).is_equal(0)
	var date := UiText.tick_date(shown.decision_tick)
	var key := &"m2.investor.approved" if shown.decision == ParcelView.DECISION_APPROVED else &"m2.investor.declined"
	assert_str(text).contains(UiText.t(key, {"date": date}))


func test_a_decline_before_the_proposal_is_not_counted_as_given_up() -> void:
	# Otonom tarama: önerilmemiş boş parseller öneriden ÖNCE ret kaydı alır (fixture'da ~60. günde).
	var scene := _default_scene({}, 0, 60)
	var f: SimFacade = scene["facade"]
	var proj := M2RenderSupport.projector(f)
	var pool := M2RenderSupport.free_parcels(proj, 40, true)
	var picked := PackedInt64Array()
	for v in f.parcel_views(pool):
		if v.decision == ParcelView.DECISION_DECLINED and v.development == ParcelView.DEVELOPMENT_VACANT:
			picked.append(v.id)
		if picked.size() >= 6:
			break
	assert_int(picked.size()).override_failure_message("öneri öncesi otonom retli parsel yok").is_greater(0)
	scene["ids"] = picked
	_propose(scene)
	var results: M2Results = scene["results"]
	var panel := _panel(scene)
	var m: M2ResultModel = panel.model
	for v in f.parcel_views(picked):
		assert_bool(v.decision_tick <= results.proposed_tick).override_failure_message(
				"parsel %d kararı öneriden eski değil" % v.id).is_true()
	assert_int(m.counts_decided()["declined"]).override_failure_message(
			"öneri öncesi ret 'vazgeçildi' sayıldı").is_equal(0)
	assert_int(m.counts_decided()["approved"]).is_equal(0)
	assert_int(m.counts_decided()["waiting"]).is_equal(picked.size())
	assert_bool(m.primary.before_proposal).is_true()
	var text := panel.joined_text()
	assert_str(text).contains(UiText.t(&"m2.investor.prior"))
	assert_str(text).contains(UiText.t(&"m2.investor.waiting"))
	if picked.size() > 1:
		assert_str(text).contains(UiText.t(&"m2.others", {"n": picked.size(), "approved": 0, "declined": 0,
				"waiting": picked.size()}))
	# öneri sonrası yeni karar gelince normal gösterilir
	for i in 90:
		_step(scene, 1)
		var cur := f.parcel_views(picked)
		var fresh := cur.any(func(x: ParcelView) -> bool:
			return x.decision != "" and x.decision_tick > results.proposed_tick)
		if fresh:
			break
	var after: M2ResultModel = _panel(scene).model
	var exp := _expected_counts(f, picked, results.proposed_tick)
	assert_dict(after.counts_decided()).is_equal(exp)


func test_mock_facade_never_shows_a_decision_or_a_why_button() -> void:
	var mock := UiTestSupport.mock()
	var hud := _hud(mock)
	var results := M2Results.attach(hud, mock)
	results.track_parcels(mock.parcel_ids().slice(0, 2))
	var panel := results.results_panel()
	assert_object(panel).is_not_null()
	for v in mock.parcel_views(mock.parcel_ids().slice(0, 2)):
		assert_str(String(v.decision)).is_equal("")
	assert_int(panel.named_buttons("why_decision").size()).is_equal(0)
	assert_bool(panel.joined_text().contains(UiText.t(&"m2.investor.approved", {"date": ""}))).is_false()




func test_same_tick_decline_is_a_prior_evaluation_not_an_answer_to_the_proposal() -> void:
	# B-003: öneri tick'inde zaten kayıtlı ret (decision_tick == öneri tick'i) öneriye cevap DEĞİLDİR.
	# T-043A (D-010): oynanabilir koşulda plansız arazi her boş parseli `zoning_unplanned` ile reddeder ve ret
	# `negative_repeat_days` boyunca TEKRAR kaydedilmez; yani aynı-tick ret yalnız parselin İLK taramasındadır. Bu yüzden
	# ısınma yok (eski senaryo 45 gün ısınıp taze ret arıyordu: plansız rejimde ret çoktan kaydedilmiş ve sessizdi).
	var scene := _default_scene({}, 0, 0)
	var f: SimFacade = scene["facade"]
	var pool := M2RenderSupport.free_parcels(M2RenderSupport.projector(f), 40, true)
	var picked := PackedInt64Array()
	for day in 60:
		for v in f.parcel_views(pool):
			if v.decision == ParcelView.DECISION_DECLINED and v.decision_tick == f.current_tick() \
					and v.development == ParcelView.DEVELOPMENT_VACANT:
				picked.append(v.id)
		if not picked.is_empty():
			break
		_step(scene, 1)
	assert_int(picked.size()).override_failure_message("aynı tick'te retli parsel bulunamadı").is_greater(0)
	picked = picked.slice(0, 8)
	scene["ids"] = picked
	_propose(scene)
	var results: M2Results = scene["results"]
	var panel := _panel(scene)
	var m: M2ResultModel = panel.model
	for v in f.parcel_views(picked):
		assert_int(v.decision_tick).is_equal(results.proposed_tick)
	assert_int(m.counts_decided()["declined"]).override_failure_message("aynı-tick ret vazgeçildi sayıldı").is_equal(0)
	assert_int(m.counts_decided()["waiting"]).is_equal(picked.size())
	assert_bool(m.primary.before_proposal).is_true()
	var text := panel.joined_text()
	assert_str(text).contains(UiText.t(&"m2.investor.prior"))
	assert_str(text).contains(UiText.t(&"m2.investor.waiting"))


func test_a_built_parcel_gets_an_honest_already_invested_line_not_waiting() -> void:
	# T-043A (D-010): plansız arazide otonom yatırım YOKTUR; "yatırım almış parsel" önce OYUNCU planıyla doğar (eski
	# senaryo 50 gün otonom büyüme bekliyordu). Aynı parsele ikinci öneri: panel "zaten yatırım almış" der,
	# "bekliyor" demez.
	var scene := _default_scene({}, 0, 0)
	var f: SimFacade = scene["facade"]
	var pool := M2RenderSupport.free_parcels(M2RenderSupport.projector(f), 40, true)
	var seeded := pool.slice(0, 8)
	var first := f.submit_command(SimCommand.zoning_propose(seeded, &"zone.mixed"))
	assert_bool(first.is_rejected()).override_failure_message("ilk plan teklifi reddedildi").is_false()
	var picked := PackedInt64Array()
	for day in 150:
		_step(scene, 1)
		for v in f.parcel_views(seeded):
			if v.decision == ParcelView.DECISION_APPROVED and v.development != ParcelView.DEVELOPMENT_VACANT:
				picked.append(v.id)
				break
		if not picked.is_empty():
			break
	assert_int(picked.size()).override_failure_message("plan sonrası yatırım almış parsel yok").is_greater(0)
	scene["ids"] = picked
	_propose(scene)
	var text := _panel(scene).joined_text()
	assert_str(text).contains(UiText.t(&"m2.investor.already"))
	assert_bool(text.contains(UiText.t(&"m2.investor.waiting"))).is_false()


## İlerleme çubuğu: kesim tepki kartlarındaki (ROW_REACTION) yoğunluk çubukları HARİÇ ilk MeterBar.
## B-130/D-026: yoğun yol yapımında konut arayanlar tepki verince panelde tepki kartı (kendi çubuğu) da görünür.
func _first_meter(node: Node) -> MeterBar:
	for child in node.get_children():
		if child is MeterBar:
			return child
		if child.get_meta(M2ResultPanel.META_ROW, "") == M2ResultPanel.ROW_REACTION:
			continue
		var inner := _first_meter(child)
		if inner != null:
			return inner
	return null


## Değer-yalnız güncellemeler (yapı imzası aynı) düğümleri yeniden kullanır ve sim ile birebirdir. Senaryo, hangi
## parselin asıl parsel (ilk SONRAKİ karar) olacağına ve ne zaman inşaata gireceğine BAĞLI DEĞİLDİR: günlük adımlarda
## her yapı-aynı adım denetlenir; asıl parselin gerçekten inşaatta ilerlediği (0..900) adımlar sayılır ve yeterli sayıda
## yoksa test sessizce geçmez/yanlış nedenle düşmez, açık bir mesajla düşer. (T-051 yerleşim ağırlıkları serbest parsel
## kümesini değiştirince asıl parsel 2 -> 7 oldu; eski sürüm "öneri bekliyor" penceresinde inşaat bekliyordu.)
func test_value_only_changes_reuse_the_nodes_and_stay_exact() -> void:
	var scene := _default_scene({}, 8, 2)
	_propose(scene)
	var f: SimFacade = scene["facade"]
	var panel := _panel(scene)
	var progress_steps := 0  # yapı aynı + asıl parsel inşaatta + ilerleme değişti
	var pending_steps := 0  # yapı aynı + "imar bekliyor" satırı görünürken yapılan değer-yalnız adım
	for day in 250:
		var model_before := panel.model
		var structure := model_before.structure_signature()
		var body_child := panel._body.get_child(0)
		var meter := _first_meter(panel)
		var before_pm := model_before.primary.view.progress_pm
		_step(scene, 1)
		if panel.model.structure_signature() != structure:
			continue  # düğüm kümesi meşru olarak değişti (karar/gelişme durumu): yeniden kurulum beklenir
		assert_bool(panel._body.get_child(0) == body_child).override_failure_message(
				"düğümler yeniden kuruldu (gün %d, yapı imzası aynı)" % day).is_true()
		assert_bool(_first_meter(panel) == meter).override_failure_message(
				"ilerleme çubuğu yeniden kuruldu (gün %d)" % day).is_true()
		var v := f.parcel_views(PackedInt64Array([panel.model.primary.id()]))[0]
		assert_int(panel.model.primary.view.progress_pm).override_failure_message(
				"panel modeli simle birebir değil (gün %d)" % day).is_equal(v.progress_pm)
		if meter != null:
			assert_int(meter.permille).is_equal(v.progress_pm)
		if v.pending_zone != &"":
			pending_steps += 1
		if v.development == ParcelView.DEVELOPMENT_UNDER_CONSTRUCTION and v.progress_pm > 0 and v.progress_pm < 900 \
				and v.progress_pm != before_pm:
			progress_steps += 1
			assert_str(panel.joined_text()).contains(
					UiText.t(&"format.percent", {"value": UiText.number(v.progress_pm / 10)}))
		if progress_steps >= 3:
			break
	assert_int(progress_steps).override_failure_message(
			"asıl parsel (%d) 250 günde yapı-aynı üç ilerleme adımı göstermedi" % panel.model.primary.id()).is_equal(3)
	assert_int(pending_steps).override_failure_message("'imar bekliyor' satırlı değer-yalnız adım görülmedi").is_greater(0)
	var o := f.economy_outcome()
	assert_int(panel.model.metric(&"investments_approved").value).is_equal(o.metrics()["investments_approved"])


func test_refresh_rate_is_capped_but_the_first_and_forced_refreshes_are_exact() -> void:
	var scene := _default_scene({}, 4, 2)
	M2Results.default_interval_msec = 60000
	_propose(scene)
	var results: M2Results = scene["results"]
	var panel := _panel(scene)
	var tick0 := panel.model.tick
	_step(scene, 5)
	assert_int(panel.model.tick).override_failure_message("sınır içinde yeniden hesap yapıldı").is_equal(tick0)
	results.build_model()  # doğrudan okuma sınırdan etkilenmez
	assert_int(results.build_model().tick).is_equal(tick0 + 5)
	M2Results.default_interval_msec = 0
	_step(scene, 1)
	assert_int(panel.model.tick).is_equal(tick0 + 6)
