extends SimTestBase
## T-045 (B-001/B-002 sim tarafı) · kalıcı karar özeti (`ParcelView.decision*`) ve olay ufkundan bağımsız değişen-parsel
## sorgusu (`SimFacade.parcel_changes_since`). Karar KURALLARI ve gerekçe/olay ufku kuralı DEĞİŞMEZ; yeni okumalar
## mevcut ekonomi sütunlarından / durum DIŞI geçici halkadan türer (durum hash'i ve kayıt biçimi eskisiyle aynı).
##
## Yük senaryosu (`LOAD_PATCH`): 3000 parsel / 2 bölge, bol sermaye ve altyapı, sık tarama. Ölçülen: ~80 gerekçe/gün,
## tepe >= 700 eşzamanlı proje, gerekçe günlüğü (kapasite 1000) ilk ~13 günde döner. Yatırımcı kararı gerçek
## `EconomySystem` kararıdır (zorlanmış sonuç yok); yalnız sermaye/altyapı başlangıç koşuludur.

const M := preload("res://tests/sim/m2_support.gd")
const E := preload("res://tests/sim/economy/economy_test_support.gd")
const Q := preload("res://tests/sim/m2_query_test.gd")

const LOAD_DAYS := 120
const LOAD_PARCELS := 3000
const LOAD_PATCH := {
	"decision": {
		"review_period_days": 5, "max_reviews_per_tick": 80, "max_starts_per_region_per_day": 40,
		"decline_backoff_days": 3, "negative_repeat_days": 10,
	},
	"investors": {"list": [
		{"capital": 100000000, "threshold_shift": -30, "monthly_inflow": 6000},
		{"capital": 100000000, "threshold_shift": 0, "monthly_inflow": 6000},
	]},
	"regions": {"defaults": {"initial_households": 4000, "infra_capacity_units": 200000}},
}
const DECLINE_CODES: Array[String] = [
	"zoning_not_buildable", "infrastructure_exhausted", "insufficient_financing", "demand_too_low", "return_too_low",
]


func _load_handle(extra: Dictionary = {}) -> EconomyHandle:
	return E.synthetic_handle(LOAD_PARCELS, 2, E.merge(LOAD_PATCH, extra), SEED)


## Görünür karar/aşama özeti. `decision_reason_id` (budanınca sessizce 0'a düşer), `progress_pm` (her gün ilerler),
## `land_value` ve `reason_ids` BİLEREK dışarıda: sorgunun kapsamı `ParcelChangeFeed` belgesindedir.
static func _tuple(v: ParcelView) -> Array:
	return [String(v.development), String(v.use), v.units, 0 if v.owner == null else v.owner.id,
		v.developed_by_sim, String(v.decision), String(v.decision_code), v.decision_tick]


func _truth(f: SimFacade, ids: PackedInt64Array) -> Dictionary:
	var out := {}
	for v in f.parcel_views(ids):
		out[v.id] = _tuple(v)
	return out


func _changed_between(before: Dictionary, after: Dictionary) -> Array:
	var out: Array = []
	for id: int in after:
		if before.get(id, null) != after[id]:
			out.append(id)
	out.sort()
	return out


func _parcel_of(e: SimEvent) -> int:
	return int(SimContract.parse_ref(StringName(e.subjects[0]))["id"])


# --- (a) Kalıcı karar özeti: gerekçe günlüğü dönse de doğru kalır (B-001) ---

func test_decision_summary_stays_correct_after_the_reason_log_rotated_many_times() -> void:
	var f := _load_handle().facade
	var oracle := {}  # parsel -> son `actor.decided` olayı (bağımsız gerçek: olaylar her gün yoklanır, kayıp yok)
	var last_seq := 0
	for _day in LOAD_DAYS:
		f.advance(1)
		for e in f.events_since(last_seq):
			last_seq = e.seq
			if e.kind == SimEvent.KIND_ACTOR_DECIDED:
				oracle[_parcel_of(e)] = e
	var st := f.game_state()
	assert_int(st.reasons.last_id() / LOAD_DAYS).override_failure_message("günde >= 60 gerekçe beklenir") \
		.is_greater_equal(60)
	assert_int(st.reasons.first_id()).override_failure_message("günlük en az iki kez dönmüş olmalı") \
		.is_greater(2 * int(st.config["reason_log_capacity"]))
	var views := f.parcel_views(PackedInt64Array(oracle.keys()))
	assert_int(views.size()).is_equal(oracle.size())
	var pruned := 0
	var alive := 0
	for v in views:
		var e: SimEvent = oracle[v.id]
		if e.message_key == &"event.investor.develop":
			assert_str(String(v.decision)).is_equal("approved")
			assert_str(String(v.decision_code)).is_equal("approved")
			assert_str(String(v.development)).is_not_equal("vacant")
		else:
			assert_str(String(e.message_key)).is_equal("event.investor.declined")
			assert_str(String(v.decision)).is_equal("declined")
			assert_str(String(v.decision_code)).is_equal(String(e.args["code"]))
			assert_str(String(v.development)).is_equal("vacant")
		assert_int(v.decision_tick).is_equal(e.tick)
		var rid := int(e.reason_ids[0])
		if rid < st.reasons.first_id():
			pruned += 1
			assert_int(v.decision_reason_id).override_failure_message("budanmış gerekçe 0 olmalı (parsel %d)" % v.id) \
				.is_equal(0)
		else:
			alive += 1
			assert_int(v.decision_reason_id).is_equal(rid)
			assert_object(f.reason(v.decision_reason_id)).is_not_null()
	assert_int(pruned).override_failure_message("budanmış karar görülmedi: test anlamsız").is_greater(500)
	assert_int(alive).is_greater(0)
	assert_array(SimContractChecks.check_parcels(f, f.snapshot())).is_empty()


func test_built_parcel_keeps_approved_and_vacant_parcel_keeps_declined_with_resolvable_reasons() -> void:
	var run := M.two_conditions_run(M.SEED, 200)
	var f: SimFacadeImpl = run["facade"]
	var built := f.parcel_views(PackedInt64Array([int(run["approved_parcel"])]))[0]
	assert_str(String(built.development)).is_equal("built")
	assert_str(String(built.decision)).is_equal("approved")
	assert_str(String(built.decision_code)).is_equal("approved")
	assert_int(built.decision_tick).is_greater(0)
	assert_int(built.decision_tick).is_less(built.decision_tick + 200)
	var why := f.reason(built.decision_reason_id)
	assert_object(why).is_not_null()
	assert_str(String(why.decision_key)).is_equal("decision.investor.develop")
	assert_str(String(why.outcome)).is_equal("positive")
	assert_int(why.tick).is_equal(built.decision_tick)
	assert_str(String(why.actor.ref())).is_equal(String(built.owner.ref()))
	var vacant := f.parcel_views(PackedInt64Array([int(run["declined_parcel"])]))[0]
	assert_str(String(vacant.development)).is_equal("vacant")
	assert_str(String(vacant.decision)).is_equal("declined")
	assert_bool(DECLINE_CODES.has(String(vacant.decision_code))).is_true()
	assert_int(vacant.decision_tick).is_greater(0)
	var no := f.reason(vacant.decision_reason_id)
	assert_object(no).is_not_null()
	assert_str(String(no.decision_key)).is_equal("decision.investor.develop")
	assert_str(String(no.outcome)).is_equal("negative")
	assert_int(no.tick).is_equal(vacant.decision_tick)
	assert_array(SimContractChecks.check_parcels(f, f.snapshot())).is_empty()


func test_untouched_parcels_and_t0_stock_have_no_decision() -> void:
	var patch := E.merge(M.ISOLATE, E.regions({"F1": E.favorable(), "F2": E.unfavorable()}))
	var source := FacadeTestSupport.fixture_source(6)
	var ids_f1 := source.parcel_ids(E.R1)
	var stock_id := int(ids_f1[ids_f1.size() - 1])
	var stock := ListStockSource.create([{"parcel_id": stock_id, "use": "residential", "units": 8, "owner": 0}])
	var h := M.politics_handle(patch, 6, M.SEED, stock)
	h.facade.advance(30)
	var views := h.facade.parcel_views(h.facade.parcel_ids())
	for v in views:
		assert_str(String(v.decision)).override_failure_message("parsel %d" % v.id).is_equal("")
		assert_int(v.decision_tick).is_equal(-1)
		assert_int(v.decision_reason_id).is_equal(0)
	assert_array(SimContractChecks.check_parcel_decisions(views)).is_empty()


func test_stalled_project_reports_the_approval_reason_not_the_continue_reason() -> void:
	var run := M.two_conditions_run(M.SEED, 1)
	var f: SimFacadeImpl = run["facade"]
	var id := int(run["approved_parcel"])
	var approved_reason := 0
	for _day in 60:  # inşaat başlayana dek
		f.advance(1)
		var v := f.parcel_views(PackedInt64Array([id]))[0]
		if v.development == ParcelView.DEVELOPMENT_UNDER_CONSTRUCTION:
			approved_reason = v.decision_reason_id
			break
	assert_int(approved_reason).override_failure_message("inşaat başlamadı").is_greater(0)
	# Test tarafı koşul: bölge altyapısı çökerse proje durur (kural değişmez; yalnız başlangıç koşulu).
	var regions: Dictionary = EconomyState.data(f.game_state())["regions"]
	var caps: PackedInt64Array = regions["infra_cap"]  # tipli yerel: sütuna yazar (`as` kopyalar)
	caps.fill(0)
	f.advance(2)
	var stalled := f.parcel_views(PackedInt64Array([id]))[0]
	assert_str(String(stalled.development)).is_equal("stalled")
	assert_str(String(stalled.decision)).is_equal("approved")
	assert_int(stalled.decision_reason_id).is_equal(approved_reason)
	assert_str(String(f.reason(stalled.decision_reason_id).decision_key)).is_equal("decision.investor.develop")
	var raw := EconomyQuery.parcel_record(f.game_state(), id)
	assert_int(int(raw["reason_id"])).override_failure_message("ham sütun durma gerekçesine geçmiş olmalı") \
		.is_not_equal(approved_reason)


func test_zone_change_clears_the_old_decline_and_the_new_evaluation_is_recorded_later() -> void:
	var run := M.two_conditions_run(M.SEED, 60)
	var f: SimFacadeImpl = run["facade"]
	var id := int(run["declined_parcel"])
	var before := f.parcel_views(PackedInt64Array([id]))[0]
	assert_str(String(before.decision)).is_equal("declined")
	var proposed_at := f.current_tick()
	var r := f.submit_command(SimCommand.zoning_propose(PackedInt64Array([id]), &"zone.commercial"))
	assert_bool(r.is_rejected()).is_false()
	var saw_cleared := false
	var final := before
	for _day in 40:  # öneri meclis oylamasına gider (~10 gün) + yürürlük gecikmesi + dikkat gecikmesi
		f.advance(1)
		final = f.parcel_views(PackedInt64Array([id]))[0]
		if final.decision == ParcelView.DECISION_NONE:
			saw_cleared = true
			assert_int(final.decision_tick).is_equal(-1)
			assert_int(final.decision_reason_id).is_equal(0)
		elif saw_cleared:
			break
	assert_bool(saw_cleared).override_failure_message("imar yürürlüğe girince eski ret temizlenmeli").is_true()
	assert_str(String(final.decision)).is_equal("declined")
	assert_int(final.decision_tick).override_failure_message("yeni ret öneriden sonra kaydedilmeli") \
		.is_greater(proposed_at)


# --- (b) parcel_changes_since == tam tarama (B-002) ---

func test_changes_since_equals_the_full_scan_every_tick_under_load() -> void:
	var h := _load_handle()
	var f := h.facade
	var ids := f.parcel_ids()
	var before := _truth(f, ids)
	var peak_active := 0
	var total_changes := 0
	var stages_seen := {}
	var rerecorded := 0
	for _day in LOAD_DAYS:
		var from_tick := f.current_tick()
		f.advance(1)
		var feed := f.parcel_changes_since(from_tick)
		var after := _truth(f, ids)
		var expected := _changed_between(before, after)
		assert_bool(feed.complete).is_true()
		assert_int(feed.up_to_tick).is_equal(f.current_tick())
		assert_array(Array(feed.ids)).override_failure_message("tick %d: sorgu != tam tarama" % f.current_tick()) \
			.is_equal(expected)
		total_changes += expected.size()
		for id: int in expected:
			stages_seen[after[id][0]] = true
			if before[id][5] == "declined" and after[id][5] == "declined":
				rerecorded += 1  # tekrarlanabilir ret penceresi dolunca yeni kayıt: karar tick'i ilerler
		peak_active = maxi(peak_active, (EconomyState.data(f.game_state())["active"] as Dictionary).size())
		before = after
	assert_int(peak_active).override_failure_message(">= 100 eşzamanlı inşaat beklenir").is_greater_equal(100)
	assert_int(total_changes).is_greater(1000)
	assert_int(rerecorded).override_failure_message("ret yeniden kaydı görülmedi").is_greater(0)
	for stage in ["planned", "under_construction", "built"]:
		assert_bool(stages_seen.has(stage)).override_failure_message("aşama görülmedi: %s" % stage).is_true()
	assert_int(f.game_state().reasons.first_id()).is_greater(1000)


func test_changes_since_equals_the_full_scan_with_zone_changes_stalls_and_resumes() -> void:
	var patch := E.merge(M.ISOLATE, E.regions({"F1": E.favorable(), "F2": E.unfavorable()}))
	var f := M.politics_handle(patch, 14).facade
	var ids := f.parcel_ids()
	f.submit_command(SimCommand.zoning_propose(ids, &"zone.mixed"))
	var before := _truth(f, ids)
	var saw := {}
	for day in 150:
		if day == 45:  # ikinci imar: reddedilmiş boş parsellerde karar özeti sıfırlanır ve yeniden kaydedilir
			f.submit_command(SimCommand.zoning_propose(ids, &"zone.commercial"))
		if day == 30 or day == 55:  # test tarafı koşul: F1 altyapısı çöker (durma), sonra döner (devam)
			var regions: Dictionary = EconomyState.data(f.game_state())["regions"]
			var cap: PackedInt64Array = regions["infra_cap"]
			cap[0] = 0 if day == 30 else 2000
		var from_tick := f.current_tick()
		f.advance(1)
		var feed := f.parcel_changes_since(from_tick)
		var after := _truth(f, ids)
		var expected := _changed_between(before, after)
		assert_bool(feed.complete).is_true()
		assert_array(Array(feed.ids)).override_failure_message("tick %d" % f.current_tick()).is_equal(expected)
		for id: int in expected:
			saw[after[id][0]] = true
			if before[id][0] == "stalled" and after[id][0] == "under_construction":
				saw["resumed"] = true
			if before[id][5] != "" and after[id][5] == "":
				saw["decision_cleared"] = true
			if before[id][5] == "" and after[id][5] == "declined":
				saw["declined_after_clear"] = true
		before = after
	for key in ["planned", "under_construction", "stalled", "resumed", "built", "decision_cleared",
			"declined_after_clear"]:
		assert_bool(saw.has(key)).override_failure_message("görülmedi: %s" % key).is_true()


func test_a_consumer_following_only_the_feed_stays_exactly_in_sync_with_uneven_frame_batches() -> void:
	var f := _load_handle().facade
	var ids := f.parcel_ids()
	var mirror := _truth(f, ids)
	var cursor := f.parcel_changes_since(f.current_tick())
	assert_bool(cursor.complete).is_true()
	var batches := [1, 3, 7, 2, 5, 1, 11, 4]
	var steps := 0
	var day := 0
	while day < LOAD_DAYS:
		var k: int = batches[steps % batches.size()]
		steps += 1
		f.advance(k)
		day += k
		var feed := f.parcel_changes_since(cursor.up_to_tick)
		assert_bool(feed.complete).is_true()
		assert_int(feed.epoch).is_equal(cursor.epoch)
		for v in f.parcel_views(feed.ids):
			mirror[v.id] = _tuple(v)
		cursor = feed
		assert_dict(mirror).override_failure_message("gün %d: tüketici aynası gerçekten sapmış" % day) \
			.is_equal(_truth(f, ids))


# --- (c) kayıt/yükleme: epoch değişir, tüketici bir kez tam eşitler ---

func test_loading_a_save_changes_the_epoch_and_one_full_resync_restores_consistency() -> void:
	var f := _load_handle().facade
	var ids := f.parcel_ids()
	f.advance(40)
	var bytes := f.export_save()
	var at_save := f.parcel_changes_since(f.current_tick())
	assert_bool(at_save.complete).is_true()
	f.advance(15)  # tüketici 55. tick'e kadar ilerlemiş, sonra eski kayda dönülür
	var consumer := f.parcel_changes_since(f.current_tick())
	var loaded := f.import_save(bytes)
	assert_bool(loaded.ok).is_true()
	assert_int(f.current_tick()).is_equal(40)
	var after_load := f.parcel_changes_since(consumer.up_to_tick)
	assert_int(after_load.epoch).override_failure_message("yükleme epoch'u artırmalı").is_not_equal(consumer.epoch)
	assert_bool(after_load.complete).override_failure_message("gelecekteki tick eksik sayılır").is_false()
	assert_int(after_load.ids.size()).is_equal(0)
	# Tarihi halkadan eski sorgu da eksik; yüklenen tick'in kendisi tamdır (epoch yine uyarır).
	assert_bool(f.parcel_changes_since(10).complete).is_false()
	var same_tick := f.parcel_changes_since(40)
	assert_bool(same_tick.complete).is_true()
	assert_int(same_tick.epoch).is_equal(after_load.epoch)
	assert_int(same_tick.ids.size()).is_equal(0)
	# Tüketici BİR KEZ tam yeniden eşitler, sonra yalnız değişimi izler.
	var mirror := _truth(f, ids)
	var cursor := f.parcel_changes_since(f.current_tick())
	for _round in 6:
		f.advance(5)
		var feed := f.parcel_changes_since(cursor.up_to_tick)
		assert_bool(feed.complete).is_true()
		assert_int(feed.epoch).is_equal(cursor.epoch)
		for v in f.parcel_views(feed.ids):
			mirror[v.id] = _tuple(v)
		cursor = feed
		assert_dict(mirror).is_equal(_truth(f, ids))


func test_a_fresh_facade_that_imports_a_save_starts_with_an_empty_history_and_a_new_epoch() -> void:
	var a := _load_handle().facade
	a.advance(30)
	var bytes := a.export_save()
	var b := _load_handle().facade
	var epoch_before := b.parcel_changes_since(0).epoch
	assert_bool(b.import_save(bytes).ok).is_true()
	assert_bool(b.state_hash() == a.state_hash()).is_true()
	var feed := b.parcel_changes_since(-1)
	assert_bool(feed.complete).override_failure_message("yüklemeden önceki geçmiş bilinmiyor").is_false()
	assert_int(feed.epoch).is_not_equal(epoch_before)
	b.advance(10)
	a.advance(10)
	assert_str(b.state_hash()).override_failure_message("yükleme sonrası koşu kesintisizle aynı olmalı") \
		.is_equal(a.state_hash())
	var fa := a.parcel_changes_since(30)
	var fb := b.parcel_changes_since(30)
	assert_bool(fb.complete).is_true()
	assert_array(Array(fb.ids)).override_failure_message("yüklemeden sonraki değişimler aynı olmalı") \
		.is_equal(Array(fa.ids))


# --- (d) halka sınırı ---

func test_ring_covers_exactly_the_configured_window_and_stays_bounded() -> void:
	var h := _load_handle({"decision": {"change_window_ticks": 16}})
	var f := h.facade
	var per_tick := {}
	var max_size := 0
	for _day in 60:
		var from_tick := f.current_tick()
		f.advance(1)
		var feed := f.parcel_changes_since(from_tick)
		assert_bool(feed.complete).is_true()
		per_tick[f.current_tick()] = feed.ids.size()
		max_size = maxi(max_size, h.system.change_log().size())
	var now := f.current_tick()
	assert_bool(f.parcel_changes_since(now - 16).complete).override_failure_message("pencere sınırı tam").is_true()
	var too_old := f.parcel_changes_since(now - 17)
	assert_bool(too_old.complete).is_false()
	assert_int(too_old.ids.size()).override_failure_message("eksik kapsamda kimlik güvenilmez").is_equal(0)
	assert_bool(f.parcel_changes_since(0).complete).is_false()
	var expected := 0
	for t in range(now - 15, now + 1):
		expected += int(per_tick[t])
	assert_int(h.system.change_log().size()).override_failure_message("halka yalnız pencere içini tutar") \
		.is_equal(expected)
	var total := 0
	for t: int in per_tick:
		total += int(per_tick[t])
	assert_int(total).override_failure_message("test anlamsız: pencere dışı değişim yok").is_greater(expected * 2)
	assert_int(max_size).is_less(total)
	# Pencere içi birleşim: son 16 tick'in tek tek birleşimi.
	var union := {}
	var window_feed := f.parcel_changes_since(now - 16)
	for id in window_feed.ids:
		union[id] = true
	assert_int(window_feed.ids.size()).is_greater(0)
	assert_int(union.size()).override_failure_message("kimlikler tekrarsız").is_equal(window_feed.ids.size())


func test_default_window_is_data_driven_and_validated() -> void:
	assert_int(E.config().p("change_window_ticks")).is_greater_equal(64)
	var bad := E.raw_config()
	bad["decision"]["change_window_ticks"] = 0
	assert_bool(EconomyConfig.from_dict(bad).is_valid()).is_false()


# --- (e) determinizm, salt okunurluk, hash ---

func test_same_seed_and_commands_give_identical_feeds_and_other_seed_differs() -> void:
	var feeds: Array[Dictionary] = []
	for world_seed in [SEED, SEED, SEED + 1]:
		var f := E.synthetic_handle(LOAD_PARCELS, 2, LOAD_PATCH, world_seed).facade
		f.advance(45)
		var snapshot := {}
		for since in [0, 20, 40, 44]:
			snapshot[since] = Array(f.parcel_changes_since(since).ids)
		feeds.append(snapshot)
	assert_dict(feeds[0]).is_equal(feeds[1])
	assert_dict(feeds[0]).override_failure_message("farklı tohum aynı değişimi vermemeli").is_not_equal(feeds[2])
	assert_int((feeds[0][0] as Array).size()).is_greater(0)


func test_polling_the_feed_leaves_state_hash_and_save_bytes_untouched() -> void:
	var quiet := _load_handle().facade
	var polled := _load_handle().facade
	for _day in 40:
		quiet.advance(1)
		polled.advance(1)
		polled.parcel_changes_since(polled.current_tick() - 1)
		polled.parcel_changes_since(0)
		polled.parcel_changes_since(-1)
	assert_str(polled.state_hash()).is_equal(quiet.state_hash())
	assert_bool(polled.export_save() == quiet.export_save()).override_failure_message("halka kayda sızmamalı").is_true()


func test_state_hash_is_bit_identical_to_the_pre_change_recording_for_both_golden_scenarios() -> void:
	assert_str(M.stress_run().state_hash()).is_equal(Q.GOLDEN_A)
	assert_str((M.two_conditions_run()["facade"] as SimFacadeImpl).state_hash()).is_equal(Q.GOLDEN_B)


# --- (f) ekonomisiz / erken durum ---

func test_facade_without_economy_reports_no_changes_and_a_complete_range() -> void:
	var f := FacadeTestSupport.facade(4)
	f.advance(5)
	var feed := f.parcel_changes_since(2)
	assert_bool(feed.complete).is_true()
	assert_int(feed.ids.size()).is_equal(0)
	assert_int(feed.up_to_tick).is_equal(5)
	assert_bool(f.parcel_changes_since(99).complete).is_false()
	var view := f.parcel_views(f.parcel_ids())[0]
	assert_str(String(view.decision)).is_equal("")


func test_economy_facade_before_the_first_tick_has_an_empty_complete_history() -> void:
	var f := _load_handle().facade
	var feed := f.parcel_changes_since(-1)
	assert_bool(feed.complete).is_true()
	assert_int(feed.ids.size()).is_equal(0)
	assert_int(feed.up_to_tick).is_equal(0)
