extends SimTestBase
## T-027 · FacadeConfig: facade'ın çalışma-modeli sayıları/sözlükleri kodda değil veride (F05-C); geçersiz veri
## anlaşılır hatayla reddedilir.


func _good() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(FacadeConfig.DEFAULT_PATH))


func test_default_config_loads_with_int_values() -> void:
	var cfg := FacadeConfig.load_default()
	assert_bool(cfg.is_valid()).override_failure_message(cfg.error).is_true()
	assert_str(String(cfg.speed_levels[0])).is_equal("paused")
	assert_int(cfg.speed_levels.size()).is_equal(SimFacade.SPEED_FASTEST + 1)
	assert_int(typeof(cfg.apply_delay_days)).is_equal(TYPE_INT)
	assert_int(cfg.apply_delay_days).is_greater_equal(1)
	assert_int(typeof(cfg.parcel_reason_limit)).is_equal(TYPE_INT)
	assert_array(cfg.land_uses).is_not_empty()
	assert_bool(cfg.is_land_use(&"zone.mixed")).is_true()
	assert_bool(cfg.is_land_use(&"zone.casino")).is_false()


func test_speed_level_names_follow_the_driver_speed_table() -> void:
	var cfg := FacadeConfig.load_default()
	var sim_cfg := new_config()
	for level_name in cfg.speed_levels:
		assert_bool(sim_cfg.driver["speeds"].has(String(level_name))) \
			.override_failure_message("hız adı sürücü tablosunda yok: %s" % level_name).is_true()


func test_invalid_values_are_rejected_with_message() -> void:
	var cases := {
		"speed_levels": func(raw: Dictionary) -> void: raw["facade"]["speed_levels"] = ["normal", "fast"],
		"speed_levels ": func(raw: Dictionary) -> void: raw["facade"]["speed_levels"] = [],
		"parcel_reason_limit": func(raw: Dictionary) -> void: raw["facade"]["parcel_reason_limit"] = 0,
		"land_uses": func(raw: Dictionary) -> void: raw["zoning"]["land_uses"] = [],
		"land_uses ": func(raw: Dictionary) -> void: raw["zoning"]["land_uses"] = ["zone.a", "zone.a"],
		"apply_delay_days": func(raw: Dictionary) -> void: raw["zoning"]["apply_delay_days"] = 0,
		"apply_delay_days ": func(raw: Dictionary) -> void: raw["zoning"]["apply_delay_days"] = 2.5,
		"zoning": func(raw: Dictionary) -> void: raw.erase("zoning"),
	}
	for label: String in cases:
		var raw := _good()
		cases[label].call(raw)
		var cfg := FacadeConfig.from_dict(raw)
		assert_bool(cfg.is_valid()).override_failure_message("kabul edildi: %s" % label).is_false()
		assert_str(cfg.error).contains(label.strip_edges())


func test_bad_json_is_rejected() -> void:
	assert_bool(FacadeConfig.from_json_text("{oops").is_valid()).is_false()
	assert_bool(FacadeConfig.from_json_text("[1]").is_valid()).is_false()
