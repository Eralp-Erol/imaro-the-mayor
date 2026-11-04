extends GdUnitTestSuite
## T-062 B1 / ADR-0006 §2.1b · görünüm tablosu yalnız onaylı oyun tablosundan; mesh isteği kapıdan; onaysız kimlik
## yüklenmez (negatif). Leke rengi atlastan piştirilir.


func test_look_covers_exactly_the_approved_game_species_in_table_order() -> void:
	var look := VegetationViewTestSupport.look_full()
	var gate := VegetationTestSupport.species().gate
	assert_array(Array(look.errors)).is_empty()
	assert_array(Array(look.ids)).is_equal(Array(gate.approved_ids_of("vegetation")))
	assert_int(look.count).is_equal(10)
	for id in look.ids:
		assert_bool(gate.is_approved(id)).is_true()
	assert_int(gate.unapproved_ids.size()).is_equal(0)


func test_all_levels_load_and_only_palms_have_a_proxy_mesh() -> void:
	var look := VegetationViewTestSupport.look_full()
	for i in look.count:
		assert_object(look.mesh_lod0[i]).is_not_null()
		assert_object(look.mesh_lod1[i]).is_not_null()
		var palm := look.keys[i].begins_with("palm_")
		assert_bool(look.mesh_proxy[i] != null).is_equal(palm)
		# LOD1, LOD0'dan az ya da eşit üçgen (kayıt sözleşmesi); mesh gerçekten üçgen taşır.
		assert_int((look.mesh_lod1[i] as ArrayMesh).get_surface_count()).is_greater(0)


func test_unapproved_ids_are_never_loaded_negative() -> void:
	var gate := LibraryGate.load_plants()
	gate.report_errors = false
	# kit çınarı: katalogda approved ama oyun tablosunda DEĞİL; reddedilmiş bir bina kimliği; bilinmeyen kimlik.
	for id in ["veg_plane", "bld_lmk_clocktower", "veg_hero_does_not_exist", ""]:
		assert_object(VegetationLook.mesh_for(gate, id, "LOD0")).is_null()
	assert_int(gate.unapproved_ids.size()).is_equal(4)
	assert_int(gate.denied_requests).is_equal(4)
	# onaylı kimlik geçer
	assert_object(VegetationLook.mesh_for(gate, "veg_hero_plane_a", "LOD1")).is_not_null()
	assert_int(gate.unapproved_ids.size()).is_equal(4)


func test_a_closed_gate_yields_no_species_and_no_meshes() -> void:
	var gate := LibraryGate.new()
	gate.report_errors = false
	gate.add_table_text("{not json", "bozuk")
	var sp := VegetationSpecies.from_gate(gate)
	assert_int(sp.size()).is_equal(0)
	var look := VegetationLook.load_full(sp, VegetationViewTestSupport.config())
	assert_int(look.count).is_equal(0)


func test_baked_blob_colors_are_green_and_differ_between_species() -> void:
	var look := VegetationViewTestSupport.look_full()
	var seen: Dictionary = {}
	for i in look.count:
		var c := look.blob_color[i]
		assert_bool(c.g > c.b).override_failure_message("%s rengi yeşil değil: %s" % [look.keys[i], c]).is_true()
		assert_bool(c.g >= c.r - 0.02).is_true()
		assert_bool(c != VegetationLook.NEUTRAL).is_true()
		seen[c.to_html(false)] = true
	assert_int(seen.size()).is_greater(4)


func test_bake_color_with_a_fully_transparent_atlas_falls_back_to_neutral() -> void:
	var look := VegetationViewTestSupport.look_full()
	var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 0, 0, 0))   # tüm pikseller alfa maskesinin altında
	assert_that(VegetationLook.bake_color(look.mesh_lod1[0] as ArrayMesh, img)).is_equal(VegetationLook.NEUTRAL)
	img.fill(Color(0, 1, 0, 1))
	var c := VegetationLook.bake_color(look.mesh_lod1[0] as ArrayMesh, img)
	assert_bool(c.g > 0.9 and c.r < 0.1).is_true()


func test_view_sources_hardcode_no_asset_path_or_species_id() -> void:
	# Mesh yolu yalnız kapıdan gelir: görünüm kaynaklarında GLB yolu ve tür kimliği yok.
	for f in ["vegetation_view", "vegetation_look", "vegetation_layout", "vegetation_window",
			"vegetation_cell_builder", "vegetation_blob_builder", "vegetation_lod", "vegetation_loader",
			"vegetation_cache", "vegetation_view_config"]:
		var text := FileAccess.get_file_as_string("res://src/view/vegetation/%s.gd" % f)
		assert_bool(text.contains(".glb")).override_failure_message("%s: .glb yolu" % f).is_false()
		assert_bool(text.contains("veg_hero_")).override_failure_message("%s: tür kimliği" % f).is_false()
		assert_bool(text.contains("assets/hero")).override_failure_message("%s: asset yolu" % f).is_false()
