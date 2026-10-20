extends GdUnitTestSuite
## T-001 ölçüt 4 · TerrainView kurulumu (düğümler, chunk yerleşimi). Mesh VERİSİ
## tests/view/terrain_mesh_builder_test.gd'de; burada yalnız düğüm ağacı sayıları
## sınanır (dummy renderer'da AABB/çizim doğrulanamaz → capture ile bakılır).

const CHUNK_CELLS := 32

var _world: WorldData


func before() -> void:
	_world = WorldTestSupport.coarse(WorldTestSupport.control())


func _make_view(threaded: bool) -> TerrainView:
	var view: TerrainView = auto_free(TerrainView.new())
	view.chunk_cells = CHUNK_CELLS
	view.use_threads = threaded
	add_child(view)
	view.build(_world)
	return view


func test_view_creates_one_land_node_per_land_chunk_and_water_nodes_only_where_water_exists() -> void:
	var view := _make_view(false)
	var counts := view.chunk_counts()
	assert_int(counts.x * counts.y).is_equal(16)
	assert_int(view.land_nodes().size()).is_between(1, counts.x * counts.y)
	assert_int(view.water_nodes().size()).is_between(1, counts.x * counts.y)
	assert_int(view.get_child_count()).is_equal(view.land_nodes().size() + view.water_nodes().size())
	assert_int(int(view.stats["land_triangles"])).is_greater(1000)
	assert_int(int(view.stats["water_triangles"])).is_greater(100)


func test_chunk_nodes_sit_at_their_world_origin_on_a_shared_material() -> void:
	var view := _make_view(false)
	var material: Material = view.land_nodes()[0].mesh.surface_get_material(0)
	assert_object(material).is_not_null()
	for node in view.land_nodes():
		assert_object(node.mesh.surface_get_material(0)).is_same(material)
		assert_int(node.mesh.get_surface_count()).is_equal(1)
		# Konum, chunk ızgarasına oturur (hücre köşesi katı).
		var rel := (Vector2(node.position.x, node.position.z) - _world.origin) / (CHUNK_CELLS * _world.cell_size)
		assert_float(rel.x - roundf(rel.x)).is_equal_approx(0.0, 0.0001)
		assert_float(rel.y - roundf(rel.y)).is_equal_approx(0.0, 0.0001)
		assert_float(node.position.y).is_equal(0.0)


func test_threaded_and_sequential_builds_produce_identical_triangle_counts() -> void:
	var seq := _make_view(false)
	var par := _make_view(true)
	assert_int(int(par.stats["land_triangles"])).is_equal(int(seq.stats["land_triangles"]))
	assert_int(int(par.stats["water_triangles"])).is_equal(int(seq.stats["water_triangles"]))
	assert_int(par.land_nodes().size()).is_equal(seq.land_nodes().size())


func test_surface_height_follows_world_and_never_dips_below_the_sea() -> void:
	var view := _make_view(false)
	var water_idx := _world.land_mask.find(0)
	var wp := _world.cell_to_world(water_idx % _world.width, water_idx / _world.width)
	assert_float(view.surface_height_at(wp.x, wp.y)).is_equal(_world.sea_level)
	var land_idx := _world.land_mask.find(1)
	var lp := _world.cell_to_world(land_idx % _world.width, land_idx / _world.width)
	assert_float(view.surface_height_at(lp.x, lp.y)).is_greater(_world.sea_level)
