extends GdUnitTestSuite
## T-040 · İlk nedensel döngünün RENDER payı (başsız, gerçek bileşenler): imar önerisi -> yatırımcı kararı ->
## inşaat ->
## SimBuildingProjector satırları -> BuildingView (hücre-yerel). Küçük GERÇEK dünya (düz arazi + ızgara WorldNetwork +
## T0Settlement) + gerçek PoliticsBootstrap/SimFacadeImpl + gerçek BuildingView. Zorlanmış sonuç yok: yalnız başlangıç
## koşulları (ISOLATE: otonom tarama kapalı; UNFAVORABLE: dar altyapı) ve oyuncu komutu veridir.
## Ölçüt 4 (kademeli, hücre-yerel, T0 çift yapı yok), 8 (komutsuz yapı yok), 9 (determinizm, kayıt/yükleme).

const ISOLATE := M2RenderSupport.ISOLATE
const BUILDING_STATES := [ParcelView.DEVELOPMENT_UNDER_CONSTRUCTION, ParcelView.DEVELOPMENT_BUILT,
		ParcelView.DEVELOPMENT_STALLED]
## Tek bir parselin değişiminde yeniden kurulabilecek en çok hücre (1 km hücre kenarında ayak izi en çok 2x2'ye
## değer).
const MAX_REBUILT_CELLS := 4


func _view(world: WorldData, config: BuildingViewConfig = null) -> BuildingView:
	var view: BuildingView = auto_free(BuildingView.new())
	add_child(view)
	var cfg := config if config != null else BuildingViewConfig.new()
	cfg.use_threads = false
	view.setup(world, BuildingTestSupport.kit(), cfg)
	return view


func _propose(f: SimFacade, ids: PackedInt64Array) -> void:
	var r := f.submit_command(SimCommand.zoning_propose(ids, &"zone.mixed"))
	assert_bool(r.is_rejected()).override_failure_message("imar önerisi reddedildi").is_false()


## Senaryo: `n` boş parsele öneri, `days` gün; her gün sim_view senkronu. Dönüş: facade, projector, ids.
func _scenario(patch: Dictionary, n: int, days: int, sync_daily: bool = true) -> Dictionary:
	var h := M2RenderSupport.handle(patch)
	var f := h.facade
	var proj := M2RenderSupport.projector(f)
	var ids := M2RenderSupport.free_parcels(proj, n, true)
	f.advance(2)
	_propose(f, ids)
	for day in days:
		f.advance(1)
		if sync_daily:
			proj.sync()
	return {"facade": f, "proj": proj, "ids": ids}


func test_proposal_becomes_staged_building_only_through_the_investor_decision() -> void:
	var h := M2RenderSupport.handle(ISOLATE)
	var f := h.facade
	var proj := M2RenderSupport.projector(f)
	var ids := M2RenderSupport.free_parcels(proj, 6, true)
	assert_int(ids.size()).is_greater(2)
	f.advance(2)
	proj.sync()
	assert_int(proj.columns().count).override_failure_message("komutsuz yapı oluştu").is_equal(0)
	_propose(f, ids)
	var order := {}                 # parsel -> görülen aşamalar (sıralı, tekrarsız)
	var floors_seen := {}           # parsel -> inşaat sırasında gözlenen kat toplamları (sıralı)
	for day in 160:
		f.advance(1)
		proj.sync()
		for v in f.parcel_views(ids):
			var seq: Array = order.get(v.id, [])
			if seq.is_empty() or seq[seq.size() - 1] != v.development:
				seq.append(v.development)
			order[v.id] = seq
			var rows := M2RenderSupport.rows_of(proj, v.id)
			if not (v.development in BUILDING_STATES):
				assert_int(rows.size()).override_failure_message(
						"parsel %d %s iken yapı satırı var" % [v.id, v.development]).is_equal(0)
			elif not rows.is_empty():
				var fl: Array = floors_seen.get(v.id, [])
				var total := M2RenderSupport.floors_of(proj, v.id)
				if fl.is_empty() or fl[fl.size() - 1] != total:
					fl.append(total)
				floors_seen[v.id] = fl
	var built := 0
	var best_distinct := 0
	for pid: int in order:
		var seq: Array = order[pid]
		if seq.has(ParcelView.DEVELOPMENT_BUILT):
			built += 1
			assert_array(seq.filter(func(s: StringName) -> bool: return s != ParcelView.DEVELOPMENT_STALLED)) \
					.is_equal([ParcelView.DEVELOPMENT_VACANT, ParcelView.DEVELOPMENT_PLANNED,
					ParcelView.DEVELOPMENT_UNDER_CONSTRUCTION, ParcelView.DEVELOPMENT_BUILT])
		var fl: Array = floors_seen.get(pid, [])
		for i in range(1, fl.size()):
			assert_int(fl[i]).override_failure_message("parsel %d kat azaldı: %s" % [pid, str(fl)]).is_greater(fl[i - 1])
		best_distinct = maxi(best_distinct, fl.size())
	assert_int(built).override_failure_message("hiçbir proje tamamlanmadı").is_greater(0)
	if M2RenderSupport.staging_available():
		assert_int(best_distinct).override_failure_message("kat kademesi gözlenmedi").is_greater_equal(2)
	else:
		# T-062 A2 · Studio Director kararı 2: hero aileleri tek boy; nihai modül inşaat başlayınca TAM boy görünür
		# (kademe yok). Kat toplamı inşaat boyunca sabit kalır ve sim biriminin kat karşılığıdır.
		assert_int(best_distinct).override_failure_message("kademesiz tabloda kat değişti").is_equal(1)
	proj.sync(true)
	for v in f.parcel_views(ids):
		if v.development == ParcelView.DEVELOPMENT_BUILT:
			assert_int(M2RenderSupport.rows_of(proj, v.id).size()).is_greater(0)


func test_final_building_matches_sim_units_and_use_family() -> void:
	var run := _scenario(ISOLATE, 4, 160)
	var proj: SimBuildingProjector = run["proj"]
	proj.sync(true)
	var cols := proj.columns()
	assert_int(cols.count).is_greater(0)
	for v in (run["facade"] as SimFacade).parcel_views(run["ids"]):
		if v.development != ParcelView.DEVELOPMENT_BUILT:
			continue
		assert_bool(v.developed_by_sim).is_true()
		assert_int(v.progress_pm).is_equal(ParcelView.PROGRESS_FULL)
		var rows := M2RenderSupport.rows_of(proj, v.id)
		assert_int(rows.size()).is_greater(0)
		for i in rows:
			assert_int(cols.flags[i] & BuildingColumns.FLAG_GROUND_SHOP).is_equal(0)  # konut: dükkân bandı yok
		assert_int(M2RenderSupport.floors_of(proj, v.id)).is_greater(0)


func test_negative_unfavorable_conditions_decline_without_any_building_and_with_a_sim_reason() -> void:
	var patch := ISOLATE.duplicate(true)
	patch.merge(M2RenderSupport.UNFAVORABLE, true)
	var run := _scenario(patch, 3, 60)
	var f: SimFacade = run["facade"]
	var proj: SimBuildingProjector = run["proj"]
	proj.sync(true)
	assert_int(proj.columns().count).override_failure_message("reddedilen parselde yapı var").is_equal(0)
	for v in f.parcel_views(run["ids"]):
		assert_str(String(v.development)).is_equal(String(ParcelView.DEVELOPMENT_VACANT))
		var negative := 0
		for r in f.reasons_for(v.ref()):
			if r.decision_key == &"decision.investor.develop" and r.outcome == ReasonRecord.OUTCOME_NEGATIVE:
				negative += 1
		assert_int(negative).override_failure_message("parsel %d: sim gerekçesi yok" % v.id).is_greater(0)


func test_only_the_affected_cells_are_rebuilt_and_the_t0_view_is_untouched() -> void:
	var fx := M2RenderSupport.fixture()
	var settlement: SettlementResult = fx["settlement"]
	var t0_view := _view(fx["world"])
	var t0_rebuilds := [0]
	t0_view.cells_rebuilt.connect(func(_keys: Array) -> void: t0_rebuilds[0] += 1)
	var t0_report := t0_view.set_columns(settlement.columns, 1)
	assert_bool(t0_report["ok"]).is_true()
	assert_int(t0_rebuilds[0]).is_equal(1)
	var t0_cells := int(t0_view.stats["cells"])
	var sim_view := _view(fx["world"])
	var h := M2RenderSupport.handle(ISOLATE)
	var f := h.facade
	var proj := M2RenderSupport.projector(f)
	var ids := M2RenderSupport.free_parcels(proj, 1, true)
	f.advance(2)
	_propose(f, ids)
	var max_rebuilt := 0
	var applied := 0
	for day in 150:
		f.advance(1)
		if bool(proj.sync().get("changed", false)):
			var rep := sim_view.set_columns(proj.columns(), proj.version())
			assert_bool(rep["ok"]).is_true()
			max_rebuilt = maxi(max_rebuilt, int(rep["rebuilt"]))
			applied += 1
	# Kademeli tabloda satırlar birden çok kez değişir (kat kademeleri); hero tek boydur (T-062 A2, karar 2): inşaat
	# başlayınca nihai satır TEK değişimle gelir.
	var min_applied := 2 if M2RenderSupport.staging_available() else 1
	assert_int(applied).override_failure_message("yapı değişimi hiç gözlenmedi").is_greater_equal(min_applied)
	assert_int(max_rebuilt).is_between(1, MAX_REBUILT_CELLS)
	assert_int(sim_view.building_count()).is_equal(proj.columns().count)
	# T0 görünümü bu süreçte hiç yeniden kurulmadı (55k satırlık plan maliyeti tetiklenmedi).
	assert_int(t0_rebuilds[0]).is_equal(1)
	assert_int(int(t0_view.stats["cells"])).is_equal(t0_cells)
	assert_int(t0_view.building_count()).is_equal(settlement.columns.count)


func test_t0_stock_parcels_never_get_sim_rows() -> void:
	var h := M2RenderSupport.handle()
	var f := h.facade
	var proj := M2RenderSupport.projector(f)
	proj.sync()   # tick 0: ekonomi durumu henüz kurulmadı, T0 parselleri vacant görünür
	assert_int(proj.columns().count).is_equal(0)
	var stock_ids := M2RenderSupport.t0_parcels(40)
	_propose(f, stock_ids)
	for day in 40:
		f.advance(1)
		proj.sync()
	proj.sync(true)
	var t0 := {}
	for pid in (M2RenderSupport.fixture()["settlement"] as SettlementResult).columns.occupied_parcels():
		t0[int(pid)] = true
	var cols := proj.columns()
	for i in cols.count:
		assert_bool(t0.has(cols.parcel_id[i])).override_failure_message(
				"T0 stok parseli %d için sim satırı" % cols.parcel_id[i]).is_false()
	for v in f.parcel_views(stock_ids):
		assert_bool(v.developed_by_sim).is_false()


func test_same_seed_and_commands_give_the_same_rows_and_state_hash_regardless_of_sync_schedule() -> void:
	var a := _scenario(ISOLATE, 5, 170)
	var b := _scenario(ISOLATE, 5, 170)
	var late := _scenario(ISOLATE, 5, 170, false)
	(a["proj"] as SimBuildingProjector).sync(true)
	(b["proj"] as SimBuildingProjector).sync(true)
	(late["proj"] as SimBuildingProjector).sync(true)   # hiç ara senkron yok: denetim yolu
	var hash_a: String = (a["facade"] as SimFacadeImpl).state_hash()
	assert_str((b["facade"] as SimFacadeImpl).state_hash()).is_equal(hash_a)
	assert_str((late["facade"] as SimFacadeImpl).state_hash()).is_equal(hash_a)
	var cols_a: BuildingColumns = (a["proj"] as SimBuildingProjector).columns()
	assert_int(cols_a.count).is_greater(0)
	assert_str((b["proj"] as SimBuildingProjector).columns().state_hash()).is_equal(cols_a.state_hash())
	assert_str((late["proj"] as SimBuildingProjector).columns().state_hash()).is_equal(cols_a.state_hash())


func test_mid_construction_save_load_gives_the_same_rows_and_continues_identically() -> void:
	var run := _scenario(ISOLATE, 4, 0)
	var f: SimFacadeImpl = run["facade"]
	var proj_a: SimBuildingProjector = run["proj"]
	var ids: PackedInt64Array = run["ids"]
	var mid := false
	for day in 120:
		f.advance(1)
		proj_a.sync(true)
		for v in f.parcel_views(ids):
			mid = mid or (v.development == ParcelView.DEVELOPMENT_UNDER_CONSTRUCTION and v.progress_pm > 300)
		if mid:
			break
	assert_bool(mid).override_failure_message("inşaat ortasına gelinemedi").is_true()
	var bytes := f.export_save()
	var hash_a := proj_a.columns().state_hash()
	assert_int(proj_a.columns().count).is_greater(0)
	# B: aynı dünya, taze facade + taze projector; kayıt içe alınır.
	var hb := M2RenderSupport.handle(ISOLATE)
	var fb := hb.facade
	var proj_b := M2RenderSupport.projector(fb)
	assert_bool(fb.import_save(bytes).ok).is_true()
	proj_b.sync(true)
	assert_str(proj_b.columns().state_hash()).override_failure_message("yükleme sonrası satırlar farklı").is_equal(hash_a)
	assert_str(fb.state_hash()).is_equal(f.state_hash())
	# Devam: ikisi de aynı sonuca varır.
	for day in 100:
		f.advance(1)
		fb.advance(1)
		proj_a.sync()
		proj_b.sync()
	proj_a.sync(true)
	proj_b.sync(true)
	assert_str(fb.state_hash()).is_equal(f.state_hash())
	assert_str(proj_b.columns().state_hash()).is_equal(proj_a.columns().state_hash())


func test_rewinding_the_same_facade_to_an_older_save_restores_the_older_rows() -> void:
	var run := _scenario(ISOLATE, 4, 0)
	var f: SimFacadeImpl = run["facade"]
	var proj: SimBuildingProjector = run["proj"]
	# Kayıt günü satırların SONRA değişeceği bir an olmalı: kademeli tabloda inşaat ortası (gün 70); hero tek
	# boyda satırlar
	# inşaat başlayınca (ölçülen gün ~29) bir kerede gelir ve sonra değişmez -> kayıt, inşaat öncesi (gün 20, 0
	# satır):
	# geri sarma satırları SİLMELİDİR.
	var save_day := 70 if M2RenderSupport.staging_available() else 20
	for day in save_day:
		f.advance(1)
		proj.sync(true)
	var bytes := f.export_save()
	var early_hash := proj.columns().state_hash()
	var early_count := proj.columns().count
	for day in 160 - save_day:
		f.advance(1)
		proj.sync(true)
	assert_str(proj.columns().state_hash()).is_not_equal(early_hash)
	assert_bool(f.import_save(bytes).ok).is_true()
	proj.sync(true)   # geri sarma: izlenen parseller yeniden okunur
	assert_int(proj.columns().count).is_equal(early_count)
	assert_str(proj.columns().state_hash()).is_equal(early_hash)


func test_hidden_events_do_not_matter_the_feed_is_independent_of_the_event_horizon() -> void:
	# Saklama ufku çok dar: onay olayları pencerede gizlenir (B-002). Feed olay günlüğünden bağımsızdır: seyrek
	# senkronla bile hiçbir onay kaçmaz, tam eşitleme GEREKMEZ ve sonuç sıfırdan kurulan projector ile aynıdır.
	var h := M2RenderSupport.handle(ISOLATE, M2RenderSupport.SEED, M2RenderSupport.tiny_log_config(20))
	var f := h.facade
	var proj := M2RenderSupport.projector(f)
	var ids := M2RenderSupport.free_parcels(proj, 40, true)
	assert_int(ids.size()).is_greater(10)
	f.advance(2)
	proj.sync()
	_propose(f, ids)
	for day in 150:
		f.advance(1)
		if day % 6 == 5:
			proj.sync()
	assert_int(f.first_retained_event_seq()).override_failure_message("olay ufku daralmadı: senaryo anlamsız") \
			.is_greater(1)
	proj.sync(true)
	assert_int(int(proj.stats["full_syncs"])).override_failure_message("tam eşitleme gerekmemeliydi").is_equal(0)
	var fresh := M2RenderSupport.projector(f)
	fresh.sync(true)   # ilk bağlanma: pencere tüm geçmişi kapsamıyorsa tam eşitleme, kapsıyorsa feed(-1) (referans)
	assert_int(fresh.columns().count).is_greater(0)
	assert_str(proj.columns().state_hash()).override_failure_message(
			"feed güdümlü satırlar sıfırdan kurulandan farklı (%d / %d satır)" % [proj.columns().count,
			fresh.columns().count]).is_equal(fresh.columns().state_hash())


func test_normal_log_needs_no_full_sync_when_synced_daily() -> void:
	var run := _scenario(ISOLATE, 6, 120)
	assert_int(int((run["proj"] as SimBuildingProjector).stats["full_syncs"])).is_equal(0)
