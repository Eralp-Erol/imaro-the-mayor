extends "res://tests/sim/politics/reaction_world_base.gd"
## 2026-11-01 · D-014 §3 (KULLANICI): evi yıkılanın ve yakınında/yol dibinde oturanın tepkisi YÜKSEK; ilçe geneli çok az
## ama SIFIR DEĞİL. "Yeni ev sunulursa tepki hiç olmaz" için sim'de mekanizma YOK (haneler yalnız bölge toplamı); o
## kısım uygulanmadı: tepkinin "yeniden yerleşti mi" kararı TEK noktada (`ReactionRehousing.still_unhoused`) ve
## şimdilik hep "hayır" (davranış değişmez). Sayılar ÇALIŞMA MODELİ (F05-C).

const REGION := "D1"
const SEEK_TOPIC := "housing_cost"


func _setup(changes: Dictionary = {}) -> Callable:
	return func(files: Dictionary) -> void:
		files["reactions"] = _raw_reactions()
		files["reactions"]["agenda"]["min_displacement_pm"] = 1500  # bölge ölçekli yol kapalı (gerçek D2 durumu)
		for cohort: String in files["reactions"]["cohorts"]:  # bölge sinyali kuralları sessiz (D2'de kesim payı kapısı)
			for rule: Dictionary in files["reactions"]["cohorts"][cohort].get("grievance_rules", []):
				rule["gain"] = 0
		for k: String in changes:
			files["reactions"]["local"][k] = changes[k]


func _items(h: PoliticsHandle) -> Array:
	return pol(h)["events"]["agenda"].filter(func(item: Dictionary) -> bool:
		for f: Dictionary in h.state().reasons.by_id(int(item["reason_id"]))["factors"]:
			if String(f["name"]) == "reason.factor.displacement":
				return true
		return false)


func _unhoused(h: PoliticsHandle, code: String = REGION) -> int:
	for row in EconomyQuery.region_stats(h.state(), h.context.economy):
		if String(row["code"]) == code:
			return int(row["latent_hh"]) - int(row["housed_hh"])
	return -1


## Yatırımcıların bölgeye `homes` konut daha bitirmesi (bölge biten konutu artar).
func _build_homes(h: PoliticsHandle, homes: int, code: String = REGION) -> void:
	var regions: Dictionary = EconomyState.data(h.state())["regions"]
	var r := (regions["codes"] as PackedStringArray).find(code)
	var built: PackedInt64Array = regions["res_built"]
	built[r] += homes


func _grievance(h: PoliticsHandle, key: String = BLOC_HOUSED) -> int:
	return int(ActorStore.actor_ref(h.state(), key)["state"].get("grievances", {}).get(SEEK_TOPIC, 0))


# --- TEK "yeniden yerleşti mi" giriş noktası: şimdilik hep "hayır" ---

func test_the_rehousing_entry_point_says_everyone_is_still_unhoused_for_any_household_row() -> void:
	assert_int(ReactionRehousing.still_unhoused("D1", 1, 10)).is_equal(10)
	assert_int(ReactionRehousing.still_unhoused("D2", 77, 1)).is_equal(1)
	assert_int(ReactionRehousing.still_unhoused("D1", 1, 0)).is_equal(0)


func test_new_homes_in_the_region_do_not_end_the_reaction_because_the_sim_has_no_rehousing_yet() -> void:
	var h: PoliticsHandle = _world(true, _setup())["handle"]
	_build_homes(h, _unhoused(h))
	assert_int(_unhoused(h)).override_failure_message("bölgede barınamayan kalmadı").is_equal(0)
	h.facade.advance(14)
	assert_int(_items(h).size()).override_failure_message("şimdilik tepki yeni evden etkilenmez").is_equal(1)


# --- Yüksek yerel tepki ---

func test_one_evicted_household_is_already_a_high_reaction_and_nobody_evicted_is_none() -> void:
	var cfg: Dictionary = politics_config().reactions["local"]
	var one := ReactionAgenda.local_reading(cfg, 1000, 0)
	assert_bool(bool(one["opens"])).override_failure_message("tek yıkılan ev tepki açmalı").is_true()
	assert_int(int(one["pressure"])).override_failure_message("yıkılan evin sahibi: yüksek").is_greater_equal(600)
	var near_only := ReactionAgenda.local_reading(cfg, 0, 30 * 1000)
	assert_bool(bool(near_only["opens"])).is_false()
	assert_int(int(ReactionAgenda.local_reading(cfg, 0, 0)["pressure"])).is_equal(0)


func test_neighbours_at_the_road_edge_react_strongly_but_lighter_than_the_evicted() -> void:
	var cfg: Dictionary = politics_config().reactions["local"]
	var evicted := int(ReactionAgenda.local_reading(cfg, 10 * 1000, 0)["level_pm"])
	var both := int(ReactionAgenda.local_reading(cfg, 10 * 1000, 10 * 500)["level_pm"])
	assert_int(both - evicted).override_failure_message("yol dibindakiler baskıyı belirgin artırır").is_greater_equal(
		evicted / 4)
	assert_int(both).is_less(2 * evicted)


func test_the_floor_is_data_and_the_biggest_road_still_reaches_the_ceiling() -> void:
	var cfg: Dictionary = politics_config().reactions["local"]
	assert_int(int(ReactionAgenda.local_reading(cfg, 72 * 1000, 72 * 500)["pressure"])).is_equal(1000)
	var off: Dictionary = cfg.duplicate()
	off["floor_pressure_pm"] = 0
	assert_int(int(ReactionAgenda.local_reading(off, 1000, 0)["pressure"])).override_failure_message(
		"taban kapalıyken eski küçük baskı").is_less(100)


func test_a_small_displacing_road_opens_an_item_with_a_high_pressure_in_the_world() -> void:
	var h: PoliticsHandle = _world(true, _setup())["handle"]
	h.facade.advance(14)
	assert_int(_items(h).size()).is_equal(1)
	var fire: Dictionary = h.state().reasons.by_id(int(_items(h)[0]["reason_id"]))
	var pressure := 0
	for f: Dictionary in fire["factors"]:
		if String(f["name"]) == "reason.factor.displacement":
			pressure = int(f["value"])
	assert_int(pressure).override_failure_message("öğe baskısı yüksek (>= taban)").is_greater_equal(600)


# --- İlçe geneli: çok az ama sıfır değil ---

func test_the_district_feels_a_tiny_nonzero_grievance_while_the_displacement_lasts() -> void:
	var h: PoliticsHandle = _world(true, _setup())["handle"]
	assert_int(_grievance(h)).is_equal(0)
	h.facade.advance(60)
	var g := _grievance(h)
	assert_int(g).override_failure_message("ilçe geneli sıfır olmamalı").is_greater(0)
	assert_int(g).override_failure_message("ilçe geneli çok az: %d" % g).is_less(100)


func test_no_expropriation_means_no_district_grievance_at_all() -> void:
	var h: PoliticsHandle = _world(false, _setup())["handle"]
	h.facade.advance(120)
	assert_int(_grievance(h)).is_equal(0)
	assert_bool(pol(h).has("reaction_local")).is_false()


func test_with_the_new_data_off_the_district_stays_silent_as_before() -> void:
	var off := {"floor_pressure_pm": 0, "district_floor": 0, "district_gain": 0}
	var h: PoliticsHandle = _world(true, _setup(off))["handle"]
	h.facade.advance(60)
	assert_int(_items(h).size()).is_equal(1)
	assert_int(_grievance(h)).is_equal(0)


# --- Yol/olay kimliğine bağlı tepkiyi kaldırma girişi (geri alma kancası) ---

func test_retracting_a_command_before_the_scan_leaves_no_item_and_no_district_grievance() -> void:
	var h: PoliticsHandle = _world(true, _setup())["handle"]
	var command: int = h.facade.public_works()[0].command_id
	assert_int(PublicWorksState.reaction_rows(h.state(), "displaced", REGION).size()).is_equal(1)
	var removed := ReactionAgenda.retract_command(h.state(), command)
	assert_int(removed).override_failure_message("bir hane + bir yakınlık satırı").is_equal(2)
	assert_int(PublicWorksState.reaction_rows(h.state(), "displaced", REGION).size()).is_equal(0)
	assert_int(PublicWorksState.reaction_rows(h.state(), "nearby", REGION).size()).is_equal(0)
	h.facade.advance(60)
	assert_int(_items(h).size()).override_failure_message("kaldırılan yolun tepkisi yok").is_equal(0)
	assert_int(_grievance(h)).is_equal(0)


func test_retracting_one_command_keeps_the_other_commands_reaction() -> void:
	var h: PoliticsHandle = _world(true, _setup())["handle"]
	var own: int = h.facade.public_works()[0].command_id
	var rows: Array = (PublicWorksState.data(h.state())["displaced"] as Dictionary)[REGION]
	rows.append([h.state().tick, 3, own + 90])
	assert_int(ReactionAgenda.retract_command(h.state(), own + 90)).is_equal(1)
	var left := PublicWorksState.reaction_rows(h.state(), "displaced", REGION)
	assert_int(left.size()).is_equal(1)
	assert_int(int(left[0][2])).is_equal(own)


func test_retracting_an_unknown_command_changes_nothing() -> void:
	var h: PoliticsHandle = _world(true, _setup())["handle"]
	var before := h.facade.state_hash()
	assert_int(ReactionAgenda.retract_command(h.state(), 9999)).is_equal(0)
	assert_str(h.facade.state_hash()).is_equal(before)


func test_retracting_without_any_reaction_ledger_is_harmless() -> void:
	var h: PoliticsHandle = _world(false, _setup())["handle"]
	assert_int(ReactionAgenda.retract_command(h.state(), 1)).is_equal(0)


# --- Determinizm, kayıt ---

func test_same_commands_same_hash_and_save_resumes_with_the_district_grievance() -> void:
	var hashes: Array[String] = []
	for _i in 2:
		var h: PoliticsHandle = _world(true, _setup())["handle"]
		h.facade.advance(90)
		hashes.append(h.facade.state_hash())
	assert_str(hashes[1]).is_equal(hashes[0])
	var straight: PoliticsHandle = _world(true, _setup())["handle"]
	straight.facade.advance(120)
	var first: PoliticsHandle = _world(true, _setup())["handle"]
	first.facade.advance(30)
	var restored: PoliticsHandle = _world(false, _setup())["handle"]
	assert_bool(restored.facade.import_save(first.facade.export_save()).ok).is_true()
	assert_str(restored.facade.state_hash()).is_equal(first.facade.state_hash())
	restored.facade.advance(90)
	assert_str(restored.facade.state_hash()).is_equal(straight.facade.state_hash())


# --- Veri doğrulaması ---

func test_invalid_new_local_data_is_rejected_with_a_path() -> void:
	var cases := {
		"reactions.local.floor_pressure_pm": 2000,
		"reactions.local.district_floor": -1,
		"reactions.local.district_gain": "many",
	}
	for path: String in cases:
		var files := raw_politics()
		var raw := _raw_reactions()
		raw["local"][path.get_slice(".", 2)] = cases[path]
		files["reactions"] = raw
		var cfg := PoliticsConfig.from_files(files, config())
		assert_bool(cfg.is_valid()).override_failure_message("geçerli sayıldı: %s" % path).is_false()
		assert_str(cfg.error).override_failure_message(path).contains(path)


func test_code_defaults_keep_the_new_behaviour_off() -> void:
	var d: Dictionary = ReactionConfig.defaults()["local"]
	assert_int(int(d["floor_pressure_pm"])).is_equal(0)
	assert_int(int(d["district_floor"])).is_equal(0)
	assert_int(int(d["district_gain"])).is_equal(0)
