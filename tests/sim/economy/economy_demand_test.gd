extends SimTestBase
## T-013 ölçüt 3 · Hane/talep (SIM-01): bölge başına birleşik talep kohortları (konut/iş), gelir/erişim/hizmet
## girdileri.
## Saf matematik `EconomyMath` ve aylık kohort akışı `EconomySystem.on_monthly`. Yatırım kapalı tutulur
## (base_threshold çok yüksek) ki kohort davranışı yatırımcı kararından ayrı ölçülsün.

const W := preload("res://tests/sim/economy/economy_world.gd")
const S := preload("res://tests/sim/economy/economy_test_support.gd")
const NO_INVEST := {"decision": {"base_threshold": 1000000}}


func _cfg_patch(region: Dictionary) -> Dictionary:
	return S.merge(NO_INVEST, {"regions": {"defaults": region}})


func _latent(f: SimFacadeImpl, code: StringName, cfg: EconomyConfig) -> int:
	return EconomyQuery.region_stats(f.game_state(), cfg).filter(
		func(r: Dictionary) -> bool: return r["code"] == code)[0]["latent_hh"]


# --- Saf matematik ---

func test_demand_index_is_500_at_balance_and_rises_with_shortage() -> void:
	assert_int(EconomyMath.demand_index_pm(100, 100, 1000)).is_equal(500)
	assert_int(EconomyMath.demand_index_pm(100, 80, 1000)).is_equal(700)
	assert_int(EconomyMath.demand_index_pm(100, 0, 1000)).is_equal(1000)
	assert_int(EconomyMath.demand_index_pm(100, 60, 500)).override_failure_message("kazanç ölçekler").is_equal(700)


func test_demand_index_falls_to_zero_when_oversupplied_and_is_bounded() -> void:
	assert_int(EconomyMath.demand_index_pm(100, 120, 1000)).is_equal(300)
	assert_int(EconomyMath.demand_index_pm(100, 1000, 1000)).is_equal(0)
	assert_int(EconomyMath.demand_index_pm(0, 0, 1000)) \
		.override_failure_message("talep eden yok: talep yok, sıfıra bölme yok") \
		.is_equal(0)
	assert_int(EconomyMath.demand_index_pm(0, 50, 1000)).is_equal(0)


func test_demand_value_maps_index_to_signed_thousand_scale() -> void:
	assert_int(EconomyMath.demand_value(500)).is_equal(0)
	assert_int(EconomyMath.demand_value(1000)).is_equal(1000)
	assert_int(EconomyMath.demand_value(0)).is_equal(-1000)
	assert_int(EconomyMath.demand_value(750)).is_equal(500)


func test_rent_multiplier_runs_from_floor_to_cap() -> void:
	assert_int(EconomyMath.rent_mult_pm(0, 600, 1400)).is_equal(600)
	assert_int(EconomyMath.rent_mult_pm(1000, 600, 1400)).is_equal(1400)
	assert_int(EconomyMath.rent_mult_pm(500, 600, 1400)).is_equal(1000)


func test_project_units_follow_density_and_height_cap() -> void:
	# 1800 m2 x 6/1000 m2 = 10.8 -> 10 (sıfıra doğru), taban yoğunluk, sınır yok
	assert_int(EconomyMath.project_units(1800, 6, 1000, -1, 3, 4)).is_equal(10)
	assert_int(EconomyMath.project_units(1800, 6, 2000, -1, 3, 4)).override_failure_message("yoğunluk x2").is_equal(21)
	assert_int(EconomyMath.project_units(1800, 6, 1000, 6, 3, 4)) \
		.override_failure_message("6 m = 2 kat = yarım") \
		.is_equal(5)
	assert_int(EconomyMath.project_units(1800, 6, 1000, 400, 3, 4)) \
		.override_failure_message("referans katı aşmaz") \
		.is_equal(10)
	assert_int(EconomyMath.project_units(1800, 6, 0, -1, 3, 4)) \
		.override_failure_message("yoğunluk 0 = yapılamaz") \
		.is_equal(0)
	assert_int(EconomyMath.project_units(1800, 6, 1000, 2, 3, 4)) \
		.override_failure_message("bir kata yetmeyen yükseklik") \
		.is_equal(0)
	assert_int(EconomyMath.project_units(10, 6, 1000, -1, 3, 4)) \
		.override_failure_message("çok küçük parsel en az 1") \
		.is_equal(1)


func test_fraction_accumulator_has_no_truncation_bias() -> void:
	# +/- aynı büyüklükte oran aynı büyüklükte değişim verir ve kalan biriktirilir.
	var up := EconomyMath.accumulate_pm(100, 18, 0)
	var down := EconomyMath.accumulate_pm(100, -18, 0)
	assert_int(up[0]).is_equal(1)
	assert_int(down[0]).is_equal(-1)
	var total := 0
	var rem := 0
	for i in 10:
		var step := EconomyMath.accumulate_pm(100, 18, rem)
		total += step[0]
		rem = step[1]
	assert_int(total).override_failure_message("10 ay x %1.8 x 100 = 18").is_equal(18)


# --- Kohortlar ---

func test_initial_households_come_from_config_and_are_housed_zero_without_stock() -> void:
	var h := W.handle(_cfg_patch({"initial_households": 123}))
	h.facade.advance(1)
	var row: Dictionary = EconomyQuery.region_stats(h.facade.game_state(), h.config)[0]
	assert_int(row["latent_hh"]).is_equal(123)
	assert_int(row["housed_hh"]).override_failure_message("konut yok: barınan yok").is_equal(0)
	assert_int(row["demand_res_pm"]).override_failure_message("tam kıtlık").is_equal(1000)
	assert_int(row["demand_com_pm"]).override_failure_message("müşteri yok: ticaret talebi 0").is_equal(0)


func test_good_access_and_service_grow_households_monthly() -> void:
	var h := W.handle(_cfg_patch({"initial_households": 400, "access_pm": 1000, "service_pm": 1000}))
	h.facade.advance(30)
	assert_int(_latent(h.facade, S.R1, h.config)).override_failure_message("pull 800 -> +18 promil").is_equal(407)
	h.facade.advance(30)
	assert_int(_latent(h.facade, S.R1, h.config)).override_failure_message("kesir birikimi").is_equal(414)


func test_poor_access_and_service_shrink_households_out_migration() -> void:
	var h := W.handle(_cfg_patch({"initial_households": 400, "access_pm": 0, "service_pm": 0}))
	h.facade.advance(30)
	assert_int(_latent(h.facade, S.R1, h.config)).override_failure_message("pull 200 -> -18 promil").is_equal(393)


func test_neutral_inputs_hold_households_steady() -> void:
	var h := W.handle(_cfg_patch({"initial_households": 400, "access_pm": 625, "service_pm": 625}))
	h.facade.advance(90)
	# pull = (625*300 + 625*300 + 500*400)/1000 = 575 -> küçük pozitif büyüme; sapma sınırlı
	var v := _latent(h.facade, S.R1, h.config)
	assert_int(v).is_between(400, 420)


func test_jobs_from_commercial_stock_raise_the_pull_of_the_region() -> void:
	var base := W.facade(_cfg_patch({"initial_households": 100}))
	base.advance(1)
	var ids := base.parcel_ids(S.R1)
	var stock := ListStockSource.create([
		{"parcel_id": ids[0], "use": &"residential", "units": 100, "owner": 0},
		{"parcel_id": ids[1], "use": &"commercial", "units": 20, "owner": 0},
	])
	var with_jobs := W.handle(_cfg_patch({"initial_households": 100}), S.SEED, S.PER_REGION, stock)
	var stock_no_jobs := ListStockSource.create([{"parcel_id": ids[0], "use": &"residential", "units": 100, "owner": 0}])
	var without_jobs := W.handle(_cfg_patch({"initial_households": 100}), S.SEED, S.PER_REGION, stock_no_jobs)
	with_jobs.facade.advance(60)
	without_jobs.facade.advance(60)
	assert_int(_latent(with_jobs.facade, S.R1, with_jobs.config)) \
		.override_failure_message("iş olan bölge daha çok hane çekmeli") \
		.is_greater(_latent(without_jobs.facade, S.R1, without_jobs.config))


func test_commercial_demand_needs_housed_customers_and_scales_with_income() -> void:
	var probe := W.facade(NO_INVEST)
	probe.advance(1)
	var res_id := probe.parcel_ids(S.R1)[0]
	var stock := ListStockSource.create([
		{"parcel_id": res_id, "use": &"residential", "units": 100, "owner": 0},
		{"parcel_id": probe.parcel_ids(S.R1)[1], "use": &"commercial", "units": 5, "owner": 0},
	])
	var poor := W.handle(_cfg_patch({"initial_households": 100, "income_pm": 500}), S.SEED, S.PER_REGION, stock)
	var rich := W.handle(_cfg_patch({"initial_households": 100, "income_pm": 2000}), S.SEED, S.PER_REGION, stock)
	poor.facade.advance(1)
	rich.facade.advance(1)
	var poor_row: Dictionary = EconomyQuery.region_stats(poor.facade.game_state(), poor.config)[0]
	var rich_row: Dictionary = EconomyQuery.region_stats(rich.facade.game_state(), rich.config)[0]
	assert_int(poor_row["housed_hh"]).is_equal(100)
	assert_int(rich_row["demand_com_pm"]) \
		.override_failure_message("zengin bölge ticarete daha çok talep") \
		.is_greater(poor_row["demand_com_pm"])
	assert_int(poor_row["demand_com_pm"]).override_failure_message("denge: need 5 = supply 5").is_equal(500)
	assert_int(rich_row["demand_com_pm"]).is_equal(1000)


func test_housing_demand_is_per_region_not_global() -> void:
	var patch := S.merge(NO_INVEST, S.regions({"F1": S.favorable(), "F2": S.unfavorable()}))
	var h := W.handle(patch)
	h.facade.advance(1)
	var rows := EconomyQuery.region_stats(h.facade.game_state(), h.config)
	assert_int(rows.size()).is_equal(2)
	assert_int(rows[0]["latent_hh"]).is_equal(400)
	assert_int(rows[1]["latent_hh"]).is_equal(12)
	assert_int(rows[0]["infra_cap"]).is_equal(2000)
	assert_int(rows[1]["infra_cap"]).is_equal(4)


func test_growth_fraction_is_carried_between_months() -> void:
	# 100 hane x %1,8 = 1,8: ay 1 +1 (kalan 800), ay 2 (101 x 18 + 800) / 1000 = +2 => 103. Kalan atılırsa 102 olurdu.
	var h := W.handle(_cfg_patch({"initial_households": 100, "access_pm": 1000, "service_pm": 1000}))
	h.facade.advance(60)
	assert_int(_latent(h.facade, S.R1, h.config)).is_equal(103)
