class_name VegetationLayout
extends RefCounted
## B0 sütunlarının görünüm tarafı eki (T-062 B1): örnek başına zemin yüksekliği (`WorldData.height_at`, yapı/arazi
## deseni ile aynı kaynak) ve hücre başına sınır kutusu (y aralığı = zemin dibi .. tepe), PROXY'li tür sayısı. SAF ve
## iş parçacığı güvenli (yalnız okur); aynı sütun + dünya -> aynı çıktı (determinizm). Sütunları DEĞİŞTİRMEZ.
## Görünüm sütunlarla BİRE BİR eşlenir: `cols.count` örnek, `y.size() == cols.count`.

## Gizleme maskesi kaynak bitleri (`hidden`).
const CH_CORRIDOR := 1
const CH_PARCEL := 2

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
## Gizleme maskesi (GÖRÜNÜM katmanı; sütunlara ve sim'e dokunmaz): `cols` satırıyla aynı sıra, 0 = çizilir, bit seti =
## bu örnek gizli. Bitler kaynağı ayırır (`CH_CORRIDOR`: T-042 yeni yol koridoru, `CH_PARCEL`: alınan/kamulaştırılan
## parsel içi) ki biri değişince öbürü bozulmasın. BOŞ dizi = hiçbir örnek gizli değil (varsayılan; hızlı yol).
## Yazma YALNIZ `set_channel_rows`; iş parçacığı okuyan görünümler (leke işçileri) yazmadan önce BEKLETİLİR
## (`VegetationView`).
var hidden: PackedByteArray = PackedByteArray()
## Gizli (herhangi bir bit seti) örnek sayısı.
var hidden_count: int = 0

var _channel_rows: Dictionary = {}   # bit -> sıralı tekil satırlar (son uygulanan)
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


## Satır `i` gizli mi (herhangi bir kaynak). Maske boşsa her zaman false.
func is_hidden(i: int) -> bool:
	return not hidden.is_empty() and hidden[i] != 0


## Satır `i`nin hücre dizini k (`cell_start[k] <= i < cell_start[k + 1]`).
func cell_of_row(i: int) -> int:
	return cols.cell_start.bsearch(i, false) - 1


## Yol koridoru kaynağı (`CH_CORRIDOR`); `set_channel_rows` ile aynı.
func set_hidden(rows: PackedInt32Array) -> PackedInt32Array:
	return set_channel_rows(CH_CORRIDOR, rows)


## `bit` kaynağının gizli satır kümesini (sıralı/sırasız, tekil olmayabilir) yerleştirir. ARTIMLI: önceki kümeyle
## karşılaştırılır, yalnız farkın satırlarına yazılır (tüm sütunlar taranmaz; maliyet ~ |eski| + |yeni|). Dönüş:
## GÖRÜNÜR durumu (herhangi bir bit) değişen hücre dizinleri k (artan). Deterministik: aynı küme -> aynı maske; boş küme
## kaynağın tüm satırlarını geri getirir (başka kaynağın tuttukları gizli kalır).
func set_channel_rows(bit: int, rows: PackedInt32Array) -> PackedInt32Array:
	var fresh := _clean_rows(rows)
	var old: PackedInt32Array = _channel_rows.get(bit, PackedInt32Array())
	if fresh == old:
		return PackedInt32Array()
	if hidden.is_empty() and not fresh.is_empty():
		hidden.resize(cols.count)
	var changed := {}
	var a := 0
	var b := 0
	while a < old.size() or b < fresh.size():
		var ra := old[a] if a < old.size() else 0x7fffffff
		var rb := fresh[b] if b < fresh.size() else 0x7fffffff
		if ra == rb:
			a += 1
			b += 1
		elif ra < rb:
			_clear_bit(ra, bit, changed)
			a += 1
		else:
			_set_bit(rb, bit, changed)
			b += 1
	if fresh.is_empty():
		_channel_rows.erase(bit)
	else:
		_channel_rows[bit] = fresh
	if hidden_count == 0:
		hidden = PackedByteArray()
	var out := PackedInt32Array(changed.keys())
	out.sort()
	return out


func _set_bit(i: int, bit: int, changed: Dictionary) -> void:
	var was := hidden[i]
	hidden[i] = was | bit
	if was == 0:
		hidden_count += 1
		changed[cell_of_row(i)] = true


func _clear_bit(i: int, bit: int, changed: Dictionary) -> void:
	var was := hidden[i]
	var now := was & ~bit
	hidden[i] = now
	if now == 0 and was != 0:
		hidden_count -= 1
		changed[cell_of_row(i)] = true


## Geçerli aralıktaki, sıralı ve tekil satırlar.
func _clean_rows(rows: PackedInt32Array) -> PackedInt32Array:
	if rows.is_empty():
		return rows
	var sorted := rows.duplicate()
	sorted.sort()
	var out := PackedInt32Array()
	var last := -1
	for i in sorted:
		if i != last and i >= 0 and i < cols.count:
			out.append(i)
			last = i
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
