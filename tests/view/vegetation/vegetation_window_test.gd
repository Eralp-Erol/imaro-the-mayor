extends GdUnitTestSuite
## T-062 B1 · kamera pencere mantığı: yalnız kamera çevresindeki hücreler açılır/kapanır; bağımsız kaba kuvvet
## karşılaştırması; histerezis; leke parçaları.


func _lod() -> VegetationLod:
	return VegetationLod.from_config(VegetationViewTestSupport.config())


## Bağımsız tanım: hücre kutusuna 3B uzaklık < eşik (tüm hücreler taranır, üreteçten AYRI).
func _brute_needed(lay: VegetationLayout, cam: Vector3, margin: float) -> PackedInt32Array:
	var lod := _lod()
	var out := PackedInt32Array()
	for k in lay.cell_count():
		var b := lay.cell_box(k)
		var d := VegetationLod.box_distance_range(cam, b.position, b.end).x
		var limit := lod.lod1_end_m + margin
		if lay.cell_proxy_count[k] > 0:
			limit = lod.palm_proxy_end_m + margin
		if d < limit:
			out.append(k)
	return out


func test_cells_to_open_equals_the_brute_force_set_and_is_sorted() -> void:
	var lay := VegetationViewTestSupport.layout()
	var cfg := VegetationViewConfig.load_default()
	for cam in [VegetationViewTestSupport.camera_over_peak(30.0), VegetationViewTestSupport.camera_over_peak(300.0)]:
		var got := VegetationWindow.cells_to_open(lay, _lod(), cam, cfg.load_margin_m, {})
		var want := _brute_needed(lay, cam, cfg.load_margin_m)
		assert_array(Array(got)).is_equal(Array(want))
		assert_int(got.size()).is_greater(0)
		# dünyanın yalnız küçük bir kısmı (6366 hücrenin hepsi değil)
		assert_int(got.size()).is_less(lay.cell_count())


func test_moving_the_camera_opens_and_closes_only_the_expected_cells() -> void:
	var lay := VegetationViewTestSupport.layout()
	var cfg := VegetationViewConfig.load_default()
	var lod := _lod()
	var a := VegetationViewTestSupport.camera_over_peak(30.0)
	var b := a + Vector3(1500.0, 0.0, 0.0)
	var active: Dictionary = {}
	for k in VegetationWindow.cells_to_open(lay, lod, a, cfg.load_margin_m, active):
		active[k] = true
	var before := active.keys().duplicate()
	var to_close := VegetationWindow.cells_to_close(lay, lod, b, cfg.unload_margin_m, active)
	var to_open := VegetationWindow.cells_to_open(lay, lod, b, cfg.load_margin_m, active)
	# kapananlar açık olanların alt kümesi ve yeni konumda GERÇEKTEN gereksiz
	for k in to_close:
		assert_bool(active.has(k)).is_true()
		assert_bool(VegetationWindow.cell_needed(lay, lod, k, b, cfg.unload_margin_m)).is_false()
	# açılanlar henüz açık değil ve yeni konumda gerekli
	for k in to_open:
		assert_bool(active.has(k)).is_false()
		assert_bool(VegetationWindow.cell_needed(lay, lod, k, b, cfg.load_margin_m)).is_true()
	# kalanlar yeni konumda hâlâ gerekliler (kapanmayan = açık kalır)
	for k in before:
		if not to_close.has(k):
			assert_bool(VegetationWindow.cell_needed(lay, lod, k, b, cfg.unload_margin_m)).is_true()
	assert_int(to_close.size()).is_greater(0)
	assert_int(to_open.size()).is_greater(0)


func test_hysteresis_a_cell_just_inside_the_unload_margin_stays_open() -> void:
	var lay := VegetationViewTestSupport.layout()
	var cfg := VegetationViewConfig.load_default()
	var lod := _lod()
	var k := lay.index_of_key(lay.cols.peak_cell().y)
	var box := lay.cell_box(k)
	var lim := lod.lod1_end_m
	if lay.cell_proxy_count[k] > 0:
		lim = lod.palm_proxy_end_m
	# kutunun doğusunda, en yakın nokta tam (lim + load_margin + 5) m uzakta: açılmaz ama açıksa kapanmaz
	var cam := Vector3(box.end.x + lim + cfg.load_margin_m + 5.0, box.position.y, box.position.z + 10.0)
	assert_bool(VegetationWindow.cell_needed(lay, lod, k, cam, cfg.load_margin_m)).is_false()
	assert_bool(VegetationWindow.cell_needed(lay, lod, k, cam, cfg.unload_margin_m)).is_true()
	assert_int(VegetationWindow.cells_to_open(lay, lod, cam, cfg.load_margin_m, {}).find(k)).is_equal(-1)
	assert_int(VegetationWindow.cells_to_close(lay, lod, cam, cfg.unload_margin_m, {k: true}).size()).is_equal(0)


func test_blob_chunk_window_covers_the_ring_and_skips_chunks_entirely_inside_the_lod1_radius() -> void:
	var lay := VegetationViewTestSupport.layout()
	var cfg := VegetationViewConfig.load_default()
	var cam := VegetationViewTestSupport.camera_over_peak(30.0)
	var chunks := VegetationWindow.chunks_to_open(lay, cam, cfg.lod1_end_m, cfg.blob_end_m, cfg.blob_load_margin_m,
			cfg.blob_chunk_cells, {})
	assert_int(chunks.size()).is_greater(0)
	var grid := lay.chunk_grid_size(cfg.blob_chunk_cells)
	var brute := 0
	for chz in grid.y:
		for chx in grid.x:
			if VegetationWindow.chunk_needed(lay, chx, chz, cam, cfg.lod1_end_m, cfg.blob_end_m, cfg.blob_load_margin_m,
					cfg.blob_chunk_cells):
				brute += 1
				assert_bool(chunks.has(Vector2i(chx, chz))).is_true()
	assert_int(chunks.size()).is_equal(brute)
	# çok uzak kamera: hiç parça yok (leke 2,2 km ötesinde söner)
	var far := cam + Vector3(30000.0, 0.0, 0.0)
	assert_int(VegetationWindow.chunks_to_open(lay, far, cfg.lod1_end_m, cfg.blob_end_m, cfg.blob_load_margin_m,
			cfg.blob_chunk_cells, {}).size()).is_equal(0)
