extends GdUnitTestSuite
## ADR-0010 Karar 3a: PerfLogger CPU meşgul süresi (`busy_ms`), dökümü (`pre_draw_ms`, `render_cpu_ms`), kullanım
## (`utilization`), ısıl pencerelerde busy p95 ve `refresh_hz` izleme. Sentetik seri `record_frame` ile beslenir
## (saat bağımsız); canlı sinyal hattı için kare başlangıç/çizim öncesi/sonrası işleyicileri doğrudan çağrılır
## (dummy renderer gerçek `frame_post_draw` yayınlamayabilir; gerçek sinyal sırası masaüstü kalibrasyonunda ölçüldü).

const TMP_DIR := "user://perf_logger_busy_test/"


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


## n kare: kare süresi 10 ms, busy 6 ms (pre_draw 4, render_cpu 1,5); utilization = 0,6.
func _feed(logger: PerfLogger, n: int, with_busy: bool = true) -> void:
	for k in n:
		if with_busy:
			logger.record_frame(10.0, 300.0, 400000.0, k, 6.0, 4.0, 1.5)
		else:
			logger.record_frame(10.0, 300.0, 400000.0, k)


func test_summarize_reports_busy_pre_draw_render_cpu_and_utilization() -> void:
	var logger := _logger(TMP_DIR + "a.json")
	logger.stable_after_s = 0.5  # 50 kare x 10 ms
	_feed(logger, 150)
	var rep := PerfLogger.summarize(logger._ms, logger._draws, logger._prims, logger._days, logger._stable_start,
			logger._busy, logger._pre_draw, logger._render_cpu)
	assert_int(int(rep["busy_ms"]["count"])).is_equal(150)
	assert_float(float(rep["busy_ms"]["mean"])).is_equal(6.0)
	assert_float(float(rep["busy_ms"]["p95"])).is_equal(6.0)
	assert_float(float(rep["pre_draw_ms"]["mean"])).is_equal(4.0)
	assert_float(float(rep["render_cpu_ms"]["mean"])).is_equal(1.5)
	assert_float(float(rep["utilization"])).is_equal_approx(0.6, 0.0005)
	assert_int(int(rep["busy_over_frame"])).is_equal(0)
	# Kararlı pencere: kare 51'den başlar, 100 kare.
	assert_int(int(rep["stable"]["from_frame"])).is_equal(51)
	assert_int(int(rep["stable"]["busy_ms"]["count"])).is_equal(100)
	assert_float(float(rep["stable"]["busy_ms"]["mean"])).is_equal(6.0)
	assert_float(float(rep["stable"]["utilization"])).is_equal_approx(0.6, 0.0005)
	# Mantık: busy hiçbir kare süresini aşmaz, negatif yok.
	assert_float(float(rep["busy_ms"]["max"])).is_less_equal(float(rep["frame_ms"]["max"]))
	assert_float(float(rep["busy_ms"]["min"])).is_greater_equal(0.0)


func test_unmeasured_frames_are_excluded_not_counted_as_zero() -> void:
	var logger := _logger(TMP_DIR + "b.json")
	logger.record_frame(10.0, 0.0, 0.0, 0, 8.0, 5.0, 2.0)
	logger.record_frame(10.0, 0.0, 0.0, 0)  # ölçülemedi: -1
	logger.record_frame(10.0, 0.0, 0.0, 0, 4.0, 3.0, 1.0)
	var rep := PerfLogger.summarize(logger._ms, logger._draws, logger._prims, logger._days, -1, logger._busy,
			logger._pre_draw, logger._render_cpu)
	assert_int(int(rep["busy_ms"]["count"])).is_equal(2)
	assert_float(float(rep["busy_ms"]["mean"])).is_equal(6.0)
	assert_float(float(rep["busy_ms"]["min"])).is_equal(4.0)
	# Kullanım yalnız ölçülmüş karelerde: (8+4)/(10+10) = 0,6 (üç karede olsaydı 0,4).
	assert_float(float(rep["utilization"])).is_equal_approx(0.6, 0.0005)


func test_busy_over_frame_counts_pairs_where_busy_exceeds_frame_time() -> void:
	var rep := PerfLogger.summarize(PackedFloat32Array([10.0, 10.0]), PackedFloat32Array(), PackedFloat32Array(),
			PackedInt32Array(), -1, PackedFloat32Array([9.0, 14.0]))
	assert_int(int(rep["busy_over_frame"])).is_equal(1)


func test_without_busy_data_the_report_says_so_and_old_fields_are_unchanged() -> void:
	# Olumsuz kontrol: busy verilmezse busy_ms count 0, kullanım -1 (uydurma değer yok). Yukarıdaki testin
	# `count == 150` beklentisi bu durumda düşerdi.
	var logger := _logger(TMP_DIR + "c.json")
	logger.stable_after_s = 0.5
	_feed(logger, 150, false)
	var rep := PerfLogger.summarize(logger._ms, logger._draws, logger._prims, logger._days, logger._stable_start,
			logger._busy, logger._pre_draw, logger._render_cpu)
	assert_int(int(rep["busy_ms"]["count"])).is_equal(0)
	assert_int(int(rep["stable"]["busy_ms"]["count"])).is_equal(0)
	assert_float(float(rep["utilization"])).is_equal(-1.0)
	# Eski çağrı biçimi (busy dizileri hiç verilmeden) çökmez ve eski alanlar aynı.
	var old := PerfLogger.summarize(logger._ms, logger._draws, logger._prims, logger._days, logger._stable_start)
	assert_int(int(old["frames"])).is_equal(150)
	assert_float(float(old["frame_ms"]["mean"])).is_equal(10.0)
	assert_int(int(old["stable"]["from_frame"])).is_equal(51)
	assert_float(float(old["stable"]["frame_ms"]["mean"])).is_equal(10.0)
	assert_int(int(old["stable"]["busy_ms"]["count"])).is_equal(0)
	for key in ["tick_frame_ms", "non_tick_frame_ms", "draw_calls", "triangles", "worst_frames"]:
		assert_bool(old.has(key)).is_true()


func test_flush_json_keeps_t076_fields_and_adds_busy_fields() -> void:
	var path := TMP_DIR + "d.json"
	var logger := _logger(path)
	logger.stable_after_s = 0.5
	_feed(logger, 120)
	add_child(logger)
	assert_int(logger.flush("complete")).is_equal(OK)
	var rep: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	# T-076 betiklerinin okuduğu alanlar.
	for key in ["frame_ms", "stable", "refresh_hz", "vsync_mode", "frames", "worst_frames", "memory", "startup"]:
		assert_bool(rep.has(key)).is_true()
	assert_float(float(rep["frame_ms"]["mean"])).is_equal(10.0)
	assert_int(int(rep["stable"]["frame_ms"]["count"])).is_equal(70)
	# Yeni alanlar.
	assert_int(int(rep["busy_ms"]["count"])).is_equal(120)
	assert_float(float(rep["stable"]["busy_ms"]["p99"])).is_equal(6.0)
	assert_float(float(rep["stable"]["pre_draw_ms"]["mean"])).is_equal(4.0)
	assert_float(float(rep["stable"]["render_cpu_ms"]["mean"])).is_equal(1.5)
	assert_float(float(rep["stable"]["utilization"])).is_equal_approx(0.6, 0.0005)
	assert_bool(rep.has("refresh_hz_start")).is_true()
	assert_bool(bool(rep["refresh_hz_changed"])).is_false()


func test_windows_carry_busy_p95_and_refresh_hz_and_thermal_gets_busy_ratio() -> void:
	var logger := _logger(TMP_DIR + "e.json")
	logger.window_s = 1.0  # 100 kare x 10 ms
	logger.note_refresh_hz(120.0)
	# 3 pencere: busy 5 -> 5 -> 8 ms (CPU kısılması: kare süresi sabit kalır, busy artar).
	for k in 300:
		logger.record_frame(10.0, 300.0, 400000.0, k, 5.0 if k < 200 else 8.0, 3.0, 1.0)
	var wins := logger.windows()
	assert_int(wins.size()).is_equal(3)
	assert_float(float(wins[0]["busy_ms_p95"])).is_equal(5.0)
	assert_float(float(wins[2]["busy_ms_p95"])).is_equal(8.0)
	assert_float(float(wins[2]["refresh_hz"])).is_equal(120.0)
	var th := PerfLogger.thermal_summary(logger._ms, 1.0, logger._busy)
	assert_bool(bool(th["reached"])).is_true()
	assert_float(float(th["p95_ratio"])).is_equal(1.0)  # kare süresi VSync'te kısılmayı göstermez
	assert_bool(bool(th["busy_reached"])).is_true()
	assert_float(float(th["busy_p95_ratio"])).is_equal_approx(1.6, 0.001)
	assert_bool(bool(th["busy_within_limit"])).is_false()  # 1,6 > 1,25
	# busy verilmezse eski ısıl çıktı: busy alanları yok, mevcut alanlar duruyor.
	var plain := PerfLogger.thermal_summary(logger._ms, 1.0)
	assert_bool(plain.has("busy_p95_ratio")).is_false()
	assert_bool(bool(plain["within_limit"])).is_true()


func test_refresh_hz_change_inside_run_is_flagged() -> void:
	var logger := _logger(TMP_DIR + "f.json")
	logger.note_refresh_hz(120.0)
	logger.note_refresh_hz(120.04)  # gürültü sayılmaz
	assert_bool(logger._refresh_changed).is_false()
	logger.note_refresh_hz(60.0)  # Düşük Güç Modu gibi
	assert_bool(logger._refresh_changed).is_true()
	assert_float(logger._refresh_start).is_equal(120.0)
	_feed(logger, 5)
	add_child(logger)
	logger.flush("complete")
	var rep: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(TMP_DIR + "f.json"))
	assert_bool(bool(rep["refresh_hz_changed"])).is_true()
	assert_float(float(rep["refresh_hz_start"])).is_equal(120.0)


func test_live_cycle_pairs_busy_with_the_next_frame_and_orders_pre_draw_before_busy() -> void:
	var logger := _logger(TMP_DIR + "g.json")
	add_child(logger)
	assert_bool(logger._signals_connected).is_true()
	logger._process(0.016)  # taban
	# Bir döngü: physics_frame (ilk) + process_frame (ikinci, no-op) -> pre_draw -> post_draw.
	logger._on_cycle_start()
	var first_start := logger._cycle_start_us
	OS.delay_usec(2000)
	logger._on_cycle_start()
	assert_int(logger._cycle_start_us).is_equal(first_start)  # ikinci başlangıç sinyali süreyi değiştirmez
	OS.delay_usec(2000)
	logger._on_pre_draw()
	OS.delay_usec(2000)
	logger._on_post_draw()
	logger._process(0.016)  # sonraki kare: busy + dt birlikte kaydedilir
	assert_int(logger.frame_count()).is_equal(1)
	var busy := logger._busy[0]
	var pre := logger._pre_draw[0]
	assert_float(busy).is_greater_equal(5.5)  # en az 2+2+2 ms bekledik
	assert_float(pre).is_greater_equal(3.5)
	assert_float(pre).is_less(busy)
	# Aynı busy bir sonraki kareye taşınmaz (tüketilir): çizim yoksa -1.
	logger._process(0.016)
	assert_float(logger._busy[1]).is_equal(-1.0)


func test_post_draw_without_cycle_start_and_baseline_frame_record_nothing() -> void:
	var logger := _logger(TMP_DIR + "h.json")
	add_child(logger)
	logger._on_post_draw()  # başlangıcı görülmeyen döngü
	assert_float(logger._busy_done).is_equal(-1.0)
	logger._on_cycle_start()
	logger._on_post_draw()
	assert_float(logger._busy_done).is_greater_equal(0.0)
	logger._process(0.016)  # taban kare: bekleyen busy bu ölçüme ait değil, atılır
	assert_float(logger._busy_done).is_equal(-1.0)


func test_discarded_cycle_after_flush_is_not_recorded() -> void:
	var logger := _logger(TMP_DIR + "i.json")
	add_child(logger)
	logger._discard_cycle = true
	logger._on_cycle_start()
	OS.delay_usec(1000)
	logger._on_post_draw()
	assert_float(logger._busy_done).is_equal(-1.0)
	assert_bool(logger._discard_cycle).is_false()


func test_signals_are_disconnected_on_complete_and_only_exist_while_logger_lives() -> void:
	var before := RenderingServer.frame_post_draw.get_connections().size()
	# Bayrak yoksa düğüm da bağlantı da yok.
	var host: Node = auto_free(Node.new())
	assert_object(PerfLogger.attach_if_requested(host, {})).is_null()
	assert_int(RenderingServer.frame_post_draw.get_connections().size()).is_equal(before)
	var logger := _logger(TMP_DIR + "j.json")
	add_child(logger)
	assert_int(RenderingServer.frame_post_draw.get_connections().size()).is_equal(before + 1)
	_feed(logger, 3)
	logger.mark_complete()
	assert_bool(logger._signals_connected).is_false()
	assert_int(RenderingServer.frame_post_draw.get_connections().size()).is_equal(before)
	assert_bool(get_tree().process_frame.is_connected(logger._on_cycle_start)).is_false()


func test_render_measure_is_on_by_default_and_the_flag_turns_it_off_and_is_reported() -> void:
	var on := PerfLogger.attach_if_requested(self, {"perf-log": TMP_DIR + "on.json"})
	assert_object(on).is_not_null()
	assert_bool(on.measure_render).is_true()
	var off := PerfLogger.attach_if_requested(self, {
			"perf-log": TMP_DIR + "off.json", "perf-log-no-render-measure": ""})
	assert_object(off).is_not_null()
	assert_bool(off.measure_render).is_false()
	off.stable_after_s = 0.5
	_feed(off, 120)
	assert_int(off.flush("complete")).is_equal(OK)
	var rep: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(off.out_path))
	assert_bool(bool(rep["render_measure"])).is_false()
