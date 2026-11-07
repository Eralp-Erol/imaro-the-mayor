extends GdUnitTestSuite
## T-078 · Ekonomi bölge değiştirici kapısı (`EconomySystem.apply_region_modifier`): dış sistemlerin (komşu belediye,
## makro; M3) ekonomi bölge sütunlarına girdiği TEK nokta. Bugün çağıran yoktur; kapı davranışı burada kilitlenir.
## Olumsuz yollar durumu DEĞİŞTİRMEZ (hash aynı).

const W := preload("res://tests/sim/economy/economy_world.gd")
const S := preload("res://tests/sim/economy/economy_test_support.gd")


func _started() -> EconomyHandle:
	var h := W.handle()
	h.facade.advance(1)  # ekonomi durumu ilk tick'te kurulur
	return h


func _column(h: EconomyHandle, column: String, code: StringName) -> int:
	var regions: Dictionary = W.data(h.facade)["regions"]
	var index := (regions["codes"] as PackedStringArray).find(String(code))
	return int((regions[column] as PackedInt64Array)[index])


func test_latent_households_change_is_applied() -> void:
	var h := _started()
	var before := _column(h, "latent_hh", S.R1)
	var other_before := _column(h, "latent_hh", S.R2)
	assert_str(String(h.system.apply_region_modifier(h.facade.game_state(), S.R1, &"latent_hh", 250))).is_empty()
	assert_int(_column(h, "latent_hh", S.R1)).is_equal(before + 250)
	assert_int(_column(h, "latent_hh", S.R2)).is_equal(other_before)


func test_pm_columns_are_clamped_to_zero_one_thousand() -> void:
	var h := _started()
	var state := h.facade.game_state()
	assert_str(String(h.system.apply_region_modifier(state, S.R1, &"access_pm", 5000))).is_empty()
	assert_int(_column(h, "access_pm", S.R1)).is_equal(1000)
	assert_str(String(h.system.apply_region_modifier(state, S.R1, &"service_pm", -5000))).is_empty()
	assert_int(_column(h, "service_pm", S.R1)).is_equal(0)


func test_counts_do_not_go_negative() -> void:
	var h := _started()
	h.system.apply_region_modifier(h.facade.game_state(), S.R1, &"infra_cap", -1000000)
	assert_int(_column(h, "infra_cap", S.R1)).is_equal(0)


func test_gate_changes_the_state_hash_and_same_calls_give_same_hash() -> void:
	var a := _started()
	var b := _started()
	var untouched := a.facade.state_hash()
	a.system.apply_region_modifier(a.facade.game_state(), S.R1, &"latent_hh", 10)
	b.system.apply_region_modifier(b.facade.game_state(), S.R1, &"latent_hh", 10)
	assert_str(a.facade.state_hash()).is_not_equal(untouched)
	assert_str(a.facade.state_hash()).is_equal(b.facade.state_hash())


func test_economy_not_started_is_rejected() -> void:
	var h := W.handle()  # tick 0: ekonomi durumu henüz yok
	var hash_before := h.facade.state_hash()
	var reason := h.system.apply_region_modifier(h.facade.game_state(), S.R1, &"latent_hh", 10)
	assert_str(String(reason)).is_equal("economy.not_started")
	assert_str(h.facade.state_hash()).is_equal(hash_before)


func test_unknown_region_is_rejected_without_change() -> void:
	var h := _started()
	var hash_before := h.facade.state_hash()
	var reason := h.system.apply_region_modifier(h.facade.game_state(), &"NOPE", &"latent_hh", 10)
	assert_str(String(reason)).is_equal("gate.unknown_region")
	assert_str(h.facade.state_hash()).is_equal(hash_before)


func test_columns_outside_the_gate_whitelist_are_rejected() -> void:
	var h := _started()
	var hash_before := h.facade.state_hash()
	for column: StringName in [&"res_built", &"res_pipe", &"com_built", &"growth_frac", &"income_pm", &"nonsense"]:
		var reason := h.system.apply_region_modifier(h.facade.game_state(), S.R1, column, 5)
		assert_str(String(reason)).override_failure_message("'%s' kapıdan geçti" % column).is_equal("gate.unknown_column")
	assert_str(h.facade.state_hash()).is_equal(hash_before)
