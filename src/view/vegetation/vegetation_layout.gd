class_name VegetationLayout
extends RefCounted
## B0 sütunlarının görünüm tarafı eki (T-062 B1): örnek başına zemin yüksekliği (`WorldData.height_at`, yapı/arazi
## deseni ile aynı kaynak) ve hücre başına sınır kutusu (y aralığı = zemin dibi .. tepe), PROXY'li tür sayısı. SAF ve
## iş parçacığı güvenli (yalnız okur); aynı sütun + dünya -> aynı çıktı (determinizm). Sütunları DEĞİŞTİRMEZ.
## Görünüm sütunlarla BİRE BİR eşlenir: `cols.count` örnek, `y.size() == cols.count`.

var cols: VegetationColumns = null
## Zemin yüksekliği (m), `cols` satırıyla aynı sıra (gövde tabanı; çöküntü `config.sink_m` yerleştirmede).
var y: PackedFloat32Array = PackedFloat32Array()
## Hücre dizini k (cell_keys sırası) -> kutu: ymin (en alçak zemin), ymax (en yüksek ağaç tepesi).
var cell_ymin: PackedFloat32Array = PackedFloat32Array()
var cell_ymax: PackedFloat32Array = PackedFloat32Array()
## Hücre dizini k -> bu hücrede PROXY'li (palmiye) örnek sayısı.
var cell_proxy_count: PackedInt32Array = PackedInt32Array()
var global_ymin: float = 0.0
var global_ymax: float = 0.0
## T-042 yol koridoru maskesi (GÖRÜNÜM katmanı; sütunlara ve sim'e dokunmaz): `cols` satırıyla aynı sıra, 1 = bu örnek
## gizli (yeni yolun koridorunda). BOŞ dizi = hiçbir örnek gizli değil (varsayılan; hızlı yol). Yazma YALNIZ
## `set_hidden`; iş parçacığı okuyan görünümler (leke işçileri) yazmadan önce BEKLETİLİR (`VegetationView`).
var hidden: PackedByteArray = PackedByteArray()
var hidden_count: int = 0

var _chunk_boxes: Dictionary = {}


## `height_m`/`has_proxy`: tür dizini başına tepe yüksekliği ve PROXY bayrağı (VegetationLook).
static func build(columns: VegetationColumns, world: WorldData, height_m: PackedFloat32Array,
		has_proxy: PackedByteArray) -> VegetationLayout:
	var lay := VegetationLayout.new()
	lay.cols = columns
	lay.y.resize(columns.count)
	for i in columns.count:
		lay.y[i] = world.height_at(columns.x[i], columns.z[i]) if world != null else 0.0
	var n := columns.cell_keys.size()
	lay.cell_ymin.resize(n)
	lay.cell_ymax.resize(n)
	lay.cell_proxy_count.resize(n)
	var gmin := INF
	var gmax := -INF
	for k in n:
		var lo := INF
		var hi := -INF
		var proxies := 0
		for i in range(columns.cell_start[k], columns.cell_start[k + 1]):
			var sp := columns.species[i]
			lo = minf(lo, lay.y[i])
			hi = maxf(hi, lay.y[i] + height_m[sp] * columns.scale[i])
			if has_proxy[sp] == 1:
				proxies += 1
		lay.cell_ymin[k] = lo
		lay.cell_ymax[k] = hi
		lay.cell_proxy_count[k] = proxies
		gmin = minf(gmin, lo)
		gmax = maxf(gmax, hi)
	lay.global_ymin = gmin if n > 0 else 0.0
	lay.global_ymax = gmax if n > 0 else 0.0
	return lay


## Satır `i` gizli mi (koridor maskesi). Maske boşsa her zaman false.
func is_hidden(i: int) -> bool:
	return not hidden.is_empty() and hidden[i] == 1


## Satır `i`nin hücre dizini k (`cell_start[k] <= i < cell_start[k + 1]`).
func cell_of_row(i: int) -> int:
	return cols.cell_start.bsearch(i, false) - 1


## Gizli satır kümesini (sıralı/sırasız, tekil olmayabilir) KÖKTEN kurar.
## Dönüş: maskesi değişen hücre dizinleri k (artan).
## Deterministik: aynı satır kümesi -> aynı maske; boş küme maskeyi tamamen kaldırır (hepsi geri gelir).
func set_hidden(rows: PackedInt32Array) -> PackedInt32Array:
	if rows.is_empty() and hidden.is_empty():
		return PackedInt32Array()
	var fresh := PackedByteArray()
	var count := 0
	if not rows.is_empty():
		fresh.resize(cols.count)
		for i in rows:
			if i >= 0 and i < cols.count and fresh[i] == 0:
				fresh[i] = 1
				count += 1
	var changed := {}
	if hidden.is_empty():
		for i in rows:
			if i >= 0 and i < cols.count:
				changed[cell_of_row(i)] = true
	elif fresh.is_empty():
		for i in cols.count:
			if hidden[i] == 1:
				changed[cell_of_row(i)] = true
	else:
		for i in cols.count:
			if hidden[i] != fresh[i]:
				changed[cell_of_row(i)] = true
	hidden = fresh
	hidden_count = count
	var out := PackedInt32Array(changed.keys())
	out.sort()
	return out


func cell_count() -> int:
	return cols.cell_keys.size()


## Hücre indeksi k (cell_keys içinde); yoksa -1.
func index_of_key(key: int) -> int:
	var at := cols.cell_keys.bsearch(key)
	if at >= cols.cell_keys.size() or cols.cell_keys[at] != key:
		return -1
	return at


func cell_cx(key: int) -> int:
	return key % cols.cells_w


@warning_ignore("integer_division")
func cell_cz(key: int) -> int:
	return key / cols.cells_w


## Hücre kuzeybatı köşesi (dünya xz).
func cell_origin(key: int) -> Vector2:
	return Vector2(cols.origin.x + float(cell_cx(key)) * cols.cell_m, cols.origin.y + float(cell_cz(key)) * cols.cell_m)


## Hücre sınır kutusu (dünya): xz hücre dikdörtgeni, y = zemin dibi .. tepe.
func cell_box(k: int) -> AABB:
	var o := cell_origin(cols.cell_keys[k])
	return AABB(Vector3(o.x, cell_ymin[k], o.y), Vector3(cols.cell_m, cell_ymax[k] - cell_ymin[k], cols.cell_m))


## Leke parçası (chunk) kutusu: `chunk_cells` x `chunk_cells` hücrenin birleşimi; boşsa boyutsuz AABB.
## Önbelleklenir (salt okunur sonuç).
func chunk_box(chx: int, chz: int, chunk_cells: int) -> AABB:
	var ck := Vector3i(chx, chz, chunk_cells)
	if _chunk_boxes.has(ck):
		return _chunk_boxes[ck]
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for cz in range(chz * chunk_cells, (chz + 1) * chunk_cells):
		for cx in range(chx * chunk_cells, (chx + 1) * chunk_cells):
			if cx >= cols.cells_w or cz >= cols.cells_h:
				continue
			var k := index_of_key(cz * cols.cells_w + cx)
			if k < 0:
				continue
			var b := cell_box(k)
			lo = lo.min(b.position)
			hi = hi.max(b.end)
	var box := AABB()
	if lo.x != INF:
		box = AABB(lo, hi - lo)
	_chunk_boxes[ck] = box
	return box


## Parça kuzeybatı köşesi (dünya xz).
func chunk_origin(chx: int, chz: int, chunk_cells: int) -> Vector2:
	return Vector2(cols.origin.x + float(chx * chunk_cells) * cols.cell_m,
			cols.origin.y + float(chz * chunk_cells) * cols.cell_m)


func chunk_grid_size(chunk_cells: int) -> Vector2i:
	return Vector2i(ceili(float(cols.cells_w) / float(chunk_cells)), ceili(float(cols.cells_h) / float(chunk_cells)))
