extends GdUnitTestSuite
## T-023 · Komut sözleşmesi: beyaz liste yalnız belediye fiilleri (CAN-03), ortak şekil doğrulaması gerekçeli reddeder.


func _reason_of(cmd: SimCommand) -> String:
	var problem := cmd.validate_shape()
	return "" if problem.is_empty() else String(problem["reason_key"])


func test_catalog_contains_only_mayor_verbs() -> void:
	assert_int(SimCommand.CATALOG.size()).is_greater_equal(2)
	for kind: StringName in SimCommand.CATALOG:
		assert_bool(SimCommand.is_forbidden_kind(kind)) \
			.override_failure_message("catalog kind %s creates private development (CAN-03)" % kind).is_false()


func test_municipal_command_cannot_spawn_private_building() -> void:
	for kind: StringName in [&"building.place", &"private.develop", &"spawn.house"]:
		var cmd := SimCommand.make(kind, {"parcel_ids": PackedInt64Array([1])})
		assert_str(_reason_of(cmd)).is_equal(String(CommandResult.REJECT_NOT_A_MAYOR_VERB))


func test_unknown_kind_is_rejected() -> void:
	assert_str(_reason_of(SimCommand.make(&"zoning.teleport"))).is_equal(String(CommandResult.REJECT_UNKNOWN_KIND))


func test_valid_commands_pass_shape_validation() -> void:
	assert_str(_reason_of(SimCommand.zoning_propose(PackedInt64Array([1, 2]), &"zone.mixed"))).is_empty()
	var with_optional := SimCommand.zoning_propose(PackedInt64Array([1]), &"zone.mixed")
	with_optional.params["density"] = 3
	assert_str(_reason_of(with_optional)).is_empty()
	assert_str(_reason_of(SimCommand.budget_propose({"budget.line.roads": 10, &"budget.line.parks": 0}))).is_empty()


func test_shape_violations_are_rejected_with_specific_reasons() -> void:
	var cases := [
		[SimCommand.make(&"zoning.propose", {"land_use": &"zone.mixed"}), CommandResult.REJECT_MISSING_PARAM],
		[SimCommand.make(&"zoning.propose", {"parcel_ids": [1], "land_use": &"zone.mixed"}),
			CommandResult.REJECT_BAD_PARAM_TYPE],
		[SimCommand.make(&"zoning.propose", {"parcel_ids": PackedInt64Array([1]), "land_use": "zone.mixed"}),
			CommandResult.REJECT_BAD_PARAM_TYPE],
		[SimCommand.zoning_propose(PackedInt64Array(), &"zone.mixed"), CommandResult.REJECT_INVALID_VALUE],
		[SimCommand.zoning_propose(PackedInt64Array([0]), &"zone.mixed"), CommandResult.REJECT_INVALID_VALUE],
		[SimCommand.zoning_propose(PackedInt64Array([1]), &""), CommandResult.REJECT_INVALID_VALUE],
		[SimCommand.make(&"zoning.propose", {"parcel_ids": PackedInt64Array([1]), "land_use": &"zone.mixed",
			"owner": 5}), CommandResult.REJECT_UNKNOWN_PARAM],
		[SimCommand.make(&"zoning.propose", {"parcel_ids": PackedInt64Array([1]), "land_use": &"zone.mixed",
			"density": -1}), CommandResult.REJECT_INVALID_VALUE],
		[SimCommand.budget_propose({}), CommandResult.REJECT_INVALID_VALUE],
		[SimCommand.budget_propose({&"budget.line.roads": -5}), CommandResult.REJECT_INVALID_VALUE],
		[SimCommand.budget_propose({&"budget.line.roads": 2.5}), CommandResult.REJECT_BAD_PARAM_TYPE],
	]
	for c: Array in cases:
		var cmd: SimCommand = c[0]
		assert_str(_reason_of(cmd)).override_failure_message("params %s" % [cmd.params]).is_equal(String(c[1]))


func test_rejection_names_the_offending_param() -> void:
	var problem := SimCommand.make(&"zoning.propose", {"land_use": &"zone.mixed"}).validate_shape()
	assert_dict(problem["args"]).is_equal({"param": "parcel_ids"})


func test_from_dict_coerces_json_params_to_canonical_types() -> void:
	var raw: Dictionary = JSON.parse_string(
		"{\"kind\": \"zoning.propose\", \"params\": {\"parcel_ids\": [1, 2], \"land_use\": \"zone.mixed\"," \
		+ " \"density\": 2}}")
	var cmd := SimCommand.from_dict(raw)
	assert_str(_reason_of(cmd)).is_empty()
	assert_int(typeof(cmd.params["parcel_ids"])).is_equal(TYPE_PACKED_INT64_ARRAY)
	assert_int(typeof(cmd.params["land_use"])).is_equal(TYPE_STRING_NAME)
	assert_int(typeof(cmd.params["density"])).is_equal(TYPE_INT)
	assert_bool(cmd.same_as(SimCommand.from_dict(JSON.parse_string(JSON.stringify(cmd.to_dict()))))).is_true()


func test_make_copies_params_so_caller_mutation_does_not_leak() -> void:
	var lines := {&"budget.line.roads": 10}
	var cmd := SimCommand.budget_propose(lines)
	lines[&"budget.line.roads"] = 99
	assert_int(cmd.params["lines"][&"budget.line.roads"]).is_equal(10)
