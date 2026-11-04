extends GdUnitTestSuite
## T-062 B1 / T-057 Karar 5 · hücre lekesi geometrisi: hücre başına birkaç yüz üçgen, dış yüzler, ağaç sayısı B0
## ile tutarlı, yalnız bireysel olmayan kümeler, deterministik.


func _first_chunk_with_trees() -> Vector2i:
	var lay := VegetationViewTestSupport.layout()
	var cc := VegetationViewTestSupport.config().blob_chunk_cells
	var key := lay.cols.peak_cell().y
	return Vector2i(lay.cell_cx(key) / cc, lay.cell_cz(key) / cc)


func _build(key: Vector2i) -> Dictionary:
	return VegetationBlobBuilder.build_chunk(VegetationViewTestSupport.layout(), VegetationViewTestSupport.look_numbers(),
			VegetationViewTestSupport.config(), key.x, key.y)


func test_chunk_mesh_arrays_are_consistent_and_triangles_face_outward() -> void:
	var built := _build(_first_chunk_with_trees())
	var verts: PackedVector3Array = built["vertices"]
	var normals: PackedVector3Array = built["normals"]
	var colors: PackedColorArray = built["colors"]
	var tris := int(built["tris"])
	assert_int(tris).is_greater(0)
	assert_int(verts.size()).is_equal(tris * 3)
	assert_int(normals.size()).is_equal(tris * 3)
	assert_int(colors.size()).is_equal(tris * 3)
	# Godot ön yüzü saat yönüdür: (b-a)x(c-a) normalin TERSİNE bakar; normal birim uzunlukta
	for t in range(0, mini(tris, 400)):
		var a := verts[t * 3]
		var b := verts[t * 3 + 1]
		var c := verts[t * 3 + 2]
		var n := normals[t * 3]
		assert_float(n.length()).is_equal_approx(1.0, 0.001)
		assert_float((b - a).cross(c - a).normalized().dot(n)).is_less(-0.99)


func test_trees_in_the_chunk_match_the_b0_columns_minus_skipped_species() -> void:
	var lay := VegetationViewTestSupport.layout()
	var cfg := VegetationViewConfig.load_default()
	var look := VegetationViewTestSupport.look_numbers()
	var key := _first_chunk_with_trees()
	var built := _build(key)
	var cc := cfg.blob_chunk_cells
	var expect := 0
	var cols := lay.cols
	for i in cols.count:
		var ck := cols.cell_key_of(cols.x[i], cols.z[i])
		var cx := lay.cell_cx(ck) / cc
		var cz := lay.cell_cz(ck) / cc
		if cx == key.x and cz == key.y and look.blob_on[cols.species[i]] == 1:
			expect += 1
	assert_int(expect).is_greater(0)
	assert_int(int(built["trees"])).is_equal(expect)
	# kümeleme gerçekten birleştirir: küme sayısı ağaç sayısından az
	assert_int(int(built["clumps"])).is_less(int(built["trees"]))
	assert_int(int(built["clumps"])).is_greater(0)


func test_hedges_are_skipped_and_triangles_per_cell_stay_in_the_hundreds() -> void:
	var look := VegetationViewTestSupport.look_numbers()
	var hedge := look.index_of_key("hedge")
	assert_int(hedge).is_greater(-1)
	assert_int(look.blob_on[hedge]).is_equal(0)
	var built := _build(_first_chunk_with_trees())
	var lay := VegetationViewTestSupport.layout()
	var cells := 0
	var cc := VegetationViewTestSupport.config().blob_chunk_cells
	var key := _first_chunk_with_trees()
	for cz in range(key.y * cc, (key.y + 1) * cc):
		for cx in range(key.x * cc, (key.x + 1) * cc):
			if lay.index_of_key(cz * lay.cols.cells_w + cx) >= 0:
				cells += 1
	var per_cell := float(built["tris"]) / float(cells)
	assert_float(per_cell).is_less(2500.0)   # en yoğun parça (kent çekirdeği) üst sınırı
	assert_float(per_cell).is_greater(0.0)


func test_average_triangles_per_cell_over_many_chunks_stay_in_the_hundreds() -> void:
	var lay := VegetationViewTestSupport.layout()
	var cfg := VegetationViewConfig.load_default()
	var grid := lay.chunk_grid_size(cfg.blob_chunk_cells)
	var tris := 0
	var cells := 0
	var chunks := 0
	for chz in grid.y:
		for chx in grid.x:
			var box := lay.chunk_box(chx, chz, cfg.blob_chunk_cells)
			if box.size == Vector3.ZERO and box.position == Vector3.ZERO:
				continue
			var built := VegetationBlobBuilder.build_chunk(lay, VegetationViewTestSupport.look_numbers(), cfg, chx, chz)
			tris += int(built["tris"])
			for cz in range(chz * cfg.blob_chunk_cells, (chz + 1) * cfg.blob_chunk_cells):
				for cx in range(chx * cfg.blob_chunk_cells, (chx + 1) * cfg.blob_chunk_cells):
					if cx < lay.cols.cells_w and cz < lay.cols.cells_h and lay.index_of_key(cz * lay.cols.cells_w + cx) >= 0:
						cells += 1
			chunks += 1
			if chunks >= 20:
				break
		if chunks >= 20:
			break
	assert_int(chunks).is_greater(3)
	assert_float(float(tris) / float(cells)).is_less(900.0)   # hücre başına ortalama (hafif ağ: kent yoğun)


func test_chunk_geometry_is_deterministic_and_colors_come_from_species_greens() -> void:
	var key := _first_chunk_with_trees()
	var a := _build(key)
	var b := _build(key)
	assert_array(Array((a["vertices"] as PackedVector3Array).to_byte_array())).is_equal(
			Array((b["vertices"] as PackedVector3Array).to_byte_array()))
	assert_array(Array((a["colors"] as PackedColorArray).to_byte_array())).is_equal(
			Array((b["colors"] as PackedColorArray).to_byte_array()))
	for c in (a["colors"] as PackedColorArray).slice(0, 60):
		assert_bool(c.g >= c.b).is_true()   # nötr yeşil (numbers_only rengi), küçük değer sapması


func test_empty_input_gives_an_empty_chunk() -> void:
	var lay := VegetationViewTestSupport.layout()
	var cfg := VegetationViewConfig.load_default()
	var grid := lay.chunk_grid_size(cfg.blob_chunk_cells)
	# ızgara köşesi (dünyanın boş ucu varsayımı yerine bağımsız arama): ağaçsız bir parça bul
	var found := false
	for chz in grid.y:
		for chx in grid.x:
			var box := lay.chunk_box(chx, chz, cfg.blob_chunk_cells)
			if box.size == Vector3.ZERO and box.position == Vector3.ZERO:
				var built := VegetationBlobBuilder.build_chunk(lay, VegetationViewTestSupport.look_numbers(), cfg, chx, chz)
				assert_int(int(built["tris"])).is_equal(0)
				assert_int((built["vertices"] as PackedVector3Array).size()).is_equal(0)
				found = true
				break
		if found:
			break
	assert_bool(found).is_true()
