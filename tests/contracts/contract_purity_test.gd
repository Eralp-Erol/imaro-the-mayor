extends GdUnitTestSuite
## T-023 ölçüt 5 · src/contracts/ saflığı: Node/Time/OS/rastgelelik yok, RefCounted (TEK-01/02, PLT-04).
## Olumsuz varyantlar tarayıcının gerçekten yakaladığını kanıtlar (tarama boş geçmez).

const MIN_CONTRACT_FILES := 18


func test_contract_sources_have_no_forbidden_apis() -> void:
	var files := ContractPurityScanner.gd_files(ContractPurityScanner.ROOT)
	assert_int(files.size()).override_failure_message("too few contract files found: %s" % [files]) \
		.is_greater_equal(MIN_CONTRACT_FILES)
	var problems := ContractPurityScanner.scan_tree()
	assert_array(problems).override_failure_message("forbidden APIs in src/contracts: %s" % [problems]).is_empty()


func test_scanner_detects_each_forbidden_api() -> void:
	var bad_bodies: Array[String] = [
		"var n := Node.new()", "var n: Node3D = null", "get_tree().quit()", "var t := Time.get_ticks_msec()",
		"var o := OS.get_name()", "var r := randf()", "var r := randi_range(1, 2)", "randomize()",
		"var g := RandomNumberGenerator.new()", "var f := Engine.get_frames_drawn()",
		"var x := Input.is_action_pressed(&\"a\")", "var d := DirAccess.open(\"res://\")",
		"var s := load(\"res://x.gd\")", "var f := FileAccess.open(\"res://x\", FileAccess.READ)",
	]
	for body in bad_bodies:
		var source := "class_name X\nextends RefCounted\n\n\nfunc f() -> void:\n\t%s\n" % body
		assert_array(ContractPurityScanner.scan_source(source)) \
			.override_failure_message("scanner missed: %s" % body).is_not_empty()


func test_scanner_rejects_node_base_class() -> void:
	var problems := ContractPurityScanner.scan_source("class_name X\nextends Node\n")
	assert_array(problems).is_not_empty()
	assert_array(ContractPurityScanner.scan_source("class_name X\n")).contains(["0: missing 'extends RefCounted'"])


func test_scanner_ignores_comments_and_string_literals() -> void:
	var source := "class_name X\nextends RefCounted\n## Node yok, Time. OS. randf() yok\n" \
		+ "const S := \"Node randf() Time.now\"  # OS.get_name()\n"
	assert_array(ContractPurityScanner.scan_source(source)).is_empty()


func test_file_access_only_allowed_in_mock_loader() -> void:
	var source := "extends RefCounted\nfunc f() -> void:\n\tvar t := FileAccess.get_file_as_string(\"x\")\n"
	assert_array(ContractPurityScanner.scan_source(source, false)).is_not_empty()
	assert_array(ContractPurityScanner.scan_source(source, true)).is_empty()
	assert_array(ContractPurityScanner.FILE_ACCESS_ALLOWED).has_size(1)


func test_every_contract_script_is_refcounted_not_node() -> void:
	for path in ContractPurityScanner.gd_files(ContractPurityScanner.ROOT):
		var script: Script = load(path)
		assert_object(script).override_failure_message("cannot load %s" % path).is_not_null()
		assert_str(String(script.get_instance_base_type())) \
			.override_failure_message("%s base %s" % [path, script.get_instance_base_type()]).is_equal("RefCounted")


func test_sim_facade_and_dto_base_are_abstract() -> void:
	assert_bool((load("res://src/contracts/sim_facade.gd") as Script).is_abstract()).is_true()
	assert_bool((load("res://src/contracts/sim_dto.gd") as Script).is_abstract()).is_true()
	assert_bool((load("res://src/contracts/mock/mock_sim_facade.gd") as Script).is_abstract()).is_false()
