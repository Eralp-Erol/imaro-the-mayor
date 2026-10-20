# gdlint:disable=max-public-methods
extends GdUnitTestSuite
## T-001 ölçüt 4 · Chunk'lı arazi/su MESH VERİSİ testleri (render'dan bağımsız; yalnız Packed*Array hesabı).
## WLD-01/TEK-03: görünüm, WorldData'nın aynı örneklerinden türer; chunk dikişlerinde delik/basamak yoktur;
## kıyı/su ayrımı WorldData ile tutarlıdır. Olumsuz durumlar bellekte bozulmuş dünya ile gösterilir.

const CHUNK_CELLS := 32  # 100 hücre / 32 → 4 chunk, sonuncusu 4 hücrelik kısmi chunk (kırpma yolu sınanır)
const EPS := 0.001

var _world: WorldData
var _palette: TerrainPalette


func before() -> void:
	_world = WorldTestSupport.coarse(WorldTestSupport.control())
	_palette = TerrainPalette.new(_world)


# --- Chunk ızgarası ---

func test_chunk_rects_cover_every_cell_exactly_once() -> void:
	var counts := TerrainMeshBuilder.chunk_counts(_world, CHUNK_CELLS)
	var seen := PackedByteArray()
	seen.resize((_world.width - 1) * (_world.height - 1))
	for cz in counts.y:
		for cx in counts.x:
			var rect := TerrainMeshBuilder.chunk_cell_rect(_world, cx, cz, CHUNK_CELLS)
			assert_bool(rect.size.x > 0 and rect.size.y > 0).is_true()
			for j in range(rect.position.y, rect.end.y):
				for i in range(rect.position.x, rect.end.x):
					seen[j * (_world.width - 1) + i] += 1
	for count in seen:
		assert_int(count).is_equal(1)


func test_chunk_count_matches_world_size_and_default_chunk_is_four_km() -> void:
	var counts := TerrainMeshBuilder.chunk_counts(_world, CHUNK_CELLS)
	assert_int(counts.x).is_equal(ceili((_world.width - 1) / float(CHUNK_CELLS)))
	var full := WorldTestSupport.default_world()
	var big := TerrainMeshBuilder.chunk_counts(full, 40)
	assert_vector(Vector2(big)).is_equal(Vector2(10, 10))  # 40 km / 4 km
	assert_float(40 * full.cell_size).is_equal(4000.0)


# --- Kara: dikiş, delik, çakışma yok ---

func test_every_land_vertex_matches_the_world_height_sample_across_chunk_seams() -> void:
	var checked := 0
	for chunk in _all_chunks(1, false):
		var origin: Vector3 = chunk["origin"]
		var verts: PackedVector3Array = chunk["land"]["vertices"]
		for v in verts:
			var i := roundi((origin.x + v.x - _world.origin.x) / _world.cell_size)
			var j := roundi((origin.z + v.z - _world.origin.y) / _world.cell_size)
			assert_float(origin.x + v.x).is_equal_approx(_world.origin.x + i * _world.cell_size, EPS)
			assert_float(v.y).is_equal_approx(_world.heights[j * _world.width + i], EPS)
			checked += 1
	assert_int(checked).is_greater(1000)


func test_land_mesh_has_no_hole_every_cell_with_land_corner_has_a_triangle() -> void:
	assert_array(_land_mesh_violations(_world)).override_failure_message(
		"ihlaller: %s" % [_land_mesh_violations(_world).slice(0, 5)]).is_empty()


func test_land_mesh_hole_check_fails_when_a_land_cell_is_sunk_negative() -> void:
	# Olumsuz: bir hücrenin dört köşesini deniz altına gömmek kara üçgenini düşürür; maske hâlâ "kara" der → "delik".
	var broken := WorldTestSupport.coarse(WorldTestSupport.control())
	var land_idx := broken.land_mask.find(1)
	var i := mini(land_idx % broken.width, broken.width - 2)
	var j := mini(land_idx / broken.width, broken.height - 2)
	var a := j * broken.width + i
	for idx in [a, a + 1, a + broken.width, a + broken.width + 1]:
		broken.heights[idx] = broken.sea_level - 5.0
	assert_array(_land_mesh_violations(broken)).is_not_empty()


func test_no_land_triangle_lies_fully_below_sea_and_none_is_degenerate() -> void:
	for chunk in _all_chunks(1, false):
		var verts: PackedVector3Array = chunk["land"]["vertices"]
		for t in range(0, verts.size(), 3):
			assert_float(maxf(maxf(verts[t].y, verts[t + 1].y), verts[t + 2].y)).is_greater_equal(_world.sea_level)
			assert_float((verts[t + 1] - verts[t]).cross(verts[t + 2] - verts[t]).length()).is_greater(0.0)


func test_land_normals_are_flat_unit_upward_and_match_clockwise_winding() -> void:
	for chunk in _all_chunks(1, false, 1.0):
		var data: Dictionary = chunk["land"]
		var verts: PackedVector3Array = data["vertices"]
		var normals: PackedVector3Array = data["normals"]
		assert_int(normals.size()).is_equal(verts.size())
		assert_int(verts.size() / 3).is_equal(int(data["triangles"]))
		for t in range(0, verts.size(), 3):
			var n := normals[t]
			assert_vector(normals[t + 1]).is_equal_approx(n, Vector3.ONE * EPS)
			assert_vector(normals[t + 2]).is_equal_approx(n, Vector3.ONE * EPS)
			assert_float(n.length()).is_equal_approx(1.0, EPS)
			assert_float(n.y).is_greater(0.0)
			# Godot ön yüz = saat yönü: (v1-v0)x(v2-v0), normalin TERSİ yönünde olmalı.
			assert_float((verts[t + 1] - verts[t]).cross(verts[t + 2] - verts[t]).dot(n)).is_less(0.0)


func test_shading_exaggeration_changes_normals_but_not_geometry() -> void:
	var a := TerrainMeshBuilder.build_land(_world, _palette, 3, 3, CHUNK_CELLS, 1, false, 1.0)
	var b := TerrainMeshBuilder.build_land(_world, _palette, 3, 3, CHUNK_CELLS, 1, false, 4.0)
	assert_array(a["vertices"]).is_equal(b["vertices"])
	var any_steeper := false
	for k in (a["normals"] as PackedVector3Array).size():
		if (b["normals"] as PackedVector3Array)[k].y < (a["normals"] as PackedVector3Array)[k].y - 0.01:
			any_steeper = true
			break
	assert_bool(any_steeper).is_true()


func test_chunk_geometry_stays_inside_world_bounds_and_reaches_all_four_edges() -> void:
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for chunk in _all_chunks(1, true):
		var origin: Vector3 = chunk["origin"]
		for v: Vector3 in chunk["land"]["vertices"]:
			var w := origin + v
			lo = lo.min(w)
			hi = hi.max(w)
		for v: Vector3 in chunk["water"]["vertices"]:
			if chunk["water"]["triangles"] > 0:
				var w := origin + v
				lo = lo.min(Vector3(w.x, lo.y, w.z))
				hi = hi.max(Vector3(w.x, hi.y, w.z))
	var b := _world.bounds()
	assert_float(lo.x).is_equal_approx(b.position.x, EPS)
	assert_float(lo.z).is_equal_approx(b.position.y, EPS)
	assert_float(hi.x).is_equal_approx(b.end.x, EPS)
	assert_float(hi.z).is_equal_approx(b.end.y, EPS)
	assert_float(lo.y).is_greater_equal(TerrainMeshBuilder.SKIRT_BOTTOM_Y - EPS)


func test_skirts_close_the_world_boundary_only() -> void:
	assert_int(_total_triangles(true)).is_greater(_total_triangles(false))
	var walls := 0
	for chunk in _all_chunks(1, true):
		var origin: Vector3 = chunk["origin"]
		var verts: PackedVector3Array = chunk["land"]["vertices"]
		var normals: PackedVector3Array = chunk["land"]["normals"]
		for t in range(0, verts.size(), 3):
			if absf(normals[t].y) > 0.001:
				continue  # arazi yüzü; etekler dikeydir
			walls += 1
			var on_x := true
			var on_z := true
			for k in 3:
				var w := origin + verts[t + k]
				var x_edge := is_equal_approx(w.x, _world.origin.x) or is_equal_approx(w.x, _world.bounds().end.x)
				var z_edge := is_equal_approx(w.z, _world.origin.y) or is_equal_approx(w.z, _world.bounds().end.y)
				on_x = on_x and x_edge
				on_z = on_z and z_edge
			assert_bool(on_x or on_z).is_true()
	assert_int(walls).is_greater(0)


# --- Su: kıyı/su ayrımı WorldData ile tutarlı ---

func test_water_mesh_is_flat_at_sea_level_and_covers_exactly_cells_with_a_water_corner() -> void:
	var w := _world.width
	for chunk in _all_chunks():
		var water: Dictionary = chunk["water"]
		var rect := TerrainMeshBuilder.chunk_cell_rect(_world, chunk["cx"], chunk["cz"], CHUNK_CELLS)
		var covered := {}
		var indices: PackedInt32Array = water["indices"]
		var verts: PackedVector3Array = water["vertices"]
		var local_w := rect.size.x + 1
		for k in range(0, indices.size(), 6):
			var l00 := indices[k]
			var ci := rect.position.x + l00 % local_w
			var cj := rect.position.y + l00 / local_w
			covered[Vector2i(ci, cj)] = true
			for m in 6:
				assert_float(verts[indices[k + m]].y).is_equal(_world.sea_level)
		for j in range(rect.position.y, rect.end.y):
			for i in range(rect.position.x, rect.end.x):
				var a := j * w + i
				var has_water := (_world.heights[a] < _world.sea_level or _world.heights[a + 1] < _world.sea_level
						or _world.heights[a + w] < _world.sea_level or _world.heights[a + w + 1] < _world.sea_level)
				assert_bool(covered.has(Vector2i(i, j))).is_equal(has_water)
		assert_int(int(water["triangles"])).is_equal(covered.size() * 2)


func test_every_water_sample_is_under_water_mesh_and_every_land_sample_is_in_the_land_mesh() -> void:
	# Kıyı sözleşmesi: su örnekleri (land_mask 0) su yüzeyi altında kalır, kara örnekleri (1) deniz seviyesinin üstündedir.
	for idx in _world.heights.size():
		if _world.land_mask[idx] == 1:
			assert_float(_world.heights[idx]).is_greater_equal(_world.sea_level + 0.5)
		else:
			assert_float(_world.heights[idx]).is_less_equal(_world.sea_level - 0.5)
	assert_array(_land_mesh_violations(_world)).is_empty()


func test_water_colors_run_from_turquoise_shallow_to_navy_deep() -> void:
	var shallow := TerrainPalette.water_color(-60.0, 1.5)
	var mid := TerrainPalette.water_color(-1200.0, 25.0)
	var deep := TerrainPalette.water_color(-6000.0, 110.0)
	assert_float(shallow.g).is_greater(deep.g)
	assert_float(shallow.get_luminance()).is_greater(mid.get_luminance())
	assert_float(mid.get_luminance()).is_greater(deep.get_luminance())
	assert_float(deep.b).is_greater(deep.r)
	# Sığ: yeşil ve mavi yakın (turkuaz), derin: mavi baskın.
	assert_float(shallow.g / shallow.b).is_greater(0.85)
	assert_float(deep.g / deep.b).is_less(0.6)


# --- Determinizm ve renk ---

func test_chunk_data_is_deterministic_and_independent_of_build_order() -> void:
	var first := TerrainMeshBuilder.build_land(_world, _palette, 2, 1, CHUNK_CELLS)
	var palette2 := TerrainPalette.new(_world)
	TerrainMeshBuilder.build_land(_world, palette2, 0, 0, CHUNK_CELLS)  # başka chunk önce kurulsun
	var second := TerrainMeshBuilder.build_land(_world, palette2, 2, 1, CHUNK_CELLS)
	assert_array(first["vertices"]).is_equal(second["vertices"])
	assert_array(first["colors"]).is_equal(second["colors"])


func test_land_colors_are_valid_and_separate_plain_forest_and_rock() -> void:
	var plain := _palette.land_color(25.0, 1.0, 900.0, 0, 20000.0, 8000.0)
	var forest := _palette.land_color(260.0, 14.0, 4000.0, 0, 18000.0, 3000.0)
	var rock := _palette.land_color(700.0, 32.0, 9000.0, 0, 37000.0, 33000.0)
	for c in [plain, forest, rock]:
		for ch in [c.r, c.g, c.b]:
			assert_float(ch).is_between(0.0, 1.0)
	assert_float(forest.g).is_less(plain.g)  # orman ovadan koyu
	assert_float(forest.get_luminance()).is_less(plain.get_luminance())
	assert_float(rock.r).is_greater(rock.b)  # okra/kahve: kırmızı > mavi
	assert_float(rock.get_luminance()).is_greater(forest.get_luminance())
	assert_object(_palette.land_color(25.0, 1.0, 900.0, 0, 20000.0, 8000.0)).is_equal(plain)


func test_field_mosaic_varies_inside_the_d4_plain_but_not_into_one_flat_colour() -> void:
	var d4 := _world.region_by_code(&"D4")
	var seen := {}
	for k in 60:
		var x := d4.anchor.x - 2500.0 + k * 83.0
		var z := d4.anchor.y - 1500.0 + k * 47.0
		var idx := _world.world_to_index(x, z)
		var c := _palette.land_color(28.0, 0.8, 5000.0, idx, x, z)
		seen[c.to_html(false)] = true
	assert_int(seen.size()).is_greater(8)  # tek renkli leke değil


# --- Yardımcılar ---

func _all_chunks(stride: int = 1, skirts: bool = true, exaggeration: float = 4.0) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var counts := TerrainMeshBuilder.chunk_counts(_world, CHUNK_CELLS)
	for cz in counts.y:
		for cx in counts.x:
			out.append({
				"cx": cx, "cz": cz, "origin": TerrainMeshBuilder.chunk_origin(_world, cx, cz, CHUNK_CELLS),
				"land": TerrainMeshBuilder.build_land(_world, _palette, cx, cz, CHUNK_CELLS, stride, skirts,
					exaggeration),
				"water": TerrainMeshBuilder.build_water(_world, cx, cz, CHUNK_CELLS),
			})
	return out


func _total_triangles(skirts: bool) -> int:
	var total := 0
	var counts := TerrainMeshBuilder.chunk_counts(_world, CHUNK_CELLS)
	for cz in counts.y:
		for cx in counts.x:
			total += int(TerrainMeshBuilder.build_land(_world, _palette, cx, cz, CHUNK_CELLS, 1, skirts)["triangles"])
	return total


## Kara mesh'inde delik: kara köşesi taşıyan her hücre (verilen dünya için) en az bir üçgen içermeli.
func _land_mesh_violations(world: WorldData) -> PackedStringArray:
	var violations := PackedStringArray()
	var palette := TerrainPalette.new(world)
	var counts := TerrainMeshBuilder.chunk_counts(world, CHUNK_CELLS)
	var w := world.width
	var emitted := {}
	for cz in counts.y:
		for cx in counts.x:
			var data := TerrainMeshBuilder.build_land(world, palette, cx, cz, CHUNK_CELLS, 1, false, 1.0)
			var origin := TerrainMeshBuilder.chunk_origin(world, cx, cz, CHUNK_CELLS)
			var verts: PackedVector3Array = data["vertices"]
			for t in range(0, verts.size(), 3):
				var c := (verts[t] + verts[t + 1] + verts[t + 2]) / 3.0
				var ci := int(floor((origin.x + c.x - world.origin.x) / world.cell_size))
				var cj := int(floor((origin.z + c.z - world.origin.y) / world.cell_size))
				emitted[Vector2i(ci, cj)] = true
	for j in world.height - 1:
		for i in w - 1:
			var a := j * w + i
			if world.land_mask[a] == 0 and world.land_mask[a + 1] == 0 \
					and world.land_mask[a + w] == 0 and world.land_mask[a + w + 1] == 0:
				continue
			# Kara köşesi taşıyan hücre: ya üçgen var ya da (bozuk veride) tüm köşeler su altında → delik.
			if not emitted.has(Vector2i(i, j)):
				violations.append("hücre (%d,%d) kara köşesi taşıyor ama kara üçgeni yok" % [i, j])
	return violations
