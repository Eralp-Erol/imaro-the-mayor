extends GdUnitTestSuite
## T-043C UI (CAN-06, SIM-12; Q-003) · Bütçe paneli ve yol önizlemesi gerçek bütçeli sim ile:
## kasa/son ay geliri/yol gideri,
## "Gösterge" etiketi, maliyet "N birim" (para simgesi yok), geri alma iadesi, bütçesiz eski metin, gerekçe metinleri.

const B := preload("res://tests/sim/budget/budget_support.gd")
const P := preload("res://tests/sim/public_works/public_works_support.gd")
const NORTH := Vector2(1100.0, 1000.0)

var _facade: SimFacadeImpl
var _net: WorldNetwork


func before_test() -> void:
	UiText.reset()
	UiText.report_missing = false


func after_test() -> void:
	UiText.reset()


func _setup(attach: bool) -> void:
	var run := B.road_run(P.SEED, {}, attach)
	_facade = run["facade"]
	_net = run["net"]


func _holder(window: Vector2 = Vector2(440.0, 1400.0)) -> Control:
	var holder: Control = auto_free(Control.new())
	holder.theme = UiTheme.build(UiContext.for_profile_name(&"desktop"))
	holder.size = window
	add_child(holder)
	return holder


func _budget_panel() -> BudgetPanel:
	var p := BudgetPanel.create(UiContext.for_profile_name(&"desktop"), _facade, BudgetDraft.new())
	var holder := _holder()
	holder.add_child(p)
	p.size = holder.size
	return p


func _road_panel(tool: RoadDrawTool) -> RoadDrawPanel:
	var p := RoadDrawPanel.create(UiContext.for_profile_name(&"desktop"), _facade, tool)
	var holder := _holder()
	holder.add_child(p)
	p.size = holder.size
	return p


func test_budget_strings_exist() -> void:
	for key: StringName in [&"actor.municipality", &"decision.budget.road_cost", &"decision.budget.road_refund",
			&"decision.budget.tax_revenue", &"budget.factor.amount", &"budget.factor.infra_units",
			&"budget.factor.unit_cost", &"budget.factor.public_share_pm", &"budget.factor.residential_units",
			&"budget.factor.commercial_units", &"budget.factor.tax_rate_pm", &"budget.factor.completed_buildings",
			&"budget.line.roads", &"budget.indicator_note", &"budget.reasons_pruned", &"road.cost_units"]:
		assert_bool(UiText.has(key)).override_failure_message("eksik metin: %s" % key).is_true()


func test_without_budget_the_panel_says_not_built_and_road_cost_keeps_old_text() -> void:
	_setup(false)
	var panel := _budget_panel()
	assert_str(panel.state_view.visible_text()).is_equal("Bütçe sistemi henüz kurulmadı")
	var tool := RoadDrawTool.create(_net, _facade)
	tool.activate()
	tool.tap_at(P.GRID_ORIGIN, 5.0)
	tool.tap_at(NORTH, 1.0)
	assert_str(_road_panel(tool).joined_text()).contains("Maliyet: henüz kurulmadı")


func test_with_budget_panel_shows_sim_cash_indicator_label_and_no_dead_editor() -> void:
	_setup(true)
	var view := _facade.snapshot().budget
	var text := _budget_panel().joined_text()
	assert_str(text).contains(UiText.money(view.balance))
	assert_str(text).contains("Gösterge")
	assert_str(text).contains("Son ay vergi geliri")
	assert_str(text).contains("henüz ay kapanmadı")  # period 0: 0 gelir diye gösterilmez
	assert_str(text).contains("Yollar")
	assert_str(text).contains("henüz kurulmadı")  # tahsis düzenleme sim'de yok
	assert_bool(text.contains("Meclise sun")).is_false()


func test_road_preview_cost_is_sim_units_then_undo_shows_refund() -> void:
	_setup(true)
	var tool := RoadDrawTool.create(_net, _facade)
	tool.activate()
	tool.tap_at(P.GRID_ORIGIN, 5.0)
	tool.tap_at(NORTH, 1.0)
	var args := tool.preview_args()
	assert_bool(bool(args.get("cost_available", false))).is_true()
	var cost := int(args["cost"])
	assert_int(cost).is_greater(0)
	var text := _road_panel(tool).joined_text()
	assert_str(text).contains("Maliyet: %s birim" % UiText.number(cost))
	assert_bool(text.contains("henüz kurulmadı")).is_false()
	assert_bool(text.contains("₺")).is_false()
	tool.confirm()
	_facade.advance(70)
	var after := _road_panel(tool)
	assert_str(after.joined_text()).contains("İade: %s birim" % UiText.number(cost))
	var budget_text := _budget_panel().joined_text()
	assert_str(budget_text).contains(UiText.money(_facade.snapshot().budget.expenses()))


func test_negative_cash_warns_but_road_is_still_accepted() -> void:
	var run := B.road_run(P.SEED, {"initial_balance": -5000})
	_facade = run["facade"]
	_net = run["net"]
	var text := _budget_panel().joined_text()
	assert_str(text).contains(UiText.t(&"budget.debt"))
	assert_str(text).contains(UiText.t(&"budget.debt_note"))
	var r := _facade.validate_command(P.road(P.spur_a_cm()))
	assert_bool(r.is_rejected()).is_false()
