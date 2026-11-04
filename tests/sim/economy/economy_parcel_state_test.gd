extends SimTestBase
## T-013 ölçüt 2 · Parsel durumu (`zoning`, `development_stage`, `owner_id`, `land_value`) sim durumunda; kayda ve
## hash'e girer; T0 mevcut stok `ExistingStockSource` ile `built` doğar; ekonomi kurulu değilse facade değişmez.

const W := preload("res://tests/sim/economy/economy_world.gd")
const S := preload("res://tests/sim/economy/economy_test_support.gd")
## Otonom tarama kapalı: ilk tick'te hiçbir yatırım kararı verilmesin (durum düzenini ölçmek için).
const NO_REVIEW := {"decision": {"review_enabled": 0}}


func _stock(f: SimFacadeImpl) -> ListStockSource:
	var ids := f.parcel_ids()
	return ListStockSource.create([
		{"parcel_id": ids[0], "use": &"residential", "units": 12, "owner": 0},
		{"parcel_id": ids[1], "use": &"commercial", "units": 5, "owner": 0},
	])


func test_without_economy_installed_parcels_stay_as_the_source_template() -> void:
	var f := FacadeTestSupport.facade(3)
	f.advance(5)
	assert_dict(S.raw_config()).is_not_empty()
	for v in f.parcel_views(f.parcel_ids()):
		assert_str(String(v.development)).is_equal("vacant")
	assert_bool(f.game_state().systems.has("economy")).is_false()


func test_state_is_created_on_first_tick_with_one_row_per_parcel() -> void:
	var f := W.facade(NO_REVIEW)
	assert_bool(f.game_state().systems.has("economy")).override_failure_message("ilk tick'ten önce durum yok").is_false()
	f.advance(1)
	var d := W.data(f)
	var n := f.snapshot().parcel_count
	assert_int(n).is_greater(0)
	for column in ["parcel_ids", "stage", "use", "units", "owner_id", "land_value", "days_left", "reason_id",
			"last_code", "last_reason_tick"]:
		assert_int(d[column].size()).override_failure_message("sütun %s" % column).is_equal(n)
	assert_array(Array(d["parcel_ids"])).is_equal(Array(f.parcel_ids()))
	for stage: int in d["stage"]:
		assert_int(stage).is_equal(EconomyState.STAGE_VACANT)


func test_land_value_starts_from_the_source_template() -> void:
	var f := W.facade()
	f.advance(1)
	for v in f.parcel_views(f.parcel_ids()):
		assert_int(v.land_value).is_equal(FacadeTestSupport.LAND_VALUE)


func test_existing_stock_starts_built_without_any_decision_record() -> void:
	var probe := W.facade()
	var f := W.facade({}, S.SEED, S.PER_REGION, _stock(probe))
	f.advance(1)
	var ids := f.parcel_ids()
	var views := f.parcel_views(PackedInt64Array([ids[0], ids[1], ids[2]]))
	assert_str(String(views[0].development)).is_equal("built")
	assert_str(String(views[1].development)).is_equal("built")
	assert_str(String(views[2].development)).override_failure_message("stoksuz parsel boş doğar").is_equal("vacant")
	var rec := EconomyQuery.parcel_record(f.game_state(), ids[0])
	assert_int(rec["units"]).is_equal(12)
	assert_str(String(rec["use"])).is_equal("residential")
	assert_int(f.reasons_for(SimContract.parcel_ref(ids[0])).size()) \
		.override_failure_message("T0 stoğu karar değil") \
		.is_equal(0)


func test_existing_stock_feeds_region_supply_and_households() -> void:
	var probe := W.facade()
	var h := W.handle({}, S.SEED, S.PER_REGION, _stock(probe))
	h.facade.advance(1)
	var region := h.facade.parcel_views(PackedInt64Array([h.facade.parcel_ids()[0]]))[0].region_code
	var stats := EconomyQuery.region_stats(h.facade.game_state(), h.config)
	var row: Dictionary = stats.filter(func(r: Dictionary) -> bool: return r["code"] == region)[0]
	assert_int(row["res_built"]).is_equal(12)
	# latent_hh = initial_households (200) + stok (12) * initial_occupancy_pm (950) / 1000 = 200 + 11 (sıfıra doğru
	# kesme)
	assert_int(row["latent_hh"]).is_equal(211)


func test_economy_columns_are_part_of_the_state_hash() -> void:
	var a := W.facade()
	var b := W.facade()
	a.advance(1)
	b.advance(1)
	assert_str(assert_hash(a.state_hash())).is_equal(b.state_hash())
	var d: Dictionary = b.game_state().systems["economy"]
	d["land_value"][0] = int(d["land_value"][0]) + 1
	assert_str(b.state_hash()).override_failure_message("land_value hash'e girmiyor").is_not_equal(a.state_hash())
	d["land_value"][0] = int(d["land_value"][0]) - 1
	d["owner_id"][0] = 3
	assert_str(b.state_hash()).override_failure_message("owner_id hash'e girmiyor").is_not_equal(a.state_hash())
	d["owner_id"][0] = 0
	d["stage"][0] = EconomyState.STAGE_BUILT
	assert_str(b.state_hash()).override_failure_message("stage hash'e girmiyor").is_not_equal(a.state_hash())


func test_stock_naming_unknown_parcel_is_rejected_at_setup() -> void:
	var bad := ListStockSource.create([{"parcel_id": 99999, "use": &"residential", "units": 3, "owner": 0}])
	var problem := EconomySystem.setup_problem(FacadeTestSupport.fixture_source(3), S.config(), bad)
	assert_str(problem).contains("99999")
	assert_str(EconomySystem.setup_problem(FacadeTestSupport.fixture_source(3), S.config(), null)).is_empty()


func test_stock_investor_owner_beyond_the_pool_is_rejected_at_setup() -> void:
	var bad := ListStockSource.create([{"parcel_id": 1, "use": &"residential", "units": 3, "owner": 99}])
	assert_str(EconomySystem.setup_problem(FacadeTestSupport.fixture_source(3), S.config(), bad)).contains("owner")


func test_parcel_record_of_unknown_parcel_is_empty() -> void:
	var f := W.facade()
	f.advance(1)
	assert_dict(EconomyQuery.parcel_record(f.game_state(), 424242)).is_empty()
	assert_dict(EconomyQuery.parcel_record(FacadeTestSupport.facade(3).game_state(), 1)).is_empty()
