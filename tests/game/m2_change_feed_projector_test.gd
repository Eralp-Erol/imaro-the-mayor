extends GdUnitTestSuite
## T-040 RENDER 3. tur (B-002, T-045 ölçüt 5) · SimBuildingProjector `parcel_changes_since` ile (başsız, GERÇEK
## bileşenler:
## PoliticsBootstrap/SimFacadeImpl + gerçek T0Settlement + gerçek projector). Kapsam: feed güdümlü senkron =
## `sync(exact)` =
## sıfırdan kurulan projector; düşük kare hızında gecikme/kuyruk sınırı (2/4/15/60 kare/gün, sentetik kare sürücüsü);
## kayıt/yükleme (epoch) ve eksik feed (complete=false) => TEK tam eşitleme, sonra yine yalnız feed; sığmayan parsel
## API'si.

const ISOLATE := M2RenderSupport.ISOLATE
## Bir parselin sim aşamasındaki değişim ile görünen satırların eşitlenmesi arasında geçebilecek en çok sim günü
## (B-002 hedefi).
const MAX_LAG_DAYS := 2
## Projector kuyruğu (işlenmemiş sim günü) üst sınırı: gün sonu ölçümü; bütçe duvar saati olduğundan yük altında
## 1-2 gün oynayabilir (görünür gecikme yine MAX_LAG_DAYS ile sınırlı).
const MAX_BACKLOG_DAYS := 4
## Kare başına projector dilim bütçesi ve geride kalma eşiği: playable.gd ile AYNI (SIM_SYNC_BUDGET_US /
## MAX_SYNC_BACKLOG_DAYS).
const FRAME_BUDGET_US := SimBuildingPump.BUDGET_US
## Eşzamanlı inşaat sayısını ~100'e çıkaran yük: fixture dünyasındaki T0 dışı yerleşebilir parsel sayısına yakın.
const LOAD_PARCELS := 130
## Sanal saat (B-004): her projector iş birimi bu kadar µs sayılır; bütçe duvar saatine/makine yüküne bağlı DEĞİL.
const VIRTUAL_UNIT_US := 900
## Kayıt yükleme/geri sarma sonrası, görünür satırların sim'e yetişmesi için en çok sim günü (B-005).
const MAX_LAG_AFTER_LOAD_DAYS := 10

var _plan_cache: Dictionary = {}


func _propose(f: SimFacade, ids: PackedInt64Array) -> void:
	var r := f.submit_command(SimCommand.zoning_propose(ids, &"zone.mixed"))
	assert_bool(r.is_rejected()).override_failure_message("imar önerisi reddedildi").is_false()


## `wave_size` 0: tüm parseller tek komutta (patlama). Aksi halde her gün `wave_size` parsel önerilir (yayılı yük:
## oyuncu
## bir mahalleyi günlerce imara açar / otonom yatırımcı sürekli onay verir) — `_drive` dağıtır.
func _run(patch: Dictionary, n: int, wave_size: int = 0) -> Dictionary:
	var h := M2RenderSupport.handle(patch)
	var f := h.facade
	var proj := M2RenderSupport.projector(f)
	proj.virtual_unit_us = VIRTUAL_UNIT_US
	var ids := M2RenderSupport.free_parcels(proj, n, true)
	f.advance(2)
	proj.sync()
	if wave_size == 0:
		_propose(f, ids)
	return {"facade": f, "proj": proj, "ids": ids, "wave_size": wave_size, "proposed": 0, "save_day": -1,
			"load_day": -1}


## Sim'in şimdiki durumundan beklenen toplam kat (projector kuralı: yerleşebilir inşaat/yapıldı/durmuş parsel).
func _expected_floors(proj: SimBuildingProjector, v: ParcelView) -> int:
	var building := v.developed_by_sim and v.use != ParcelView.USE_NONE and v.units > 0 \
			and v.development in [ParcelView.DEVELOPMENT_UNDER_CONSTRUCTION, ParcelView.DEVELOPMENT_BUILT,
			ParcelView.DEVELOPMENT_STALLED]
	if not building:
		return 0
	var key := "%d|%s|%d" % [v.id, v.use, v.units]
	if not _plan_cache.has(key):
		_plan_cache[key] = proj.placer().plan(v.id, v.use, v.units)
	var plan: SimBuildingPlacer.Plan = _plan_cache[key]
	if plan == null:
		return 0
	var progress := ParcelView.PROGRESS_FULL if v.development == ParcelView.DEVELOPMENT_BUILT else v.progress_pm
	var floors := 0
	for r in proj.placer().rows_for(plan, progress):
		floors += r.floors
	return floors


func _displayed_floors(proj: SimBuildingProjector) -> Dictionary:
	var cols := proj.columns()
	var out := {}
	for i in cols.count:
		out[cols.parcel_id[i]] = int(out.get(cols.parcel_id[i], 0)) + cols.floors[i]
	return out


## Sentetik kare sürücüsü: gün başına `fpd` kare; ilk kare tick'li. İş dağıtımı playable.gd'nin kullandığı
## `SimBuildingPump` ile AYNI (tick'li karede iş yok, bekleyen sütun varsa görünüm kurulumu, aksi halde bütçeli dilim).
## Dönüş: {max_lag, lag_hist, max_backlog, max_concurrent, built}.
func _drive(run: Dictionary, days: int, fpd: int) -> Dictionary:
	var f: SimFacade = run["facade"]
	var proj: SimBuildingProjector = run["proj"]
	var ids: PackedInt64Array = run["ids"]
	_plan_cache = {}
	var pump := SimBuildingPump.create(proj)
	var noop_view := func(_cols: BuildingColumns, _version: int) -> void: pass
	var streak := {}
	var max_lag := 0
	var worst_pid := -1
	var max_backlog := 0
	var max_concurrent := 0
	var built := 0
	var live := {}
	for pid in ids:
		live[int(pid)] = true
	var lag_days := 0
	var tracked_days := 0
	var bytes := PackedByteArray()
	var post_load_lag := 0
	var loaded := false
	for day in days:
		if day == int(run["save_day"]):
			bytes = (f as SimFacadeImpl).export_save()
		if day == int(run["load_day"]):
			assert_bool((f as SimFacadeImpl).import_save(bytes).ok).is_true()   # epoch++ (kare-60 smoke ile aynı)
			run["wave_size"] = 0   # geri sarmada sonraki öneriler kayıtta yok
			streak = {}
			live = {}
			for pid in ids:
				live[int(pid)] = true
			loaded = true
		f.advance(1)
		var wave := int(run["wave_size"])
		if wave > 0 and int(run["proposed"]) < ids.size():
			var from := int(run["proposed"])
			_propose(f, ids.slice(from, mini(from + wave, ids.size())))
			run["proposed"] = from + wave
		for frame in fpd:
			pump.frame(frame == 0, noop_view)
		max_backlog = maxi(max_backlog, proj.backlog_ticks())
		var shown := _displayed_floors(proj)
		var concurrent := 0
		for v in f.parcel_views(PackedInt64Array(live.keys())):
			if v.development == ParcelView.DEVELOPMENT_UNDER_CONSTRUCTION:
				concurrent += 1
			var expected := _expected_floors(proj, v)
			tracked_days += 1
			if int(shown.get(v.id, 0)) == expected:
				streak[v.id] = 0
				if v.development == ParcelView.DEVELOPMENT_BUILT:
					built += 1
					live.erase(v.id)   # nihai ve doğru gösteriliyor: bir daha okunmaz (BUILT terminaldir)
			else:
				streak[v.id] = int(streak.get(v.id, 0)) + 1
				lag_days += 1
				if int(streak[v.id]) > max_lag:
					max_lag = int(streak[v.id])
					worst_pid = v.id
				if loaded:
					post_load_lag = maxi(post_load_lag, int(streak[v.id]))
		max_concurrent = maxi(max_concurrent, concurrent)
	return {"post_load_lag": post_load_lag, "max_lag": max_lag, "worst": worst_pid, "max_backlog": max_backlog,
			"max_concurrent": max_concurrent, "built": built, "lag_days": lag_days, "tracked_days": tracked_days}


func test_feed_driven_sync_equals_exact_and_a_from_scratch_projector() -> void:
	var run := _run(ISOLATE, 60)
	var f: SimFacade = run["facade"]
	var proj: SimBuildingProjector = run["proj"]
	for day in 170:
		f.advance(1)
		proj.sync()
	var settled := proj.columns().state_hash()
	assert_int(proj.columns().count).is_greater(0)
	proj.sync(true)
	assert_str(proj.columns().state_hash()).override_failure_message("feed güdümlü sonuç sync(exact) ile farklı") \
			.is_equal(settled)
	var fresh := M2RenderSupport.projector(f)
	fresh.sync(true)
	assert_str(fresh.columns().state_hash()).override_failure_message("sıfırdan kurulan projector farklı") \
			.is_equal(settled)
	assert_int(int(proj.stats["full_syncs"])).is_equal(0)
	# Okuma yalnız gerçek değişimler: her gün tüm parselleri okumanın çok altında.
	assert_int(int(proj.stats["parcel_reads"])).is_less(60 * 170 / 4)


func test_idle_sim_costs_no_parcel_reads_at_all() -> void:
	var h := M2RenderSupport.handle(ISOLATE)   # öneri yok: hiçbir parsel değişmez
	var f := h.facade
	var proj := M2RenderSupport.projector(f)
	for day in 40:
		f.advance(1)
		proj.sync()
	assert_int(int(proj.stats["parcel_reads"])).is_equal(0)
	assert_int(int(proj.stats["full_syncs"])).is_equal(0)
	assert_int(proj.columns().count).is_equal(0)
	assert_bool(proj.busy()).is_false()


func test_low_frame_rates_never_leave_a_parcel_stale_longer_than_the_lag_bound() -> void:
	for fpd in [2, 4, 15, 60]:
		var run := _run(ISOLATE, LOAD_PARCELS, 3)   # günde 3 öneri: ~100 eşzamanlı inşaat, yayılı yük
		var res := _drive(run, 230, fpd)
		var proj: SimBuildingProjector = run["proj"]
		print("LAG fpd=%d %s reads=%d stage_polls=%d windows=%d changed=%d" % [fpd, str(res),
				int(proj.stats["parcel_reads"]), int(proj.stats["stage_polls"]), int(proj.stats["windows"]),
				int(proj.stats["changed_windows"])])
		assert_int(int(res["max_concurrent"])).override_failure_message(
				"fpd=%d: yük yeterince eşzamanlı inşaat üretmedi (%d)" % [fpd, int(res["max_concurrent"])]) \
				.is_greater_equal(70)
		assert_int(int(res["built"])).override_failure_message("fpd=%d: proje tamamlanmadı" % fpd).is_greater(20)
		assert_int(int(res["max_lag"])).override_failure_message(
				"fpd=%d: parsel %d %d gün gecikti (sınır %d) %s" % [fpd, int(res["worst"]), int(res["max_lag"]),
				MAX_LAG_DAYS, str(res)]).is_less_equal(MAX_LAG_DAYS)
		assert_int(int(res["max_backlog"])).override_failure_message(
				"fpd=%d: kuyruk %d gün" % [fpd, int(res["max_backlog"])]).is_less_equal(MAX_BACKLOG_DAYS)
		# Boşaltınca ve exact okumayla da aynı satırlar (kalıcı kayıp yok).
		var guard := 0
		var pump := SimBuildingPump.create(proj)
		while (proj.busy() or pump.view_pending()) and guard < 5000:
			pump.frame(false, func(_c: BuildingColumns, _v: int) -> void: pass)
			guard += 1
		var settled := proj.columns().state_hash()
		proj.sync(true)
		assert_str(proj.columns().state_hash()).override_failure_message("fpd=%d: boşaltınca exact ile farklı" % fpd) \
				.is_equal(settled)
		assert_int(int(proj.stats["full_syncs"])).is_equal(0)


## B-005: kayıt yükleme (epoch++) sonrası tam eşitleme tick'li karelerde de ilerler; satırlar sınırlı günde yetişir.
## `rewind`: false = aynı durumu yeniden yükle (oynanabilirin kare-60 smoke'u); true = 40 gün ÖNCEKİ kayda geri sar.
func _reload_case(fpd: int, rewind: bool) -> Dictionary:
	var run := _run(ISOLATE, LOAD_PARCELS, 3)
	run["save_day"] = 90 if rewind else 120
	run["load_day"] = 130 if rewind else 120
	var res := _drive(run, 260, fpd)
	var proj: SimBuildingProjector = run["proj"]
	print("RELOAD rewind=%s fpd=%d %s full_syncs=%d" % [str(rewind), fpd, str(res), int(proj.stats["full_syncs"])])
	assert_int(int(proj.stats["full_syncs"])).override_failure_message("fpd=%d: tam eşitleme sayısı" % fpd) \
			.is_equal(1)
	assert_int(int(res["post_load_lag"])).override_failure_message(
			"fpd=%d rewind=%s: yükleme sonrası %d gün gecikme (sınır %d) %s" % [fpd, str(rewind),
			int(res["post_load_lag"]), MAX_LAG_AFTER_LOAD_DAYS, str(res)]).is_less_equal(MAX_LAG_AFTER_LOAD_DAYS)
	var pump := SimBuildingPump.create(proj)
	var guard := 0
	while (proj.busy() or pump.view_pending()) and guard < 20000:
		pump.frame(false, func(_c: BuildingColumns, _v: int) -> void: pass)
		guard += 1
	var settled := proj.columns().state_hash()
	proj.sync(true)
	assert_str(proj.columns().state_hash()).override_failure_message("fpd=%d: exact ile farklı" % fpd).is_equal(settled)
	var fresh := M2RenderSupport.projector(run["facade"])
	fresh.sync(true)
	assert_str(fresh.columns().state_hash()).override_failure_message("fpd=%d: sıfırdan kurulandan farklı" % fpd) \
			.is_equal(settled)
	return res


func test_after_a_save_load_the_rows_catch_up_within_the_bound_at_every_frame_rate() -> void:
	for fpd in [2, 4, 15, 60]:
		_reload_case(fpd, false)


func test_after_rewinding_to_an_older_save_the_rows_catch_up_within_the_bound_at_every_frame_rate() -> void:
	for fpd in [2, 4, 15, 60]:
		_reload_case(fpd, true)


func test_feed_changes_right_after_a_load_are_not_lost() -> void:
	# Yüklemeden hemen sonra yeni onaylar/aşamalar gelir: tam eşitleme senkron biter, feed kaybolmaz; sonuç sıfırdan
	# kurulanla aynı.
	var run := _run(ISOLATE, 60, 4)
	var f: SimFacadeImpl = run["facade"]
	var proj: SimBuildingProjector = run["proj"]
	var ids: PackedInt64Array = run["ids"]
	var pump := SimBuildingPump.create(proj)
	var noop := func(_c: BuildingColumns, _v: int) -> void: pass
	for day in 30:
		f.advance(1)
		_propose(f, ids.slice(day * 2, day * 2 + 2))
		pump.frame(false, noop)
	var bytes := f.export_save()
	assert_bool(f.import_save(bytes).ok).is_true()
	for day in 120:
		f.advance(1)
		if day < 20 and 30 + day < ids.size():
			_propose(f, ids.slice(30 + day, 31 + day))
		for frame in 3:
			pump.frame(frame == 0, noop)
	assert_int(int(proj.stats["full_syncs"])).is_equal(1)
	var guard := 0
	while (proj.busy() or pump.view_pending()) and guard < 20000:
		pump.frame(false, noop)
		guard += 1
	var settled := proj.columns().state_hash()
	var fresh := M2RenderSupport.projector(f)
	fresh.sync(true)
	proj.sync(true)
	assert_str(proj.columns().state_hash()).is_equal(settled)
	assert_str(fresh.columns().state_hash()).is_equal(settled)


func test_virtual_clock_makes_the_lag_measurement_independent_of_wall_time() -> void:
	# Aynı koşu iki kez (arada gereksiz CPU yükü): sanal saat sonuçları BİREBİR aynı verir.
	var a := _drive(_run(ISOLATE, 60, 3), 120, 2)
	var burn := 0
	for i in 400000:
		burn += i
	var b := _drive(_run(ISOLATE, 60, 3), 120, 2)
	assert_str(str(a)).is_equal(str(b))
	assert_int(burn).is_greater(0)


func test_save_load_bumps_the_epoch_and_costs_exactly_one_full_sync_then_only_the_feed() -> void:
	var run := _run(ISOLATE, 50)
	var f: SimFacadeImpl = run["facade"]
	var proj: SimBuildingProjector = run["proj"]
	for day in 70:
		f.advance(1)
		proj.sync()
	var bytes := f.export_save()
	var early_hash := proj.columns().state_hash()
	assert_int(proj.columns().count).is_greater(0)
	# (a) AYNI tick'te yükleme: tick değişmez ama epoch değişir; busy() bunu görür.
	assert_bool(f.import_save(bytes).ok).is_true()
	assert_bool(proj.busy()).override_failure_message("epoch değişimi fark edilmedi").is_true()
	var rep := proj.sync()
	assert_bool(bool(rep["resync"])).is_true()
	assert_int(int(proj.stats["full_syncs"])).is_equal(1)
	assert_str(proj.columns().state_hash()).is_equal(early_hash)
	assert_bool(proj.busy()).is_false()
	# (b) İleri git, sonra eski kayda GERİ SAR: tek tam eşitleme, eski satırlar.
	for day in 60:
		f.advance(1)
		proj.sync()
	assert_str(proj.columns().state_hash()).is_not_equal(early_hash)
	assert_int(int(proj.stats["full_syncs"])).is_equal(1)
	assert_bool(f.import_save(bytes).ok).is_true()
	proj.sync()
	assert_int(int(proj.stats["full_syncs"])).is_equal(2)
	assert_str(proj.columns().state_hash()).is_equal(early_hash)
	# (c) Sonrasında yalnız feed: devam, kesintisiz sıfırdan kurulanla aynı; yeni tam eşitleme YOK.
	for day in 90:
		f.advance(1)
		proj.sync()
	assert_int(int(proj.stats["full_syncs"])).is_equal(2)
	var settled := proj.columns().state_hash()
	proj.sync(true)
	assert_str(proj.columns().state_hash()).is_equal(settled)
	var fresh := M2RenderSupport.projector(f)
	fresh.sync(true)
	assert_str(fresh.columns().state_hash()).is_equal(settled)


func test_a_freshly_attached_projector_to_a_loaded_state_does_one_full_sync() -> void:
	var run := _run(ISOLATE, 50)
	var f: SimFacadeImpl = run["facade"]
	var proj: SimBuildingProjector = run["proj"]
	for day in 80:
		f.advance(1)
		proj.sync()
	var bytes := f.export_save()
	var hb := M2RenderSupport.handle(ISOLATE)
	var fb := hb.facade
	var proj_b := M2RenderSupport.projector(fb)
	assert_bool(fb.import_save(bytes).ok).is_true()
	# Bütçeli adım bile tam eşitlemeyi TEK adımda (senkron) bitirir; T0 stoku ham okumada atlanır.
	var steps := 0
	while proj_b.busy() and steps < 20000:
		proj_b.step(FRAME_BUDGET_US)
		steps += 1
	assert_int(int(proj_b.stats["full_syncs"])).is_equal(1)
	assert_int(steps).override_failure_message("tam eşitleme tek adımda bitmedi").is_less_equal(8)
	assert_str(proj_b.columns().state_hash()).is_equal(proj.columns().state_hash())
	assert_int(int(proj_b.stats["parcel_reads"])).is_less_equal(fb.parcel_ids().size())


func test_an_incomplete_feed_triggers_one_full_sync_and_the_feed_resumes() -> void:
	# Pencere (16 tick) sorgudan kısa: tüketici geride kalınca `complete=false` => tek tam eşitleme.
	var patch := ISOLATE.duplicate(true)
	(patch["decision"] as Dictionary)["change_window_ticks"] = 16
	var run := _run(patch, 50)
	var f: SimFacade = run["facade"]
	var proj: SimBuildingProjector = run["proj"]
	for day in 10:
		f.advance(1)
		proj.sync()
	assert_int(int(proj.stats["full_syncs"])).is_equal(0)
	f.advance(60)   # senkron yok: son tüketilen tick penceresinin dışında
	assert_bool(f.parcel_changes_since(0).complete).is_false()
	var rep := proj.sync()
	assert_bool(bool(rep["resync"])).is_true()
	assert_int(int(proj.stats["full_syncs"])).is_equal(1)
	var fresh := M2RenderSupport.projector(f)
	fresh.sync(true)
	proj.sync(true)
	assert_str(proj.columns().state_hash()).is_equal(fresh.columns().state_hash())
	assert_int(proj.columns().count).is_greater(0)
	for day in 60:
		f.advance(1)
		proj.sync()
	assert_int(int(proj.stats["full_syncs"])).override_failure_message("feed sürmedi: ikinci tam eşitleme") \
			.is_equal(1)
	proj.sync(true)
	var fresh2 := M2RenderSupport.projector(f)
	fresh2.sync(true)
	assert_str(proj.columns().state_hash()).is_equal(fresh2.columns().state_hash())


func test_unplaceable_built_parcels_are_reported_not_silent() -> void:
	var h := M2RenderSupport.handle(ISOLATE)
	var f := h.facade
	var proj := M2RenderSupport.projector(f)
	var fx := M2RenderSupport.fixture()
	var occupied := {}
	for pid in (fx["settlement"] as SettlementResult).columns.occupied_parcels():
		occupied[int(pid)] = true
	var bad := PackedInt64Array()
	var good := M2RenderSupport.free_parcels(proj, 6, true)
	for v: ParcelView in fx["views"]:
		if bad.size() >= 6:
			break
		if not occupied.has(v.id) and proj.placer().plan(v.id, &"residential", maxi(1, v.area_m2 * 6 / 1000)) == null:
			bad.append(v.id)
	assert_int(bad.size()).override_failure_message("fixture'da yerleşemeyen parsel yok: test anlamsız").is_greater(0)
	f.advance(2)
	var all := PackedInt64Array(good)
	all.append_array(bad)
	_propose(f, all)
	for day in 170:
		f.advance(1)
		proj.sync()
	proj.sync(true)
	var built_bad := 0
	for v in f.parcel_views(bad):
		if v.development in [ParcelView.DEVELOPMENT_UNDER_CONSTRUCTION, ParcelView.DEVELOPMENT_BUILT,
				ParcelView.DEVELOPMENT_STALLED]:
			built_bad += 1
			assert_bool(proj.is_unplaced(v.id)).override_failure_message(
					"parsel %d sim'de %s ama yerleşemeyen listesinde yok" % [v.id, v.development]).is_true()
			assert_str(String(proj.unplaced_reason(v.id))).is_not_empty()
			assert_int(M2RenderSupport.rows_of(proj, v.id).size()).is_equal(0)
	assert_int(built_bad).override_failure_message("yerleşemeyen parsellerin hiçbiri yapılmadı: test anlamsız") \
			.is_greater(0)
	assert_int(proj.unplaced_count()).is_equal(built_bad)
	var ids := proj.unplaced_parcel_ids()
	assert_int(ids.size()).is_equal(built_bad)
	for i in range(1, ids.size()):
		assert_int(ids[i]).is_greater(ids[i - 1])
	var counts := proj.unplaced_reason_counts()
	var total := 0
	for r: String in counts:
		total += int(counts[r])
	assert_int(total).is_equal(built_bad)
	for v in f.parcel_views(good):
		assert_bool(proj.is_unplaced(v.id)).is_false()
	# Sıfırdan kurulan projector aynı listeyi verir; sayaç stats ile tutarlı.
	var fresh := M2RenderSupport.projector(f)
	fresh.sync(true)
	assert_array(Array(fresh.unplaced_parcel_ids())).is_equal(Array(ids))
	assert_int(int(proj.stats["unplaced"])).is_equal(built_bad)
