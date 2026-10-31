extends "res://tests/sim/politics/reaction_world_base.gd"
## 2026-10-31 · Yerinden edilme MAHALLE ölçeğinde okunur (D-011, D-008 "halk tepki versin"). Gerçek Ismeral D2'de
## (hane 8686) kamulaştırmalı yolun yerinden ettiği hane bölge hanesinin yalnız 0-8 pm'i olduğu için bölge ölçekli
## gündem (20 pm) ve kesim payı (%10) kapıları HİÇ açılmıyordu. Yeni yol: yolun (komutun) kendi yerinden ettiği hane,
## `reactions.json` `local` bölümündeki mahalle büyüklüğüne (veri) göre okunur; yerinden edilen hane varsa komut başına
## BİR PE-01 öğesi + nedeni (`ReactionCause.record_local`); yerinden edilen 0 ise sessiz; yakındakiler (proximity)
## yalnız baskıyı artırır, tek başına öğe açmaz. Sayılar ÇALIŞMA MODELİ (F05-C).

const LOCAL_KEY := "reaction_local"
const CAUSE := "decision.bloc.expropriation_cause"
const F_DISPLACED := "reason.factor.displaced_households"
const F_PROXIMITY := "reason.factor.road_proximity"
const F_COUNT := "reason.factor.displaced_household_count"
## 1. ve 2. parsel konutlu (alınır), 6. yakın; hepsi boş: yol hane yerinden etmez ama 6. parsel yakında kalır.
const VACANT_ROWS: Array = [
	{"parcel_id": 5, "use": "residential", "units": 8, "owner": 1},
	{"parcel_id": 6, "use": "residential", "units": 6, "owner": 1}]


## Bölge ölçekli yolu kapatır (gerçek D2'deki durumun karşılığı: bölge payı eşiğin çok altında) ve `local` verisini
## düzenler.
func _local(changes: Dictionary = {}, close_region: bool = true) -> Callable:
	return func(files: Dictionary) -> void:
		files["reactions"] = _raw_reactions()
		if close_region:
			files["reactions"]["agenda"]["min_displacement_pm"] = 1500
		for k: String in changes:
			files["reactions"]["local"][k] = changes[k]


func _items(h: PoliticsHandle) -> Array:
	return pol(h)["events"]["agenda"]


## Yerinden edilmenin DOĞRUDAN açtığı öğeler: ateşleme gerekçesinde `reason.factor.displacement` parçası olanlar
## (dünyada başka şablonlar kendi nedenleriyle de gündeme girebilir; onlar sayılmaz).
func _local_items(h: PoliticsHandle) -> Array:
	return _items(h).filter(func(item: Dictionary) -> bool:
		for f: Dictionary in h.state().reasons.by_id(int(item["reason_id"]))["factors"]:
			if String(f["name"]) == "reason.factor.displacement":
				return true
		return false)


func _causes(h: PoliticsHandle) -> Array[Dictionary]:
	return reasons_of(h, CAUSE)


func _factor(rec: Dictionary, name: String) -> Dictionary:
	for f: Dictionary in rec["factors"]:
		if String(f["name"]) == name:
			return f
	return {}


func _cfg() -> Dictionary:
	return politics_config().reactions["local"]


# --- Saf okuma (veri sayıları) ---

func test_the_median_road_is_a_small_but_visible_reaction_and_a_large_road_is_clearly_stronger() -> void:
	var cfg := _cfg()
	var median := ReactionAgenda.local_reading(cfg, 6 * 1000, 19 * 500)  # q50: 6 hane yerinden, 19 hane yakın
	var q90 := ReactionAgenda.local_reading(cfg, 38 * 1000, 30 * 500)
	var biggest := ReactionAgenda.local_reading(cfg, 72 * 1000, 72 * 500)
	assert_bool(bool(median["opens"])).override_failure_message("6 hane görünür tepki açmalı").is_true()
	assert_bool(bool(q90["opens"]) and bool(biggest["opens"])).is_true()
	assert_int(int(median["pressure"])).override_failure_message("ortanca yol küçük").is_between(1, 400)
	assert_int(int(q90["pressure"])).override_failure_message("38 hane belirgin güçlü").is_greater_equal(
		3 * int(median["pressure"]))
	assert_int(int(biggest["pressure"])).is_greater_equal(int(q90["pressure"]))
	assert_int(int(biggest["pressure"])).is_less_equal(1000)


func test_zero_displaced_households_never_open_even_with_many_nearby_households() -> void:
	var cfg := _cfg()
	assert_bool(bool(ReactionAgenda.local_reading(cfg, 0, 0)["opens"])).is_false()
	var only_near := ReactionAgenda.local_reading(cfg, 0, 115 * 1000)  # en yakın yol örneğinin üst ucu
	assert_bool(bool(only_near["opens"])).override_failure_message("yakınlık tek başına açmaz").is_false()
	assert_int(int(only_near["displacement_pm"])).is_equal(0)


func test_proximity_adds_pressure_but_lighter_than_the_same_number_of_displaced_households() -> void:
	var cfg := _cfg()
	var base := int(ReactionAgenda.local_reading(cfg, 10 * 1000, 0)["pressure"])
	var more_near := int(ReactionAgenda.local_reading(cfg, 10 * 1000, 10 * 1000)["pressure"])
	var more_displaced := int(ReactionAgenda.local_reading(cfg, 20 * 1000, 0)["pressure"])
	assert_int(more_near).override_failure_message("yakınlık baskıyı artırmalı").is_greater(base)
	assert_int(more_near).override_failure_message("yakınlık yerinden edilmeden hafif").is_less(more_displaced)


func test_the_reading_scales_with_the_neighborhood_size_in_data_not_with_a_constant() -> void:
	var cfg := _cfg().duplicate()
	var small := int(ReactionAgenda.local_reading(cfg, 10 * 1000, 0)["displacement_pm"])
	cfg["neighborhood_households"] = int(cfg["neighborhood_households"]) * 2
	var big := int(ReactionAgenda.local_reading(cfg, 10 * 1000, 0)["displacement_pm"])
	assert_int(big * 2).is_between(small - 1, small + 1)


# --- Sim: gündem öğesi ve nedeni ---

func test_a_displacing_road_opens_one_pe01_item_even_when_the_region_scale_gate_is_closed() -> void:
	var h: PoliticsHandle = _world(true, _local())["handle"]
	var displaced: int = h.facade.public_works()[0].displaced_households
	assert_int(displaced).is_greater(0)
	h.facade.advance(14)
	assert_int(_local_items(h).size()).override_failure_message("yerinden edilme gündeme girmeli").is_equal(1)
	var item: Dictionary = _local_items(h)[0]
	assert_str(String(item["template"])).is_equal("PE-01")
	assert_str(String(item["bloc"])).is_equal(BLOC_HOUSED)  # yerinden edilenler barınan hane kohortundandı (veri)
	assert_str(String(item["region"])).is_equal("D1")
	assert_str(String(h.facade.agenda_items()[0].delivery)).is_equal("agenda")


func test_the_item_is_explained_by_a_cause_record_with_the_command_parcels_and_the_real_household_count() -> void:
	var h: PoliticsHandle = _world(true, _local())["handle"]
	h.facade.advance(14)
	var command := "command.%d" % h.facade.public_works()[0].command_id
	var item: Dictionary = _local_items(h)[0]
	var fire := h.facade.reason(int(item["reason_id"]))
	var cause_ids: Array = _causes(h).map(func(r: Dictionary) -> int: return int(r["id"]))
	var linked: Array = Array(fire.parent_ids).filter(func(id: Variant) -> bool: return cause_ids.has(int(id)))
	assert_int(linked.size()).override_failure_message("öğenin nedeni yerinden edilme kaydı").is_equal(1)
	var rec: Dictionary = h.state().reasons.by_id(int(linked[0]))
	assert_bool((rec["subjects"] as PackedStringArray).has(command)).is_true()
	assert_bool((rec["subjects"] as PackedStringArray).has("parcel.1")).is_true()
	assert_int(int(_factor(rec, F_COUNT)["value"])).is_equal(h.facade.public_works()[0].displaced_households)
	assert_int(int(_factor(rec, F_DISPLACED)["value"])).is_greater(0)
	assert_int(int(_factor(rec, F_PROXIMITY)["value"])).override_failure_message("yakınlık gerçek veriden").is_greater(0)
	assert_int(int(_factor(rec, F_PROXIMITY)["value"])).is_less(int(_factor(rec, F_DISPLACED)["value"]))
	assert_int(int(_factor(rec, F_DISPLACED)["weight"])).is_greater(int(_factor(rec, F_PROXIMITY)["weight"]))


func test_one_road_opens_one_item_only_not_a_stream_over_a_year() -> void:
	var h: PoliticsHandle = _world(true, _local())["handle"]
	var most_open := 0
	for _d in 400:
		h.facade.advance(1)
		var open := 0
		for item: Dictionary in _local_items(h):
			open += 1 if item["status"] == "open" else 0
		most_open = maxi(most_open, open)
	assert_int(_local_items(h).size()).override_failure_message("400 günde tek yol tek öğe").is_equal(1)
	assert_int(most_open).is_less_equal(1)
	assert_bool(pol(h).has(LOCAL_KEY)).is_true()
	assert_int((pol(h)[LOCAL_KEY]["opened"] as Dictionary).size()).is_equal(1)


func test_two_roads_open_two_items_one_after_the_other_never_a_burst() -> void:
	var h: PoliticsHandle = _world(true, _local())["handle"]
	h.facade.submit_command(SimCommand.public_work_undo_last())  # aynı parseller geri gelir; ikinci komut ayrı bir yol
	h.facade.advance(1)
	h.facade.submit_command(SimCommand.public_work_road(PackedInt64Array(DIAGONAL), &"local", true))
	h.facade.advance(1)
	assert_int(h.facade.public_works().size()).is_equal(1)
	var most_open := 0
	for _d in 400:
		h.facade.advance(1)
		var open := 0
		for item: Dictionary in _local_items(h):
			open += 1 if item["status"] == "open" else 0
		most_open = maxi(most_open, open)
	assert_int((pol(h)[LOCAL_KEY]["opened"] as Dictionary).size()).override_failure_message(
		"her yol (komut) kendi öğesini alır").is_equal(2)
	assert_int(_local_items(h).size()).is_equal(2)
	assert_int(most_open).override_failure_message("aynı anda tek yerinden edilme öğesi").is_less_equal(1)


func test_listening_to_the_local_item_leaves_the_group_more_trusting_than_ignoring_it() -> void:
	var trust := {}
	for answer in ["listen", ""]:
		var h: PoliticsHandle = _world(true, _local())["handle"]
		h.facade.advance(14)
		var item: Dictionary = _local_items(h)[0]
		assert_str(String(item["topic"])).override_failure_message("öğe nedeni konusunu taşır (veri)").is_equal(
			"housing_cost")
		if not answer.is_empty():
			Commands.submit(h.state(), AgendaRespondHandler.KIND, {"item_id": item["id"], "option_id": answer})
		h.facade.advance(20)
		var player := ActorStore.protagonist_key(h.state(), h.context.actors)
		trust[answer] = int(ActorStore.relation(h.state(), h.context.actors, BLOC_HOUSED, player)["trust"])
	assert_int(int(trust["listen"])).override_failure_message("dinleme güveni artırmalı: %s" % str(trust)) \
		.is_greater(int(trust[""]))


func test_a_road_that_displaces_nobody_is_silent_even_when_households_live_nearby() -> void:
	var h: PoliticsHandle = _world(true, _local(), VACANT_ROWS)["handle"]
	assert_int(h.facade.public_works()[0].displaced_households).is_equal(0)
	h.facade.advance(120)
	assert_int(PublicWorksState.reaction_rows(h.state(), "nearby", "D1").size()).override_failure_message(
		"yakın hane gerçekten sayılmış olmalı").is_greater(0)
	assert_int(_local_items(h).size()).override_failure_message("sahte tepki yok").is_equal(0)
	for rec in _causes(h):  # bölge ölçekli kesim tepkisi yakınlık kaydı yazabilir; yerinden edilen hane iddiası yok
		assert_int(int(_factor(rec, F_COUNT)["value"])).is_equal(0)
	assert_bool(pol(h).has(LOCAL_KEY)).is_false()


func test_the_threshold_and_scale_are_data_not_code() -> void:
	var strict: PoliticsHandle = _world(true, _local({"min_displacement_pm": 90000}))["handle"]
	strict.facade.advance(30)
	assert_int(_local_items(strict).size()).is_equal(0)
	var huge: PoliticsHandle = _world(true, _local({"neighborhood_households": 900000}))["handle"]
	huge.facade.advance(30)
	assert_int(_local_items(huge).size()).override_failure_message("mahalle büyüklüğü veriden").is_equal(0)
	var off: PoliticsHandle = _world(true, _local({"enabled": false}))["handle"]
	off.facade.advance(30)
	assert_int(_local_items(off).size()).is_equal(0)


func test_the_reaction_is_not_undone_when_the_road_is_undone() -> void:
	var h: PoliticsHandle = _world(true, _local())["handle"]
	h.facade.submit_command(SimCommand.public_work_undo_last())
	h.facade.advance(14)
	assert_int(_local_items(h).size()).override_failure_message("halk tepkisi geri alınmaz (D-011)").is_equal(1)


func test_runs_without_expropriation_never_write_the_local_state() -> void:
	var h: PoliticsHandle = _world(false, _local())["handle"]
	h.facade.advance(120)
	assert_bool(pol(h).has(LOCAL_KEY)).is_false()
	assert_int(_local_items(h).size()).is_equal(0)


# --- Determinizm, kayıt, CAN-03 ---

func test_same_commands_give_the_same_hash_with_the_local_item() -> void:
	var hashes: Array[String] = []
	for _i in 2:
		var h: PoliticsHandle = _world(true, _local())["handle"]
		h.facade.advance(60)
		assert_int(_local_items(h).size()).is_equal(1)
		hashes.append(h.facade.state_hash())
	assert_str(hashes[1]).is_equal(hashes[0])


func test_save_load_continue_equals_an_uninterrupted_run_with_the_local_item() -> void:
	var straight: PoliticsHandle = _world(true, _local())["handle"]
	straight.facade.advance(200)
	var first: PoliticsHandle = _world(true, _local())["handle"]
	first.facade.advance(20)
	assert_int(_local_items(first).size()).is_equal(1)
	var restored: PoliticsHandle = _world(false, _local())["handle"]
	var loaded := restored.facade.import_save(first.facade.export_save())
	assert_bool(loaded.ok).override_failure_message(loaded.message).is_true()
	assert_str(restored.facade.state_hash()).is_equal(first.facade.state_hash())
	restored.facade.advance(180)
	assert_str(restored.facade.state_hash()).is_equal(straight.facade.state_hash())
	assert_int(_local_items(restored).size()).override_failure_message("kayıt sonrası yeniden açılmamalı").is_equal(1)


func test_the_local_item_never_creates_a_private_building() -> void:
	var h: PoliticsHandle = _world(true, _local())["handle"]
	var before := 0
	for v in h.facade.parcel_views(h.facade.parcel_ids()):
		before += 1 if v.developed_by_sim else 0
	h.facade.advance(120)
	assert_int(_local_items(h).size()).is_equal(1)
	for id in [1, 2, 3]:
		assert_str(String(h.facade.parcel_views(PackedInt64Array([id]))[0].development)).is_equal("taken")
	var after := 0
	for v in h.facade.parcel_views(h.facade.parcel_ids()):
		after += 1 if v.developed_by_sim else 0
	assert_int(after).override_failure_message("CAN-03").is_greater_equal(before)


# --- Veri doğrulaması ---

func test_invalid_local_data_is_rejected_with_a_path() -> void:
	var cases := {
		"reactions.local.neighborhood_households": func(raw: Dictionary) -> void: raw["local"]["neighborhood_households"] = 0,
		"reactions.local.min_displacement_pm": func(raw: Dictionary) -> void: raw["local"]["min_displacement_pm"] = 0,
		"reactions.local.cohort": func(raw: Dictionary) -> void: raw["local"]["cohort"] = "nobody",
		"reactions.local": func(raw: Dictionary) -> void: raw["local"]["unknown_key"] = 1,
		"reactions.local.proximity_share_pm": func(raw: Dictionary) -> void: raw["local"]["proximity_share_pm"] = 2000,
	}
	for path: String in cases:
		var files := raw_politics()
		var raw := _raw_reactions()
		(cases[path] as Callable).call(raw)
		files["reactions"] = raw
		var cfg := PoliticsConfig.from_files(files, config())
		assert_bool(cfg.is_valid()).override_failure_message("geçerli sayıldı: %s" % path).is_false()
		assert_str(cfg.error).override_failure_message(path).contains(path)


func test_the_local_section_lives_outside_the_config_digest() -> void:
	var files := raw_politics()
	var without := PoliticsConfig.from_files(files, config())
	files["reactions"] = _raw_reactions()
	var with_local := PoliticsConfig.from_files(files, config())
	assert_bool(with_local.is_valid()).override_failure_message(with_local.error).is_true()
	assert_str(with_local.digest).is_equal(without.digest)
	assert_bool(bool(with_local.reactions["local"]["enabled"])).is_true()


func test_the_playable_politics_config_reads_the_reactions_data_file() -> void:
	# Oynanabilir yapılandırma `reactions.json`ı da okumalı: mahalle ölçeği sayıları ve yerinden edilme şikâyet kuralları
	# yoksa gerçek oyunda kod varsayılanı çalışır (veri dosyası ölü kalır).
	var playable := PlayablePolitics.config()
	assert_object(playable).is_not_null()
	var signals: Array = playable.cohort("housed")["grievance_rules"].map(
		func(rule: Dictionary) -> String: return String(rule["signal"]))
	assert_bool(signals.has("displacement")).override_failure_message(
		"reactions.json kesim kuralları yüklenmedi").is_true()
	var raw: Dictionary = _raw_reactions()["local"]
	for k: String in ["neighborhood_households", "min_displacement_pm", "full_displacement_pm", "proximity_share_pm"]:
		assert_int(int(playable.reactions["local"][k])).is_equal(int(raw[k]))
	assert_bool(bool(playable.reactions["local"]["enabled"])).is_true()
	# digest dışılığı: test_the_local_section_lives_outside_the_config_digest (aynı from_files yolu)


func test_without_a_reactions_file_the_local_reading_is_off_by_code_default() -> void:
	# Bayrak: kod varsayılanı KAPALI; yalnız `reactions.json` açar (dosyasız koşular ve GOLDEN A/B etkilenmez).
	assert_bool(bool(ReactionConfig.defaults()["local"]["enabled"])).is_false()
	var cfg := PoliticsConfig.from_files(raw_politics(), config())
	assert_bool(cfg.is_valid()).override_failure_message(cfg.error).is_true()
	assert_bool(bool(cfg.reactions["local"]["enabled"])).is_false()
