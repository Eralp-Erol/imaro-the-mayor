extends SimTestBase
## T-027 ölçüt 7 · `src/app/save_slot*` ayrıca taranır: dosya G/Ç'ye İZİN VAR (tek yer), ama zaman/OS/global
## rastgelelik/sahne ağacı/Node yok; sim ise bu katmana dokunmaz (bkz. sim_purity_test). Tarayıcı sim_purity_test'in
## aynı kurallarıdır (tek doğruluk kaynağı).

const Purity := preload("res://tests/sim/sim_purity_test.gd")
const APP_DIR := "res://src/app"
const PREFIX := "save_slot"


func _sources() -> Array[String]:
	var files: Array[String] = []
	Purity._collect(APP_DIR, PREFIX, files)
	return files


func test_scan_finds_the_save_slot_sources() -> void:
	var names: Array[String] = []
	for f in _sources():
		names.append(f.get_file())
	assert_array(names).contains(["save_slot.gd"])


func test_no_forbidden_apis_in_save_slot_sources() -> void:
	var offenders: Array[String] = []
	for path in _sources():
		for hit in Purity.forbidden_hits(FileAccess.get_file_as_string(path)):
			offenders.append("%s -> %s" % [path, hit])
	assert_array(offenders).override_failure_message("yasak API:\n" + "\n".join(offenders)).is_empty()


func test_save_slot_has_no_wall_clock_or_unrounded_transcendental_math() -> void:
	for path in _sources():
		var text := FileAccess.get_file_as_string(path)
		assert_array(Purity.transcendental_hits(text)).is_empty()
		assert_bool(Purity.strip_comments(text).contains("get_unix_time")).is_false()
		assert_bool(Purity.strip_comments(text).contains("get_ticks_")).is_false()
		assert_bool(Purity.strip_comments(text).contains("get_modified_time")).override_failure_message(
			"duvar saati/dosya zamanı sim girdisi olamaz").is_false()


func test_save_slot_is_the_only_src_app_file_io_besides_known_platform_files() -> void:
	# Dosya G/Ç yalnız save_slot*'ta (tick_driver* saf; platform dosyaları bu görevin dışındadır ve taranmaz).
	var driver_files: Array[String] = []
	Purity._collect(APP_DIR, "tick_driver", driver_files)
	for path in driver_files:
		assert_array(Purity.file_io_hits(FileAccess.get_file_as_string(path))).override_failure_message(path).is_empty()
	var io_found := false
	for path in _sources():
		io_found = io_found or not Purity.file_io_hits(FileAccess.get_file_as_string(path)).is_empty()
	assert_bool(io_found).override_failure_message("dosya G/Ç beklenen yerde değil").is_true()


func test_save_slot_classes_are_refcounted() -> void:
	for path in _sources():
		var text := Purity.strip_comments(FileAccess.get_file_as_string(path))
		var m := RegEx.create_from_string("(?m)^extends\\s+(\\w+)").search(text)
		assert_object(m).is_not_null()
		assert_str(m.get_string(1)).is_equal("RefCounted")
