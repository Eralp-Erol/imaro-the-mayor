extends SimTestBase
## T-013 ölçüt 6(d)/9 · Aylık arsa değeri dinamiği (aşırı talep -> spekülasyon, kısmi) ve yatırımcı kira geliri
## (finansman geri bildirimi). Yatırım kapalı tutulur (review_enabled = 0): değerler yalnız aylık akıştan gelir.

const W := preload("res://tests/sim/economy/economy_world.gd")
const S := preload("res://tests/sim/economy/economy_test_support.gd")
## Yatırım ve dış sermaye girdisi kapalı: sermaye değişimi yalnız kiradan gelir.
const ISOLATE := {
	"decision": {"review_enabled": 0},
	"investors": {"list": [
		{"capital": 80000, "threshold_shift": 0, "monthly_inflow": 0},
		{"capital": 80000, "threshold_shift": 0, "monthly_inflow": 0},
	]},
}


func _land(f: SimFacadeImpl, p: int) -> int:
	return EconomyQuery.parcel_record(f.game_state(), p)["land_value"]


func test_extreme_demand_bids_up_vacant_buildable_land_every_month() -> void:
	var h := W.handle(S.merge(ISOLATE, {"regions": {"defaults": {"initial_households": 5000}}}))
	var p := int(h.facade.parcel_ids()[0])
	h.facade.advance(29)
	assert_int(_land(h.facade, p)).override_failure_message("ay dolmadan değişmez").is_equal(1000)
	h.facade.advance(1)
	assert_int(_land(h.facade, p)).is_equal(1020)
	h.facade.advance(30)
	assert_int(_land(h.facade, p)).is_equal(1040)
	assert_int(h.facade.parcel_views(PackedInt64Array([p]))[0].land_value) \
		.override_failure_message("ParcelView yansıtır") \
		.is_equal(1040)


func test_land_bid_up_is_capped_at_the_configured_multiple_of_the_base_value() -> void:
	var capped := {"regions": {"defaults": {"initial_households": 5000}}, "land": {"max_multiplier_pm": 1100}}
	var h := W.handle(S.merge(ISOLATE, capped))
	var p := int(h.facade.parcel_ids()[0])
	h.facade.advance(30 * 12)
	assert_int(_land(h.facade, p)).is_equal(1100)


func test_land_value_relaxes_toward_the_base_when_demand_is_weak() -> void:
	var h := W.handle(S.merge(ISOLATE, {"regions": {"defaults": {"initial_households": 0}}}))
	var p := int(h.facade.parcel_ids()[0])
	h.facade.advance(1)
	var land: PackedInt64Array = W.data(h.facade)["land_value"]
	land[0] = 2000
	h.facade.advance(29)
	assert_int(_land(h.facade, p)).override_failure_message("(2000-1000) x 30/1000 = 30 geri").is_equal(1970)
	h.facade.advance(30 * 40)
	assert_int(_land(h.facade, p)) \
		.override_failure_message("tabana yakınsar (%3 gevşeme/ay), altına inmez") \
		.is_between(1000, 1300)


func test_land_value_is_stable_in_the_neutral_demand_band() -> void:
	# D = 500+: ne spekülasyon (>=800) ne gevşeme (<=450). Kıtlık %40 -> D = 900? Dengede: latent = 10 projeye denk.
	var calm := {"regions": {"defaults": {"initial_households": 100}}, "decision": {"demand_gain_pm": 100}}
	var h := W.handle(S.merge(ISOLATE, calm))
	var p := int(h.facade.parcel_ids()[0])
	h.facade.advance(30 * 4)
	assert_int(_land(h.facade, p)).is_equal(1000)


func test_built_and_unbuildable_parcels_are_not_speculated_on() -> void:
	var probe := W.facade(ISOLATE)
	var built := int(probe.parcel_ids()[0])
	var stock := ListStockSource.create([{"parcel_id": built, "use": &"residential", "units": 5, "owner": 0}])
	var patch := S.merge(ISOLATE, {"regions": {"defaults": {"initial_households": 5000}},
		"zones": {"zone.residential": {"uses": ["residential"], "density_pm": 1000}}})
	var h := W.handle(patch, S.SEED, S.PER_REGION, stock)
	var green := int(h.facade.parcel_ids()[1])
	h.facade.submit_command(SimCommand.zoning_propose(PackedInt64Array([green]), &"zone.green"))
	h.facade.advance(90)
	assert_int(_land(h.facade, built)).override_failure_message("yapılı parsel").is_equal(1000)
	assert_int(_land(h.facade, green)) \
		.override_failure_message("yapılanmaya kapalı imar") \
		.is_less_equal(1000 + 20)  # ilk ay imar yürürlükten önce
	assert_int(_land(h.facade, int(h.facade.parcel_ids()[2]))) \
		.override_failure_message("boş yapılabilir parsel") \
		.is_greater(1000)


func test_landowner_built_stock_pays_no_rent_to_investors() -> void:
	var probe := W.facade(ISOLATE)
	var p := int(probe.parcel_ids()[0])
	var stock := ListStockSource.create([{"parcel_id": p, "use": &"residential", "units": 10, "owner": 0}])
	var h := W.handle(ISOLATE, S.SEED, S.PER_REGION, stock)
	h.facade.advance(90)
	assert_int(EconomyQuery.totals(h.facade.game_state())["rent_income"]).is_equal(0)


func test_investor_owned_built_parcel_pays_rent_into_investor_capital_monthly() -> void:
	var probe := W.facade(ISOLATE)
	var p := int(probe.parcel_ids()[0])
	var stock := ListStockSource.create([{"parcel_id": p, "use": &"residential", "units": 10, "owner": 2}])
	var patch := S.merge(ISOLATE, {"regions": {"defaults": {"initial_households": 100}}})
	var h := W.handle(patch, S.SEED, S.PER_REGION, stock)
	var capital: PackedInt64Array = PackedInt64Array()
	h.facade.advance(1)
	capital = W.data(h.facade)["investors"]["capital"]
	var before := capital[1]
	h.facade.advance(29)  # tick 30: ilk aylık akış
	var row: Dictionary = EconomyQuery.region_stats(h.facade.game_state(), h.config)[0]
	var mult := EconomyMath.rent_mult_pm(row["demand_res_pm"], h.config.p("rent_floor_pm"), h.config.p("rent_cap_pm"))
	var expected := 10 * h.config.use_param(EconomyConfig.USE_RESIDENTIAL, "rent_per_unit_month") * mult / 1000
	assert_int(capital[1] - before).override_failure_message("kira = birim x aylık kira x çarpan").is_equal(expected)
	assert_int(capital[0]) \
		.override_failure_message("başka yatırımcı gelir almaz") \
		.is_equal(h.config.investors[0]["capital"])
	assert_int(EconomyQuery.totals(h.facade.game_state())["rent_income"]).is_equal(expected)


func test_rent_is_higher_where_demand_is_higher() -> void:
	var probe := W.facade(ISOLATE)
	var ids := probe.parcel_ids(S.R1)
	var stock := ListStockSource.create([
		{"parcel_id": ids[0], "use": &"residential", "units": 10, "owner": 1},
		{"parcel_id": probe.parcel_ids(S.R2)[0], "use": &"residential", "units": 10, "owner": 1},
	])
	var h := W.handle(S.merge(ISOLATE, S.regions({"F1": {"initial_households": 1000}, "F2": {"initial_households": 0}})),
		S.SEED, S.PER_REGION, stock)
	h.facade.advance(1)
	var capital: PackedInt64Array = W.data(h.facade)["investors"]["capital"]
	h.facade.advance(29)
	assert_int(EconomyQuery.totals(h.facade.game_state())["rent_income"]).is_greater(0)
	var rows := EconomyQuery.region_stats(h.facade.game_state(), h.config)
	assert_int(rows[0]["demand_res_pm"]).is_greater(rows[1]["demand_res_pm"])
	var floor_pm := h.config.p("rent_floor_pm")
	var cap_pm := h.config.p("rent_cap_pm")
	var mult_high := EconomyMath.rent_mult_pm(rows[0]["demand_res_pm"], floor_pm, cap_pm)
	var mult_low := EconomyMath.rent_mult_pm(rows[1]["demand_res_pm"], floor_pm, cap_pm)
	var rent_unit := h.config.use_param(EconomyConfig.USE_RESIDENTIAL, "rent_per_unit_month")
	var expected: int = h.config.investors[0]["capital"] + 10 * rent_unit * mult_high / 1000 \
		+ 10 * rent_unit * mult_low / 1000
	assert_int(capital[0]).is_equal(expected)
