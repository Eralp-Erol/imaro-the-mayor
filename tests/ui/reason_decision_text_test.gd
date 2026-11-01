extends GdUnitTestSuite
## B-006: ReasonPanel'de sim'in yazabileceği HİÇBİR karar anahtarı ham (`decision.`...) görünmemeli.
## Kaynaklar: data/actors/decision_tables.json (basamaklar dahil; kayıtta `decision.<id>[.<basamak>]`) ve
## sim'in doğrudan `record_reason` ile yazdığı sabitler. Yeni karar tablosu eklenip metni unutulursa bu test KIRILIR.

const STATIC_KEYS: Array[String] = [
	"decision.investor.continue", "decision.bloc.expropriation_cause",
]
const SCAN_RX := "\"((?:decision|reason\\.factor|budget\\.factor)\\.[a-z0-9_]+(?:\\.[a-z0-9_]+)*)\""


func before_test() -> void:
	UiText.reset()
	UiText.report_missing = false


func after_test() -> void:
	UiText.reset()


func _sim_decision_keys() -> PackedStringArray:
	var keys := PackedStringArray()
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/actors/decision_tables.json"))
	for id: String in (raw["decisions"] as Dictionary):
		var tiers: Array = (raw["decisions"][id] as Dictionary).get("tiers", [])
		if tiers.is_empty():
			keys.append("decision." + id)
		for t: Dictionary in tiers:
			keys.append("decision.%s.%s" % [id, t["id"]])
	for k: Variant in [ExpropriationFlow.DECISION_EXPROPRIATE, ExpropriationFlow.DECISION_RESTORE,
			EconomyState.DEVELOP_DECISION, BudgetSystem.DECISION_TAX, BudgetSystem.DECISION_ROAD_COST,
			BudgetSystem.DECISION_ROAD_REFUND, EventEngine.FIRE_DECISION]:
		keys.append(String(k))
	keys.append_array(PackedStringArray(STATIC_KEYS))
	return keys


func test_keys_were_collected() -> void:
	var keys := _sim_decision_keys()
	assert_bool(keys.has("decision.council.vote")).is_true()
	assert_bool(keys.has("decision.bloc.react.boycott")).is_true()
	assert_bool(keys.has("decision.event.fire")).is_true()


func test_no_sim_decision_key_shows_raw_in_reason_panel() -> void:
	var bad := PackedStringArray()
	for key in _sim_decision_keys():
		for outcome: StringName in [&"positive", &"negative"]:
			var text := ReasonPanel.decision_text(StringName(key), outcome)
			if text.contains("decision.") or text.is_empty():
				bad.append("%s/%s -> '%s'" % [key, outcome, text])
	assert_array(bad).override_failure_message("ham/boş karar metni: %s" % ", ".join(bad)).is_empty()


## B-018 kök neden: yukarıdaki liste ELLE yazılmıştı; yıkım/bütçe kararları listede yoktu. Bu tarama src/sim altındaki
## HER `decision.*` / `reason.factor.*` / `budget.factor.*` metin sabitini bulur (elle liste gerekmez); yeni sabit
## metinsiz kalırsa KIRILIR.


func _scan_dir(dir_path: String, out: PackedStringArray) -> void:
	for f in DirAccess.get_files_at(dir_path):
		if f.ends_with(".gd"):
			out.append(dir_path.path_join(f))
	for d in DirAccess.get_directories_at(dir_path):
		_scan_dir(dir_path.path_join(d), out)


func _literal_keys() -> PackedStringArray:
	var files := PackedStringArray()
	_scan_dir("res://src/sim", files)
	var rx := RegEx.create_from_string(SCAN_RX)
	var out := PackedStringArray()
	for path in files:
		for m in rx.search_all(FileAccess.get_file_as_string(path)):
			var key := m.get_string(1)
			if not out.has(key):
				out.append(key)
	return out


func test_scan_finds_demolish_and_budget_keys() -> void:
	var keys := _literal_keys()
	assert_bool(keys.has("decision.municipal.demolish_road")).is_true()
	assert_bool(keys.has("reason.factor.removed_capacity_units")).is_true()
	assert_bool(keys.has("decision.budget.road_demolish")).is_true()
	assert_bool(keys.has("decision.budget.resettlement")).is_true()


func test_every_literal_decision_and_factor_in_sim_has_turkish_text() -> void:
	var bad := PackedStringArray()
	for key in _literal_keys():
		if key.contains(".factor."):
			if not UiText.has(StringName(key)):
				bad.append(key)
			continue
		var readable := UiText.has(StringName(key)) \
			or UiText.has(StringName(key + ".positive")) or UiText.has(StringName(key + ".negative"))
		if not readable:
			bad.append(key)
	assert_array(bad).override_failure_message("metinsiz sim anahtarı: %s" % ", ".join(bad)).is_empty()
