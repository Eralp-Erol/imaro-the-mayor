extends GdUnitTestSuite
## T-050 / D-012 / D-013 · Yaşam varlıkları YALNIZ onaylı kütüphane kapısından gelir: araç `veh_car`, insan B blok figür
## (nötr + geniş). Başka kimlik (piyon/faset/eski kit insanı) kapıdan geçmez, mesh yüklenmez.
## Kapı kapalıysa görünüm kurulmaz.

const TABLES := ["res://data/library/game_vehicles.json", "res://data/library/game_humans.json"]


func _gate() -> LibraryGate:
	var g := LibraryGate.new()
	g.report_errors = false
	return g


func test_life_gate_grants_exactly_the_three_approved_ids() -> void:
	var gate := LibraryGate.load_life()
	var ids := Array(gate.approved_ids())
	ids.sort()
	assert_array(ids).is_equal(["hum_hero_block_broad_a", "hum_hero_block_neutral_a", "veh_car"])
	assert_bool(gate.is_closed()).is_false()


func test_not_selected_or_unapproved_human_styles_are_denied() -> void:
	var gate := _gate()
	assert_bool(gate.load_game_tables(PackedStringArray(TABLES), LibraryGate.CATALOG_PATH)).is_true()
	for id in ["hum_hero_pawn_neutral_a", "hum_hero_pawn_broad_a", "hum_hero_facet_neutral_a",
			"hum_hero_facet_broad_a", "prop_human", "veh_tram", "veh_bus"]:
		assert_dict(gate.request(id)).override_failure_message("%s kapıdan geçti" % id).is_empty()
	assert_int(gate.denied_requests).is_equal(7)


func test_assets_load_through_the_gate_and_are_complete() -> void:
	var assets := LifeAssets.load_default(_gate_loaded())
	assert_array(Array(assets.errors)).override_failure_message("; ".join(assets.errors)).is_empty()
	assert_bool(assets.ok()).is_true()
	assert_array(Array(assets.loaded_ids)).is_equal(["veh_car", "hum_hero_block_neutral_a", "hum_hero_block_broad_a"])
	assert_int(assets.car_rows.size()).is_greater(0)
	for body in 2:
		for lod in 2:
			assert_object((assets.human_mesh[body] as Array)[lod]).is_not_null()
	# LOD1 daha ucuz olmalı (uzak temsil).
	var tri0 := _tris((assets.human_mesh[0] as Array)[0] as Mesh)
	var tri1 := _tris((assets.human_mesh[0] as Array)[1] as Mesh)
	assert_int(tri1).is_less_equal(tri0)


func test_closed_gate_builds_no_assets() -> void:
	var gate := _gate()
	assert_bool(gate.load_game_tables(PackedStringArray(TABLES), "res://data/library/yok_katalog.json")).is_false()
	var assets := LifeAssets.load_default(gate)
	assert_bool(assets.ok()).is_false()
	assert_bool(assets.errors.is_empty()).is_false()
	assert_object(assets.car_mesh).is_null()
	assert_object(assets.atlas).is_null()


func test_materials_carry_movement_params_and_compile() -> void:
	var assets := LifeAssets.load_default(_gate_loaded())
	var mv := LifeConfig.load_default().data["movement"] as Dictionary
	for mat: ShaderMaterial in [assets.make_car_material(mv), assets.make_human_material(mv)]:
		assert_object(mat.shader).is_not_null()
		assert_float(float(mat.get_shader_parameter("life_speed"))).is_greater(0.0)
		assert_float(float(mat.get_shader_parameter("life_end_fade"))).is_equal(float(mv["end_fade_m"]))
	var car_speed: float = assets.make_car_material(mv).get_shader_parameter("life_speed")
	var human_speed: float = assets.make_human_material(mv).get_shader_parameter("life_speed")
	assert_float(car_speed).is_equal(float(mv["car_speed_mps"]))
	assert_float(human_speed).is_equal(float(mv["person_speed_mps"]))


func _gate_loaded() -> LibraryGate:
	var gate := _gate()
	gate.load_game_tables(PackedStringArray(TABLES), LibraryGate.CATALOG_PATH)
	return gate


func _tris(mesh: Mesh) -> int:
	var n := 0
	for s in mesh.get_surface_count():
		var idx: Variant = mesh.surface_get_arrays(s)[Mesh.ARRAY_INDEX]
		n += (idx as PackedInt32Array).size() / 3
	return n
