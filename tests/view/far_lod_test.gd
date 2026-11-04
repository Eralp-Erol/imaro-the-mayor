extends GdUnitTestSuite
## T-049 perf: FarLod (uzak mod kararı, birleştirme) + TerrainView/RoadView birleşik uzak mesh. Aynı veri, farklı
## temsil: üçgen sayıları ve köşe kutuları chunk'lı çizimle AYNI olmalı; geçiş yalnız görünürlüğü çevirir.

const CHUNK_CELLS := 32


func test_next_state_has_hysteresis_between_exit_and_enter() -> void:
	assert_bool(FarLod.next_state(FarLod.ENTER_M - 1.0, false)).is_false()
	assert_bool(FarLod.next_state(FarLod.ENTER_M, false)).is_true()
	# Uzak modda iken EXIT ile ENTER arası: uzak kalır; EXIT altında çıkar.
	assert_bool(FarLod.next_state((FarLod.ENTER_M + FarLod.EXIT_M) * 0.5, true)).is_true()
	assert_bool(FarLod.next_state(FarLod.EXIT_M - 1.0, true)).is_false()
	assert_bool(FarLod.next_state((FarLod.ENTER_M + FarLod.EXIT_M) * 0.5, false)).is_false()
	assert_float(FarLod.EXIT_M).is_less(FarLod.ENTER_M)


func test_merge_parts_offsets_vertices_and_rebases_indices() -> void:
	var a := {"vertices": PackedVector3Array([Vector3(0, 1, 0), Vector3(1, 1, 0), Vector3(0, 1, 1)]),
		"normals": PackedVector3Array([Vector3.UP, Vector3.UP, Vector3.UP]),
		"colors": PackedColorArray([Color.RED, Color.RED, Color.RED]),
		"indices": PackedInt32Array([0, 1, 2])}
	var b := a.duplicate(true)
	var merged := FarLod.merge_parts([a, b], [Vector3(100, 0, 0), Vector3(0, 5, 200)])
	var verts: PackedVector3Array = merged["vertices"]
	assert_int(verts.size()).is_equal(6)
	assert_vector(verts[0]).is_equal(Vector3(100, 1, 0))
	assert_vector(verts[4]).is_equal(Vector3(1, 6, 200))
	assert_array(merged["indices"]).is_equal(PackedInt32Array([0, 1, 2, 3, 4, 5]))
	assert_int((merged["normals"] as PackedVector3Array).size()).is_equal(6)
	assert_bool(merged.has("uvs")).is_false()


func test_merge_parts_skips_empty_parts_and_keeps_uvs() -> void:
	var empty := {"vertices": PackedVector3Array(), "normals": PackedVector3Array(), "colors": PackedColorArray()}
	var full := {"vertices": PackedVector3Array([Vector3.ZERO, Vector3.RIGHT, Vector3.BACK]),
		"normals": PackedVector3Array([Vector3.UP, Vector3.UP, Vector3.UP]),
		"colors": PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE]),
		"uvs": PackedVector2Array([Vector2.ZERO, Vector2.RIGHT, Vector2.DOWN]),
		"uv2s": PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])}
	var merged := FarLod.merge_parts([empty, full], [Vector3(9, 9, 9), Vector3(10, 0, 0)])
	assert_int((merged["vertices"] as PackedVector3Array).size()).is_equal(3)
	assert_int((merged["uvs"] as PackedVector2Array).size()).is_equal(3)
	assert_vector((merged["vertices"] as PackedVector3Array)[1]).is_equal(Vector3(11, 0, 0))


func test_terrain_far_mesh_matches_chunks_and_toggles_visibility() -> void:
	var world := WorldTestSupport.coarse(WorldTestSupport.control())
	var view: TerrainView = auto_free(TerrainView.new())
	view.chunk_cells = CHUNK_CELLS
	view.use_threads = false
	view.build_far_mesh = true
	add_child(view)
	view.build(world)
	var far := view.far_nodes()
	assert_int(far.size()).is_equal(2)
	var far_land_tris := 0
	var far_water_tris := 0
	for node in far:
		var arrays := node.mesh.surface_get_arrays(0)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var idx: Variant = arrays[Mesh.ARRAY_INDEX]
		var tris := (idx as PackedInt32Array).size() / 3 if idx != null else verts.size() / 3
		if node.name == &"FarWater":
			far_water_tris = tris
		else:
			far_land_tris = tris
		assert_bool(node.visible).is_false()
	assert_int(far_land_tris).is_equal(int(view.stats["land_triangles"]))
	assert_int(far_water_tris).is_equal(int(view.stats["water_triangles"]))
	# Birleşik meshin dünya kutusu, chunk'ların dünya kutularının birleşimidir (kaydırma doğru).
	var chunks_box := AABB()
	var first := true
	for node in view.land_nodes():
		var box := node.mesh.get_aabb()
		box.position += node.position
		chunks_box = box if first else chunks_box.merge(box)
		first = false
	var far_land: MeshInstance3D = far[0] if far[0].name == &"FarLand" else far[1]
	assert_vector(far_land.mesh.get_aabb().position).is_equal_approx(chunks_box.position, Vector3(0.01, 0.01, 0.01))
	assert_vector(far_land.mesh.get_aabb().size).is_equal_approx(chunks_box.size, Vector3(0.01, 0.01, 0.01))
	view.set_far_mode(true)
	assert_bool(view.far_mode()).is_true()
	for node in view.land_nodes():
		assert_bool(node.visible).is_false()
	for node in far:
		assert_bool(node.visible).is_true()
	view.set_far_mode(false)
	for node in view.land_nodes():
		assert_bool(node.visible).is_true()
	for node in far:
		assert_bool(node.visible).is_false()


func test_terrain_without_far_mesh_has_no_extra_nodes_and_far_mode_is_inert() -> void:
	var world := WorldTestSupport.coarse(WorldTestSupport.control())
	var view: TerrainView = auto_free(TerrainView.new())
	view.chunk_cells = CHUNK_CELLS
	view.use_threads = false
	add_child(view)
	view.build(world)
	assert_int(view.far_nodes().size()).is_equal(0)
	view.set_far_mode(true)
	assert_bool(view.far_mode()).is_false()
	for node in view.land_nodes():
		assert_bool(node.visible).is_true()


func test_road_far_mesh_equals_metro_triangles_and_follows_rebuild() -> void:
	var world := NetworkTestSupport.flat_world()
	var net := NetworkTestSupport.empty_network(world)
	var style := RoadStyle.load_default()
	var a := net.add_node_raw(Vector2(100, 100))
	var b := net.add_node_raw(Vector2(2600, 100))
	net.add_edge_raw(a, b, &"arterial", 20.0)
	var view: RoadView = auto_free(RoadView.new())
	view.build_far_mesh = true
	add_child(view)
	view.build(net, style)
	assert_object(view.far_node()).is_not_null()
	assert_bool(view.far_node().visible).is_false()
	assert_int(int(view.stats["far_triangles"])).is_equal(int(view.stats["metro_triangles"]))
	assert_int(int(view.stats["far_triangles"])).is_greater(0)
	view.set_far_mode(true)
	assert_bool(view.far_node().visible).is_true()
	for chunk: Node3D in view.get_children():
		if chunk != view.far_node():
			assert_bool(chunk.visible).is_false()
	# Yeni kenar + yalnız etkilenen chunk'ların yeniden kurulumu: uzak mesh güncel kalır, mod korunur.
	var c := net.add_node_raw(Vector2(100, 900))
	var d := net.add_node_raw(Vector2(2600, 900))
	net.add_edge_raw(c, d, &"local", 10.0)
	var keys: Array[Vector2i] = []
	for key in RoadChunkPlan.build(net, style).keys():
		keys.append(key)
	view.rebuild_chunks(keys)
	assert_int(int(view.stats["far_triangles"])).is_equal(int(view.stats["metro_triangles"]))
	assert_bool(view.far_mode()).is_true()
	assert_bool(view.far_node().visible).is_true()
	for chunk: Node3D in view.get_children():
		if chunk != view.far_node():
			assert_bool(chunk.visible).is_false()


func test_road_without_far_mesh_keeps_only_chunk_children() -> void:
	var world := NetworkTestSupport.flat_world()
	var net := NetworkTestSupport.empty_network(world)
	net.add_edge_raw(net.add_node_raw(Vector2(100, 100)), net.add_node_raw(Vector2(500, 100)), &"local", 10.0)
	var view: RoadView = auto_free(RoadView.new())
	add_child(view)
	view.build(net, RoadStyle.load_default())
	assert_object(view.far_node()).is_null()
	view.set_far_mode(true)
	assert_bool(view.far_mode()).is_false()
