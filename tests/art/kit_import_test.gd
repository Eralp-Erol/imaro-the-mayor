extends GdUnitTestSuite
## T-004 ölçüt 1/2/7 · Kit import doğrulaması (spec 8, 9.2 K1/K2/K6/K11/K12): gerçek manifest + .glb'ler denetlenir;
## olumsuz varyantlar BELLEKTE bozulmuş ölçüm/manifestle gösterilir (doğrulayıcı gerçekten hata yakalıyor mu).
## Gerçek dosyalar `art/blender/rebuild_kit.sh` ile üretilir; içe aktarılmamışsa çalışma zamanı glTF okumasına düşülür.

const SAMPLE_ID := "bld_res_mid_a_gf"
## Spec 2.2 ölçü tablosu: [w_min, w_max, d_min, d_max, eave_min, eave_max]; K1 ±%5 toleransla.
const SCALE_TABLE := {
	"res_old": [6.0, 10.0, 10.0, 14.0, 6.5, 10.5], "res_mid": [12.0, 20.0, 10.0, 16.0, 12.0, 18.0],
	"res_late": [16.0, 24.0, 12.0, 18.0, 15.0, 24.0], "res_house": [7.0, 10.0, 8.0, 10.0, 3.0, 6.0],
	"ind_shed": [30.0, 60.0, 20.0, 40.0, 7.0, 10.0], "ind_heritage": [25.0, 50.0, 15.0, 25.0, 10.0, 15.0],
	"civ_hall": [30.0, 60.0, 20.0, 40.0, 8.0, 16.0],
}
## Spec 2.2 H/W (saçak / cephe genişliği) aralıkları.
const RATIO_TABLE := {
	"res_old": [0.8, 1.4], "res_mid": [0.8, 1.5], "res_late": [0.8, 1.4], "res_house": [0.4, 0.8],
	"ind_shed": [0.15, 0.3], "ind_heritage": [0.3, 0.6], "civ_hall": [0.25, 0.5],
}

var _lib: KitLibrary


func before() -> void:
	_lib = KitLibrary.load_manifest()


func _sample_stats(id: String) -> Dictionary:
	var root := KitLibrary.instantiate_scene(str(_lib.entry(id)["glb"]))
	var stats := KitValidator.inspect_scene(root)
	root.free()
	return stats


# --- Gerçek veri ---------------------------------------------------------------------------------------------

func test_manifest_lists_the_first_eight_modules_and_scale_objects() -> void:
	var min_variants := {"res_mid": 4, "res_old": 4, "res_late": 3, "res_house": 3, "ind_shed": 3, "ind_heritage": 2,
			"civ_hall": 3}   # spec 1: aile başına en az mesh varyantı (+_gf hariç sayılmaz, _gf ayrıca denetlenir)
	for fam in min_variants:
		assert_int(_lib.family_ids(fam, false).size()).is_greater_equal(int(min_variants[fam]))
	assert_int(_lib.family_ids("res_mid", true).size()).is_greater_equal(3)   # _gf varyantları (spec: res_mid +_gf 3)
	assert_int(_lib.family_ids("res_old", true).size()).is_greater_equal(2)
	assert_int(_lib.family_ids("res_late", true).size()).is_greater_equal(2)
	for id in ["bld_lmk_clocktower", "prop_human", "veh_car", "veg_plane", "prop_chimney"]:
		assert_bool(_lib.has_id(id)).is_true()
	assert_int(_lib.entries().size()).is_less_equal(40)      # K6: kit LOD0 mesh sayısı ≤ 40


func test_every_module_passes_import_validation() -> void:
	var result := KitValidator.check_all(_lib)
	assert_array(result["errors"]).is_empty()
	assert_int(result["checked"]).is_equal(_lib.entries().size())


func test_module_names_use_lod_suffixes_and_single_material() -> void:
	for e in _lib.entries():
		var lods: Dictionary = e["lods"]
		assert_bool(lods.has("LOD0")).is_true()
		for lod in lods:
			assert_str(str(lods[lod]["node"])).is_equal("%s_%s" % [e["id"], lod])
		if str(e["kind"]) in ["building", "landmark"]:
			assert_bool(lods.has("LOD1") and lods.has("PROXY")).is_true()


func test_dimensions_match_the_spec_scale_table_within_five_percent() -> void:
	for e in _lib.entries():
		var fam := str(e["family"])
		if not SCALE_TABLE.has(fam):
			continue
		var t: Array = SCALE_TABLE[fam]
		var w := float(e["footprint_m"][0])
		var d := float(e["footprint_m"][1])
		var eave := float(e["eave_height_m"])
		var gf_extra := 1.2 if bool(e["gf"]) else 0.0
		assert_float(w).is_between(t[0] * 0.95, t[1] * 1.05)
		assert_float(d).is_between(t[2] * 0.95, t[3] * 1.05)
		# _gf: tabloda "+1,2" payı (eave tabloya dahil edilirken gf farkı ayrıca tanınır)
		assert_float(eave).is_between(t[4] * 0.95, (t[5] + gf_extra) * 1.05)
		var rt: Array = RATIO_TABLE[fam]
		assert_float(eave / w).is_between(rt[0] * 0.95, rt[1] * 1.05)


func test_scale_reference_objects_match_section_2_3() -> void:
	var human: Array = _lib.entry("prop_human")["aabb_lod0_m"]["max"]
	assert_float(float(human[1])).is_equal_approx(1.75, 1.75 * 0.05)
	var car: Dictionary = _lib.entry("veh_car")["aabb_lod0_m"]
	var size := Vector3(car["max"][0] - car["min"][0], car["max"][1] - car["min"][1], car["max"][2] - car["min"][2])
	assert_float(size.z).is_equal_approx(4.4, 4.4 * 0.05)
	assert_float(size.x).is_equal_approx(1.8, 1.8 * 0.05)
	assert_float(size.y).is_equal_approx(1.5, 1.5 * 0.05)
	assert_float(float(_lib.entry("veg_plane")["total_height_m"])).is_between(13.3, 14.7)
	assert_float(float(_lib.entry("prop_chimney")["total_height_m"])).is_between(25.0, 35.0)


func test_clock_tower_height_is_human_scaled() -> void:
	var e := _lib.entry("bld_lmk_clocktower")
	assert_float(float(e["total_height_m"])).is_between(21.0, 25.0)     # spec 4: 23 m [ÇM], kabul 21–25
	assert_float(float(e["total_height_m"])).is_less(26.0)               # mutlak üst sınır
	assert_int(int(e["lods"]["LOD0"]["tris"])).is_less_equal(1200)
	assert_int(int(e["lods"]["LOD1"]["tris"])).is_less_equal(120)


func test_triangle_budgets_and_proxies() -> void:
	for e in _lib.entries():
		assert_int(int(e["lods"]["LOD0"]["tris"])).is_less_equal(1500)
		if e["lods"].has("PROXY"):
			assert_int(int(e["lods"]["PROXY"]["tris"])).is_less_equal(14)
		if e["lods"].has("LOD1") and str(e["kind"]) in ["building"]:
			assert_int(int(e["lods"]["LOD1"]["tris"])).is_between(16, 60)


func test_roof_types_are_varied_not_all_tile() -> void:
	var types := {}
	for e in _lib.entries():
		if str(e["kind"]) == "building":
			types[str(e["roof_type"])] = int(types.get(str(e["roof_type"]), 0)) + 1
	assert_bool(types.has("flat") and types.has("hip") and types.has("gable") and types.has("sawtooth")).is_true()
	assert_int(int(types["flat"])).is_greater(int(types["hip"]))     # düz teras baskın (spec 3.2)


func test_footprint_variants_differ_by_at_least_twenty_percent_in_area() -> void:
	# Spec 3.3(1): aynı ailede en az bir çift mesh ayak izi alanı ≥ %20 farklı olmalı (maket hissi önleme).
	for fam in ["res_mid", "res_old", "res_late", "res_house"]:
		var areas: Array[float] = []
		for id in _lib.family_ids(fam, false):
			var fp: Array = _lib.entry(id)["footprint_m"]
			areas.append(float(fp[0]) * float(fp[1]))
		areas.sort()
		assert_float(areas[-1] / areas[0]).is_greater_equal(1.2)


# --- Olumsuz varyantlar: doğrulayıcı hatayı yakalar ---------------------------------------------------------------

func test_negative_baseline_sample_passes() -> void:
	var errors := KitValidator.check_entry(_lib.entry(SAMPLE_ID), _sample_stats(SAMPLE_ID))
	assert_array(errors).is_empty()


func test_negative_triangle_count_mismatch_is_reported() -> void:
	var stats := _sample_stats(SAMPLE_ID)
	stats["%s_LOD0" % SAMPLE_ID]["tris"] += 10
	assert_array(KitValidator.check_entry(_lib.entry(SAMPLE_ID), stats)).is_not_empty()


func test_negative_two_surfaces_and_wrong_material_are_reported() -> void:
	var stats := _sample_stats(SAMPLE_ID)
	stats["%s_LOD0" % SAMPLE_ID]["surfaces"] = 2
	var errors := KitValidator.check_entry(_lib.entry(SAMPLE_ID), stats)
	assert_bool(_any_contains(errors, "surface")).is_true()
	var stats2 := _sample_stats(SAMPLE_ID)
	stats2["%s_LOD0" % SAMPLE_ID]["materials"] = ["mat_wall"]
	assert_bool(_any_contains(KitValidator.check_entry(_lib.entry(SAMPLE_ID), stats2), "mat_kit")).is_true()


func test_negative_pivot_offset_is_reported() -> void:
	var stats := _sample_stats(SAMPLE_ID)
	var ab: AABB = stats["%s_LOD0" % SAMPLE_ID]["aabb"]
	stats["%s_LOD0" % SAMPLE_ID]["aabb"] = AABB(ab.position + Vector3(0.0, 1.0, 0.0), ab.size)   # taban merkezi/y kaydı
	assert_bool(_any_contains(KitValidator.check_entry(_lib.entry(SAMPLE_ID), stats), "etek")).is_true()
	var stats2 := _sample_stats(SAMPLE_ID)
	var ab2: AABB = stats2["%s_LOD0" % SAMPLE_ID]["aabb"]
	stats2["%s_LOD0" % SAMPLE_ID]["aabb"] = AABB(ab2.position + Vector3(5.0, 0.0, 0.0), ab2.size)
	assert_bool(_any_contains(KitValidator.check_entry(_lib.entry(SAMPLE_ID), stats2), "pivot")).is_true()


func test_negative_missing_lod_node_and_bad_name_are_reported() -> void:
	var stats := _sample_stats(SAMPLE_ID)
	stats.erase("%s_PROXY" % SAMPLE_ID)
	assert_bool(_any_contains(KitValidator.check_entry(_lib.entry(SAMPLE_ID), stats), "PROXY")).is_true()
	var bad := _lib.entry(SAMPLE_ID).duplicate(true)
	bad["id"] = "Bld_Res_Mid_A"
	assert_bool(_any_contains(KitValidator.check_entry(bad, _sample_stats(SAMPLE_ID)), "adlandırma")).is_true()


func test_negative_budget_violations_are_reported() -> void:
	var entry := _lib.entry(SAMPLE_ID).duplicate(true)
	var stats := _sample_stats(SAMPLE_ID)
	entry["lods"]["LOD0"]["tris"] = 2000
	stats["%s_LOD0" % SAMPLE_ID]["tris"] = 2000
	assert_bool(_any_contains(KitValidator.check_entry(entry, stats), "tavan")).is_true()
	var entry2 := _lib.entry(SAMPLE_ID).duplicate(true)
	var stats2 := _sample_stats(SAMPLE_ID)
	entry2["lods"]["PROXY"]["tris"] = 20
	stats2["%s_PROXY" % SAMPLE_ID]["tris"] = 20
	assert_bool(_any_contains(KitValidator.check_entry(entry2, stats2), "PROXY")).is_true()


func test_negative_tower_height_out_of_range_is_reported() -> void:
	var id := "bld_lmk_clocktower"
	var entry := _lib.entry(id).duplicate(true)
	var stats := _sample_stats(id)
	var ab: AABB = stats["%s_LOD0" % id]["aabb"]
	stats["%s_LOD0" % id]["aabb"] = AABB(ab.position, ab.size + Vector3(0.0, 7.0, 0.0))   # 30 m kule
	entry["total_height_m"] = 30.0
	entry["aabb_lod0_m"]["max"][1] = 30.0
	assert_bool(_any_contains(KitValidator.check_entry(entry, stats), "saat kulesi")).is_true()


func test_negative_stale_sha_and_wrong_manifest_aabb_are_reported() -> void:
	var stats := _sample_stats(SAMPLE_ID)
	assert_bool(_any_contains(KitValidator.check_entry(_lib.entry(SAMPLE_ID), stats, "00ff"), "sha256")).is_true()
	var entry := _lib.entry(SAMPLE_ID).duplicate(true)
	entry["aabb_lod0_m"]["max"][0] = float(entry["aabb_lod0_m"]["max"][0]) + 3.0
	assert_bool(_any_contains(KitValidator.check_entry(entry, stats), "AABB")).is_true()


func test_negative_inspect_mesh_detects_two_surfaces_and_bad_uv() -> void:
	var mesh := ArrayMesh.new()
	for k in 2:
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3.ZERO, Vector3.RIGHT, Vector3.UP])
		arr[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0.03125, 1.0), Vector2(0.03125, 1.0), Vector2(0.9, 0.0)])
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var st := KitValidator.inspect_mesh(mesh)
	assert_int(st["surfaces"]).is_equal(2)
	assert_bool(st["uv_ok"]).is_false()   # 0,9 parça kimliği değil; y = 0 gölge çarpanı geçersiz


func test_generator_is_deterministic_when_blender_is_available() -> void:
	var blender := "/Applications/Blender.app/Contents/MacOS/Blender"
	if not FileAccess.file_exists(blender):
		return   # Blender yok (CI): determinizm başka ortamda doğrulanır; test atlanır
	var script := ProjectSettings.globalize_path("res://art/blender/generators/build_kit.py")
	var hashes: Array[String] = []
	for run in 2:
		var out_dir := OS.get_temp_dir().path_join("imaro_kit_det_%d_%d" % [OS.get_process_id(), run])
		var output: Array = []
		var code := OS.execute(blender, ["--background", "--factory-startup", "--python", script, "--", "--seed", "0",
				"--only", "res_mid,lmk_clocktower,prop_human", "--out-root", out_dir], output)
		assert_int(code).is_equal(0)
		var manifest := FileAccess.get_file_as_string(out_dir.path_join("buildings/kit_manifest.json"))
		hashes.append(manifest.sha256_text())
	assert_str(hashes[0]).is_equal(hashes[1])
	assert_str(hashes[0]).is_not_empty()


func _any_contains(errors: Array[String], needle: String) -> bool:
	for e in errors:
		if e.contains(needle):
			return true
	return false
