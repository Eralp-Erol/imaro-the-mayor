extends GdUnitTestSuite
## T-076 hazırlık: PerfLogger'ın ortam alanları (VSync/yenileme geri okuması, derleme türü, başlangıç, komut satırı) ve
## `--perf-log-novsync` bayrağının ayrıştırılması. Başsız (dummy DisplayServer) testte VSync çağrısı zararsızdır;
## gerçek pencerede VSync'in kapandığı hazırlık log'undaki masaüstü koşusunda `vsync_mode` geri okumasıyla görüldü.

const TMP_DIR := "user://perf_logger_env_test/"


func before_test() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TMP_DIR))


func after_test() -> void:
	var dir := DirAccess.open(TMP_DIR)
	if dir == null:
		return
	for f in dir.get_files():
		dir.remove(f)


func test_novsync_flag_is_parsed_and_off_by_default() -> void:
	var host: Node = auto_free(Node.new())
	add_child(host)
	var plain := PerfLogger.attach_if_requested(host, {"perf-log": "a.json"})
	assert_bool(plain.novsync).is_false()
	var host2: Node = auto_free(Node.new())
	add_child(host2)
	var off := PerfLogger.attach_if_requested(host2, {"perf-log": "a.json", "perf-log-novsync": true})
	assert_bool(off.novsync).is_true()


func test_report_carries_vsync_build_startup_and_command_line_fields() -> void:
	var path := TMP_DIR + "env.json"
	var logger: PerfLogger = auto_free(PerfLogger.new())
	logger.out_path = path
	logger.write_every = 0
	for k in 12:
		logger.record_frame(8.0 + k, 300.0, 400000.0, k)
	add_child(logger)
	assert_int(logger.flush("periodic")).is_equal(OK)
	var rep: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert_bool(rep.has("vsync_mode")).is_true()
	assert_bool(rep.has("max_fps")).is_true()
	assert_bool(bool(rep["novsync_requested"])).is_false()
	assert_bool(rep.has("template_build")).is_true()
	assert_bool(rep.has("cmdline_args")).is_true()
	assert_int(int(rep["format"])).is_equal(2)
	assert_int((rep["startup"]["first_frames_ms"] as Array).size()).is_equal(10)
	assert_float(float(rep["startup"]["first_frames_ms"][0])).is_equal(8.0)
