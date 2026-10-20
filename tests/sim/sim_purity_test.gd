extends SimTestBase
## T-002 ölçüt 8 ve 9 · Yasak API taraması (sim-invariants checklist) ve platform bağımsızlığı (PLT-04): simülasyon
## kodunda Node/SceneTree/Time/OS/global rastgelelik/delta/platform profili yok; transandantal fonksiyon çağrıları
## yuvarlama olmadan kalıcı duruma girmez. Tarama `src/sim/` (tüm alt dizinler, başka hatların dosyaları dâhil) ve
## `src/app/tick_driver*.gd` üzerindedir.

const SCAN_ROOTS: Array[String] = ["res://src/sim"]
const SCAN_PREFIX_DIRS: Array[String] = ["res://src/app"]
const SCAN_PREFIX := "tick_driver"

## Yorum satırı dışı kodda yasak desenler. Küresel rastgelelik: önünde '.' olmayan çağrı (rng.randi_range serbest).
const FORBIDDEN: Dictionary = {
	"global rng": "(?<![\\.\\w])(randf|randi|randomize|randf_range|randi_range|rand_from_seed|seed|shuffle"
		+ "|pick_random)\\(",
	"Time": "\\bTime\\.",
	"OS": "\\bOS\\.",
	"Engine": "\\bEngine\\.",
	"scene tree": "\\b(get_tree|SceneTree|get_node|get_parent|add_child|queue_free)\\b",
	"Node class": "\\b(extends\\s+(Node|Node2D|Node3D|Control|CanvasItem|Window)|Node|Node2D|Node3D|Control)\\b",
	"process callbacks": "\\b(_process|_physics_process|_input|_unhandled_input|_ready)\\b",
	"delta": "\\bdelta\\b",
	"input/display": "\\b(Input|InputEvent|DisplayServer|RenderingServer|PhysicsServer3D|Viewport)\\b",
	"platform": "\\b(PlatformProfile|platform_profile|InputProfile|input_profile|ProjectSettings)\\b",
	"threads": "\\b(Thread|Mutex|WorkerThreadPool)\\b",
}

## Transandantal/platforma duyarlı matematik çağrıları; aynı satırda deterministik yuvarlama işareti zorunlu.
const TRANSCENDENTAL := "\\b(sin|cos|tan|asin|acos|atan|atan2|sinh|cosh|tanh|exp|pow|log|ease|smoothstep)\\("
const ROUNDING_MARKERS: Array[String] = ["roundi(", "snappedf(", "snappedi(", "floori(", "ceili(", "int("]
## Dosya düzeyi yetki: yalnızca kurulumda (tick dışında) yapılandırma dosyası okuyan sınıflar. Kayıt yuvası G/Ç'si
## src/app/save_slot*'tadır ve ayrı taranır (save_slot_purity_test.gd); sim içinde başka dosya G/Ç'ye izin yoktur.
const FILE_IO_ALLOWED: Array[String] = ["sim_config.gd", "facade_config.gd", "economy_config.gd"]
## Taban sınıfı çözümlemesi için ek kök: `class_name` -> `extends` haritası buradan da kurulur (örn. SimFacade).
const CLASS_MAP_ROOTS: Array[String] = ["res://src/sim", "res://src/contracts"]
const FILE_IO := "\\b(FileAccess|DirAccess)\\b"


static func strip_comments(text: String) -> String:
	var out: PackedStringArray = []
	for line in text.split("\n"):
		var idx := line.find("#")
		out.append(line if idx < 0 else line.substr(0, idx))
	return "\n".join(out)


## Metindeki ihlaller: ["kural: satır", ...]. Yorumlar yok sayılır.
static func forbidden_hits(text: String) -> Array[String]:
	var hits: Array[String] = []
	var code := strip_comments(text)
	for rule: String in FORBIDDEN:
		var re := RegEx.create_from_string(FORBIDDEN[rule])
		for line in code.split("\n"):
			if re.search(line) != null:
				hits.append("%s: %s" % [rule, line.strip_edges()])
	return hits


static func transcendental_hits(text: String) -> Array[String]:
	var hits: Array[String] = []
	var re := RegEx.create_from_string(TRANSCENDENTAL)
	for line in strip_comments(text).split("\n"):
		if re.search(line) == null:
			continue
		var rounded := false
		for marker in ROUNDING_MARKERS:
			rounded = rounded or line.contains(marker)
		if not rounded:
			hits.append(line.strip_edges())
	return hits


static func file_io_hits(text: String) -> Array[String]:
	var hits: Array[String] = []
	var re := RegEx.create_from_string(FILE_IO)
	for line in strip_comments(text).split("\n"):
		if re.search(line) != null:
			hits.append(line.strip_edges())
	return hits


static func _collect(dir_path: String, prefix: String, out: Array[String]) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	for sub in dir.get_directories():
		_collect(dir_path.path_join(sub), prefix, out)
	for file in dir.get_files():
		if file.ends_with(".gd") and file.begins_with(prefix):
			out.append(dir_path.path_join(file))


func _sources() -> Array[String]:
	var files: Array[String] = []
	for root in SCAN_ROOTS:
		_collect(root, "", files)
	for root in SCAN_PREFIX_DIRS:
		_collect(root, SCAN_PREFIX, files)
	return files


func test_scan_finds_the_sim_sources_it_is_meant_to_police() -> void:
	var names: Array[String] = []
	for f in _sources():
		names.append(f.get_file())
	for expected in ["game_state.gd", "simulation.gd", "rng_streams.gd", "commands.gd", "reason_log.gd",
			"sim_save.gd", "state_hash.gd", "tick_driver.gd", "sim_event_log.gd", "command_reject.gd",
			"sim_facade_impl.gd", "zoning_propose_handler.gd", "parcel_zoning_system.gd", "parcel_source.gd",
			"list_parcel_source.gd", "reason_adapter.gd", "event_adapter.gd", "facade_config.gd"]:
		assert_bool(names.has(expected)).override_failure_message("taranmayan dosya: %s" % expected).is_true()


func test_no_forbidden_apis_in_simulation_or_tick_driver_sources() -> void:
	var offenders: Array[String] = []
	for path in _sources():
		for hit in forbidden_hits(FileAccess.get_file_as_string(path)):
			offenders.append("%s -> %s" % [path, hit])
	assert_array(offenders).override_failure_message("yasak API:\n" + "\n".join(offenders)).is_empty()


func test_file_io_only_in_allowed_setup_classes() -> void:
	var offenders: Array[String] = []
	for path in _sources():
		if FILE_IO_ALLOWED.has(path.get_file()):
			continue
		for hit in file_io_hits(FileAccess.get_file_as_string(path)):
			offenders.append("%s -> %s" % [path, hit])
	assert_array(offenders).override_failure_message("izinsiz dosya G/Ç:\n" + "\n".join(offenders)).is_empty()


func test_transcendental_math_is_never_unrounded() -> void:
	var offenders: Array[String] = []
	for path in _sources():
		for hit in transcendental_hits(FileAccess.get_file_as_string(path)):
			offenders.append("%s -> %s" % [path, hit])
	assert_array(offenders).override_failure_message("yuvarlanmamış transandantal:\n" + "\n".join(offenders)).is_empty()


## `class_name X` + `extends Y` -> {"X": "Y"} (sim ve sözleşme dosyaları).
func _class_map() -> Dictionary:
	var map := {}
	var files: Array[String] = []
	for root in CLASS_MAP_ROOTS:
		_collect(root, "", files)
	var name_re := RegEx.create_from_string("(?m)^class_name\\s+(\\w+)")
	var base_re := RegEx.create_from_string("(?m)^extends\\s+(\\w+)")
	for path in files:
		var text := strip_comments(FileAccess.get_file_as_string(path))
		var n := name_re.search(text)
		var b := base_re.search(text)
		if n != null and b != null:
			map[n.get_string(1)] = b.get_string(1)
	return map


## Taban zinciri RefCounted/Resource'ta bitiyor mu? (SimSystem, CommandHandler, ParcelSource gibi yerel tabanlar
## üzerinden de.) Zincir Node'a ya da bilinmeyen bir sınıfa çıkıyorsa false.
func _is_pure_base(base: String, map: Dictionary) -> bool:
	var guard := 0
	var current := base
	while guard < 16:
		if current == "RefCounted" or current == "Resource":
			return true
		if not map.has(current):
			return false
		current = map[current]
		guard += 1
	return false


func test_simulation_classes_extend_refcounted_or_resource_not_node() -> void:
	var map := _class_map()
	for path in _sources():
		var text := strip_comments(FileAccess.get_file_as_string(path))
		var re := RegEx.create_from_string("(?m)^extends\\s+(\\w+)")
		var m := re.search(text)
		if m != null:
			var base := m.get_string(1)
			assert_bool(_is_pure_base(base, map)) \
				.override_failure_message("%s extends %s (zincir RefCounted/Resource'ta bitmiyor)" % [path, base]).is_true()


func test_base_resolution_flags_node_chains_and_unknown_bases() -> void:
	var map := {"A": "RefCounted", "B": "A", "C": "Node", "D": "C", "E": "Mystery"}
	assert_bool(_is_pure_base("B", map)).is_true()
	assert_bool(_is_pure_base("RefCounted", map)).is_true()
	assert_bool(_is_pure_base("D", map)).override_failure_message("Node zinciri kaçtı").is_false()
	assert_bool(_is_pure_base("C", map)).is_false()
	assert_bool(_is_pure_base("E", map)).override_failure_message("bilinmeyen taban kaçtı").is_false()
	assert_bool(_is_pure_base("Node3D", map)).is_false()


func test_facade_directory_is_scanned_and_never_touches_the_app_save_layer() -> void:
	var facade_files: Array[String] = []
	for path in _sources():
		if path.begins_with("res://src/sim/facade/"):
			facade_files.append(path)
	assert_int(facade_files.size()).override_failure_message("facade dizini taranmıyor").is_greater_equal(8)
	var re := RegEx.create_from_string("\\b(SaveSlot|FileAccess|DirAccess)\\b")
	for path in facade_files:
		if FILE_IO_ALLOWED.has(path.get_file()):
			continue
		assert_bool(re.search(strip_comments(FileAccess.get_file_as_string(path))) == null) \
			.override_failure_message("%s dosya G/Ç ya da kayıt yuvası katmanına dokunuyor" % path).is_true()


# --- Tarayıcının kendisi başarısız olabilmeli (olumsuz testler) ---

func test_scanner_flags_each_forbidden_construct() -> void:
	var bad := {
		"global rng": "var x := randi() % 10",
		"global rng ": "var y := randf_range(0.0, 1.0)",
		"Time": "var t := Time.get_ticks_msec()",
		"OS": "OS.get_unix_time()",
		"Engine": "Engine.get_frames_drawn()",
		"scene tree": "var tree = get_tree()",
		"Node class": "extends Node",
		"process callbacks": "func _process(d):",
		"delta": "func step(state, delta):",
		"input/display": "var e := Input.is_action_pressed(\"x\")",
		"platform": "var p := PlatformProfile.current()",
	}
	for label: String in bad:
		assert_array(forbidden_hits(bad[label])).override_failure_message("kaçtı: %s" % bad[label]).is_not_empty()


func test_scanner_allows_seeded_rng_instances_and_comments() -> void:
	assert_array(forbidden_hits("var v := rng.randi_range(0, 9)\nvar f := rng.randf()")).is_empty()
	assert_array(forbidden_hits("# Node, Time.now(), randi(), delta yalnızca yorumda")).is_empty()
	assert_array(forbidden_hits("var s := state.rng.stream(&\"a\").randi()")).is_empty()


func test_transcendental_scanner_flags_unrounded_and_accepts_rounded() -> void:
	assert_array(transcendental_hits("var a := sin(x)")).is_not_empty()
	assert_array(transcendental_hits("var b := pow(2.0, y)")).is_not_empty()
	assert_array(transcendental_hits("var c := exp(z) * 3.0")).is_not_empty()
	assert_array(transcendental_hits("var d := roundi(pow(2.0, y) * 100.0)")).is_empty()
	assert_array(transcendental_hits("var e := snappedf(log(x), 0.001)")).is_empty()
	assert_array(transcendental_hits("# sin(x) yorumda")).is_empty()


func test_file_io_scanner_flags_fileaccess() -> void:
	assert_array(file_io_hits("var f := FileAccess.open(p, FileAccess.READ)")).is_not_empty()
	assert_array(file_io_hits("# FileAccess yorumda")).is_empty()
