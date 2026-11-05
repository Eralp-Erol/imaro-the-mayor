extends "res://tests/sim/politics/reaction_world_base.gd"
## D-021 · GOLDEN_X ile meclis güven kesintisi (`CouncilTrust`) ilişkisi. `golden_expropriation_undo_test.gd` senaryosu
## (kamulaştırmalı yol A' ayakta kalır: D1'de 16 hane yerinden edilir) kuralın eşiğini AŞAR; bu yüzden GOLDEN_X
## kural açıkken DEĞİŞİR (nedeni: `politics.council_trust` durumu + 3 üye için neden kaydı + sayaç). Bu test iki şeyi
## kilitler: (1) kural KAPALIYKEN aynı senaryo, D-021 ÖNCESİ kaydedilmiş GOLDEN_X'i bit-bit verir (yani değişikliğin
## TEK nedeni kural); (2) kural açıkken hash farklıdır ve fark kesinti durumundan gelir. Sabit burada TEKRARLANIR
## (golden dosyasına dokunulmaz); GOLDEN_X sahibin onayıyla yenilenirse bu sabit "kural kapalı" referansı olarak kalır.
## B-080 (ADR-0011): kural açıkken PE-03 `council.trust_gap` da kesinti sonrası güveni okur; bu yüzden (2) fark kesinti
## durumuna ek olarak `politics.events.last_pressure["PE-03"]` anahtarındadır (yalnız bu anahtar; kesintili koşuda
## büyük).

# B-130/D-026 ile yenilendi: eski c987fb3d9d6e338e2318902f8e5d73bdbeffb2f318442e1cfa07824193cd4094 (D-021 öncesi). Kural
# kapalıyken bile `bloc.react` petition eşiği 250 -> 190 kayıt eşiğini (hash'e girer) değiştirdi; bu sabit hâlâ "yalnız
# council_trust kuralı kapalı" referansıdır, yalnız bloc.react eşiğine göre yeniden alındı.
const GOLDEN_X_BEFORE_D021 := "92d1a99e9ef9b491683d790a7e8b5ca2f39510ba7114f1c2fde7e324e22c1ef6"
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
	var hash_off := _scenario(false).state_hash()
	assert_str(hash_off).override_failure_message(
		"kural kapalıyken GOLDEN_X (D-021 öncesi) değişmemeli; yenilenecekse: %s" % hash_off) \
		.is_equal(GOLDEN_X_BEFORE_D021)


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
	for system: String in ["economy", "public_works", "actors", "policy"]:
		var where := _diff(_scrub(state.systems.get(system, {})), _scrub(off_state.systems.get(system, {})), system)
		assert_str(where).override_failure_message("sistem değişti: " + where).is_empty()
	assert_array(_ledger(state)).is_not_empty()
	assert_array(_ledger(state)).is_equal(_ledger(off_state))
	# Siyaset: kesinti durumu, neden sayacı ve PE-03 son baskısı çıkarılınca (ve kayan neden numaraları temizlenince)
	# aynı. PE-03 baskısı B-080 (ADR-0011) ile BİLİNÇLİ farklıdır: `council.trust_gap` etkin güveni okur; fark yalnız bu
	# anahtarda ve kesintili koşuda büyüktür (aşağıda ayrıca iddia edilir).
	var pol_on: Dictionary = PoliticsState.data(state).duplicate(true)
	var pol_off: Dictionary = PoliticsState.data(off_state).duplicate(true)
	var pressure_on := int(pol_on["events"]["last_pressure"].get("PE-03", -1))
	var pressure_off := int(pol_off["events"]["last_pressure"].get("PE-03", -1))
	for pol: Dictionary in [pol_on, pol_off]:
		pol.erase(CouncilTrust.KEY)
		(pol["counters"] as Dictionary).erase("reason_records")
		(pol["events"]["last_pressure"] as Dictionary).erase("PE-03")
	var pol_where := _diff(_scrub(pol_on), _scrub(pol_off), "politics")
	assert_str(pol_where).override_failure_message("siyaset durumu kesinti dışında değişti: " + pol_where).is_empty()
	assert_int(pressure_off).override_failure_message("PE-03 baskısı taranmış olmalı").is_greater_equal(0)
	assert_int(pressure_on).override_failure_message("kesinti PE-03 baskısını artırmalı (B-080)") \
		.is_greater(pressure_off)


## İlk farklı yolun açıklaması ("" = eşit).
func _diff(a: Variant, b: Variant, path: String) -> String:
	var found := ""
	if a is Dictionary and b is Dictionary:
		var keys: Array = (a as Dictionary).keys()
		for key: Variant in (b as Dictionary):
			if not keys.has(key):
				keys.append(key)
		for key: Variant in keys:
			if not (a as Dictionary).has(key) or not (b as Dictionary).has(key):
				found = "%s/%s: anahtar yalnız birinde" % [path, str(key)]
			else:
				found = _diff(a[key], b[key], "%s/%s" % [path, str(key)])
			if not found.is_empty():
				break
	elif a is Array and b is Array:
		if (a as Array).size() != (b as Array).size():
			found = "%s: uzunluk %d != %d" % [path, (a as Array).size(), (b as Array).size()]
		else:
			for i in (a as Array).size():
				found = _diff(a[i], b[i], "%s[%d]" % [path, i])
				if not found.is_empty():
					break
	elif str(a) != str(b):
		found = "%s: %s != %s" % [path, str(a).left(80), str(b).left(80)]
	return found


## Neden kaydı numaraları (`reason_id`, `reason_ids`, `parent_ids`) kesinti kayıtları numara tükettiği için kayar;
## karşılaştırmadan önce silinir. Sözlük/dizi derin kopyalanır.
func _scrub(value: Variant) -> Variant:
	if value is Dictionary:
		var out := {}
		for key: Variant in (value as Dictionary):
			if str(key) in ["reason_id", "reason_ids", "parent_ids"]:
				continue
			out[key] = _scrub(value[key])
		return out
	if value is Array:
		var list: Array = []
		for item: Variant in (value as Array):
			list.append(_scrub(item))
		return list
	if (value is String or value is StringName) and str(value).begins_with("reason.") \
			and str(value).trim_prefix("reason.").is_valid_int():
		return "reason.#"  # kaynak referansı olarak saklanan neden numarası (aktör hafızası `source_ref`)
	return value


func _ledger(state: GameState) -> Array:
	var out: Array = []
	for entry: Dictionary in state.systems["budget"]["ledger"]:
		out.append([entry["tick"], entry["kind"], entry["amount"], entry["ref"]])
	return out
