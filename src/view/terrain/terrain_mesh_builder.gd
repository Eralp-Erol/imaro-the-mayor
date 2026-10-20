class_name TerrainMeshBuilder
extends RefCounted
## WorldData → chunk mesh VERİSİ (T-001 ölçüt 4, WLD-01, TEK-03). Render'dan bağımsız: yalnız Packed*Array üretir
## (dummy renderer'da ve iş parçacıklarında çalışır); ArrayMesh/MeshInstance3D kurulumu TerrainView'dadır.
##
## Tasarım:
## - Chunk = `chunk_cells` x `chunk_cells` hücre (varsayılan 40 hücre = 4 km); komşu chunk'lar sınır örneklerini
##   PAYLAŞIR
##   (aynı WorldData örneği → aynı yükseklik → dikişte delik/basamak yok). Köşe konumları chunk'ın kuzeybatı köşesine
##   göre yereldir (y = dünya y'si); düğüm konumu `chunk_origin()`.
## - Kara: indekssiz üçgen listesi, ÜÇGEN BAŞINA düz normal (flat-shaded), hücre başına renk (TerrainPalette);
##   köşegen yönü yükseklik farkına göre.
##   Tamamen deniz seviyesinin altındaki üçgenler ATILIR (opak su yüzeyi örter) → üçgen sayısı ~yarıya iner.
## - Su: deniz seviyesinde düz yüzey; en az bir köşesi su olan hücreler; köşe rengi kıyı mesafesinden (sığ → derin).
## - Dünya sınırlarında etek (skirt): "boş sınır" yerine kapalı blok; metro dışı dünya sonraki işlerdir.
## Tüm fonksiyonlar saf ve salt okunurdur.

const SKIRT_BOTTOM_Y := -260.0
## Köşegen seçiminde ana köşegene tanınan önyargı (hücre aralığının metre başına yüksekliği; 100 m hücrede 2 m).
const DIAGONAL_BIAS_PER_M := 0.02
const SKIRT_WATER_TOP_TINT := Color(0.02, 0.07, 0.15)


## Toplam chunk sayısı (x, z).
static func chunk_counts(world: WorldData, chunk_cells: int) -> Vector2i:
	return Vector2i(ceili(float(world.width - 1) / chunk_cells), ceili(float(world.height - 1) / chunk_cells))


## Chunk'ın kapsadığı hücre aralığı (hücre indeksi; bitiş hariç). Son chunk kırpılır.
static func chunk_cell_rect(world: WorldData, cx: int, cz: int, chunk_cells: int) -> Rect2i:
	var i0 := cx * chunk_cells
	var j0 := cz * chunk_cells
	var i1 := mini(i0 + chunk_cells, world.width - 1)
	var j1 := mini(j0 + chunk_cells, world.height - 1)
	return Rect2i(i0, j0, i1 - i0, j1 - j0)


## Chunk düğümünün dünya konumu (kuzeybatı köşesi, y = 0).
static func chunk_origin(world: WorldData, cx: int, cz: int, chunk_cells: int) -> Vector3:
	var p := world.cell_to_world(cx * chunk_cells, cz * chunk_cells)
	return Vector3(p.x, 0.0, p.y)


## Kara chunk'ı. `stride` > 1: kaba LOD (her `stride` örnekten biri; etek yok sayılmaz). `shading_exaggeration` YALNIZ
## düz normallerin eğimini büyütür (hillshade z-faktörü); geometri gerçek yükseklikte kalır. Dönüş:
## {"vertices": PackedVector3Array, "normals": PackedVector3Array, "colors": PackedColorArray, "triangles": int}
static func build_land(world: WorldData, palette: TerrainPalette, cx: int, cz: int, chunk_cells: int,
		stride: int = 1, skirts: bool = true, shading_exaggeration: float = 1.0) -> Dictionary:
	var rect := chunk_cell_rect(world, cx, cz, chunk_cells)
	var i0 := rect.position.x
	var j0 := rect.position.y
	var i1 := rect.end.x
	var j1 := rect.end.y
	var w := world.width
	var cell := world.cell_size
	var sea := world.sea_level
	var span := cell * stride
	var origin := chunk_origin(world, cx, cz, chunk_cells)
	var max_tris := ((i1 - i0) * (j1 - j0) * 2) / (stride * stride) + 8 * (i1 - i0 + j1 - j0) / stride + 16
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	verts.resize(max_tris * 3)
	normals.resize(max_tris * 3)
	colors.resize(max_tris * 3)
	var n := 0
	var heights := world.heights
	var shore := world.shore_distance
	for j in range(j0, j1, stride):
		var jn := mini(j + stride, j1)
		var z0 := (j - j0) * cell
		var z1 := (jn - j0) * cell
		for i in range(i0, i1, stride):
			var inx := mini(i + stride, i1)
			var x0 := (i - i0) * cell
			var x1 := (inx - i0) * cell
			var a := j * w + i
			var b := j * w + inx
			var c := jn * w + i
			var d := jn * w + inx
			var h00 := heights[a]
			var h10 := heights[b]
			var h01 := heights[c]
			var h11 := heights[d]
			if maxf(maxf(h00, h10), maxf(h01, h11)) < sea:
				continue
			var p00 := Vector3(x0, h00, z0)
			var p10 := Vector3(x1, h10, z0)
			var p01 := Vector3(x0, h01, z1)
			var p11 := Vector3(x1, h11, z1)
			var gx := ((h10 + h11) - (h00 + h01)) * 0.5 / span
			var gz := ((h01 + h11) - (h00 + h10)) * 0.5 / span
			var slope := rad_to_deg(atan(sqrt(gx * gx + gz * gz)))
			var elev := (h00 + h10 + h01 + h11) * 0.25 - sea
			var sd := (shore[a] + shore[b] + shore[c] + shore[d]) * 0.25
			var wx := origin.x + (x0 + x1) * 0.5
			var wz := origin.z + (z0 + z1) * 0.5
			var col := palette.land_color(elev, slope, sd, a, wx, wz)
			# Köşegen: yükseklik farkı belirgin biçimde küçük olan çapraz (yüzey daha az kırılır). Önyargı: düz/rampa
			# alanda gürültü yüzünden yön sürekli değişip şerit (corduroy) deseni oluşturmasın.
			if absf(h00 - h11) <= absf(h10 - h01) + DIAGONAL_BIAS_PER_M * span:
				n = _emit_land_tri(p00, p10, p11, col, sea, shading_exaggeration, verts, normals, colors, n)
				n = _emit_land_tri(p00, p11, p01, col, sea, shading_exaggeration, verts, normals, colors, n)
			else:
				n = _emit_land_tri(p00, p10, p01, col, sea, shading_exaggeration, verts, normals, colors, n)
				n = _emit_land_tri(p10, p11, p01, col, sea, shading_exaggeration, verts, normals, colors, n)
	if skirts:
		n = _add_skirts(world, rect, stride, verts, normals, colors, n)
	verts.resize(n * 3)
	normals.resize(n * 3)
	colors.resize(n * 3)
	return {"vertices": verts, "normals": normals, "colors": colors, "triangles": n}


## Su chunk'ı (indeksli, düz yüzey). Dönüş:
## {"vertices": PackedVector3Array, "normals": PackedVector3Array, "colors": PackedColorArray,
##  "indices": PackedInt32Array, "triangles": int}; su yoksa triangles = 0.
static func build_water(world: WorldData, cx: int, cz: int, chunk_cells: int) -> Dictionary:
	var rect := chunk_cell_rect(world, cx, cz, chunk_cells)
	var i0 := rect.position.x
	var j0 := rect.position.y
	var i1 := rect.end.x
	var j1 := rect.end.y
	var w := world.width
	var cell := world.cell_size
	var sea := world.sea_level
	var heights := world.heights
	var indices := PackedInt32Array()
	var any_water := false
	var local_w := i1 - i0 + 1
	var used := PackedByteArray()
	used.resize(local_w * (j1 - j0 + 1))
	for j in range(j0, j1):
		for i in range(i0, i1):
			var a := j * w + i
			if heights[a] < sea or heights[a + 1] < sea or heights[a + w] < sea or heights[a + w + 1] < sea:
				any_water = true
				var l00 := (j - j0) * local_w + (i - i0)
				var l10 := l00 + 1
				var l01 := l00 + local_w
				var l11 := l01 + 1
				used[l00] = 1
				used[l10] = 1
				used[l01] = 1
				used[l11] = 1
				indices.append_array(PackedInt32Array([l00, l10, l11, l00, l11, l01]))
	if not any_water:
		return {"vertices": PackedVector3Array(), "normals": PackedVector3Array(), "colors": PackedColorArray(),
			"indices": indices, "triangles": 0}
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var count := local_w * (j1 - j0 + 1)
	verts.resize(count)
	normals.resize(count)
	colors.resize(count)
	for j in range(j0, j1 + 1):
		for i in range(i0, i1 + 1):
			var l := (j - j0) * local_w + (i - i0)
			if used[l] == 0:
				continue
			var idx := j * w + i
			verts[l] = Vector3((i - i0) * cell, sea, (j - j0) * cell)
			normals[l] = Vector3.UP
			colors[l] = TerrainPalette.water_color(world.shore_distance[idx], sea - heights[idx])
	return {"vertices": verts, "normals": normals, "colors": colors, "indices": indices,
		"triangles": indices.size() / 3}


## Dünya sınırındaki chunk kenarları için dikey etek (kapalı blok). Dönüş: yeni üçgen sayısı toplamı.
static func _add_skirts(world: WorldData, rect: Rect2i, stride: int, verts: PackedVector3Array,
		normals: PackedVector3Array, colors: PackedColorArray, n_in: int) -> int:
	var n := n_in
	var i0 := rect.position.x
	var j0 := rect.position.y
	var i1 := rect.end.x
	var j1 := rect.end.y
	# Kenar: [sabit eksen ("x"/"z"), sabit indeks, boyunca başlangıç, boyunca bitiş, dışa yön]
	var edges: Array = []
	if i0 == 0:
		edges.append([true, 0, j0, j1, Vector3(-1, 0, 0)])
	if i1 == world.width - 1:
		edges.append([true, i1, j0, j1, Vector3(1, 0, 0)])
	if j0 == 0:
		edges.append([false, 0, i0, i1, Vector3(0, 0, -1)])
	if j1 == world.height - 1:
		edges.append([false, j1, i0, i1, Vector3(0, 0, 1)])
	for e in edges:
		var fixed_is_i: bool = e[0]
		var fixed: int = e[1]
		var a0: int = e[2]
		var a1: int = e[3]
		var outward: Vector3 = e[4]
		for a in range(a0, a1, stride):
			var b := mini(a + stride, a1)
			var pa := _skirt_top(world, fixed_is_i, fixed, a, i0, j0)
			var pb := _skirt_top(world, fixed_is_i, fixed, b, i0, j0)
			var qa := Vector3(pa.x, SKIRT_BOTTOM_Y, pa.z)
			var qb := Vector3(pb.x, SKIRT_BOTTOM_Y, pb.z)
			var sea := world.sea_level
			var ia := (a * world.width + fixed) if fixed_is_i else (fixed * world.width + a)
			var ib := (b * world.width + fixed) if fixed_is_i else (fixed * world.width + b)
			var under := world.heights[ia] < sea and world.heights[ib] < sea
			var col := SKIRT_WATER_TOP_TINT if under else TerrainPalette.SKIRT_EARTH
			n = _add_wall_tri(pa, pb, qb, outward, col, verts, normals, colors, n)
			n = _add_wall_tri(pa, qb, qa, outward, col, verts, normals, colors, n)
	return n


## Etek üst köşesi (chunk yerel koordinatı): kara yüksekliği ya da deniz seviyesi (hangisi yüksekse).
static func _skirt_top(world: WorldData, fixed_is_i: bool, fixed: int, along: int, i0: int, j0: int) -> Vector3:
	var i := fixed if fixed_is_i else along
	var j := along if fixed_is_i else fixed
	var h := maxf(world.heights[j * world.width + i], world.sea_level)
	return Vector3((i - i0) * world.cell_size, h, (j - j0) * world.cell_size)


## Kara üçgeni: tamamı deniz seviyesinin altındaysa atılır (opak su örter). Düz normal.
static func _emit_land_tri(p0: Vector3, p1: Vector3, p2: Vector3, col: Color, sea: float, k_shade: float,
		verts: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray, n: int) -> int:
	if maxf(maxf(p0.y, p1.y), p2.y) < sea:
		return n
	var e1 := p2 - p0
	var e2 := p1 - p0
	e1.y *= k_shade
	e2.y *= k_shade
	var nrm := e1.cross(e2).normalized()
	var k := n * 3
	verts[k] = p0
	verts[k + 1] = p1
	verts[k + 2] = p2
	normals[k] = nrm
	normals[k + 1] = nrm
	normals[k + 2] = nrm
	colors[k] = col
	colors[k + 1] = col
	colors[k + 2] = col
	return n + 1


## Üçgeni `outward` yönüne bakacak (saat yönünde) biçimde ekler.
static func _add_wall_tri(p0: Vector3, p1: Vector3, p2: Vector3, outward: Vector3, col: Color,
		verts: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray, n: int) -> int:
	var nrm := (p2 - p0).cross(p1 - p0)
	if nrm.length_squared() < 1e-9:
		return n
	nrm = nrm.normalized()
	var a := p0
	var b := p1
	var c := p2
	if nrm.dot(outward) < 0.0:
		b = p2
		c = p1
		nrm = -nrm
	var k := n * 3
	verts[k] = a
	verts[k + 1] = b
	verts[k + 2] = c
	normals[k] = nrm
	normals[k + 1] = nrm
	normals[k + 2] = nrm
	colors[k] = col
	colors[k + 1] = col
	colors[k + 2] = col
	return n + 1
