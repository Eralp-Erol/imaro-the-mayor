extends GdUnitTestSuite
## T-043A köprüsü · Sözleşme 1.4 (ADR-0005 Ek G): `SimFacade.plan_state(parcel_id)` ve `plan_preview(...)` salt okunur
## sorguları. Varsayılan (kaynak plan kavramı sunmuyorsa, mock dahil): `untracked` / `ok == false` — uydurma durum ve
## sayı yok. DTO'lar JSON/dict gidiş-dönüşünde kayıpsızdır.

const S := preload("res://tests/contracts/contract_test_support.gd")


func test_contract_version_has_the_1_4_plan_queries_and_old_documents_stay_compatible() -> void:
	assert_int(SimContract.VERSION_MINOR).is_greater_equal(4)  # 1.4 (T-043A) plan sorguları; 1.5 (T-042b) kamulaştırma
	for older in ["1.0", "1.1", "1.2", "1.3", "1.4", "1.5", "1.6"]:
		assert_bool(SimContract.is_compatible(older)).is_true()
	assert_bool(SimContract.is_compatible("2.0")).is_false()


func test_mock_facade_reports_plans_as_untracked_and_previews_as_not_ok() -> void:
	var f := S.facade(S.SCENARIO_POSITIVE)
	var st := f.plan_state(1)
	assert_str(String(st.state)).is_equal("untracked")
	assert_int(st.parcel_id).is_equal(1)
	assert_str(String(st.provenance)).is_equal("mock")
	var pv := f.plan_preview(S.ids([1, 2]), &"zone.mixed")
	assert_bool(pv.ok).is_false()
	assert_str(String(pv.reason)).is_equal("plan.not_built")
	assert_str(String(pv.provenance)).is_equal("mock")
	assert_int(pv.parcels.size()).is_equal(0)


func test_plan_queries_do_not_change_the_observable_state() -> void:
	var f := S.facade(S.SCENARIO_POSITIVE)
	var before := S.observable_hash(f)
	f.plan_state(1)
	f.plan_preview(S.ids([1]), &"zone.mixed")
	assert_str(S.observable_hash(f)).is_equal(before)


func test_plan_state_view_round_trips_through_json() -> void:
	var v := PlanStateView.new()
	v.parcel_id = 7
	v.state = PlanStateView.STATE_PROPOSED
	v.pending_zone = &"zone.mixed"
	v.due_tick = 12
	v.command_id = 3
	v.source_ref = &"command.3"
	v.density = 800
	v.max_height_m = -1
	v.vote_ref = &"vote.2"
	var back := PlanStateView.from_dict(JSON.parse_string(JSON.stringify(v.to_dict())))
	assert_bool(back.same_as(v)).is_true()
	assert_int(back.due_tick).is_equal(12)
	assert_str(String(back.source_ref)).is_equal("command.3")


func test_plan_preview_view_round_trips_through_json() -> void:
	var v := PlanPreviewView.new()
	v.ok = true
	v.land_use = &"zone.residential"
	v.parcels = [{"id": 4, "region": &"F1", "use": &"residential", "units": 10, "infra_units": 10}]
	v.regions = [{"code": &"F1", "added_units": 10, "added_infra_units": 10, "capacity_units": 100, "load_units": 40,
		"headroom_units": 60, "fits": true}]
	v.total_units = 10
	v.total_infra_units = 10
	v.max_parcels = 40
	v.council_required = true
	v.council_min_parcels = 10
	v.council_min_units = 40
	var back := PlanPreviewView.from_dict(JSON.parse_string(JSON.stringify(v.to_dict())))
	assert_bool(back.same_as(v)).is_true()
	assert_int(int(back.parcels[0]["units"])).is_equal(10)
	assert_bool(bool(back.regions[0]["fits"])).is_true()
	assert_bool(back.council_required).is_true()
	assert_int(back.council_min_parcels).is_equal(10)
	assert_int(back.council_min_units).is_equal(40)
	assert_bool(PlanPreviewView.new().to_dict().has("council_min_parcels")).is_true()
