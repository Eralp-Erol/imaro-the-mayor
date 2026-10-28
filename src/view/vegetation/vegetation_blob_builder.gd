class_name VegetationBlobBuilder
extends RefCounted
## Hücre lekesi (HLOD) geometrisi (T-062 B1; T-057 Karar 5): SAF, deterministik, iş parçacığı güvenli (yalnız okur).
## Bir parça (chunk = chunk_cells x chunk_cells hücre) için tek birleşik mesh verisi üretir: her 256 m hücrede
## ağaçlar `blob_clump_m` ızgarasında KÜMELENİR; küme = alçak çokgenli tek kütle (halka profili `blob.shapes`,
## `blob_sides` kenar). Kütle yarıçapı = taç alanları toplamından, yüksekliği alan ağırlıklı ortalama yükseklikten; renk
## alan ağırlıklı baskın türün atlastan piştirilmiş ana rengi (küme başına deterministik küçük değer sapması).
## Bireysel ağaç proxy'si DEĞİL (reddedildi): küme birden çok ağacı tek kütlede toplar. Düz gölgelenmiş (üçgen başına
## normal), indekssiz üçgen listesi. Köşeler PARÇA KÖŞESİNE göre yereldir (düğüm parça köşesinde durur).

const TWO_PI := 6.283185307179586


## Birikim kabı (Dictionary içinde Packed dizi `as` ile kopyalanır; alanlar doğrudan değiştirilir).
class _Acc:
	extends RefCounted
	var vertices: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var colors: PackedColorArray = PackedColorArray()
	var tris: int = 0
	var clumps: int = 0
	var trees: int = 0


## Dönüş: {"vertices", "normals", "colors", "tris", "clumps", "trees"} (hepsi yerel koordinat).
static func build_chunk(layout: VegetationLayout, look: VegetationLook, config: VegetationViewConfig, chx: int,
		chz: int) -> Dictionary:
	var out := _Acc.new()
	var cols := layout.cols
	var cc := config.blob_chunk_cells
	var chunk_o := layout.chunk_origin(chx, chz, cc)
	for cz in range(chz * cc, (chz + 1) * cc):
		for cx in range(chx * cc, (chx + 1) * cc):
			if cx >= cols.cells_w or cz >= cols.cells_h:
				continue
			var k := layout.index_of_key(cz * cols.cells_w + cx)
			if k < 0:
				continue
			_build_cell(layout, look, config, k, chunk_o, out)
	return {"vertices": out.vertices, "normals": out.normals, "colors": out.colors, "tris": out.tris,
			"clumps": out.clumps, "trees": out.trees}


static func _build_cell(layout: VegetationLayout, look: VegetationLook, config: VegetationViewConfig, k: int,
		chunk_o: Vector2, out: _Acc) -> void:
	var cols := layout.cols
	var cell_key := cols.cell_keys[k]
	var cell_o := layout.cell_origin(cell_key)
	var s_count := look.count
	# kümeler: alt-ızgara anahtarı -> sıra no; düz diziler (ekleme sırası = ilk görülme sırası).
	var index_of: Dictionary = {}
	var area_sum := PackedFloat32Array()
	var wx := PackedFloat32Array()
	var wz := PackedFloat32Array()
	var wy := PackedFloat32Array()
	var wh := PackedFloat32Array()
	var sp_area := PackedFloat32Array()
	var trees := 0
	for i in range(cols.cell_start[k], cols.cell_start[k + 1]):
		var sp := cols.species[i]
		if look.blob_on[sp] != 1:
			continue
		var sc := cols.scale[i]
		var crown_r := look.reach_m[sp] * look.radius_frac[sp] * sc
		var area := PI * crown_r * crown_r
		var sub := int(floor((cols.x[i] - cell_o.x) / config.blob_clump_m)) \
				+ 128 * int(floor((cols.z[i] - cell_o.y) / config.blob_clump_m))
		var c: int
		if index_of.has(sub):
			c = index_of[sub]
		else:
			c = area_sum.size()
			index_of[sub] = c
			area_sum.append(0.0)
			wx.append(0.0)
			wz.append(0.0)
			wy.append(0.0)
			wh.append(0.0)
			sp_area.resize(sp_area.size() + s_count)
		area_sum[c] += area
		wx[c] += cols.x[i] * area
		wz[c] += cols.z[i] * area
		wy[c] += layout.y[i] * area
		wh[c] += look.height_m[sp] * sc * area
		sp_area[c * s_count + sp] += area
		trees += 1
	out.trees += trees
	for c in area_sum.size():
		var a := area_sum[c]
		var dominant := 0
		var best := -1.0
		for sp in s_count:
			if sp_area[c * s_count + sp] > best:
				best = sp_area[c * s_count + sp]
				dominant = sp
		var radius := clampf(sqrt(a / PI) * config.blob_radius_mult, config.blob_min_clump_radius_m,
				config.blob_max_clump_radius_m)
		var px := wx[c] / a
		var pz := wz[c] / a
		var ground := wy[c] / a
		var height := wh[c] / a
		var h1 := _hash01(cell_key, c, 1)
		var h2 := _hash01(cell_key, c, 2)
		var color := look.blob_color[dominant]
		var v := 1.0 + (h1 * 2.0 - 1.0) * config.blob_value_jitter
		color = Color(clampf(color.r * v, 0.0, 1.0), clampf(color.g * v, 0.0, 1.0), clampf(color.b * v, 0.0, 1.0), 1.0)
		_emit_clump(out, look.shape_rings[dominant] as Array, config.blob_sides, Vector3(px - chunk_o.x, ground,
				pz - chunk_o.y), radius, height, look.crown_base_frac[dominant], config.blob_sink_m, h2 * TWO_PI, color)
		out.clumps += 1


## Tek küme: taban kapağı + halkalar arası şeritler + tepe. `rings`: Array[Vector2](yarıçap oranı, t in [0,1)).
static func _emit_clump(out: _Acc, rings: Array, sides: int, base: Vector3, radius: float, height: float,
		base_frac: float, sink_m: float, yaw0: float, color: Color) -> void:
	if rings.is_empty() or height <= 0.0:
		return
	var crown_base := base_frac * height
	var y_bottom := base.y + crown_base - (sink_m if base_frac <= 0.0 else 0.0)
	var y_top := base.y + height
	var span := y_top - y_bottom
	var center := Vector3(base.x, y_bottom + span * 0.4, base.z)
	var ring_pts: Array[PackedVector3Array] = []
	for r: Vector2 in rings:
		var pts := PackedVector3Array()
		for s in sides:
			var ang := yaw0 + TWO_PI * float(s) / float(sides)
			pts.append(Vector3(base.x + cos(ang) * radius * r.x, y_bottom + span * r.y, base.z + sin(ang) * radius * r.x))
		ring_pts.append(pts)
	var bottom_center := Vector3(base.x, y_bottom, base.z)
	var apex := Vector3(base.x, y_top, base.z)
	var first := ring_pts[0]
	for s in sides:
		_tri(out, bottom_center, first[s], first[(s + 1) % sides], center, color)
	for j in ring_pts.size() - 1:
		var lo := ring_pts[j]
		var hi := ring_pts[j + 1]
		for s in sides:
			var s2 := (s + 1) % sides
			_tri(out, lo[s], hi[s], hi[s2], center, color)
			_tri(out, lo[s], hi[s2], lo[s2], center, color)
	var top := ring_pts[ring_pts.size() - 1]
	for s in sides:
		_tri(out, top[s], apex, top[(s + 1) % sides], center, color)


## Üçgen ekler; sargı Godot ön yüzüne (saat yönü, dışarıdan bakınca) çevrilir, düz normal DIŞARI bakar.
static func _tri(out: _Acc, a: Vector3, b: Vector3, c: Vector3, center: Vector3, color: Color) -> void:
	var n := (b - a).cross(c - a)
	if n.length_squared() < 1.0e-12:
		return
	var mid := (a + b + c) / 3.0
	var outward := n.dot(mid - center) > 0.0   # saat yönü DEĞİL (CCW dışarıdan): b/c değiştir
	if outward:
		var t := b
		b = c
		c = t
		n = -n
	var nrm := (-n).normalized()
	out.vertices.append_array(PackedVector3Array([a, b, c]))
	out.normals.append_array(PackedVector3Array([nrm, nrm, nrm]))
	out.colors.append_array(PackedColorArray([color, color, color]))
	out.tris += 1


## Tamsayı karması -> [0, 1) (küresel rastgelelik yok; küme sapması deterministik).
static func _hash01(a: int, b: int, salt: int) -> float:
	var h := (a * 73856093) ^ (b * 19349663) ^ (salt * 83492791)
	h = (h ^ (h >> 13)) * 1274126177
	h = (h ^ (h >> 16)) & 0x7FFFFFFF
	return float(h % 100003) / 100003.0
