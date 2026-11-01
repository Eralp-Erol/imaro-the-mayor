extends GdUnitTestSuite
## B-006: ReasonPanel'de sim'in yazabileceği HİÇBİR karar anahtarı ham (`decision.`...) görünmemeli.
## Kaynaklar: data/actors/decision_tables.json (basamaklar dahil; kayıtta `decision.<id>[.<basamak>]`) ve
## sim'in doğrudan `record_reason` ile yazdığı sabitler. Yeni karar tablosu eklenip metni unutulursa bu test KIRILIR.

const STATIC_KEYS: Array[String] = [
	"decision.investor.continue", "decision.bloc.expropriation_cause",
]


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
