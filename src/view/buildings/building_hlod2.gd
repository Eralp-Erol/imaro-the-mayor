class_name BuildingHlod2
extends RefCounted
## HLOD2 (T-012 ölçüt 2; kit spec §7.2): süper-chunk başına TEK mesh, kent KÜTLELERİ. SAF ve iş parçacığı güvenli.
##
## Kurallar (spec "HLOD kuralları"): (1) düz slab yok: kütle `hlod2_cell_m` ızgarasında ve YÜKSEKLİK KADEMESİNDE
## kümelenir, her kutu kendi yüksekliğini taşır; (2) renk ORTALAMA değil, kümedeki bir duvar/çatı SATIRIdır:
## varsayılan alan ağırlıklı ÖRNEKLEME (kütle anahtarından türeyen deterministik; her satır alanı kadar
## şansla, böylece kent tek gri/kahveye inmez, metro genelinde satır dağılımı korunur);
## `hlod2_sample_colors = false` ise alan ağırlıklı BASKIN;
## (3) landmark ve en yüksek %10 yapı ayrı (yönlü) kutu olarak korunur -> silüet/yükseklik sırası; (4) renkler aynı
## paletten (BuildingKit.shaded) -> LOD1 <-> HLOD'da ton kayması yok.
## Kutu: tabanı açık, 4 yan (duvar rengi) + üst (çatı rengi); alt kenar tabandan SKIRT_M aşağıda (yamaçta havada kalma
## yok).

const SKIRT_M := 3.0
const MIN_BOX_M := 3.0
## Kaplama oranı kareköküne çarpan ve alt sınır: sınır kutusu bu oranda daralır.
const COVER_GAIN := 1.1
const MIN_SHRINK := 0.45


class Mass:
	extends RefCounted
	var xmin: float = INF
	var xmax: float = -INF
	var zmin: float = INF
	var zmax: float = -INF
	var low_y: float = INF
	var top_weighted: float = 0.0
	var area: float = 0.0
	var wall_area: Dictionary = {}
	var roof_area: Dictionary = {}

	func add(corners: PackedVector2Array, ground_y: float, top_y: float, a: float, wall: int, roof: int) -> void:
		for c in corners:
			xmin = minf(xmin, c.x)
			xmax = maxf(xmax, c.x)
			zmin = minf(zmin, c.y)
			zmax = maxf(zmax, c.y)
		low_y = minf(low_y, ground_y)
		top_weighted += top_y * a
		area += a
		wall_area[wall] = float(wall_area.get(wall, 0.0)) + a
		roof_area[roof] = float(roof_area.get(roof, 0.0)) + a

	func top_y() -> float:
		return top_weighted / maxf(area, 0.001)

	func dominant(table: Dictionary) -> int:
		var best := -1
		var best_a := -1.0
		var rows: Array = table.keys()
		rows.sort()
		for r: int in rows:
			if float(table[r]) > best_a:
				best_a = float(table[r])
				best = r
		return best

	## Alan ağırlıklı deterministik örnekleme: `u` [0, 1) (kütle anahtarından).
	func sampled(table: Dictionary, u: float) -> int:
		var rows: Array = table.keys()
		rows.sort()
		var total := 0.0
		for r: int in rows:
			total += float(table[r])
		var at := u * total
		for r: int in rows:
			at -= float(table[r])
			if at < 0.0:
				return r
		return rows[rows.size() - 1]


## `cells`: süper-chunk içindeki BuildingCellData listesi. Dönüş: {vertices, normals, colors, boxes, masses} ya da boş
## sözlük (yapı yok). Köşeler `origin`'e göreli.
static func build(cells: Array, cols: BuildingColumns, kit: BuildingKit, config: BuildingViewConfig,
		origin: Vector2) -> Dictionary:
	var items: Array[Dictionary] = []
	for cd: BuildingCellData in cells:
		for j in cd.kept.size():
			var i := cd.kept[j]
			var m := cols.module_idx[i]
			var top := cd.base_y[j] + kit.height_m[m]
			items.append({"i": i, "m": m, "ground": cd.base_y[j], "top": top, "h": kit.height_m[m]})
	if items.is_empty():
		return {}
	# En yüksek %N ayrı kalır (yükseklik azalan, eşitlikte sütun indeksi artan: deterministik).
	var order := items.duplicate()
	order.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["h"]) > float(b["h"]) or (is_equal_approx(float(a["h"]), float(b["h"])) and int(a["i"]) < int(b["i"])))
	var keep_n := int(ceil(float(order.size()) * config.hlod2_keep_top_share))
	var singles: Dictionary = {}
	for k in keep_n:
		singles[int((order[k] as Dictionary)["i"])] = true
	var masses: Dictionary = {}
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var boxes := 0
	var cell := maxf(config.hlod2_cell_m, 8.0)
	for it in items:
		var i: int = it["i"]
		var m: int = it["m"]
		var corners := footprint_corners(cols.x[i], cols.z[i], cols.yaw[i], kit.footprint_w[m], kit.footprint_d[m])
		var area := kit.footprint_w[m] * kit.footprint_d[m]
		if singles.has(i) or kit.is_landmark[m] == 1:
			var single := Mass.new()
			single.add(corners, float(it["ground"]), float(it["top"]), area, cols.wall_row[i], cols.roof_row[i])
			boxes += _emit_box(verts, normals, colors, single, kit, origin, corners, false, 0)
			continue
		var tier := 0
		for edge in config.hlod2_tier_edges_m:
			if float(it["h"]) >= edge:
				tier += 1
		var gx := floori(cols.x[i] / cell)
		var gz := floori(cols.z[i] / cell)
		var mk := (gx * 65536 + gz) * 4 + tier
		if not masses.has(mk):
			masses[mk] = Mass.new()
		(masses[mk] as Mass).add(corners, float(it["ground"]), float(it["top"]), area, cols.wall_row[i],
				cols.roof_row[i])
	var mass_keys: Array = masses.keys()
	mass_keys.sort()
	for mk: int in mass_keys:
		boxes += _emit_box(verts, normals, colors, masses[mk] as Mass, kit, origin, PackedVector2Array(),
				config.hlod2_sample_colors, mk)
	return {"vertices": verts, "normals": normals, "colors": colors, "boxes": boxes, "masses": masses.size()}


## Yönlü ayak izi köşeleri (dünya x, z): yerel +Z cephe, Basis(UP, yaw).
static func footprint_corners(x: float, z: float, yaw: float, w: float, d: float) -> PackedVector2Array:
	var c := cos(yaw)
	var s := sin(yaw)
	var out := PackedVector2Array()
	for p in [Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(0.5, 0.5), Vector2(-0.5, 0.5)]:
		var lx: float = p.x * w
		var lz: float = p.y * d
		out.append(Vector2(x + lx * c + lz * s, z - lx * s + lz * c))
	return out


## Kutu ekler: `oriented` doluysa 4 köşe (yönlü), yoksa kütlenin eksen hizalı sınırı. Dönüş: eklenen kutu sayısı.
static func _emit_box(verts: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray, mass: Mass,
		kit: BuildingKit, origin: Vector2, oriented: PackedVector2Array, sample: bool, mass_key: int) -> int:
	var quad := oriented
	if quad.is_empty():
		var x0 := mass.xmin
		var x1 := maxf(mass.xmax, x0 + MIN_BOX_M)
		var z0 := mass.zmin
		var z1 := maxf(mass.zmax, z0 + MIN_BOX_M)
		# Kütle sınır kutusu sokak/avluyu da kapsar: kaplama oranına göre merkezden daralır (zemin görünsün, kent
		# düz plaka olmasın; spec ret ölçütü 1). Tek yapılı kümeler daralmaz.
		var cover := clampf(mass.area / maxf((x1 - x0) * (z1 - z0), 1.0), 0.0, 1.0)
		var shrink := clampf(sqrt(cover) * COVER_GAIN, MIN_SHRINK, 1.0)
		var cx := (x0 + x1) * 0.5
		var cz := (z0 + z1) * 0.5
		var hx := (x1 - x0) * 0.5 * shrink
		var hz := (z1 - z0) * 0.5 * shrink
		x0 = cx - hx
		x1 = cx + hx
		z0 = cz - hz
		z1 = cz + hz
		quad = PackedVector2Array([Vector2(x0, z0), Vector2(x1, z0), Vector2(x1, z1), Vector2(x0, z1)])
	var y0 := mass.low_y - SKIRT_M
	var y1 := maxf(mass.top_y(), mass.low_y + 2.0)
	var wall_row := mass.dominant(mass.wall_area)
	var roof_row := mass.dominant(mass.roof_area)
	if sample:
		wall_row = mass.sampled(mass.wall_area, _unit_hash(mass_key, 1))
		roof_row = mass.sampled(mass.roof_area, _unit_hash(mass_key, 2))
	var wall_c := kit.shaded(wall_row, 1.0)
	var roof_c := kit.shaded(roof_row, 1.0)
	var o := Vector3(origin.x, 0.0, origin.y)
	var base: Array[Vector3] = []
	for q in quad:
		base.append(Vector3(q.x, y0, q.y) - o)
	var top: Array[Vector3] = []
	for q in quad:
		top.append(Vector3(q.x, y1, q.y) - o)
	var centre := Vector3(0.0, 0.0, 0.0)
	for b in base:
		centre += b
	centre /= 4.0
	for k in 4:
		var k2 := (k + 1) % 4
		var edge := base[k2] - base[k]
		var n := Vector3(edge.z, 0.0, -edge.x).normalized()
		var mid := (base[k] + base[k2]) * 0.5
		if n.dot(mid - centre) < 0.0:
			n = -n
		_emit_tri(verts, normals, colors, base[k], top[k], top[k2], n, wall_c)
		_emit_tri(verts, normals, colors, base[k], top[k2], base[k2], n, wall_c)
	_emit_tri(verts, normals, colors, top[0], top[1], top[2], Vector3.UP, roof_c)
	_emit_tri(verts, normals, colors, top[0], top[2], top[3], Vector3.UP, roof_c)
	return 1


## Anahtardan [0, 1) deterministik sayı (RNG durumu yok: iş parçacığı güvenli).
static func _unit_hash(key: int, salt: int) -> float:
	var h := (key * 73856093) ^ (salt * 19349663)
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return float(h & 0xFFFFFF) / float(0x1000000)


## Üçgen ekler; Godot ön yüz = saat yönü: (b-a)x(c-a) normalle AYNI yöne bakıyorsa b/c değiştirilir.
static func _emit_tri(verts: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray,
		a: Vector3, b: Vector3, c: Vector3, n: Vector3, color: Color) -> void:
	var p1 := b
	var p2 := c
	if (b - a).cross(c - a).dot(n) > 0.0:
		p1 = c
		p2 = b
	verts.append(a)
	verts.append(p1)
	verts.append(p2)
	for k in 3:
		normals.append(n)
		colors.append(color)
