extends GdUnitTestSuite
## T-067 UI (D-019 E1; SIM-12, SIM-07, CAN-03): yeniden iskân BEKLEME LİSTESİ oyuncuya görünür. Sayılar YALNIZ
## `PolicyView.waiting_households/waiting_by_region/served_households` alanlarından (burada senaryo facade'i bunları
## taşır; gerçek sim sorgusu tests/sim/public_works/resettlement_queue_test.gd). Ham anahtar ekrana çıkmaz.

const SCENARIO := "mock_scenario_expropriation"


## Bekleme alanlarını testin verdiği değerlerle dolduran sahte (mock) facade.
class QueueFacade:
	extends MockSimFacade
	var waiting: int = 0
	var by_region: Dictionary = {}
	var served: int = 0
	var enabled_now: bool = true

	func policies() -> Array[PolicyView]:
		var v := PolicyView.new()
		v.policy_id = PolicyView.ID_RESETTLEMENT
		v.enabled = enabled_now
		v.waiting_households = waiting
		v.waiting_by_region = by_region.duplicate()
		v.served_households = served
		return [v]


var _facade: QueueFacade


func before_test() -> void:
	InspectorHost.default_interval_msec = 0
	UiText.reset()
	UiText.report_missing = true
	_facade = QueueFacade.new(MockScenario.load_file(UiTestSupport.FIXTURES + SCENARIO + ".json"))


func after_test() -> void:
	UiText.reset()


func _panel(profile: StringName = &"desktop", width: float = 440.0) -> PolicyPanel:
	var ctx := UiContext.for_profile_name(profile)
	var holder := Control.new()
	holder.theme = UiTheme.build(ctx)
	holder.size = Vector2(width, 1600.0)
	add_child(holder)
	auto_free(holder)
	var panel := PolicyPanel.create(ctx, _facade, {})
	holder.add_child(panel)
	panel.size = holder.size
	return panel


func _hud() -> Array:
	var hud := HudRoot.new()
	add_child(hud)
	auto_free(hud)
	hud.setup(_facade, UiTestSupport.platform(&"desktop"))
	var decisions := DecisionPanels.attach(hud, _facade, Callable(), false)
	return [hud, decisions]


func test_panel_shows_waiting_count_regions_and_the_reason_with_real_numbers() -> void:
	_facade.waiting = 7
	_facade.by_region = {"B": 2, "A": 5}
	_facade.served = 3
	var text := _panel().joined_text()
	assert_str(text).contains("Bekleyen aile: 7")
	assert_str(text).contains("A: 5 · B: 2")
	assert_str(text).contains("Sonradan ev verilen aile: 3")
	assert_str(text).contains("belediye ev yapmaz")
	assert_str(text).not_contains("queue.")


func test_panel_says_nobody_waits_and_hides_served_and_reason_rows_at_zero() -> void:
	var text := _panel().joined_text()
	assert_str(text).contains("Bekleyen aile yok")
	assert_str(text).not_contains("Sonradan ev verilen")
	assert_str(text).not_contains("yatırımcının bitirdiği")


func test_paused_list_is_explained_when_the_policy_is_off() -> void:
	_facade.waiting = 2
	_facade.enabled_now = false
	assert_str(_panel().joined_text()).contains("bekleyen ailelere ev verilmez")


func test_panel_signature_changes_when_the_queue_changes() -> void:
	_facade.waiting = 2
	var panel := _panel()
	var before := panel.signature_now()
	_facade.waiting = 1
	_facade.served = 1
	assert_str(panel.signature_now()).is_not_equal(before)


func test_touch_panel_with_queue_rows_keeps_44pt_targets() -> void:
	_facade.waiting = 4
	_facade.by_region = {"A": 4}
	var panel := _panel(&"touch", 389.0)
	assert_array(Array(TouchAudit.violations(panel, 389.0, 44.0))).is_empty()


func test_strip_shows_waiting_and_then_the_homes_found_batch() -> void:
	var parts := _hud()
	var hud: HudRoot = parts[0]
	_facade.waiting = 5
	hud.refresh()
	assert_array(Array(hud.strip.queue_texts())).contains(["5 aile yeniden iskân için ev bekliyor"])
	assert_array(Array(hud.strip.queue_texts())).has_size(1)   # henüz kimse yerleşmedi: "yerleşti" satırı yok
	# Yatırımcı ev bitirdi: 3 aile yerleşti (toplam 0 -> 3), 2 aile hâlâ bekliyor.
	_facade.waiting = 2
	_facade.served = 3
	hud.facade.advance(1)
	hud.refresh()
	var texts := Array(hud.strip.queue_texts())
	assert_array(texts).contains(["3 aile yeni eve yerleşti", "2 aile yeniden iskân için ev bekliyor"])
	assert_bool(hud.strip.visible).is_true()
	# Liste boşaldı: bekleyen satırı gider, yerleşti satırı kalır.
	_facade.waiting = 0
	hud.facade.advance(1)
	hud.refresh()
	assert_array(Array(hud.strip.queue_texts())).is_equal(["3 aile yeni eve yerleşti"])


func test_notice_ignores_the_total_already_present_at_start_and_a_falling_total() -> void:
	var n := ResettlementQueueNotice.new()
	var v := PolicyView.new()
	v.policy_id = PolicyView.ID_RESETTLEMENT
	v.served_households = 9
	n.observe([v])
	assert_int(n.last_batch()).is_equal(0)   # açılıştaki eski toplam "yeni" sayılmaz
	v.served_households = 12
	n.observe([v])
	assert_int(n.last_batch()).is_equal(3)
	v.served_households = 4   # geri alma/yükleme
	n.observe([v])
	assert_int(n.last_batch()).is_equal(0)


func test_no_policy_world_shows_no_queue_row() -> void:
	var n := ResettlementQueueNotice.new()
	n.observe([])
	assert_int(n.waiting()).is_equal(0)
	assert_int(n.last_batch()).is_equal(0)
