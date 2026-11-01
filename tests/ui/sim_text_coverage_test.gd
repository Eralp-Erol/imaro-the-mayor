extends GdUnitTestSuite
## B-011: sim'in yazdığı her olay `message_key`i ve her komut türü Türkçe tabloda karşılık bulur (bildirim şeridinde ham
## `public_work.demolish` / `event.road.demolished` görünmesin). Kaynak taraması: src/sim altındaki dosyalarda
## `&"event.…"` sabitleri ve `SimCommand.KIND_*` komut türü sabitleri. Yeni olay/komut eklenip metni unutulursa bu
## test KIRILIR.

const EVENT_RX := "&\"(event\\.[a-z0-9_]+(?:\\.[a-z0-9_]+)*)\""
const COMMAND_RX := "const KIND_[A-Z_]+ := &\"([a-z_.]+)\""


func before_test() -> void:
	UiText.reset()
	UiText.report_missing = false


func after_test() -> void:
	UiText.reset()


func _sim_files(dir_path: String, out: PackedStringArray) -> void:
	for f in DirAccess.get_files_at(dir_path):
		if f.ends_with(".gd"):
			out.append(dir_path.path_join(f))
	for d in DirAccess.get_directories_at(dir_path):
		_sim_files(dir_path.path_join(d), out)


func _matches(rx_text: String) -> PackedStringArray:
	var files := PackedStringArray()
	_sim_files("res://src/sim", files)
	files.append("res://src/contracts/sim_command.gd")
	var rx := RegEx.create_from_string(rx_text)
	var out := PackedStringArray()
	for path in files:
		for m in rx.search_all(FileAccess.get_file_as_string(path)):
			var key := m.get_string(1)
			if not out.has(key):
				out.append(key)
	return out


func test_scan_finds_the_known_keys() -> void:
	assert_bool(_matches(EVENT_RX).has("event.road.demolished")).is_true()
	assert_bool(_matches(COMMAND_RX).has("public_work.demolish")).is_true()


func test_every_sim_event_key_has_turkish_text() -> void:
	var missing := PackedStringArray()
	for key in _matches(EVENT_RX):
		var probe := SimEvent.new()
		probe.message_key = StringName(key)
		if UiText.has(StringName(key)) or ExpropriationText.handles_event(probe.message_key) \
				or PolicyText.handles_event(probe.message_key):
			continue
		missing.append(key)
	assert_array(missing).override_failure_message("çevirisiz olay anahtarları: %s" % ", ".join(missing)).is_empty()


func test_every_sim_command_kind_reads_as_turkish_in_the_strip() -> void:
	var bad := PackedStringArray()
	for kind in _matches(COMMAND_RX):
		var event := SimEvent.new()
		event.kind = SimEvent.KIND_COMMAND_APPLIED
		event.message_key = &"event.command.applied"
		event.args = {"kind": kind}
		var text := UiText.event_text(event)
		if text.contains(kind):
			bad.append("%s -> '%s'" % [kind, text])
	assert_array(bad).override_failure_message("ham komut türü: %s" % ", ".join(bad)).is_empty()
