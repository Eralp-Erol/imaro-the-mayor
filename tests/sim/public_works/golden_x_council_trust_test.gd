extends "res://tests/sim/politics/reaction_world_base.gd"
## D-021 · GOLDEN_X ile meclis güven kesintisi (`CouncilTrust`) ilişkisi. `golden_expropriation_undo_test.gd` senaryosu
## (kamulaştırmalı yol A' ayakta kalır: D1'de 16 hane yerinden edilir) kuralın eşiğini AŞAR; bu yüzden GOLDEN_X
## kural açıkken DEĞİŞİR (nedeni: `politics.council_trust` durumu + 3 üye için neden kaydı + sayaç). Bu test iki şeyi
## kilitler: (1) kural KAPALIYKEN aynı senaryo, D-021 ÖNCESİ kaydedilmiş GOLDEN_X'i bit-bit verir (yani değişikliğin
## TEK nedeni kural); (2) kural açıkken hash farklıdır ve fark kesinti durumundan gelir. Sabit burada TEKRARLANIR
## (golden dosyasına dokunulmaz); GOLDEN_X sahibin onayıyla yenilenirse bu sabit "kural kapalı" referansı olarak kalır.

const GOLDEN_X_BEFORE_D021 := "c987fb3d9d6e338e2318902f8e5d73bdbeffb2f318442e1cfa07824193cd4094"
const FINAL_TICK := 60
const SCAN_DAYS := 7


func _f(run: Dictionary) -> SimFacadeImpl:
	return (run["handle"] as PoliticsHandle).facade as SimFacadeImpl


func _edit(enabled: bool) -> Callable:
	return func(files: Dictionary) -> void:
		files["reactions"] = _raw_reactions()
		files["reactions"]["council_trust"]["enabled"] = enabled


func _do(run: Dictionary, command: SimCommand) -> void:
	var r := _f(run).submit_command(command)
	assert_bool(r.is_rejected()).override_failure_message("%s reddedildi: %s" % [command.kind, r.reason_key]) \
		.is_false()
	_f(run).advance(1)


## `golden_expropriation_undo_test.gd` `_scenario()` ile AYNI adımlar (1-3), tick 60'a kadar.
func _scenario(enabled: bool) -> SimFacadeImpl:
	var run := _world(false, _edit(enabled), [], true)
	var f := _f(run)
	_do(run, SimCommand.public_work_road(PackedInt64Array(DIAGONAL), &"local", true))
	_do(run, SimCommand.public_work_undo_last())
	_do(run, SimCommand.public_work_road(PackedInt64Array(DIAGONAL), &"local", true))
	f.advance(SCAN_DAYS * 3 + 1)
	_do(run, SimCommand.public_work_road(P.spur_a_cm(), &"local", false))
	var road_b := f.public_works()[f.public_works().size() - 1].command_id
	_do(run, SimCommand.public_work_demolish(road_b))
	f.advance(FINAL_TICK - f.current_tick())
	assert_int(f.current_tick()).is_equal(FINAL_TICK)
	return f


func test_with_the_rule_off_the_golden_x_scenario_is_bit_identical_to_the_pre_d021_value() -> void:
	assert_str(_scenario(false).state_hash()).override_failure_message(
		"kural kapalıyken GOLDEN_X (D-021 öncesi) değişmemeli").is_equal(GOLDEN_X_BEFORE_D021)


func test_with_the_rule_on_the_hash_differs_only_because_the_cut_state_exists() -> void:
	var on := _scenario(true)
	var off := _scenario(false)
	assert_str(on.state_hash()).is_not_equal(off.state_hash())
	var state := (on as SimFacadeImpl).game_state()
	var trust: Dictionary = PoliticsState.data(state).get(CouncilTrust.KEY, {})
	assert_bool(trust.is_empty()).override_failure_message("kesinti durumu yazılmış olmalı").is_false()
	# Kesinti durumu dışında oyun aynıdır: ekonomi ve yol işleri bit-bit aynı; bütçe defteri (tick, tür, tutar, referans)
	# aynı (kalemlerin `reason_id`si kayıt numarası kaydığı için KARŞILAŞTIRILMAZ: yeni neden kayıtları numara tüketir).
	var off_state := (off as SimFacadeImpl).game_state()
	for system: String in ["economy", "public_works"]:
		assert_str(str(state.systems.get(system, {}))).override_failure_message("sistem değişti: " + system) \
			.is_equal(str(off_state.systems.get(system, {})))
	assert_array(_ledger(state)).is_not_empty()
	assert_array(_ledger(state)).is_equal(_ledger(off_state))


func _ledger(state: GameState) -> Array:
	var out: Array = []
	for entry: Dictionary in state.systems["budget"]["ledger"]:
		out.append([entry["tick"], entry["kind"], entry["amount"], entry["ref"]])
	return out
