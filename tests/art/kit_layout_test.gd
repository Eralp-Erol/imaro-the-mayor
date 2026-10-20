extends GdUnitTestSuite
## T-004 ölçüt 4 · kit_lab test mahallesi: spec 3.2 çatı payı ve 3.3 varyasyon kuralları SAYILARLA, saat kulesi oranı.
## Veri tabanlı (render yok); olumsuz varyantlar bozulmuş yerleşimle sayaçların ihlali yakaladığını gösterir.

const SEED := 20261020

var _lib: KitLibrary
var _layout: KitLabLayout
var _report: Dictionary = {}


func before() -> void:
	_lib = KitLibrary.load_manifest()
	_layout = KitLabLayout.new()
	_layout.generate(_lib, SEED)
	_report = KitLabMetrics.full_report(_lib, _layout)


func test_layout_is_deterministic_for_a_seed_and_differs_across_seeds() -> void:
	var again := KitLabLayout.new()
	again.generate(_lib, SEED)
	assert_int(again.placements.size()).is_equal(_layout.placements.size())
	for i in [0, 100, 500, _layout.placements.size() - 1]:
		assert_str(str(again.placements[i]["pos"])).is_equal(str(_layout.placements[i]["pos"]))
		assert_str(str(again.placements[i]["id"])).is_equal(str(_layout.placements[i]["id"]))
	var other := KitLabLayout.new()
	other.generate(_lib, SEED + 1)
	assert_bool(str(other.placements[100]["pos"]) != str(_layout.placements[100]["pos"])
			or str(other.placements[100]["id"]) != str(_layout.placements[100]["id"])).is_true()


func test_district_has_at_least_1500_buildings_and_every_family() -> void:
	assert_int(_report["building_count"]).is_greater_equal(1500)
	for fam in ["res_mid", "res_old", "res_late", "res_house", "ind_shed", "ind_heritage", "civ_hall"]:
		assert_bool((_report["families"] as Dictionary).has(fam)).is_true()


func test_orientation_scale_and_no_mirroring_rules() -> void:
	for p in _layout.placements:
		var rot: float = p["rot"]
		assert_bool(is_zero_approx(rot) or is_equal_approx(rot, PI)).is_true()     # yön yalnız 0/180°
		var s: Vector3 = p["scale"]
		assert_float(s.x).is_between(0.90, 1.15)
		assert_float(s.z).is_between(0.50, 1.15)   # derinlik ölçeği parsel derinliğine kırpılabilir (alt sınır gevşek)
		assert_float(s.y).is_between(0.95, 1.05)
		assert_float(s.x * s.y * s.z).is_greater(0.0)                                # ayna (negatif ölçek) yok


func test_adjacent_buildings_never_share_mesh_and_wall_and_runs_are_short() -> void:
	var v: Dictionary = _report["variation_3_3"]
	assert_int(v["adjacent_same_mesh_wall"]).is_equal(0)
	assert_int(v["max_identical_run"]).is_less_equal(2)


func test_any_nine_neighbours_have_three_meshes_and_three_wall_colours() -> void:
	var v: Dictionary = _report["variation_3_3"]
	assert_int(v["windows_9"]).is_greater(500)
	assert_int(v["windows_9_below_3_variety"]).is_equal(0)


func test_unique_combinations_in_200m_windows_reach_sixty_percent() -> void:
	var f: Dictionary = _report["floors_unique"]
	assert_int(f["windows_unique"]).is_greater(5)
	assert_int(f["windows_unique_below_60pct"]).is_equal(0)
	assert_float(f["min_unique_ratio"]).is_greater_equal(0.6)


func test_clock_tower_ratio_is_within_spec_four_range() -> void:
	var t: Dictionary = _report["tower"]
	assert_float(t["tower_height_m"]).is_between(21.0, 25.0)
	assert_float(t["ratio"]).is_between(1.3, 1.8)
	assert_bool(t["ok"]).is_true()


func test_plaza_around_the_tower_is_free_of_buildings() -> void:
	assert_float(KitLabLayout.PLAZA.size.x).is_greater_equal(50.0)
	assert_float(KitLabLayout.PLAZA.size.y).is_greater_equal(50.0)
	for p in _layout.placements:
		var pos: Vector3 = p["pos"]
		assert_bool(KitLabLayout.PLAZA.has_point(Vector2(pos.x, pos.z))).is_false()


func test_metro_wide_tile_roof_share_and_tones_follow_spec_3_2() -> void:
	var all: Dictionary = (_report["roof_shares_by_zone"] as Dictionary)["_all"]
	assert_float(all["tile"]).is_less_equal(35.0)                       # metro genelinde kiremit ≤ %35
	assert_int(all["tile_tone_count"]).is_greater_equal(2)              # kiremit varsa ≥ 2 ton
	assert_float(all["r3_pct_of_tile"]).is_less_equal(40.0)             # R3 kiremit alanının ≤ %40'ı
	var w: Dictionary = _report["tile_500m_window"]
	assert_float(w["tile_pct"]).is_less_equal(55.0)                     # herhangi 500 × 500 m penceresi ≤ %55
	assert_int(w["windows"]).is_greater(5)


func test_flat_roofs_dominate_dense_zones_and_metal_dominates_industry() -> void:
	var by_zone: Dictionary = _report["roof_shares_by_zone"]
	assert_float(by_zone["dense"]["flat"]).is_between(55.0, 70.0)
	assert_float(by_zone["dense"]["tile"]).is_between(20.0, 35.0)
	assert_float(by_zone["industry"]["metal"]).is_between(55.0, 75.0)
	assert_float(by_zone["village"]["tile"]).is_greater(by_zone["village"]["flat"])


# --- Olumsuz varyantlar: sayaçlar ihlali yakalar ---------------------------------------------------------------

func test_negative_identical_neighbours_are_counted() -> void:
	var one := _layout.placements[0].duplicate()
	var bad: Array[Dictionary] = []
	for i in 12:
		var q := one.duplicate()
		q["pos"] = Vector3(i * 10.0, 0.0, 0.0)
		bad.append(q)
	var row: Array = range(12)
	var v := KitLabMetrics.variation_counters(bad, [row])
	assert_int(v["adjacent_same_mesh_wall"]).is_equal(11)
	assert_int(v["max_identical_run"]).is_greater(2)
	assert_int(v["windows_9_below_3_variety"]).is_greater(0)


func test_negative_all_tile_district_exceeds_the_tile_limit() -> void:
	var bad: Array[Dictionary] = []
	for p in _layout.placements:
		if str(p["entry"]["roof_type"]) in ["hip", "gable"]:
			bad.append(p)
	var sh := KitLabMetrics.roof_shares(bad)
	assert_float(sh["tile"]).is_greater(55.0)           # yalnız eğimli çatılar → kiremit payı kuralı ihlal edilir
	var window := KitLabMetrics.max_tile_share_window(bad, KitLabLayout.AREA, 500.0, 100.0, 5)
	assert_float(window["tile_pct"]).is_greater(55.0)


func test_negative_tall_frame_breaks_the_tower_ratio() -> void:
	var tall := _layout.placements[0].duplicate()
	tall["pos"] = Vector3(40.0, 0.0, 0.0)
	tall["entry"] = _lib.entry("bld_res_mid_d")      # 6 kat: 18,9 m parapet üstü
	tall["scale"] = Vector3.ONE
	var r := KitLabMetrics.tower_ratio([tall], 23.0)
	assert_bool(r["ok"]).is_false()                  # 23 / 18,9 = 1,22 < 1,3 → kule ezilir
	var squat := tall.duplicate()
	squat["entry"] = _lib.entry("bld_res_house_a")   # 1 kat ev: oran > 1,8
	assert_bool(KitLabMetrics.tower_ratio([squat], 23.0)["ok"]).is_false()
