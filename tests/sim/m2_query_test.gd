extends SimTestBase
## T-040 (M2 ilk nedensel döngü), SİM tarafı: salt okunur sorgu/DTO genişlemesi. Karar kuralları DEĞİŞMEZ; yeni
## okumalar yalnız mevcut ekonomi/siyaset durumundan türer. Gerçek `PoliticsBootstrap` (oynanabilir sahnedeki kurulum)
## ve WorldFixture parselleri (F1/F2) kullanılır; sonuç zorlanmaz, yalnız başlangıç koşulları ve oyuncu komutu veridir.
##
## Ölçütler: 2 (olumlu + olumsuz yatırımcı kararı, gerekçeli), 3 (inşaat ilerlemesi sorgusu), 5 (ölçülebilir ekonomik
## sonuç), 6 (siyasi tepki), 9 (determinizm, kayıt/yükleme), 10 (sorgular salt okunur).

const M := preload("res://tests/sim/m2_support.gd")
const E := preload("res://tests/sim/economy/economy_test_support.gd")
## ESKİ koddan (sorgu genişlemesinden ÖNCE) kaydedilen durum hash'leri. Sorgular salt okunur olduğundan ve karar
## kuralları değişmediğinden bu değerler değişmemelidir; değişirse bir sorgu durum yazmış ya da kural kaymıştır.
## B-130/D-026 ile YENİLENDİ (sahip Q-040 "A"; bilinçli kural değişikliği): `bloc.react` petition eşiği 250 -> 190
## (`data/actors/decision_tables.json`). Neden: gerekçe kayıtları eşiği (ve histerezis eşiği 220 -> 160) taşır ve
## ReasonLog hash'e girer; A'da ek olarak bir petition kaydı daha OLUMLU (3 -> 4 olumlu, 60 -> 61 kayıt), B'de yalnız
## kayıtlardaki eşik alanı değişir (kayıt/olumlu/olay sayıları aynı: 6/2/1). ESKİ: A d66d81a9…27ebb2, B 3e85ce2c…b49d9
## (eşik 250 ile bire bir üretilir: `production/bugs/B-130.md`).
const GOLDEN_A := "ffbaf113645896e9d60c5c8eeba0ef6b8df5f54df8326b31b7bcbfd7678ae2e6"
const GOLDEN_B := "42abd619af18f2a9fb64298aa89bbe0d62a14db9d5af3f9c91cb715ffb27df9a"


func _view(f: SimFacade, id: int) -> ParcelView:
	return f.parcel_views(PackedInt64Array([id]))[0]


## Parselin yatırımcı karar gerekçeleri. `ParcelView.reason_ids` yalnız EN YENİ `parcel_reason_limit` gerekçeyi taşır ve
## sonradan gelen grup tepkileri yatırımcı kararını bu listeden itebilir (bulgu); tam liste `reasons_for` ile okunur.
func _investor_reasons(f: SimFacade, v: ParcelView) -> Array[ReasonRecord]:
	var out: Array[ReasonRecord] = []
	for r in f.reasons_for(v.ref()):
		if r.decision_key == &"decision.investor.develop":
			out.append(r)
	return out


func _factor(r: ReasonRecord, name_key: StringName) -> ReasonFactor:
	for fac in r.factors:
		if fac.name_key == name_key:
			return fac
	return null


# --- Ölçüt 9/10: durum hash'i eskisiyle bit-bit aynı; sorgular durumu değiştirmez ---

func test_state_hash_is_bit_identical_to_the_pre_change_recording_stress_scenario() -> void:
	assert_str(M.stress_run().state_hash()).is_equal(GOLDEN_A)


func test_state_hash_is_bit_identical_to_the_pre_change_recording_two_conditions_scenario() -> void:
	assert_str((M.two_conditions_run()["facade"] as SimFacadeImpl).state_hash()).is_equal(GOLDEN_B)


func test_every_read_query_leaves_the_state_hash_untouched() -> void:
	var run := M.two_conditions_run(M.SEED, 30)
	var f: SimFacadeImpl = run["facade"]
	var before := f.state_hash()
	var ids := f.parcel_ids()
	for _i in 3:
		f.parcel_views(ids)
		f.snapshot()
		f.economy_outcome()
		f.reasons_for(SimContract.parcel_ref(int(run["approved_parcel"])))
		f.events_since(0)
	assert_str(f.state_hash()).is_equal(before)
	# Sorgu ile ilerletilen koşu, hiç sorgulanmayan koşuyla aynı yere varır.
	f.advance(30)
	var quiet: SimFacadeImpl = M.two_conditions_run(M.SEED, 60)["facade"]
	assert_str(f.state_hash()).is_equal(quiet.state_hash())


# --- Ölçüt 3: ParcelView kullanım/birim/ilerleme ---

func test_parcel_view_follows_the_project_from_planned_through_built_with_monotonic_progress() -> void:
	var patch := E.merge(M.ISOLATE, E.regions({"F1": E.favorable(), "F2": E.unfavorable()}))
	var h := M.politics_handle(patch, 6)
	var f := h.facade
	var p1 := int(f.parcel_ids(E.R1)[0])
	var cfg := E.config(patch)
	var vacant := _view(f, p1)
	assert_str(String(vacant.development)).is_equal("vacant")
	assert_str(String(vacant.use)).is_empty()
	assert_int(vacant.units).is_equal(0)
	assert_int(vacant.progress_pm).is_equal(0)
	assert_bool(vacant.developed_by_sim).is_false()
	f.submit_command(SimCommand.zoning_propose(PackedInt64Array([p1]), &"zone.mixed"))
	var stages: Array[String] = []
	var last_progress := -1
	var saw_mid := false
	for _day in 200:
		f.advance(1)
		var v := _view(f, p1)
		if stages.is_empty() or stages[-1] != String(v.development):
			stages.append(String(v.development))
		assert_array(SimContractChecks.check_parcel_projects([v])).is_empty()
		assert_int(v.progress_pm).override_failure_message("ilerleme geri gitti").is_greater_equal(last_progress)
		last_progress = v.progress_pm
		if v.development == ParcelView.DEVELOPMENT_UNDER_CONSTRUCTION:
			var rec := EconomyQuery.parcel_record(f.game_state(), p1)
			var total: int = cfg.use_param(EconomyConfig.USE_RESIDENTIAL, "construction_base_days") \
				+ v.units * cfg.use_param(EconomyConfig.USE_RESIDENTIAL, "construction_days_per_unit")
			@warning_ignore("integer_division")
			var expected: int = (total - int(rec["days_left"])) * 1000 / total
			assert_int(v.progress_pm).override_failure_message("ilerleme days_left/toplam'dan türemeli").is_equal(expected)
			saw_mid = saw_mid or (v.progress_pm > 0 and v.progress_pm < 1000)
		if v.development == ParcelView.DEVELOPMENT_PLANNED:
			assert_int(v.progress_pm).is_equal(0)
		if v.development != ParcelView.DEVELOPMENT_VACANT:
			assert_str(String(v.use)).is_equal("residential")
			assert_int(v.units).is_greater(0)
			assert_bool(v.developed_by_sim).is_true()
	assert_array(stages).is_equal(["vacant", "planned", "under_construction", "built"])
	assert_bool(saw_mid).override_failure_message("inşaat ortası ilerleme görülmedi").is_true()
	assert_int(last_progress).is_equal(1000)


func test_declined_parcel_stays_empty_in_the_view() -> void:
	var run := M.two_conditions_run()
	var v := _view(run["facade"], int(run["declined_parcel"]))
	assert_str(String(v.development)).is_equal("vacant")
	assert_str(String(v.use)).is_empty()
	assert_int(v.units).is_equal(0)
	assert_int(v.progress_pm).is_equal(0)
	assert_bool(v.developed_by_sim).is_false()


func test_t0_stock_parcels_are_not_marked_as_developed_by_sim_but_new_ones_are() -> void:
	var patch := E.merge(M.ISOLATE, E.regions({"F1": E.favorable(), "F2": E.unfavorable()}))
	var source := FacadeTestSupport.fixture_source(6)
	var ids_f1 := source.parcel_ids(E.R1)
	var stock_a := int(ids_f1[ids_f1.size() - 1])
	var stock_b := int(ids_f1[ids_f1.size() - 2])
	var stock := ListStockSource.create([
		{"parcel_id": stock_a, "use": "residential", "units": 8, "owner": 0},
		{"parcel_id": stock_b, "use": "commercial", "units": 3, "owner": 1},
	])
	var h := M.politics_handle(patch, 6, M.SEED, stock)
	var f := h.facade
	var target := int(ids_f1[0])
	f.submit_command(SimCommand.zoning_propose(PackedInt64Array([target]), &"zone.mixed"))
	f.advance(150)
	var a := _view(f, stock_a)
	assert_str(String(a.development)).is_equal("built")
	assert_str(String(a.use)).is_equal("residential")
	assert_int(a.units).is_equal(8)
	assert_int(a.progress_pm).is_equal(1000)
	assert_bool(a.developed_by_sim).override_failure_message("T0 stoku sim gelişimi sayılmamalı").is_false()
	var b := _view(f, stock_b)
	assert_str(String(b.use)).is_equal("commercial")
	assert_int(b.units).is_equal(3)
	assert_bool(b.developed_by_sim).is_false()
	var t := _view(f, target)
	assert_str(String(t.development)).is_equal("built")
	assert_int(t.progress_pm).is_equal(1000)
	assert_bool(t.developed_by_sim).is_true()
	assert_array(SimContractChecks.check_parcel_projects(f.parcel_views(f.parcel_ids()))).is_empty()
	assert_array(SimContractChecks.check_facade(f)).is_empty()


func test_facade_without_economy_leaves_project_fields_at_defaults() -> void:
	var f := FacadeTestSupport.facade(3)
	f.advance(40)
	for v in f.parcel_views(f.parcel_ids()):
		assert_str(String(v.use)).is_empty()
		assert_int(v.units).is_equal(0)
		assert_int(v.progress_pm).is_equal(0)
		assert_bool(v.developed_by_sim).is_false()


# --- Ölçüt 2: aynı komut, iki koşul, gerekçeli olumlu ve olumsuz karar ---

func test_same_zoning_command_gives_one_approved_and_one_coded_decline_each_readable_through_the_facade() -> void:
	for seed_value in range(1, 7):  # sonuç RNG gürültüsünden bağımsız
		var run := M.two_conditions_run(seed_value)
		var f: SimFacadeImpl = run["facade"]
		var yes_ref := SimContract.parcel_ref(int(run["approved_parcel"]))
		var no_ref := SimContract.parcel_ref(int(run["declined_parcel"]))
		var yes_view := _view(f, int(run["approved_parcel"]))
		var no_view := _view(f, int(run["declined_parcel"]))
		assert_str(String(yes_view.development)).override_failure_message("seed %d" % seed_value) \
			.is_not_equal("vacant")
		assert_str(String(no_view.development)).is_equal("vacant")
		# Gerekçe parsel görünümünden ve konu sorgusundan okunur (HUD "Nedenini gör").
		var good_all := _investor_reasons(f, yes_view)
		var bad_all := _investor_reasons(f, no_view)
		assert_int(good_all.size()).override_failure_message("seed %d: olumlu karar gerekçesi" % seed_value).is_equal(1)
		assert_int(bad_all.size()).override_failure_message("seed %d: olumsuz karar gerekçesi" % seed_value).is_equal(1)
		var good := good_all[0]
		var bad := bad_all[0]
		assert_str(String(good.outcome)).is_equal("positive")
		assert_str(String(bad.outcome)).is_equal("negative")
		assert_bool(good.is_consistent() and bad.is_consistent()).is_true()
		assert_int(good.score).is_greater_equal(good.threshold)
		assert_int(bad.score).is_less(bad.threshold)
		assert_str(String(good.decision_key)).is_equal("decision.investor.develop")
		assert_array(Array(good.subjects)).contains([String(yes_ref), "command.1"])
		assert_array(Array(bad.subjects)).contains([String(no_ref), "command.1"])
		assert_int(f.reasons_for(yes_ref).size()).is_greater(0)
		assert_int(f.reasons_for(no_ref).size()).is_greater(0)
		# Kodlu ret: altyapı engel etkeni, olumlu kararda aynı etken engel değil.
		var infra_bad := _factor(bad, &"reason.factor.infrastructure_capacity")
		assert_int(infra_bad.value).is_equal(-1000)
		assert_int(_factor(good, &"reason.factor.infrastructure_capacity").value).is_greater(-1000)
		var declined_events := f.events_since(0).filter(
			func(e: SimEvent) -> bool: return e.message_key == &"event.investor.declined")
		assert_int(declined_events.size()).is_equal(1)
		assert_str(String(declined_events[0].args["code"])).is_equal("infrastructure_exhausted")
		assert_array(Array(declined_events[0].reason_ids)).contains([bad.id])


func test_outcome_is_derived_from_conditions_not_from_the_parcel_so_swapping_conditions_swaps_the_result() -> void:
	var patch := E.merge(M.ISOLATE, E.regions({"F1": E.unfavorable(), "F2": E.favorable()}))
	var h := M.politics_handle(patch, 6)
	var f := h.facade
	var p1 := int(f.parcel_ids(E.R1)[0])
	var p2 := int(f.parcel_ids(E.R2)[0])
	f.submit_command(SimCommand.zoning_propose(PackedInt64Array([p1, p2]), &"zone.mixed"))
	f.advance(60)
	assert_str(String(_view(f, p1).development)).is_equal("vacant")
	assert_str(String(_view(f, p2).development)).is_not_equal("vacant")


func test_no_private_building_appears_without_a_recorded_investor_decision_and_no_command_means_no_building() -> void:
	var patch := E.merge(M.ISOLATE, E.regions({"F1": E.favorable(), "F2": E.favorable()}))
	var f := M.politics_handle(patch, 6).facade
	f.advance(120)  # oyuncu komutu yok, periyodik tarama kapalı
	for v in f.parcel_views(f.parcel_ids()):
		assert_str(String(v.development)).is_equal("vacant")
		assert_bool(v.developed_by_sim).is_false()
	var run := M.two_conditions_run()
	var g: SimFacadeImpl = run["facade"]
	for v in g.parcel_views(g.parcel_ids()):
		if v.developed_by_sim:
			var decisions := _investor_reasons(g, v)
			assert_int(decisions.size()).override_failure_message("kararsız gelişme: %d" % v.id).is_greater(0)
			assert_str(String(decisions[0].outcome)).is_equal("positive")


# --- Ölçüt 5: ölçülebilir ekonomik sonuç ---

func test_outcome_is_unavailable_without_an_economy_with_a_reason_and_no_numbers() -> void:
	var f := FacadeTestSupport.facade(3)
	var o := f.economy_outcome()
	assert_bool(o.available).is_false()
	assert_str(String(o.unavailable_reason_key)).is_equal("economy.not_built")
	assert_array(o.regions).is_empty()
	assert_str(String(o.provenance)).is_equal("sim")
	assert_bool(f.snapshot().extensions["x.sim.available.economy"]).is_false()


func test_outcome_is_honestly_not_started_before_the_first_tick_and_ready_after() -> void:
	var f := M.stress_run(M.SEED, 0)
	var o := f.economy_outcome()
	assert_bool(o.available).is_false()
	assert_str(String(o.unavailable_reason_key)).is_equal("economy.not_started")
	assert_array(o.regions).is_empty()
	f.advance(1)
	assert_bool(f.economy_outcome().available).is_true()


func test_outcome_before_and_after_the_loop_shows_new_units_households_and_investor_rent() -> void:
	var f := M.stress_run(M.SEED, 1)
	var before := f.economy_outcome()
	assert_bool(before.available).is_true()
	assert_bool(f.snapshot().extensions["x.sim.available.economy"]).is_true()
	assert_int(before.tick).is_equal(1)
	assert_int(before.projects_completed).is_equal(0)
	assert_int(before.metrics()["sim_residential_units"]).is_equal(0)
	f.advance(149)
	var after := f.economy_outcome()
	assert_int(after.tick).is_equal(150)
	var d := after.delta_since(before)
	assert_int(d["investments_approved"]).is_greater(0)
	assert_int(d["projects_completed"]).is_greater(0)
	assert_int(d["residential_units"]).override_failure_message("yeni konut birimi").is_greater(0)
	assert_int(d["residential_pipeline"]).is_greater_equal(-d["residential_units"])
	assert_int(d["rent_income"]).override_failure_message("yatırımcı kira geliri").is_greater(0)
	assert_int(d["construction_spend"]).is_greater(0)
	# Hane/talep göstergeleri gerçek bölge kohortundan: barınan hane en fazla bekleyen hane ve konut stoğu kadar.
	for r in after.regions:
		assert_int(r.housed_households).is_less_equal(r.households)
		assert_int(r.housed_households).is_less_equal(r.residential_units)
	assert_int(after.metrics()["housed_households"]).is_greater(before.metrics()["housed_households"])
	# Belediye geliri sim'de yok (T-014 kurulmadı): uydurma sayı yok, kısa neden var.
	assert_bool(after.municipal_revenue_available).is_false()
	assert_str(String(after.municipal_revenue_reason_key)).is_equal("economy.municipal_revenue.not_built")
	assert_int(after.municipal_revenue).is_equal(0)
	assert_bool(f.snapshot().budget.revenue == 0 and not f.snapshot().extensions["x.sim.available.budget"]).is_true()


func test_sim_developed_units_equal_the_sum_over_parcels_marked_developed_by_sim() -> void:
	var f := M.stress_run(M.SEED, 150)
	var by_region := {}
	for v in f.parcel_views(f.parcel_ids()):
		if v.developed_by_sim and v.development == ParcelView.DEVELOPMENT_BUILT:
			by_region[v.region_code] = int(by_region.get(v.region_code, 0)) + v.units
	var o := f.economy_outcome()
	var total := 0
	for r in o.regions:
		assert_int(r.sim_residential_units + r.sim_commercial_units) \
			.override_failure_message("bölge %s" % r.region_code).is_equal(int(by_region.get(r.region_code, 0)))
		total += r.sim_residential_units + r.sim_commercial_units
	assert_int(total).is_greater(0)
	# Stok yok: sim'in tamamladığı birim = bölge konut+ticaret stoğu.
	assert_int(o.metrics()["residential_units"] + o.metrics()["commercial_units"]).is_equal(total)


func test_outcome_sim_units_stay_correct_when_a_completion_happens_between_two_reads() -> void:
	var f := M.stress_run(M.SEED, 60)
	var mid := f.economy_outcome()
	f.advance(60)
	var late := f.economy_outcome()
	assert_int(late.metrics()["sim_residential_units"]).is_greater(mid.metrics()["sim_residential_units"])
	var again := f.economy_outcome()
	assert_bool(again.same_as(late)).override_failure_message("aynı tickte iki okuma aynı olmalı").is_true()


# --- Ölçüt 6: siyasi sonuç ---

func test_the_loop_produces_real_group_reactions_in_opposite_directions_that_point_back_to_the_causes() -> void:
	var f := M.stress_run(M.SEED, 120)
	var snap := f.snapshot()
	assert_bool(snap.extensions["x.sim.available.groups"]).is_true()
	var reactions: Dictionary = {}
	for g in snap.group_reactions:
		reactions[g.reaction] = g
	assert_bool(reactions.has(GroupReactionView.REACTION_SUPPORT)).override_failure_message("destek tepkisi yok").is_true()
	assert_bool(reactions.has(GroupReactionView.REACTION_OPPOSE)).override_failure_message("itiraz tepkisi yok").is_true()
	var support: GroupReactionView = reactions[GroupReactionView.REACTION_SUPPORT]
	var oppose: GroupReactionView = reactions[GroupReactionView.REACTION_OPPOSE]
	assert_str(String(support.group.ref())).is_not_equal(String(oppose.group.ref()))
	assert_int(support.stance).is_greater(0)
	assert_int(oppose.stance).is_less(0)
	assert_array(SimContractChecks.check_no_aggregate_score(snap.to_dict(), "snapshot")).is_empty()
	for g: GroupReactionView in [support, oppose]:
		assert_int(g.reason_ids.size()).override_failure_message("tepkinin gerekçesi yok").is_greater(0)
		assert_array(SimContractChecks.check_reason_id(f, int(g.reason_ids[0]), "group")).is_empty()
		assert_int(g.cause_refs.size()).override_failure_message("tepki nedeni (cause_refs) yok").is_greater(0)
	var kinds := {}
	for e in f.events_since(0):
		kinds[e.kind] = true
	assert_bool(kinds.has(SimEvent.KIND_GROUP_REACTED)).is_true()


func test_a_group_reaction_exists_in_the_two_conditions_loop_too() -> void:
	var f: SimFacadeImpl = M.two_conditions_run()["facade"]
	var reacted := f.events_since(0).filter(func(e: SimEvent) -> bool: return e.kind == SimEvent.KIND_GROUP_REACTED)
	assert_int(reacted.size()).is_greater(0)
	var g := f.snapshot().group_reactions
	assert_bool(g.any(func(v: GroupReactionView) -> bool: return v.reaction != GroupReactionView.REACTION_NEUTRAL)) \
		.is_true()


# --- Ölçüt 9: determinizm, kayıt/yükleme ---

func test_same_seed_and_commands_give_identical_views_and_outcome_and_other_seeds_differ() -> void:
	var a: SimFacadeImpl = M.two_conditions_run(M.SEED, 80)["facade"]
	var b: SimFacadeImpl = M.two_conditions_run(M.SEED, 80)["facade"]
	assert_str(a.state_hash()).is_equal(b.state_hash())
	assert_bool(a.economy_outcome().same_as(b.economy_outcome())).is_true()
	assert_str(StateHash.of(SimDto.dicts_of(a.parcel_views(a.parcel_ids())))) \
		.is_equal(StateHash.of(SimDto.dicts_of(b.parcel_views(b.parcel_ids()))))
	var c: SimFacadeImpl = M.two_conditions_run(M.SEED + 1, 80)["facade"]
	assert_str(c.state_hash()).is_not_equal(a.state_hash())


func test_save_in_the_middle_of_construction_then_load_continues_to_the_same_result() -> void:
	var run := M.two_conditions_run(M.SEED, 20)
	var f: SimFacadeImpl = run["facade"]
	var p1 := int(run["approved_parcel"])
	for _day in 100:  # inşaat ortasına kadar (planlama + inşaat süreleri veridir)
		if _view(f, p1).progress_pm >= 300:
			break
		f.advance(1)
	var mid := _view(f, p1)
	assert_str(String(mid.development)).is_equal("under_construction")
	assert_int(mid.progress_pm).is_between(1, 999)
	var bytes := f.export_save()
	var fresh_run := M.politics_handle(E.merge(M.ISOLATE, E.regions({"F1": E.favorable(), "F2": E.unfavorable()})), 6)
	var g := fresh_run.facade
	var loaded := g.import_save(bytes)
	assert_bool(loaded.ok).override_failure_message(loaded.message).is_true()
	assert_bool(_view(g, p1).same_as(mid)).override_failure_message("yükleme sonrası görünüm aynı olmalı").is_true()
	assert_bool(g.economy_outcome().same_as(f.economy_outcome())).is_true()
	f.advance(120)
	g.advance(120)
	assert_str(g.state_hash()).is_equal(f.state_hash())
	assert_str(String(_view(g, p1).development)).is_equal("built")
	assert_int(_view(g, p1).progress_pm).is_equal(1000)
	assert_bool(g.economy_outcome().same_as(f.economy_outcome())).is_true()
