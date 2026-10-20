extends SimTestBase
## T-013 ölçüt 9 · Denge hipotezleri (ölçülebilir, KANON DEĞİL): çalışma modelinin yönlerini koruyan ilişki testleri.
## Sayılar `data/sim/economy/economy_config.json` varsayılanlarıyla ölçülmüştür (tablo: T-013 raporu/spec §9); ayar
## değişince ilişkiler (monotonluk) korunmalı, mutlak değerler değişebilir. Sentetik 200 parsellik tek bölge.

const S := preload("res://tests/sim/economy/economy_test_support.gd")
const PARCELS := 200
const BIG_INFRA := {"infra_capacity_units": 100000}


func _patch(region: Dictionary, extra: Dictionary = {}) -> Dictionary:
	return S.merge({"regions": {"defaults": S.merge(BIG_INFRA, region)}}, extra)


func _run(patch: Dictionary, ticks: int) -> EconomyHandle:
	var h := S.synthetic_handle(PARCELS, 1, patch)
	h.facade.advance(ticks)
	return h


func _approvals(h: EconomyHandle) -> int:
	return EconomyQuery.totals(h.facade.game_state())["approvals"]


func _row(h: EconomyHandle) -> Dictionary:
	return EconomyQuery.region_stats(h.facade.game_state(), h.config)[0]


func _avg_vacant_land(h: EconomyHandle) -> int:
	var d := EconomyState.data(h.facade.game_state())
	var stage: PackedByteArray = d["stage"]
	var land: PackedInt64Array = d["land_value"]
	var sum := 0
	var count := 0
	for i in stage.size():
		if stage[i] == EconomyState.STAGE_VACANT:
			sum += land[i]
			count += 1
	return sum / maxi(count, 1)


func test_h1_investment_rises_with_housing_scarcity() -> void:
	var last := -1
	for hh in [0, 20, 100, 400]:
		var n := _approvals(_run(_patch({"initial_households": hh}), 360))
		assert_int(n).override_failure_message("hane %d: %d, önceki %d" % [hh, n, last]).is_greater(last)
		last = n
	assert_int(last).is_greater(0)
	var none := _approvals(_run(_patch({"initial_households": 0}), 360))
	assert_int(none).override_failure_message("talep yok: yatırım yok").is_equal(0)


func test_h2_investment_is_self_limiting_as_supply_catches_up_with_demand() -> void:
	var h := S.synthetic_handle(PARCELS, 1, _patch({"initial_households": 150}))
	var windows: Array[int] = []
	var last := 0
	for w in 12:
		h.facade.advance(30)
		var n := _approvals(h)
		windows.append(n - last)
		last = n
	assert_int(windows[0]).override_failure_message(str(windows)).is_greater(0)
	var tail := 0
	for i in range(3, 12):
		tail += windows[i]
	assert_int(tail).override_failure_message("arz talebe yetişince yeni başlangıç olmaz: %s" % str(windows)).is_equal(0)
	assert_int(_row(h)["demand_res_pm"]).override_failure_message("denge civarı").is_between(400, 600)


func test_h3_higher_density_fills_infrastructure_with_fewer_projects() -> void:
	var last := 1 << 30
	for density in [500, 1000, 2000, 3000]:
		var patch := S.merge({"regions": {"defaults": {"initial_households": 3000, "infra_capacity_units": 400}}},
			{"zones": {"zone.residential": {"uses": ["residential"], "density_pm": density}}})
		var h := _run(patch, 360)
		var n := _approvals(h)
		assert_int(n).override_failure_message("yoğunluk %d" % density).is_less(last)
		assert_int(_row(h)["infra_load_pm"]).override_failure_message("altyapı dolmaya yakın").is_greater_equal(900)
		last = n


func test_h4_extreme_demand_bids_land_up_and_normal_demand_does_not() -> void:
	var calm := _run(_patch({"initial_households": 100}), 360)
	var hot := _run(_patch({"initial_households": 800}), 360)
	assert_int(_avg_vacant_land(calm)).is_equal(1000)
	assert_int(_avg_vacant_land(hot)).override_failure_message("aşırı talepte arsa değeri yükselir").is_greater(1100)
	assert_int(_avg_vacant_land(hot)).is_less_equal(3000)


func test_h5_good_access_and_services_attract_households_and_investment() -> void:
	var mixed := {"zones": {"zone.residential": {"uses": ["residential", "commercial"], "density_pm": 1000}}}
	var poor := _run(_patch({"initial_households": 300, "access_pm": 0, "service_pm": 0}, mixed), 720)
	var good := _run(_patch({"initial_households": 300, "access_pm": 1000, "service_pm": 1000}, mixed), 720)
	assert_int(_row(good)["latent_hh"]).is_greater(_row(poor)["latent_hh"])
	assert_int(_row(poor)["latent_hh"]).override_failure_message("kötü hizmet: hane azalır").is_less(300)
	assert_int(_approvals(good)).is_greater(_approvals(poor))


func test_h5b_mixed_zoning_creates_jobs_that_residential_only_cannot() -> void:
	var mixed := {"zones": {"zone.residential": {"uses": ["residential", "commercial"], "density_pm": 1000}}}
	var res_only := _run(_patch({"initial_households": 300}), 720)
	var with_jobs := _run(_patch({"initial_households": 300}, mixed), 720)
	assert_int(_row(res_only)["com_built"]).is_equal(0)
	assert_int(_row(with_jobs)["com_built"]).is_greater(0)
	assert_int(_row(with_jobs)["latent_hh"]).override_failure_message("iş çekimi hane artırır") \
		.is_greater(_row(res_only)["latent_hh"])


func test_h6_capital_limits_the_pace_and_inflow_restores_it() -> void:
	var broke := {"investors": {"list": [{"capital": 5000, "threshold_shift": 0, "monthly_inflow": 0},
		{"capital": 5000, "threshold_shift": 0, "monthly_inflow": 0}]}}
	var funded := {"investors": {"list": [{"capital": 5000, "threshold_shift": 0, "monthly_inflow": 6000},
		{"capital": 5000, "threshold_shift": 0, "monthly_inflow": 6000}]}}
	var stuck := _run(_patch({"initial_households": 2000}, broke), 360)
	var flowing := _run(_patch({"initial_households": 2000}, funded), 360)
	assert_int(_approvals(stuck)).override_failure_message("proje bedelinden az sermaye: yatırım yok").is_equal(0)
	var codes := {}
	for rec in stuck.facade.game_state().reasons.find({}):
		codes[String(rec["code"])] = true
	assert_array(codes.keys()).is_equal(["insufficient_financing"])
	assert_int(_approvals(flowing)).is_greater(5)
