extends GdUnitTestSuite
## T-076 hazırlık: PerfLogger bellek örneği/özeti, pencereli (ısıl) ölçüm, 15 dk ısıl karşılaştırma, hedefe ulaşınca
## donan oturum ve yazılamayan dosya (çökmez, ölçüm bellekte kalır). Asıl özet/dosya/açma testleri perf_logger_test.gd.
## Sentetik seri `record_frame`/`record_memory` ile beslenir (saat bağımsız, deterministik).

const TMP_DIR := "user://perf_logger_session_test/"
const MB := 1048576.0


func before_test() -> void:
	OS.unset_environment(PerfLogger.ENV_NAME)
	OS.unset_environment(PerfLogger.THERMAL_ENV_NAME)
	_clean(TMP_DIR)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TMP_DIR))


func after_test() -> void:
	OS.unset_environment(PerfLogger.ENV_NAME)
	OS.unset_environment(PerfLogger.THERMAL_ENV_NAME)
	_clean(TMP_DIR)


func _clean(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for sub in dir.get_directories():
		_clean(path.path_join(sub))
		dir.remove(sub)
	for f in dir.get_files():
		dir.remove(f)


func _logger(path: String) -> PerfLogger:
	var logger: PerfLogger = auto_free(PerfLogger.new())
	logger.out_path = path
	logger.write_every = 0
	return logger


func _mem(frame: int, static_mb: float, video_mb: float = 100.0, nodes: int = 5000) -> Dictionary:
	return {"frame": frame, "static": static_mb * MB, "video": video_mb * MB, "texture": 50.0 * MB,
			"buffer": 40.0 * MB, "nodes": nodes, "objects": nodes * 3}


func test_memory_summary_reports_first_last_max_and_growth_in_mb() -> void:
	var samples: Array = [_mem(1, 500.0), _mem(61, 520.0, 110.0), _mem(121, 515.0, 108.0)]
	var m := PerfLogger.memory_summary(samples, 560.0 * MB)
	assert_int(int(m["samples"])).is_equal(3)
	assert_float(float(m["static_mb"]["first"])).is_equal(500.0)
	assert_float(float(m["static_mb"]["last"])).is_equal(515.0)
	assert_float(float(m["static_mb"]["max"])).is_equal(520.0)
	assert_float(float(m["static_mb"]["growth"])).is_equal(15.0)
	assert_float(float(m["video_mb"]["max"])).is_equal(110.0)
	assert_float(float(m["static_peak_mb"])).is_equal(560.0)
	assert_int(int(m["nodes"]["max"])).is_equal(5000)


func test_memory_summary_without_samples_says_so_instead_of_inventing_zeros() -> void:
	var m := PerfLogger.memory_summary([], 0.0)
	assert_int(int(m["samples"])).is_equal(0)
	assert_bool(m.has("static_mb")).is_false()


func test_memory_summary_marks_static_counter_unavailable_when_it_only_reads_zero() -> void:
	# Release şablonunda statik bellek sayacı 0 dönebilir: rapor bunu "0 MB" gibi yutmaz, açıkça işaretler.
	var m := PerfLogger.memory_summary([_mem(1, 0.0, 300.0), _mem(61, 0.0, 320.0)], 0.0)
	assert_bool(bool(m["static_available"])).is_false()
	assert_float(float(m["video_mb"]["growth"])).is_equal(20.0)
	var live := PerfLogger.memory_summary([_mem(1, 500.0)], 500.0 * MB)
	assert_bool(bool(live["static_available"])).is_true()


func test_memory_series_is_downsampled_but_keeps_first_and_last() -> void:
	var samples: Array = []
	for k in 1000:
		samples.append(_mem(k * 60 + 1, 500.0 + k))
	var m := PerfLogger.memory_summary(samples, 0.0)
	var series: Array = m["series"]
	assert_bool(series.size() <= PerfLogger.MEMORY_SERIES_MAX).is_true()
	assert_int(int(series[0]["frame"])).is_equal(1)
	assert_int(int(series[series.size() - 1]["frame"])).is_equal(999 * 60 + 1)


func test_sample_memory_reads_real_monitors_and_records_one_sample() -> void:
	var logger := _logger(TMP_DIR + "mem.json")
	logger.record_frame(8.0, 300.0, 400000.0, 0)
	var s := logger.sample_memory()
	assert_float(float(s["static"])).is_greater(0.0)
	assert_int(logger.memory_sample_count()).is_equal(1)
	assert_float(float(s["video"])).is_greater_equal(0.0)


func test_flush_writes_memory_block_with_peak_and_os_info() -> void:
	var path := TMP_DIR + "mem_report.json"
	var logger := _logger(path)
	for k in 10:
		logger.record_frame(8.0, 300.0, 400000.0, k)
	logger.record_memory(_mem(1, 500.0))
	logger.record_memory(_mem(61, 530.0))
	add_child(logger)
	assert_int(logger.flush("periodic")).is_equal(OK)
	var rep: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert_float(float(rep["memory"]["static_mb"]["growth"])).is_equal(30.0)
	assert_bool(rep["memory"].has("static_peak_mb")).is_true()
	assert_bool(rep["memory"].has("os_memory_mb")).is_true()
	assert_int(int(rep["memory"]["samples"])).is_equal(2)


func test_windows_close_on_frame_time_boundary_with_stats_and_memory() -> void:
	var logger := _logger(TMP_DIR + "win.json")
	logger.window_s = 1.0  # 1 sn = 100 kare x 10 ms
	logger.record_memory(_mem(1, 500.0))
	for k in 250:  # 200 kare x 10 ms (2 pencere) + 50 kare x 20 ms (1 pencere)
		logger.record_frame(10.0 if k < 200 else 20.0, 300.0, 400000.0, k)
	var wins := logger.windows()
	assert_int(wins.size()).is_equal(3)
	assert_int(int(wins[0]["frames"])).is_equal(100)
	assert_float(float(wins[0]["frame_ms"]["mean"])).is_equal(10.0)
	assert_int(int(wins[2]["frames"])).is_equal(50)
	assert_float(float(wins[2]["frame_ms"]["mean"])).is_equal(20.0)
	assert_float(float(wins[1]["t_s"])).is_equal_approx(2.0, 0.01)
	assert_float(float(wins[0]["static_mb"])).is_equal(500.0)


func test_windows_off_by_default() -> void:
	var logger := _logger(TMP_DIR + "nowin.json")
	for k in 500:
		logger.record_frame(10.0, 300.0, 400000.0, k)
	assert_int(logger.windows().size()).is_equal(0)


func test_thermal_summary_compares_last_two_minutes_with_first_two_minutes() -> void:
	var ms := PackedFloat32Array()
	for k in 30000:  # 300 sn x 10 ms; son 120 sn 12,5 ms (+%25)
		ms.append(10.0 if k < 18000 else 12.5)
	var rep := PerfLogger.thermal_summary(ms, 120.0)
	assert_bool(bool(rep["reached"])).is_true()
	assert_float(float(rep["first"]["p95"])).is_equal(10.0)
	assert_float(float(rep["last"]["p95"])).is_equal(12.5)
	assert_float(float(rep["p95_ratio"])).is_equal_approx(1.25, 0.001)
	assert_float(float(rep["limit_ratio"])).is_equal(1.25)
	assert_bool(bool(rep["within_limit"])).is_true()


func test_thermal_summary_flags_a_throttled_session() -> void:
	var ms := PackedFloat32Array()
	for k in 30000:
		ms.append(10.0 if k < 18000 else 16.0)
	var rep := PerfLogger.thermal_summary(ms, 120.0)
	assert_bool(bool(rep["within_limit"])).is_false()
	assert_float(float(rep["p95_ratio"])).is_equal_approx(1.6, 0.001)


func test_thermal_summary_for_a_short_session_is_not_reached_not_a_pass() -> void:
	var ms := PackedFloat32Array()
	for k in 5000:  # 50 sn < 2 x 120 sn
		ms.append(10.0)
	var rep := PerfLogger.thermal_summary(ms, 120.0)
	assert_bool(bool(rep["reached"])).is_false()
	assert_bool(rep.has("within_limit")).is_false()


func test_attach_parses_thermal_window_and_memory_flags() -> void:
	var host: Node = auto_free(Node.new())
	add_child(host)
	var logger := PerfLogger.attach_if_requested(host, {"perf-log": "t.json", "perf-log-thermal": true})
	assert_float(logger.complete_at_s).is_equal(PerfLogger.DEFAULT_THERMAL_SESSION_S)
	assert_float(logger.window_s).is_equal(PerfLogger.DEFAULT_THERMAL_WINDOW_S)
	var host2: Node = auto_free(Node.new())
	add_child(host2)
	var l2 := PerfLogger.attach_if_requested(host2, {"perf-log": "t.json", "perf-log-thermal": "60",
			"perf-log-window": "5", "perf-log-mem-every": "30"})
	assert_float(l2.complete_at_s).is_equal(60.0)
	assert_float(l2.window_s).is_equal(5.0)
	assert_int(l2.memory_every).is_equal(30)


func test_without_thermal_flag_window_and_time_target_stay_off() -> void:
	var host: Node = auto_free(Node.new())
	add_child(host)
	var logger := PerfLogger.attach_if_requested(host, {"perf-log": "t.json"})
	assert_float(logger.complete_at_s).is_equal(0.0)
	assert_float(logger.window_s).is_equal(0.0)
	assert_int(logger.memory_every).is_equal(PerfLogger.DEFAULT_MEMORY_EVERY)


func test_session_target_reached_by_time_or_frames() -> void:
	var logger := _logger(TMP_DIR + "target.json")
	logger.complete_at_s = 1.0
	assert_bool(logger.target_reached()).is_false()
	for k in 99:
		logger.record_frame(10.0, 300.0, 400000.0, k)
	assert_bool(logger.target_reached()).is_false()
	logger.record_frame(10.0, 300.0, 400000.0, 99)
	assert_bool(logger.target_reached()).is_true()
	var by_frames := _logger(TMP_DIR + "target2.json")
	by_frames.complete_at_frames = 3
	by_frames.record_frame(1.0, 0.0, 0.0, 0)
	by_frames.record_frame(1.0, 0.0, 0.0, 0)
	assert_bool(by_frames.target_reached()).is_false()
	by_frames.record_frame(1.0, 0.0, 0.0, 0)
	assert_bool(by_frames.target_reached()).is_true()


func test_completed_session_freezes_the_measurement_and_later_writes_keep_the_complete_report() -> void:
	var path := TMP_DIR + "frozen.json"
	var logger := _logger(path)
	for k in 20:
		logger.record_frame(8.0, 300.0, 400000.0, k)
	add_child(logger)
	assert_int(logger.mark_complete()).is_equal(OK)
	logger.record_frame(500.0, 300.0, 400000.0, 21)  # oturum sürüyor ama ölçüm bitti
	assert_int(logger.frame_count()).is_equal(20)
	assert_int(logger.flush("periodic")).is_equal(OK)
	assert_int(logger.flush("exit")).is_equal(OK)
	var rep: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert_str(String(rep["reason"])).is_equal("complete")
	assert_int(int(rep["frames"])).is_equal(20)
	assert_float(float(rep["frame_ms"]["max"])).is_equal(8.0)


func test_long_session_report_has_windows_thermal_and_memory_blocks() -> void:
	var path := TMP_DIR + "long.json"
	var logger := _logger(path)
	logger.window_s = 60.0
	logger.complete_at_s = 300.0
	for k in 30000:  # 180 sn x 10 ms + 150 sn x 12,5 ms = 330 sn
		logger.record_frame(10.0 if k < 18000 else 12.5, 300.0, 400000.0, k)
		if k % 6000 == 0:
			logger.record_memory(_mem(k + 1, 500.0 + k / 600))
	add_child(logger)
	assert_int(logger.mark_complete()).is_equal(OK)
	var rep: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert_int((rep["windows"] as Array).size()).is_equal(5)
	assert_bool(bool(rep["thermal"]["reached"])).is_true()
	assert_bool(bool(rep["thermal"]["within_limit"])).is_true()
	assert_float(float(rep["memory"]["static_mb"]["growth"])).is_equal(40.0)
	assert_float(float(rep["session_target_s"])).is_equal(300.0)


func test_unwritable_path_keeps_windows_memory_and_recording_alive() -> void:
	var blocker := TMP_DIR + "blocker3"
	var f := FileAccess.open(blocker, FileAccess.WRITE)
	f.store_string("x")
	f.close()
	var logger := _logger(blocker + "/sub/long.json")
	logger.window_s = 1.0
	logger.complete_at_s = 3.0
	for k in 300:
		logger.record_frame(10.0, 300.0, 400000.0, k)
	logger.record_memory(_mem(1, 500.0))
	add_child(logger)
	assert_bool(logger.mark_complete() != OK).is_true()
	assert_bool(logger.last_error != OK).is_true()
	# Yazılamayan dosya ölçümü bozmaz: pencereler/bellek bellekte kalır, flush çökmeden hata döner.
	assert_int(logger.windows().size()).is_equal(3)
	assert_int(logger.memory_sample_count()).is_equal(1)
	assert_bool(logger.flush("periodic") != OK).is_true()
	assert_bool(FileAccess.file_exists(blocker + "/sub/long.json")).is_false()
