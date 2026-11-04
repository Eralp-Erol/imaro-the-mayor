extends GdUnitTestSuite
## T-018 ölçüt 5 · Merkezi Türkçe metin tablosu kuralları (data/ui/strings.tr.json): geçerli JSON, anahtar
## biçimi,
## para simgesi/adı yasağı (Q-003), tek "Mutluluk" skoru yasağı (SIM-09), yer tutucu dengesi, zorunlu anahtar
## aileleri.
## Her kuralın OLUMSUZ karşılığı: bilerek bozulmuş sözlük bellekte üretilir ve denetçinin ihlal bulduğu
## doğrulanır.

const PATH := "res://data/ui/strings.tr.json"
const FORBIDDEN_CURRENCY := ["₺", "$", "€", "£", "lira", "Lira"]
const GAME_TITLE := "Imaro: The Mayor"  # CAN-01; yerelleştirilmiş ad/alt başlık yalnız kullanıcı kararıyla
const FORBIDDEN_WORDS := ["puan", "skor"]  # ux-text-system §4 (sicil için); küçük harfe çevrilmiş metinde aranır
const REQUIRED_PREFIXES := [
	"mode.", "zoom.", "clock.", "tool.", "draw.", "zoning.", "inspector.", "reason.", "council.", "budget.",
	"record.", "election.", "state.loading", "state.empty.", "state.error.", "settings.", "a11y.", "format.",
]

var _table: Dictionary


func before() -> void:
	var file := FileAccess.open(PATH, FileAccess.READ)
	assert_object(file).is_not_null()
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	assert_bool(parsed is Dictionary).is_true()
	_table = parsed as Dictionary


static func violations(table: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	var key_re := RegEx.new()
	key_re.compile("^(_meta\\.)?[a-z0-9_]+(\\.[a-z0-9_]+)*$")
	var ph_re := RegEx.new()
	ph_re.compile("\\{[a-z_0-9]+\\}")
	for key in table:
		var k := str(key)
		var v: Variant = table[key]
		if key_re.search(k) == null:
			out.append("anahtar biçimi: " + k)
		if not (v is String):
			out.append("değer String değil: " + k)
			continue
		var s := v as String
		if s.strip_edges() == "":
			out.append("boş metin: " + k)
		if not k.begins_with("_meta."):
			for bad in FORBIDDEN_CURRENCY:
				if s.contains(bad):
					out.append("para simgesi/adı: " + k)
			if s.contains("¤"):
				out.append("para simgesi metinde gömülü (yapılandırmadan gelmeli): " + k)
			if s.to_lower().contains("mutluluk"):
				out.append("tek skor ifadesi (SIM-09): " + k)
		if not k.begins_with("_meta."):
			var low := s.to_lower()
			for w in FORBIDDEN_WORDS:
				if low.contains(w):
					out.append("yasak kelime '%s': %s" % [w, k])
			if k == "format.percent" and not s.begins_with("%"):
				out.append("Türkçe yüzde biçimi %{value} olmalı: " + k)
		if k == "app.title" and s != GAME_TITLE:
			out.append("oyun adı CAN-01 ile aynı olmalı: " + k)
		var opens := s.count("{")
		var closes := s.count("}")
		if opens != closes or ph_re.search_all(s).size() != opens:
			out.append("yer tutucu dengesiz: " + k)
	return out


func test_table_is_clean() -> void:
	assert_array(Array(violations(_table))).is_empty()


func test_required_key_families_exist() -> void:
	for prefix in REQUIRED_PREFIXES:
		var found := false
		for key in _table:
			if str(key).begins_with(prefix):
				found = true
				break
		assert_bool(found).override_failure_message("anahtar ailesi yok: " + prefix).is_true()


func test_no_not_built_system_has_fake_content() -> void:
	# Kurulmamış sistemler için dürüst etiket anahtarı bulunmalı (sahte sekme yerine).
	for key in ["council.not_built", "budget.not_built", "election.not_built", "state.not_built"]:
		assert_bool(_table.has(key)).is_true()


func test_negative_controls_are_detected() -> void:
	var bad_currency := _table.duplicate()
	bad_currency["x.price"] = "Maliyet 100 ₺"
	assert_bool(violations(bad_currency).size() > 0).is_true()
	var bad_score := _table.duplicate()
	bad_score["x.score"] = "Mutluluk: {value}"
	assert_bool(violations(bad_score).size() > 0).is_true()
	var bad_key := _table.duplicate()
	bad_key["Kötü Anahtar"] = "x"
	assert_bool(violations(bad_key).size() > 0).is_true()
	var bad_ph := _table.duplicate()
	bad_ph["x.ph"] = "Değer {value"
	assert_bool(violations(bad_ph).size() > 0).is_true()
	var bad_title := _table.duplicate()
	bad_title["app.title"] = "Imaro: Belediye Başkanı"
	assert_bool(violations(bad_title).size() > 0).is_true()
	var bad_puan := _table.duplicate()
	bad_puan["x.puan"] = "Toplam puan: {value}"
	assert_bool(violations(bad_puan).size() > 0).is_true()
	var bad_percent := _table.duplicate()
	bad_percent["format.percent"] = "{value}%"
	assert_bool(violations(bad_percent).size() > 0).is_true()
	var inline_symbol := _table.duplicate()
	inline_symbol["x.sym"] = "Tutar 5 ¤"
	assert_bool(violations(inline_symbol).size() > 0).is_true()
