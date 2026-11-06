extends GdUnitTestSuite
## A1 (pencere başına döküm), A2 (kip etiketi) ve A3 (CPU hız yoklaması) alanları: sentetik kip A / kip B / karışık
## seriler `record_frame` ile beslenir (saat bağımsız). Kaynak:
## production/log/2026-11-06-teknik-direktor-busy-bimodal.md bölüm 2.
## Eski alanların geri uyumu `perf_logger_busy_test.gd` ve `perf_logger_env_test.gd` içinde.

const TMP_DIR := "user://perf_logger_modes_test/"
const HZ := 120.0  # aralık 8,333 ms: yakın eşiği 7,083 ms, aşma eşiği 12,5 ms


func before_test() -> void:
	OS.unset_environment(PerfLogger.ENV_NAME)
	_clean(TMP_DIR)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TMP_DIR))


func after_test() -> void:
	OS.unset_environment(PerfLogger.ENV_NAME)
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


# --- A1/A2/A3 (production/log/2026-11-06-teknik-direktor-busy-bimodal.md bölüm 2) ---------------------------------

## Kip A: 8 ms kare, busy 3,5 (pre 2, render_cpu 1): aralığa yakın kare yok, kullanım 0,4375.
func _feed_mode_a(logger: PerfLogger, frames: int) -> void:
	for k in frames:
		logger.record_frame(8.0, 300.0, 400000.0, k, 3.5, 2.0, 1.0)


## Kip B (iki modlu): her 4. kare 20 ms ve busy 15 (pre 10, render_cpu 4), diğerleri 8 ms ve busy 3. 4 kare = 44 ms.
func _feed_mode_b(logger: PerfLogger, groups: int) -> void:
	for g in groups:
		for j in 4:
			if j == 3:
				logger.record_frame(20.0, 300.0, 400000.0, g, 15.0, 10.0, 4.0)
			else:
				logger.record_frame(8.0, 300.0, 400000.0, g, 3.0, 2.0, 1.0)


func test_a1_window_fields_mode_a() -> void:
	var logger := _logger(TMP_DIR + "k.json")
	logger.window_s = 1.0  # 125 kare x 8 ms
	logger.note_refresh_hz(HZ)
	_feed_mode_a(logger, 250)
	var wins := logger.windows()
	assert_int(wins.size()).is_equal(2)
	var w: Dictionary = wins[0]
	assert_float(float(w["pre_draw_ms_mean"])).is_equal(2.0)
	assert_float(float(w["render_cpu_ms_mean"])).is_equal(1.0)
	assert_float(float(w["render_cpu_ms_p95"])).is_equal(1.0)
	assert_float(float(w["is_ms_mean"])).is_equal(3.0)
	assert_float(float(w["is_ms_p95"])).is_equal(3.0)
	assert_float(float(w["rest_ms_mean"])).is_equal(0.5)
	assert_float(float(w["busy_near_interval_frac"])).is_equal(0.0)
	assert_float(float(w["over_interval_frac"])).is_equal(0.0)
	assert_float(float(w["utilization"])).is_equal_approx(0.4375, 0.0005)
	assert_str(str(w["mode"])).is_equal("A")
	# Eski pencere alanları aynen duruyor.
	assert_float(float(w["busy_ms_p95"])).is_equal(3.5)
	assert_float(float(w["refresh_hz"])).is_equal(HZ)
	assert_int(int(w["frames"])).is_equal(125)


func test_a1_a2_window_fields_mode_b() -> void:
	var logger := _logger(TMP_DIR + "l.json")
	logger.window_s = 0.88  # 20 grup x 44 ms
	logger.note_refresh_hz(HZ)
	_feed_mode_b(logger, 40)
	var wins := logger.windows()
	assert_int(wins.size()).is_equal(2)
	var w: Dictionary = wins[0]
	assert_float(float(w["busy_near_interval_frac"])).is_equal(0.25)  # 15 ms >= 7,083
	assert_float(float(w["over_interval_frac"])).is_equal(0.25)  # 20 ms > 12,5
	assert_float(float(w["pre_draw_ms_mean"])).is_equal(4.0)  # (2+2+2+10)/4
	assert_float(float(w["render_cpu_ms_mean"])).is_equal(1.75)  # (1+1+1+4)/4
	assert_float(float(w["is_ms_mean"])).is_equal(5.75)
	assert_float(float(w["is_ms_p95"])).is_equal(14.0)
	assert_float(float(w["rest_ms_mean"])).is_equal(0.25)  # busy ort (3+3+3+15)/4 = 6,0; 6,0 - 5,75
	assert_str(str(w["mode"])).is_equal("B")


func test_a2_mixed_windows_are_labelled_per_window_and_counted() -> void:
	var logger := _logger(TMP_DIR + "m.json")
	logger.window_s = 0.88
	logger.note_refresh_hz(HZ)
	# 110 kare x 8 ms = 880 ms (kip A) x 2, sonra 20 grup (kip B) x 1.
	_feed_mode_a(logger, 110)
	_feed_mode_a(logger, 110)
	_feed_mode_b(logger, 20)
	var wins := logger.windows()
	assert_int(wins.size()).is_equal(3)
	assert_array([wins[0]["mode"], wins[1]["mode"], wins[2]["mode"]]).is_equal(["A", "A", "B"])
	var counts := PerfLogger.mode_counts(wins)
	assert_int(int(counts["A"])).is_equal(2)
	assert_int(int(counts["B"])).is_equal(1)
	assert_int(int(counts["unknown"])).is_equal(0)
	# JSON'a üst düzey mode_windows + üst düzey/stable A1 alanları + thermal is_* yazılır.
	logger.stable_after_s = 0.0
	add_child(logger)
	assert_int(logger.flush("complete")).is_equal(OK)
	var rep: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(TMP_DIR + "m.json"))
	assert_int(int(rep["mode_windows"]["A"])).is_equal(2)
	assert_int(int(rep["mode_windows"]["B"])).is_equal(1)
	for key in ["is_ms_mean", "is_ms_p95", "rest_ms_mean", "busy_near_interval_frac", "over_interval_frac",
			"pre_draw_ms_mean", "render_cpu_ms_mean", "render_cpu_ms_p95"]:
		assert_bool(rep.has(key)).is_true()
	assert_float(float(rep["busy_near_interval_frac"])).is_greater(0.0)  # B penceresindeki yakın kareler
	assert_int(int(rep["format"])).is_equal(2)  # eski tüketiciler için format sabit
	assert_int(int(rep["extras_version"])).is_equal(PerfLogger.EXTRAS_VERSION)
	assert_str(str(rep["windows"][2]["mode"])).is_equal("B")


func test_a2_thresholds_are_strict_and_unmeasured_is_unknown() -> void:
	assert_str(PerfLogger.window_mode(0.19, 0.49)).is_equal("A")
	assert_str(PerfLogger.window_mode(0.2, 0.1)).is_equal("B")  # near sınırda B
	assert_str(PerfLogger.window_mode(0.0, 0.5)).is_equal("B")  # kullanım sınırda B
	assert_str(PerfLogger.window_mode(0.0, 0.9)).is_equal("B")
	assert_str(PerfLogger.window_mode(-1.0, 0.3)).is_equal("?")
	assert_str(PerfLogger.window_mode(0.0, -1.0)).is_equal("?")
	assert_float(PerfLogger.MODE_NEAR_FRAC_MAX).is_equal(0.2)
	assert_float(PerfLogger.MODE_UTILIZATION_MAX).is_equal(0.5)


func test_a1_unknowns_are_minus_one_not_zero() -> void:
	# Yenileme hızı bilinmiyor: oranlar -1; render ölçümü kapalı: is/rest -1 ama pre_draw ortalaması geçerli.
	var logger := _logger(TMP_DIR + "n.json")
	for k in 10:
		logger.record_frame(8.0, 0.0, 0.0, k, 3.0, 2.0, -1.0)
	var rep := PerfLogger.summarize(logger._ms, logger._draws, logger._prims, logger._days, -1, logger._busy,
			logger._pre_draw, logger._render_cpu)
	assert_float(float(rep["busy_near_interval_frac"])).is_equal(-1.0)
	assert_float(float(rep["over_interval_frac"])).is_equal(-1.0)
	assert_float(float(rep["pre_draw_ms_mean"])).is_equal(2.0)
	assert_float(float(rep["render_cpu_ms_mean"])).is_equal(-1.0)
	assert_float(float(rep["is_ms_mean"])).is_equal(-1.0)
	assert_float(float(rep["is_ms_p95"])).is_equal(-1.0)
	assert_float(float(rep["rest_ms_mean"])).is_equal(-1.0)
	# Hiç busy yok + yenileme hızı var: mod "?" (A ya da B uydurulmaz).
	var plain := PerfLogger.interval_block(PackedFloat32Array(), PackedFloat32Array(), PackedFloat32Array(),
			PackedFloat32Array([8.0]), HZ)
	assert_float(float(plain["busy_near_interval_frac"])).is_equal(-1.0)
	assert_float(float(plain["over_interval_frac"])).is_equal(0.0)
	assert_str(PerfLogger.window_mode(float(plain["busy_near_interval_frac"]), -1.0)).is_equal("?")


func test_a1_summarize_top_level_and_stable_carry_interval_fields() -> void:
	var logger := _logger(TMP_DIR + "o.json")
	logger.stable_after_s = 0.44  # tam 10 grup: kararlı evre grup sınırından başlar
	_feed_mode_b(logger, 40)  # 160 kare, 1,76 s
	var rep := PerfLogger.summarize(logger._ms, logger._draws, logger._prims, logger._days, logger._stable_start,
			logger._busy, logger._pre_draw, logger._render_cpu, HZ)
	assert_float(float(rep["busy_near_interval_frac"])).is_equal(0.25)
	assert_float(float(rep["over_interval_frac"])).is_equal(0.25)
	assert_float(float(rep["stable"]["busy_near_interval_frac"])).is_equal(0.25)
	assert_float(float(rep["stable"]["is_ms_mean"])).is_equal(5.75)
	# Eski yanıt alanları değişmedi.
	assert_float(float(rep["busy_ms"]["mean"])).is_equal(6.0)
	assert_int(int(rep["frames"])).is_equal(160)


func test_a1_thermal_gets_is_p95_ratio() -> void:
	var ms := PackedFloat32Array()
	var pre := PackedFloat32Array()
	var rcpu := PackedFloat32Array()
	for k in 300:  # 3 s; uçlar 1 sn = 100 kare
		ms.append(10.0)
		pre.append(2.0 if k < 200 else 3.0)
		rcpu.append(1.0 if k < 200 else 1.5)
	var th := PerfLogger.thermal_summary(ms, 1.0, PackedFloat32Array(), pre, rcpu)
	assert_bool(bool(th["is_reached"])).is_true()
	assert_float(float(th["is_first_p95"])).is_equal(3.0)
	assert_float(float(th["is_last_p95"])).is_equal(4.5)
	assert_float(float(th["is_p95_ratio"])).is_equal_approx(1.5, 0.001)
	# pre/rcpu verilmezse eski ısıl çıktı: is_* yok.
	assert_bool(PerfLogger.thermal_summary(ms, 1.0).has("is_p95_ratio")).is_false()


func test_a3_probe_loop_is_deterministic_and_measured() -> void:
	var a := PerfLogger.cpu_probe_loop()
	assert_int(a).is_equal(PerfLogger.cpu_probe_loop())
	assert_int(a).is_not_equal(0)
	var us := PerfLogger.measure_cpu_probe_us()
	assert_int(us).is_greater_equal(0)
	assert_int(us).is_less(50000)  # makul üst sınır (50 ms); ölçülen değer rapora yazılır, burada sabitlenmez


func test_a3_probe_runs_once_per_second_of_frame_time_and_can_be_off() -> void:
	var logger := _logger(TMP_DIR + "p.json")
	for k in 99:
		logger.record_frame(10.0, 0.0, 0.0, k)
	assert_bool(logger.maybe_probe()).is_false()  # 990 ms: henüz saniye dolmadı
	logger.record_frame(10.0, 0.0, 0.0, 99)
	assert_bool(logger.maybe_probe()).is_true()  # 1000 ms
	assert_bool(logger.maybe_probe()).is_false()  # aynı saniyede ikinci kez yok
	assert_int(logger._probe_all.size()).is_equal(1)
	# Geç kalan döngü (kare süresi uzun): eşik tek adımda ilerler, yoklama yığılmaz.
	logger.record_frame(3500.0, 0.0, 0.0, 100)
	assert_bool(logger.maybe_probe()).is_true()
	assert_bool(logger.maybe_probe()).is_false()
	assert_int(logger._probe_all.size()).is_equal(2)
	# Kapalıyken hiç yoklama ve atılan döngü yok.
	var off := _logger(TMP_DIR + "q.json")
	off.cpu_probe = false
	off.record_frame(5000.0, 0.0, 0.0, 0)
	assert_bool(off.maybe_probe()).is_false()
	assert_bool(off._discard_cycle).is_false()
	assert_int(off._probe_all.size()).is_equal(0)


func test_a3_probe_cycle_busy_is_discarded_from_summary() -> void:
	var logger := _logger(TMP_DIR + "r.json")
	add_child(logger)
	logger.record_frame(1000.0, 0.0, 0.0, 0)
	logger._on_cycle_start()  # yoklamanın içinde koşacağı döngü
	assert_bool(logger.maybe_probe()).is_true()
	OS.delay_usec(1000)
	logger._on_post_draw()
	assert_float(logger._busy_done).is_equal(-1.0)  # yoklama maliyeti busy'ye girmez
	assert_float(logger._pre_done).is_equal(-1.0)
	# Sonraki döngü normal ölçülür.
	logger._on_cycle_start()
	logger._on_post_draw()
	assert_float(logger._busy_done).is_greater_equal(0.0)


func test_a3_window_carries_probe_min_p50_and_resets_per_window() -> void:
	var logger := _logger(TMP_DIR + "s.json")
	logger.window_s = 1.0
	logger.note_refresh_hz(HZ)
	logger.record_probe(300.0)
	logger.record_probe(100.0)
	logger.record_probe(200.0)
	_feed_mode_a(logger, 250)
	var wins := logger.windows()
	assert_int(wins.size()).is_equal(2)
	assert_float(float(wins[0]["cpu_probe_us_min"])).is_equal(100.0)
	assert_float(float(wins[0]["cpu_probe_us_p50"])).is_equal(200.0)
	assert_int(int(wins[0]["cpu_probe_count"])).is_equal(3)
	# İkinci pencerede yoklama yok: -1 (0 değil), sayaç sıfırlandı.
	assert_float(float(wins[1]["cpu_probe_us_min"])).is_equal(-1.0)
	assert_int(int(wins[1]["cpu_probe_count"])).is_equal(0)
	add_child(logger)
	logger.flush("complete")
	var rep: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(TMP_DIR + "s.json"))
	assert_int(int(rep["cpu_probe_us"]["count"])).is_equal(3)
	assert_float(float(rep["cpu_probe_us"]["min"])).is_equal(100.0)
	assert_bool(bool(rep["cpu_probe_enabled"])).is_true()
	assert_int(int(rep["cpu_probe_iterations"])).is_equal(PerfLogger.PROBE_ITERATIONS)


func test_a3_flag_turns_probe_off_and_default_is_on() -> void:
	var on := PerfLogger.attach_if_requested(self, {"perf-log": TMP_DIR + "t.json"})
	assert_bool(on.cpu_probe).is_true()
	var off := PerfLogger.attach_if_requested(self, {
			"perf-log": TMP_DIR + "u.json", "perf-log-no-cpu-probe": ""})
	assert_bool(off.cpu_probe).is_false()


func test_a1_interval_boundaries_are_inclusive_for_near_and_strict_for_over() -> void:
	# 100 Hz: aralık 10 ms; yakın eşiği 8,5 ms (>=), aşma eşiği 15 ms (>).
	var busy := PackedFloat32Array([8.5, 8.5, 8.25, 8.25])
	var ms := PackedFloat32Array([15.0, 15.0, 15.5, 15.5])
	var blk := PerfLogger.interval_block(busy, PackedFloat32Array(), PackedFloat32Array(), ms, 100.0)
	assert_float(float(blk["busy_near_interval_frac"])).is_equal(0.5)
	assert_float(float(blk["over_interval_frac"])).is_equal(0.5)
