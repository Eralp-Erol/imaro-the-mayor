extends GdUnitTestSuite
## T-021 ölçüt 1/3/6 · ReasonModel (saf mantık): kayıt -> satırlar (katkı, yön, çubuk), marj, UI'da yeniden
## hesaplanan DEĞİŞMEZ (skor = Σ katkı, sonuç = eşik karşılaştırması) ve tutarsız kaydın işaretlenmesi.
## Olumsuz varyantlar: tutarlı kayıt işaretlenmez; her ihlal türü ayrı yakalanır; sınır (skor == eşik) doğru
## tarafta; v1.1 alanları yokken zarifçe düşer, varken kullanılır.

const SCENARIOS := [
	"mock_scenario_investment_declined", "mock_scenario_investment_positive", "mock_scenario_group_reactions",
	"mock_scenario_council_budget_vote",
]


func before_test() -> void:
	UiText.reset()
	UiText.report_missing = false


func after_test() -> void:
	UiText.reset()


static func record(threshold: int, factors: Array[ReasonFactor]) -> ReasonRecord:
	var r := ReasonRecord.new()
	r.id = 1
	r.threshold = threshold
	r.factors = factors
	return r.finalize()


static func factor(key: StringName, value: int, weight: int, estimate: bool = false) -> ReasonFactor:
	var f := ReasonFactor.make(key, value, weight)
	f.is_estimate = estimate
	return f


func test_rows_are_sorted_by_absolute_contribution_with_direction_and_bar() -> void:
	var r := record(500, [factor(&"a", 100, 200), factor(&"b", -600, 500), factor(&"c", 400, 500)])
	var m := ReasonModel.from_record(r)
	assert_array(m.rows.map(func(x: ReasonModel.Row) -> StringName: return x.name_key)).is_equal([&"b", &"c", &"a"])
	assert_int(m.rows[0].direction).is_equal(ReasonModel.DIR_AGAINST)
	assert_int(m.rows[1].direction).is_equal(ReasonModel.DIR_FOR)
	assert_float(m.rows[0].bar_fraction).is_equal(-1.0)  # en büyük |katkı| tam uzunluk, sola (aleyhte)
	assert_float(m.rows[1].bar_fraction).is_equal_approx(200.0 / 300.0, 0.001)
	assert_int(m.rows[0].contribution).is_equal(-300)
	assert_bool(m.is_consistent()).is_true()


func test_zero_weight_factor_is_info_only_and_sorted_last() -> void:
	var r := record(0, [factor(&"info", 900, 0), factor(&"real", 100, 1000)])
	var m := ReasonModel.from_record(r)
	assert_bool(m.rows[1].is_info_only).is_true()
	assert_float(m.rows[1].bar_fraction).is_equal(0.0)
	assert_int(m.rows[1].direction).is_equal(ReasonModel.DIR_NEUTRAL)
	assert_bool(m.top_names.has(&"info")).is_false()  # bilgi-yalnız etken özet cümlesine girmez


func test_tiny_nonzero_factor_keeps_a_visible_sliver() -> void:
	var r := record(0, [factor(&"big", 1000, 1000), factor(&"tiny", 1, 100)])  # katkı 0'a kesilir, yön lehte
	var m := ReasonModel.from_record(r)
	var tiny: ReasonModel.Row = m.rows[1]
	assert_int(tiny.contribution).is_equal(0)
	assert_int(tiny.direction).is_equal(ReasonModel.DIR_FOR)
	assert_float(tiny.bar_fraction).is_greater(0.0)


func test_margin_is_recorded_score_minus_threshold() -> void:
	var m := ReasonModel.from_record(record(500, [factor(&"a", 300, 1000)]))
	assert_int(m.margin).is_equal(-200)
	assert_int(ReasonModel.from_record(record(100, [factor(&"a", 300, 1000)])).margin).is_equal(200)


func test_every_mock_scenario_record_is_consistent_negative_control() -> void:
	# Olumsuz kontrol: sim'in/mock'un ürettiği tutarlı kayıtlar ASLA işaretlenmez.
	var checked := 0
	for scenario in SCENARIOS:
		var f := UiTestSupport.played(scenario)
		for id in UiTestSupport.all_reason_ids(f):
			var m := ReasonModel.from_record(f.reason(id))
			assert_array(m.issues).override_failure_message("%s #%d işaretlendi" % [scenario, id]).is_empty()
			checked += 1
	assert_int(checked).is_greater_equal(6)


func test_score_mismatch_is_flagged_with_both_numbers() -> void:
	var r := record(500, [factor(&"a", 300, 1000)])
	r.score += 150
	var m := ReasonModel.from_record(r)
	assert_bool(m.has_issue(ReasonModel.ISSUE_SCORE)).is_true()
	var args: Dictionary = m.issues[0]["args"]
	assert_int(args["recorded"]).is_equal(450)
	assert_int(args["computed"]).is_equal(300)


func test_outcome_contradicting_threshold_is_flagged() -> void:
	var r := record(500, [factor(&"a", 300, 1000)])  # skor 300 < 500 -> negative
	r.outcome = ReasonRecord.OUTCOME_POSITIVE
	assert_bool(ReasonModel.from_record(r).has_issue(ReasonModel.ISSUE_OUTCOME)).is_true()


func test_boundary_score_equal_to_threshold_means_positive() -> void:
	var r := record(300, [factor(&"a", 300, 1000)])
	assert_int(r.score).is_equal(r.threshold)
	assert_bool(ReasonModel.from_record(r).is_consistent()).is_true()
	r.outcome = ReasonRecord.OUTCOME_NEGATIVE  # tam eşikte negatif yazılmışsa tutarsız
	assert_bool(ReasonModel.from_record(r).has_issue(ReasonModel.ISSUE_OUTCOME)).is_true()


func test_unknown_outcome_and_unsupported_scoring_are_flagged_not_silently_accepted() -> void:
	var r := record(0, [factor(&"a", 100, 1000)])
	r.outcome = &"maybe"
	assert_bool(ReasonModel.from_record(r).has_issue(ReasonModel.ISSUE_UNKNOWN_OUTCOME)).is_true()
	var r2 := record(0, [factor(&"a", 100, 1000)])
	r2.scoring = &"quadratic"
	assert_bool(ReasonModel.from_record(r2).has_issue(ReasonModel.ISSUE_SCORING)).is_true()


func test_record_listing_itself_as_parent_is_flagged() -> void:
	var r := record(0, [factor(&"a", 100, 1000)])
	r.parent_ids = PackedInt64Array([r.id])
	assert_bool(ReasonModel.from_record(r).has_issue(ReasonModel.ISSUE_CHAIN)).is_true()


func test_truncation_toward_zero_matches_contract() -> void:
	# (-1 * 500) / 1000 = 0 (sıfıra kesme); (-1500 * 1000) / 1000 = -1500. UI sözleşme formülünü kullanır.
	var m := ReasonModel.from_record(record(0, [factor(&"a", -1, 500), factor(&"b", -1500, 1000)]))
	assert_int(m.computed_score).is_equal(-1500)
	assert_bool(m.is_consistent()).is_true()


func test_extension_fields_are_used_when_present() -> void:
	var r := ReasonTestSupport.ExtRecord.new()
	r.id = 5
	r.threshold = 0
	var f := ReasonTestSupport.ExtFactor.new()
	f.name_key = &"a"
	f.value = 400
	f.weight = 500
	f.direction = 1
	f.trend = -1
	r.factors = [f]
	r.finalize()
	var m := ReasonModel.from_record(r)
	assert_that(m.summary_key).is_equal(&"decision.investor.develop.negative")
	assert_array(Array(m.cause_refs)).is_equal(["parcel.7"])
	assert_bool(m.rows[0].has_trend).is_true()
	assert_int(m.rows[0].trend).is_equal(-1)
	assert_bool(m.is_consistent()).is_true()


func test_explicit_direction_contradicting_value_times_weight_is_flagged() -> void:
	var r := ReasonTestSupport.ExtRecord.new()
	r.id = 5
	var f := ReasonTestSupport.ExtFactor.new()
	f.name_key = &"a"
	f.value = -400
	f.weight = 500
	f.direction = 1  # değer×ağırlık negatif ama sim "lehte" diyor
	r.factors = [f]
	r.finalize()
	assert_bool(ReasonModel.from_record(r).has_issue(ReasonModel.ISSUE_DIRECTION)).is_true()


func test_v10_record_without_extension_fields_degrades_gracefully() -> void:
	var m := ReasonModel.from_record(record(0, [factor(&"a", 100, 1000)]))
	assert_that(m.summary_key).is_equal(&"")
	assert_int(m.cause_refs.size()).is_equal(0)
	assert_bool(m.rows[0].has_trend).is_false()


func test_scale_range_contains_zero_score_and_threshold() -> void:
	var m := ReasonModel.from_record(record(500, [factor(&"a", -200, 1000)]))
	var rng := m.scale_range()
	assert_bool(rng.x <= -200.0 and rng.x <= 0.0).is_true()
	assert_bool(rng.y >= 500.0).is_true()
	assert_float(ReasonModel.position_in(500.0, rng)).is_between(0.0, 1.0)
	assert_float(ReasonModel.position_in(-9999.0, rng)).is_equal(0.0)  # aralık dışı kenetlenir


func test_fixed_point_formatting_is_turkish_and_exact() -> void:
	assert_str(UiText.fixed(450)).is_equal("0,45")
	assert_str(UiText.fixed(500)).is_equal("0,50")
	assert_str(UiText.fixed(125)).is_equal("0,125")
	assert_str(UiText.fixed(1000)).is_equal("1,00")
	assert_str(UiText.fixed(-60, true)).is_equal("−0,06")
	assert_str(UiText.fixed(120, true)).is_equal("+0,12")
	assert_str(UiText.fixed(0, true)).is_equal("0,00")
	assert_str(UiText.fixed(1234567)).is_equal("1.234,567")
