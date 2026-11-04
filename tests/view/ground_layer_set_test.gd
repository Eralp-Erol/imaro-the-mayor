extends GdUnitTestSuite
## T-062 A4 / ADR-0006 §3.3 · Onaylı zemin katmanları: dizi YALNIZ kapıdan geçen kimliklerden kurulur (14 onaylı),
## sıra `layer_index`, tile_m tablodan; onaysız/bozuk tablo katman YÜKLEMEZ; üretim kodunda lab/macro doku
## referansı yok.

const GROUND_TABLE := "res://data/library/game_ground.json"


func _table() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(GROUND_TABLE)) as Dictionary


func test_array_is_built_headless_from_the_14_approved_layers_in_layer_index_order() -> void:
	var layers := GroundLayerSet.build(LibraryGate.load_default())
	assert_array(Array(layers.errors)).is_empty()
	assert_int(layers.count()).is_equal(14)
	assert_object(layers.array).is_not_null()
	assert_int(layers.array.get_layers()).is_equal(14)
	assert_int(layers.size_px).is_equal(512)
	assert_int(layers.mip_levels).is_greater(5)   # mipmap açık (A0): uzakta moiré önlemi
	var rows: Array = _table()["layers"]
	for row: Dictionary in rows:
		var id := str(row["id"])
		assert_int(layers.index_of(id)).is_equal(int(row["layer_index"]))
		assert_float(layers.tile_m[layers.index_of(id)]).is_equal(float(row["tile_m"]))
	assert_int(layers.gate.unapproved_ids.size()).is_equal(0)


func test_shared_set_is_cached_and_feeds_terrain_and_roads_one_array() -> void:
	assert_object(GroundLayerSet.shared()).is_same(GroundLayerSet.shared())


func test_a_table_with_a_rejected_id_loads_no_layers_fail_closed() -> void:
	# Negatif: katalogda rejected olan kimlik tabloda varsa kapı tabloyu TÜMDEN reddeder -> sıfır katman, hata kaydı.
	var catalog := JSON.parse_string(FileAccess.get_file_as_string(LibraryGate.CATALOG_PATH)) as Dictionary
	var entries: Array = catalog["entries"]
	entries.append({"id": "gnd_tex_evil", "approval": "rejected"})
	var table := _table()
	var rows: Array = table["layers"]
	rows.append({"id": "gnd_tex_evil", "png": "res://assets/ground/tex/gnd_macro.png", "tile_m": 4.0, "layer_index": 99})
	var gate := LibraryGate.new()
	gate.report_errors = false
	assert_bool(gate.load_catalog_text(JSON.stringify(catalog), "catalog")).is_true()
	assert_bool(gate.add_table_text(JSON.stringify(table), "ground")).is_false()
	var layers := GroundLayerSet.build(gate)
	assert_int(layers.count()).is_equal(0)
	assert_object(layers.array).is_null()
	assert_bool(layers.has_layer("gnd_tex_evil")).is_false()
	assert_bool(gate.load_errors.size() > 0).is_true()


func test_resolve_of_unknown_id_returns_the_fallback_and_counts_a_denial() -> void:
	var gate := LibraryGate.load_default()
	gate.report_errors = false
	var layers := GroundLayerSet.build(gate, false)
	var fallback := layers.index_of("gnd_tex_grass_dry")
	assert_int(layers.resolve("gnd_lab_ctrl", "gnd_tex_grass_dry")).is_equal(fallback)
	assert_int(gate.unapproved_ids.size()).is_equal(1)
	assert_int(gate.denied_requests).is_equal(1)
	# Onaylı kimlik ret saymaz.
	assert_int(layers.resolve("gnd_tex_rock_cliff", "gnd_tex_grass_dry")).is_equal(layers.index_of("gnd_tex_rock_cliff"))
	assert_int(gate.denied_requests).is_equal(1)


func test_production_code_has_no_lab_or_macro_ground_texture_reference() -> void:
	# `gnd_macro.png` / `gnd_lab_ctrl.png` katalogda YOK: oyunda kullanılmaz. Ayrıca zemin PNG yolu yalnız oyun
	# tablosundan (data/library, kapı) gelir: üretim koduna sabit yol yazılamaz.
	var tokens := ["gnd_macro", "gnd_lab_ctrl", "ground_lab", "assets/ground/tex/"]
	var hits: Array[String] = []
	for root in ["res://src", "res://art/shaders", "res://scenes/game", "res://data/view", "res://data/world"]:
		for path in _text_files(root):
			var text := FileAccess.get_file_as_string(path)
			for token in tokens:
				if text.contains(token):
					hits.append("%s -> %s" % [path, token])
	hits.sort()
	assert_array(hits).override_failure_message("lab/macro zemin referansı: %s" % str(hits)).is_empty()


func _text_files(dir_path: String) -> PackedStringArray:
	var out := PackedStringArray()
	for sub in DirAccess.get_directories_at(dir_path):
		out.append_array(_text_files(dir_path.path_join(sub)))
	for file in DirAccess.get_files_at(dir_path):
		if ["gd", "json", "tscn", "tres", "gdshader"].has(file.get_extension()):
			out.append(dir_path.path_join(file))
	return out
