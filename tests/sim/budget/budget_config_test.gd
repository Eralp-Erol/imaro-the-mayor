extends GdUnitTestSuite
## T-043C · Bütçe yapılandırması (F05-C: sayılar veridir, kanon değil) ve Q-003 (para birimi adı/simgesi sabit yok).

const B := preload("res://tests/sim/budget/budget_support.gd")


func test_default_config_is_valid_integer_data() -> void:
	var cfg := BudgetConfig.load_default()
	assert_str(cfg.error).is_empty()
	assert_bool(cfg.is_valid()).is_true()
	assert_int(cfg.tax_rate_pm).is_between(0, 1000)
	assert_int(cfg.public_cost_share_pm).is_between(0, 1000)
	assert_bool(EconomyState.use_id(cfg.road_cost_use) != EconomyConfig.USE_NONE).is_true()
	assert_int(cfg.ledger_max).is_greater(0)


func test_invalid_configs_are_rejected_with_a_reason() -> void:
	var cases := {
		"tax over 1000": {"tax": {"tax_rate_pm": 1001}},
		"negative tax": {"tax": {"tax_rate_pm": -1}},
		"fractional share": {"road": {"public_cost_share_pm": 12.5}},
		"share over 1000": {"road": {"public_cost_share_pm": 1001}},
		"string balance": {"initial_balance": "50000"},
		"zero ledger": {"ledger": {"max_entries": 0}},
		"unknown key": {"tax": {"tax_rate_per_mille": 100}},
		"unknown section": {"currency": {"symbol": "X"}},
	}
	for label: String in cases:
		var cfg := BudgetConfig.from_dict(EconomyTestSupport.merge(B.raw_config(), cases[label]))
		assert_bool(cfg.is_valid()).override_failure_message("kabul edilmemeli: " + label).is_false()
		assert_str(cfg.error).override_failure_message(label).is_not_empty()


func test_cost_use_must_exist_in_the_economy_config() -> void:
	var cfg := B.config({"road": {"cost_use": "industrial"}})
	assert_str(BudgetSystem.setup_problem(cfg, EconomyConfig.load_default())).is_not_empty()
	assert_str(BudgetSystem.setup_problem(B.config(), EconomyConfig.load_default())).is_empty()


func test_no_currency_name_or_symbol_is_hardcoded_in_budget_data_or_code() -> void:
	var text := FileAccess.get_file_as_string(B.CONFIG_PATH).to_lower()
	for needle in ["currency", "symbol", "₺", "¤", "$", "€", "lira", " tl"]:
		assert_bool(text.contains(needle)).override_failure_message("sabit para birimi izi: " + needle).is_false()
	for path in ["res://src/sim/budget/budget_config.gd", "res://src/sim/budget/budget_state.gd",
			"res://src/sim/budget/budget_system.gd"]:
		var code := FileAccess.get_file_as_string(path)
		for needle in ["₺", "¤", "€", "\"TL\""]:
			assert_bool(code.contains(needle)).override_failure_message("%s: %s" % [path, needle]).is_false()
