extends "res://tests/sim/public_works/resettlement_test_base.gd"
## T-065 Aşama 1 · Yeniden iskân AKIŞI: tahsis, tepki, ret/kısmi ev, ardışık yol (ölçütler 1-4, 6, 8).
## Dünya: yol DIAGONAL parsel 1-3'ü alır; D1'de 16 hane yerinden edilir (420 hane, 22 konut). Hedef D2: testler boş ev
## verir. Beklenen değerler testte bağımsız hesaplanır, üretim koduna çağrı yapılmaz.

const FULL := {"max_distance_m": 5000}  # D2'nin parseli yola ~1160 m: yer şartı tamam (tam ev)
const SPREAD := {"household_fate": "leave_region"}


func _roads(run: Dictionary) -> Array[PublicWorkView]:
	return _f(run).public_works()


## Politika AÇIK, D2'de 60 boş ev, yer şartı tamam; yol yapıldı. Çıktı: dünya.
func _o1(resettlement: Dictionary = FULL, vacancy: int = 60) -> Dictionary:
	var run := _rworld(vacancy, resettlement)
	_policy(run, true)
	_road(run)
	return run


# --- Kapalı politika: bugünkü davranış ---

func test_policy_off_the_road_leaves_households_and_the_ledger_exactly_as_before() -> void:
	var run := _rworld(60, FULL)
	var d1 := _latent(run, SOURCE)
	var d2 := _latent(run, TARGET)
	_road(run)
	assert_int(_latent(run, SOURCE)).override_failure_message("kaynak değişmemeli").is_equal(d1)
	assert_int(_latent(run, TARGET)).override_failure_message("hedef değişmemeli").is_equal(d2)
	assert_bool(_record(run).is_empty()).is_true()
	var args := _events(run, SimEvent.KIND_PUBLIC_WORK_EXPROPRIATED)[0].args
	assert_bool(args.has("resettlement_applied") or args.has("rehoused_households")).is_false()
	assert_int(int(args["households"])).is_equal(16)
	assert_bool(_roads(run)[0].resettlement_applied).is_false()
	var rows := PublicWorksState.reaction_rows(_h(run).state(), "displaced", SOURCE)
	assert_int(int(rows[0][1])).is_equal(16)


func test_the_preview_of_a_road_has_no_resettlement_keys_while_the_policy_is_off() -> void:
	var run := _rworld(60, FULL)
	var preview := _f(run).validate_command(SimCommand.public_work_road(PackedInt64Array(DIAGONAL), &"local", true))
	assert_bool(preview.is_rejected()).is_false()
	assert_int(int(preview.args["displaced_households"])).is_equal(16)
	for key in ["resettlement_applied", "rehoused_households", "unplaced_households", "resettlement_cost"]:
		assert_bool(preview.args.has(key)).override_failure_message(key).is_false()


# --- Olumlu O-1: yeterli boş ev ---

func test_with_enough_vacancy_the_households_move_to_the_target_region_and_nothing_is_built() -> void:
	var run := _rworld(60, FULL)
	_policy(run, true)
	var built_before := _res_built(run, SOURCE) + _res_built(run, TARGET)
	_road(run)
	var record := _record(run)
	assert_array(record["moves"]).is_equal([[SOURCE, TARGET, 16]])
	assert_int(int(record["rehoused"])).is_equal(16)
	assert_int(int(record["unplaced"])).is_equal(0)
	assert_int(int(record["partial"])).is_equal(0)
	assert_int(_latent(run, SOURCE)).is_equal(420 - 16)  # kaynakta azaldı (başlangıç 420)
	assert_int(_latent(run, TARGET)).is_equal(40 + 16)  # hedefte arttı
	# CAN-03: yalnız yıkım konut birimini düşürdü (16 birim); hiçbir yerde birim artmadı
	assert_int(_res_built(run, SOURCE) + _res_built(run, TARGET)).is_equal(built_before - 16)
	assert_int(_res_built(run, TARGET)).is_equal(100)


func test_the_preview_the_event_the_record_and_the_view_all_say_the_same_numbers() -> void:
	var run := _rworld(60, FULL)
	_policy(run, true)
	var cmd := SimCommand.public_work_road(PackedInt64Array(DIAGONAL), &"local", true)
	var preview := _f(run).validate_command(cmd)
	var queued := _f(run).submit_command(cmd)
	_f(run).advance(1)
	var record := _record(run)
	var event_args := _events(run, SimEvent.KIND_PUBLIC_WORK_EXPROPRIATED)[0].args
	var view := _roads(run)[0]
	for args: Dictionary in [preview.args, queued.args, event_args]:
		assert_bool(bool(args["resettlement_applied"])).is_true()
		assert_int(int(args["rehoused_households"])).is_equal(int(record["rehoused"]))
		assert_int(int(args["unplaced_households"])).is_equal(int(record["unplaced"]))
		assert_int(int(args["resettlement_cost"])).is_equal(int(record["cost"]))
	assert_bool(view.resettlement_applied).is_true()
	assert_int(view.rehoused_households).is_equal(16)
	assert_int(view.unplaced_households).is_equal(0)
	assert_int(view.resettlement_cost).is_equal(int(record["cost"]))
	assert_int(view.rehoused_households + view.unplaced_households).is_equal(view.displaced_households)


func test_the_cost_is_households_times_months_of_the_target_rent_in_whole_numbers() -> void:
	var run := _rworld(60, FULL)
	_policy(run, true)
	var econ := EconomyTestSupport.config(P.economy_patch())
	var regions: Dictionary = EconomyState.data(_h(run).state())["regions"]
	var r := (regions["codes"] as PackedStringArray).find(TARGET)
	var mult := EconomyMath.rent_mult_pm(EconomyMath.region_demand_pm(econ, regions, r,
		EconomyConfig.USE_RESIDENTIAL, 0), econ.p("rent_floor_pm"), econ.p("rent_cap_pm"))
	var months := _works_config(FULL).resettlement.support_months
	var unit_cost := econ.use_param(EconomyConfig.USE_RESIDENTIAL, "rent_per_unit_month") * mult * months / 1000
	_road(run)
	assert_int(unit_cost).is_greater(0)
	assert_int(int(_record(run)["cost"])).is_equal(16 * unit_cost)


func test_the_remaining_reaction_is_small_but_not_zero_and_the_ledger_stays_raw() -> void:
	var on := _o1()
	var off := _rworld(60, FULL)
	_road(off)
	var cfg: Dictionary = politics_config().reactions["local"]
	var window := int(politics_config().blocs["reaction_window"])
	var reading_on := ReactionAgenda.local_readings(_h(on).state(), window, cfg)[0]
	var reading_off := ReactionAgenda.local_readings(_h(off).state(), window, cfg)[0]
	assert_int(int(reading_off["households"])).is_equal(16)
	assert_int(int(reading_on["households"])).is_equal(4)  # ceil(16 x 200 / 1000): sıfır DEĞİL
	assert_int(int(reading_on["displaced_total"])).override_failure_message("ham sayı kalır").is_equal(16)
	assert_int(int(reading_on["pressure"])).is_less(int(reading_off["pressure"]))
	assert_int(int(reading_on["displacement_pm"])).is_greater(0)
	# defter ham: neden kaydındaki ve defterdeki sayı gerçek yerinden edilen hane
	var rows := PublicWorksState.reaction_rows(_h(on).state(), "displaced", SOURCE)
	assert_int(int(rows[0][1])).is_equal(16)


func test_the_district_signal_uses_the_same_relief_as_the_neighbourhood_reading() -> void:
	var on := _o1()
	var off := _rworld(60, FULL)
	_road(off)
	var signal_on := _district_signal(on)
	var signal_off := _district_signal(off)
	assert_int(signal_on).override_failure_message("kalan tepki sıfır olmamalı").is_greater(0)
	assert_int(signal_on).is_less(signal_off)
	# beklenen: defter satırı [tick, 4 (etkin), komut] ile AYNI fonksiyon (tek rahatlama noktası)
	var rows: Array = PublicWorksState.reaction_rows(_h(on).state(), "displaced", SOURCE)
	var relieved := [[int(rows[0][0]), 4, int(rows[0][2])]]
	var window := int(politics_config().blocs["reaction_window"])
	var latent := _latent(on, SOURCE)
	assert_int(signal_on).is_equal(BlocSignals.reaction_pm(relieved, _h(on).state().tick, window, latent,
		BlocSignals.SCALE))


func _district_signal(run: Dictionary) -> int:
	var h := _h(run)
	var rows := EconomyQuery.region_stats(h.state(), h.context.economy)
	return int(BlocEngine.reaction_signals(h.state(), h.context, rows)[SOURCE]["displacement"])


func test_the_cause_record_shows_the_raw_count_and_the_rehoused_and_unplaced_counts() -> void:
	var run := _o1()
	var h := _h(run)
	var cfg: Dictionary = politics_config().reactions["local"]
	var reading := ReactionAgenda.local_readings(h.state(), int(politics_config().blocs["reaction_window"]), cfg)[0]
	var cause := ReactionCause.record_local(h.state(), h.context, BLOC_HOUSED, reading)
	assert_bool(cause.is_empty()).is_false()
	var factors := {}
	for f: Dictionary in h.state().reasons.by_id(int(cause["id"]))["factors"]:
		factors[String(f["name"])] = int(f["value"])
	assert_int(factors["reason.factor.displaced_household_count"]).override_failure_message("ham sayı").is_equal(16)
	assert_int(factors["reason.factor.rehoused_households"]).is_equal(16)
	assert_int(factors["reason.factor.unplaced_households"]).is_equal(0)


# --- Olumsuz N-1: ev yok ---

func test_without_any_vacancy_the_road_is_still_built_the_count_is_real_and_the_reaction_is_whole() -> void:
	var run := _rworld(0, FULL)
	_policy(run, true)
	_road(run)
	assert_int(_roads(run).size()).override_failure_message("yol yapılmalı (reddedilmez)").is_equal(1)
	var record := _record(run)
	assert_array(record["moves"]).is_empty()
	assert_int(int(record["rehoused"])).is_equal(0)
	assert_int(int(record["unplaced"])).is_equal(16)
	assert_int(int(record["cost"])).is_equal(0)
	assert_int(_latent(run, SOURCE)).is_equal(420)
	assert_int(_latent(run, TARGET)).is_equal(407)
	var args := _events(run, SimEvent.KIND_PUBLIC_WORK_EXPROPRIATED)[0].args
	assert_int(int(args["rehoused_households"])).is_equal(0)
	assert_int(int(args["unplaced_households"])).is_equal(16)
	assert_int(int(args["resettlement_cost"])).is_equal(0)
	var cfg: Dictionary = politics_config().reactions["local"]
	var reading := ReactionAgenda.local_readings(_h(run).state(), int(politics_config().blocs["reaction_window"]),
		cfg)[0]
	assert_int(int(reading["households"])).override_failure_message("tepki tam").is_equal(16)
	var cause := ReactionCause.record_local(_h(run).state(), _h(run).context, BLOC_HOUSED, reading)
	var names := {}
	for f: Dictionary in _h(run).state().reasons.by_id(int(cause["id"]))["factors"]:
		names[String(f["name"])] = int(f["value"])
	assert_int(names["reason.factor.unplaced_households"]).is_equal(16)
	assert_int(names["reason.factor.rehoused_households"]).is_equal(0)


func test_a_road_that_displaces_nobody_writes_no_record_even_with_the_policy_on() -> void:
	var run := _rworld(60, FULL)
	_policy(run, true)
	_f(run).advance(1)
	_spur(run)  # parsel 6 alınır: 6 konut, yerinden edilen var → kayıt VAR
	assert_bool(_record(run).is_empty()).is_false()
	var free := _rworld(60, FULL)  # D1'in barınmayanı hep var; yerinden edilen 0 olan durum: D1'de bekleyen hane yok
	_set_region(free, SOURCE, 0, 22)
	_policy(free, true)
	_road(free)
	assert_int(int(_f(free).public_works()[0].displaced_households)).is_equal(0)
	assert_bool(_record(free).is_empty()).override_failure_message("yerinden edilen 0 iken kayıt yazılmaz").is_true()
	assert_bool(_f(free).public_works()[0].resettlement_applied).is_false()


# --- Olumsuz N-3 ve kısmi ev: kira ve yer şartları ---

## D1: 20 hane / 22 konut (kira 920), D2: 1000 hane / 1050 konut (kira 960, boş ev 50). Yerinden edilen 14.
func _rent_world(resettlement: Dictionary) -> Dictionary:
	var run := _rworld(0, resettlement)
	_set_region(run, SOURCE, 20, 22)
	_set_region(run, TARGET, 1000, 1050)
	_policy(run, true)
	_road(run)
	return run


func test_both_conditions_exceeded_is_not_a_home_and_one_exceeded_is_a_partial_home() -> void:
	var neither := _record(_rent_world({"rent_tolerance_pm": 250, "max_distance_m": 5000}))
	assert_int(int(neither["rehoused"])).is_equal(14)
	assert_int(int(neither["partial"])).override_failure_message("iki şart da tamam: tam ev").is_equal(0)
	var by_place := _record(_rent_world({"rent_tolerance_pm": 250, "max_distance_m": 0}))
	assert_int(int(by_place["partial"])).is_equal(14)  # kira tamam, yer aşıldı
	var by_rent := _record(_rent_world({"rent_tolerance_pm": 0, "max_distance_m": 5000}))
	assert_int(int(by_rent["partial"])).is_equal(14)  # yer tamam, kira aşıldı
	var both := _record(_rent_world({"rent_tolerance_pm": 0, "max_distance_m": 0}))
	assert_int(int(both["rehoused"])).override_failure_message("N-3: ev sayılmaz").is_equal(0)
	assert_int(int(both["unplaced"])).is_equal(14)
	assert_int(int(both["cost"])).is_equal(0)
	# kısmi ev, tam evden DAHA ÇOK tepki bırakır; ev sayılmayan en çok
	assert_int(int(neither["effective"][SOURCE])).is_less(int(by_place["effective"][SOURCE]))
	assert_int(int(by_place["effective"][SOURCE])).is_less(int(both["effective"][SOURCE]))


# --- Ölçüt 6: ardışık iki yol ---

func test_a_second_road_sees_the_homes_the_first_one_took_and_finds_fewer() -> void:
	var alone := _rworld(25, FULL)
	_policy(alone, true)
	_spur(alone)
	var found_alone := int(_record(alone)["rehoused"])
	var run := _rworld(25, FULL)
	_policy(run, true)
	_road(run)
	var first := int(_record(run)["rehoused"])
	assert_int(first).is_equal(7)  # 25 x %30 = 7 (16 yerinden edilenden)
	_spur(run)
	var second := int(_record(run)["rehoused"])
	assert_int(second).is_less(found_alone)
	assert_int(second).is_equal(5)  # kalan boş ev 18: 18 x %30 = 5
	assert_int(int(_record(run)["unplaced"])).is_equal(1)
	assert_int(_latent(run, TARGET)).is_equal(40 + 7 + 5)


# --- Politika durumu değişince ---

func test_policy_set_and_a_road_in_the_same_tick_use_the_new_policy_not_a_stale_preview() -> void:
	var run := _rworld(60, FULL)
	var road := SimCommand.public_work_road(PackedInt64Array(DIAGONAL), &"local", true)
	assert_bool(_f(run).validate_command(road).args.has("rehoused_households")).is_false()  # önizleme belleğe girer
	assert_bool(_f(run).submit_command(SimCommand.policy_set(PolicyView.ID_RESETTLEMENT, true)).is_rejected()).is_false()
	assert_bool(_f(run).submit_command(road).is_rejected()).is_false()  # aynı tick: politika ÖNCE uygulanır
	_f(run).advance(1)
	assert_bool(_record(run).is_empty()).override_failure_message("bayat önizleme: tahsis uygulanmadı").is_false()
	assert_int(int(_record(run)["rehoused"])).is_equal(16)


func test_after_the_policy_is_switched_off_the_next_road_has_no_allocation_but_the_old_one_stays() -> void:
	var run := _o1(FULL, 60)
	_f(run).advance(1)
	_policy(run, false)
	_spur(run)
	assert_bool(_record(run, 0).is_empty()).is_false()
	assert_bool(_record(run, 1).is_empty()).is_true()
	assert_int(_latent(run, TARGET)).override_failure_message("eski tahsis durur").is_equal(56)
