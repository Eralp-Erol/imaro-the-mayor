extends GdUnitTestSuite
## T-042b · Alınan parselin içindeki bitki gizleme: `VegetationParcelMask` (dış çizgi içi satırlar = kaba kuvvetle aynı
## küme, dilimli tarama = tek seferlik tarama), `VegetationLayout` kaynak bitleri (koridor + parsel birbirini bozmaz,
## artımlı fark) ve `VegetationView.set_parcel_rows` (gizler, geri getirir, koridor yenilemesi parsel maskesini silmez).


## Tepe hücresinin ortasında, `half` yarı kenarlı dikdörtgen dış çizgi.
func _outline(half: float, shift: Vector2 = Vector2.ZERO) -> PackedVector2Array:
	var lay := VegetationViewTestSupport.layout()
	var o := lay.cell_origin(lay.cols.peak_cell().y)
	var c := Vector2(o.x, o.y) + Vector2(lay.cols.cell_m, lay.cols.cell_m) * 0.5 + shift
	return PackedVector2Array([c + Vector2(-half, -half), c + Vector2(half, -half), c + Vector2(half, half),
			c + Vector2(-half, half)])


func _brute(lay: VegetationLayout, outline: PackedVector2Array) -> PackedInt32Array:
	var out := PackedInt32Array()
	for i in lay.cols.count:
		if Geometry2D.is_point_in_polygon(Vector2(lay.cols.x[i], lay.cols.z[i]), outline):
			out.append(i)
	return out


func _in_range_config() -> VegetationViewConfig:
	var cfg := VegetationViewConfig.load_default()
	cfg.blob_enabled = false
	cfg.lod0_end_m = 1.0e9
	cfg.lod1_end_m = 2.0e9
	cfg.palm_proxy_end_m = 3.0e9
	return cfg


func test_rows_in_outline_equals_brute_force_and_is_sorted_unique() -> void:
	var lay := VegetationViewTestSupport.layout()
	var outline := _outline(40.0)
	var got := VegetationParcelMask.rows_in_outline(lay, outline)
	var want := _brute(lay, outline)
	assert_int(want.size()).is_greater(0)
	assert_array(Array(got)).is_equal(Array(want))
	# bir dış çizgi dışında kalan örnek yok
	for i in got:
		assert_bool(Geometry2D.is_point_in_polygon(Vector2(lay.cols.x[i], lay.cols.z[i]), outline)).is_true()
	assert_int(VegetationParcelMask.rows_in_outline(lay, PackedVector2Array()).size()).is_equal(0)


func test_sliced_scan_equals_one_shot_scan_and_never_overruns_the_slice_count() -> void:
	var lay := VegetationViewTestSupport.layout()
	var outlines := {3: _outline(45.0), 8: _outline(30.0, Vector2(70.0, 20.0))}
	var mask := VegetationParcelMask.new()
	mask.bind(lay)
	mask.want({3: true, 8: true}, outlines)
	var steps := 0
	while mask.pending():
		mask.step(outlines, 1)   # 1 us: her çağrıda en az bir dilim ilerler
		steps += 1
		assert_int(steps).is_less(100000)
	assert_int(steps).is_greater(2)   # gerçekten dilimlendi
	assert_array(Array(mask.rows_of[3])).is_equal(Array(_brute(lay, outlines[3])))
	assert_array(Array(mask.rows_of[8])).is_equal(Array(_brute(lay, outlines[8])))
	var union := mask.union_rows()
	for n in range(1, union.size()):
		assert_int(union[n]).is_greater(union[n - 1])
	assert_bool(mask.changed()).is_false()


func test_want_drops_released_parcels_and_keeps_cached_rows_of_the_rest() -> void:
	var lay := VegetationViewTestSupport.layout()
	var outlines := {1: _outline(35.0), 2: _outline(25.0, Vector2(90.0, 0.0))}
	var mask := VegetationParcelMask.new()
	mask.bind(lay)
	mask.want({1: true, 2: true}, outlines)
	mask.step(outlines, 1 << 40)
	var rows2: PackedInt32Array = mask.rows_of[2]
	var scanned := mask.rows_scanned
	assert_int(mask.want({2: true}, outlines)).is_equal(1)   # 1 düştü, taranacak yok
	assert_bool(mask.rows_of.has(1)).is_false()
	assert_bool(mask.pending()).is_false()
	assert_array(Array(mask.rows_of[2])).is_equal(Array(rows2))
	assert_int(mask.rows_scanned).is_equal(scanned)   # geri kalan parsel yeniden taranmadı
	# aynı yerleşimde tekrar bağlamak hesabı düşürmez; yeni yerleşim düşürür
	assert_bool(mask.bind(lay)).is_false()
	assert_bool(mask.bind(VegetationViewTestSupport.fresh_layout())).is_true()
	assert_bool(mask.rows_of.is_empty()).is_true()


func test_layout_sources_do_not_clobber_each_other_and_updates_are_incremental() -> void:
	var lay := VegetationViewTestSupport.fresh_layout()
	var corridor := VegetationCorridor.rows_inside(lay, [VegetationViewTestSupport.peak_corridor(12.0)])
	var parcel := VegetationParcelMask.rows_in_outline(lay, _outline(40.0))
	lay.set_channel_rows(VegetationLayout.CH_CORRIDOR, corridor)
	var changed := lay.set_channel_rows(VegetationLayout.CH_PARCEL, parcel)
	var union := {}
	for i in corridor:
		union[i] = true
	for i in parcel:
		union[i] = true
	assert_int(lay.hidden_count).is_equal(union.size())
	# koridor kalkınca yalnız parselin tuttukları gizli kalır
	lay.set_channel_rows(VegetationLayout.CH_CORRIDOR, PackedInt32Array())
	assert_int(lay.hidden_count).is_equal(parcel.size())
	for i in corridor:
		assert_bool(lay.is_hidden(i)).is_equal(parcel.has(i))
	# parsel de kalkınca maske tamamen kalkar; geri gelen hücreler, gizlenen hücrelerle aynı
	var back := lay.set_channel_rows(VegetationLayout.CH_PARCEL, PackedInt32Array())
	assert_array(Array(back)).is_equal(Array(changed))
	assert_bool(lay.hidden.is_empty()).is_true()
	assert_int(lay.hidden_count).is_equal(0)
	assert_int(changed.size()).is_greater(0)
	# tekrar aynı küme: değişiklik yok
	lay.set_channel_rows(VegetationLayout.CH_PARCEL, parcel)
	assert_int(lay.set_channel_rows(VegetationLayout.CH_PARCEL, parcel).size()).is_equal(0)
	# tek parselden diğerine: yalnız fark yazılır, bit eşit sonuç
	var other := VegetationParcelMask.rows_in_outline(lay, _outline(40.0, Vector2(30.0, 0.0)))
	lay.set_channel_rows(VegetationLayout.CH_PARCEL, other)
	var fresh := VegetationViewTestSupport.fresh_layout()
	fresh.set_channel_rows(VegetationLayout.CH_PARCEL, other)
	assert_array(Array(lay.hidden)).is_equal(Array(fresh.hidden))
	assert_int(lay.hidden_count).is_equal(other.size())


func test_view_hides_taken_parcel_trees_and_brings_them_back_and_corridor_refresh_keeps_them_hidden() -> void:
	var view: VegetationView = auto_free(VegetationView.new())
	add_child(view)
	view.setup(VegetationViewTestSupport.look_numbers(), _in_range_config())
	var lay := VegetationViewTestSupport.fresh_layout()
	view.set_layout(lay)
	view.track_camera(VegetationViewTestSupport.camera_over_peak(5.0))
	view.settle()
	var all := lay.cols.count
	assert_int(view.visible_instances().x).is_equal(all)
	var rows := VegetationParcelMask.rows_in_outline(lay, _outline(40.0))
	assert_int(rows.size()).is_greater(0)
	assert_int(view.set_parcel_rows(rows)).is_greater(0)
	view.settle()
	assert_int(view.visible_instances().x).is_equal(all - rows.size())
	# yol koridoru yenilemesi (playable `_refresh_vegetation_corridors`) parsel kaynağını silmez
	view.set_corridors([])
	view.set_corridors([VegetationViewTestSupport.peak_corridor(12.0)])
	view.settle()
	for i in rows:
		assert_bool(lay.is_hidden(i)).is_true()
	view.set_corridors([])
	view.settle()
	assert_int(view.visible_instances().x).is_equal(all - rows.size())
	# aynı küme tekrar: iş yok
	assert_int(view.set_parcel_rows(rows)).is_equal(0)
	# geri alma: parsel kümesi boş -> hepsi geri gelir
	assert_int(view.set_parcel_rows(PackedInt32Array())).is_greater(0)
	view.settle()
	assert_int(view.visible_instances().x).is_equal(all)
	assert_int(lay.hidden_count).is_equal(0)
