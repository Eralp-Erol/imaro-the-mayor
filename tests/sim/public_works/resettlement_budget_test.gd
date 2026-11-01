extends "res://tests/sim/public_works/resettlement_test_base.gd"
## T-065 Aşama 1 · Yeniden iskân BEDELİ gösterge bütçeye ayrı kalem olarak yazılır, geri almada iade edilir (ADR-0009
## Bütçe). Para kısıt DEĞİLDİR: bedel kasayı etkiler ama hiçbir komutu reddetmez. Yol kalemi yeniden iskân bedelini
## İÇERMEZ (SIM-07: oyuncuya yanlış kalem gösterilmez). Politika kapalıyken bütçe bölümüne yeni alan yazılmaz.

const FULL := {"max_distance_m": 5000}


func _budget(run: Dictionary) -> Dictionary:
	return BudgetState.data(_h(run).state())


func _line(run: Dictionary, key: StringName) -> BudgetLineView:
	return _f(run).snapshot().budget.line(key)


func _balance_rule_holds(run: Dictionary) -> bool:
	var d := _budget(run)
	return int(d["balance"]) == int(d["initial_balance"]) + int(d["revenue_total"]) - int(d["roads_net"]) \
		- int(d.get("resettlement_net", 0))


func test_with_the_policy_off_the_budget_section_has_no_resettlement_field_at_all() -> void:
	var run := _rworld(60, FULL)
	_road(run)
	_f(run).advance(2)
	assert_bool(_budget(run).has("resettlement_net")).is_false()
	assert_bool((_budget(run)["charged"][0] as Dictionary).has("resettlement")).is_false()
	assert_object(_line(run, BudgetLineView.KEY_RESETTLEMENT)).is_null()
	var kinds := (_budget(run)["ledger"] as Array).map(func(e: Dictionary) -> String: return str(e["kind"]))
	assert_bool(kinds.has("resettlement")).is_false()


func test_the_cost_is_booked_once_on_its_own_line_and_the_road_line_does_not_include_it() -> void:
	var off := _rworld(60, FULL)
	_road(off)
	var run := _rworld(60, FULL)
	_policy(run, true)
	_road(run)
	_f(run).advance(2)
	var cost := int(_record(run)["cost"])
	assert_int(cost).is_greater(0)
	assert_int(int(_budget(run)["resettlement_net"])).is_equal(cost)
	assert_int(int((_budget(run)["charged"][0] as Dictionary)["resettlement"])).is_equal(cost)
	assert_int(_line(run, BudgetLineView.KEY_RESETTLEMENT).amount).is_equal(cost)
	assert_int(_line(run, &"budget.line.roads").amount).override_failure_message("yol kalemi aynı kalır").is_equal(
		_line(off, &"budget.line.roads").amount)
	assert_bool(_balance_rule_holds(run)).is_true()
	var entries := (_budget(run)["ledger"] as Array).filter(func(e: Dictionary) -> bool:
		return e["kind"] == "resettlement")
	assert_int(entries.size()).is_equal(1)
	assert_int(int((entries[0] as Dictionary)["amount"])).is_equal(cost)
	assert_int(int((entries[0] as Dictionary)["reason_id"])).is_greater(0)  # SIM-12: nedeni var
	_f(run).advance(5)
	assert_int(int(_budget(run)["resettlement_net"])).override_failure_message("bir kez yazılır").is_equal(cost)


func test_no_vacancy_means_no_cost_and_no_resettlement_line() -> void:
	var run := _rworld(0, FULL)
	_policy(run, true)
	_road(run)
	_f(run).advance(2)
	assert_bool(_budget(run).has("resettlement_net")).is_false()
	assert_object(_line(run, BudgetLineView.KEY_RESETTLEMENT)).is_null()


func test_undo_refunds_the_resettlement_cost_to_the_cent() -> void:
	var run := _rworld(60, FULL)
	_policy(run, true)
	_road(run)
	_f(run).advance(2)
	var cost := int(_record(run)["cost"])
	_do(run, SimCommand.public_work_undo_last())
	_f(run).advance(1)
	assert_int(int(_budget(run)["resettlement_net"])).is_equal(0)
	assert_int(_line(run, BudgetLineView.KEY_RESETTLEMENT).amount).is_equal(0)
	assert_bool(_balance_rule_holds(run)).is_true()
	var refunds := (_budget(run)["ledger"] as Array).filter(func(e: Dictionary) -> bool:
		return e["kind"] == "resettlement_refund")
	assert_int(refunds.size()).is_equal(1)
	assert_int(int((refunds[0] as Dictionary)["amount"])).is_equal(cost)


func test_the_budget_never_blocks_a_road_even_when_the_cost_exceeds_the_balance() -> void:
	var run := _rworld(60, FULL)
	_policy(run, true)
	var d := _budget(run)
	d["balance"] = 0
	d["initial_balance"] = 0
	_road(run)  # _do reddedilirse kendi iddiası patlar: bütçe kısıt değil
	_f(run).advance(2)
	assert_int(int(_budget(run)["balance"])).is_less(0)
	assert_bool(_balance_rule_holds(run)).is_true()


func test_a_budget_section_whose_resettlement_total_does_not_add_up_is_refused_on_load() -> void:
	var run := _rworld(60, FULL)
	_policy(run, true)
	_road(run)
	_f(run).advance(2)
	var good: Dictionary = _budget(run).duplicate(true)
	assert_str(BudgetState.validate_data(good)).is_empty()
	var wrong_net := good.duplicate(true)
	wrong_net["resettlement_net"] = int(good["resettlement_net"]) + 1
	assert_str(BudgetState.validate_data(wrong_net)).is_not_empty()
	var wrong_balance := good.duplicate(true)
	wrong_balance["balance"] = int(good["balance"]) + 1
	assert_str(BudgetState.validate_data(wrong_balance)).is_not_empty()
	var orphan := good.duplicate(true)
	orphan.erase("resettlement_net")  # satırda bedel var, toplam yok
	assert_str(BudgetState.validate_data(orphan)).is_not_empty()
	var bad_type := good.duplicate(true)
	bad_type["charged"][0]["resettlement"] = "x"
	assert_str(BudgetState.validate_data(bad_type)).is_not_empty()
