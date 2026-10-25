extends GdUnitTestSuite
## T-048: sentetik ağ; coğrafya/sanat kararı veya sim fixture'ı yok.

var _world: WorldData
var _net: WorldNetwork
var _style: RoadStyle


func before_test() -> void:
	_world = NetworkTestSupport.flat_world()
	_net = NetworkTestSupport.empty_network(_world)
	_style = RoadStyle.load_default()


func _edge(a: Vector2, b: Vector2, cls: StringName = &"local", width: float = 10.0) -> int:
	return _net.add_edge_raw(_net.add_node_raw(a), _net.add_node_raw(b), cls, width)


func _view() -> RoadView:
	var view: RoadView = auto_free(RoadView.new())
	add_child(view)
	view.build(_net, _style)
	return view


func _data(key: Vector2i, metro: bool = false) -> Dictionary:
	return RoadMeshBuilder.build(_net, _style, RoadChunkPlan.build(_net, _style), key, metro)


func _hash(data: Dictionary) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update((data["vertices"] as PackedVector3Array).to_byte_array())
	context.update((data["normals"] as PackedVector3Array).to_byte_array())
	context.update((data["colors"] as PackedColorArray).to_byte_array())
	return context.finish().hex_encode()


func test_only_road_modes_produce_strips_including_closed_and_delta_edges() -> void:
	_edge(Vector2(100, 100), Vector2(500, 100), &"arterial", 20.0)
	var closed := _edge(Vector2(100, 200), Vector2(500, 200), &"collector", 14.0)
	(_net.edges[closed] as WorldRoadEdge).open = false
	(_net.edges[closed] as WorldRoadEdge).layer = WorldRoadEdge.LAYER_DELTA
	_edge(Vector2(100, 300), Vector2(500, 300), &"local")
	_edge(Vector2(100, 400), Vector2(500, 400), &"field", 6.0)
	_edge(Vector2(100, 500), Vector2(500, 500), &"rail", 12.0)
	_edge(Vector2(100, 600), Vector2(500, 600), &"ferry", 0.0)
	assert_int(int(_data(Vector2i.ZERO)["strips"])).is_equal(4)
	assert_int(int(_view().stats["strips"])).is_equal(4)


func test_every_corner_and_triangle_center_sits_on_sloping_terrain() -> void:
	for z in _world.height:
		for x in _world.width:
			_world.heights[z * _world.width + x] = 10.0 + x * 2.0 + z * 3.0
	_edge(Vector2(170, 120), Vector2(780, 680), &"arterial", 20.0)
	for metro in [false, true]:
		var vertices: PackedVector3Array = _data(Vector2i.ZERO, metro)["vertices"]
		assert_int(vertices.size()).is_greater(0)
		for p in vertices:
			assert_float(p.y - _world.height_at(p.x, p.z)).is_equal_approx(
					float(_style.data["surface_offset_m"]), 0.0001)
		for i in range(0, vertices.size(), 3):
			var center := (vertices[i] + vertices[i + 1] + vertices[i + 2]) / 3.0
			assert_float(center.y - _world.height_at(center.x, center.z)).is_equal_approx(
					float(_style.data["surface_offset_m"]), 0.0001)


func test_nonplanar_cell_uses_visible_terrain_diagonal_instead_of_bilinear_surface() -> void:
	# Tek hücre: main diagonal h00=h11, görünür yüzey merkezde 10; bilineer merkez 15.
	_world = NetworkTestSupport.flat_world(100.0)
	_world.heights = PackedFloat32Array([10, 20, 20, 10])
	_net = NetworkTestSupport.empty_network(_world)
	_edge(Vector2(5, 50), Vector2(95, 50))
	var vertices: PackedVector3Array = _data(Vector2i.ZERO)["vertices"]
	for i in range(0, vertices.size(), 3):
		var center := (vertices[i] + vertices[i + 1] + vertices[i + 2]) / 3.0
		var expected := 10.0 + absf(center.x - center.z) * 0.1
		assert_float(center.y - expected).is_equal_approx(float(_style.data["surface_offset_m"]), 0.0001)


func test_same_input_and_insertion_order_independent_mesh_hash() -> void:
	_edge(Vector2(100, 200), Vector2(800, 200))
	_edge(Vector2(100, 400), Vector2(800, 400), &"collector", 14.0)
	var first := _hash(_data(Vector2i.ZERO))
	var reordered := {}
	var ids := _net.edges.keys()
	ids.reverse()
	for id: int in ids:
		reordered[id] = _net.edges[id]
	_net.edges = reordered
	assert_str(_hash(_data(Vector2i.ZERO))).is_equal(first)


func test_class_width_and_color_come_from_data_and_preserve_network_corridor() -> void:
	for cls: StringName in WorldRoadEdge.ROAD_CLASSES:
		_net = NetworkTestSupport.empty_network(_world)
		var eid := _edge(Vector2(100, 200), Vector2(800, 200), cls, 18.0)
		var edge: WorldRoadEdge = _net.edges[eid]
		assert_float(_style.width_of(edge)).is_equal(18.0)
		_style.data["classes"][String(cls)]["width_scale"] = 1.25
		_style.data["classes"][String(cls)]["color"] = "#cc2244"
		var data := _data(Vector2i.ZERO)
		var min_z := INF
		var max_z := -INF
		for p: Vector3 in data["vertices"]:
			min_z = minf(min_z, p.z)
			max_z = maxf(max_z, p.z)
		assert_float(max_z - min_z).is_equal_approx(22.5, 0.0001)
		assert_bool((data["colors"] as PackedColorArray)[0].is_equal_approx(Color.html("#cc2244"))).is_true()


func test_metro_is_thinner_and_has_fewer_triangles_with_engine_distance_lod() -> void:
	_edge(Vector2(100, 200), Vector2(800, 200))
	var near: PackedVector3Array = _data(Vector2i.ZERO)["vertices"]
	var metro: PackedVector3Array = _data(Vector2i.ZERO, true)["vertices"]
	assert_int(metro.size()).is_less(near.size())
	var view := _view()
	var chunk := view.chunk_node(Vector2i.ZERO)
	var near_node: MeshInstance3D = chunk.get_node("Near")
	var metro_node: MeshInstance3D = chunk.get_node("Metro")
	assert_float(near_node.visibility_range_end).is_equal(float(_style.data["metro_begin_m"]))
	assert_float(metro_node.visibility_range_begin).is_equal(near_node.visibility_range_end)
	assert_bool(near_node.custom_aabb == metro_node.custom_aabb).is_true()
	assert_bool(view.is_processing()).is_false()
	assert_bool(view.is_physics_processing()).is_false()
	var min_z := INF
	var max_z := -INF
	for p in metro:
		min_z = minf(min_z, p.z)
		max_z = maxf(max_z, p.z)
	assert_float(max_z - min_z).is_equal_approx(10.0 * float(_style.data["metro_width_scale"]), 0.0001)


func test_rebuild_preserves_unrelated_chunk_node_and_mesh_resource() -> void:
	var changed := _edge(Vector2(100, 200), Vector2(800, 200))
	_edge(Vector2(2100, 200), Vector2(2800, 200))
	var view := _view()
	var untouched := view.chunk_node(Vector2i(2, 0))
	var mesh: Mesh = (untouched.get_node("Near") as MeshInstance3D).mesh
	var previous := view.chunk_node(Vector2i.ZERO).get_instance_id()
	(_net.edges[changed] as WorldRoadEdge).width = 16.0
	view.rebuild_chunks([Vector2i.ZERO])
	assert_object(view.chunk_node(Vector2i(2, 0))).is_same(untouched)
	assert_object((untouched.get_node("Near") as MeshInstance3D).mesh).is_same(mesh)
	assert_bool(view.chunk_node(Vector2i.ZERO).get_instance_id() != previous).is_true()
	assert_int(int(view.stats["last_rebuilt"])).is_equal(1)


func test_cross_chunk_edge_is_clipped_and_removal_clears_old_chunks() -> void:
	var eid := _edge(Vector2(800, 200), Vector2(2200, 200))
	var view := _view()
	var keys: Array[Vector2i] = view.plan().edge_keys[eid]
	assert_int(keys.size()).is_equal(3)
	for key in keys:
		var vertices: PackedVector3Array = _data(key)["vertices"]
		for p in vertices:
			assert_float(p.x).is_between(-0.001, 1000.001)
	_net.remove_edge_raw(eid)
	view.rebuild_chunks(keys)
	assert_int(view.get_child_count()).is_equal(0)
	assert_int(int(view.stats["strips"])).is_equal(0)


func test_shared_junction_produces_grounded_fill_without_changing_network() -> void:
	var center := _net.add_node_raw(Vector2(500, 500))
	for end in [Vector2(100, 500), Vector2(900, 500), Vector2(500, 900)]:
		_net.add_edge_raw(center, _net.add_node_raw(end), &"local", 10.0)
	var before := _net.graph_hash()
	var data := _data(Vector2i.ZERO)
	assert_int(int(data["strips"])).is_equal(3)
	assert_int(int(data["junctions"])).is_equal(1)
	_view()
	assert_str(_net.graph_hash()).is_equal(before)
	for normal: Vector3 in data["normals"]:
		assert_float(normal.y).is_greater(0.0)


func test_empty_network_and_unknown_chunk_are_safe() -> void:
	var view := _view()
	assert_int(view.get_child_count()).is_equal(0)
	view.rebuild_chunks([Vector2i(50, -1)])
	assert_int(view.get_child_count()).is_equal(0)
	assert_int((_data(Vector2i.ZERO)["vertices"] as PackedVector3Array).size()).is_equal(0)


func test_acute_junction_has_a_single_surface_in_overlap_region() -> void:
	var center := _net.add_node_raw(Vector2(500, 500))
	for end in [Vector2(100, 500), Vector2(900, 500), Vector2(900, 600)]:
		_net.add_edge_raw(center, _net.add_node_raw(end), &"local", 10.0)
	var vertices: PackedVector3Array = _data(Vector2i.ZERO)["vertices"]
	# Kaydırılmış örnekler üçgen kenarlarının üzerinde değildir.
	for x in range(501, 545, 2):
		for z in range(495, 515, 2):
			var probe := Vector2(x + 0.173, z + 0.319)
			var hits := 0
			for i in range(0, vertices.size(), 3):
				var triangle := PackedVector2Array()
				for j in 3:
					triangle.append(Vector2(vertices[i + j].x, vertices[i + j].z))
				if Geometry2D.is_point_in_polygon(probe, triangle):
					hits += 1
			assert_int(hits).is_between(0, 1)
