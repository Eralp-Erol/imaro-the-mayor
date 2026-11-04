extends SimTestBase
## T-013 ölçüt 4 · Yatırımcı karar fonksiyonu (SIM-02) saf birim testleri: etkenler 1000 ölçekli tamsayı, doğrusal
## puan, eşik, engel etkenleri (altyapı/finansman/imar), sonuç kodu. Sistem düzeyi (record_reason, olay) ayrı dosyada.

const S := preload("res://tests/sim/economy/economy_test_support.gd")


## Güçlü örnek koşul (elle hesaplı): 10 birim konut, arsa 1000, sermaye 80000, altyapı 1000/100, talep 750, kira x1.1.
func _inputs(patch: Dictionary = {}) -> Dictionary:
	var base := {
		"use": EconomyConfig.USE_RESIDENTIAL, "zone_ok": true, "units": 10, "land_value": 1000, "capital": 80000,
		"infra_cap": 1000, "infra_load": 100, "demand_after_pm": 750, "rent_mult_pm": 1100, "sentiment": 0,
		"threshold_shift": 0,
	}
	base.merge(patch, true)
	return base


func _factor(result: Dictionary, name: StringName) -> Dictionary:
	for f: Dictionary in result["factors"]:
		if f["name"] == name:
			return f
	return {}


func test_strong_case_has_hand_computed_factors_and_is_positive() -> void:
	var cfg := S.config()
	var r := InvestorDecision.decide(cfg, _inputs())
	assert_int(_factor(r, &"reason.factor.demand")["value"]).is_equal(500)
	assert_int(_factor(r, &"reason.factor.expected_return")["value"]).is_equal(373)
	assert_int(_factor(r, &"reason.factor.construction_cost")["value"]).is_equal(-220)
	assert_int(_factor(r, &"reason.factor.infrastructure_capacity")["value"]).is_equal(150)
	assert_int(_factor(r, &"reason.factor.financing")["value"]).is_equal(100)
	assert_int(_factor(r, &"reason.factor.zoning_fit")["value"]).is_equal(0)
	assert_int(_factor(r, &"reason.factor.market_sentiment")["value"]).is_equal(0)
	assert_int(r["outlay"]).is_equal(11000)
	assert_int(r["score"]).is_equal(539)
	assert_int(r["threshold"]).is_equal(450)
	assert_bool(r["positive"]).is_true()
	assert_int(r["code"]).is_equal(EconomyState.CODE_APPROVED)


func test_factor_weights_come_from_config_and_all_values_are_integers() -> void:
	var cfg := S.config()
	var r := InvestorDecision.decide(cfg, _inputs())
	assert_int(_factor(r, &"reason.factor.demand")["weight"]).is_equal(cfg.p("w_demand"))
	assert_int(_factor(r, &"reason.factor.infrastructure_capacity")["weight"]).is_equal(cfg.p("w_infrastructure"))
	assert_bool(_factor(r, &"reason.factor.expected_return")["is_estimate"]) \
		.override_failure_message("getiri tahmindir") \
		.is_true()
	assert_bool(_factor(r, &"reason.factor.market_sentiment")["is_estimate"]).is_true()
	for f: Dictionary in r["factors"]:
		assert_int(typeof(f["value"])).is_equal(TYPE_INT)
		assert_int(typeof(f["weight"])).is_equal(TYPE_INT)
	assert_int(typeof(r["score"])).is_equal(TYPE_INT)


func test_score_and_outcome_match_what_the_reason_log_computes() -> void:
	# ReasonRecord değişmezi: score = Σ contribution; olumlu <=> score >= eşik. Karar fonksiyonu log ile çelişemez.
	var cfg := S.config()
	for patch in [{}, {"demand_after_pm": 300}, {"capital": 100}, {"sentiment": -400}, {"units": 700}]:
		var r := InvestorDecision.decide(cfg, _inputs(patch))
		var state := new_state()
		var id := state.record_reason(&"actor.investor.1", &"decision.investor.develop", r["factors"], r["threshold"])
		var rec := state.reasons.by_id(id)
		assert_int(rec["score"]).override_failure_message(str(patch)).is_equal(r["score"])
		assert_bool(rec["outcome"] == ReasonLog.OUTCOME_POSITIVE).override_failure_message(str(patch)).is_equal(r["positive"])


func test_infrastructure_exhaustion_alone_vetoes_an_otherwise_perfect_project() -> void:
	var cfg := S.config()
	var r := InvestorDecision.decide(cfg, _inputs({"demand_after_pm": 1000, "rent_mult_pm": 1400, "infra_load": 995}))
	assert_int(_factor(r, &"reason.factor.infrastructure_capacity")["value"]).is_equal(-1000)
	assert_bool(r["positive"]).is_false()
	assert_int(r["code"]).is_equal(EconomyState.CODE_INFRASTRUCTURE)


func test_insufficient_capital_alone_vetoes() -> void:
	var cfg := S.config()
	var r := InvestorDecision.decide(cfg, _inputs({"demand_after_pm": 1000, "rent_mult_pm": 1400, "capital": 10999}))
	assert_int(_factor(r, &"reason.factor.financing")["value"]).is_equal(-1000)
	assert_bool(r["positive"]).is_false()
	assert_int(r["code"]).is_equal(EconomyState.CODE_FINANCING)
	var exact := InvestorDecision.decide(cfg, _inputs({"capital": 11000}))
	assert_int(_factor(exact, &"reason.factor.financing")["value"]) \
		.override_failure_message("sermaye = bedel: engel yok") \
		.is_equal(0)


func test_zoning_that_forbids_the_use_alone_vetoes() -> void:
	var cfg := S.config()
	var r := InvestorDecision.decide(cfg, _inputs({"zone_ok": false, "demand_after_pm": 1000, "rent_mult_pm": 1400}))
	assert_int(_factor(r, &"reason.factor.zoning_fit")["value"]).is_equal(-1000)
	assert_bool(r["positive"]).is_false()
	assert_int(r["code"]).is_equal(EconomyState.CODE_ZONING)
	var zero_units := InvestorDecision.decide(cfg, _inputs({"units": 0}))
	assert_int(zero_units["code"]).override_failure_message("0 birim = yapılamaz").is_equal(EconomyState.CODE_ZONING)


func test_gate_priority_is_zoning_then_infrastructure_then_financing() -> void:
	var cfg := S.config()
	var all_bad := _inputs({"zone_ok": false, "infra_load": 1000, "capital": 1})
	assert_int(InvestorDecision.decide(cfg, all_bad)["code"]).is_equal(EconomyState.CODE_ZONING)
	all_bad["zone_ok"] = true
	assert_int(InvestorDecision.decide(cfg, all_bad)["code"]).is_equal(EconomyState.CODE_INFRASTRUCTURE)
	all_bad["infra_load"] = 100
	assert_int(InvestorDecision.decide(cfg, all_bad)["code"]).is_equal(EconomyState.CODE_FINANCING)


func test_low_demand_is_reported_as_demand_too_low() -> void:
	var r := InvestorDecision.decide(S.config(), _inputs({"demand_after_pm": 150}))
	assert_bool(r["positive"]).is_false()
	assert_int(r["code"]).is_equal(EconomyState.CODE_DEMAND)
	assert_int(_factor(r, &"reason.factor.demand")["value"]).is_equal(-700)


func test_weak_return_with_decent_demand_is_reported_as_return_too_low() -> void:
	# Pahalı arsa getiriyi eritir; talep etkeni hâlâ olumlu.
	var r := InvestorDecision.decide(S.config(), _inputs({"demand_after_pm": 620, "land_value": 9000}))
	assert_bool(r["positive"]).is_false()
	assert_int(r["code"]).is_equal(EconomyState.CODE_RETURN)
	assert_int(_factor(r, &"reason.factor.demand")["value"]).is_greater(0)


func test_land_price_lowers_the_expected_return() -> void:
	var cfg := S.config()
	var cheap := _factor(InvestorDecision.decide(cfg, _inputs({"land_value": 1000})), &"reason.factor.expected_return")
	var dear := _factor(InvestorDecision.decide(cfg, _inputs({"land_value": 6000})), &"reason.factor.expected_return")
	assert_int(dear["value"]).is_less(cheap["value"])


func test_interest_rate_lowers_the_expected_return() -> void:
	var low := InvestorDecision.decide(S.config({"decision": {"interest_pm": 0}}), _inputs())
	var high := InvestorDecision.decide(S.config({"decision": {"interest_pm": 100}}), _inputs())
	assert_int(_factor(high, &"reason.factor.expected_return")["value"]) \
		.is_less(_factor(low, &"reason.factor.expected_return")["value"])


func test_threshold_shift_models_investor_risk_appetite() -> void:
	var cfg := S.config()
	var border := _inputs({"demand_after_pm": 560})
	var neutral := InvestorDecision.decide(cfg, border)
	assert_bool(neutral["positive"]) \
		.override_failure_message("sınır durumu olumsuz kurulmalı: %d" % neutral["score"]) \
		.is_false()
	var eager := InvestorDecision.decide(cfg, _inputs({"demand_after_pm": 560, "threshold_shift": -150}))
	assert_int(eager["threshold"]).is_equal(300)
	assert_bool(eager["positive"]).is_true()


func test_sentiment_noise_moves_the_score_by_its_weighted_value_only() -> void:
	var cfg := S.config()
	var base := InvestorDecision.decide(cfg, _inputs())
	var noisy := InvestorDecision.decide(cfg, _inputs({"sentiment": 400}))
	assert_int(noisy["score"] - base["score"]).is_equal(400 * cfg.p("w_sentiment") / 1000)


func test_decision_is_pure_same_inputs_same_output() -> void:
	var cfg := S.config()
	assert_dict(InvestorDecision.decide(cfg, _inputs())).is_equal(InvestorDecision.decide(cfg, _inputs()))


func test_gate_veto_holds_for_the_default_weights_against_the_best_possible_other_factors() -> void:
	# Engel etkeni (-1000 x 1000) diğer etkenlerin azami katkısını aşmalı; ağırlıklar değişirse bu test uyarır.
	var cfg := S.config()
	var best_other := cfg.p("w_demand") + cfg.p("w_expected_return") \
		+ cfg.p("sentiment_range") * cfg.p("w_sentiment") / 1000 \
		+ cfg.p("infra_bonus_max") + cfg.p("financing_bonus_max")
	var lowest_threshold := cfg.p("base_threshold")
	for entry in cfg.investors:
		lowest_threshold = mini(lowest_threshold, cfg.p("base_threshold") + int(entry["threshold_shift"]))
	assert_int(best_other - 1000).override_failure_message("engel etkeni vetoyu garanti etmiyor").is_less(lowest_threshold)
