extends "res://tests/sim/politics/reaction_world_base.gd"
## GOLDEN_X (ADR-0009 "GOLDEN_X sabitleme planı", T-065 P3) · "kamulaştırma + geri al + yolu yık" senaryosunun SABİT
## durum özeti. GOLDEN_A/B (tests/sim/m2_query_test.gd) kamulaştırma yolunu hiç çalıştırmaz; bu test siyaset (tepki
## defteri, haftalık tarama, PE-01 gündemi) + bütçe (yapım gideri, yıkım gideri, iade) + yol işlerini (kamulaştırma,
## klasik geri al, yolu yık) birlikte kilitler. T-065 (yeniden iskân politikası) bu sabiti DEĞİŞTİRMEDEN geçmelidir
## (politika kapalıyken bugünkü oyun bit-bit aynı).
##
## Dünya: ReactionWorldBase sahte kamulaştırma köprüsü (parsel 1-3 köşegende alınır) + gerçek `data/` dosyaları +
## `BudgetConfig.load_default()`. Yeniden üretme: `data/politics/reactions.json`,
## `data/sim/public_works/road_works.json` veya `data/sim/budget/budget_config.json` çalışma değeri (ya da bu üç
## sistemin kuralı) bilinçli değişirse sabit, gerekçesiyle ve AYRI commit'te yeniden alınır (aynen GOLDEN_A/B
## kuralı). Hash'i yeniden almak için testi çalıştırın; başarısızlık iletisi gerçek değeri yazar.

const GOLDEN_X := "c987fb3d9d6e338e2318902f8e5d73bdbeffb2f318442e1cfa07824193cd4094"
const FINAL_TICK := 60
const SAVE_TICK := 30
const SCAN_DAYS := 7


func _f(run: Dictionary) -> SimFacadeImpl:
	return (run["handle"] as PoliticsHandle).facade as SimFacadeImpl


## Taze dünya: yol yok, siyaset + bütçe bağlı, tick 1.
func _fresh() -> Dictionary:
	return _world(false, Callable(), [], true)


## Komut kabul edilmeli (yoksa hash anlamsızdır) ve bir tick sonra uygulanmış olmalı.
func _do(run: Dictionary, command: SimCommand) -> void:
	var r := _f(run).submit_command(command)
	assert_bool(r.is_rejected()).override_failure_message("%s reddedildi: %s" % [command.kind, r.reason_key]) \
		.is_false()
	_f(run).advance(1)


func _kinds(run: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for e in _f(run).events_since(0):
		if String(e.kind).begins_with("public_work."):
			out.append(String(e.kind))
	return out


## Senaryo adımları 1-3 (ADR-0009): tick 1 -> 30. Dönen koşu tick SAVE_TICK'te.
func _scenario_until_save_tick() -> Dictionary:
	var run := _fresh()
	var f := _f(run)
	# 1. Kamulaştırmalı yol A; ilk haftalık taramadan ÖNCE klasik geri al (pencere açık).
	_do(run, SimCommand.public_work_road(PackedInt64Array(DIAGONAL), &"local", true))
	assert_bool(f.undo_available()).is_true()
	_do(run, SimCommand.public_work_undo_last())
	assert_int(f.public_works().size()).is_equal(0)
	# 2. Aynı noktalara kamulaştırmalı yol A' (kabul edilmeli); 3 haftalık tarama geçsin.
	_do(run, SimCommand.public_work_road(PackedInt64Array(DIAGONAL), &"local", true))
	assert_int(f.public_works().size()).is_equal(1)
	f.advance(SCAN_DAYS * 3 + 1)
	assert_bool(f.undo_available()).is_false()  # tepki taramaya girdi: pencere kapandı
	# 3. Düz yol B; sonra B'yi yık.
	_do(run, SimCommand.public_work_road(P.spur_a_cm(), &"local", false))
	var road_b := f.public_works()[f.public_works().size() - 1].command_id
	_do(run, SimCommand.public_work_demolish(road_b))
	f.advance(SAVE_TICK - f.current_tick())
	assert_int(f.current_tick()).is_equal(SAVE_TICK)
	return run


func _scenario() -> SimFacadeImpl:
	var run := _scenario_until_save_tick()
	var f := _f(run)
	f.advance(FINAL_TICK - f.current_tick())
	assert_int(f.current_tick()).is_equal(FINAL_TICK)
	return f


func test_scenario_commands_all_take_effect_in_the_recorded_order() -> void:
	var run := _scenario_until_save_tick()
	assert_array(_kinds(run)).is_equal([
		"public_work.expropriated", "public_work.built", "public_work.restored", "public_work.removed",
		"public_work.expropriated", "public_work.built", "public_work.built", "public_work.demolished"])
	# A' ayakta (alınan parseller 1-3 hâlâ alınmış), B yıkılmış (satırı durur, hedef işaretli)
	var f := _f(run)
	for id in [1, 2, 3]:
		assert_str(String(f.parcel_views(PackedInt64Array([id]))[0].development)).is_equal("taken")
	assert_str(String(f.parcel_views(PackedInt64Array([5]))[0].development)).is_not_equal("taken")


## Hash'in "boş" bir senaryoyu kilitlemediğinin kanıtı: üç sistem de gerçekten iz bıraktı.
func test_the_locked_scenario_really_exercises_roads_politics_and_budget() -> void:
	var f := _scenario()
	var kinds := {}
	for entry: Dictionary in BudgetState.data(f.game_state())["ledger"]:
		kinds[String(entry["kind"])] = true
	assert_bool(kinds.has("road_cost")).is_true()
	assert_bool(kinds.has("road_refund")).override_failure_message("geri alma iadesi yok").is_true()
	assert_bool(kinds.has("road_demolish")).override_failure_message("yıkım gideri yok").is_true()
	var rows := PublicWorksState.reaction_rows(f.game_state(), "displaced", "D1").size() \
		+ PublicWorksState.reaction_rows(f.game_state(), "displaced", "D2").size()
	assert_int(rows).override_failure_message("A' için tepki defteri satırı yok").is_greater(0)
	assert_int(int(PoliticsState.data(f.game_state())["counters"]["scans"])).is_greater_equal(3)
	var opened: Dictionary = PoliticsState.data(f.game_state())["reaction_local"]["opened"]
	assert_int(opened.size()).override_failure_message("A' için PE-01 öğesi açılmadı").is_equal(1)


func test_state_hash_at_tick_60_is_the_recorded_golden() -> void:
	var hash_a := _scenario().state_hash()
	print("GOLDEN_X_CANDIDATE=%s" % hash_a)
	assert_str(hash_a).override_failure_message("GOLDEN_X yeniden alınacaksa: %s" % hash_a).is_equal(GOLDEN_X)


func test_a_second_run_with_the_same_seed_reaches_the_same_hash() -> void:
	assert_str(_scenario().state_hash()).is_equal(_scenario().state_hash())


func test_save_at_tick_30_then_load_and_continue_reaches_the_same_hash() -> void:
	var straight := _scenario().state_hash()
	var saved := _scenario_until_save_tick()
	var bytes := _f(saved).export_save()
	assert_int(bytes.size()).is_greater(0)
	var fresh := _fresh()
	var result := _f(fresh).import_save(bytes)
	assert_bool(result.ok).override_failure_message(result.message).is_true()
	assert_int(_f(fresh).current_tick()).is_equal(SAVE_TICK)
	_f(fresh).advance(FINAL_TICK - SAVE_TICK)
	assert_str(_f(fresh).state_hash()).is_equal(straight)

