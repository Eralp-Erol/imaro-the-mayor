extends GdUnitTestSuite
## T-065 Aşama 1 · `ResettlementPlanner.allocate` SAF hesabı (spec §3.0/§4, ADR-0009 B): üç denetim (kapasite, kira,
## yer),
## `max_fill_pm` tavanı, sıralama (sınıf, mesafe, kod), kalan tepki (`effective`). Girdi düz veridir; dünya gerekmez.
## Önizleme ve uygulama AYNI hesabı kullanır (ölçüt 8): akış testleri `resettlement_flow_test.gd`.
## Sayılar ÇALIŞMA MODELİ (F05-C): burada veri bölümü açıkça yazılır, gömülü sayı yok.

const DATA := {"max_fill_pm": 300, "rent_tolerance_pm": 250, "max_distance_m": 800, "partial_relief_pm": 600,
	"residual_reaction_pm": 200, "support_months": 12, "move_grant": 0}


func _cfg(changes: Dictionary = {}) -> ResettlementConfig:
	var section := DATA.duplicate()
	section.merge(changes, true)
	var cfg := ResettlementConfig.from_dict(section)
	assert_bool(cfg.available).override_failure_message(cfg.error).is_true()
	return cfg


func _src(code: String, displaced: int, rent: int = 100) -> Dictionary:
	return {"code": code, "displaced": displaced, "rent": rent}


## `dist2` -1: yer şartı aşılıyor (menzil dışı).
func _tgt(code: String, vacancy: int, rent: int = 100, dist2: int = 0, unit_cost: int = 10) -> Dictionary:
	return {"code": code, "vacancy": vacancy, "rent": rent, "unit_cost": unit_cost, "dist2": dist2}


func _plan(sources: Array, targets: Array, changes: Dictionary = {}) -> Dictionary:
	return ResettlementPlanner.allocate(sources, targets, _cfg(changes))


# --- Olumlu O-1: yeterli boş ev ---

func test_enough_vacancy_houses_everyone_and_the_remaining_reaction_is_small_but_not_zero() -> void:
	var plan := _plan([_src("D1", 12)], [_tgt("D2", 40)])
	assert_array(plan["moves"]).is_equal([["D1", "D2", 12]])  # 40 x %30 = 12
	assert_int(plan["rehoused"]).is_equal(12)
	assert_int(plan["unplaced"]).is_equal(0)
	assert_int(plan["partial"]).is_equal(0)
	assert_int((plan["effective"] as Dictionary)["D1"]).is_equal(3)  # ceil(12 x 200 / 1000): sıfır DEĞİL (D-016 §2)
	assert_int(plan["cost"]).is_equal(12 * 10)  # hane x hedefin birim bedeli (girdi: unit_cost)
	assert_int(plan["residual_pm"]).is_equal(200)


func test_a_single_rehoused_household_still_leaves_at_least_one_unit_of_reaction() -> void:
	var plan := _plan([_src("D1", 1)], [_tgt("D2", 100)])
	assert_int(plan["rehoused"]).is_equal(1)
	assert_int((plan["effective"] as Dictionary)["D1"]).is_equal(1)  # yukarı yuvarlama: 1 x 200 / 1000 -> 1


func test_residual_zero_is_the_old_d014_behaviour_when_everyone_is_housed() -> void:
	var plan := _plan([_src("D1", 12)], [_tgt("D2", 40)], {"residual_reaction_pm": 0})
	assert_int((plan["effective"] as Dictionary)["D1"]).is_equal(0)


# --- max_fill_pm: tek yol tüm boş evleri tüketmesin ---

func test_one_road_may_take_at_most_max_fill_of_the_target_vacancy() -> void:
	var plan := _plan([_src("D1", 100)], [_tgt("D2", 10)])
	assert_int(plan["rehoused"]).is_equal(3)  # 10 x %30
	assert_int(plan["unplaced"]).is_equal(97)
	assert_int((plan["unplaced_by"] as Dictionary)["D1"]).is_equal(97)
	assert_int((plan["effective"] as Dictionary)["D1"]).is_equal(97 + 1)  # 97 tam + ceil(3 x 200 / 1000)


func test_two_sources_share_the_same_target_cap_not_a_cap_each() -> void:
	var plan := _plan([_src("D1", 5), _src("D3", 5)], [_tgt("D2", 20)])  # tavan 6
	assert_array(plan["moves"]).is_equal([["D1", "D2", 5], ["D3", "D2", 1]])
	assert_int(plan["rehoused"]).is_equal(6)
	assert_int(plan["unplaced"]).is_equal(4)


# --- Olumsuz N-1: ev yok ---

func test_no_vacancy_anywhere_means_everyone_is_unplaced_cost_zero_and_the_reaction_is_whole() -> void:
	var plan := _plan([_src("D1", 12)], [_tgt("D2", 0), _tgt("D3", 0)])
	assert_array(plan["moves"]).is_empty()
	assert_int(plan["rehoused"]).is_equal(0)
	assert_int(plan["unplaced"]).is_equal(12)
	assert_int(plan["cost"]).is_equal(0)
	assert_int((plan["effective"] as Dictionary)["D1"]).is_equal(12)
	var none := _plan([_src("D1", 12)], [])
	assert_int(none["unplaced"]).is_equal(12)


func test_a_vacancy_too_small_for_the_cap_is_honestly_not_used() -> void:
	var plan := _plan([_src("D1", 4)], [_tgt("D2", 3)])  # floor(3 x 0,3) = 0
	assert_int(plan["rehoused"]).is_equal(0)
	assert_int(plan["unplaced"]).is_equal(4)


# --- Olumsuz N-3 ve kısmi: kira ve yer şartları ---

func test_both_conditions_exceeded_is_not_a_home() -> void:
	# kira: 200 x 1000 > 100 x 1250; yer: menzil dışı
	var plan := _plan([_src("D1", 5, 100)], [_tgt("D2", 100, 200, -1)])
	assert_int(plan["rehoused"]).is_equal(0)
	assert_int(plan["unplaced"]).is_equal(5)


func test_one_condition_exceeded_is_a_partial_home_with_a_bigger_remaining_reaction() -> void:
	var by_place := _plan([_src("D1", 10)], [_tgt("D2", 100, 100, -1)])  # kira uygun, yer aşıldı
	assert_int(by_place["rehoused"]).is_equal(10)
	assert_int(by_place["partial"]).is_equal(10)
	assert_int((by_place["effective"] as Dictionary)["D1"]).is_equal(4)  # 10 x (1000 - 600) / 1000
	var by_rent := _plan([_src("D1", 10, 100)], [_tgt("D2", 100, 200, 0)])  # yer uygun, kira aşıldı
	assert_int(by_rent["partial"]).is_equal(10)
	assert_int((by_rent["effective"] as Dictionary)["D1"]).is_equal(4)


func test_rent_tolerance_is_the_inclusive_limit() -> void:
	# 125 x 1000 <= 100 x 1250: tam sınır = uygun (tam ev)
	var at_limit := _plan([_src("D1", 10, 100)], [_tgt("D2", 100, 125, 0)])
	assert_int(at_limit["partial"]).is_equal(0)
	var over := _plan([_src("D1", 10, 100)], [_tgt("D2", 100, 126, 0)])
	assert_int(over["partial"]).is_equal(10)


func test_partial_relief_is_data_and_never_reduces_below_the_full_home_residual() -> void:
	var cheap := _plan([_src("D1", 10)], [_tgt("D2", 100, 100, -1)], {"partial_relief_pm": 950})
	assert_int((cheap["effective"] as Dictionary)["D1"]).is_equal(2)  # 1000 - 950 = 50 < kalan 200: tam evden iyi olamaz


# --- Sıralama ---

func test_full_homes_come_before_partial_and_nearer_before_farther_then_code() -> void:
	var targets := [_tgt("D5", 100, 100, 900), _tgt("D4", 100, 100, 400), _tgt("D6", 100, 100, -1),
		_tgt("D3", 100, 100, 400)]
	var plan := _plan([_src("D1", 70)], targets)  # tavan 30 her hedef
	assert_array(plan["moves"]).is_equal([["D1", "D3", 30], ["D1", "D4", 30], ["D1", "D5", 10]])
	# tam evler yetti: kısmi (D6) hiç kullanılmadı
	assert_int(plan["partial"]).is_equal(0)


func test_partial_homes_are_used_only_after_the_full_ones_are_exhausted() -> void:
	var plan := _plan([_src("D1", 50)], [_tgt("D2", 100, 100, 100), _tgt("D3", 100, 100, -1)])
	assert_array(plan["moves"]).is_equal([["D1", "D2", 30], ["D1", "D3", 20]])
	assert_int(plan["partial"]).is_equal(20)
	assert_int((plan["effective"] as Dictionary)["D1"]).is_equal(6 + 8)  # ceil(30x200/1000) + 20 x 400 / 1000


# --- Değişmezler ---

func test_invariants_rehoused_plus_unplaced_is_displaced_and_the_plan_is_deterministic() -> void:
	var sources := [_src("D1", 37), _src("D3", 21, 150)]
	var targets := [_tgt("D2", 55, 100, 300), _tgt("D4", 12, 400, -1), _tgt("D5", 80, 140, 700, 25)]
	var first := _plan(sources, targets)
	var second := _plan(sources.duplicate(true), targets.duplicate(true))
	assert_str(StateHash.of(first)).is_equal(StateHash.of(second))
	assert_int(int(first["rehoused"]) + int(first["unplaced"])).is_equal(37 + 21)
	var moved := 0
	for move: Array in first["moves"]:
		assert_int(int(move[2])).is_greater(0)
		moved += int(move[2])
	assert_int(moved).is_equal(first["rehoused"])
	var unplaced := 0
	for code: String in first["unplaced_by"]:
		unplaced += int(first["unplaced_by"][code])
	assert_int(unplaced).is_equal(first["unplaced"])
	for code: String in first["effective"]:
		assert_int(int(first["effective"][code])).is_greater_equal(int(first["unplaced_by"].get(code, 0)))


func test_sources_with_nothing_displaced_are_ignored_and_input_order_does_not_matter() -> void:
	var targets := [_tgt("D2", 100)]
	var a := _plan([_src("D3", 4), _src("D1", 0), _src("D4", 6)], targets)
	var b := _plan([_src("D4", 6), _src("D3", 4)], targets)
	assert_str(StateHash.of(a)).is_equal(StateHash.of(b))
	assert_bool((a["effective"] as Dictionary).has("D1")).is_false()


func test_cost_is_households_times_the_target_unit_cost_summed_over_moves() -> void:
	var plan := _plan([_src("D1", 40)], [_tgt("D2", 100, 100, 100, 7), _tgt("D3", 100, 100, 200, 11)])
	assert_array(plan["moves"]).is_equal([["D1", "D2", 30], ["D1", "D3", 10]])
	assert_int(plan["cost"]).is_equal(30 * 7 + 10 * 11)
