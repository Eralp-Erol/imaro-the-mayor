extends GdUnitTestSuite
## T-011 · NetworkGeometry: ağ katmanının saf geometri yardımcıları (TEK-01/02). Kesin sayılarla sınanır; her
## yardımcının
## olumsuz karşılığı (bozuk girdide beklenen ret/boş sonuç) vardır.

const TAGS_SQUARE: Array[int] = [10, 11, 12, 13]


func _square(side: float) -> PackedVector2Array:
	# Pozitif yönelim (işaretli alan > 0): (0,0) -> (s,0) -> (s,s) -> (0,s).
	return PackedVector2Array([Vector2(0, 0), Vector2(side, 0), Vector2(side, side), Vector2(0, side)])


func _l_shape() -> PackedVector2Array:
	# Dışbükey olmayan L (tek içbükey köşe (10,10)); alan = 30x10 + 10x20 = 500.
	return PackedVector2Array([Vector2(0, 0), Vector2(30, 0), Vector2(30, 10), Vector2(10, 10), Vector2(10, 30),
			Vector2(0, 30)])


func test_signed_area_is_positive_for_the_canonical_orientation_and_negative_when_reversed() -> void:
	assert_float(NetworkGeometry.signed_area(_square(10.0))).is_equal(100.0)
	var reversed := PackedVector2Array(_square(10.0))
	reversed.reverse()
	assert_float(NetworkGeometry.signed_area(reversed)).is_equal(-100.0)


func test_point_in_polygon_inside_outside_and_concave_notch() -> void:
	var sq := _square(10.0)
	assert_bool(NetworkGeometry.point_in_polygon(Vector2(5, 5), sq)).is_true()
	assert_bool(NetworkGeometry.point_in_polygon(Vector2(15, 5), sq)).is_false()
	assert_bool(NetworkGeometry.point_in_polygon(Vector2(-0.5, 5), sq)).is_false()
	var ell := _l_shape()
	assert_bool(NetworkGeometry.point_in_polygon(Vector2(5, 25), ell)).is_true()
	# Olumsuz: L'nin içbükey boşluğundaki nokta dışarıdadır.
	assert_bool(NetworkGeometry.point_in_polygon(Vector2(20, 20), ell)).is_false()


func test_segment_params_crossing_and_parallel() -> void:
	var cross := NetworkGeometry.segment_params(Vector2(0, 0), Vector2(10, 10), Vector2(0, 10), Vector2(10, 0))
	assert_float(cross.x).is_equal_approx(0.5, 1.0e-9)
	assert_float(cross.y).is_equal_approx(0.5, 1.0e-9)
	var parallel := NetworkGeometry.segment_params(Vector2(0, 0), Vector2(10, 0), Vector2(0, 5), Vector2(10, 5))
	assert_bool(is_inf(parallel.x)).is_true()


func test_distance_point_segment_clamps_to_the_endpoints() -> void:
	var a := Vector2(0, 0)
	var b := Vector2(10, 0)
	assert_float(NetworkGeometry.distance_point_segment(Vector2(5, 3), a, b)).is_equal_approx(3.0, 1.0e-6)
	assert_float(NetworkGeometry.distance_point_segment(Vector2(14, 3), a, b)).is_equal_approx(5.0, 1.0e-6)


func test_inset_square_shrinks_by_the_offsets() -> void:
	var offsets := PackedFloat64Array([1.0, 1.0, 1.0, 1.0])
	var result := NetworkGeometry.inset_polygon(_square(10.0), offsets)
	var pts: PackedVector2Array = result["points"]
	assert_int(pts.size()).is_equal(4)
	assert_float(NetworkGeometry.signed_area(pts)).is_equal_approx(64.0, 1.0e-4)
	# Her iç kenar özgün kenar indeksine bağlıdır.
	assert_array(result["edge_of"]).is_equal([0, 1, 2, 3])


func test_inset_with_unequal_offsets_keeps_orientation_and_per_edge_widths() -> void:
	var offsets := PackedFloat64Array([1.0, 2.0, 1.0, 2.0])
	var pts: PackedVector2Array = NetworkGeometry.inset_polygon(_square(10.0), offsets)["points"]
	# x: [2,8] (kenar 3,1 -> 2 ve 2), z: [1,9] -> 6 * 8 = 48
	assert_float(NetworkGeometry.signed_area(pts)).is_equal_approx(48.0, 1.0e-4)


func test_inset_negative_too_large_offset_returns_no_polygon() -> void:
	var offsets := PackedFloat64Array([6.0, 6.0, 6.0, 6.0])
	var result := NetworkGeometry.inset_polygon(_square(10.0), offsets)
	assert_int((result["points"] as PackedVector2Array).size()).is_equal(0)


func test_inset_handles_collinear_vertices_with_changing_offsets() -> void:
	# Üst kenar iki parçaya bölünmüş (ortada eşdoğrusal köşe) ve parçaların ofseti farklı: basamak üretilir, alan
	# doğru.
	var poly := PackedVector2Array([Vector2(0, 0), Vector2(5, 0), Vector2(10, 0), Vector2(10, 10), Vector2(0, 10)])
	var offsets := PackedFloat64Array([1.0, 2.0, 1.0, 1.0, 1.0])
	var result := NetworkGeometry.inset_polygon(poly, offsets)
	var pts: PackedVector2Array = result["points"]
	assert_int(pts.size()).is_greater(4)
	# Sol yarı x [1,5] z [1,9] = 32; sağ yarı x [5,9] z [2,9] = 28 (basamak x = 5'te).
	assert_float(NetworkGeometry.signed_area(pts)).is_equal_approx(60.0, 1.0e-3)


func test_clip_halfplane_keeps_tags_and_marks_the_cut_edge() -> void:
	var tags := PackedInt32Array(TAGS_SQUARE)
	# x >= 4 tarafını tut.
	var result := NetworkGeometry.clip_halfplane(_square(10.0), tags, Vector2(4, 0), Vector2(1, 0))
	var pts: PackedVector2Array = result["points"]
	var out_tags: PackedInt32Array = result["tags"]
	assert_float(NetworkGeometry.signed_area(pts)).is_equal_approx(60.0, 1.0e-6)
	assert_int(pts.size()).is_equal(out_tags.size())
	assert_int(out_tags.count(-1)).is_equal(1)
	# Sol kenar (etiket 13) tamamen kesildi; diğer üç özgün kenar etiketini korur.
	for t in [10, 11, 12]:
		assert_bool(out_tags.has(t)).is_true()
	assert_bool(out_tags.has(13)).is_false()


func test_clip_halfplane_outside_everything_returns_empty() -> void:
	var tags := PackedInt32Array(TAGS_SQUARE)
	var result := NetworkGeometry.clip_halfplane(_square(10.0), tags, Vector2(20, 0), Vector2(1, 0))
	assert_int((result["points"] as PackedVector2Array).size()).is_equal(0)


func test_is_convex_and_negative_for_concave() -> void:
	assert_bool(NetworkGeometry.is_convex(_square(10.0))).is_true()
	assert_bool(NetworkGeometry.is_convex(_l_shape())).is_false()


func test_is_simple_detects_a_bow_tie() -> void:
	assert_bool(NetworkGeometry.is_simple(_square(10.0))).is_true()
	var bow := PackedVector2Array([Vector2(0, 0), Vector2(10, 10), Vector2(10, 0), Vector2(0, 10)])
	assert_bool(NetworkGeometry.is_simple(bow)).is_false()


func test_convex_decomposition_of_an_l_shape_conserves_area_and_yields_convex_pieces() -> void:
	var ell := _l_shape()
	var tags := PackedInt32Array([0, 1, 2, 3, 4, 5])
	var pieces := NetworkGeometry.convex_decompose(ell, tags)
	assert_int(pieces.size()).is_equal(2)
	var total := 0.0
	for piece: Dictionary in pieces:
		assert_bool(NetworkGeometry.is_convex(piece["points"])).is_true()
		total += NetworkGeometry.signed_area(piece["points"])
		assert_int((piece["points"] as PackedVector2Array).size()).is_equal((piece["tags"] as PackedInt32Array).size())
	assert_float(total).is_equal_approx(NetworkGeometry.signed_area(ell), 1.0e-6)


func test_convex_decomposition_leaves_a_convex_polygon_alone() -> void:
	var pieces := NetworkGeometry.convex_decompose(_square(10.0), PackedInt32Array(TAGS_SQUARE))
	assert_int(pieces.size()).is_equal(1)


func test_convex_overlap_sat_detects_overlap_but_not_touching() -> void:
	var a := _square(10.0)
	var shifted := PackedVector2Array()
	for p in a:
		shifted.append(p + Vector2(5, 5))
	var touching := PackedVector2Array()
	for p in a:
		touching.append(p + Vector2(10, 0))
	assert_bool(NetworkGeometry.convex_overlap(a, shifted, 0.01)).is_true()
	assert_bool(NetworkGeometry.convex_overlap(a, touching, 0.01)).is_false()


func test_polygon_rect_intersection() -> void:
	var sq := _square(10.0)
	assert_bool(NetworkGeometry.polygon_intersects_rect(sq, Rect2(5, 5, 20, 20))).is_true()
	assert_bool(NetworkGeometry.polygon_intersects_rect(sq, Rect2(-5, -5, 30, 30))).is_true()  # rect poligonu içerir
	assert_bool(NetworkGeometry.polygon_intersects_rect(sq, Rect2(2, 2, 3, 3))).is_true()  # poligon rect'i içerir
	assert_bool(NetworkGeometry.polygon_intersects_rect(sq, Rect2(20, 20, 5, 5))).is_false()


func test_simplify_polyline_keeps_corners_and_drops_collinear_points() -> void:
	var pts := PackedVector2Array([Vector2(0, 0), Vector2(5, 0.2), Vector2(10, 0), Vector2(10, 10)])
	var out := NetworkGeometry.simplify_polyline(pts, 1.0)
	assert_int(out.size()).is_equal(3)
	assert_vector(out[1]).is_equal(Vector2(10, 0))


func test_segment_polygon_distance_for_spur_filtering() -> void:
	var sq := _square(10.0)
	assert_float(NetworkGeometry.segment_polygon_distance(Vector2(-5, 5), Vector2(-1, 5), sq)).is_equal_approx(1.0, 1.0e-6)
	# Segment poligonu keserse mesafe 0.
	assert_float(NetworkGeometry.segment_polygon_distance(Vector2(-5, 5), Vector2(5, 5), sq)).is_equal(0.0)
