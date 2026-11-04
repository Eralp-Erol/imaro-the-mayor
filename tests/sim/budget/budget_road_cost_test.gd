extends GdUnitTestSuite
## T-043C ölçüt 1 ve 3 · Yol gideri = eklenen altyapı birimi x cost_per_unit x public_cost_share_pm / 1000 (tam sayı);
## yol geri alınırsa iade; kasa tutarlı (başlangıç - gider + gelir). Her kalem gerekçe taşır (SIM-12).

const B := preload("res://tests/sim/budget/budget_support.gd")
const P := preload("res://tests/sim/public_works/public_works_support.gd")
const ROAD_COST := &"decision.budget.road_cost"
const ROAD_REFUND := &"decision.budget.road_refund"


func _f(run: Dictionary) -> SimFacadeImpl:
	return run["facade"]


func test_without_roads_or_buildings_expense_and_revenue_are_zero_and_balance_is_the_initial_treasury() -> void:
	var cfg := B.config()
	var run := B.road_run()
	_f(run).advance(65)  # iki ay sınırı geçti; bina/yol yok
	var view := _f(run).snapshot().budget
	assert_int(view.revenue).is_equal(0)
	assert_int(view.expenses()).is_equal(0)
	assert_int(view.balance).is_equal(cfg.initial_balance)
	assert_int(view.period).is_equal(2)


func test_road_expense_equals_the_formula_in_whole_numbers() -> void:
	var cfg := B.config({"road": {"public_cost_share_pm": 500, "cost_use": "residential"}})
	var run := P.setup()
	assert_bool(_f(run).attach_budget(cfg)).is_true()
	var f := _f(run)
	f.advance(3)
	assert_str(String(f.submit_command(P.road(P.spur_a_cm())).status)).is_equal("queued")
	f.advance(1)
	var units := B.road_units(f)
	assert_int(units).is_greater(0)
	var expected := units * 1000 * 500 / 1000  # konut cost_per_unit = 1000 (economy_config.json)
	assert_int(B.expected_road_cost(units, cfg)).is_equal(expected)
	assert_int(B.line_amount(f)).is_equal(expected)
	assert_int(f.snapshot().budget.expenses()).is_equal(expected)
	assert_int(f.snapshot().budget.balance).is_equal(cfg.initial_balance - expected)


func test_each_road_cost_item_carries_a_reason_naming_the_command() -> void:
	var run := B.road_run()
	var f := _f(run)
	f.advance(3)
	var queued := f.submit_command(P.road(P.spur_a_cm()))
	f.advance(1)
	var ids := f.snapshot().budget.reason_ids
	assert_int(ids.size()).is_greater(0)
	var found: ReasonRecord = null
	for id in ids:
		var r := f.reason(id)
		if r != null and r.decision_key == ROAD_COST:
			found = r
	assert_object(found).is_not_null()
	assert_bool(found.subjects.has(String(SimContract.ref(SimContract.REF_COMMAND, queued.command_id)))).is_true()
	var by_subject := f.reasons_for(SimContract.ref(SimContract.REF_COMMAND, queued.command_id))
	var has_cost := false
	for r in by_subject:
		has_cost = has_cost or r.decision_key == ROAD_COST
	assert_bool(has_cost).is_true()
	# gerekçedeki tutar faktörü kasadan düşen tutarla aynı (sahte sayı yok)
	var amount_factor: ReasonFactor = null
	for fac in found.factors:
		if fac.name_key == &"budget.factor.amount":
			amount_factor = fac
	assert_object(amount_factor).is_not_null()
	assert_int(amount_factor.value).is_equal(B.line_amount(f))


func test_undoing_the_road_refunds_the_expense_and_keeps_the_treasury_consistent() -> void:
	var cfg := B.config()
	var run := B.road_run()
	var f := _f(run)
	f.advance(3)
	f.submit_command(P.road(P.spur_a_cm()))
	f.advance(1)
	assert_int(B.line_amount(f)).is_greater(0)
	f.advance(40)  # ay sınırı geçer; bina yok -> gelir 0
	assert_int(f.snapshot().budget.balance).is_less(cfg.initial_balance)
	assert_str(String(f.submit_command(SimCommand.public_work_undo_last()).status)).is_equal("queued")
	f.advance(1)
	assert_int(B.line_amount(f)).is_equal(0)
	assert_int(f.snapshot().budget.balance).is_equal(cfg.initial_balance)
	var refund_seen := false
	for id in f.snapshot().budget.reason_ids:
		refund_seen = refund_seen or f.reason(id).decision_key == ROAD_REFUND
	assert_bool(refund_seen).is_true()


func test_undo_refunds_only_the_last_road_and_the_first_stays_charged() -> void:
	var cfg := B.config()
	var run := B.road_run()
	var f := _f(run)
	f.advance(2)
	f.submit_command(P.road(P.spur_a_cm()))
	f.advance(1)
	var first := B.line_amount(f)
	f.submit_command(P.road(P.spur_b_cm()))
	f.advance(1)
	var second := B.line_amount(f) - first
	assert_int(first).is_equal(B.expected_road_cost(B.road_units(f, 0), cfg))
	assert_int(second).is_equal(B.expected_road_cost(B.road_units(f, 1), cfg))
	f.submit_command(SimCommand.public_work_undo_last())
	f.advance(1)
	assert_int(B.line_amount(f)).is_equal(first)
	assert_int(f.snapshot().budget.balance).is_equal(cfg.initial_balance - first)


func test_road_preview_reports_the_cost_and_undo_preview_the_refund_from_the_sim() -> void:
	var cfg := B.config()
	var run := B.road_run()
	var f := _f(run)
	f.advance(2)
	var preview := f.validate_command(P.road(P.spur_a_cm()))
	assert_str(String(preview.status)).is_equal("valid")
	assert_bool(bool(preview.args["cost_available"])).is_true()
	assert_bool(preview.args.has("cost_reason_key")).is_false()
	assert_int(int(preview.args["cost"])).is_equal(B.expected_road_cost(int(preview.args["units_total"]), cfg))
	var queued := f.submit_command(P.road(P.spur_a_cm()))
	assert_int(int(queued.args["cost"])).is_equal(int(preview.args["cost"]))  # kuyruk sonucu da aynı hesabı taşır
	f.advance(1)
	var undo := f.validate_command(SimCommand.public_work_undo_last())
	assert_bool(bool(undo.args["refund_available"])).is_true()
	assert_int(int(undo.args["refund"])).is_equal(int(preview.args["cost"]))


func test_without_a_budget_the_preview_still_says_cost_not_built() -> void:
	var run := B.road_run(P.SEED, {}, false)
	var preview := _f(run).validate_command(P.road(P.spur_a_cm()))
	assert_bool(bool(preview.args["cost_available"])).is_false()
	assert_str(String(preview.args["cost_reason_key"])).is_equal("public_work.cost.not_built")
	assert_bool(preview.args.has("cost")).is_false()


func test_a_rejected_road_costs_nothing() -> void:
	var cfg := B.config()
	var run := B.road_run()
	var f := _f(run)
	f.advance(2)
	var bad := f.submit_command(P.road(P.detached_cm()))
	assert_str(String(bad.status)).is_equal("rejected")
	f.advance(3)
	assert_int(B.line_amount(f)).is_equal(0)
	assert_int(f.snapshot().budget.balance).is_equal(cfg.initial_balance)
