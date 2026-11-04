extends SimTestBase
## T-043A (sim yarısı) · Toplu plan teklifi üst sınırı (`zoning.plan_max_parcels_per_proposal`, core-loop-v0 §2/§7):
## tek komut = tek oylama/tek teklif; sınır veridedir (kodda sabit yok). Yeni komut türü YOKTUR (CAN-03).

const S := preload("res://tests/sim/economy/economy_test_support.gd")


func _ids(count: int) -> PackedInt64Array:
	var out := PackedInt64Array()
	for i in count:
		out.append(i + 1)
	return out


func test_default_limit_is_read_from_facade_data() -> void:
	var cfg := FacadeConfig.load_default()
	assert_bool(cfg.is_valid()).override_failure_message(cfg.error).is_true()
	assert_int(cfg.plan_max_parcels_per_proposal).is_equal(40)


func test_limit_is_optional_in_data_and_must_be_a_positive_int() -> void:
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FacadeConfig.DEFAULT_PATH))
	(raw["zoning"] as Dictionary).erase("plan_max_parcels_per_proposal")
	var missing := FacadeConfig.from_dict(raw)
	assert_bool(missing.is_valid()).is_true()
	assert_int(missing.plan_max_parcels_per_proposal).is_equal(FacadeConfig.DEFAULT_PLAN_MAX_PARCELS)
	for bad: Variant in [0, -3, 2.5, "40"]:
		var copy: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FacadeConfig.DEFAULT_PATH))
		copy["zoning"]["plan_max_parcels_per_proposal"] = bad
		assert_bool(FacadeConfig.from_dict(copy).is_valid()).override_failure_message(str(bad)).is_false()


func test_proposal_over_the_limit_is_rejected_with_the_limit_in_the_args_and_changes_nothing() -> void:
	var f := S.synthetic_handle(60, 1).facade
	var before := f.state_hash()
	var over := f.submit_command(SimCommand.zoning_propose(_ids(41), &"zone.mixed"))
	assert_bool(over.is_rejected()).is_true()
	assert_str(String(over.reason_key)).is_equal("command.reject.invalid_value")
	assert_str(String(over.args["param"])).is_equal("parcel_ids")
	assert_int(int(over.args["max"])).is_equal(40)
	assert_str(f.state_hash()).override_failure_message("reddedilen komut durumu değiştirdi").is_equal(before)


func test_proposal_at_the_limit_is_accepted_and_applies_to_every_listed_parcel() -> void:
	var f := S.synthetic_handle(60, 1, {"decision": {"review_enabled": 0}}).facade
	var ok := f.submit_command(SimCommand.zoning_propose(_ids(40), &"zone.mixed"))
	assert_bool(ok.is_rejected()).is_false()
	f.advance(5)
	for v in f.parcel_views(_ids(40)):
		assert_str(String(v.zone)).is_equal("zone.mixed")
	assert_str(String(f.parcel_views(PackedInt64Array([41]))[0].zone)).is_equal("zone.residential")


func test_validate_command_reports_the_same_rejection() -> void:
	var f := S.synthetic_handle(60, 1).facade
	assert_bool(f.validate_command(SimCommand.zoning_propose(_ids(41), &"zone.mixed")).is_rejected()).is_true()
	assert_bool(f.validate_command(SimCommand.zoning_propose(_ids(40), &"zone.mixed")).is_rejected()).is_false()
