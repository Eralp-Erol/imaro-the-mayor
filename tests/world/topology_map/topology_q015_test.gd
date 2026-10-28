extends GdUnitTestSuite
## T-028 · Q-015 uyumu: harita ayrı veri değildir; kaynakta gömülü harita koordinatı yok, veri dizinine üretilmiş dosya
## girmez, görünüm WorldData'yı değiştirmez. Her tarama olumsuz varyantla kanıtlanır.

const SOURCE_DIR := "res://src/world/topology_map"
const DATA_DIR := "res://data/world/ismeral"
const ALLOWED_DATA_FILES: Array[String] = ["world.json", "coast.json", "regions.json", "sites.json", "terrain.json",
		"network.json", "settlement.json", "vegetation.json"]


static func hardcoded_coordinates(text: String) -> PackedStringArray:
	var rx := RegEx.create_from_string("Vector2\\(\\s*-?\\d{4,}")
	var hits := PackedStringArray()
	for m in rx.search_all(text):
		hits.append(m.get_string())
	return hits


func test_no_source_hardcodes_a_map_coordinate() -> void:
	var checked := 0
	for name in DirAccess.open(SOURCE_DIR).get_files():
		if name.ends_with(".gd"):
			var hits := hardcoded_coordinates(FileAccess.get_file_as_string("%s/%s" % [SOURCE_DIR, name]))
			assert_array(hits).override_failure_message("%s: %s" % [name, hits]).is_empty()
			checked += 1
	assert_int(checked).is_greater(8)
	assert_bool(hardcoded_coordinates("var p := Vector2(20227.9, 18666.8)").is_empty()).is_false()


func test_no_generated_map_data_in_the_world_data_dir() -> void:
	for name in DirAccess.get_files_at(DATA_DIR):
		if name.ends_with(".uid") or name.ends_with(".import"):
			continue
		assert_bool(ALLOWED_DATA_FILES.has(name)).override_failure_message("beklenmeyen dosya: %s" % name).is_true()


func test_building_the_model_does_not_modify_the_world() -> void:
	var world := WorldTestSupport.default_world()
	var before := world.state_hash()
	var m := TopologyModel.build(world, null, null)
	assert_str(world.state_hash()).is_equal(before)
	assert_object(m).is_not_null()


func test_source_never_names_a_place() -> void:
	# CAN-01: kaynakta Orven dışında özel yer adı sabiti yok (D2 adı veriden gelir; metin sabitinde yalnız kanon adları).
	var allowed := ["Orven", "Ismeral", "Anderva", "Imaro"]
	var rx := RegEx.create_from_string("\"[^\"]*\\b(Karvet|Varnis|Konak|Kemeraltı|Bornova|Karşıyaka|Bayraklı)\\b[^\"]*\"")
	for name in DirAccess.open(SOURCE_DIR).get_files():
		if name.ends_with(".gd"):
			var text := FileAccess.get_file_as_string("%s/%s" % [SOURCE_DIR, name])
			assert_object(rx.search(text)).override_failure_message(name).is_null()
	assert_array(allowed).is_not_empty()
	assert_object(rx.search("\"Karşıyaka mahallesi\"")).is_not_null()
