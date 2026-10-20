class_name BuildingChunkPlan
extends RefCounted
## BuildingColumns -> chunk bölmesi (T-012 ölçüt 1; ADR-0001 karar 3: 1 km chunk). Saf ve başsız: yalnız indeks
## gruplaması ve içerik özeti; mesh/düğüm yok.
##
## Hücre anahtarı = floor((konum - dünya_origin) / cell_m) (Vector2i). Süper-chunk (HLOD2) = hücre anahtarının
## `super_cells` ile TAM BÖLÜMÜ (negatif konumlar da düzgün: floori). Hücre içi indeksler SÜTUN SIRASINDA tutulur;
## bir hücrenin içerik özeti (`cell_hashes`) yalnız o hücredeki yapıların render'a etki eden alanlarından hesaplanır ->
## sim değişiminde yalnız özeti değişen hücreler yeniden kurulur (`changed_cells`).

var cell_m: float = 1000.0
var super_cells: int = 4
var origin: Vector2 = Vector2.ZERO
## Vector2i -> PackedInt32Array (sütun indeksleri).
var cells: Dictionary = {}
var count: int = 0


static func build(cols: BuildingColumns, plan_origin: Vector2, p_cell_m: float, p_super_cells: int = 4) \
		-> BuildingChunkPlan:
	var plan := BuildingChunkPlan.new()
	plan.cell_m = maxf(p_cell_m, 1.0)
	plan.super_cells = maxi(p_super_cells, 1)
	plan.origin = plan_origin
	plan.count = cols.count
	# Packed* diziler değer gibi kopyalanır (sözlükten `as` ile alınan kopya üstünde append sonuç vermez):
	# önce referans tipi Array'e topla, sonra paketle.
	var buckets: Dictionary = {}
	for i in cols.count:
		var key := plan.cell_of(cols.x[i], cols.z[i])
		if not buckets.has(key):
			buckets[key] = []
		(buckets[key] as Array).append(i)
	for key: Vector2i in buckets:
		plan.cells[key] = PackedInt32Array(buckets[key] as Array)
	return plan


func cell_of(x: float, z: float) -> Vector2i:
	return Vector2i(floori((x - origin.x) / cell_m), floori((z - origin.y) / cell_m))


## Hücrenin dünya köşesi (en küçük x, z).
func cell_origin(key: Vector2i) -> Vector2:
	return origin + Vector2(key) * cell_m


func super_of(key: Vector2i) -> Vector2i:
	return Vector2i(floori(float(key.x) / float(super_cells)), floori(float(key.y) / float(super_cells)))


func super_origin(skey: Vector2i) -> Vector2:
	return origin + Vector2(skey) * cell_m * float(super_cells)


## Sıralı hücre anahtarları (x sonra z): kurulum sırası deterministik.
func keys() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for k: Vector2i in cells:
		out.append(k)
	out.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x < b.x or (a.x == b.x and a.y < b.y))
	return out


func indices(key: Vector2i) -> PackedInt32Array:
	return cells.get(key, PackedInt32Array())


## Sıralı süper-chunk anahtarları -> o süper-chunk'ın hücre anahtarları.
func super_groups() -> Dictionary:
	var groups: Dictionary = {}
	for k in keys():
		var sk := super_of(k)
		if not groups.has(sk):
			groups[sk] = [] as Array[Vector2i]
		(groups[sk] as Array[Vector2i]).append(k)
	return groups


## Hücre içerik özeti (SHA-256 hex): render'a etki eden alanlar (modül, konum, yön, renk satırları, parlaklık).
## `parcel_id`, `floors`, `flags`, `era` render'ı değiştirmez -> özete girmez.
func cell_hash(cols: BuildingColumns, key: Vector2i) -> String:
	var idx := indices(key)
	var m := PackedInt32Array()
	var xs := PackedFloat32Array()
	var zs := PackedFloat32Array()
	var ys := PackedFloat32Array()
	var rows := PackedByteArray()
	for i in idx:
		m.append(cols.module_idx[i])
		xs.append(cols.x[i])
		zs.append(cols.z[i])
		ys.append(cols.yaw[i])
		rows.append(cols.wall_row[i])
		rows.append(cols.roof_row[i])
		rows.append(cols.accent_row[i])
		rows.append(cols.bright[i])
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(PackedByteArray([idx.size() & 255, (idx.size() >> 8) & 255, (idx.size() >> 16) & 255, 1]))
	for part: PackedByteArray in [m.to_byte_array(), xs.to_byte_array(), zs.to_byte_array(), ys.to_byte_array(), rows]:
		if not part.is_empty():
			ctx.update(part)
	return ctx.finish().hex_encode()


func cell_hashes(cols: BuildingColumns) -> Dictionary:
	var out: Dictionary = {}
	for k in keys():
		out[k] = cell_hash(cols, k)
	return out


## Eski ve yeni özet sözlükleri arasında farklı/yeni/silinen hücre anahtarları (sıralı).
static func changed_cells(old_hashes: Dictionary, new_hashes: Dictionary) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for k: Vector2i in new_hashes:
		if not old_hashes.has(k) or old_hashes[k] != new_hashes[k]:
			out.append(k)
	for k: Vector2i in old_hashes:
		if not new_hashes.has(k):
			out.append(k)
	out.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x < b.x or (a.x == b.x and a.y < b.y))
	return out
