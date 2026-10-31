extends GdUnitTestSuite
## T-042b adım 2 (sim) · Kamulaştırma veri bayrakları (`data/sim/public_works/road_works.json` `expropriation`): hepsi
## ÇALIŞMA MODELİ (F05-C; Q-017 ayrıntı parametreleri açık, kanon DEĞİL). Kodda gömülü sayı yok; bilinmeyen anahtar ve
## geçersiz değer yükleme hatasıdır; bölüm yoksa kamulaştırma KAPALI (eski veri/yapılandırmalar bit-eşit çalışır).

const BASE := {"classes": {"local": {"infra_units_per_km": 100}}}


func _with(section: Dictionary) -> Dictionary:
	var out := BASE.duplicate(true)
	out["expropriation"] = section
	return out


func test_section_missing_means_expropriation_is_off() -> void:
	var cfg := PublicWorksConfig.from_dict(BASE)
	assert_bool(cfg.is_valid()).is_true()
	assert_bool(cfg.expropriation_enabled).is_false()


func test_shipped_data_enables_the_d011_first_version_with_working_values() -> void:
	var cfg := PublicWorksConfig.load_default()
	assert_bool(cfg.is_valid()).override_failure_message(cfg.error).is_true()
	assert_bool(cfg.expropriation_enabled).is_true()  # D-011: bina yıkılır
	assert_bool(cfg.protect_heritage).is_true()  # D-011: tarihî yapılar korunur
	assert_str(String(cfg.household_fate)).is_equal("return_to_latent")  # Q-017 ayrıntısı: ÇM, kanon değil
	assert_int(cfg.proximity_radius_m).is_greater(0)  # D-011: yakındakiler de tepki verir (mesafeye bağlı)
	assert_bool(cfg.cost_available).is_false()  # bedel yalnız gösterge
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PublicWorksConfig.DEFAULT_PATH))
	assert_str(JSON.stringify(raw["expropriation"]).to_lower()).contains("q-017")  # açık sorular veride işaretli


func test_values_are_parsed_and_defaults_are_conservative() -> void:
	var cfg := PublicWorksConfig.from_dict(_with({"enabled": true}))
	assert_bool(cfg.is_valid()).override_failure_message(cfg.error).is_true()
	assert_bool(cfg.protect_heritage).is_true()  # varsayılan muhafazakâr
	assert_str(String(cfg.household_fate)).is_equal("return_to_latent")
	var custom := PublicWorksConfig.from_dict(_with({"enabled": true, "protect_heritage": false,
		"household_fate": "leave_region", "proximity_radius_m": 80, "reaction_keep_days": 100}))
	assert_bool(custom.protect_heritage).is_false()
	assert_str(String(custom.household_fate)).is_equal("leave_region")
	assert_int(custom.proximity_radius_m).is_equal(80)
	assert_int(custom.reaction_keep_days).is_equal(100)


func test_invalid_values_and_unknown_keys_are_rejected() -> void:
	for bad: Dictionary in [{"enabled": "yes"}, {"enabled": true, "household_fate": "rehouse_queue"},
			{"enabled": true, "proximity_radius_m": -1}, {"enabled": true, "reaction_keep_days": 0},
			{"enabled": true, "typo_key": 1}, {"enabled": true, "protect_heritage": 1}]:
		var cfg := PublicWorksConfig.from_dict(_with(bad))
		assert_bool(cfg.is_valid()).override_failure_message(str(bad)).is_false()
		assert_str(cfg.error).is_not_empty()
