extends GdUnitTestSuite
## T-042 sanat düzeltmesi · yeni oyuncu yolunun koridorundaki bitki gizleme: koridor kuralı
## (yarı genişlik + bordür + pay),
## kaba kuvvetle aynı satır kümesi, hücre/leke üreticileri maskeyi uygular, görünüm gizler ve geri almada GERİ GETİRİR,
## sütunlara yazılmaz (determinizm), maske boşken eski davranış bit-eşit.

const P := preload("res://tests/sim/public_works/public_works_support.gd")


func _brute_rows(lay: VegetationLayout, corridors: Array) -> PackedInt32Array:
	var out := PackedInt32Array()
	for i in lay.cols.count:
		var p := Vector2(lay.cols.x[i], lay.cols.z[i])
		for c: Array in corridors:
			var q := Geometry2D.get_closest_point_to_segment(p, c[0], c[1])
			if p.distance_to(q) <= float(c[2]):
				out.append(i)
				break
	return out


func _in_range_config() -> VegetationViewConfig:
	var cfg := VegetationViewConfig.load_default()
	cfg.blob_enabled = false
	cfg.lod0_end_m = 1.0e9
	cfg.lod1_end_m = 2.0e9
	cfg.palm_proxy_end_m = 3.0e9
	return cfg


func test_corridors_come_from_player_edges_only_with_half_width_plus_curb_plus_margin() -> void:
	var net := P.network()
	var style := RoadStyle.load_default()
	assert_array(VegetationCorridor.from_network(net, style)).is_empty()
	var result := RoadDraftCheck.apply(net, PackedVector2Array([Vector2(1180.0, 1100.0), Vector2(1180.0, 1000.0)]),
			&"local", RoadDraftRules.new())
	assert_bool(bool(result["applied"])).is_true()
	var corridors := VegetationCorridor.from_network(net, style)
	assert_int(corridors.size()).is_greater(0)
	for c: Array in corridors:
		var edge_width := 0.0
		for eid: int in net.edges:
			var e: WorldRoadEdge = net.edges[eid]
			if e.layer == WorldRoadEdge.LAYER_DELTA and net.node_pos(e.a) == c[0] and net.node_pos(e.b) == c[1]:
				edge_width = style.width_of(e)
		assert_float(edge_width).is_greater(0.0)
		var margin := float(style.data["vegetation_clear_margin_m"]) + float(style.data["surface"]["curb_m"])
		assert_float(float(c[2])).is_equal_approx(edge_width * 0.5 + margin, 0.0001)
	# geri alma: koridor kalkar
	assert_bool(RoadDraftCheck.undo(net)["ok"]).is_true()
	assert_array(VegetationCorridor.from_network(net, style)).is_empty()


func test_rows_inside_equals_brute_force_and_is_sorted_unique() -> void:
	var lay := VegetationViewTestSupport.layout()
	var corridors := [VegetationViewTestSupport.peak_corridor(12.0)]
	var got := VegetationCorridor.rows_inside(lay, corridors)
	var want := _brute_rows(lay, corridors)
	assert_int(got.size()).is_greater(0)
	assert_array(Array(got)).is_equal(Array(want))
	for n in range(1, got.size()):
		assert_int(got[n]).is_greater(got[n - 1])
	# ikinci koridor kümeyi yalnız büyütür, çift saymaz
	var two := corridors + [VegetationViewTestSupport.peak_corridor(12.0)]
	assert_array(Array(VegetationCorridor.rows_inside(lay, two))).is_equal(Array(want))


func test_shared_layout_stays_unmasked_and_set_hidden_reports_changed_cells_and_reverts() -> void:
	assert_bool(VegetationViewTestSupport.layout().hidden.is_empty()).is_true()
	var lay := VegetationViewTestSupport.fresh_layout()
	var rows := VegetationCorridor.rows_inside(lay, [VegetationViewTestSupport.peak_corridor(12.0)])
	var changed := lay.set_hidden(rows)
	assert_int(lay.hidden_count).is_equal(rows.size())
	assert_int(changed.size()).is_greater(0)
	for k in changed:
		var any := false
		for i in range(lay.cols.cell_start[k], lay.cols.cell_start[k + 1]):
			any = any or lay.is_hidden(i)
		assert_bool(any).is_true()
	# aynı kümeyi tekrar vermek değişiklik değildir
	assert_int(lay.set_hidden(rows).size()).is_equal(0)
	# boş küme hepsini geri getirir ve maske tamamen kalkar
	assert_array(Array(lay.set_hidden(PackedInt32Array()))).is_equal(Array(changed))
	assert_bool(lay.hidden.is_empty()).is_true()
	assert_int(lay.hidden_count).is_equal(0)


func test_cell_builders_skip_hidden_rows_and_unmasked_output_is_unchanged() -> void:
	var lay := VegetationViewTestSupport.fresh_layout()
	var k := lay.index_of_key(lay.cols.peak_cell().y)
	var lo := lay.cols.cell_start[k]
	var hi := lay.cols.cell_start[k + 1]
	var origin := lay.cell_origin(lay.cols.cell_keys[k])
	var before := VegetationCellBuilder.canonical_buffer(lay, lo, hi, origin, 0.12)
	var rows := VegetationCorridor.rows_inside(lay, [VegetationViewTestSupport.peak_corridor(12.0)])
	lay.set_hidden(rows)
	var in_cell := 0
	for i in rows:
		if i >= lo and i < hi:
			in_cell += 1
	assert_int(in_cell).is_greater(0)
	var masked := VegetationCellBuilder.canonical_buffer(lay, lo, hi, origin, 0.12)
	assert_int(masked.size()).is_equal(before.size() - in_cell * VegetationCellBuilder.FLOATS_PER_INSTANCE)
	var part := VegetationCellBuilder.partition(lay, lo, hi, origin, 0.12,
			VegetationViewTestSupport.camera_over_peak(5.0),
			VegetationLod.from_config(VegetationViewTestSupport.config()), false)
	var total := 0
	for n in 3:
		total += int(part["counts"][n])
	assert_int(total).is_less_equal((hi - lo) - in_cell)
	lay.set_hidden(PackedInt32Array())
	assert_array(Array(VegetationCellBuilder.canonical_buffer(lay, lo, hi, origin, 0.12).to_byte_array())) \
			.is_equal(Array(before.to_byte_array()))


func test_blob_builder_counts_fewer_trees_when_rows_are_hidden_and_recovers() -> void:
	var lay := VegetationViewTestSupport.fresh_layout()
	var cfg := VegetationViewTestSupport.config()
	var look := VegetationViewTestSupport.look_numbers()
	var o := lay.cols.peak_cell().y
	var chx := floori(float(lay.cell_cx(o)) / float(cfg.blob_chunk_cells))
	var chz := floori(float(lay.cell_cz(o)) / float(cfg.blob_chunk_cells))
	var full := VegetationBlobBuilder.build_chunk(lay, look, cfg, chx, chz)
	lay.set_hidden(VegetationCorridor.rows_inside(lay, [VegetationViewTestSupport.peak_corridor(40.0)]))
	var masked := VegetationBlobBuilder.build_chunk(lay, look, cfg, chx, chz)
	assert_int(int(masked["trees"])).is_less(int(full["trees"]))
	lay.set_hidden(PackedInt32Array())
	var back := VegetationBlobBuilder.build_chunk(lay, look, cfg, chx, chz)
	assert_int(int(back["trees"])).is_equal(int(full["trees"]))
	assert_array(Array((back["vertices"] as PackedVector3Array).to_byte_array())) \
			.is_equal(Array((full["vertices"] as PackedVector3Array).to_byte_array()))


func test_view_hides_corridor_trees_and_brings_them_back_on_undo() -> void:
	var view: VegetationView = auto_free(VegetationView.new())
	add_child(view)
	view.setup(VegetationViewTestSupport.look_numbers(), _in_range_config())
	var lay := VegetationViewTestSupport.fresh_layout()
	view.set_layout(lay)
	view.track_camera(VegetationViewTestSupport.camera_over_peak(5.0))
	view.settle()
	var all := lay.cols.count
	assert_int(view.visible_instances().x).is_equal(all)
	var changed := view.set_corridors([VegetationViewTestSupport.peak_corridor(12.0)])
	assert_int(changed).is_greater(0)
	view.settle()
	var hidden := lay.hidden_count
	assert_int(hidden).is_greater(0)
	assert_int(view.visible_instances().x).is_equal(all - hidden)
	assert_int(int(view.stats["hidden_instances"])).is_equal(hidden)
	# sütunlar dokunulmadı
	assert_int(lay.cols.count).is_equal(all)
	# geri alma: koridor yok -> hepsi geri gelir
	view.set_corridors([])
	view.settle()
	assert_int(view.visible_instances().x).is_equal(all)
	assert_int(lay.hidden_count).is_equal(0)


func test_view_blob_chunks_refresh_when_the_mask_changes() -> void:
	var cfg := VegetationViewConfig.load_default()
	var view: VegetationView = auto_free(VegetationView.new())
	add_child(view)
	view.setup(VegetationViewTestSupport.look_numbers(), cfg)
	var lay := VegetationViewTestSupport.fresh_layout()
	view.set_layout(lay)
	view.track_camera(VegetationViewTestSupport.camera_over_peak(900.0))
	view.settle()
	var trees_before := 0
	for key in view.blob_keys():
		trees_before += int(view.blob_node(key).get_meta(&"trees", 0))
	assert_int(trees_before).is_greater(0)
	view.set_corridors([VegetationViewTestSupport.peak_corridor(40.0)])
	view.settle()
	var trees_masked := 0
	for key in view.blob_keys():
		trees_masked += int(view.blob_node(key).get_meta(&"trees", 0))
	assert_int(trees_masked).is_less(trees_before)
	view.set_corridors([])
	view.settle()
	var trees_back := 0
	for key in view.blob_keys():
		trees_back += int(view.blob_node(key).get_meta(&"trees", 0))
	assert_int(trees_back).is_equal(trees_before)
