extends GdUnitTestSuite
## T-019 ölçüt 1 · UiText: anahtar → Türkçe metin, yer tutucu, eksik anahtar görünür hata, para yalnız
## yapılandırmadan.
## Olumsuz varyantlar: eksik anahtar, eksik argüman, yasak para simgesi, gömülü metin tarayıcısı kendi kendini
## sınar.

const CURRENCY_FORBIDDEN := ["₺", "TL", "lira", "Lira"]


func before_test() -> void:
	UiText.reset()
	UiText.report_missing = false


func after_test() -> void:
	UiText.reset()


func test_known_key_returns_table_text() -> void:
	assert_str(UiText.t(&"common.confirm")).is_equal("Onayla")
	assert_str(UiText.t(&"app.title")).is_equal("Imaro: The Mayor")


func test_placeholders_are_filled_by_name() -> void:
	assert_str(UiText.t(&"clock.date_ingame", {"year": 3, "day": 17})).is_equal("3. yıl, 17. gün")
	assert_str(UiText.t(&"format.days", {"n": 5})).is_equal("5 gün")


func test_missing_key_shows_key_name_and_is_recorded() -> void:
	var shown := UiText.t(&"no.such.key")
	assert_str(shown).is_equal("no.such.key")
	assert_bool(UiText.missing_keys().has("no.such.key")).is_true()


func test_missing_key_is_not_silent_empty() -> void:
	assert_str(UiText.t(&"another.missing")).is_not_empty()
	assert_bool(UiText.has(&"another.missing")).is_false()


func test_missing_argument_leaves_placeholder_visible() -> void:
	# Argüman verilmezse sessizce silinmez: yer tutucu görünür kalır (hata fark edilsin).
	assert_str(UiText.t(&"format.days")).is_equal("{n} gün")


func test_money_uses_configured_symbol_only() -> void:
	assert_str(UiText.money(1234567)).is_equal("1.234.567 ¤")
	assert_str(UiText.money(0)).is_equal("0 ¤")
	assert_str(UiText.money(-4500)).is_equal("−4.500 ¤")
	UiConfig.set_override("economy.currency_symbol", "Ж")
	assert_str(UiText.money(10)).is_equal("10 Ж")


func test_money_never_contains_forbidden_currency() -> void:
	for amount in [0, 7, 1000, -1000, 123456789]:
		var s := UiText.money(amount)
		for bad in CURRENCY_FORBIDDEN:
			assert_bool(s.contains(bad)).is_false()


func test_money_placeholder_in_template_is_formatted_from_int() -> void:
	assert_str(UiText.t(&"draw.cost", {"money": 2500})).is_equal("Tahmini maliyet: 2.500 ¤")


func test_number_uses_turkish_grouping() -> void:
	assert_str(UiText.number(999)).is_equal("999")
	assert_str(UiText.number(1000)).is_equal("1.000")
	assert_str(UiText.number(-1234)).is_equal("−1.234")


func test_ref_arguments_are_humanised_not_raw() -> void:
	var shown := UiText.t(&"draw.blocked.reason", {"reason": &"parcel.12"})
	assert_str(shown).is_equal("Gerekçe: Parsel 12")
	assert_bool(shown.contains("parcel.12")).is_false()


func test_actor_name_is_placeholder_not_invented() -> void:
	var a := ActorRef.make(&"investor", 3, &"mock.actor.investor.3")
	var shown := UiText.actor_name(a)
	assert_str(shown).is_equal("Yatırımcı 3")
	assert_str(UiText.actor_name(null)).is_equal(UiText.t(&"common.unknown"))


func test_set_table_negative_control_unknown_table_key_is_reported() -> void:
	UiText.set_table({"x.a": "A {n}"})
	assert_str(UiText.t(&"x.a", {"n": 1})).is_equal("A 1")
	assert_str(UiText.t(&"common.confirm")).is_equal("common.confirm")


func test_embedded_text_scanner_finds_violations() -> void:
	var bad := 'label.text = "Merhaba dünya"\nbutton.text = "Onayla"\nvar k := "inspector.title"\n'
	assert_int(UiLiteralScanner.violations_in_source(bad, "x.gd").size()).is_greater(0)
	var ok := 'var k := &"inspector.title"\npush_error("dev only message here")\n# Türkçe yorum serbest\n'
	assert_int(UiLiteralScanner.violations_in_source(ok, "x.gd").size()).is_equal(0)


func test_src_ui_has_no_embedded_player_text() -> void:
	var found := PackedStringArray()
	for dir in ["res://src/ui", "res://scenes/ui"]:
		found.append_array(UiLiteralScanner.violations_in_dir(dir))
	assert_array(Array(found)).is_empty()
