extends GdUnitTestSuite
## T-065 Aşama 1 · Yeniden iskân çalışma sayıları VERİDE (`data/sim/public_works/road_works.json`
## `expropriation.resettlement`; F05-C: ayarlanabilir, kanon DEĞİL). Kodda gömülü sayı yok; bölüm yoksa özellik
## kurulu değildir (`policy.set` `system.not_built`), bilinmeyen anahtar ve geçersiz değer yükleme hatasıdır.
## Politikanın varsayılanı veride DEĞİL: yokluk = kapalı (ADR-0009 A, sabit kural).

const BASE := {"classes": {"local": {"infra_units_per_km": 100}}}
const SECTION := {"max_fill_pm": 300, "rent_tolerance_pm": 250, "max_distance_m": 800, "partial_relief_pm": 600,
	"residual_reaction_pm": 200, "support_months": 12, "move_grant": 0}


func _cfg(section: Dictionary) -> PublicWorksConfig:
	var data := BASE.duplicate(true)
	data["expropriation"] = {"enabled": true, "resettlement": section}
	return PublicWorksConfig.from_dict(data)


func test_the_section_missing_means_the_feature_is_not_built() -> void:
	var data := BASE.duplicate(true)
	data["expropriation"] = {"enabled": true}
	var cfg := PublicWorksConfig.from_dict(data)
	assert_bool(cfg.is_valid()).is_true()
	assert_bool(cfg.resettlement.available).is_false()
	assert_bool(PublicWorksConfig.from_dict(BASE).resettlement.available).is_false()


func test_shipped_data_carries_the_working_values_of_the_spec() -> void:
	var cfg := PublicWorksConfig.load_default()
	assert_bool(cfg.is_valid()).override_failure_message(cfg.error).is_true()
	var rs := cfg.resettlement
	assert_bool(rs.available).is_true()
	assert_int(rs.max_fill_pm).is_equal(300)  # spec §4/§6 çalışma değerleri
	assert_int(rs.rent_tolerance_pm).is_equal(250)
	assert_int(rs.max_distance_m).is_equal(800)
	assert_int(rs.partial_relief_pm).is_equal(600)
	assert_int(rs.residual_reaction_pm).is_equal(200)  # D-016 §2: "biraz kalsın" (sıfır DEĞİL)
	assert_int(rs.support_months).is_equal(12)
	assert_int(rs.move_grant).is_equal(0)  # AÇIK (Q-003/T-014): sayı verilmedi, bedel yalnız kira
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PublicWorksConfig.DEFAULT_PATH))
	assert_bool((raw["expropriation"]["resettlement"] as Dictionary).has("enabled_default")).is_false()


func test_values_are_parsed() -> void:
	var section := SECTION.duplicate()
	section.merge({"max_fill_pm": 500, "residual_reaction_pm": 0, "move_grant": 40}, true)
	var cfg := _cfg(section)
	assert_bool(cfg.is_valid()).override_failure_message(cfg.error).is_true()
	assert_int(cfg.resettlement.max_fill_pm).is_equal(500)
	assert_int(cfg.resettlement.residual_reaction_pm).is_equal(0)  # 0 = eski D-014 davranışı (ayar)
	assert_int(cfg.resettlement.move_grant).is_equal(40)


func test_a_missing_key_is_an_error_because_the_data_holds_every_number_explicitly() -> void:
	var section := SECTION.duplicate()
	section.erase("max_fill_pm")
	var cfg := _cfg(section)
	assert_bool(cfg.is_valid()).is_false()
	assert_str(cfg.error).contains("resettlement.max_fill_pm")


func test_invalid_values_and_unknown_keys_are_rejected_with_a_path() -> void:
	var bad_cases: Array[Dictionary] = [{"max_fill_pm": 1001}, {"max_fill_pm": -1}, {"rent_tolerance_pm": -5},
		{"max_distance_m": -1}, {"partial_relief_pm": 1001}, {"residual_reaction_pm": 1500},
		{"support_months": -1}, {"move_grant": -1}, {"max_fill_pm": "lots"}, {"typo_key": 1},
		{"enabled_default": true}]
	for bad in bad_cases:
		var section: Dictionary = SECTION.duplicate()
		section.merge(bad, true)
		var cfg := _cfg(section)
		assert_bool(cfg.is_valid()).override_failure_message("geçerli sayıldı: %s" % str(bad)).is_false()
		assert_str(cfg.error).contains("resettlement")
	assert_bool(_cfg(SECTION).is_valid()).is_true()
	var not_a_dict := BASE.duplicate(true)
	not_a_dict["expropriation"] = {"enabled": true, "resettlement": 5}
	assert_bool(PublicWorksConfig.from_dict(not_a_dict).is_valid()).is_false()
