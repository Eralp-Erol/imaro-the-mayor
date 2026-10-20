extends GdUnitTestSuite
## T-007 ölçüt 4 · OLUMSUZ test: `src/sim` (+ `src/world`, `src/contracts`) PlatformProfile/InputProfile/OS.has_feature/
## DisplayServer kullanırsa bu test BAŞARISIZ olur. Önce tarayıcının kendisi sınanır (yakalıyor mu?), sonra gerçek ağaç.

const Scanner := preload("res://tests/app/sim_leak_scanner.gd")
const TMP_DIR := "user://sim_isolation_test"


func after() -> void:
	for sub in ["sim", "ok"]:
		var d := ProjectSettings.globalize_path(TMP_DIR.path_join(sub))
		for f in DirAccess.get_files_at(d):
			DirAccess.remove_absolute(d.path_join(f))
		DirAccess.remove_absolute(d)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP_DIR))


func test_scanner_catches_each_forbidden_token_in_code() -> void:
	for token in Scanner.FORBIDDEN:
		var src := "func f() -> void:\n\tvar x = %s\n" % token
		var hits := Scanner.violations_in(src)
		assert_int(hits.size()).is_greater_equal(1)
		assert_str(hits[0]["token"]).is_equal(token)
		assert_int(hits[0]["line"]).is_equal(2)


func test_scanner_catches_the_realistic_leak_patterns() -> void:
	var leaks := [
		"var p := PlatformProfile.current()\n",
		"if OS.has_feature(\"ios\"):\n\tpass\n",
		"var speed = PlatformProfile.from_tags(PackedStringArray()).max_game_speed\n",
		"var s = DisplayServer.screen_get_size()\n",
		"print(\"OS.has_feature\")\n",  # dize içinde bile kuşkulu
	]
	for src: String in leaks:
		assert_int(Scanner.violations_in(src).size()).is_greater_equal(1)


func test_scanner_ignores_comments_but_not_code_before_them() -> void:
	assert_int(Scanner.violations_in("# PlatformProfile sim'e sızmaz\n").size()).is_equal(0)
	assert_int(Scanner.violations_in("## OS.has_feature kullanma\nvar a := 1  # InputProfile\n").size()).is_equal(0)
	assert_int(Scanner.violations_in("var s := \"a # b\"  # DisplayServer\n").size()).is_equal(0)
	assert_int(Scanner.violations_in("var p = PlatformProfile.new()  # yorum\n").size()).is_equal(1)
	assert_int(Scanner.violations_in("var s := \"# \" + str(OS.has_feature(\"x\"))\n").size()).is_equal(1)


func test_scan_dir_finds_a_planted_violation_in_a_nested_temp_sim_tree_and_passes_a_clean_one() -> void:
	var bad := TMP_DIR.path_join("sim")
	var ok := TMP_DIR.path_join("ok")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(bad))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ok))
	var f := FileAccess.open(bad.path_join("leaky.gd"), FileAccess.WRITE)
	f.store_string("extends RefCounted\nfunc speed() -> int:\n\treturn PlatformProfile.current().max_game_speed\n")
	f.close()
	var g := FileAccess.open(ok.path_join("clean.gd"), FileAccess.WRITE)
	g.store_string("extends RefCounted\n# platform profili burada yok\nfunc tick() -> int:\n\treturn 1\n")
	g.close()
	var hits := Scanner.scan_dir(bad)
	assert_int(hits.size()).is_equal(1)
	assert_str(hits[0]["file"]).ends_with("leaky.gd")
	assert_int(hits[0]["line"]).is_equal(3)
	assert_int(Scanner.scan_dir(ok).size()).is_equal(0)
	assert_int(Scanner.scan_dir("res://src/does_not_exist").size()).is_equal(0)


func test_real_sim_world_and_contract_sources_do_not_use_platform_profile_or_queries() -> void:
	# Test boş geçmez: taranan kök dizinlerde gerçekten .gd var.
	var files := 0
	for root in Scanner.ROOTS:
		files += Scanner._gd_files(root).size()
	assert_int(files).is_greater(0)
	var hits := Scanner.scan_roots()
	var report := ""
	for h in hits:
		report += "%s:%d  %s  ->  %s\n" % [h["file"], h["line"], h["token"], h["text"]]
	assert_str(report).is_empty()


func test_subclass_names_are_covered_by_the_base_token() -> void:
	assert_int(Scanner.violations_in("var a := DesktopInputProfile.new()\n").size()).is_greater_equal(1)
	assert_int(Scanner.violations_in("var a := TouchInputProfile.new()\n").size()).is_greater_equal(1)
