extends ActorTestBase
## T-016 ölçüt 5 · Saflık ve içerik taraması (`src/sim/actors/`): sim-invariants yasak API listesi (ortak tarayıcı
## `sim_purity_test`), dosya G/Ç yalnız kurulumda (`load`, yalnız actor_config.gd), kayan nokta yalnız JSON zorlamada
## (actor_schema.gd), kodda aktör anahtarı/karar kimliği/ad yok (characters-npc S-N3: veri sürer, kod yalnız tür bilir).
## Tarayıcının kendisi de başarısız olabilmeli (olumsuz örnekler).

const Purity := preload("res://tests/sim/sim_purity_test.gd")
const ROOT := "res://src/sim/actors"
const EXPECTED: Array[String] = [
	"actor_config.gd", "actor_decision.gd", "actor_inputs.gd", "actor_math.gd", "actor_memory.gd", "actor_schema.gd",
	"actor_store.gd", "actor_system.gd",
]
const LOAD_ALLOWED: Array[String] = ["actor_config.gd"]
const FLOAT_ALLOWED: Array[String] = ["actor_schema.gd"]
## Kodda aktör anahtarı (`actor.<tür>...`) ya da karar kimliği (`<tür>.<fiil>`) sabiti.
const HARDCODED_KEY := "[\"'&]actor\\.[a-z]"
const HARDCODED_DECISION := "[\"'&](protagonist|council|interest|investor|media|bloc|rival|remote|story)\\.[a-z_]+[\"']"
const FLOAT_USE := "\\b(float|floorf|ceilf|roundf|is_finite|randf|TYPE_FLOAT)\\b|[0-9]\\.[0-9]"
const LOAD_CALL := "\\b(load|preload|ResourceLoader)\\b"


func _files() -> Array[String]:
	var files: Array[String] = []
	var dir := DirAccess.open(ROOT)
	assert_object(dir).override_failure_message("src/sim/actors yok").is_not_null()
	for file in dir.get_files():
		if file.ends_with(".gd"):
			files.append(ROOT.path_join(file))
	files.sort()
	return files


static func hits_of(pattern: String, text: String) -> Array[String]:
	var hits: Array[String] = []
	var re := RegEx.create_from_string(pattern)
	for line in Purity.strip_comments(text).split("\n"):
		if re.search(line) != null:
			hits.append(line.strip_edges())
	return hits


func _offenders(check: Callable, skip: Array[String] = []) -> Array[String]:
	var out: Array[String] = []
	for path in _files():
		if skip.has(path.get_file()):
			continue
		for hit: String in check.call(FileAccess.get_file_as_string(path)):
			out.append("%s -> %s" % [path.get_file(), hit])
	return out


func test_scan_finds_the_actor_sources_it_polices() -> void:
	var names: Array[String] = []
	for path in _files():
		names.append(path.get_file())
	for expected in EXPECTED:
		assert_bool(names.has(expected)).override_failure_message("taranmayan dosya: %s" % expected).is_true()


func test_no_forbidden_apis_in_actor_sources() -> void:
	var offenders := _offenders(Purity.forbidden_hits)
	assert_array(offenders).override_failure_message("yasak API:\n" + "\n".join(offenders)).is_empty()


func test_no_file_io_and_no_unrounded_transcendentals() -> void:
	var io := _offenders(Purity.file_io_hits)
	assert_array(io).override_failure_message("dosya G/Ç:\n" + "\n".join(io)).is_empty()
	var math := _offenders(Purity.transcendental_hits)
	assert_array(math).override_failure_message("yuvarlanmamış transandantal:\n" + "\n".join(math)).is_empty()


func test_actor_classes_are_refcounted_or_sim_systems() -> void:
	var re := RegEx.create_from_string("(?m)^extends\\s+(\\w+)")
	for path in _files():
		var m := re.search(Purity.strip_comments(FileAccess.get_file_as_string(path)))
		assert_bool(m != null and ["RefCounted", "SimSystem"].has(m.get_string(1))) \
			.override_failure_message("%s: beklenmeyen taban" % path.get_file()).is_true()


func test_resource_loading_is_confined_to_the_setup_time_config_loader() -> void:
	var offenders := _offenders(func(text: String) -> Array[String]: return hits_of(LOAD_CALL, text), LOAD_ALLOWED)
	assert_array(offenders) \
		.override_failure_message("yükleme tick dışı kurulumla sınırlı:\n" + "\n".join(offenders)).is_empty()
	assert_bool(hits_of(LOAD_CALL, FileAccess.get_file_as_string(ROOT + "/actor_config.gd")).is_empty()) \
		.override_failure_message("yükleyici bulunamadı: tarama kaçırıyor").is_false()


func test_no_floating_point_in_actor_logic_beyond_json_coercion() -> void:
	var offenders := _offenders(func(text: String) -> Array[String]: return hits_of(FLOAT_USE, text), FLOAT_ALLOWED)
	assert_array(offenders).override_failure_message("kayan nokta:\n" + "\n".join(offenders)).is_empty()


func test_no_actor_keys_decision_ids_or_names_in_code() -> void:
	var keys := _offenders(func(text: String) -> Array[String]: return hits_of(HARDCODED_KEY, text))
	assert_array(keys).override_failure_message("kodda aktör anahtarı (S-N3):\n" + "\n".join(keys)).is_empty()
	var decisions := _offenders(func(text: String) -> Array[String]: return hits_of(HARDCODED_DECISION, text))
	assert_array(decisions).override_failure_message("kodda karar kimliği:\n" + "\n".join(decisions)).is_empty()
	var banned: Array[String] = ["Il" + "gın", "Il" + "gin", "Orv" + "en", "Mehmet", "Ayşe", "\u20ba", "party."]
	for path in _files():
		var text := FileAccess.get_file_as_string(path)
		for token in banned:
			assert_bool(text.contains(token)).override_failure_message("%s: yasak içerik '%s'" % [path.get_file(), token]) \
				.is_false()


# --- Tarayıcılar başarısız olabilmeli ---

func test_content_scanners_flag_what_they_must_and_allow_what_they_should() -> void:
	assert_array(hits_of(HARDCODED_KEY, "var k := \"actor.council.1\"")).is_not_empty()
	assert_array(hits_of(HARDCODED_KEY, "var k := &\"actor.protagonist\"")).is_not_empty()
	assert_array(hits_of(HARDCODED_KEY, "var k := KEY_PREFIX + \".\" + kind")).is_empty()
	assert_array(hits_of(HARDCODED_KEY, "# \"actor.council.1\" yorumda")).is_empty()
	assert_array(hits_of(HARDCODED_DECISION, "var d := \"council.vote\"")).is_not_empty()
	assert_array(hits_of(HARDCODED_DECISION, "var d := \"%s.%s\" % [a, b]")).is_empty()
	assert_array(hits_of(FLOAT_USE, "var x := 0.5")).is_not_empty()
	assert_array(hits_of(FLOAT_USE, "var x: float = 1")).is_not_empty()
	assert_array(hits_of(FLOAT_USE, "var x := 5 / 2")).is_empty()
	assert_array(hits_of(LOAD_CALL, "var r := load(\"res://x.json\")")).is_not_empty()
	assert_array(Purity.forbidden_hits("var r := randi() % 5")).is_not_empty()
	assert_array(Purity.file_io_hits("FileAccess.open(p, FileAccess.READ)")).is_not_empty()
