extends GdUnitTestSuite
## T-076 ölçüm düğümü (PerfLogger): özet hesabı (yüzdelikler, en kötü 20, tick'li/tick'siz ayrımı, kararlı evre),
## JSON gidiş-dönüşü, yazılamayan yol (çökmez, hata kodu döner) ve kapalıyken düğümün hiç eklenmediği.
## Dummy renderer: çizim sayaçları 0 döner; sentetik seri `record_frame` ile beslenir (saat bağımsız, deterministik).

const TMP_DIR := "user://perf_logger_test/"


func before_test() -> void:
	OS.unset_environment(PerfLogger.ENV_NAME)
	_clean(TMP_DIR)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TMP_DIR))


func after_test() -> void:
	OS.unset_environment(PerfLogger.ENV_NAME)
	_clean(TMP_DIR)


## Dizin ağacını siler (önceki koşudan kalan engelleyici dosya/dizin bu testlerin önkoşulunu bozmasın).
func _clean(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	for sub in dir.get_directories():
		_clean(path.path_join(sub))
		dir.remove(sub)
	for f in dir.get_files():
		dir.remove(f)


func _series(n: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for k in n:
		out.append(float(k + 1))  # 1..n ms
	return out


func _logger(path: String) -> PerfLogger:
	var logger: PerfLogger = auto_free(PerfLogger.new())
	logger.out_path = path
	logger.write_every = 0
	return logger


# --- Özet hesabı ---

func test_stats_use_nearest_rank_percentiles_like_perf_probe() -> void:
	var s := PerfLogger.stats(_series(100))
	assert_int(int(s["count"])).is_equal(100)
	assert_float(float(s["mean"])).is_equal_approx(50.5, 0.001)
	assert_float(float(s["p95"])).is_equal(95.0)
	assert_float(float(s["p99"])).is_equal(99.0)
	assert_float(float(s["max"])).is_equal(100.0)
	assert_float(float(s["min"])).is_equal(1.0)


func test_stats_of_empty_series_is_count_zero_not_a_crash() -> void:
	assert_dict(PerfLogger.stats(PackedFloat32Array())).is_equal({"count": 0})


func test_worst_frames_are_top_twenty_descending_with_frame_number_and_day() -> void:
	var ms := PackedFloat32Array()
	var days := PackedInt32Array()
	for k in 200:
		ms.append(5.0)
		days.append(k / 10)
	ms[37] = 180.0
	ms[150] = 120.0
	var worst := PerfLogger.worst_frames(ms, PackedFloat32Array(), PackedFloat32Array(), days)
	assert_int(worst.size()).is_equal(PerfLogger.WORST_COUNT)
	assert_int(int(worst[0]["frame"])).is_equal(38)
	assert_float(float(worst[0]["ms"])).is_equal(180.0)
	assert_int(int(worst[0]["day"])).is_equal(3)
	assert_int(int(worst[1]["frame"])).is_equal(151)
	assert_int(int(worst[1]["day"])).is_equal(15)
	# Eşit (5 ms) karelerde önce gelen kare; eksik draw/üçgen dizileri -1.
	assert_int(int(worst[2]["frame"])).is_equal(1)
	assert_int(int(worst[2]["draw_calls"])).is_equal(-1)
	for k in range(1, worst.size()):
		assert_bool(float(worst[k - 1]["ms"]) >= float(worst[k]["ms"])).is_true()


func test_worst_frames_with_fewer_than_twenty_frames_returns_all() -> void:
	var worst := PerfLogger.worst_frames(_series(5), PackedFloat32Array(), PackedFloat32Array(), PackedInt32Array())
	assert_int(worst.size()).is_equal(5)
	assert_int(int(worst[0]["frame"])).is_equal(5)


func test_summarize_splits_tick_frames_from_idle_frames_by_day_change() -> void:
	var ms := PackedFloat32Array([10.0, 12.0, 40.0, 8.0, 9.0, 60.0])
	var days := PackedInt32Array([3, 3, 4, 4, 4, 5])  # kare 3 ve 6 tick'li
	var rep := PerfLogger.summarize(ms, PackedFloat32Array([300, 310, 320, 330, 340, 350]),
			PackedFloat32Array([1000, 2000, 3000, 9000, 5000, 6000]), days)
	assert_int(int(rep["tick_frame_ms"]["count"])).is_equal(2)
	assert_float(float(rep["tick_frame_ms"]["max"])).is_equal(60.0)
	assert_int(int(rep["non_tick_frame_ms"]["count"])).is_equal(4)
	assert_float(float(rep["non_tick_frame_ms"]["max"])).is_equal(12.0)
	assert_int(int(rep["frames_over_33ms"])).is_equal(2)
	assert_int(int(rep["frames_over_50ms"])).is_equal(1)
	assert_int(int(rep["frames_over_100ms"])).is_equal(0)
	assert_float(float(rep["draw_calls"]["max"])).is_equal(350.0)
	assert_float(float(rep["triangles"]["max"])).is_equal(9000.0)
	assert_int(int(rep["triangle_peak_frame"])).is_equal(4)


func test_unknown_days_never_count_as_tick_frames() -> void:
	var ms := PackedFloat32Array([5.0, 6.0, 7.0])
	var rep := PerfLogger.summarize(ms, PackedFloat32Array(), PackedFloat32Array(), PackedInt32Array([-1, -1, -1]))
	assert_int(int(rep["tick_frame_ms"]["count"])).is_equal(0)
	assert_int(int(rep["non_tick_frame_ms"]["count"])).is_equal(3)


func test_stable_phase_starts_after_configured_seconds_of_frame_time() -> void:
	var logger := _logger(TMP_DIR + "stable.json")
	logger.stable_after_s = 1.0  # 1 sn = 100 kare x 10 ms
	for k in 150:
		logger.record_frame(10.0 if k < 100 else 20.0, 300.0, 400000.0, k)
	var rep := PerfLogger.summarize(logger._ms, logger._draws, logger._prims, logger._days, logger._stable_start)
	assert_int(int(rep["stable"]["from_frame"])).is_equal(101)
	assert_int(int(rep["stable"]["frame_ms"]["count"])).is_equal(50)
	assert_float(float(rep["stable"]["frame_ms"]["mean"])).is_equal(20.0)


func test_stable_phase_not_reached_is_reported_honestly() -> void:
	var rep := PerfLogger.summarize(_series(10), PackedFloat32Array(), PackedFloat32Array(), PackedInt32Array(), -1)
	assert_bool(bool(rep["stable"]["reached"])).is_false()


# --- Dosya ---

func test_flush_writes_parseable_json_with_environment_fields() -> void:
	var path := TMP_DIR + "ok.json"
	var logger := _logger(path)
	for k in 30:
		logger.record_frame(float(k + 1), 300.0 + k, 400000.0, k / 5)
	add_child(logger)
	assert_int(logger.flush("complete")).is_equal(OK)
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert_bool(parsed is Dictionary).is_true()
	var rep: Dictionary = parsed
	assert_int(int(rep["frames"])).is_equal(30)
	assert_float(float(rep["frame_ms"]["max"])).is_equal(30.0)
	assert_str(String(rep["os"])).is_equal(OS.get_name())
	assert_str(String(rep["renderer"]["method"])).is_not_empty()
	assert_str(String(rep["godot"])).starts_with("4.")
	assert_str(String(rep["reason"])).is_equal("complete")
	assert_bool(bool(rep["complete"])).is_true()
	assert_int((rep["worst_frames"] as Array).size()).is_equal(20)


func test_unwritable_path_does_not_crash_and_reports_the_error() -> void:
	# Üst "dizin" aslında sıradan bir dosya: ne dizin açılabilir ne dosya yazılabilir (ayrıcalık gerekmez).
	var blocker := TMP_DIR + "blocker"
	var f := FileAccess.open(blocker, FileAccess.WRITE)
	f.store_string("x")
	f.close()
	var logger := _logger(blocker + "/sub/perf.json")
	for k in 10:
		logger.record_frame(8.0, 300.0, 400000.0, k)
	add_child(logger)
	var err := logger.flush("periodic")
	assert_bool(err != OK).is_true()
	assert_bool(logger.last_error != OK).is_true()
	# Ölçüm bellekte duruyor, oyun devam edebilir; bir sonraki kare kaydı da çalışır.
	logger.record_frame(9.0, 300.0, 400000.0, 10)
	assert_int(logger.frame_count()).is_equal(11)
	assert_bool(logger.flush("periodic") != OK).is_true()
	# Düğüm ağaçtan çıkarken yapılan "exit" yazımı da (engelleyici hâlâ yerinde) çökmeden başarısız olur.
	remove_child(logger)
	assert_bool(logger.last_error != OK).is_true()
	assert_bool(FileAccess.file_exists(blocker + "/sub/perf.json")).is_false()


func test_write_report_returns_error_instead_of_crashing_for_unwritable_path() -> void:
	var blocker := TMP_DIR + "blocker2"
	var f := FileAccess.open(blocker, FileAccess.WRITE)
	f.close()
	assert_bool(PerfLogger.write_report(blocker + "/a/b.json", {"x": 1}) != OK).is_true()


func test_flush_with_no_frames_writes_nothing() -> void:
	var path := TMP_DIR + "empty.json"
	var logger := _logger(path)
	assert_int(logger.flush("exit")).is_equal(OK)
	assert_bool(FileAccess.file_exists(path)).is_false()


# --- Açma / sıfır maliyet ---

func test_without_flag_env_or_feature_no_node_is_added() -> void:
	var host: Node = auto_free(Node.new())
	var before := host.get_child_count()
	assert_object(PerfLogger.attach_if_requested(host, {})).is_null()
	assert_object(PerfLogger.attach_if_requested(host, {"demo": true, "quit-after": "180"})).is_null()
	assert_int(host.get_child_count()).is_equal(before)
	assert_bool(PerfLogger.requested({})).is_false()


func test_perf_log_flag_adds_exactly_one_logger_with_given_path() -> void:
	var host: Node = auto_free(Node.new())
	add_child(host)
	var logger := PerfLogger.attach_if_requested(host, {"perf-log": "t076.json", "perf-log-frames": "6000"})
	assert_object(logger).is_not_null()
	assert_int(host.get_child_count()).is_equal(1)
	assert_str(logger.out_path).is_equal("user://perf/t076.json")
	assert_int(logger.complete_at_frames).is_equal(6000)
	assert_int(logger.write_every).is_equal(PerfLogger.DEFAULT_WRITE_EVERY)


func test_bare_flag_uses_timestamped_default_path() -> void:
	var host: Node = auto_free(Node.new())
	add_child(host)
	var logger := PerfLogger.attach_if_requested(host, {"perf-log": true})
	assert_str(logger.out_path).starts_with("user://perf/perf-log-")
	assert_str(logger.out_path).ends_with(".json")


func test_env_variable_alone_turns_logging_on() -> void:
	OS.set_environment(PerfLogger.ENV_NAME, "1")
	var host: Node = auto_free(Node.new())
	add_child(host)
	assert_bool(PerfLogger.requested({})).is_true()
	var logger := PerfLogger.attach_if_requested(host, {})
	assert_object(logger).is_not_null()
	assert_str(logger.out_path).starts_with("user://perf/perf-log-")


func test_resolve_path_keeps_user_and_absolute_paths() -> void:
	assert_str(PerfLogger.resolve_path("user://x/a.json")).is_equal("user://x/a.json")
	assert_str(PerfLogger.resolve_path("/tmp/a.json")).is_equal("/tmp/a.json")
	assert_str(PerfLogger.resolve_path("a.json")).is_equal("user://perf/a.json")


func test_logger_reads_host_day_through_perf_tick_without_requiring_it() -> void:
	# Ev sahibinde perf_tick yoksa gün -1; _process yolu çökmez.
	var host: Node = auto_free(Node.new())
	add_child(host)
	var logger := PerfLogger.attach_if_requested(host, {"perf-log": TMP_DIR + "host.json"})
	logger._process(0.016)  # taban
	logger._process(0.016)  # ilk gerçek kare
	assert_int(logger.frame_count()).is_equal(1)
	assert_int(logger._days[0]).is_equal(-1)
