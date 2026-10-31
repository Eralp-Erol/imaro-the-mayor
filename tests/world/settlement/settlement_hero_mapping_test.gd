extends GdUnitTestSuite
## T-062 A2 · T0 yerleşimin onaylı hero tablosuna eşlemesi (ADR-0006 §3.2; WLD-01, TEK-01/02, CAN-03):
## (i) reddedilmiş/onaysız kimlik yok, (ii) eşlenen her kimlik LibraryGate + katalogda approved, (iii) aynı
## tohum bayt-eşit,
## (iv) kat sayısı -> birim eşlemesi veriden (tablo `generator_params.floors`, ind_hero çalışma değeri işaretli).
## Her kural olumsuz varyantla kanıtlanır.

const SCAN := preload("res://tests/library/no_rejected_reference_scan_test.gd")
const MAPPING_PATH := "res://data/view/sim_building_mapping.json"
const CATALOG_PATH := "res://data/library/catalog.json"


static func _catalog_status() -> Dictionary:
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CATALOG_PATH))
	var out := {}
	for entry: Dictionary in catalog["entries"]:
		out[str(entry["id"])] = str(entry["approval"])
	return out


static func _columns_bytes(cols: BuildingColumns) -> Array[PackedByteArray]:
	return [cols.parcel_id.to_byte_array(), cols.module_idx.to_byte_array(), cols.x.to_byte_array(),
			cols.z.to_byte_array(), cols.yaw.to_byte_array(), cols.floors, cols.wall_row, cols.roof_row,
			cols.accent_row, cols.bright, cols.flags, cols.era]


# --- (i) reddedilmiş kimlik yok ---

func test_settlement_control_data_names_no_rejected_or_unapproved_identity() -> void:
	var text := FileAccess.get_file_as_string(SettlementTestSupport.CONTROL_PATH)
	var ids := SCAN.non_approved_ids()
	assert_int(ids.size()).is_equal(44)  # D-005: 45 rejected; D-012: veh_car onaylandi -> 44
	var hits := SCAN.find_tokens(text, ids)
	assert_array(Array(hits)).override_failure_message("settlement.json reddedilmiş kimlik: %s" % str(hits)).is_empty()


func test_negative_a_planted_rejected_identity_in_the_control_data_is_found() -> void:
	var planted := FileAccess.get_file_as_string(SettlementTestSupport.CONTROL_PATH) + ' "bld_res_old_c_gf": 0.9'
	assert_array(Array(SCAN.find_tokens(planted, SCAN.non_approved_ids()))).contains_exactly(["bld_res_old_c_gf"])


func test_no_generated_building_references_a_non_hero_module() -> void:
	var rules := SettlementTestSupport.full().rules
	for m in rules.modules:
		assert_str(m.id).override_failure_message(m.id).starts_with("bld_hero_")
	var cols := SettlementTestSupport.full().columns
	for i in cols.count:
		assert_int(cols.module_idx[i]).is_less(21)


# --- (ii) her eşlenen kimlik approved ---

func test_every_mapped_identity_is_approved_in_the_gate_and_the_catalog() -> void:
	var gate := LibraryGate.load_default()
	gate.report_errors = false
	assert_array(gate.load_errors).is_empty()
	var status := _catalog_status()
	var rules := SettlementTestSupport.rules()
	for m in rules.modules:
		assert_bool(gate.is_approved(m.id)).override_failure_message("kapıdan geçmiyor: %s" % m.id).is_true()
		assert_str(str(status.get(m.id, "yok"))).override_failure_message(m.id).is_equal("approved")
	var full := SettlementTestSupport.full()
	var used := {}
	for i in full.columns.count:
		used[full.module_of(i).id] = true
	assert_int(used.size()) \
			.override_failure_message("hero kimliklerinin hepsi kullanılmalı: %s" % str(used.keys())).is_equal(21)
	for id: String in used:
		assert_bool(gate.is_approved(id)).is_true()


func test_game_table_loader_passes_only_gate_approved_ids_and_counts_the_rest() -> void:
	var loaded := SettlementTable.load_game_table()
	var gate: LibraryGate = loaded["gate"]
	assert_int((loaded["table"]["modules"] as Array).size()).is_equal(21)
	assert_int(gate.unapproved_ids.size()).is_equal(0)


func test_negative_table_loader_drops_and_counts_a_planted_rejected_module() -> void:
	var table: Dictionary = SettlementTestSupport.manifest().duplicate(true)
	(table["modules"] as Array).append({"id": "bld_res_mid_a", "kind": "building", "family": "res_mid"})
	var gate := LibraryGate.load_default()
	gate.report_errors = false
	var out := SettlementTable.filter(table, gate)
	assert_int((out["modules"] as Array).size()).is_equal(21)
	assert_array(Array(gate.unapproved_ids)).contains_exactly(["bld_res_mid_a"])
	assert_str(gate.denial_log[0]["reason"]).is_equal("rejected")


func test_family_map_targets_and_sim_mapping_families_exist_in_the_table() -> void:
	var rules := SettlementTestSupport.rules()
	var families := {}
	for m in rules.modules:
		families[m.family] = true
	var fmap: Dictionary = SettlementTestSupport.control()["hero_family_map"]
	for key: String in fmap:
		assert_bool(families.has(str(fmap[key]))).override_failure_message("%s -> %s" % [key, fmap[key]]).is_true()
	var mapping: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MAPPING_PATH))
	for use: String in mapping["uses"]:
		if use.begins_with("_"):
			continue
		var entry: Dictionary = mapping["uses"][use]
		var shop := bool(entry["ground_shop"])
		for fam in entry["families"]:
			assert_bool(families.has(str(fam))).override_failure_message("%s: %s tabloda yok" % [use, fam]).is_true()
			var role: Dictionary = rules.family_roles[str(fam)]
			assert_bool(bool(role.get("ground_shop", false)) == shop) \
					.override_failure_message("%s: %s dükkân rolü uyuşmuyor" % [use, fam]).is_true()


func test_ground_shop_role_is_carried_only_by_the_bazaar_family() -> void:
	# Studio Director kararı 3: konut ailelerine dükkân varsayımı eklenmez.
	var full := SettlementTestSupport.full()
	var shops := 0
	for i in full.columns.count:
		var shop := (full.columns.flags[i] & BuildingColumns.FLAG_GROUND_SHOP) != 0
		var bazaar := full.module_of(i).family == "hero_com_bazaar"
		assert_bool(shop == bazaar) \
				.override_failure_message("yapı %d: dükkân bayrağı %s, bazaar %s" % [i, shop, bazaar]).is_true()
		shops += 1 if shop else 0
	assert_int(shops).is_greater(1000)


# --- (iii) bayt-eşit determinizm ---

func test_same_seed_two_runs_are_byte_identical_and_a_different_seed_is_not() -> void:
	var a := SettlementTestSupport.light_with(4242, SettlementTestSupport.control())
	var b := SettlementTestSupport.light_with(4242, SettlementTestSupport.control())
	var c := SettlementTestSupport.light_with(4243, SettlementTestSupport.control())
	var ba := _columns_bytes(a.columns)
	var bb := _columns_bytes(b.columns)
	var bc := _columns_bytes(c.columns)
	assert_int(a.columns.count).is_greater(1000)
	for k in ba.size():
		assert_bool(ba[k] == bb[k]).override_failure_message("sütun %d bayt-eşit değil" % k).is_true()
	var differs := false
	for k in ba.size():
		differs = differs or ba[k] != bc[k]
	assert_bool(differs).override_failure_message("tohum etkisiz").is_true()
	assert_str(a.columns.state_hash()).is_equal(b.columns.state_hash())
	assert_str(str(a.stats)).is_equal(str(b.stats))


# --- (iv) kat sayısı -> birim veriden ---

func test_module_floors_come_from_the_table_and_the_unknown_one_is_flagged_as_working_value() -> void:
	var table := SettlementTestSupport.manifest()
	var rules := SettlementTestSupport.rules()
	var working := 0
	for rec: Dictionary in table["modules"]:
		var m := rules.module(str(rec["id"]))
		var floors: Variant = (rec["generator_params"] as Dictionary)["floors"]
		if floors is float or floors is int:
			assert_int(m.floors).override_failure_message(m.id).is_equal(int(floors))
			assert_bool(m.floors_working_value).is_false()
		else:
			working += 1
			assert_str(str(floors)).is_equal("unknown")
			assert_str(m.family).is_equal("hero_ind_hero")
			assert_bool(m.floors_working_value).is_true()
			assert_int(m.floors).is_equal(int(rules.family_roles["hero_ind_hero"]["floors_unknown"]))
			assert_int(m.floors).is_equal(1)
	assert_int(working).is_equal(3)
	var expected := {"hero_old_core": 4, "hero_com_bazaar": 3, "hero_res_house": 2, "hero_res_mid": 6, "hero_res_late": 8,
			"hero_civ_hero": 3, "hero_ind_hero": 1}
	for m in rules.modules:
		assert_int(m.floors).override_failure_message(m.id).is_equal(int(expected[m.family]))


func test_t0_stock_units_equal_the_floor_sum_of_the_buildings_on_the_parcel() -> void:
	var mapping: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(MAPPING_PATH))
	assert_int(int(mapping["units_per_floor"])).is_equal(1)
	var res := SettlementTestSupport.light()
	var stock := PlayableStock.from_columns(res.columns)
	var res_units := {}
	var com_units := {}
	var cols := res.columns
	for i in cols.count:
		var pid := int(cols.parcel_id[i])
		var commercial := (cols.flags[i] & (BuildingColumns.FLAG_GROUND_SHOP | BuildingColumns.FLAG_INDUSTRY)) != 0
		var bucket: Dictionary = com_units if commercial else res_units
		bucket[pid] = int(bucket.get(pid, 0)) + int(res.module_of(i).floors)
	for pid in stock.parcel_ids():
		var r := int(res_units.get(int(pid), 0))
		var c := int(com_units.get(int(pid), 0))
		var want := c if c > r else r
		assert_int(stock.units_of(pid)).override_failure_message("parsel %d" % pid).is_equal(want)
		assert_str(String(stock.use_of(pid))).is_equal("commercial" if c > r else "residential")


func test_negative_changing_the_table_floors_changes_the_t0_stock() -> void:
	# Kat sayısı koda gömülü değil, tablodan gelir: hero_res_mid 6 -> 5 yapılınca o yapıların katı ve stok
	# birimi düşer.
	var table: Dictionary = SettlementTestSupport.manifest().duplicate(true)
	for rec: Dictionary in table["modules"]:
		if str(rec["family"]) == "hero_res_mid":
			(rec["generator_params"] as Dictionary)["floors"] = 5
	var base := SettlementTestSupport.light()
	var changed := T0Settlement.generate_detailed(base.net.world, base.net, table, SettlementTestSupport.SEED,
			SettlementTestSupport.control())
	var mids := 0
	for i in changed.columns.count:
		if changed.module_of(i).family == "hero_res_mid":
			assert_int(changed.columns.floors[i]).is_equal(5)
			mids += 1
	assert_int(mids).is_greater(100)
	var sum_base := 0
	var sum_changed := 0
	var stock_base := PlayableStock.from_columns(base.columns)
	for pid in stock_base.parcel_ids():
		sum_base += stock_base.units_of(pid)
	var stock_changed := PlayableStock.from_columns(changed.columns)
	for pid in stock_changed.parcel_ids():
		sum_changed += stock_changed.units_of(pid)
	assert_int(sum_changed).override_failure_message("stok değişmedi").is_not_equal(sum_base)
