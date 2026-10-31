extends GdUnitTestSuite
## T-062 A1 / ADR-0006 §2.1b · LibraryGate: yalnız `data/library/game_*.json` kimlikleri geçer; onaysız/bilinmeyen
## kimlik reddedilir, sayılır, kayda geçer ve ASLA asset yüklemez; bozuk/eksik girdi güvenle (kapı kapalı) hata verir.

const TABLE_PATHS := ["res://data/library/game_buildings.json", "res://data/library/game_ground.json"]


static func _table(name: String, records: Array, excluded: Array = []) -> String:
	var key := "modules" if name == "buildings" else "layers"
	var entries: Array = []
	for id in excluded:
		entries.append({"id": id, "reason": "not_approved"})
	return JSON.stringify({
		"format": "imaro-game-set/1", "table": name, key: records,
		"unapproved": {"count": entries.size(), "entries": entries},
	})


static func _catalog(approvals: Dictionary) -> String:
	var entries: Array = []
	for id in approvals:
		entries.append({"id": id, "approval": approvals[id]})
	return JSON.stringify({"entries": entries})


func _gate() -> LibraryGate:
	var gate := LibraryGate.new()
	gate.report_errors = false   # push_error GdUnit hata sayacına girmesin; iz `load_errors`/`denial_log`'ta
	return gate


func _default_gate() -> LibraryGate:
	var gate := _gate()
	gate.load_game_tables(PackedStringArray(TABLE_PATHS), LibraryGate.CATALOG_PATH)
	return gate


func _json(path: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(path)) as Dictionary


func test_default_tables_load_and_approved_ids_pass() -> void:
	var gate := _default_gate()
	assert_array(Array(gate.load_errors)).is_empty()
	assert_int(gate.approved_ids_of("buildings").size()).is_equal(21)
	assert_int(gate.approved_ids_of("ground").size()).is_equal(14)
	var rec := gate.request("bld_hero_civ_hero_a")
	assert_str(str(rec.get("id", ""))).is_equal("bld_hero_civ_hero_a")
	var paths := gate.request_paths("bld_hero_civ_hero_a")
	assert_int(paths.size()).is_equal(3)
	assert_str(paths[0]).is_equal(str((_json(TABLE_PATHS[0])["modules"][0]["lods"]["LOD0"] as Dictionary)["glb"]))
	assert_bool(paths[1].ends_with("_lod1.glb") and paths[2].ends_with("_proxy.glb")).is_true()
	assert_int(gate.request_paths("gnd_tex_asphalt_new").size()).is_equal(1)
	assert_int(gate.unapproved_ids.size()).is_equal(0)
	assert_int(gate.granted_requests).is_equal(3)   # request + 2 request_paths


func test_granted_and_denied_are_counted_separately() -> void:
	var gate := _default_gate()
	gate.request("bld_hero_civ_hero_a")
	gate.request_paths("bld_hero_civ_hero_a")
	gate.request("bld_res_mid_a")
	assert_int(gate.granted_requests).is_equal(2)
	assert_int(gate.denied_requests).is_equal(1)


func test_rejected_and_unknown_ids_are_refused_counted_and_logged() -> void:
	var gate := _default_gate()
	assert_dict(gate.request("bld_res_mid_a")).is_empty()          # rejected (D-005)
	assert_dict(gate.request("prop_human")).is_empty()             # rejected
	assert_dict(gate.request("yok_boyle_bir_kimlik")).is_empty()   # bilinmeyen
	assert_dict(gate.request("")).is_empty()                       # boş
	assert_array(Array(gate.request_paths("bld_res_old_a"))).is_empty()
	assert_array(Array(gate.unapproved_ids)).contains_exactly(
		["bld_res_mid_a", "prop_human", "yok_boyle_bir_kimlik", "", "bld_res_old_a"])
	assert_int(gate.denied_requests).is_equal(5)
	assert_array(gate.denial_log.map(func(d: Dictionary) -> String: return str(d["reason"]))).contains_exactly(
		["rejected", "rejected", "unknown_id", "empty_id", "rejected"])
	assert_bool(gate.is_approved("bld_res_mid_a")).is_false()
	assert_int(gate.stats()["unapproved_ids"]).is_equal(5)


func test_repeated_denial_counts_requests_but_lists_the_id_once() -> void:
	var gate := _default_gate()
	for i in 3:
		gate.request("bld_res_mid_a")
	assert_int(gate.denied_requests).is_equal(3)
	assert_array(Array(gate.unapproved_ids)).contains_exactly(["bld_res_mid_a"])


func test_proposed_id_is_refused_with_proposed_reason() -> void:
	var gate := _gate()
	assert_bool(gate.load_catalog_text(_catalog({"a": "approved", "p": "proposed"}), "cat")).is_true()
	assert_bool(gate.add_table_text(_table("buildings", [{"id": "a"}]), "t")).is_true()
	assert_dict(gate.request("p")).is_empty()
	assert_str(str(gate.denial_log[0]["reason"])).is_equal("proposed")
	assert_dict(gate.request("a")).is_not_empty()


func test_table_id_not_approved_in_catalog_closes_the_whole_table() -> void:
	var gate := _gate()
	gate.load_catalog_text(_catalog({"a": "approved", "r": "rejected"}), "cat")
	assert_bool(gate.add_table_text(_table("buildings", [{"id": "a"}, {"id": "r"}]), "t")).is_false()
	assert_int(gate.approved_ids().size()).is_equal(0)
	assert_dict(gate.request("a")).is_empty()
	assert_int(gate.load_errors.size()).is_equal(1)
	# Katalogda hiç olmayan kimlik de tabloyu kapatır.
	var gate2 := _gate()
	gate2.load_catalog_text(_catalog({"a": "approved"}), "cat")
	assert_bool(gate2.add_table_text(_table("buildings", [{"id": "ghost"}]), "t")).is_false()


func test_broken_or_missing_input_fails_safe_and_the_gate_stays_closed() -> void:
	var bad_inputs: Array[String] = [
		"", "   ", "{", "[]", "null", "{\"format\":\"imaro-game-set/1\"}",
		JSON.stringify({"format": "imaro-game-set/0", "table": "buildings", "modules": []}),
		JSON.stringify({"format": "imaro-game-set/1", "table": "mystery", "modules": []}),
		JSON.stringify({"format": "imaro-game-set/1", "table": "buildings", "modules": {}}),
		JSON.stringify({"format": "imaro-game-set/1", "table": "buildings", "modules": [{"nope": 1}]}),
		JSON.stringify({"format": "imaro-game-set/1", "table": "buildings", "modules": [{"id": ""}]}),
		JSON.stringify({"format": "imaro-game-set/1", "table": "buildings", "modules": [{"id": "x"}, {"id": "x"}]}),
		JSON.stringify({"format": "imaro-game-set/1", "table": "buildings", "modules": [{"id": "x"}],
			"unapproved": {"count": 5, "entries": []}}),
		JSON.stringify({"format": "imaro-game-set/1", "table": "buildings", "modules": [{"id": "x"}],
			"unapproved": {"count": 1, "entries": [{"id": "x"}]}}),
		JSON.stringify({"format": "imaro-game-set/1", "table": "buildings", "modules": [{"id": "x"}],
			"unapproved": "bozuk"}),
	]
	for text in bad_inputs:
		var gate := _gate()
		assert_bool(gate.add_table_text(text, "bad")).override_failure_message("kabul edildi: %s" % text).is_false()
		assert_int(gate.load_errors.size()).is_equal(1)
		assert_int(gate.approved_ids().size()).is_equal(0)
		assert_dict(gate.request("x")).is_empty()


func test_missing_files_and_corrupt_catalog_fail_closed() -> void:
	var gate := _gate()
	var ok := gate.load_game_tables(PackedStringArray(["res://data/library/yok.json"]), "res://data/library/yok_cat.json")
	assert_bool(ok).is_false()
	assert_int(gate.load_errors.size()).is_equal(2)   # katalog hatası + "kapı KAPALI" (tablolar okunmaz)
	assert_bool(gate.is_closed()).is_true()
	assert_int(gate.approved_ids().size()).is_equal(0)
	var gate2 := _gate()
	assert_bool(gate2.load_catalog_text("{\"entries\": 3}", "cat")).is_false()
	assert_bool(gate2.load_catalog_text("{\"entries\": [{\"id\": 7}]}", "cat")).is_false()


func test_duplicate_id_across_tables_and_double_load_are_refused() -> void:
	var gate := _gate()
	assert_bool(gate.add_table_text(_table("buildings", [{"id": "x"}]), "b")).is_true()
	assert_bool(gate.add_table_text(_table("ground", [{"id": "x"}]), "g")).is_false()
	assert_bool(gate.add_table_text(_table("buildings", [{"id": "y"}]), "b2")).is_false()
	assert_array(Array(gate.approved_ids())).contains_exactly(["x"])


func test_order_is_deterministic_and_follows_table_order() -> void:
	var a := _default_gate()
	var b := _default_gate()
	assert_array(Array(a.approved_ids())).is_equal(Array(b.approved_ids()))
	var expected: Array = []
	for m in _json(TABLE_PATHS[0])["modules"] as Array:
		expected.append(str((m as Dictionary)["id"]))
	for layer in _json(TABLE_PATHS[1])["layers"] as Array:
		expected.append(str((layer as Dictionary)["id"]))
	assert_array(Array(a.approved_ids())).is_equal(expected)
	assert_dict(a.stats()).is_equal(b.stats())


func test_table_unapproved_sections_are_reported() -> void:
	var gate := _default_gate()
	assert_int(gate.table_excluded_count()).is_equal(int(_json(TABLE_PATHS[0])["unapproved"]["count"])
		+ int(_json(TABLE_PATHS[1])["unapproved"]["count"]))
	assert_int(gate.table_excluded_count()).is_equal(42)
	assert_bool(gate.table_excluded_ids().has("bld_res_mid_a")).is_true()
	assert_int(gate.excluded_total()).is_equal(42)
	gate.request("bld_res_mid_a")          # zaten tablo-dışlananı: iki kez sayılmaz
	gate.request("yok_boyle_bir_kimlik")   # yeni
	assert_int(gate.excluded_total()).is_equal(43)
	assert_int(gate.stats()["table_excluded"]).is_equal(42)


func test_every_game_table_id_passes_the_gate_and_is_approved_in_the_catalog() -> void:
	var gate := _default_gate()
	var catalog: Dictionary = {}
	for entry in _json(LibraryGate.CATALOG_PATH)["entries"] as Array:
		catalog[str((entry as Dictionary)["id"])] = entry
	var table_ids: Array = []
	for path in TABLE_PATHS:
		var table := _json(path)
		for rec in (table.get("modules", table.get("layers", []))) as Array:
			table_ids.append(str((rec as Dictionary)["id"]))
	assert_int(table_ids.size()).is_equal(35)
	for id in table_ids:
		assert_bool(gate.is_approved(id)).override_failure_message("kapıdan geçmedi: %s" % id).is_true()
		assert_bool(catalog.has(id)).override_failure_message("katalogda yok: %s" % id).is_true()
		assert_str(str((catalog[id] as Dictionary)["approval"])).override_failure_message(id).is_equal("approved")
	# Katalogda approved building/ground olup tabloda olmayan kimlik tablonun `unapproved` listesinde olmalı.
	var excluded := gate.table_excluded_ids()
	for id in catalog:
		var entry := catalog[id] as Dictionary
		if str(entry["approval"]) == "approved" and ["building", "ground"].has(str(entry["category"])):
			assert_bool(table_ids.has(id) or excluded.has(id)).override_failure_message("sessizce düştü: %s" % id).is_true()
	assert_int(gate.stats()["unapproved_ids"]).is_equal(0)


func test_game_tables_match_the_current_catalog_file() -> void:
	var catalog_sha := FileAccess.get_sha256(LibraryGate.CATALOG_PATH)
	for path in TABLE_PATHS:
		assert_str(str(_json(path)["source_catalog_sha256"])).override_failure_message(
			"%s eski: tools/library/build_game_set.py --write" % path).is_equal(catalog_sha)


func test_unapproved_request_never_loads_an_asset() -> void:
	var gate := _default_gate()
	# Reddedilen kimliğin GLB yolu katalogdan: kapı bu yolu ne döndürür ne de yükler.
	var rejected_glb := ""
	for entry in _json(LibraryGate.CATALOG_PATH)["entries"] as Array:
		if str((entry as Dictionary)["id"]) == "bld_res_mid_a":
			rejected_glb = str((entry as Dictionary)["glb"])
	assert_str(rejected_glb).is_not_empty()
	var cached_before := ResourceLoader.has_cached(rejected_glb)
	assert_array(Array(gate.request_paths("bld_res_mid_a"))).is_empty()
	assert_dict(gate.request("bld_res_mid_a")).is_empty()
	assert_bool(ResourceLoader.has_cached(rejected_glb)).is_equal(cached_before)
	# Yapısal: kapı kaynağı hiçbir yükleme/örnekleme API'si çağırmaz.
	var source := FileAccess.get_file_as_string("res://src/view/library/library_gate.gd")
	for forbidden in ["load(", "ResourceLoader", "instantiate(", "GLTFDocument", "FileAccess.open"]:
		assert_bool(source.contains(forbidden)).override_failure_message("kapı '%s' kullanıyor" % forbidden).is_false()


func test_returned_record_is_a_copy() -> void:
	var gate := _default_gate()
	var rec := gate.request("bld_hero_civ_hero_a")
	rec["id"] = "tampered"
	assert_str(str(gate.request("bld_hero_civ_hero_a")["id"])).is_equal("bld_hero_civ_hero_a")
