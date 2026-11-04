extends GdUnitTestSuite
## T-043B (sim yarısı) · Yol/imar sonrası ÖNCELİKLİ değerlendirme (D-010 karar 1, core-loop-v0 §3): bölgenin hem
## erişimi (yol)
## hem planı tamamlandığı SON olaydan (yol onayı ya da plan yürürlüğü) sonra, olayın R m yakınındaki en çok K uygun
## parsel
## (yürürlükte plan + yola bağlı + boş) `attention_delay_days` sonra zorunlu değerlendirme kuyruğuna girer; kuyruk
## `max_reviews_per_tick` ile dağıtılır; plansız/bağlantısız parsel girmez. Zorlama yok: kuyruk yalnız BAKIŞI öne çeker,
## karar yine yatırımcı kararıdır (SIM-07, CAN-03). Kuyruk durumu yalnız ilk tetikte yaratılır (T-042 deseni).

const E := preload("res://tests/sim/economy/economy_priority_support.gd")
const P := preload("res://tests/sim/public_works/public_works_support.gd")
const S := preload("res://tests/sim/economy/economy_test_support.gd")
const DELAY := 2  # data/sim/economy/economy_config.json decision.attention_delay_days
const MAX_FIRST_CONSTRUCTION_DAYS := 40
const MAX_FIRST_COMPLETION_DAYS := 100
const NOT_REACHED := 9999
const FILLER := 1500  # yola uzak plansız dolgu parseli (oynanabilir dünyadaki gibi tarama bütçesini yer)


# --- Yapılandırma ---

func test_priority_parameters_are_data_with_safe_defaults_and_ranges() -> void:
	var base := S.config()
	assert_int(base.p("priority_review_enabled")).override_failure_message("varsayılan kapalı").is_equal(0)
	assert_int(base.p("priority_radius_m")).is_greater(0)
	assert_int(base.p("priority_max_parcels")).is_greater(0)
	var on := S.config({"decision": {"priority_review_enabled": 1, "priority_radius_m": 200, "priority_max_parcels": 5}})
	assert_int(on.p("priority_review_enabled")).is_equal(1)
	assert_int(on.p("priority_radius_m")).is_equal(200)
	assert_int(on.p("priority_max_parcels")).is_equal(5)
	for bad: Dictionary in [{"priority_review_enabled": 2}, {"priority_radius_m": 0}, {"priority_max_parcels": 0}]:
		assert_bool(EconomyConfig.from_dict(S.merge(S.raw_config(), {"decision": bad})).is_valid()) \
			.override_failure_message("geçersiz değer kabul edildi: %s" % bad).is_false()
	# Eski yapılandırma (anahtarlar hiç yok) geçerli ve kapalı: eski dosyalar/fixture'lar bit-eşit çalışır.
	var legacy := S.raw_config()
	for key in ["priority_review_enabled", "priority_radius_m", "priority_max_parcels"]:
		(legacy["decision"] as Dictionary).erase(key)
	var cfg := EconomyConfig.from_dict(legacy)
	assert_bool(cfg.is_valid()).override_failure_message(cfg.error).is_true()
	assert_int(cfg.p("priority_review_enabled")).is_equal(0)


func test_playable_economy_enables_the_priority_review() -> void:
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/game/playable_economy.json"))
	assert_int(int(raw["decision"]["priority_review_enabled"])).is_equal(1)
	assert_int(int(raw["decision"]["unplanned_land_enabled"])).is_equal(1)


# --- Kuyruğa kim girer ---

func test_road_after_plan_queues_the_nearest_k_planned_connected_vacant_parcels_with_the_road_command() -> void:
	var run := E.setup()
	var f := E.f(run)
	E.plan(f, E.NEAR_A)  # 14 yakın parsel planlı, kapasite 0: hepsi altyapıdan reddedilir ve boş kalır
	f.advance(40)
	assert_dict(E.queue(f)).override_failure_message("yol gelmeden kuyruk yaratılmamalı").is_empty()
	assert_bool(E.eco(f).has("priority")).is_false()
	var road := E.road_a(f)
	assert_bool(road.is_rejected()).is_false()
	f.advance(1)
	var due := f.current_tick() + DELAY
	var queue := E.queue(f)
	var k := S.config().p("priority_max_parcels")
	assert_int(queue.size()).override_failure_message("en çok K=%d parsel" % k).is_equal(mini(k, E.NEAR_A.size()))
	for id: int in E.NEAR_A.slice(0, k):  # yola uzaklık sırası = kimlik sırası
		assert_bool(queue.has(id)).override_failure_message("en yakın %d kuyrukta değil" % id).is_true()
		assert_int(queue[id]).is_equal(due)
		assert_int(E.queue_commands(f)[id]).is_equal(road.command_id)
	for id: int in E.NEAR_A.slice(k):
		assert_bool(queue.has(id)).override_failure_message("K'dan uzak %d kuyrukta" % id).is_false()


func test_unplanned_parcels_never_enter_the_queue_and_the_state_is_not_written() -> void:
	var run := E.setup()
	var f := E.f(run)
	f.advance(20)
	E.road_a(f)  # yol var, yakında hiç plan yok
	f.advance(60)
	assert_bool(E.eco(f).has("priority")).override_failure_message("kuyruk boşken durum yazılmamalı").is_false()
	assert_bool(E.eco(f).has("priority_cmd")).is_false()
	assert_int(E.approvals(f)).override_failure_message("plansız arazide bina çıktı").is_equal(0)


func test_a_road_far_from_every_planned_parcel_queues_nothing() -> void:
	var run := E.setup()
	var f := E.f(run)
	E.plan(f, E.NEAR_A + E.FAR_A)
	f.advance(30)
	E.road_b(f)  # doğu bölgede: planlı parsellerin hiçbiri R m içinde değil (NEAR_B planlanmadı)
	f.advance(60)
	assert_bool(E.eco(f).has("priority")).override_failure_message("bağlantısız yol kuyruk üretti").is_false()


func test_planned_parcels_far_from_the_road_are_not_queued() -> void:
	var run := E.setup()
	var f := E.f(run)
	E.plan(f, E.FAR_A)
	f.advance(30)
	E.road_a(f)
	f.advance(60)
	assert_bool(E.eco(f).has("priority")).override_failure_message("uzak planlı parsel kuyruğa girdi").is_false()


func test_built_and_proposed_parcels_do_not_enter_the_queue() -> void:
	var run := E.setup()
	var f := E.f(run)
	E.plan(f, [1, 2, 3])
	f.advance(30)  # kapasite 0: hepsi boş kalır
	E.plan(f, [4, 5])  # 4 ve 5 için teklif yolda: yürürlükte plan yok
	f.advance(1)
	E.road_a(f)
	f.advance(1)
	var queue := E.queue(f)
	for id in [1, 2, 3]:
		assert_bool(queue.has(id)).is_true()
	for id in [4, 5]:
		assert_bool(queue.has(id)).override_failure_message("teklif aşamasındaki parsel kuyruğa girdi").is_false()


func test_plan_after_road_queues_connected_plan_parcels_with_the_plan_command_instead_of_plain_attention() -> void:
	var run := E.setup()
	var f := E.f(run)
	E.road_a(f)
	f.advance(10)
	var plan := E.plan(f, [1, 2, 3, 4, 5, 6])
	for _day in 10:  # komut + apply_delay_days: plan yürürlüğe girene dek (yürürlük gününde dur)
		f.advance(1)
		if not E.ticks_of(f, E.KIND_PLAN).is_empty():
			break
	var plan_tick: int = E.ticks_of(f, E.KIND_PLAN)[0]
	assert_int(f.current_tick()).is_equal(plan_tick)
	var queue := E.queue(f)
	assert_int(queue.size()).is_equal(6)
	for id: int in queue:
		assert_int(queue[id]).is_equal(plan_tick + DELAY)
		assert_int(E.queue_commands(f)[id]).is_equal(plan.command_id)
	assert_dict(E.eco(f)["attention"]).override_failure_message("kuyruktaki parsel ayrıca dikkat listesinde").is_empty()


func test_plan_before_any_road_keeps_the_plain_attention_path_and_creates_no_queue() -> void:
	var run := E.setup()
	var f := E.f(run)
	E.plan(f, [1, 2, 3])
	f.advance(4)
	assert_bool(E.eco(f).has("priority")).override_failure_message("bağlı yol yokken kuyruk yaratıldı").is_false()
	assert_int((E.eco(f)["attention"] as Dictionary).size()).is_equal(3)
	f.advance(DELAY + 1)
	assert_int(E.evaluations(f)).override_failure_message("planlı parsel yine de değerlendirilmeli").is_greater(0)


func test_queue_overflow_beyond_k_keeps_the_plain_attention_path() -> void:
	var run := E.setup({"decision": {"priority_max_parcels": 4}})
	var f := E.f(run)
	E.road_a(f)
	f.advance(10)
	E.plan(f, [1, 2, 3, 4, 5, 6, 7, 8])
	f.advance(4)
	assert_int(E.queue(f).size()).is_equal(4)
	assert_int((E.eco(f)["attention"] as Dictionary).size()).override_failure_message("K'yı aşanlar dikkatsiz kaldı") \
		.is_equal(4)
	for id: int in [1, 2, 3, 4]:  # yola en yakın dört
		assert_bool(E.queue(f).has(id)).is_true()


func test_a_replan_that_overflows_k_moves_the_parcel_from_the_queue_to_plain_attention() -> void:
	# Aynı parsel için tek zorunlu değerlendirme: yeniden plan K'yı aşarsa parsel kuyruktan düşer, dikkat listesine geçer.
	var run := E.setup({"decision": {"priority_max_parcels": 1, "attention_delay_days": 20, "review_enabled": 0}})
	var f := E.f(run)
	E.road_a(f)
	f.advance(5)
	E.plan(f, [2])
	for _day in 6:
		f.advance(1)
	assert_array(E.queue(f).keys()).contains_exactly([2])
	E.plan(f, [1, 2], &"zone.commercial")
	for _day in 6:
		f.advance(1)
	assert_array(E.queue(f).keys()).override_failure_message("yola en yakın parsel kuyrukta kalmalı").contains_exactly([1])
	assert_bool((E.eco(f)["attention"] as Dictionary).has(1)) \
		.override_failure_message("taşan parsel dikkatte olmalı").is_true()
	assert_bool((E.eco(f)["priority_cmd"] as Dictionary).has(1)).is_false()


# --- Dağıtım (max_reviews_per_tick) ve öncelik ---

func test_queue_is_spread_over_ticks_by_max_reviews_per_tick_and_drains() -> void:
	var run := E.setup({"decision": {"max_reviews_per_tick": 3, "review_enabled": 0}})  # tarama kapalı: yalnız kuyruk
	var f := E.f(run)
	E.plan(f, E.NEAR_A)
	f.advance(40)
	E.road_a(f)
	f.advance(1)
	var queued := E.queue(f).size()
	assert_int(queued).is_equal(12)
	var due := f.current_tick() + DELAY
	f.advance(DELAY - 1)  # vadeye bir gün kala: henüz kimse bakmadı
	assert_int(E.queue(f).size()).is_equal(queued)
	var drained_at := -1
	for _day in 12:
		var before := E.evaluations(f)
		f.advance(1)
		assert_int(E.evaluations(f) - before) \
			.override_failure_message("tick başına değerlendirme sınırı aşıldı (gün %d)" % f.current_tick()) \
			.is_less_equal(3)
		if drained_at < 0 and E.queue(f).is_empty():
			drained_at = f.current_tick()
	assert_int(drained_at).override_failure_message("kuyruk boşalmadı").is_greater(0)
	assert_int(drained_at - due).override_failure_message("12 parsel / 3 -> en az 4 gün sürmeli").is_greater_equal(3)


func test_queue_is_served_before_the_periodic_scan_and_the_scan_gets_only_the_rest() -> void:
	# Kuyruk doluyken günlük bütçe (max_reviews_per_tick) önce kuyruğa gider: tarama kuyruk boşalana dek bütçeyi yemez.
	var run := E.setup({"decision": {"max_reviews_per_tick": 3}})
	var f := E.f(run)
	E.plan(f, E.NEAR_A)
	f.advance(40)
	E.road_a(f)
	f.advance(1 + DELAY)
	var cursor_before := int(E.eco(f)["review_cursor"])
	var queued_before := E.queue(f).size()
	f.advance(1)
	var drained := queued_before - E.queue(f).size()
	assert_int(drained).override_failure_message("kuyruk bütçeyi tamamen kullanmalı").is_equal(3)
	assert_int(int(E.eco(f)["review_cursor"])).override_failure_message("tarama imleci kuyruk doluyken ilerlememeli") \
		.is_equal(cursor_before)


# --- Gerekçe zinciri (SIM-12) ---

func _develop_records(f: SimFacadeImpl, parcel_id: int) -> Array:
	return f.game_state().reasons.find({"subject": String(SimContract.parcel_ref(parcel_id))})


func test_road_triggered_review_names_the_road_command_and_still_shows_the_plan_command() -> void:
	var run := E.setup({"decision": {"review_enabled": 0}})  # tarama kapalı: değerlendirmeyi yalnız kuyruk yapar
	var f := E.f(run)
	var plan := E.plan(f, [1, 2, 3, 4, 5, 6])
	f.advance(40)
	var road := E.road_a(f)
	f.advance(1)
	var due := f.current_tick() + DELAY
	f.advance(DELAY + 1)
	var seen := 0
	for id in [1, 2, 3, 4, 5, 6]:
		for rec: Dictionary in _develop_records(f, id):
			if int(rec["tick"]) < due:
				continue
			seen += 1
			var subjects: Array = rec["subjects"]
			assert_bool(subjects.has("command.%d" % road.command_id)) \
				.override_failure_message("yol komutu gerekçe konusunda yok: %s" % [subjects]).is_true()
			var plan_seen := false
			for factor: Dictionary in rec["factors"]:
				if String(factor["name"]) == "reason.factor.zoning_fit":
					plan_seen = String(factor.get("source_ref", "")) == "command.%d" % plan.command_id
			assert_bool(plan_seen).override_failure_message("plan komutu etkende görünmeli").is_true()
	assert_int(seen).override_failure_message("kuyruktaki parsellerin gerekçesi yok").is_greater(0)


func test_plan_triggered_review_names_the_plan_command() -> void:
	var run := E.setup()
	var f := E.f(run)
	E.road_a(f)
	f.advance(10)
	var plan := E.plan(f, [1, 2, 3])
	f.advance(4 + DELAY + 1)
	var seen := 0
	for id in [1, 2, 3]:
		for rec: Dictionary in _develop_records(f, id):
			if (rec["subjects"] as Array).has("command.%d" % plan.command_id):
				seen += 1
	assert_int(seen).override_failure_message("plan komutu gerekçe konusunda görünmeli").is_equal(3)


# --- Zamanlama: tetikleyiciden ilk inşaat / ilk bina (5 tohum medyanı) ---

## {started, completed}: tetikleyici günden ilk inşaat başlangıcı / ilk tamamlanma (gün; ulaşılamadıysa NOT_REACHED).
## Gün gün izlenir (olay günlüğü dolgu parsellerinin olaylarıyla taşabilir). Tetikleyici gün: yolda komutun
## uygulandığı tick,
## planda planın yürürlüğe girdiği tick.
func _timing(world_seed: int, plan_first: bool, priority_on: bool = true) -> Dictionary:
	var run := E.setup({"decision": {"priority_review_enabled": 1 if priority_on else 0}}, world_seed, FILLER)
	var f := E.f(run)
	var ids := PackedInt64Array([1, 2, 3, 4, 5, 6])
	var trigger := -1
	if plan_first:
		E.plan(f, [1, 2, 3, 4, 5, 6])
		f.advance(40)
		trigger = f.current_tick()
		E.road_a(f)
	else:
		E.road_a(f)
		f.advance(40)
		E.plan(f, [1, 2, 3, 4, 5, 6])
	var started := NOT_REACHED
	var completed := NOT_REACHED
	for _day in 220:
		f.advance(1)
		if trigger < 0:
			if f.plan_state(1).state != &"planned":
				continue
			trigger = f.current_tick()
		for v in f.parcel_views(ids):
			if v.development == ParcelView.DEVELOPMENT_UNDER_CONSTRUCTION or v.development == ParcelView.DEVELOPMENT_BUILT:
				started = mini(started, f.current_tick() - trigger)
			if v.development == ParcelView.DEVELOPMENT_BUILT:
				completed = mini(completed, f.current_tick() - trigger)
	return {"started": started, "completed": completed}


func _medians(plan_first: bool, priority_on: bool) -> Dictionary:
	var starts: Array[int] = []
	var dones: Array[int] = []
	for world_seed in E.SEEDS:
		var t := _timing(world_seed, plan_first, priority_on)
		starts.append(t["started"])
		dones.append(t["completed"])
	print("T043B_TIMING order=%s priority=%s started=%s completed=%s" % ["plan->road" if plan_first else "road->plan",
		priority_on, starts, dones])
	return {"starts": starts, "dones": dones, "started": E.median(starts), "completed": E.median(dones)}


func test_first_construction_and_first_building_follow_the_last_trigger_within_the_targets_in_both_orders() -> void:
	for plan_first in [true, false]:
		var m := _medians(plan_first, true)
		var label := "plan->yol" if plan_first else "yol->plan"
		assert_int(m["started"]).override_failure_message("%s ilk inşaat medyanı %s" % [label, m["starts"]]) \
			.is_less_equal(MAX_FIRST_CONSTRUCTION_DAYS)
		assert_int(m["completed"]).override_failure_message("%s ilk bina medyanı %s" % [label, m["dones"]]) \
			.is_less_equal(MAX_FIRST_COMPLETION_DAYS)


func test_without_the_queue_the_plan_then_road_order_is_slower_than_the_targets() -> void:
	# Kontrol: kuyruk kapalıyken plansız dolgu parselleri tarama bütçesini yer; yol sonrası planlı parsellere bakış geç
	# gelir.
	# Bu, kuyruğun işe yaradığının kanıtıdır (aynı dünya, aynı tohumlar, yalnız `priority_review_enabled` farklı).
	var off := _medians(true, false)
	var on := _medians(true, true)
	assert_int(on["started"]).is_less(off["started"])
	assert_int(off["started"]) \
		.override_failure_message("kontrol koşusu zaten hızlı: ölçüt kanıtlamıyor %s" % [off["starts"]]) \
		.is_greater(MAX_FIRST_CONSTRUCTION_DAYS)


# --- Olumsuz: yatırım yine gelmeyebilir (SIM-07), ret dağılımı kalır ---

func test_when_every_parcel_can_be_declined_the_queue_still_records_why_and_seeds_differ() -> void:
	var hashes := {}
	for world_seed in E.SEEDS:
		var run := E.setup({"regions": {"overrides": {
			String(P.CODE_A): {"initial_households": 0, "infra_capacity_units": 100000, "access_pm": 1000, "service_pm": 1000},
			String(P.CODE_B): {"initial_households": 0, "infra_capacity_units": 100000, "access_pm": 1000, "service_pm": 1000},
		}}}, world_seed)
		var f := E.f(run)
		var plan := E.plan(f, [1, 2, 3, 4, 5, 6])
		f.advance(30)
		var road := E.road_a(f)
		f.advance(120)
		assert_int(E.approvals(f)).override_failure_message("tohum %d: düşük talepte yatırım geldi" % world_seed).is_equal(0)
		var named := 0
		for id in [1, 2, 3, 4, 5, 6]:
			for rec: Dictionary in _develop_records(f, id):
				assert_str(String(rec["outcome"])).is_equal("negative")
				assert_str(String(rec["code"])).override_failure_message("plan var, ret nedeni imar olmamalı") \
					.is_not_equal("zoning_unplanned")
				if (rec["subjects"] as Array).has("command.%d" % road.command_id) \
						or (rec["subjects"] as Array).has("command.%d" % plan.command_id):
					named += 1
		assert_int(named).override_failure_message("tohum %d: ret gerekçesi tetikleyici komutu taşımıyor" % world_seed) \
			.is_greater(0)
		hashes[f.state_hash()] = true
	assert_int(hashes.size()).override_failure_message("5 tohumda tohumlar arası fark yok").is_equal(E.SEEDS.size())


func test_investment_after_a_trigger_is_not_guaranteed_by_the_queue_alone() -> void:
	# Kuyruk bakışı öne çeker, kararı değil: kapasite yetmeyen parseller kuyruktan geçse de reddedilir (CAN-03/SIM-07).
	var run := E.setup()
	var f := E.f(run)
	E.plan(f, E.NEAR_A)
	f.advance(40)
	E.road_a(f)
	f.advance(60)
	var total := E.approvals(f)
	assert_int(total).override_failure_message("100 m yol yalnız 10 birim ekler: 14 parselin hepsi yapılamaz") \
		.is_less(E.NEAR_A.size())
	assert_int(E.eco(f)["totals"]["declines"]).is_greater(0)
