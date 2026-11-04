extends GdUnitTestSuite
## T-028 ölçüt 4 · kanon durum tablosu ve karar soruları: durum sözcükleri geçerli, sayılar veriden, 4-6 soru,
## cevap/öneri yok (karar kullanıcıda), hiçbir kanon çelişkisi veya uydurma ad yok.

var _m: TopologyModel


func before() -> void:
	_m = TopologyTestSupport.full_model()


func _statuses_of(row: Dictionary) -> PackedStringArray:
	return PackedStringArray(String(row["status"]).split("/"))


func test_every_row_has_a_valid_status_and_text() -> void:
	var rows := TopologyTexts.provenance(_m)
	assert_int(rows.size()).is_greater_equal(10)
	for row in rows:
		for st in _statuses_of(row):
			assert_bool(TopologyTexts.STATUSES.has(st)).override_failure_message(String(row["item"])).is_true()
		assert_str(String(row["item"])).is_not_empty()
		assert_str(String(row["detail"])).is_not_empty()


func test_canon_vs_working_model_split_matches_the_requirements() -> void:
	var by_item := {}
	for row in TopologyTexts.provenance(_m):
		by_item[row["item"]] = row
	var inferred := 0
	var canon := 0
	for row in TopologyTexts.provenance(_m):
		var st := _statuses_of(row)
		inferred += 1 if st.has(TopologyTexts.STATUS_INFERRED) else 0
		canon += 1 if st.has(TopologyTexts.STATUS_CANON) else 0
	assert_int(inferred).is_greater_equal(2)
	assert_int(canon).is_greater_equal(3)
	for row in TopologyTexts.provenance(_m):
		var item := String(row["item"])
		if item.begins_with("D1 körfezin kuzey"):
			assert_array(_statuses_of(row)).contains([TopologyTexts.STATUS_INFERRED])
			assert_array(_statuses_of(row)).not_contains([TopologyTexts.STATUS_CANON])
		if item.begins_with("Ada sayısı"):
			assert_array(_statuses_of(row)).contains([TopologyTexts.STATUS_CM])
			assert_array(_statuses_of(row)).not_contains([TopologyTexts.STATUS_CANON])
		if item.begins_with("T0 limanı"):
			assert_array(_statuses_of(row)).contains([TopologyTexts.STATUS_CANON])


func test_rows_quote_live_numbers_from_the_model() -> void:
	var text := ""
	for row in TopologyTexts.provenance(_m):
		text += String(row["item"]) + " " + String(row["detail"]) + "\n"
	assert_str(text).contains("haritada %d ada" % _m.islands.size())
	assert_str(text).contains("toplam %d yapı" % _m.building_total)
	assert_str(text).contains(TopologyTexts.num(float(_m.gap["water_gap_m"]) / 1000.0, 1))


func test_four_to_six_questions_cover_the_q015_items_without_answers() -> void:
	var qs := TopologyTexts.questions(_m)
	assert_int(qs.size()).is_between(4, 6)
	var titles := ""
	for q in qs:
		titles += String(q["title"]).to_lower() + "|"
		assert_int((q["options"] as Array).size()).is_greater_equal(3)
		assert_str(String(q["current"])).is_not_empty()
		assert_bool(q.has("recommendation")).is_false()
		for opt: String in q["options"]:
			assert_str(opt.to_lower()).not_contains("öneri")
	for needle in ["körfez", "ada", "d1 / d6", "liman", "ova"]:
		assert_str(titles).contains(needle)


func test_question_numbers_come_from_data() -> void:
	var cur := {}
	for q in TopologyTexts.questions(_m):
		cur[q["id"]] = String(q["current"])
	assert_str(cur["K2"]).contains("%d ada" % _m.islands.size())
	assert_str(cur["K4"]).contains(TopologyTexts.num(_m.site_mark(&"port").shore_m, 0))
	assert_str(cur["K5"]).contains("%" + TopologyTexts.pct(float(_m.land_stats["plain_share"])))


func test_no_invented_place_names_in_texts() -> void:
	var text := ""
	for row in TopologyTexts.provenance(_m):
		text += "%s | %s | %s\n" % [row["item"], row["detail"], row["req"]]
	for q in TopologyTexts.questions(_m):
		text += "%s | %s | %s\n" % [q["title"], q["current"], " | ".join(q["options"])]
	var found := _proper_nouns(text)
	assert_array(found).override_failure_message("uydurma ad olabilir: %s" % str(found)).is_empty()


func test_negative_invented_name_is_detected() -> void:
	assert_array(_proper_nouns("liman yeni Karvet ilçesinde | Orven ve Ismeral serbest")).is_equal(["Karvet"])
	assert_array(_proper_nouns("Cümle başı serbest; WorldData/WorldNetwork serbest")).is_empty()


## Küçük harfli sözcükten sonra gelen büyük harfli sözcük = özel ad adayı (cümle başları, kod adları sayılmaz).
static func _proper_nouns(text: String) -> PackedStringArray:
	var allowed := ["Orven", "Ismeral", "Anderva", "Imaro"]
	var rx := RegEx.create_from_string("(?<=[a-zçğıöşü,] )([A-ZÇĞİÖŞÜ][a-zçğıöşü]{3,})(?![A-Za-z/])")
	var found := PackedStringArray()
	for m in rx.search_all(text):
		if not allowed.has(m.get_string(1)):
			found.append(m.get_string(1))
	return found
