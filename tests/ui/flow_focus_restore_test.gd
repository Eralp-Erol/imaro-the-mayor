extends GdUnitTestSuite
## Hata: `ERROR: Condition "!is_inside_tree()" is true. at: grab_focus` (kullanıcı demosu, parsel seçimi sonrası).
## Kök neden: `FlowPanel._restore_focus` odağı `grab_focus.call_deferred()` ile verir; aynı karede panel bir kez daha
## yeniden çizilirse (gövde `remove_child` + `queue_free`) ertelenmiş çağrı ağaçtan çıkmış düğmeye düşer.
## Bu test panel gövdesini aynı karede iki kez yeniden çizer ve kare bitince motor hatası olmamasını bekler.

const P := preload("res://tests/sim/public_works/public_works_support.gd")
const NORTH := Vector2(1100.0, 1000.0)

var _run: Dictionary
var _tool: RoadDrawTool


func before_test() -> void:
	UiText.reset()
	UiText.report_missing = false
	_run = P.setup()
	_tool = RoadDrawTool.create(_run["net"], _run["facade"])
	_tool.activate()


func after_test() -> void:
	UiText.reset()


func _panel() -> RoadDrawPanel:
	var ctx := UiContext.for_profile_name(&"desktop")
	var holder := Control.new()
	holder.theme = UiTheme.build(ctx)
	holder.size = Vector2(440.0, 1400.0)
	add_child(holder)
	auto_free(holder)
	var panel := RoadDrawPanel.create(ctx, _run["facade"], _tool)
	holder.add_child(panel)
	panel.size = holder.size
	return panel


func test_two_renders_in_one_frame_leave_no_deferred_focus_on_removed_buttons() -> void:
	var panel := _panel()
	await await_idle_frame()
	_tool.tap_at(P.GRID_ORIGIN, 5.0)
	_tool.tap_at(NORTH, 1.0)
	panel.refresh()
	var confirm := panel.confirm_button()
	assert_object(confirm).is_not_null()
	confirm.grab_focus()
	assert_bool(confirm.has_focus()).is_true()
	# Aynı karede iki yeniden çizim: ilki odağı ertelemeli ister, ikincisi o düğmeyi ağaçtan çıkarır.
	panel._render()
	panel._render()
	await await_idle_frame()
	await await_idle_frame()
	# Hata yoksa GdUnit hata izleyicisi testi düşürmez; odak yeni (ağaçtaki) düğmeye geçmiş olmalı.
	var now := panel.confirm_button()
	assert_object(now).is_not_null()
	assert_bool(now.is_inside_tree()).is_true()
	assert_bool(now.has_focus()).override_failure_message("odak yeni Onayla düğmesinde olmalı").is_true()


func test_restore_focus_ignores_a_button_that_left_the_tree_before_the_deferred_call() -> void:
	var panel := _panel()
	await await_idle_frame()
	_tool.tap_at(P.GRID_ORIGIN, 5.0)
	_tool.tap_at(NORTH, 1.0)
	panel.refresh()
	var stale := Button.new()
	assert_bool(panel.focus_button_if_alive(stale)) \
		.override_failure_message("ağaçta olmayan düğme odaklanmamalı") \
		.is_false()
	stale.free()
	var confirm := panel.confirm_button()
	assert_bool(panel.focus_button_if_alive(confirm)).is_true()
	assert_bool(confirm.has_focus()).is_true()
