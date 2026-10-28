class_name VegetationWindow
extends RefCounted
## Kamera çevresi pencere mantığı (T-062 B1): hangi 256 m hücre ağaç düğümü, hangi parça (chunk) leke düğümü taşır.
## SAF: kamera noktası + düzen -> açılacak/kapanacak kümeler. Her çağrı yalnız kamera çevresindeki hücre ızgarasını
## tarar (6366 hücrenin hepsini DEĞİL). Açma sınırı `margin_open`, kapama sınırı `margin_close` (histerezis: sınırda
## açıp kapama titremesi yok). Sonuçlar artan hücre/parça sırasındadır (deterministik).


## Hücre k (cell_keys dizini), kamera `cam` için `margin` payıyla ağaç düğümü gerektiriyor mu.
static func cell_needed(layout: VegetationLayout, lod: VegetationLod, k: int, cam: Vector3, margin: float) -> bool:
	var box := layout.cell_box(k)
	var r := VegetationLod.box_distance_range(cam, box.position, box.end)
	if r.x < lod.lod1_end_m + margin:
		return true
	return layout.cell_proxy_count[k] > 0 and r.x < lod.palm_proxy_end_m + margin


## `active`: Dictionary(k -> true) şu an açık hücreler. Açılacaklar (açık olmayıp `margin` ile gerekenler), artan k.
static func cells_to_open(layout: VegetationLayout, lod: VegetationLod, cam: Vector3, margin: float,
		active: Dictionary) -> PackedInt32Array:
	var out := PackedInt32Array()
	var reach := lod.palm_proxy_end_m + margin
	var cols := layout.cols
	var cx0 := clampi(int(floor((cam.x - reach - cols.origin.x) / cols.cell_m)), 0, cols.cells_w - 1)
	var cx1 := clampi(int(floor((cam.x + reach - cols.origin.x) / cols.cell_m)), 0, cols.cells_w - 1)
	var cz0 := clampi(int(floor((cam.z - reach - cols.origin.y) / cols.cell_m)), 0, cols.cells_h - 1)
	var cz1 := clampi(int(floor((cam.z + reach - cols.origin.y) / cols.cell_m)), 0, cols.cells_h - 1)
	for cz in range(cz0, cz1 + 1):
		for cx in range(cx0, cx1 + 1):
			var k := layout.index_of_key(cz * cols.cells_w + cx)
			if k < 0 or active.has(k):
				continue
			if cell_needed(layout, lod, k, cam, margin):
				out.append(k)
	return out


## Kapanacaklar: açık olup `margin` ile artık gerekmeyenler, artan k.
static func cells_to_close(layout: VegetationLayout, lod: VegetationLod, cam: Vector3, margin: float,
		active: Dictionary) -> PackedInt32Array:
	var out := PackedInt32Array()
	for k: int in active:
		if not cell_needed(layout, lod, k, cam, margin):
			out.append(k)
	out.sort()
	return out


## Leke parçası gerekli mi: kutu `end_m + margin` içinde VE tamamı `begin_m - margin`ten yakın değil (tamamı yakınsa
## fragmanların hepsi atılır).
static func chunk_needed(layout: VegetationLayout, chx: int, chz: int, cam: Vector3, begin_m: float, end_m: float,
		margin: float, chunk_cells: int) -> bool:
	var box := layout.chunk_box(chx, chz, chunk_cells)
	if box.size == Vector3.ZERO and box.position == Vector3.ZERO:
		return false
	var r := VegetationLod.box_distance_range(cam, box.position, box.end)
	return r.x < end_m + margin and r.y > begin_m - margin


static func chunks_to_open(layout: VegetationLayout, cam: Vector3, begin_m: float, end_m: float, margin: float,
		chunk_cells: int, active: Dictionary) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var cols := layout.cols
	var span := cols.cell_m * float(chunk_cells)
	var reach := end_m + margin
	var grid := layout.chunk_grid_size(chunk_cells)
	var x0 := clampi(int(floor((cam.x - reach - cols.origin.x) / span)), 0, grid.x - 1)
	var x1 := clampi(int(floor((cam.x + reach - cols.origin.x) / span)), 0, grid.x - 1)
	var z0 := clampi(int(floor((cam.z - reach - cols.origin.y) / span)), 0, grid.y - 1)
	var z1 := clampi(int(floor((cam.z + reach - cols.origin.y) / span)), 0, grid.y - 1)
	for chz in range(z0, z1 + 1):
		for chx in range(x0, x1 + 1):
			var key := Vector2i(chx, chz)
			if active.has(key):
				continue
			if chunk_needed(layout, chx, chz, cam, begin_m, end_m, margin, chunk_cells):
				out.append(key)
	return out


static func chunks_to_close(layout: VegetationLayout, cam: Vector3, begin_m: float, end_m: float, margin: float,
		chunk_cells: int, active: Dictionary) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for key: Vector2i in active:
		if not chunk_needed(layout, key.x, key.y, cam, begin_m, end_m, margin, chunk_cells):
			out.append(key)
	out.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
	return out
