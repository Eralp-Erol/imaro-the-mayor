extends GdUnitTestSuite
## T-040 (M2) sözleşme genişlemesi, sürüm 1.1 (ADR-0005 Ek C): `ParcelView.use/units/progress_pm/developed_by_sim` ve
## `EconomyOutcomeView`. Geriye uyum (eski sözlük -> varsayılan), kayıpsız dönüşüm, uyum kontrolü ve mock paritesi.

const S := preload("res://tests/contracts/contract_test_support.gd")


func _project_parcel() -> ParcelView:
	var p := ParcelView.new()
	p.id = 4
	p.region_code = &"F1"
	p.area_m2 = 1800
	p.development = ParcelView.DEVELOPMENT_UNDER_CONSTRUCTION
	p.use = ParcelView.USE_RESIDENTIAL
	p.units = 12
	p.progress_pm = 250
	p.developed_by_sim = true
	return p


func _region(code: StringName, seed_value: int) -> EconomyRegionOutcome:
	var r := EconomyRegionOutcome.new()
	r.region_code = code
	r.households = 100 + seed_value
	r.housed_households = 80 + seed_value
	r.residential_units = 90 + seed_value
	r.commercial_units = 10 + seed_value
	r.residential_pipeline = 5
	r.commercial_pipeline = 1
	r.sim_residential_units = 20 + seed_value
	r.sim_commercial_units = 2
	r.demand_residential_pm = 600
	r.demand_commercial_pm = 450
	r.infrastructure_load_pm = 300
	return r


func _outcome(tick: int, bump: int) -> EconomyOutcomeView:
	var o := EconomyOutcomeView.new()
	o.provenance = SimContract.PROVENANCE_SIM
	o.tick = tick
	o.available = true
	o.regions.append(_region(&"F1", bump))
	o.regions.append(_region(&"F2", 2 * bump))
	o.investments_approved = 3 + bump
	o.investments_declined = 1
	o.projects_completed = bump
	o.rent_income = 1000 * bump
	return o


# --- Sürüm ---

func test_contract_version_is_minor_bumped_and_old_major_one_documents_stay_compatible() -> void:
	# 1.2 karar özeti, 1.3 yol, 1.4 plan sorguları, 1.5 kamulaştırma, 1.6 geri al + yolu yık, 1.7 yeniden iskân
	assert_str(SimContract.VERSION).is_equal("1.7")
	assert_bool(SimContract.is_compatible("1.0")).is_true()
	assert_bool(SimContract.is_compatible("1.1")).is_true()
	assert_bool(SimContract.is_compatible("1.2")).is_true()
	assert_bool(SimContract.is_compatible("1.3")).is_true()
	assert_bool(SimContract.is_compatible("1.4")).is_true()
	assert_bool(SimContract.is_compatible("1.5")).is_true()
	assert_bool(SimContract.is_compatible("1.6")).is_true()
	assert_bool(SimContract.is_compatible("1.7")).is_true()
	assert_bool(SimContract.is_compatible("2.0")).is_false()


# --- ParcelView ---

func test_parcel_view_new_fields_roundtrip_losslessly_through_dict_and_json() -> void:
	var p := _project_parcel()
	var again := ParcelView.from_dict(p.to_dict())
	assert_bool(again.same_as(p)).is_true()
	assert_str(String(again.use)).is_equal("residential")
	assert_int(again.units).is_equal(12)
	assert_int(again.progress_pm).is_equal(250)
	assert_bool(again.developed_by_sim).is_true()
	var via_json := ParcelView.from_dict(JSON.parse_string(JSON.stringify(p.to_dict())))
	assert_bool(via_json.same_as(p)).override_failure_message("JSON turu kayıplı").is_true()
	assert_str(StateHash.of(p.to_dict())).is_not_empty()


func test_parcel_view_document_without_new_fields_gets_safe_defaults() -> void:
	var p := ParcelView.from_dict({"id": 9, "development": "built"})
	assert_str(String(p.use)).is_empty()
	assert_int(p.units).is_equal(0)
	assert_int(p.progress_pm).is_equal(0)
	assert_bool(p.developed_by_sim).is_false()


func test_each_new_parcel_field_changes_the_dto_hash() -> void:
	var base := StateHash.of(_project_parcel().to_dict())
	for edit: Callable in [
			func(p: ParcelView) -> void: p.use = ParcelView.USE_COMMERCIAL,
			func(p: ParcelView) -> void: p.units += 1,
			func(p: ParcelView) -> void: p.progress_pm += 1,
			func(p: ParcelView) -> void: p.developed_by_sim = false]:
		var p := _project_parcel()
		edit.call(p)
		assert_str(StateHash.of(p.to_dict())).is_not_equal(base)


# --- Uyum kontrolü (SimContractChecks.check_parcel_projects) ---

func test_project_check_accepts_consistent_parcels() -> void:
	var vacant := ParcelView.new()
	vacant.id = 1
	var planned := _project_parcel()
	planned.development = ParcelView.DEVELOPMENT_PLANNED
	planned.progress_pm = 0
	var built := _project_parcel()
	built.development = ParcelView.DEVELOPMENT_BUILT
	built.progress_pm = 1000
	var t0 := _project_parcel()
	t0.development = ParcelView.DEVELOPMENT_BUILT
	t0.progress_pm = 1000
	t0.developed_by_sim = false
	var views: Array[ParcelView] = [vacant, planned, _project_parcel(), built, t0]
	assert_array(SimContractChecks.check_parcel_projects(views)).is_empty()


func test_project_check_catches_each_inconsistency() -> void:
	var cases := {
		"vacant_with_use": func(p: ParcelView) -> void:
			p.development = ParcelView.DEVELOPMENT_VACANT,
		"built_not_complete": func(p: ParcelView) -> void:
			p.development = ParcelView.DEVELOPMENT_BUILT,
		"progress_out_of_range": func(p: ParcelView) -> void: p.progress_pm = 1001,
		"unknown_use": func(p: ParcelView) -> void: p.use = &"industrial",
		"no_units": func(p: ParcelView) -> void: p.units = 0,
		"no_use": func(p: ParcelView) -> void: p.use = &"",
		"planned_with_progress": func(p: ParcelView) -> void:
			p.development = ParcelView.DEVELOPMENT_PLANNED,
	}
	for label: String in cases:
		var p := _project_parcel()
		(cases[label] as Callable).call(p)
		var views: Array[ParcelView] = [p]
		assert_array(SimContractChecks.check_parcel_projects(views)) \
			.override_failure_message("yakalanmadı: %s" % label).is_not_empty()


# --- EconomyOutcomeView ---

func test_outcome_view_roundtrips_and_hashes() -> void:
	var o := _outcome(30, 2)
	var again := EconomyOutcomeView.from_dict(JSON.parse_string(JSON.stringify(o.to_dict())))
	assert_bool(again.same_as(o)).override_failure_message("JSON turu kayıplı").is_true()
	assert_bool(EconomyOutcomeView.from_dict(o.to_dict()).same_as(o)).is_true()
	assert_int(again.regions.size()).is_equal(2)
	assert_str(StateHash.of(o.to_dict())).is_not_empty()


func test_outcome_view_defaults_to_unavailable_with_reasons_and_no_invented_numbers() -> void:
	var o := EconomyOutcomeView.new()
	assert_bool(o.available).is_false()
	assert_str(String(o.unavailable_reason_key)).is_equal("economy.not_built")
	assert_bool(o.municipal_revenue_available).is_false()
	assert_str(String(o.municipal_revenue_reason_key)).is_equal("economy.municipal_revenue.not_built")
	assert_int(o.municipal_revenue).is_equal(0)
	var u := EconomyOutcomeView.unavailable(SimContract.PROVENANCE_MOCK, 7, &"economy.mock")
	assert_bool(u.available).is_false()
	assert_int(u.tick).is_equal(7)
	assert_str(String(u.provenance)).is_equal("mock")
	assert_str(String(u.unavailable_reason_key)).is_equal("economy.mock")
	assert_dict(u.metrics()).is_not_empty()  # anahtarlar var, değerler 0 (UI "henüz yok" için available'a bakar)
	assert_array(SimContractChecks.check_no_aggregate_score(o.to_dict(), "outcome")).is_empty()


func test_outcome_metrics_city_is_sum_of_regions_plus_counters() -> void:
	var o := _outcome(30, 2)
	var city := o.metrics()
	assert_int(city["residential_units"]).is_equal(92 + 94)
	assert_int(city["sim_residential_units"]).is_equal(22 + 24)
	assert_int(city["households"]).is_equal(102 + 104)
	assert_int(city["investments_approved"]).is_equal(5)
	assert_int(city["rent_income"]).is_equal(2000)
	var f1 := o.metrics(&"F1")
	assert_int(f1["residential_units"]).is_equal(92)
	assert_bool(f1.has("investments_approved")).override_failure_message("sayaçlar şehir geneli").is_false()
	assert_dict(o.metrics(&"nope")).override_failure_message("bilinmeyen bölge boş").is_empty()


func test_outcome_delta_since_is_after_minus_before_city_and_region() -> void:
	var before := _outcome(30, 1)
	var after := _outcome(90, 4)
	var city := after.delta_since(before)
	assert_int(city["residential_units"]).is_equal((94 + 98) - (91 + 92))
	assert_int(city["projects_completed"]).is_equal(3)
	assert_int(city["rent_income"]).is_equal(3000)
	var f2 := after.delta_since(before, &"F2")
	assert_int(f2["residential_units"]).is_equal(98 - 92)
	assert_int(after.delta_since(null)["residential_units"]).override_failure_message("öncesi yoksa 0'dan").is_equal(192)


# --- Mock paritesi ---

func test_mock_facade_reports_economy_outcome_as_unavailable_not_invented() -> void:
	var f := S.facade(S.SCENARIO_POSITIVE)
	var o := f.economy_outcome()
	assert_bool(o.available).is_false()
	assert_str(String(o.provenance)).is_equal("mock")
	assert_int(o.tick).is_equal(f.current_tick())
	assert_array(o.regions).is_empty()


func test_mock_positive_scenario_shows_project_fields_while_construction_progresses() -> void:
	var f := S.facade(S.SCENARIO_POSITIVE)
	f.submit_command(SimCommand.zoning_propose(S.ids([1]), &"zone.mixed"))
	var seen := {}
	for _i in 14:
		f.advance(1)
		var p := f.parcel_views(S.ids([1]))[0]
		seen[String(p.development)] = p
		assert_array(SimContractChecks.check_parcel_projects(f.parcel_views(f.parcel_ids()))).is_empty()
	var planned: ParcelView = seen["planned"]
	assert_str(String(planned.use)).is_not_empty()
	assert_int(planned.units).is_greater(0)
	assert_bool(planned.developed_by_sim).is_true()
	var building: ParcelView = seen["under_construction"]
	assert_int(building.progress_pm).is_between(1, 999)
