extends "res://tests/sim/politics/reaction_world_base.gd"
## B-007 / B-008 (QA 2026-11-01): yıkımlı yolun tepkisi (PE-01, `reactions.json` `local`). B-007: 1-4 hane yerinden eden
## yol sessiz kalmamalı (haftalık tarama yaşında günlük sönümle eşiğin altına düşmemeli); B-008: art arda iki yol = iki
## ayrı tepki, ikincisi ilk öğenin kapanmasını beklemez (`independent_items`). Sayılar ÇALIŞMA MODELİ (F05-C).

const LOCAL_KEY := "reaction_local"
const REASON := "reason.factor.displacement"


func _local(changes: Dictionary = {}) -> Callable:
	return func(files: Dictionary) -> void:
		files["reactions"] = _raw_reactions()
		files["reactions"]["agenda"]["min_displacement_pm"] = 1500  # bölge ölçekli yol kapalı (gerçek D2 durumu)
		for k: String in changes:
			files["reactions"]["local"][k] = changes[k]


func _cfg() -> Dictionary:
	return politics_config().reactions["local"]


func _local_items(h: PoliticsHandle) -> Array:
	return pol(h)["events"]["agenda"].filter(func(item: Dictionary) -> bool:
		for f: Dictionary in h.state().reasons.by_id(int(item["reason_id"]))["factors"]:
			if String(f["name"]) == REASON:
				return true
		return false)


## D-014 §1: klasik geri alma yolun tepkisini siler; bu yüzden "art arda iki yol" geri alma ile değil iki GERÇEK yolla
## kurulur (ikincisi parsel 6'yı alır; ilk yol durur).
func _build_second_road(w: Dictionary) -> void:
	var h: PoliticsHandle = w["handle"]
	(w["fake"] as FakeExpropriationWorld).take(P.spur_b_cm(), [6])
	h.facade.submit_command(SimCommand.public_work_road(P.spur_b_cm(), &"local", true))
	h.facade.advance(1)
	assert_int(h.facade.public_works().size()).is_equal(2)


func test_two_roads_in_a_row_open_two_separate_items_the_second_without_delay() -> void:
	# B-008: eskiden ikinci yolun öğesi ilk öğenin kapanmasını (~30 gün) beklerdi (PE-01 mutex + bekleme).
	var w := _world(true, _local())
	var h: PoliticsHandle = w["handle"]
	_build_second_road(w)
	h.facade.advance(14)
	assert_int((pol(h)[LOCAL_KEY]["opened"] as Dictionary).size()).override_failure_message(
		"her yol (komut) 14 gün içinde kendi öğesini alır").is_equal(2)
	assert_int(_local_items(h).size()).is_equal(2)
	for _d in 400:
		h.facade.advance(1)
	assert_int(_local_items(h).size()).override_failure_message("yağmur yok: tam iki öğe").is_equal(2)


func test_with_independent_items_off_the_second_road_waits_for_the_first_item_as_before() -> void:
	var w := _world(true, _local({"independent_items": false}))
	var h: PoliticsHandle = w["handle"]
	_build_second_road(w)
	h.facade.advance(15)
	assert_int(_local_items(h).size()).override_failure_message("bayrak kapalı: ikinci öğe bekler").is_equal(1)


func test_a_four_household_road_and_a_one_household_road_are_not_silent_at_any_scan_age() -> void:
	# B-007: eskiden 4 hane ilk taramada (yaş >= 1 gün) 19 pm'e düşüp eşiğin (20) altında kalırdı.
	var cfg := _cfg()
	var window := 360
	for households in [1, 2, 3, 4]:
		for age in [0, 1, 6, 7, 13]:  # haftalık tarama yaşları
			var milli: int = households * 1000 * (window - age) / window
			var reading := ReactionAgenda.local_reading(cfg, milli, 0)
			assert_bool(bool(reading["opens"])).override_failure_message(
				"%d hane, yaş %d gün sessiz kaldı" % [households, age]).is_true()
			assert_int(int(reading["displacement_pm"])).is_greater_equal(1)
	assert_bool(bool(ReactionAgenda.local_reading(cfg, 0, 0)["opens"])).override_failure_message(
		"0 hane yine sessiz").is_false()
