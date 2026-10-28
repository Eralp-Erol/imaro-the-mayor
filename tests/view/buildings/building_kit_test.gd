extends GdUnitTestSuite
## T-062 A3 · Bina tablosu (BuildingKit): oyun tablosu sırası = module_idx, yalnız onaylı kimlik (negatif dahil), kademe
## eşlemesi VERİDEN (hero LOD1 -> LOD0 kademesi, PROXY -> LOD1 kademesi, hero LOD0 çizilmez), pivot normalizasyonu,
## PROXY şablonu/piştirilmiş renk (HLOD1/HLOD2), determinizm. REQ: VIS-01/02/03/05, WLD-01, TEK-03.

var _kit: BuildingKit
var _table: Dictionary


func before() -> void:
	_kit = BuildingTestSupport.kit()
	_table = BuildingTestSupport.loaded_table()["table"]


func _record(id: String) -> Dictionary:
	for rec: Dictionary in _table["modules"]:
		if str(rec["id"]) == id:
			return rec
	return {}


func _triangles(mesh: ArrayMesh) -> int:
	var total := 0
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		total += (arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	return total


func test_module_order_matches_the_game_table_and_dimensions_come_from_it() -> void:
	var modules: Array = _table["modules"]
	assert_int(_kit.count).is_equal(modules.size())
	assert_int(_kit.count).is_equal(21)   # onaylı hero sayısı (D-005)
	for n in modules.size():
		assert_str(_kit.ids[n]).is_equal(str(modules[n]["id"]))
		assert_float(_kit.footprint_w[n]).is_equal_approx(float(modules[n]["footprint_m"][0]), 0.001)
		assert_float(_kit.footprint_d[n]).is_equal_approx(float(modules[n]["footprint_m"][1]), 0.001)
		assert_float(_kit.height_m[n]).is_equal_approx(float(modules[n]["height_m"]), 0.001)
	assert_int(_kit.module_index(BuildingTestSupport.MID_A)).is_greater_equal(0)
	assert_int(_kit.module_index("yok_boyle_bir_modul")).is_equal(-1)


func test_every_kit_module_is_approved_in_the_gate_and_in_the_catalog() -> void:
	var gate := BuildingTestSupport.gate()
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(LibraryGate.CATALOG_PATH))
	var status: Dictionary = {}
	for entry: Dictionary in catalog["entries"]:
		status[str(entry["id"])] = str(entry["approval"])
	for id in _kit.ids:
		assert_bool(gate.is_approved(id)).is_true()
		assert_str(str(status.get(id, "?"))).is_equal("approved")
		assert_bool(id.begins_with("bld_hero_")).is_true()
	assert_int(gate.unapproved_ids.size()).is_equal(0)


func test_rejected_or_unknown_ids_never_enter_the_kit_negative() -> void:
	# Yerleşim tablosuna sızmış reddedilmiş bir kayıt: kit onu ALMAZ, kapı sayar (kapı çıktısı sessiz değildir).
	var gate := LibraryGate.load_default()
	gate.report_errors = false
	var table := _table.duplicate(true)
	var fake := _record(BuildingTestSupport.MID_A).duplicate(true)
	fake["id"] = "bld_res_mid_a"        # D-005'te rejected eski kit kimliği
	var unknown := _record(BuildingTestSupport.MID_A).duplicate(true)
	unknown["id"] = "bld_hero_uydurma"   # katalogda yok
	(table["modules"] as Array).insert(0, fake)
	(table["modules"] as Array).append(unknown)
	var kit := BuildingKit.from_table(table, gate)
	assert_int(kit.count).is_equal(21)
	assert_int(kit.module_index("bld_res_mid_a")).is_equal(-1)
	assert_int(kit.module_index("bld_hero_uydurma")).is_equal(-1)
	assert_array(Array(gate.unapproved_ids)).contains_exactly_in_any_order(["bld_res_mid_a", "bld_hero_uydurma"])
	# sıra, süzülmüş tabloyla aynı kalır (module_idx kaymaz)
	for n in kit.count:
		assert_str(kit.ids[n]).is_equal(_kit.ids[n])


func test_tier_mapping_comes_from_the_table_hero_lod1_near_proxy_mid_and_lod0_is_never_drawn() -> void:
	assert_str(str(BuildingKit.LEVEL_FOR_TIER[BuildingLod.Tier.LOD0])).is_equal("LOD1")
	assert_str(str(BuildingKit.LEVEL_FOR_TIER[BuildingLod.Tier.LOD1])).is_equal("PROXY")
	assert_bool(BuildingKit.LEVEL_FOR_TIER.has(BuildingLod.Tier.HLOD1)).is_false()
	for m in _kit.count:
		var lods: Dictionary = _record(_kit.ids[m])["lods"]
		assert_int(_kit.near_tris[m]).is_equal(int(lods["LOD1"]["tris"]))
		assert_int(_kit.mid_tris[m]).is_equal(int(lods["PROXY"]["tris"]))
		var near := _kit.tier_mesh(m, BuildingLod.Tier.LOD0) as ArrayMesh
		var mid := _kit.tier_mesh(m, BuildingLod.Tier.LOD1) as ArrayMesh
		assert_int(_triangles(near)).is_equal(int(lods["LOD1"]["tris"]))
		assert_int(_triangles(mid)).is_equal(int(lods["PROXY"]["tris"]))
		# hero LOD0 üçgen sayısı hiçbir kademede yok (LOD0 yalnız kütüphanede)
		assert_int(_triangles(near)).is_not_equal(int(lods["LOD0"]["tris"]))
		assert_object(_kit.tier_mesh(m, BuildingLod.Tier.HLOD1)).is_null()
		assert_object(_kit.level_mesh(m, "LOD0")).is_null()


func test_pivot_is_normalized_to_the_footprint_centre_using_the_table_offset() -> void:
	for m in _kit.count:
		var rec := _record(_kit.ids[m])
		var off: Array = rec["pivot_offset_m"]
		assert_vector(_kit.pivot_offset[m]).is_equal_approx(Vector3(off[0], off[1], off[2]), Vector3.ONE * 0.0001)
		for tier in [BuildingLod.Tier.LOD0, BuildingLod.Tier.LOD1]:
			var level := str(BuildingKit.LEVEL_FOR_TIER[tier])
			var box: Dictionary = rec["lods"][level]["aabb_m"]
			var expected_min := Vector3(box["min"][0], box["min"][1], box["min"][2]) + _kit.pivot_offset[m]
			var expected_max := Vector3(box["max"][0], box["max"][1], box["max"][2]) + _kit.pivot_offset[m]
			var aabb := (_kit.tier_mesh(m, tier) as ArrayMesh).get_aabb()
			assert_vector(aabb.position).is_equal_approx(expected_min, Vector3.ONE * 0.001)
			assert_vector(aabb.end).is_equal_approx(expected_max, Vector3.ONE * 0.001)
			assert_float(aabb.position.y).is_equal_approx(0.0, 0.001)   # taban yerde, Y kaymaz
		# ayak izi = LOD0 sınır kutusu XZ; pivot merkezinde: LOD0 kutusu orijine göre simetrik
		var l0: Dictionary = rec["lods"]["LOD0"]["aabb_m"]
		var cx := (float(l0["min"][0]) + float(l0["max"][0])) * 0.5 + _kit.pivot_offset[m].x
		var cz := (float(l0["min"][2]) + float(l0["max"][2])) * 0.5 + _kit.pivot_offset[m].z
		assert_float(cx).is_equal_approx(0.0, 0.001)
		assert_float(cz).is_equal_approx(0.0, 0.001)
		# yakın kademe mesh'i ayak izi merkezinde (LOD1 kutusu LOD0 kutusundan ancak ince ayrıntı kadar küçük)
		var near := (_kit.tier_mesh(m, BuildingLod.Tier.LOD0) as ArrayMesh).get_aabb()
		assert_float(near.get_center().x).is_equal_approx(0.0, 0.1)
		assert_float(near.get_center().z).is_equal_approx(0.0, 0.1)


func test_tier_meshes_carry_the_modules_own_atlas_material_and_no_override_is_needed() -> void:
	for m in _kit.count:
		var rec := _record(_kit.ids[m])
		var near_mesh := _kit.tier_mesh(m, BuildingLod.Tier.LOD0) as ArrayMesh
		var mid_mesh := _kit.tier_mesh(m, BuildingLod.Tier.LOD1) as ArrayMesh
		var near := near_mesh.surface_get_material(0) as StandardMaterial3D
		var mid := mid_mesh.surface_get_material(0) as StandardMaterial3D
		assert_object(near).is_not_null()
		assert_object(mid).is_not_null()
		assert_str(near.albedo_texture.resource_path).is_equal(str(rec["atlas"]["path"]))
		assert_str(mid.albedo_texture.resource_path).is_equal(str(rec["proxy_atlas"]["path"]))
		assert_int(near.specular_mode).is_equal(BaseMaterial3D.SPECULAR_DISABLED)
		assert_int(near.diffuse_mode).is_equal(BaseMaterial3D.DIFFUSE_LAMBERT)


func test_proxy_templates_are_unindexed_triangles_matching_the_table_triangle_count() -> void:
	for m in _kit.count:
		var tpl: BuildingKit.ProxyTemplate = _kit.proxies[m]
		assert_object(tpl).is_not_null()
		assert_int(tpl.vertices.size() % 3).is_equal(0)
		assert_int(tpl.vertices.size()).is_equal(tpl.normals.size())
		assert_int(tpl.vertices.size()).is_equal(tpl.colors.size())
		assert_int(tpl.triangle_count()).is_equal(_kit.mid_tris[m])


func test_baked_colours_come_from_the_proxy_atlas_srgb_encoded_and_differ_between_modules() -> void:
	var distinct_walls := {}
	for m in _kit.count:
		var tpl: BuildingKit.ProxyTemplate = _kit.proxies[m]
		var tones := {}
		for c in tpl.colors:
			assert_float(c.a).is_equal(1.0)
			for ch in [c.r, c.g, c.b]:
				assert_float(ch).is_between(0.0, 1.0)
			tones[c.to_html()] = true
		assert_int(tones.size()).is_greater(1)   # tek düz renk değil: atlas örneklendi (üçgen başına)
		distinct_walls[_kit.wall_color[m].to_html()] = true
		assert_bool(_kit.roof_color[m] != Color(0.5, 0.5, 0.5, 1.0)).is_true()
	assert_int(distinct_walls.size()).is_greater_equal(15)   # 21 modül, çoğu ayrı duvar tonu (a/b/c stilleri)
	# sRGB kodlu ortalama: tuğla kırmızısı duvar (old_core_b) R > B.
	var brick := _kit.module_index("bld_hero_old_core_b")
	assert_float(_kit.wall_color[brick].r).is_greater(_kit.wall_color[brick].b)


func test_box_template_is_a_ten_triangle_footprint_box_with_baked_colours() -> void:
	for m in _kit.count:
		var box: BuildingKit.ProxyTemplate = _kit.boxes[m]
		assert_int(box.triangle_count()).is_equal(10)   # 4 yan x 2 + üst 2, taban açık
		var lo := Vector3(INF, INF, INF)
		var hi := Vector3(-INF, -INF, -INF)
		for v in box.vertices:
			lo = lo.min(v)
			hi = hi.max(v)
		assert_float(hi.x - lo.x).is_equal_approx(_kit.footprint_w[m], 0.001)
		assert_float(hi.z - lo.z).is_equal_approx(_kit.footprint_d[m], 0.001)
		assert_float(hi.y).is_equal_approx(_kit.height_m[m], 0.001)
		assert_bool(box.colors.has(_kit.wall_color[m])).is_true()
		assert_bool(box.colors.has(_kit.roof_color[m])).is_true()


func test_same_table_bakes_identical_templates_and_colours() -> void:
	var again := BuildingKit.from_game_table(_table, BuildingTestSupport.gate())
	assert_array(Array(again.ids)).is_equal(Array(_kit.ids))
	for m in _kit.count:
		assert_bool(again.wall_color[m] == _kit.wall_color[m]).is_true()
		assert_bool(again.roof_color[m] == _kit.roof_color[m]).is_true()
		var a: BuildingKit.ProxyTemplate = again.proxies[m]
		var b: BuildingKit.ProxyTemplate = _kit.proxies[m]
		assert_array(a.vertices).is_equal(b.vertices)
		assert_array(a.colors).is_equal(b.colors)


func test_table_only_kit_has_no_templates_and_loads_no_mesh() -> void:
	var meta := BuildingTestSupport.meta_kit()
	assert_int(meta.count).is_equal(_kit.count)
	for m in meta.count:
		assert_object(meta.proxies[m]).is_null()
		assert_object(meta.boxes[m]).is_null()
