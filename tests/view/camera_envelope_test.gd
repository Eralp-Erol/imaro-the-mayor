extends GdUnitTestSuite
## T-064 ölçüt 1, 5, 6, 7 · Kamera zarfı VERİDİR (data/view/camera_envelope.json): yükleme + doğrulayıcı (olumsuz
## testler), kodda gömülü sınır yok (tarama), ölçek bandı histerezisi, legacy bayrağı yalnız geliştirici derlemesinde,
## simülasyon zarfı/bandı okumaz (tarama).

const DATA := "res://data/view/camera_envelope.json"

var _raw: Dictionary


func before() -> void:
	_raw = JSON.parse_string(FileAccess.get_file_as_string(DATA))


func _player() -> Dictionary:
	return (_raw["player"] as Dictionary).duplicate(true)


# --- Yükleme ve doğrulayıcı ---

func test_the_player_and_legacy_envelopes_load_from_the_data_file_without_errors() -> void:
	var player := CameraEnvelope.load_default()
	assert_array(Array(player.errors)).is_empty()
	assert_float(player.d_min_m).is_equal(float((_raw["player"] as Dictionary)["d_min_m"]))
	assert_float(player.d_max_m).is_equal(float((_raw["player"] as Dictionary)["d_max_m"]))
	# D-006 kullanıcı kararı (ÇALIŞMA DEĞERİ): ~18 km tavan, ~50 m en yakın bakış.
	assert_float(player.d_max_m).is_equal(18000.0)
	assert_float(player.d_min_m).is_equal(50.0)
	assert_bool(player.k1_enabled).is_true()
	assert_bool(player.is_legacy()).is_false()
	var legacy := CameraEnvelope.legacy()
	assert_array(Array(legacy.errors)).is_empty()
	assert_bool(legacy.is_legacy()).is_true()
	assert_bool(legacy.k1_enabled).is_false()
	assert_float(legacy.d_min_m).is_equal(25.0)
	assert_float(legacy.d_max_m).is_equal(90000.0)
	assert_float(legacy.pitch_min_deg(1000.0)).is_equal(8.0)


func test_the_pitch_floor_is_a_log_distance_piecewise_linear_curve_from_the_data() -> void:
	var env := CameraEnvelope.load_default()
	for pt in env.pitch_curve:
		assert_float(env.pitch_min_deg(pt.x)).is_equal_approx(pt.y, 0.0001)  # düğüm noktaları
	var a := env.pitch_curve[1]
	var b := env.pitch_curve[2]
	var mid := sqrt(a.x * b.x)  # log-ortası -> eğim ortası
	assert_float(env.pitch_min_deg(mid)).is_equal_approx((a.y + b.y) * 0.5, 0.0001)
	assert_float(env.pitch_min_deg(1.0)).is_equal(env.pitch_curve[0].y)  # aralık dışı kenetlenir
	assert_float(env.pitch_min_deg(1.0e9)).is_equal(env.pitch_curve[env.pitch_curve.size() - 1].y)
	var last := -1.0
	for d in [50.0, 100.0, 300.0, 700.0, 1500.0, 6000.0, 18000.0]:
		assert_float(env.pitch_min_deg(d)).is_greater_equal(last)  # monoton
		last = env.pitch_min_deg(d)


func test_validator_rejects_a_non_monotonic_pitch_curve() -> void:
	var d := _player()
	d["pitch_min_curve"] = [[50.0, 3.0], [600.0, 30.0], [1500.0, 25.0], [18000.0, 40.0]]
	assert_str(", ".join(CameraEnvelope.validate(d))).contains("monoton")
	# Yataya yakın düz parçadan SONRA düşen eğri de reddedilir (monoton olmayan taban, yeni düğümlerle).
	var dip := _player()
	dip["pitch_min_curve"] = [[50.0, 3.0], [600.0, 3.0], [900.0, 20.0], [1500.0, 5.0], [18000.0, 40.0]]
	assert_str(", ".join(CameraEnvelope.validate(dip))).contains("monoton")
	var env := CameraEnvelope.from_dict(d, &"bad")
	assert_array(Array(env.errors)).is_not_empty()


func test_validator_rejects_a_curve_whose_distances_do_not_increase_or_do_not_cover_the_range() -> void:
	var d := _player()
	d["pitch_min_curve"] = [[50.0, 12.0], [50.0, 22.0], [18000.0, 40.0]]
	assert_str(", ".join(CameraEnvelope.validate(d))).contains("artmıyor")
	var e := _player()
	e["pitch_min_curve"] = [[100.0, 12.0], [18000.0, 40.0]]  # 50 m'yi kapsamıyor
	assert_str(", ".join(CameraEnvelope.validate(e))).contains("kapsamıyor")


func test_validator_rejects_a_k1_entry_pitch_below_half_fov_plus_epsilon() -> void:
	var d := _player()
	d["pitch_min_curve"] = [[50.0, 3.0], [600.0, 3.0], [1500.0, 18.9], [18000.0, 40.0]]  # K1 girişi (1500 m) 18,9 < 21
	var errors := CameraEnvelope.validate(d)
	assert_str(", ".join(errors)).contains("K1'e girişte eğim sıçrar")
	# Yatay taban K1 girişine kadar uzatılırsa (yatay serbest bölge K1 bandına taşar) doğrulayıcı reddeder.
	var flat := _player()
	flat["pitch_min_curve"] = [[50.0, 3.0], [1500.0, 3.0], [18000.0, 40.0]]
	assert_str(", ".join(CameraEnvelope.validate(flat))).contains("K1'e girişte eğim sıçrar")
	# K1 kapalıysa bu kural geçerli değil (legacy).
	d["k1_enabled"] = false
	assert_array(Array(CameraEnvelope.validate(d))).is_empty()
	# FOV büyüdükçe eşik yükselir: 22 derece, 50 derece FOV'da (25+1) yetmez.
	assert_str(", ".join(CameraEnvelope.validate(_player(), 50.0))).contains("K1'e girişte")


func test_validator_rejects_d_min_not_below_d_max_and_missing_fields() -> void:
	var d := _player()
	d["d_min_m"] = 18000.0
	assert_str(", ".join(CameraEnvelope.validate(d))).contains("d_min_m")
	var e := _player()
	e["d_min_m"] = 20000.0
	assert_array(Array(CameraEnvelope.validate(e))).is_not_empty()
	var f := _player()
	f.erase("edge_margin_m")
	assert_str(", ".join(CameraEnvelope.validate(f))).contains("edge_margin_m")


func test_validator_rejects_band_gaps_overlaps_and_wrong_ends() -> void:
	var gap := _player()
	gap["bands"] = [{"name": "street", "min_m": 50.0, "max_m": 300.0},
			{"name": "neighborhood", "min_m": 400.0, "max_m": 1500.0},
			{"name": "district", "min_m": 1500.0, "max_m": 8000.0}, {"name": "metro", "min_m": 8000.0, "max_m": 18000.0}]
	assert_str(", ".join(CameraEnvelope.validate(gap))).contains("bant boşluğu")
	var overlap := _player()
	overlap["bands"] = [{"name": "street", "min_m": 50.0, "max_m": 400.0},
			{"name": "neighborhood", "min_m": 300.0, "max_m": 1500.0},
			{"name": "district", "min_m": 1500.0, "max_m": 8000.0}, {"name": "metro", "min_m": 8000.0, "max_m": 18000.0}]
	assert_str(", ".join(CameraEnvelope.validate(overlap))).contains("bant boşluğu/çakışma")
	var short := _player()
	short["bands"] = [{"name": "street", "min_m": 50.0, "max_m": 300.0}]
	assert_str(", ".join(CameraEnvelope.validate(short))).contains("d_max_m")
	var dup := _player()
	(dup["bands"] as Array)[1]["name"] = "street"
	assert_str(", ".join(CameraEnvelope.validate(dup))).contains("tekrar")


func test_validator_rejects_bad_gates_hysteresis_and_a_pan_order_that_changes_the_distance() -> void:
	var gates := _player()
	gates["zoom_gates_m"] = [50.0, 800.0, 150.0, 18000.0]
	assert_str(", ".join(CameraEnvelope.validate(gates))).contains("artmıyor")
	var outside := _player()
	outside["zoom_gates_m"] = [50.0, 150.0, 90000.0]
	assert_str(", ".join(CameraEnvelope.validate(outside))).contains("zarf dışında")
	var hyst := _player()
	hyst["hysteresis"] = 0.6
	assert_str(", ".join(CameraEnvelope.validate(hyst))).contains("hysteresis")
	var pan := _player()
	pan["solve_order"] = {"default": ["pitch", "distance", "focus"], "pan": ["pitch", "distance", "focus"]}
	assert_str(", ".join(CameraEnvelope.validate(pan))).contains("pan")
	var unknown := _player()
	unknown["solve_order"] = {"default": ["pitch", "zoom"], "pan": ["pitch", "focus"]}
	assert_str(", ".join(CameraEnvelope.validate(unknown))).contains("bilinmeyen adım")


func test_loading_a_missing_envelope_reports_an_error_instead_of_guessing_numbers() -> void:
	var env := CameraEnvelope.from_dict({}, &"empty")
	assert_array(Array(env.errors)).is_not_empty()
	assert_float(env.d_max_m).is_equal(0.0)  # uydurma değer yok


# --- Statik tarama: kodda sınır sayısı gömülü değil ---

func _strip_comment(line: String) -> String:
	var hash_at := line.find("#")
	return line if hash_at < 0 else line.substr(0, hash_at)


func _code_lines(path: String) -> Array[String]:
	var out: Array[String] = []
	for line in FileAccess.get_file_as_string(path).split("\n"):
		out.append(_strip_comment(line))
	return out


func _gd_files(dir: String) -> Array[String]:
	var out: Array[String] = []
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		out.append_array(_gd_files(dir.path_join(d)))
	return out


func test_no_envelope_limit_is_hard_coded_in_the_camera_or_game_code() -> void:
	var p := _raw["player"] as Dictionary
	var forbidden: Array[String] = []
	# Yalnız başka kodla çakışmayan büyüklükler: tavan, harita çıkış mesafesi, metro bandı alt sınırı (8 km).
	# (300 / 1500 / 4000 gibi sayılar başka sabitlerle çakışır; zarf-dışı kullanımları kapsam dışı bırakılır.)
	for key in ["d_max_m", "map_exit_distance_m"]:
		forbidden.append(str(int(p[key])))
	forbidden.append(str(int((p["bands"] as Array)[2]["max_m"])))
	var pattern := RegEx.new()
	pattern.compile("(?<![0-9._])(%s)(\\.0)?(?![0-9_])" % "|".join(forbidden))
	var hits: Array[String] = []
	for dir in ["res://src/view/camera", "res://src/game"]:
		for path in _gd_files(dir):
			var n := 0
			for line in _code_lines(path):
				n += 1
				if pattern.search(line) != null:
					hits.append("%s:%d: %s" % [path, n, line.strip_edges()])
	assert_array(hits).override_failure_message("gömülü sınır: %s" % "\n".join(hits)).is_empty()


func test_the_scan_pattern_is_sensitive_it_does_find_a_hard_coded_ceiling() -> void:
	var pattern := RegEx.new()
	pattern.compile("(?<![0-9._])(18000)(\\.0)?(?![0-9_])")
	assert_object(pattern.search("const MAX := 18000.0")).is_not_null()
	assert_object(pattern.search("x = 118000.0")).is_null()


func test_the_start_path_embeds_no_district_id() -> void:
	# Açılış/Home yolunda ilçe kimliği yok (değer oturumdan/veriden; yoksa core).
	# T-001 dev preset'leri (legacy) bu yolun dışında.
	var id_pattern := RegEx.new()
	id_pattern.compile("\\bD[1-9]\\b")
	var hits: Array[String] = []
	var files: Array[String] = ["res://src/view/camera/camera_rig.gd", "res://src/view/camera/camera_envelope.gd",
			"res://src/view/camera/camera_sweep.gd", "res://scenes/dev/world_preview.gd"]
	files.append_array(_gd_files("res://src/game"))
	for path in files:
		for line in _code_lines(path):
			if id_pattern.search(line) != null:
				hits.append("%s: %s" % [path, line.strip_edges()])
	var presets := FileAccess.get_file_as_string("res://src/view/camera/camera_presets.gd")
	var from := presets.find("static func start_view")
	var start_fn := presets.substr(from, presets.find("static func core") - from)
	for line in start_fn.split("\n"):
		if id_pattern.search(_strip_comment(line)) != null:
			hits.append("start_view: %s" % line.strip_edges())
	assert_array(hits).override_failure_message("ilçe kimliği: %s" % "\n".join(hits)).is_empty()


func test_the_simulation_never_reads_the_envelope_bands_or_the_camera() -> void:
	var pattern := RegEx.new()
	pattern.compile("CameraEnvelope|camera_envelope|scale_band|CameraRig|CameraMath|CameraState|CameraPresets")
	var hits: Array[String] = []
	for path in _gd_files("res://src/sim"):
		for line in _code_lines(path):
			if pattern.search(line) != null:
				hits.append("%s: %s" % [path, line.strip_edges()])
	assert_array(hits).is_empty()
	assert_bool(_gd_files("res://src/sim").size() > 20).is_true()  # tarama gerçekten dosya buldu


# --- Ölçek bantları ---

func test_band_of_partitions_the_envelope_range_by_data() -> void:
	var env := CameraEnvelope.load_default()
	assert_str(String(env.band_of(env.d_min_m))).is_equal("street")
	assert_str(String(env.band_of(299.0))).is_equal("street")
	assert_str(String(env.band_of(300.0))).is_equal("neighborhood")
	assert_str(String(env.band_of(1499.0))).is_equal("neighborhood")
	assert_str(String(env.band_of(1500.0))).is_equal("district")
	assert_str(String(env.band_of(7999.0))).is_equal("district")
	assert_str(String(env.band_of(8000.0))).is_equal("metro")
	assert_str(String(env.band_of(env.d_max_m))).is_equal("metro")
	assert_str(String(CameraEnvelope.band_text_key(&"district"))).is_equal("zoom.district")


func test_band_hysteresis_makes_a_5_percent_oscillation_at_every_boundary_one_single_event() -> void:
	var env := CameraEnvelope.load_default()
	for i in range(0, env.bands.size() - 1):
		var edge := float(env.bands[i]["max_m"])
		var below := StringName(env.bands[i]["name"])
		var above := StringName(env.bands[i + 1]["name"])
		for start_below in [true, false]:
			var band := below if start_below else above
			var events := 0
			for k in 20:
				var d := edge * (0.95 if (k % 2 == 0) == start_below else 1.05)
				var next := env.next_band(d, band)
				if next != band:
					events += 1
				band = next
			assert_int(events).override_failure_message("sınır %s: %d olay" % [edge, events]).is_equal(0)
		# Eşiği (±%10) gerçekten aşınca değişir: tek olay.
		assert_str(String(env.next_band(edge * 1.11, below))).is_equal(String(above))
		assert_str(String(env.next_band(edge * 0.89, above))).is_equal(String(below))


func test_without_hysteresis_the_same_oscillation_would_chatter_so_the_test_is_sensitive() -> void:
	var env := CameraEnvelope.load_default()
	var edge := float(env.bands[0]["max_m"])
	var changes := 0
	var band := env.band_of(edge * 0.95)
	for k in 20:
		var next := env.band_of(edge * (1.05 if k % 2 == 0 else 0.95))
		if next != band:
			changes += 1
		band = next
	assert_int(changes).is_greater(10)


func test_fog_strength_is_full_in_the_street_band_and_gone_where_k1_takes_over() -> void:
	var env := CameraEnvelope.load_default()
	assert_float(env.fog_strength(env.d_min_m)).is_equal(1.0)
	assert_float(env.fog_strength(env.k1_min_distance_m)).is_equal(1.0)
	assert_float(env.fog_strength(env.fog_gone_above_m)).is_equal(0.0)
	assert_float(env.fog_strength(5000.0)).is_equal(0.0)
	assert_float(env.fog_strength(0.5 * (env.fog_full_below_m + env.fog_gone_above_m))).is_between(0.0, 1.0)
	assert_float(CameraEnvelope.legacy().fog_strength(60.0)).is_equal(0.0)  # legacy'de pus yok


# --- Legacy bayrağı ---

func test_legacy_flag_is_honoured_only_in_a_developer_build() -> void:
	assert_bool(CameraEnvelope.from_flag("legacy", true).is_legacy()).is_true()
	assert_bool(CameraEnvelope.from_flag("LEGACY", true).is_legacy()).is_true()
	# Dışa aktarılan sürümde bayrak yok sayılır (R5).
	assert_bool(CameraEnvelope.from_flag("legacy", false).is_legacy()).is_false()
	# Bilinmeyen/boş değer oyuncu zarfı.
	for v in ["", "player", "none", "legacy2"]:
		assert_bool(CameraEnvelope.from_flag(v, true).is_legacy()).is_false()


func test_a_default_rig_can_never_reach_the_old_58km_without_the_flag() -> void:
	var world := WorldTestSupport.coarse(WorldTestSupport.control())
	var rig: CameraRig = auto_free(CameraRig.new())
	rig.input_profile = DesktopInputProfile.new()
	rig.smoothing_enabled = false
	add_child(rig)
	rig.set_world(world, Callable())
	var s := CameraState.new()
	s.focus_x = world.origin.x + world.size.x * 0.5
	s.focus_z = world.origin.y + world.size.y * 0.5
	s.distance = 58000.0
	s.pitch_deg = 50.0
	rig.apply_state(s, true)
	assert_float(rig.target_state().distance).is_less_equal(rig.envelope.d_max_m)
	assert_bool(rig.apply_preset("metro_legacy_bench")).is_false()  # push_error beklenir
	assert_float(rig.target_state().distance).is_less_equal(rig.envelope.d_max_m)
	# Aynı rig'e legacy zarf verilince (yalnız dev bayrağı) eski 58 km erişilir.
	rig.envelope = CameraEnvelope.legacy()
	assert_bool(rig.apply_preset("metro_legacy_bench")).is_true()
	assert_float(rig.target_state().distance).is_equal_approx(world.size.x * 1.45, 0.01)
