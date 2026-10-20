extends GdUnitTestSuite
## T-005 ölçüt 1 · `settlement.json` kontrol verisi: şema, kanon (CAN-01/CAN-03), koordinat gömme YOK (WLD-01),
## palet satırı tek kaynağı (kit_palette.json) ile uyum. Her kuralın OLUMSUZ varyantı vardır.

const SOURCE_FILES: Array[String] = [
	"res://src/world/settlement/building_columns.gd", "res://src/world/settlement/t0_settlement.gd",
	"res://src/world/settlement/settlement_rules.gd", "res://src/world/settlement/settlement_lot.gd",
	"res://src/world/settlement/settlement_groups.gd", "res://src/world/settlement/settlement_invariants.gd",
	"res://src/world/settlement/settlement_stats.gd", "res://src/world/settlement/settlement_obb.gd",
]
const FORBIDDEN_NAMES: Array[String] = ["Ilgın", "Ilgin", "Konak", "Karşıyaka", "Bornova", "Alsancak", "Buca",
		"Bayraklı", "Çiğli", "Balçova", "Narlıdere", "Güzelbahçe", "Kemeraltı", "Gediz", "Kordon"]


func test_shipped_control_data_is_valid() -> void:
	var errors := SettlementRules.validate(SettlementTestSupport.control(), SettlementTestSupport.manifest())
	assert_array(errors).override_failure_message(str(errors)).is_empty()


func test_control_data_embeds_no_coordinates_and_no_real_names() -> void:
	var text := FileAccess.get_file_as_string(SettlementTestSupport.CONTROL_PATH)
	for key in SettlementRules.COORDINATE_KEYS:
		assert_bool(text.contains("\"%s\"" % key)).override_failure_message(key).is_false()
	for name in FORBIDDEN_NAMES:
		assert_bool(text.contains(name)).override_failure_message(name).is_false()
	assert_str(text).contains("ONAYLANMIŞ YÖN")


func test_palette_rows_match_the_kit_palette_single_source() -> void:
	var rows: Dictionary = SettlementTestSupport.control()["palette_rows"]
	var kit_rows: Array = SettlementTestSupport.palette()["rows"]
	for entry: Dictionary in kit_rows:
		var name := str(entry["name"])
		if name.begins_with("W") or name.begins_with("R") or name.begins_with("A") or name == "G1":
			assert_bool(rows.has(name)).override_failure_message("palette_rows eksik: %s" % name).is_true()
			assert_int(int(rows[name])).override_failure_message(name).is_equal(int(entry["row"]))
	for name: String in rows:
		var found := false
		for entry: Dictionary in kit_rows:
			found = found or (str(entry["name"]) == name and int(entry["row"]) == int(rows[name]))
		assert_bool(found).override_failure_message("palette_rows kit'te yok/uyuşmuyor: %s" % name).is_true()


func test_every_manifest_palette_row_name_resolves_to_a_row() -> void:
	var rules := SettlementTestSupport.rules()
	assert_int(rules.modules.size()).is_greater(20)
	for m in rules.modules:
		assert_bool(m.wall_rows.has(-1)).override_failure_message(m.id).is_false()
		assert_bool(m.roof_rows.has(-1)).override_failure_message(m.id).is_false()
		assert_bool(m.accent_rows.has(-1)).override_failure_message(m.id).is_false()


func test_zone_candidates_are_built_from_the_manifest_not_from_code() -> void:
	var rules := SettlementTestSupport.rules()
	var z := rules.zone(&"center")
	assert_object(z).is_not_null()
	assert_int(z.candidates.size()).is_greater(8)
	var ids := {}
	for m in z.candidates:
		ids[m.id] = true
		assert_bool(rules.module_by_id.has(m.id)).is_true()
	assert_bool(ids.has("bld_res_mid_a")).is_true()
	assert_bool(ids.has("bld_civ_hall_a")).override_failure_message("sivil yapı normal adaylarda olamaz").is_false()
	assert_bool(ids.has("bld_lmk_clocktower")).is_false()


# --- OLUMSUZ: bozulmuş veri kırmızı verir ---

func test_negative_unknown_family_is_rejected() -> void:
	var c := SettlementTestSupport.control()
	c["zones"]["center"]["family_weights"]["res_fantasy"] = 0.5
	var errors := SettlementRules.validate(c, SettlementTestSupport.manifest())
	assert_bool(" ".join(errors).contains("res_fantasy")).override_failure_message(str(errors)).is_true()


func test_negative_embedded_coordinate_is_rejected() -> void:
	var c := SettlementTestSupport.control()
	c["tower"]["center_km"] = [20.0, 18.0]
	var errors := SettlementRules.validate(c, SettlementTestSupport.manifest())
	assert_bool(" ".join(errors).contains("center_km")).override_failure_message(str(errors)).is_true()


func test_negative_unknown_palette_row_and_unordered_bands_are_rejected() -> void:
	var c := SettlementTestSupport.control()
	(c["palette_rows"] as Dictionary).erase("R3")
	var e1 := SettlementRules.validate(c, SettlementTestSupport.manifest())
	assert_bool(e1.is_empty()).is_false()
	var c2 := SettlementTestSupport.control()
	c2["regions"]["D1"]["bands"] = [{"max_t": 0.5, "zone": "center"}, {"max_t": 0.2, "zone": "dense"}]
	var e2 := SettlementRules.validate(c2, SettlementTestSupport.manifest())
	assert_bool(" ".join(e2).contains("artan")).override_failure_message(str(e2)).is_true()


func test_negative_civic_family_in_regular_weights_and_missing_tower_module_are_rejected() -> void:
	var c := SettlementTestSupport.control()
	c["zones"]["dense"]["family_weights"]["civ_hall"] = 0.1
	assert_bool(SettlementRules.validate(c, SettlementTestSupport.manifest()).is_empty()).is_false()
	var c2 := SettlementTestSupport.control()
	c2["tower"]["module"] = "bld_lmk_missing"
	assert_bool(SettlementRules.validate(c2, SettlementTestSupport.manifest()).is_empty()).is_false()


# --- Saflık (TEK-01/02): üretici kaynakları yasak API içermez; sim'e yazmaz (CAN-03) ---

func test_settlement_sources_are_pure_and_never_touch_simulation_state() -> void:
	for path in SOURCE_FILES:
		var hits := WorldTestSupport.forbidden_api_hits(path)
		assert_array(hits).override_failure_message("%s: %s" % [path, hits]).is_empty()
		var text := FileAccess.get_file_as_string(path)
		for banned in ["owner_id =", "owner_id=", "SimState", "GameState", "Simulation.", "SimFacade"]:
			assert_bool(text.contains(banned)).override_failure_message("%s: %s" % [path, banned]).is_false()
