extends GdUnitTestSuite
## T-042 sanat düzeltmesi · yol önizleme şeridi: geçerli = daha opak + açık kenar çizgisi; geçersiz = renge EK kesikli
## kenar + tarama (renk körlüğü) ve çakışan parsel sınırı; renkler `ui_tokens.json` token'larından (yeni sabit yok).


func _preview() -> RoadDraftPreview:
	var p := RoadDraftPreview.new()
	add_child(p)
	return auto_free(p)


## Yüzey -> köşe sayısı (şerit yüzeyi 0, halkalar/parsel sınırı 1; şerit hiç yoksa yalnız 0 halkalardır).
func _vertex_counts(p: RoadDraftPreview) -> Array[int]:
	var out: Array[int] = []
	var mesh := p.mark_node().mesh
	for s in mesh.get_surface_count():
		out.append((mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size())
	return out


func _colors(p: RoadDraftPreview, surface: int) -> PackedColorArray:
	return p.mark_node().mesh.surface_get_arrays(surface)[Mesh.ARRAY_COLOR]


func _square(c: Vector2, half: float) -> PackedVector2Array:
	return PackedVector2Array([c + Vector2(-half, -half), c + Vector2(half, -half), c + Vector2(half, half),
			c + Vector2(-half, half)])


func test_valid_ribbon_is_more_opaque_than_the_invalid_one_and_uses_token_colors() -> void:
	var tokens := UiTokens.load_default()
	var p := _preview()
	p.show_draft(Vector2.ZERO, Vector2(100.0, 0.0), 10.0, true)
	var valid_alpha := p.ribbon_color().a
	assert_float(valid_alpha).is_greater(RoadDraftPreview.RIBBON_ALPHA)
	assert_bool(Color(p.ribbon_color(), 1.0).is_equal_approx(tokens.color("ok"))).is_true()
	var cols := _colors(p, 0)
	# açık tonlu kenar çizgisi: `text` token'ı, şerit gövdesinden daha açık
	var edge_found := false
	for c in cols:
		if Color(c, 1.0).is_equal_approx(tokens.color("text")):
			edge_found = true
	assert_bool(edge_found).is_true()
	p.show_draft(Vector2.ZERO, Vector2(100.0, 0.0), 10.0, false)
	assert_float(p.ribbon_color().a).is_less(valid_alpha)
	assert_bool(Color(p.ribbon_color(), 1.0).is_equal_approx(tokens.color("danger"))).is_true()


func test_invalid_ribbon_adds_dashes_and_hatching_that_the_valid_one_does_not_have() -> void:
	var p := _preview()
	p.show_draft(Vector2.ZERO, Vector2(100.0, 0.0), 10.0, true)
	var valid_n := _vertex_counts(p)[0]
	p.show_draft(Vector2.ZERO, Vector2(100.0, 0.0), 10.0, false)
	var invalid_n := _vertex_counts(p)[0]
	# kesik kenar + tarama: şekil ipucu (yalnız ton farkı değil)
	assert_int(invalid_n).is_greater(valid_n * 2)


func test_conflict_parcel_outline_is_drawn_in_danger_only_for_invalid_drafts() -> void:
	var tokens := UiTokens.load_default()
	var p := _preview()
	var outline := _square(Vector2(50.0, 30.0), 20.0)
	p.show_draft(Vector2.ZERO, Vector2(100.0, 0.0), 10.0, false)
	var without := _vertex_counts(p)[1]
	p.show_draft(Vector2.ZERO, Vector2(100.0, 0.0), 10.0, false, outline)
	var with_outline := _vertex_counts(p)[1]
	assert_int(with_outline).is_greater(without)
	var danger_found := false
	for c in _colors(p, 1):
		if Color(c, 1.0).is_equal_approx(tokens.color("danger")):
			danger_found = true
	assert_bool(danger_found).is_true()
	# geçerli taslakta parsel sınırı çizilmez
	p.show_draft(Vector2.ZERO, Vector2(100.0, 0.0), 10.0, true, outline)
	assert_int(_vertex_counts(p)[1]).is_equal(without)


func test_every_triangle_index_points_at_its_own_strip_vertices() -> void:
	# Aynı yüzeyde birden çok şerit (gövde + kenarlar + tarama): indeksler köşe sayısı içinde ve her üçgen yerel kalır.
	var p := _preview()
	p.show_draft(Vector2.ZERO, Vector2(100.0, 0.0), 10.0, false)
	var arrays := p.mark_node().mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	assert_int(indices.size()).is_greater(0)
	var referenced := {}
	for i in indices.size() / 3:
		var tri := [indices[i * 3], indices[i * 3 + 1], indices[i * 3 + 2]]
		for idx: int in tri:
			assert_int(idx).is_less(verts.size())
			referenced[idx] = true
		var span := maxf(maxf(absf(verts[tri[0]].x - verts[tri[1]].x), absf(verts[tri[1]].x - verts[tri[2]].x)),
				absf(verts[tri[0]].x - verts[tri[2]].x))
		assert_float(span).is_less(20.0)   # yerel üçgen (bir şerit parçası), köşeler başka şeritten karışmaz
	# her köşe en az bir üçgende kullanılır (ekleme şeritleri gerçekten çizilir)
	assert_int(referenced.size()).is_equal(verts.size())
