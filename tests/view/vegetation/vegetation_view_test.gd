extends GdUnitTestSuite
## T-062 B1 · VegetationView düğüm yapısı (başsız): hücre->örnek bire bir, kamera hücre değişiminde yalnız beklenen
## hücreler, kademe sayıları kaba kuvvetle, MultiMesh bayt determinizmi, yalnız onaylı kimlik, gölge ayarı, leke
## parçaları.
## (Dummy renderer: çizim/AABB doğrulanmaz; görüntü doğrulaması capture ile.)


func _view(look: VegetationLook = null, cfg: VegetationViewConfig = null) -> VegetationView:
	var view: VegetationView = auto_free(VegetationView.new())
	add_child(view)
	view.setup(look if look != null else VegetationViewTestSupport.look_numbers(),
			cfg if cfg != null else VegetationViewTestSupport.config())
	view.set_layout(VegetationViewTestSupport.layout())
	return view


func _no_blob_config() -> VegetationViewConfig:
	var cfg := VegetationViewConfig.load_default()
	cfg.blob_enabled = false
	return cfg


## Kaba kuvvet: tüm sütunlar, kamera mesafesi, kademe sayıları (Vector3i LOD0/LOD1/PROXY).
func _brute_tiers(cam: Vector3) -> Vector3i:
	var lay := VegetationViewTestSupport.layout()
	var lod := VegetationLod.from_config(VegetationViewTestSupport.config())
	var has_proxy := VegetationViewTestSupport.has_proxy()
	var n := [0, 0, 0]
	var cols := lay.cols
	for i in cols.count:
		var d := Vector3(cols.x[i], lay.y[i], cols.z[i]).distance_to(cam)
		var t := lod.tier_for(d, has_proxy[cols.species[i]] == 1)
		if t != VegetationLod.Tier.NONE:
			n[t] += 1
	return Vector3i(n[0], n[1], n[2])


func _buffers(view: VegetationView) -> Dictionary:
	var out: Dictionary = {}
	for key in view.open_cell_keys():
		var cell := view.cell_node(key)
		for child in cell.get_children():
			var mmi := child as MultiMeshInstance3D
			if mmi != null and mmi.visible:
				out["%d/%s" % [key, mmi.name]] = mmi.multimesh.buffer.to_byte_array()
	return out


func test_visible_instances_per_tier_match_a_brute_force_count() -> void:
	var view := _view(null, _no_blob_config())
	for cam in [VegetationViewTestSupport.camera_over_peak(5.0), VegetationViewTestSupport.camera_over_peak(250.0),
			VegetationViewTestSupport.camera_over_peak(1200.0)]:
		view.track_camera(cam)
		view.settle()
		var got := view.visible_instances()
		var want := _brute_tiers(cam)
		assert_int(got.x).is_equal(want.x)
		assert_int(got.y).is_equal(want.y)
		assert_int(got.z).is_equal(want.z)
	# ilk kamera yakın: anlamlı (sıfır eşitliği değil)
	view.track_camera(VegetationViewTestSupport.camera_over_peak(5.0))
	view.settle()
	assert_int(view.visible_instances().y).is_greater(0)


func test_cells_map_one_to_one_to_the_b0_columns_when_everything_is_in_range() -> void:
	var cfg := _no_blob_config()
	cfg.lod0_end_m = 1.0e9   # her şey LOD0 menzilinde: tüm hücreler açık, tüm örnekler görünür
	cfg.lod1_end_m = 2.0e9
	cfg.palm_proxy_end_m = 3.0e9
	var view := _view(null, cfg)
	var lay := VegetationViewTestSupport.layout()
	view.track_camera(VegetationViewTestSupport.camera_over_peak(5.0))
	view.settle()
	assert_int(view.open_cell_keys().size()).is_equal(lay.cell_count())
	assert_int(view.visible_instances().x).is_equal(lay.cols.count)
	# hücre başına, tür başına örnek sayısı B0 sütunlarıyla aynı
	var per_species := PackedInt32Array()
	per_species.resize(VegetationViewTestSupport.species().size())
	for k in lay.cell_count():
		var cell := view.cell_node(lay.cols.cell_keys[k])
		assert_object(cell).is_not_null()
		var in_cell := 0
		for child in cell.get_children():
			var mmi := child as MultiMeshInstance3D
			if mmi.visible:
				in_cell += mmi.multimesh.instance_count
				per_species[int(VegetationViewTestSupport.look_numbers().ids.find(str(mmi.get_meta(&"species_id"))))] \
						+= mmi.multimesh.instance_count
		assert_int(in_cell).is_equal(lay.cols.cell_start[k + 1] - lay.cols.cell_start[k])
	assert_array(Array(per_species)).is_equal(Array(lay.cols.species_counts()))


func test_camera_move_opens_and_closes_only_expected_cells_and_keeps_the_rest() -> void:
	var view := _view(null, _no_blob_config())
	var cfg := VegetationViewTestSupport.config()
	var lay := VegetationViewTestSupport.layout()
	var lod := VegetationLod.from_config(cfg)
	var a := VegetationViewTestSupport.camera_over_peak(30.0)
	view.track_camera(a)
	view.settle()
	var open_a := view.open_cell_keys()
	assert_int(open_a.size()).is_greater(0)
	var nodes_a: Dictionary = {}
	for key in open_a:
		nodes_a[key] = view.cell_node(key)
	var opened: Array = []
	var closed: Array = []
	view.window_changed.connect(func(o: PackedInt32Array, c: PackedInt32Array) -> void:
		opened.append_array(Array(o))
		closed.append_array(Array(c)))
	# 5 m: adım eşiği (10 m) altında: hiçbir şey değişmez
	view.track_camera(a + Vector3(5.0, 0.0, 0.0))
	view.settle()
	assert_int(opened.size() + closed.size()).is_equal(0)
	# 600 m yana: pencere kayar
	var b := a + Vector3(600.0, 0.0, 0.0)
	view.track_camera(b)
	view.settle()
	var open_b := view.open_cell_keys()
	for k: int in closed:
		assert_bool(open_b.has(lay.cols.cell_keys[k])).is_false()
		assert_bool(VegetationWindow.cell_needed(lay, lod, k, b, cfg.unload_margin_m)).is_false()
	for k: int in opened:
		assert_bool(open_a.has(lay.cols.cell_keys[k])).is_false()
		assert_bool(open_b.has(lay.cols.cell_keys[k])).is_true()
	assert_int(opened.size()).is_greater(0)
	assert_int(closed.size()).is_greater(0)
	# kalan hücrelerin düğümü AYNI nesne (yeniden kurulmadı)
	var kept := 0
	for key in open_a:
		if open_b.has(key):
			assert_bool(view.cell_node(key) == nodes_a[key]).is_true()
			kept += 1
	assert_int(kept).is_greater(0)
	# açık küme = kaba kuvvet gereksinim kümesinin üst kümesi (açma payı) ve kapama payı içinde
	for k in VegetationWindow.cells_to_open(lay, lod, b, cfg.load_margin_m, {}):
		assert_bool(open_b.has(lay.cols.cell_keys[k])).is_true()


func test_same_input_gives_byte_equal_multimesh_buffers() -> void:
	var cam := VegetationViewTestSupport.camera_over_peak(40.0)
	var v1 := _view(null, _no_blob_config())
	v1.track_camera(cam)
	v1.settle()
	var v2 := _view(null, _no_blob_config())
	v2.track_camera(cam)
	v2.settle()
	var b1 := _buffers(v1)
	var b2 := _buffers(v2)
	assert_int(b1.size()).is_greater(0)
	assert_array(b1.keys()).is_equal(b2.keys())
	for key: String in b1:
		assert_array(Array(b1[key])).is_equal(Array(b2[key]))
	# yol bağımsızlığı: önce uzağa gidip geri dönen görünüm de aynı baytları verir
	var v3 := _view(null, _no_blob_config())
	v3.track_camera(cam + Vector3(3000.0, 0.0, 0.0))
	v3.settle()
	v3.track_camera(cam)
	v3.settle()
	var b3 := _buffers(v3)
	assert_array(b3.keys()).is_equal(b1.keys())
	for key: String in b1:
		assert_array(Array(b3[key])).is_equal(Array(b1[key]))


func test_only_approved_species_are_drawn_and_no_unapproved_id_is_counted() -> void:
	var look := VegetationViewTestSupport.look_full()
	var view := _view(look, _no_blob_config())
	view.track_camera(VegetationViewTestSupport.camera_over_peak(30.0))
	view.settle()
	var drawn := view.drawn_species_ids()
	assert_int(drawn.size()).is_greater(2)
	var gate := look.gate
	for id in drawn:
		assert_bool(gate.is_approved(id)).is_true()
	assert_int(int(view.stats["unapproved_ids"])).is_equal(0)


func test_only_lod0_casts_shadows_and_tier_nodes_use_the_loaded_meshes() -> void:
	var look := VegetationViewTestSupport.look_full()
	var view := _view(look, _no_blob_config())
	view.track_camera(VegetationViewTestSupport.camera_over_peak(5.0))
	view.settle()
	var seen := [0, 0]
	for key in view.open_cell_keys():
		for child in view.cell_node(key).get_children():
			var mmi := child as MultiMeshInstance3D
			if mmi.get_meta(&"tier") == 0:
				assert_int(mmi.cast_shadow).is_equal(GeometryInstance3D.SHADOW_CASTING_SETTING_ON)
				seen[0] += 1
			else:
				assert_int(mmi.cast_shadow).is_equal(GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
				seen[1] += 1
			var sp := look.ids.find(str(mmi.get_meta(&"species_id")))
			var expect: Mesh = [look.mesh_lod0[sp], look.mesh_lod1[sp], look.mesh_proxy[sp]][int(mmi.get_meta(&"tier"))]
			assert_bool(mmi.multimesh.mesh == expect).is_true()
	assert_int(seen[0]).is_greater(0)
	assert_int(seen[1]).is_greater(0)


func test_draw_calls_stay_bounded_by_the_camera_neighbourhood() -> void:
	# 6366 hücrenin tümü değil: açık hücre sayısı ve görünür MMI kamera çevresiyle sınırlı
	var view := _view(null, _no_blob_config())
	view.track_camera(VegetationViewTestSupport.camera_over_peak(30.0))
	view.settle()
	var lay := VegetationViewTestSupport.layout()
	assert_int(int(view.stats["cells_open"])).is_less(lay.cell_count() / 2)
	assert_int(view.visible_mmi_count()).is_less(int(view.stats["cells_open"]) * 3 * 11)


func test_blob_chunks_open_for_the_ring_beyond_400_m_and_use_the_cutoff_shader() -> void:
	var view := _view()
	var cam := VegetationViewTestSupport.camera_over_peak(300.0)
	view.track_camera(cam)
	view.settle()
	var cfg := VegetationViewTestSupport.config()
	var lay := VegetationViewTestSupport.layout()
	var expect := VegetationWindow.chunks_to_open(lay, cam, cfg.lod1_end_m, cfg.blob_end_m, cfg.blob_load_margin_m,
			cfg.blob_chunk_cells, {})
	var got := view.blob_keys()
	assert_int(got.size()).is_greater(0)
	for key in got:
		assert_bool(expect.has(key)).is_true()
	assert_int(got.size()).is_equal(expect.size())
	var total_tris := 0
	for key in got:
		var mi := view.blob_node(key)
		var mat := mi.material_override as ShaderMaterial
		assert_float(float(mat.get_shader_parameter("begin_m"))).is_equal(cfg.lod1_end_m)
		assert_float(float(mat.get_shader_parameter("end_m"))).is_equal(cfg.blob_end_m)
		assert_int(mi.cast_shadow).is_equal(GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
		total_tris += int(mi.get_meta(&"tris"))
	assert_int(int(view.stats["blob_tris_all"])).is_equal(total_tris)
	assert_int(total_tris).is_greater(0)
	# kamera çok uzağa: parçalar kapanır
	view.track_camera(cam + Vector3(40000.0, 0.0, 0.0))
	view.settle()
	assert_int(view.blob_keys().size()).is_equal(0)


func test_blob_disabled_builds_no_chunks_and_a_layout_less_view_ignores_the_camera() -> void:
	var view := _view(null, _no_blob_config())
	view.track_camera(VegetationViewTestSupport.camera_over_peak(300.0))
	view.settle()
	assert_int(view.blob_keys().size()).is_equal(0)
	var empty: VegetationView = auto_free(VegetationView.new())
	add_child(empty)
	empty.setup(VegetationViewTestSupport.look_numbers(), VegetationViewTestSupport.config())
	empty.track_camera(Vector3.ZERO)   # düzen yok: hata/çökme yok
	assert_int(empty.visible_mmi_count()).is_equal(0)


## Yol aracı kare sıçraması (production/log/2026-11-01-yol-araci-ilk-kare.md): kamera hareketinden sonra biten leke
## parçaları aynı karede kurulunca ~110 ms'lik kare çıkıyordu. Kurulum `blob_install_budget_ms` ile dilimlidir: bütçe
## dolunca karede en çok 1 parça kurulur, kalanlar sonraki karelerde; sonuç bütçesiz sonuçla AYNI parça kümesidir.
func test_blob_installs_are_time_sliced_and_converge_to_the_unbudgeted_result() -> void:
	var cam := VegetationViewTestSupport.camera_over_peak(300.0)
	var full := _view()
	full.track_camera(cam)
	full.settle()
	var expected := full.blob_keys()
	assert_int(expected.size()).is_greater(2)   # dilimleme ancak birden çok parçada anlamlı
	var cfg := VegetationViewConfig.load_default()
	cfg.blob_install_budget_ms = 0.001   # her karede yalnız zorunlu 1 parça
	var view := _view(null, cfg)
	var seen := 0
	var most_in_one_frame := 0
	for _frame in 400:
		view.track_camera(cam)
		view._join_blob_jobs()   # işçiler biter; kurulum yine de kare başına bütçeli
		var now := view.blob_keys().size()
		most_in_one_frame = maxi(most_in_one_frame, now - seen)
		seen = now
		if seen == expected.size() and int(view.stats.get("blob_jobs", 1)) == 0 and int(view.stats.get("queued", 1)) == 0:
			break
	assert_int(most_in_one_frame).is_equal(1)
	var got := view.blob_keys()
	assert_int(got.size()).is_equal(expected.size())
	for key in expected:
		assert_bool(got.has(key)).is_true()
	assert_int(int(view.stats["blob_tris_all"])).is_equal(int(full.stats["blob_tris_all"]))
