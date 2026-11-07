extends GdUnitTestSuite
## T-078 · Dosya boyu koruması: `economy_system.gd` gdlint sınırının (1000) çok altında kalır (M3 işleri ekonomiye
## dokunur; yeni mantık yan sınıflara gider). Bölünmenin (aylık akış, proje yaşam döngüsü) geri toplanmasını da yakalar.

const MAX_LINES := 800
const SPLIT_CLASSES: Array[String] = [
	"res://src/sim/economy/economy_monthly.gd", "res://src/sim/economy/economy_projects.gd",
]


func _lines(path: String) -> int:
	return FileAccess.get_file_as_string(path).split("\n").size()


func test_economy_system_stays_under_line_budget() -> void:
	var lines := _lines("res://src/sim/economy/economy_system.gd")
	assert_int(lines).override_failure_message("economy_system.gd %d satır (sınır %d)" % [lines, MAX_LINES]) \
		.is_less_equal(MAX_LINES)


func test_split_classes_exist_and_are_also_bounded() -> void:
	for path in SPLIT_CLASSES:
		assert_bool(FileAccess.file_exists(path)).override_failure_message("%s yok" % path).is_true()
		assert_int(_lines(path)).is_less_equal(MAX_LINES)
