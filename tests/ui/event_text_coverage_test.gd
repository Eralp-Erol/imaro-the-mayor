extends GdUnitTestSuite
## HUD'da ham anahtar görünmemeli: sim'in ürettiği her olay `message_key`i `UiText`te karşılık bulur. Önceki hata:
## `event.agenda.expired` (EventEngine `"event.agenda.%s" % status` ile üretir) çevrilmemiş olarak şeritte görünüyordu.
## Statik kısım: dinamik anahtar parçaları (gündem durumu, grup tepkisi). Dinamik kısım: gerçek ekonomi/siyaset
## facade'i günlerce koşulur, görülen her anahtar çözülmeli. Görülmeyen anahtar bu testle kanıtlanmış SAYILMAZ
## (statik kısım var).

const DAYS := 400
const PARCELS := 120


func before_test() -> void:
	UiText.reset()
	UiText.report_missing = false


func after_test() -> void:
	UiText.reset()


func test_agenda_status_keys_have_text() -> void:
	for status: String in [EventEngine.RESOLVED, EventEngine.EXPIRED]:
		var key := StringName("event.agenda.%s" % status)
		assert_bool(UiText.has(key)).override_failure_message("çevirisi yok: %s" % key).is_true()


func test_group_reaction_keys_have_text() -> void:
	var reactions: Array[String] = ["support", "oppose", "protest", "calmed"]
	var blocs: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/politics/blocs.json"))
	for r: Variant in (blocs["tier_reactions"] as Dictionary).values():
		if not reactions.has(str(r)):
			reactions.append(str(r))
	for r in reactions:
		var key := StringName("event.group.%s" % r)
		assert_bool(UiText.has(key)).override_failure_message("çevirisi yok: %s" % key).is_true()


func test_every_event_key_from_a_real_run_has_text() -> void:
	var views: Array[ParcelView] = []
	for i in PARCELS:
		var v := ParcelView.new()
		v.id = i + 1
		v.region_code = &"D1" if i % 2 == 0 else &"D2"
		v.center = Vector2(float(i % 20) * 40.0, float(i / 20) * 40.0)
		v.area_m2 = 400
		v.zone = &"zone.residential"
		views.append(v)
	var facade := EconomyBootstrap.create_facade(17, ListParcelSource.create(&"event-text-test", views))
	assert_object(facade).is_not_null()
	facade.submit_command(SimCommand.zoning_propose(PackedInt64Array([1]), &"zone.commercial"))
	facade.advance(DAYS)
	var missing := PackedStringArray()
	var seen := 0
	for e in facade.events_since(0):
		if e.kind == SimEvent.KIND_COMMAND_REJECTED:
			continue
		seen += 1
		if not UiText.has(e.message_key) and not missing.has(String(e.message_key)):
			missing.append(String(e.message_key))
	assert_int(seen).is_greater(0)
	assert_array(missing).override_failure_message("çevirisiz olay anahtarları: %s" % ", ".join(missing)).is_empty()
