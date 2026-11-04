extends GdUnitTestSuite
## T-062 QA B-2 / ADR-0006 §2.1b · LibraryGate FAIL-CLOSED: katalog tek başına eksik/bozuk ya da tablo-katalog hash'i
## uyuşmazsa kapı KAPANIR; tablolar gerçek ve sağlam olsa bile hiçbir kimlik onaylanmaz. Gerçek hata yolu (res:// ve
## user:// geçici dosya) kullanılır, taklit yok. Ana kapı testleri: `library_gate_test.gd`.

const TABLE_PATHS := ["res://data/library/game_buildings.json", "res://data/library/game_ground.json"]
const TMP_DIR := "user://gate_test_tmp"
const HERO := "bld_hero_civ_hero_a"


static func _table(name: String, records: Array) -> String:
	var key := "modules" if name == "buildings" else "layers"
	return JSON.stringify({
		"format": "imaro-game-set/1", "table": name, key: records, "unapproved": {"count": 0, "entries": []},
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


func _write_tmp(name: String, text: String) -> String:
	DirAccess.make_dir_recursive_absolute(TMP_DIR)
	var path := TMP_DIR.path_join(name)
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()
	return path


func _clean_tmp() -> void:
	for f in DirAccess.get_files_at(TMP_DIR):
		DirAccess.remove_absolute(TMP_DIR.path_join(f))
	DirAccess.remove_absolute(TMP_DIR)


func _assert_fully_closed(gate: LibraryGate, label: String) -> void:
	assert_bool(gate.is_closed()).override_failure_message("%s: kapı kapanmadı" % label).is_true()
	assert_array(Array(gate.load_errors)).override_failure_message("%s: hata kaydı yok" % label).is_not_empty()
	assert_int(gate.approved_ids().size()).override_failure_message("%s: onaylı kimlik kaldı" % label).is_equal(0)
	assert_bool(gate.is_approved(HERO)).is_false()
	assert_dict(gate.request(HERO)).override_failure_message("%s: request verdi" % label).is_empty()
	assert_array(Array(gate.request_paths(HERO))).override_failure_message("%s: request_paths verdi" % label).is_empty()
	assert_int(gate.granted_requests).is_equal(0)
	assert_str(str(gate.denial_log[0]["reason"])).is_equal(LibraryGate.REASON_GATE_CLOSED)
	assert_bool(gate.stats()["closed"]).is_true()


func test_missing_catalog_alone_closes_the_gate_even_with_valid_tables() -> void:
	var gate := _gate()
	var ok := gate.load_game_tables(PackedStringArray(TABLE_PATHS), "res://data/library/yok_katalog.json")
	assert_bool(ok).is_false()
	_assert_fully_closed(gate, "katalog yok")
	assert_int(gate.table_excluded_count()).is_equal(0)


func test_corrupt_or_empty_catalog_alone_closes_the_gate() -> void:
	var bad_catalogs: Dictionary = {
		"empty.json": "", "broken.json": "{", "list.json": "[]", "no_entries.json": "{}",
		"entries_not_array.json": "{\"entries\": 3}", "bad_entry.json": "{\"entries\": [{\"id\": 7}]}",
	}
	for name in bad_catalogs:
		var path := _write_tmp(str(name), str(bad_catalogs[name]))
		var gate := _gate()
		var ok := gate.load_game_tables(PackedStringArray(TABLE_PATHS), path)
		assert_bool(ok).override_failure_message(str(name)).is_false()
		_assert_fully_closed(gate, str(name))
	_clean_tmp()


func test_catalog_hash_mismatch_closes_the_gate() -> void:
	# Katalog içeriği değişti (geçerli JSON, bir kimlik daha): tabloların `source_catalog_sha256`ı artık eşleşmez.
	var changed := FileAccess.get_file_as_string(LibraryGate.CATALOG_PATH) + "\n"
	var path := _write_tmp("changed_catalog.json", changed)
	assert_str(changed.sha256_text()).is_not_equal(FileAccess.get_sha256(LibraryGate.CATALOG_PATH))
	var gate := _gate()
	assert_bool(gate.load_game_tables(PackedStringArray(TABLE_PATHS), path)).is_false()
	_assert_fully_closed(gate, "hash uyuşmaz")
	assert_bool(" ".join(gate.load_errors).contains("source_catalog_sha256")).is_true()
	_clean_tmp()


func test_catalog_text_hash_equals_the_file_hash_so_the_real_tables_pass() -> void:
	assert_str(FileAccess.get_file_as_string(LibraryGate.CATALOG_PATH).sha256_text()).is_equal(
		FileAccess.get_sha256(LibraryGate.CATALOG_PATH))
	var gate := _default_gate()
	assert_bool(gate.is_closed()).is_false()
	assert_bool(gate.stats()["closed"]).is_false()


func test_hash_mismatch_in_a_later_table_drops_ids_accepted_earlier() -> void:
	var catalog := _catalog({"a": "approved", "g": "approved"})
	var gate := _gate()
	assert_bool(gate.load_catalog_text(catalog, "cat")).is_true()
	var good: Dictionary = JSON.parse_string(_table("buildings", [{"id": "a"}]))
	good["source_catalog_sha256"] = catalog.sha256_text()
	assert_bool(gate.add_table_text(JSON.stringify(good), "good")).is_true()
	assert_dict(gate.request("a")).is_not_empty()
	var stale: Dictionary = JSON.parse_string(_table("ground", [{"id": "g"}]))
	stale["source_catalog_sha256"] = "0".repeat(64)
	assert_bool(gate.add_table_text(JSON.stringify(stale), "stale")).is_false()
	assert_bool(gate.is_closed()).is_true()
	assert_int(gate.approved_ids().size()).is_equal(0)
	assert_dict(gate.request("a")).is_empty()
	assert_bool(gate.is_approved("g")).is_false()
	# Kapalıyken yeni tablo da kabul edilmez.
	assert_bool(gate.add_table_text(_table("buildings", [{"id": "z"}]), "late")).is_false()
	assert_bool(gate.add_table_text(JSON.stringify(good), "again")).is_false()
	assert_dict(gate.request("z")).is_empty()


func test_closed_gate_makes_settlement_table_return_an_empty_table() -> void:
	var gate := _gate()
	gate.load_game_tables(PackedStringArray(TABLE_PATHS), "res://data/library/yok_katalog.json")
	var loaded := SettlementTable.load_game_table(SettlementTable.PATH, gate)
	assert_dict(loaded["table"]).is_empty()
	assert_bool((loaded["gate"] as LibraryGate).is_closed()).is_true()
