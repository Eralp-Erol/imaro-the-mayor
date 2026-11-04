extends GdUnitTestSuite
## T-023 · MockScenario yükleyicisi bozuk/dürüst olmayan veriyi reddeder: MOCK işareti zorunlu, gerekçe aritmetiği
## tutmalı, etiketler önce tanımlanmalı, sözleşme sürümü uyumlu olmalı.

const S := preload("res://tests/contracts/contract_test_support.gd")


func _errors_after(mutate: Callable) -> PackedStringArray:
	var d := S.scenario_dict(S.SCENARIO_POSITIVE)
	mutate.call(d)
	return MockScenario.from_dict(d).errors


func _has_error(errors: PackedStringArray, fragment: String) -> bool:
	for e in errors:
		if e.contains(fragment):
			return true
	return false


func _first_reason_effect(d: Dictionary) -> Dictionary:
	for e: Dictionary in d["rules"][0]["effects"]:
		if e["type"] == "reason":
			return e
	return {}


func test_all_fixture_scenarios_are_valid() -> void:
	for scenario_name in S.ALL_SCENARIOS:
		var s := S.scenario(scenario_name)
		assert_array(s.errors).override_failure_message("%s: %s" % [scenario_name, s.errors]).is_empty()
		assert_bool(String(s.id).begins_with("mock_")).is_true()


func test_scenario_without_mock_provenance_is_rejected() -> void:
	var errors := _errors_after(func(d: Dictionary) -> void: d["provenance"] = "SIM")
	assert_bool(_has_error(errors, "provenance")).is_true()
	errors = _errors_after(func(d: Dictionary) -> void: d.erase("provenance"))
	assert_bool(_has_error(errors, "provenance")).is_true()


func test_description_must_be_marked_mock() -> void:
	var errors := _errors_after(func(d: Dictionary) -> void: d["description"] = "Gerçek veri gibi görünen açıklama")
	assert_bool(_has_error(errors, "description")).is_true()


func test_declared_outcome_must_match_factor_arithmetic() -> void:
	var errors := _errors_after(func(d: Dictionary) -> void: _first_reason_effect(d)["reason"]["threshold"] = 900)
	assert_bool(_has_error(errors, "declared outcome")).is_true()
	errors = _errors_after(func(d: Dictionary) -> void: _first_reason_effect(d)["reason"]["score"] = 591)
	assert_bool(_has_error(errors, "declared score")).is_true()
	errors = _errors_after(func(d: Dictionary) -> void: _first_reason_effect(d)["reason"].erase("outcome"))
	assert_bool(_has_error(errors, "declared outcome")).is_true()


func test_labels_must_be_defined_before_use() -> void:
	var errors := _errors_after(func(d: Dictionary) -> void: _first_reason_effect(d)["after_ticks"] = 9)
	assert_bool(_has_error(errors, "label 'r_investor'")).is_true()


func test_incompatible_contract_version_is_rejected() -> void:
	var errors := _errors_after(func(d: Dictionary) -> void: d["contract_version"] = "2.0")
	assert_bool(_has_error(errors, "contract_version")).is_true()


func test_unknown_effect_type_and_duplicate_parcel_are_rejected() -> void:
	var bad_effect := {"after_ticks": 1, "type": "spawn_building"}
	var errors := _errors_after(func(d: Dictionary) -> void: d["rules"][0]["effects"].append(bad_effect))
	assert_bool(_has_error(errors, "unknown effect type")).is_true()
	errors = _errors_after(func(d: Dictionary) -> void: d["initial"]["parcels"].append(d["initial"]["parcels"][0]))
	assert_bool(_has_error(errors, "duplicate id")).is_true()


func test_missing_file_reports_error() -> void:
	var s := MockScenario.load_file("res://tests/fixtures/does_not_exist.json")
	assert_bool(s.is_valid()).is_false()
	assert_bool(_has_error(s.errors, "cannot read")).is_true()
