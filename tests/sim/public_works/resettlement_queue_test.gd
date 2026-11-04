extends "res://tests/sim/public_works/resettlement_queue_test_base.gd"
## T-067 (D-019 E1) · Bekleme listesi: oluşma, sonradan biten evin önce onlara verilmesi, tepki, sıra. Ortak dünya ve
## yardımcılar: `resettlement_queue_test_base.gd`.

# --- Liste oluşur ---

func test_with_no_vacancy_the_families_wait_and_the_view_says_how_many() -> void:
	var run := _queued()
	var record := _record(run)
	assert_int(int(record["unplaced"])).is_equal(16)
	assert_int(int(record["rehoused"])).is_equal(0)
	var policy := _wait(run)
	assert_int(policy.waiting_households).is_equal(16)
	assert_dict(policy.waiting_by_region).is_equal({SOURCE: 16})
	assert_int(policy.served_households).is_equal(0)
	assert_bool(ResettlementQueue.exists(_state(run))).is_true()


func test_the_road_is_still_built_and_the_reaction_is_whole_while_the_families_wait() -> void:
	var run := _queued()
	_f(run).advance(5)
	assert_int(_f(run).public_works().size()).is_equal(1)
	var index := ReactionRehousing.index(_state(run))
	assert_int(ReactionRehousing.still_unhoused(SOURCE, _command_of(run), 16, index)).is_equal(16)


func test_nothing_is_created_when_the_policy_was_never_opened() -> void:
	var run := _rworld(0, FULL)
	_road(run)
	_f(run).advance(10)
	assert_bool(_state(run).systems.has("policy")).override_failure_message("bölüm yaratılmamalı").is_false()
	assert_bool(ResettlementQueue.exists(_state(run))).is_false()
	assert_int(_f(run).policies()[0].waiting_households).is_equal(0)


func test_a_policy_that_is_on_but_leaves_nobody_waiting_creates_no_queue_state() -> void:
	var run := _rworld(60, FULL)  # D2'de 60 boş ev: 16 aile hemen yerleşir
	_policy(run, true)
	_road(run)
	_f(run).advance(5)
	assert_bool(ResettlementQueue.exists(_state(run))).is_false()
	assert_int(_wait(run).waiting_households).is_equal(0)


# --- Sonradan biten ev önce onlara verilir ---

func test_a_home_finished_later_goes_to_the_waiting_families_first() -> void:
	var run := _queued()
	_complete(run, TARGET, 10)
	_f(run).advance(1)
	var record := _record(run)
	assert_int(int(record["rehoused"])).is_equal(10)
	assert_int(int(record["unplaced"])).is_equal(6)
	assert_dict(record["unplaced_by"]).is_equal({SOURCE: 6})
	assert_array(record["moves"]).is_empty()  # yol anındaki tahsis değişmez
	assert_int((record["served"] as Array).size()).is_equal(1)
	var row: Array = record["served"][0]
	assert_array(row.slice(1)).is_equal([SOURCE, TARGET, 10, 0, 1])  # kaynak, hedef, hane, tam ev, kaynaktan düştü
	assert_int(row[0]).is_equal(_f(run).current_tick())
	assert_int(_latent(run, TARGET)).is_equal(50)
	assert_int(_latent(run, SOURCE)).is_equal(420 - 10)
	var policy := _wait(run)
	assert_int(policy.waiting_households).is_equal(6)
	assert_int(policy.served_households).is_equal(10)


func test_nothing_is_built_by_the_municipality_when_the_families_are_served() -> void:
	var run := _queued()
	var d1_built := _res_built(run, SOURCE)
	_complete(run, TARGET, 10)
	_f(run).advance(1)
	assert_int(_res_built(run, TARGET)).override_failure_message("birim yalnız yatırımcıyla artar").is_equal(50)
	assert_int(_res_built(run, SOURCE)).is_equal(d1_built)


func test_the_reaction_goes_on_until_a_home_is_given_and_then_a_little_stays() -> void:
	var run := _queued()
	var command := _command_of(run)
	_complete(run, TARGET, 10)
	_f(run).advance(1)
	var index := ReactionRehousing.index(_state(run))
	# 6 bekleyen tam + 10 evi bulunan x 200/1000 = 6 + 2 = 8 (yukarı yuvarlama); sıfır DEĞİL, tam DA DEĞİL
	assert_int(ReactionRehousing.still_unhoused(SOURCE, command, 16, index)).is_equal(8)
	_complete(run, TARGET, 6)
	_f(run).advance(1)
	index = ReactionRehousing.index(_state(run))
	assert_int(ReactionRehousing.still_unhoused(SOURCE, command, 16, index)) \
		.override_failure_message("kalan sıfır olmaz").is_equal(4)  # ceil(16 x 200 / 1000)
	assert_int(_wait(run).waiting_households).is_equal(0)
	assert_bool(ResettlementQueue.exists(_state(run))).override_failure_message("liste boşalınca bölüm silinir").is_false()


func test_the_raw_ledger_row_is_never_changed_by_a_home_being_given() -> void:
	var run := _queued()
	_complete(run, TARGET, 10)
	_f(run).advance(1)
	var rows := PublicWorksState.reaction_rows(_state(run), "displaced", SOURCE)
	assert_int(int(rows[0][1])).is_equal(16)


func test_the_number_given_never_exceeds_the_units_that_are_really_empty() -> void:
	var run := _queued()
	# 10 yeni birim bitti ama piyasa 8 haneyi hemen çekti: gerçekten boş birim yalnız 2
	_set_region(run, TARGET, 48, 50)
	_f(run).advance(1)
	assert_int(int(_record(run)["rehoused"])).is_equal(2)
	assert_int(_latent(run, TARGET)).is_equal(50)


func test_homes_that_were_already_empty_are_not_handed_to_the_queue() -> void:
	var run := _rworld(0, FULL)
	_set_region(run, TARGET, 40, 43)  # 3 boş ev var; max_fill 300 -> yol anında 0 ev ayrılır
	_policy(run, true)
	_road(run)
	assert_int(int(_record(run)["unplaced"])).is_equal(16)
	_f(run).advance(10)
	assert_int(int(_record(run)["rehoused"])).override_failure_message("eski boş ev liste değildir").is_equal(0)
	_complete(run, TARGET, 2)  # şimdi 2 yeni ev
	_f(run).advance(1)
	assert_int(int(_record(run)["rehoused"])).override_failure_message("yalnız yeni 2 birim").is_equal(2)


func test_a_partial_home_is_accepted_with_a_smaller_relief() -> void:
	var run := _queued({})  # varsayılan 800 m: D2'nin yola uzaklığı aşılır, kira şartı tamam -> kısmi ev
	_complete(run, TARGET, 10)
	_f(run).advance(1)
	var record := _record(run)
	assert_int(int(record["rehoused"])).is_equal(10)
	assert_int(int(record["partial"])).is_equal(10)
	assert_int((record["served"][0] as Array)[4]).is_equal(1)  # sınıf: kısmi
	# 6 x 1000 + 10 x max(200, 1000 - 600) = 10000 -> 10
	var index := ReactionRehousing.index(_state(run))
	assert_int(ReactionRehousing.still_unhoused(SOURCE, _command_of(run), 16, index)).is_equal(10)


# --- Gerçek yatırımcı tamamlaması (sahte sütun artışı değil) ---

## D1'de boş, imarlı parsel 4 var; yol altyapı kapasitesi eklediğinde YATIRIMCI orada kendi kararıyla konut bitirir.
## Bekleyen aileler (hane kaderi `return_to_latent`: D1'in talebinde) o evlerin öncelikli sahibidir; belediye yapmaz.
func test_a_home_the_real_investor_finishes_is_given_to_the_queue_on_the_day_it_is_done() -> void:
	var run := _queued()
	var built_before := _res_built(run, SOURCE)
	var completed_at := -1
	for _day in 400:
		_f(run).advance(1)
		if _res_built(run, SOURCE) != built_before:
			completed_at = _f(run).current_tick()
			break
	assert_int(completed_at).override_failure_message("yatırımcı 400 günde konut bitirmedi").is_greater(0)
	var units := _res_built(run, SOURCE) - built_before
	var record := _record(run)
	assert_int(int(record["rehoused"])).is_equal(mini(units, 16))
	assert_int(int((record["served"][0] as Array)[0])).override_failure_message("tamamlanma günü").is_equal(completed_at)
	var completed := false
	for e in _f(run).events_since(0):
		completed = completed or (e.message_key == &"event.construction.completed" and e.tick == completed_at)
	assert_bool(completed).override_failure_message("evi yatırımcı tamamladı (olay)").is_true()
	assert_int(int(EconomyQuery.totals(_state(run))["completions"])).is_equal(1)
	assert_int(_wait(run).waiting_households).is_equal(16 - mini(units, 16))


# --- Sıra: yol sırası, sonra bölge kodu ---

func test_the_oldest_road_is_served_first_then_the_next() -> void:
	var run := _queued()
	_spur(run)  # ikinci yol: parsel 6 (6 konut) -> D1'den daha çok hane bekler
	var second := _record(run, 1)
	assert_bool(second.is_empty()).is_false()
	var waiting_second := int(second["unplaced"])
	assert_int(waiting_second).is_greater(0)
	_complete(run, TARGET, 10)
	_f(run).advance(1)
	assert_int(int(_record(run, 0)["rehoused"])).override_failure_message("eski yol önce").is_equal(10)
	assert_int(int(_record(run, 1)["rehoused"])).is_equal(0)
	_complete(run, TARGET, 6 + waiting_second)
	_f(run).advance(1)
	assert_int(int(_record(run, 0)["unplaced"])).is_equal(0)
	assert_int(int(_record(run, 1)["rehoused"])).is_equal(waiting_second)
	assert_int(_wait(run).waiting_households).is_equal(0)
