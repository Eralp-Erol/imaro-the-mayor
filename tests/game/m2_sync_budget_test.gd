extends GdUnitTestSuite
## T-040 ölçüt 10 · Projector'ın BÜTÇELİ dilimli çalışması (başsız, gerçek bileşenler): iş birimlere bölünür
## (bütçe 0 => adım başına en çok bir birim), kuyruk boşalır, sonuç `sync(exact)` ile ve sıfırdan kurulan projector
## ile bit-bit aynıdır, kayıt/yükleme sonrası aynı sonuç, kademe-zamanlı yoklama her gün okumaktan çok daha az
## parsel okur.

const ISOLATE := M2RenderSupport.ISOLATE


## Kare benzetimi: her sim gününden sonra `frames` kare, kare başına `budget_us` bütçeli tek adım.
func _run_framed(f: SimFacade, proj: SimBuildingProjector, days: int, frames: int, budget_us: int) -> void:
	for day in days:
		f.advance(1)
		for frame in frames:
			proj.step(budget_us)


func _drain(proj: SimBuildingProjector, budget_us: int = 0, limit: int = 20000) -> int:
	var steps := 0
	while proj.busy() and steps < limit:
		proj.step(budget_us)
		steps += 1
	return steps


func _scenario(n: int = 6) -> Dictionary:
	var h := M2RenderSupport.handle(ISOLATE)
	var f := h.facade
	var proj := M2RenderSupport.projector(f)
	var ids := M2RenderSupport.free_parcels(proj, n, true)
	f.advance(2)
	f.submit_command(SimCommand.zoning_propose(ids, &"zone.mixed"))
	return {"facade": f, "proj": proj, "ids": ids}


func test_zero_budget_runs_at_most_one_unit_per_step_and_the_queue_drains() -> void:
	# 40 parsel: günlerce birikmiş iş TEK pencerede birleşir (feed), ama VIEW_CHUNK'tan büyük olduğu için dilimlenir.
	var run := _scenario(40)
	var f: SimFacade = run["facade"]
	var proj: SimBuildingProjector = run["proj"]
	f.advance(25)   # 25 günlük iş birikti (zoning + onay + planlı)
	assert_bool(proj.busy()).is_true()
	assert_int(proj.backlog_ticks()).is_greater(20)
	var steps := 0
	while proj.busy() and steps < 5000:
		var units_before := int(proj.stats.get("units", 0))
		proj.step(0)
		assert_int(int(proj.stats.get("units", 0)) - units_before).override_failure_message(
				"sıfır bütçede adım başına birden çok birim").is_less_equal(1)
		steps += 1
	assert_bool(proj.busy()).override_failure_message("kuyruk boşalmadı (%d adım)" % steps).is_false()
	assert_int(proj.backlog_ticks()).is_equal(0)
	assert_int(steps).override_failure_message("iş tek adıma sığmış: dilimleme yok").is_greater(3)


func test_budgeted_framed_run_settles_to_the_exact_and_to_a_fresh_projectors_rows() -> void:
	var run := _scenario(8)
	var f: SimFacade = run["facade"]
	var proj: SimBuildingProjector = run["proj"]
	_run_framed(f, proj, 170, 12, 1200)
	_drain(proj, 1200)
	var settled := proj.columns().state_hash()
	assert_int(proj.columns().count).is_greater(0)
	proj.sync(true)
	assert_str(proj.columns().state_hash()).override_failure_message(
			"dilimli sonuç exact ile farklı").is_equal(settled)
	var fresh := M2RenderSupport.projector(f)
	fresh.sync(true)
	assert_str(fresh.columns().state_hash()).is_equal(settled)
	assert_int(int(proj.stats["full_syncs"])).override_failure_message("feed ile tam eşitleme gerekmemeliydi").is_equal(0)


func test_few_frames_per_day_still_settle_and_do_not_fall_behind_forever() -> void:
	var run := _scenario(6)
	var f: SimFacade = run["facade"]
	var proj: SimBuildingProjector = run["proj"]
	_run_framed(f, proj, 170, 2, 1200)   # gün başına yalnız 2 kare: kuyruk birikebilir
	_drain(proj, 1200)
	assert_bool(proj.busy()).is_false()
	var settled := proj.columns().state_hash()
	proj.sync(true)
	assert_str(proj.columns().state_hash()).is_equal(settled)


func test_save_load_then_budgeted_steps_gives_the_same_rows() -> void:
	var run := _scenario(6)
	var f: SimFacadeImpl = run["facade"]
	var proj_a: SimBuildingProjector = run["proj"]
	_run_framed(f, proj_a, 45, 12, 1200)
	var bytes := f.export_save()
	_drain(proj_a, 1200)
	proj_a.sync(true)
	var hb := M2RenderSupport.handle(ISOLATE)
	var proj_b := M2RenderSupport.projector(hb.facade)
	assert_bool(hb.facade.import_save(bytes).ok).is_true()
	_drain(proj_b, 1200)
	proj_b.sync(true)
	assert_str(proj_b.columns().state_hash()).override_failure_message("yükleme sonrası dilimli satırlar farklı") \
			.is_equal(proj_a.columns().state_hash())


func test_stage_timed_polling_reads_far_fewer_parcels_than_polling_every_inflight_project_daily() -> void:
	var run := _scenario(8)
	var f: SimFacade = run["facade"]
	var proj: SimBuildingProjector = run["proj"]
	var inflight_days := 0
	for day in 150:
		f.advance(1)
		for v in f.parcel_views(run["ids"]):
			if v.developed_by_sim and v.development in [ParcelView.DEVELOPMENT_PLANNED,
					ParcelView.DEVELOPMENT_UNDER_CONSTRUCTION, ParcelView.DEVELOPMENT_STALLED]:
				inflight_days += 1
		proj.sync()
	var reads := int(proj.stats["parcel_reads"])
	assert_int(inflight_days).is_greater(100)
	assert_int(reads).override_failure_message("okuma %d, her gün okuma %d" % [reads, inflight_days]) \
			.is_less(inflight_days / 2)
	# Daha az okumaya rağmen sonuç aynı: exact ile eşit.
	var settled := proj.columns().state_hash()
	proj.sync(true)
	assert_str(proj.columns().state_hash()).is_equal(settled)


func test_a_slice_never_exceeds_a_unit_of_work_even_with_a_huge_backlog() -> void:
	var run := _scenario(8)
	var f: SimFacade = run["facade"]
	var proj: SimBuildingProjector = run["proj"]
	f.advance(120)   # tek seferde 120 gün: olay günlüğü taşar, denetim başlar
	var max_ms := 0.0
	var steps := 0
	while proj.busy() and steps < 20000:
		max_ms = maxf(max_ms, float(proj.step(1200)["ms"]))
		steps += 1
	assert_bool(proj.busy()).is_false()
	# Başsız CPU'da tek dilim: 120 günlük birikmiş işte bile birkaç ms (yük altında gevşek sınır; 8 ms kare hedefi).
	assert_float(max_ms).override_failure_message("tek adım %.2f ms" % max_ms).is_less(25.0)
	var settled := proj.columns().state_hash()
	proj.sync(true)
	assert_str(proj.columns().state_hash()).is_equal(settled)
