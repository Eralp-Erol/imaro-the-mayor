extends SimTestBase
## T-013 ölçüt 4/9 · Finansman (SIM-02): yatırımcı sermayesi sınırlı; proje bedeli onayda sermayeden düşer, aylık dış
## girdi (kredi/diğer gelir, `monthly_inflow`) ve kira geliri sermayeyi besler. Sermaye tükenince
## `insufficient_financing`
## baskın olur ve girdi geldikçe yatırım yeniden başlar (H6).

const W := preload("res://tests/sim/economy/economy_world.gd")
const S := preload("res://tests/sim/economy/economy_test_support.gd")
const ISOLATE := {"decision": {"review_enabled": 0}}


func _investors(capital: int, inflow: int, count: int = 1) -> Dictionary:
	var list: Array = []
	for i in count:
		list.append({"capital": capital, "threshold_shift": 0, "monthly_inflow": inflow})
	return {"investors": {"list": list}}


func _capital(f: SimFacadeImpl) -> int:
	var total := 0
	for c: int in W.data(f)["investors"]["capital"]:
		total += c
	return total


func test_monthly_inflow_tops_up_every_investors_capital() -> void:
	var patch := S.merge(ISOLATE, _investors(5000, 700, 2))
	var h := W.handle(patch)
	h.facade.advance(29)
	assert_int(_capital(h.facade)).override_failure_message("ay dolmadan girdi yok").is_equal(10000)
	h.facade.advance(1)
	assert_int(_capital(h.facade)).is_equal(10000 + 2 * 700)
	h.facade.advance(60)
	assert_int(_capital(h.facade)).is_equal(10000 + 6 * 700)
	assert_int(EconomyQuery.totals(h.facade.game_state())["capital_inflow"]).is_equal(6 * 700)


func test_zero_inflow_leaves_capital_unchanged() -> void:
	var h := W.handle(S.merge(ISOLATE, _investors(5000, 0)))
	h.facade.advance(90)
	assert_int(_capital(h.facade)).is_equal(5000)


func test_exhausted_capital_blocks_new_projects_with_a_financing_reason() -> void:
	# Tek yatırımcı, tek proje bedeli kadar sermaye, girdi yok: ilk proje onaylanır, sonrakiler finansmanla reddedilir.
	var patch := S.merge(ISOLATE, S.merge(_investors(11000, 0), S.regions({"F1": S.favorable()})))
	var h := W.handle(patch)
	var ids := h.facade.parcel_ids(S.R1)
	h.facade.submit_command(SimCommand.zoning_propose(PackedInt64Array([ids[0], ids[1]]), &"zone.mixed"))
	h.facade.advance(12)
	var first := h.facade.reasons_for(SimContract.parcel_ref(ids[0]))
	var second := h.facade.reasons_for(SimContract.parcel_ref(ids[1]))
	assert_str(String(first[0].outcome)).is_equal("positive")
	assert_str(String(second[0].outcome)).override_failure_message("sermaye bitti").is_equal("negative")
	var latest := h.facade.game_state().reasons.latest({"subject": "parcel.%d" % ids[1]})
	assert_str(String(latest["code"])).is_equal("insufficient_financing")
	assert_int(_capital(h.facade)).is_equal(0)
	assert_str(String(W.stage_of(h.facade, ids[1]))).is_equal("vacant")


func test_investment_resumes_once_inflow_rebuilds_capital() -> void:
	var patch := S.merge(S.merge(_investors(11000, 6000), S.regions({"F1": S.favorable()})),
		{"decision": {"review_period_days": 10, "prescreen_demand_pm": 0, "max_starts_per_region_per_day": 5}})
	var h := W.handle(patch)
	h.facade.advance(25)
	var early: int = EconomyQuery.totals(h.facade.game_state())["approvals"]
	assert_int(early).override_failure_message("ilk proje sermayeyle").is_equal(1)
	h.facade.advance(30 * 10)
	var later: int = EconomyQuery.totals(h.facade.game_state())["approvals"]
	assert_int(later).override_failure_message("girdi geldikçe yeni projeler").is_greater(early + 2)
	assert_int(later).override_failure_message("sermaye sınırı: bedelin aşamayacağı sayı").is_less_equal(
		1 + (300 * 6000 / 11000) + 1)


func test_investor_inflow_is_validated_by_the_config() -> void:
	var negative := {"investors": {"list": [{"capital": 100, "threshold_shift": 0, "monthly_inflow": -1}]}}
	var raw := S.merge(S.raw_config(), negative)
	var cfg := EconomyConfig.from_dict(raw)
	assert_bool(cfg.is_valid()).is_false()
	assert_str(cfg.error).contains("monthly_inflow")
	var missing := S.merge(S.raw_config(), {"investors": {"list": [{"capital": 100, "threshold_shift": 0}]}})
	assert_bool(EconomyConfig.from_dict(missing).is_valid()).override_failure_message("monthly_inflow zorunlu").is_false()
