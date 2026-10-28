extends GdUnitTestSuite
## T-062 B0 · bitki tablosu (LibraryGate) + yerleşim kuralları (vegetation.json): yalnız onaylı/hash eşleşen türler,
## onaysız tür asla yüklenmez (fail-closed), kural doğrulaması olumsuz örneklerle, kurallar-veri tutarlılığı.

const PLANTS := "res://data/library/game_plants.json"
const FURNITURE := "res://data/library/game_furniture.json"


func _gate_with(plants_text: String, catalog: Dictionary) -> LibraryGate:
	var gate := LibraryGate.new()
	gate.report_errors = false
	gate.load_catalog_text(JSON.stringify({"entries": _entries(catalog)}), "cat")
	gate.add_table_text(plants_text, "plants")
	return gate


static func _entries(approvals: Dictionary) -> Array:
	var out: Array = []
	for id in approvals:
		out.append({"id": id, "approval": approvals[id]})
	return out


static func _table(records: Array) -> String:
	return JSON.stringify({"format": "imaro-game-set/1", "table": "vegetation", "plants": records,
			"unapproved": {"count": 0, "entries": []}})


func test_species_come_only_from_the_gate_and_cover_the_ten_approved_plants() -> void:
	var species := VegetationSpecies.load_default()
	assert_int(species.size()).is_equal(10)
	assert_int(species.gate.unapproved_ids.size()).is_equal(0)
	for k in species.size():
		assert_bool(species.gate.is_approved(species.ids[k])).is_true()
		assert_float(species.reach_m[k]).is_greater(0.0)
		assert_int(species.tris_lod0[k]).is_greater(species.tris_lod1[k] - 1)
	assert_array(Array(species.keys)).contains_exactly_in_any_order(["cypress", "hedge", "maquis", "olive_open",
			"olive_twisted", "palm_date", "palm_slender", "pine_brutia", "pine_stone", "plane"])
	assert_bool(species.has_proxy(species.index_of("palm_date"))).is_true()
	assert_bool(species.has_proxy(species.index_of("plane"))).is_false()
	assert_bool(species.has_key("veg_plane")).is_false()


func test_default_gate_tables_do_not_change_for_building_and_ground_consumers() -> void:
	var gate := LibraryGate.load_default()
	assert_int(gate.approved_ids_of("buildings").size()).is_equal(21)
	assert_int(gate.approved_ids_of("ground").size()).is_equal(14)
	assert_int(gate.approved_ids_of("vegetation").size()).is_equal(0)
	assert_bool(gate.is_approved("veg_hero_plane_a")).is_false()


func test_negative_unapproved_plants_never_enter_the_species_table() -> void:
	var record := {"id": "veg_hero_plane_a", "species": "plane", "reach_m": 5.0, "height_m": 13.0,
			"lods": {"LOD0": {"tris": 10}, "LOD1": {"tris": 5}}}
	# Katalogda rejected: tablonun tamamı kapanır (fail-closed), tür yok.
	var gate := _gate_with(_table([record]), {"veg_hero_plane_a": "rejected"})
	var species := VegetationSpecies.from_gate(gate)
	assert_int(species.size()).is_equal(0)
	assert_int(gate.load_errors.size()).is_equal(1)
	# Katalogda proposed ya da hiç yok: aynı.
	for status in ["proposed", "hold"]:
		var g2 := _gate_with(_table([record]), {"veg_hero_plane_a": status})
		assert_int(VegetationSpecies.from_gate(g2).size()).is_equal(0)
	var g3 := _gate_with(_table([record]), {})
	assert_int(VegetationSpecies.from_gate(g3).size()).is_equal(0)
	# Onaylı: girer.
	var g4 := _gate_with(_table([record]), {"veg_hero_plane_a": "approved"})
	assert_int(VegetationSpecies.from_gate(g4).size()).is_equal(1)
	assert_int(g4.approved_ids_of("vegetation").size()).is_equal(1)


func test_negative_generation_refuses_without_species_and_reports_the_reason() -> void:
	var empty := VegetationSpecies.from_gate(_gate_with(_table([]), {}))
	assert_int(empty.size()).is_equal(0)
	var rules := VegetationRules.from_control(VegetationTestSupport.control(), empty)
	assert_bool(rules.is_valid()).is_false()
	var cols := VegetationPlacement.generate(SettlementTestSupport.light(), empty, rules, 1, false)
	assert_int(cols.count).is_equal(0)
	assert_str(str(cols.stats.get("error", ""))).is_not_empty()
	assert_array(Array(cols.shape_errors())).is_empty()


func test_committed_rules_are_valid_and_reference_only_table_species() -> void:
	var rules := VegetationTestSupport.rules()
	assert_array(Array(rules.errors)).is_empty()
	var species := VegetationTestSupport.species()
	for key: String in rules.cfg["species"]:
		assert_bool(species.has_key(key)).is_true()
	assert_int(rules.scale_lo.size()).is_equal(species.size())
	for k in species.size():
		assert_float(rules.scale_lo[k]).is_greater(0.0)
		assert_float(rules.scale_hi[k]).is_greater_equal(rules.scale_lo[k])


func test_negative_rules_validation_catches_bad_data() -> void:
	var species := VegetationTestSupport.species()
	var cases := {
		"unknown species": func(c: Dictionary) -> void: c["street"]["weights"]["core"]["veg_plane"] = 1.0,
		"zero weight sum": func(c: Dictionary) -> void: c["coast"]["weights"] = {"pine_brutia": 0.0},
		"negative weight": func(c: Dictionary) -> void: c["yard"]["groups"]["urban"]["plane"] = -1.0,
		"bad layer order": func(c: Dictionary) -> void: c["budget"]["layer_order"] = ["street", "yard"],
		"no budget": func(c: Dictionary) -> void: c["budget"]["max_instances"] = 0,
		"slope above cliff": func(c: Dictionary) -> void: c["terrain"]["max_slope_deg"]["rural"] = 80.0,
		"scale inverted": func(c: Dictionary) -> void: c["species"]["plane"]["scale"] = [1.2, 0.8],
		"cluster band": func(c: Dictionary) -> void: c["clusters"]["lo"] = 0.9,
		"zone group missing": func(c: Dictionary) -> void: c["zone_groups"]["town"] = "nowhere",
		"yard group missing": func(c: Dictionary) -> void: c["yard"]["zones"]["town"]["group"] = "nowhere",
		"wrong schema": func(c: Dictionary) -> void: c["schema_version"] = 99,
		"missing section": func(c: Dictionary) -> void: c.erase("hedge"),
	}
	for label: String in cases:
		var ctl := VegetationTestSupport.control()
		(cases[label] as Callable).call(ctl)
		var errors := VegetationRules.validate(ctl, species)
		assert_bool(errors.is_empty()).override_failure_message("kabul edildi: %s" % label).is_false()
	assert_bool(VegetationRules.validate({}, species).is_empty()).is_false()


func test_sidewalk_values_match_the_road_style_view_data() -> void:
	var style: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/view/road_style.json"))
	var side: Dictionary = VegetationTestSupport.control()["sidewalk_m"]
	for cls: String in ["arterial", "collector", "local", "field"]:
		assert_float(float(side[cls])).override_failure_message(cls).is_equal(float(style["classes"][cls]["sidewalk_m"]))


func test_rules_file_names_no_rejected_or_unapproved_identity() -> void:
	var Scan := preload("res://tests/library/no_rejected_reference_scan_test.gd")
	var text := FileAccess.get_file_as_string(VegetationRules.PATH)
	var hits := Scan.find_tokens(text, Scan.non_approved_ids())
	assert_array(Array(hits)).override_failure_message("vegetation.json: %s" % str(hits)).is_empty()
	var planted := text + ' "bld_res_old_c_gf": 1.0'
	assert_array(Array(Scan.find_tokens(planted, Scan.non_approved_ids()))).contains_exactly(["bld_res_old_c_gf"])


func test_game_tables_are_gate_clean_and_the_furniture_table_loads() -> void:
	var gate := LibraryGate.load_plants()
	gate.report_errors = false
	assert_array(Array(gate.load_errors)).is_empty()
	assert_int(gate.approved_ids_of("vegetation").size()).is_equal(10)
	assert_int(gate.approved_ids_of("furniture").size()).is_equal(8)
	var paths := gate.request_paths("veg_hero_palm_date_a")
	assert_int(paths.size()).is_equal(3)
	assert_int(gate.request_paths("fur_hero_bench_a").size()).is_equal(2)
	assert_dict(gate.request("veg_plane")).is_empty()
	assert_int(gate.unapproved_ids.size()).is_equal(1)
