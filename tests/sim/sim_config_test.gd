extends SimTestBase
## T-002 · SimConfig: çalışma-modeli sayıları kodda değil veride (F05-C); geçersiz veri anlaşılır hatayla reddedilir.


func _good() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(SimConfig.DEFAULT_PATH))


func test_default_config_loads_with_integer_calendar_and_speeds() -> void:
	var cfg := SimConfig.load_default()
	assert_bool(cfg.is_valid()).override_failure_message(cfg.error).is_true()
	for key: String in ["days_per_month", "months_per_quarter", "reason_log_capacity", "command_log_capacity"]:
		assert_int(typeof(cfg.sim[key])).override_failure_message("%s int olmalı" % key).is_equal(TYPE_INT)
		assert_int(cfg.sim[key]).is_greater(0)
	assert_bool(cfg.driver["speeds"].has(cfg.driver["default_speed"])).is_true()
	assert_int(cfg.driver["speeds"]["paused"]).is_equal(0)
	assert_int(typeof(cfg.driver["max_ticks_per_advance"])).is_equal(TYPE_INT)


func test_json_integral_floats_are_coerced_to_int() -> void:
	# JSON sayıları float döner; yapılandırma bunları int'e çevirmeli (kayıt biçimine float sızmasın).
	var raw := _good()
	assert_int(typeof(raw["sim"]["days_per_month"])).is_equal(TYPE_FLOAT)
	var cfg := SimConfig.from_dict(raw)
	assert_int(typeof(cfg.sim["days_per_month"])).is_equal(TYPE_INT)
	assert_int(typeof(cfg.driver["speeds"]["fast"])).is_equal(TYPE_INT)


func test_missing_key_is_rejected_with_message() -> void:
	var raw := _good()
	raw["sim"].erase("days_per_month")
	var cfg := SimConfig.from_dict(raw)
	assert_bool(cfg.is_valid()).is_false()
	assert_str(cfg.error).contains("days_per_month")


func test_non_integral_and_non_positive_values_are_rejected() -> void:
	var raw := _good()
	raw["sim"]["days_per_month"] = 30.5
	assert_bool(SimConfig.from_dict(raw).is_valid()).is_false()
	raw = _good()
	raw["sim"]["months_per_quarter"] = 0
	assert_bool(SimConfig.from_dict(raw).is_valid()).is_false()
	raw = _good()
	raw["driver"]["speeds"]["fast"] = -1
	assert_bool(SimConfig.from_dict(raw).is_valid()).is_false()


func test_unknown_default_speed_and_bad_json_are_rejected() -> void:
	var raw := _good()
	raw["driver"]["default_speed"] = "ludicrous"
	var cfg := SimConfig.from_dict(raw)
	assert_bool(cfg.is_valid()).is_false()
	assert_str(cfg.error).contains("default_speed")
	assert_bool(SimConfig.from_json_text("{not json").is_valid()).is_false()
	assert_bool(SimConfig.from_json_text("[1,2]").is_valid()).is_false()
