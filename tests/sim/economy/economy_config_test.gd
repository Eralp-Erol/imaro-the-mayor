extends SimTestBase
## T-013 ölçüt 1 · Çalışma-modeli sayıları kodda değil `data/sim/economy/economy_config.json`'da (F05-C): yükleme,
## doğrulama (anlaşılır hata), bölge geçersiz kılma ve "bölge kodu gömülü değil" denetimi.

const S := preload("res://tests/sim/economy/economy_test_support.gd")


func test_default_config_loads_and_is_valid() -> void:
	var cfg := EconomyConfig.load_default()
	assert_bool(cfg.is_valid()).override_failure_message(cfg.error).is_true()
	assert_int(cfg.investors.size()).is_greater_equal(2)
	assert_int(cfg.p("base_threshold")).is_equal(450)
	assert_int(cfg.p("review_period_days")).is_greater(0)


func test_zone_profiles_map_to_uses_and_unknown_zone_is_not_buildable() -> void:
	var cfg := S.config()
	assert_array(cfg.zone_profile(&"zone.mixed")["uses"]) \
		.is_equal([EconomyConfig.USE_RESIDENTIAL, EconomyConfig.USE_COMMERCIAL])
	assert_array(cfg.zone_profile(&"zone.green")["uses"]).is_empty()
	assert_dict(cfg.zone_profile(&"zone.does_not_exist")).is_empty()
	assert_int(int(cfg.zone_profile(&"zone.residential")["density_pm"])).is_equal(1000)


func test_every_facade_land_use_has_an_economy_zone_profile() -> void:
	# Sözlük iki dosyada ayrı tutuluyor: biri eksikse imar sessizce "yapılanmaya kapalı" olurdu.
	var facade_cfg := FacadeConfig.load_default()
	var cfg := S.config()
	for use in facade_cfg.land_uses:
		assert_bool(cfg.zone_profile(use).is_empty()) \
			.override_failure_message("economy_config.zones eksik: %s" % use) \
			.is_false()


func test_use_params_are_integers_and_positive() -> void:
	var cfg := S.config()
	for use in [EconomyConfig.USE_RESIDENTIAL, EconomyConfig.USE_COMMERCIAL]:
		for key in ["units_per_1000m2", "cost_per_unit", "rent_per_unit_month", "infra_per_unit", "plan_days",
				"construction_base_days", "construction_days_per_unit"]:
			assert_int(cfg.use_param(use, key)).override_failure_message("%d.%s" % [use, key]).is_greater(0)


func test_region_params_merge_defaults_with_overrides_by_code() -> void:
	var cfg := S.config(S.regions({"F1": {"initial_households": 7}}))
	assert_int(int(cfg.region_params(&"F1")["initial_households"])).is_equal(7)
	assert_int(int(cfg.region_params(&"F1")["infra_capacity_units"])).is_equal(1000)
	assert_int(int(cfg.region_params(&"F2")["initial_households"])).is_equal(200)


func test_no_region_code_is_embedded_in_the_default_data() -> void:
	# LANES kural 8: bölge kodu gömülmez; varsayılan geçersiz kılma tablosu boş.
	assert_dict(S.raw_config()["regions"]["overrides"]).is_empty()


func test_invalid_configs_report_which_field_is_wrong() -> void:
	var cases := {
		"zones": {"zones": {"zone.x": {"uses": ["spaceport"], "density_pm": 1000}}},
		"fractional": {"decision": {"base_threshold": 450.5}},
		"negative weight": {"decision": {"w_demand": -1}},
		"no investors": {"investors": {"list": []}},
		"bad capital": {"investors": {"list": [{"capital": 0, "threshold_shift": 0}]}},
		"unknown override field": {"regions": {"overrides": {"F1": {"warp_speed": 9}}}},
		"missing section": {"land": null},
		"bad use param": {"uses": {"residential": {"cost_per_unit": 0}}},
	}
	for label: String in cases:
		var raw := S.merge(S.raw_config(), cases[label])
		if raw.get("land", 1) == null:
			raw.erase("land")
		var cfg := EconomyConfig.from_dict(raw)
		assert_bool(cfg.is_valid()).override_failure_message("%s: geçersiz yapılandırma kabul edildi" % label).is_false()
		assert_str(cfg.error).override_failure_message("%s: hata metni boş" % label).is_not_empty()


func test_underscore_keys_are_documentation_and_ignored() -> void:
	var raw := S.merge(S.raw_config(), {"decision": {"_extra_note": "x"}, "_header2": "y"})
	assert_bool(EconomyConfig.from_dict(raw).is_valid()).is_true()


func test_broken_json_text_is_reported_not_thrown() -> void:
	var cfg := EconomyConfig.from_json_text("{ not json")
	assert_bool(cfg.is_valid()).is_false()
	assert_str(cfg.error).contains("JSON")
	assert_bool(EconomyConfig.load_file("res://data/sim/economy/yok.json").is_valid()).is_false()
