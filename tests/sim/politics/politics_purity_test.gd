extends PoliticsTestBase
## T-017 ölçüt 8 · Saflık ve canon taraması: (`src/sim/politics/` + T-017'nin dokunduğu facade dosyaları) sim-invariants
## yasak API listesi, dosya G/Ç ve `load` yalnız kurulumda (politics_config.gd), kayan nokta yok, kodda aktör
## anahtarı/karar kimliği/ad yok (S-N3); veri ve kodda ad/parti/rakip/protagonist adı/para birimi/yolsuzluk teması yok
## (Q-003, Q-005..Q-010). Tarayıcıların kendisi de başarısız olabilir.

const Purity := preload("res://tests/sim/sim_purity_test.gd")
const ROOT := "res://src/sim/politics"
const EXTRA_FILES: Array[String] = [
	"res://src/sim/facade/proposal_gate.gd", "res://src/sim/facade/snapshot_provider.gd",
	"res://src/sim/facade/zoning_propose_handler.gd",
]
const EXPECTED: Array[String] = [
	"agenda_respond_handler.gd", "bloc_engine.gd", "bloc_signals.gd", "council_engine.gd", "event_causes.gd",
	"event_engine.gd", "event_sources.gd", "event_spec.gd", "media_engine.gd", "parcel_regions.gd",
	"politics_bootstrap.gd", "politics_config.gd", "politics_context.gd", "politics_gate.gd", "politics_handle.gd",
	"politics_query.gd", "politics_snapshot.gd", "politics_state.gd", "politics_system.gd",
]
const LOAD_ALLOWED: Array[String] = ["politics_config.gd"]
const HARDCODED_KEY := "[\"'&]actor\\.[a-z]"
const FLOAT_USE := "\\b(float|floorf|ceilf|roundf|is_finite|randf|TYPE_FLOAT)\\b|[0-9]\\.[0-9]"
const LOAD_CALL := "\\b(load|preload|ResourceLoader)\\b"
## Para birimi/ad/parti/rakip izleri (Q-003, Q-005..Q-010); bölgeler/protagonist adı gibi AÇIK konular.
const BANNED: Array[String] = ["Il" + "gın", "Il" + "gin", "Orv" + "en", "Mehmet", "Ayşe", "\u20ba", "\u20ac",
	"party.", "Party", "rival.", "Rival"]
## Para birimi sözcükleri (tam sözcük, Q-003).
const CURRENCY_WORD := "(?i)\\b(dolar|euro|kuruş|lira|dollar|usd|try)\\b"


func _files() -> Array[String]:
	var files: Array[String] = []
	var dir := DirAccess.open(ROOT)
	assert_object(dir).override_failure_message("src/sim/politics yok").is_not_null()
	for file in dir.get_files():
		if file.ends_with(".gd"):
			files.append(ROOT.path_join(file))
	files.append_array(EXTRA_FILES)
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


func test_scan_finds_the_politics_sources_it_polices() -> void:
	var names: Array[String] = []
	for path in _files():
		names.append(path.get_file())
	for expected in EXPECTED:
		assert_bool(names.has(expected)).override_failure_message("taranmayan dosya: %s" % expected).is_true()


func test_no_forbidden_apis_file_io_or_unrounded_math_in_political_sources() -> void:
	var apis := _offenders(Purity.forbidden_hits)
	assert_array(apis).override_failure_message("yasak API:\n" + "\n".join(apis)).is_empty()
	var io := _offenders(Purity.file_io_hits)
	assert_array(io).override_failure_message("dosya G/Ç:\n" + "\n".join(io)).is_empty()
	var math := _offenders(Purity.transcendental_hits)
	assert_array(math).override_failure_message("yuvarlanmamış transandantal:\n" + "\n".join(math)).is_empty()


func test_political_classes_are_refcounted_commands_or_sim_systems() -> void:
	var re := RegEx.create_from_string("(?m)^extends\\s+(\\w+)")
	for path in _files():
		var m := re.search(Purity.strip_comments(FileAccess.get_file_as_string(path)))
		assert_bool(m != null and ["RefCounted", "SimSystem", "CommandHandler", "ProposalGate", "SnapshotProvider"].has(
			m.get_string(1))).override_failure_message("%s: beklenmeyen taban" % path.get_file()).is_true()


func test_resource_loading_is_confined_to_the_setup_time_config_loader() -> void:
	var offenders := _offenders(func(text: String) -> Array[String]: return hits_of(LOAD_CALL, text), LOAD_ALLOWED)
	assert_array(offenders).override_failure_message("yükleme tick dışı kurulumla sınırlı:\n" + "\n".join(offenders)) \
		.is_empty()
	assert_bool(hits_of(LOAD_CALL, FileAccess.get_file_as_string(ROOT + "/politics_config.gd")).is_empty()) \
		.override_failure_message("yükleyici bulunamadı: tarama kaçırıyor").is_false()


func test_no_floating_point_in_political_logic() -> void:
	var offenders := _offenders(func(text: String) -> Array[String]: return hits_of(FLOAT_USE, text))
	assert_array(offenders).override_failure_message("kayan nokta:\n" + "\n".join(offenders)).is_empty()


func test_no_actor_keys_decision_ids_names_parties_or_currency_in_code() -> void:
	var keys := _offenders(func(text: String) -> Array[String]: return hits_of(HARDCODED_KEY, text))
	assert_array(keys).override_failure_message("kodda aktör anahtarı (S-N3):\n" + "\n".join(keys)).is_empty()
	for decision_id in config().table_ids():  # karar kimlikleri veridir (decision_tables.json): kodda sabit yok
		var literal := "[\"'&]%s[\"']" % decision_id.replace(".", "\\.")
		var found := _offenders(func(text: String) -> Array[String]: return hits_of(literal, text))
		assert_array(found).override_failure_message("kodda karar kimliği '%s':\n%s" % [decision_id, "\n".join(found)]) \
			.is_empty()
	var currency := _offenders(func(text: String) -> Array[String]: return hits_of(CURRENCY_WORD, text))
	assert_array(currency).override_failure_message("kodda para birimi:\n" + "\n".join(currency)).is_empty()
	for path in _files():
		var text := FileAccess.get_file_as_string(path)
		for token in BANNED:
			assert_bool(text.contains(token)).override_failure_message("%s: yasak içerik '%s'" % [path.get_file(), token]) \
				.is_false()


func test_data_carries_no_names_parties_rivals_currency_or_corruption_templates() -> void:
	var text := raw_politics_text()
	for token in BANNED:
		assert_bool(text.contains(token)).override_failure_message("veride yasak içerik '%s'" % token).is_false()
	assert_bool(RegEx.create_from_string(CURRENCY_WORD).search(text) != null) \
		.override_failure_message("veride para birimi") \
		.is_false()
	var cfg := politics_config()
	for template in cfg.templates:
		assert_array(template["tone_tags"]).is_empty()
		assert_bool(String(template["id"]) in ["PE-01", "PE-02", "PE-03", "PE-04", "PE-07"]) \
			.override_failure_message("M2 dilimi dışı şablon: %s" % template["id"]).is_true()
	assert_array(cfg.events["blocked_tags"]).contains(["corruption"])
	assert_str(cfg.events["tone_profile"]).is_equal("moderate")
	assert_bool(cfg.milestone_open("M3")).override_failure_message("M3+ şablonlar kapalı").is_false()
	# kampanya/ad/seçim alanları siyasi veride yok
	for forbidden in ["campaign", "election", "candidate", "party_name", "player_name", "protagonist"]:
		assert_bool(text.to_lower().contains(forbidden)).override_failure_message("veride '%s'" % forbidden).is_false()


func test_political_actors_are_placeholder_keys_with_no_background_or_name_fields() -> void:
	var h := handle()
	for key in ActorStore.keys(h.state()):
		var actor := ActorStore.actor(h.state(), key)
		assert_str(actor["name_key"]).is_equal(key + ".name")
	var protagonist := ActorStore.actor(h.state(), PLAYER)
	assert_array(protagonist["state"]["profile_slots"]).is_empty()
	assert_bool(protagonist.has("traits") and not protagonist["traits"].is_empty()).is_false()


# --- Tarayıcılar başarısız olabilmeli ---

func test_content_scanners_flag_what_they_must_and_allow_what_they_should() -> void:
	assert_array(hits_of(HARDCODED_KEY, "var k := \"actor.council.1\"")).is_not_empty()
	assert_array(hits_of(HARDCODED_KEY, "var k := KEY_PREFIX + \".\" + kind")).is_empty()
	assert_array(hits_of("[\"'&]council\\.vote[\"']", "var d := \"council.vote\"")).is_not_empty()
	assert_array(hits_of("[\"'&]council\\.vote[\"']", "var d := \"decision.council.vote\"")).is_empty()
	assert_array(hits_of(CURRENCY_WORD, "var price := 5 lira")).is_not_empty()
	assert_array(hits_of(CURRENCY_WORD, "kuyruk dolarsa")).is_empty()
	assert_array(hits_of(FLOAT_USE, "var x := 0.5")).is_not_empty()
	assert_array(hits_of(FLOAT_USE, "var x := 5 / 2")).is_empty()
	assert_array(hits_of(LOAD_CALL, "var r := load(\"res://x.json\")")).is_not_empty()
	assert_array(Purity.forbidden_hits("var r := randi() % 5")).is_not_empty()
	assert_array(Purity.forbidden_hits("var t := Time.get_ticks_msec()")).is_not_empty()
	assert_array(Purity.file_io_hits("FileAccess.open(p, FileAccess.READ)")).is_not_empty()
