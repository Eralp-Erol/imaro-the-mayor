extends GdUnitTestSuite
## T-042 adım 2 · Yol işi veri dosyası (`data/sim/public_works/road_works.json`): ÇALIŞMA MODELİ sayıları veride,
## açıklanabilir formül (uzunluk x sınıf katsayısı), geçersiz veri reddi, maliyet "henüz kurulmadı" (T-014, Q-003).


func test_default_config_is_valid_and_marked_as_a_working_model() -> void:
	var cfg := PublicWorksConfig.load_default()
	assert_bool(cfg.is_valid()).override_failure_message(cfg.error).is_true()
	assert_bool(cfg.has_class(&"local")).is_true()
	assert_bool(cfg.has_class(&"arterial")).is_false()
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PublicWorksConfig.DEFAULT_PATH))
	assert_str(str(raw.get("_header", "")).to_lower()).contains("calisma modeli")


func test_infra_units_follow_length_times_the_class_coefficient() -> void:
	var cfg := PublicWorksConfig.from_dict({"classes": {"local": {"infra_units_per_km": 100}}})
	assert_int(cfg.infra_units(&"local", 100000)).is_equal(100)  # 1 km
	assert_int(cfg.infra_units(&"local", 10000)).is_equal(10)  # 100 m
	assert_int(cfg.infra_units(&"local", 999)).is_equal(0)  # sıfıra doğru kesme
	assert_int(cfg.infra_units(&"arterial", 10000)).is_equal(0)  # veri yok -> etki yok


func test_cost_is_not_built_and_carries_no_money() -> void:
	var cfg := PublicWorksConfig.load_default()
	assert_bool(cfg.cost_available).is_false()
	assert_str(String(cfg.cost_reason_key)).is_equal("public_work.cost.not_built")


func test_invalid_data_is_rejected_with_a_message() -> void:
	for bad: Dictionary in [{}, {"classes": {}}, {"classes": {"local": {}}},
			{"classes": {"local": {"infra_units_per_km": -1}}}, {"classes": {"local": {"infra_units_per_km": 1.5}}}]:
		var cfg := PublicWorksConfig.from_dict(bad)
		assert_bool(cfg.is_valid()).override_failure_message(str(bad)).is_false()
		assert_str(cfg.error).is_not_empty()
