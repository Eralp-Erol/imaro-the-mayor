extends GdUnitTestSuite
## T-050 · Yaşam görünümü ayarları: `data/view/life.json` geçerli, profiller veri (ADR-0004), geçersiz dosya reddedilir.
## Sayılar ÇALIŞMA DEĞERİdir (kanon değil); bu test yalnız şema ve güvenli aralıkları sınar.


func test_default_config_is_valid_for_both_profiles() -> void:
	for profile: StringName in [&"desktop", &"touch"]:
		var cfg := LifeConfig.load_default(profile)
		assert_array(Array(cfg.errors)).override_failure_message("%s: %s" % [profile, "; ".join(cfg.errors)]).is_empty()
		assert_bool(cfg.valid()).is_true()


func test_touch_profile_is_sparser_and_shorter_ranged_than_desktop() -> void:
	var d := LifeConfig.load_default(&"desktop")
	var t := LifeConfig.load_default(&"touch")
	assert_float(t.density()).is_less(d.density())
	assert_float(t.profile_value("car_range_m")).is_less(d.profile_value("car_range_m"))
	assert_float(t.profile_value("max_cars")).is_less(d.profile_value("max_cars"))
	assert_float(t.profile_value("max_people")).is_less(d.profile_value("max_people"))


func test_profile_for_maps_only_touch_to_touch() -> void:
	assert_str(String(LifeConfig.profile_for(&"touch"))).is_equal("touch")
	assert_str(String(LifeConfig.profile_for(&"desktop"))).is_equal("desktop")
	assert_str(String(LifeConfig.profile_for(&"anything"))).is_equal("desktop")


func test_field_roads_carry_no_life() -> void:
	var row := LifeConfig.load_default().class_row(&"field")
	assert_float(float(row["cars_cap_per_100m"])).is_equal(0.0)
	assert_float(float(row["people_cap_per_100m"])).is_equal(0.0)


func test_unknown_class_has_no_row() -> void:
	assert_bool(LifeConfig.load_default().class_row(&"rail").is_empty()).is_true()


func test_density_caps_are_overflow_guards_not_targets() -> void:
	# Tavan yalnız taşma emniyeti: yoğunluk tavanları makul (sokakta 100 m'de en çok ~12 araç/yaya).
	var cfg := LifeConfig.load_default()
	for cls in ["arterial", "collector", "local"]:
		var row := cfg.class_row(StringName(cls))
		assert_float(float(row["cars_cap_per_100m"])).is_between(1.0, 20.0)
		assert_float(float(row["people_cap_per_100m"])).is_between(1.0, 20.0)


func test_missing_file_is_invalid_not_a_crash() -> void:
	var cfg := LifeConfig.load_path("res://data/view/yok_life.json")
	assert_bool(cfg.valid()).is_false()


func test_bad_values_are_rejected() -> void:
	var raw := JSON.parse_string(FileAccess.get_file_as_string(LifeConfig.PATH)) as Dictionary
	var cases := {
		"spill_share": func(d: Dictionary) -> void: d["spill_share"] = 1.5,
		"negatif ağırlık": func(d: Dictionary) -> void: d["weights"]["res"] = -1.0,
		"sınıf anahtarı eksik": func(d: Dictionary) -> void: (d["classes"]["local"] as Dictionary).erase("cars_cap_per_100m"),
		"hız sıfır": func(d: Dictionary) -> void: d["movement"]["car_speed_mps"] = 0.0,
		"profil eksik": func(d: Dictionary) -> void: (d["profiles"] as Dictionary).erase("desktop"),
		"şema": func(d: Dictionary) -> void: d["schema_version"] = 99,
	}
	for label in cases:
		var data := raw.duplicate(true)
		(cases[label] as Callable).call(data)
		var path := "user://life_bad_%d.json" % absi(String(label).hash())
		var fh := FileAccess.open(path, FileAccess.WRITE)
		fh.store_string(JSON.stringify(data))
		fh.close()
		var cfg := LifeConfig.load_path(path)
		assert_bool(cfg.valid()).override_failure_message("%s kabul edildi" % label).is_false()
		DirAccess.remove_absolute(path)
