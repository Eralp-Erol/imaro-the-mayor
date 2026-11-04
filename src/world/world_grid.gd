class_name WorldGrid
extends RefCounted
## Dünya rasterleri için saf, tamsayı/deterministik ızgara işlemleri (T-001, WLD-01, TEK-03).
## Sahne, zaman, OS, rastgelelik yok. Tüm raster'lar satır-büyük düz dizilerdir: indeks = j * width + i.

const INF_DIST := 1 << 28
## Chamfer 3-4 ağırlıkları: ortogonal adım 3, çapraz adım 4 (birim: hücrenin 1/3'ü).
const CHAMFER_ORTHO := 3
const CHAMFER_DIAG := 4


## Çokgeni (dünya metresi) satır tarama ile doldurur: örnek noktası (i, j) = origin + (i, j) * cell.
## Çift-tek (even-odd) kuralı. Dolu hücrelere `value` yazılır.
static func fill_polygon(poly: PackedVector2Array, origin: Vector2, cell: float, width: int, height: int,
		out: PackedByteArray, value: int) -> void:
	var n := poly.size()
	if n < 3:
		return
	var rows: Array[PackedFloat64Array] = []
	rows.resize(height)
	for j in height:
		rows[j] = PackedFloat64Array()
	for k in n:
		var a := poly[k]
		var b := poly[(k + 1) % n]
		if a.y == b.y:
			continue
		var top := a if a.y < b.y else b
		var bottom := b if a.y < b.y else a
		# Satır merkezleri z_j = origin.y + j * cell; yarı açık aralık [top.y, bottom.y).
		var j0 := maxi(0, ceili((top.y - origin.y) / cell))
		var j1 := mini(height - 1, ceili((bottom.y - origin.y) / cell) - 1)
		var inv_dy := 1.0 / (bottom.y - top.y)
		for j in range(j0, j1 + 1):
			var z := origin.y + j * cell
			var t := (z - top.y) * inv_dy
			var row: PackedFloat64Array = rows[j]
			row.append(top.x + (bottom.x - top.x) * t)
			rows[j] = row
	for j in height:
		var xs: PackedFloat64Array = rows[j]
		if xs.size() < 2:
			continue
		xs.sort()
		var m := xs.size() - 1
		var s := 0
		while s < m:
			var i0 := maxi(0, ceili((xs[s] - origin.x) / cell))
			var i1 := mini(width - 1, ceili((xs[s + 1] - origin.x) / cell) - 1)
			var base := j * width
			for i in range(i0, i1 + 1):
				out[base + i] = value
			s += 2


## Her hücre için en yakın FARKLI sınıf hücresine chamfer uzaklığı (1/3 hücre birimi).
## Sınır hücreleri (4-komşusu başka sınıf) 0 alır. Hepsi aynı sınıfsa INF_DIST kalır.
static func boundary_distance(mask: PackedByteArray, width: int, height: int) -> PackedInt32Array:
	var dist := PackedInt32Array()
	dist.resize(width * height)
	for j in height:
		for i in width:
			var idx := j * width + i
			var v := mask[idx]
			var edge := false
			if i > 0 and mask[idx - 1] != v:
				edge = true
			elif i < width - 1 and mask[idx + 1] != v:
				edge = true
			elif j > 0 and mask[idx - width] != v:
				edge = true
			elif j < height - 1 and mask[idx + width] != v:
				edge = true
			dist[idx] = 0 if edge else INF_DIST
	_chamfer(dist, width, height)
	return dist


## `mask[idx] == target` hücrelerine chamfer uzaklığı (1/3 hücre birimi); hedef yoksa INF_DIST.
static func distance_to_value(mask: PackedByteArray, width: int, height: int, target: int) -> PackedInt32Array:
	var dist := PackedInt32Array()
	dist.resize(width * height)
	for idx in dist.size():
		dist[idx] = 0 if mask[idx] == target else INF_DIST
	_chamfer(dist, width, height)
	return dist


## Morfolojik kapama (dilate sonra erode), yarıçap `radius_cells`. 1 = `mask` değeri 1 olan hücreler.
## Harita dışı hücreler dilate'te yok sayılır, erode'da "dolu" kabul edilir (kenar aşınmaz).
static func closing(mask: PackedByteArray, width: int, height: int, radius_cells: float) -> PackedByteArray:
	var r3 := int(round(radius_cells * CHAMFER_ORTHO))
	var to_land := distance_to_value(mask, width, height, 1)
	var dilated := PackedByteArray()
	dilated.resize(mask.size())
	for idx in dilated.size():
		dilated[idx] = 1 if to_land[idx] <= r3 else 0
	var to_hole := distance_to_value(dilated, width, height, 0)
	var out := PackedByteArray()
	out.resize(mask.size())
	for idx in out.size():
		out[idx] = 1 if to_hole[idx] > r3 else 0
	return out


## 4-bağlantılı bileşen etiketleme (`mask` değeri 1). Dönüş: etiket (0 = arka plan, 1..n) ve alanlar.
## Etiketler tarama sırasına göre verilir (satır-büyük ilk hücre) — deterministik.
@warning_ignore("integer_division")
static func label_components(mask: PackedByteArray, width: int, height: int) -> Dictionary:
	var labels := PackedInt32Array()
	labels.resize(width * height)
	var areas := PackedInt32Array()
	areas.append(0)  # etiket 0 = arka plan
	var stack := PackedInt32Array()
	var next_label := 1
	for start in mask.size():
		if mask[start] != 1 or labels[start] != 0:
			continue
		var count := 0
		labels[start] = next_label
		stack.append(start)
		while not stack.is_empty():
			var idx := stack[stack.size() - 1]
			stack.resize(stack.size() - 1)
			count += 1
			var i := idx % width
			var j := idx / width
			if i > 0 and mask[idx - 1] == 1 and labels[idx - 1] == 0:
				labels[idx - 1] = next_label
				stack.append(idx - 1)
			if i < width - 1 and mask[idx + 1] == 1 and labels[idx + 1] == 0:
				labels[idx + 1] = next_label
				stack.append(idx + 1)
			if j > 0 and mask[idx - width] == 1 and labels[idx - width] == 0:
				labels[idx - width] = next_label
				stack.append(idx - width)
			if j < height - 1 and mask[idx + width] == 1 and labels[idx + width] == 0:
				labels[idx + width] = next_label
				stack.append(idx + width)
		areas.append(count)
		next_label += 1
	return {"labels": labels, "areas": areas}


## Çok kaynaklı genişlik-öncelikli yayılım (4-komşu), yalnız `passable[idx] == 1` hücrelerinde.
## Dönüş: her hücrenin adım uzaklığı (-1 = erişilemez). `sources` hücre indeksleridir.
@warning_ignore("integer_division")
static func bfs_steps(passable: PackedByteArray, width: int, height: int,
		sources: PackedInt32Array) -> PackedInt32Array:
	var steps := PackedInt32Array()
	steps.resize(width * height)
	steps.fill(-1)
	var queue := PackedInt32Array()
	for s in sources:
		if passable[s] == 1 and steps[s] < 0:
			steps[s] = 0
			queue.append(s)
	var head := 0
	while head < queue.size():
		var idx := queue[head]
		head += 1
		var d := steps[idx] + 1
		var i := idx % width
		var j := idx / width
		if i > 0 and passable[idx - 1] == 1 and steps[idx - 1] < 0:
			steps[idx - 1] = d
			queue.append(idx - 1)
		if i < width - 1 and passable[idx + 1] == 1 and steps[idx + 1] < 0:
			steps[idx + 1] = d
			queue.append(idx + 1)
		if j > 0 and passable[idx - width] == 1 and steps[idx - width] < 0:
			steps[idx - width] = d
			queue.append(idx - width)
		if j < height - 1 and passable[idx + width] == 1 and steps[idx + width] < 0:
			steps[idx + width] = d
			queue.append(idx + width)
	return steps


# İki geçişli chamfer 3-4 (yerinde). Yalnız tamsayı işlemleri: platformlar arası bit-bit aynı.
static func _chamfer(dist: PackedInt32Array, width: int, height: int) -> void:
	for j in height:
		for i in width:
			var idx := j * width + i
			var best := dist[idx]
			if best == 0:
				continue
			if i > 0:
				best = mini(best, dist[idx - 1] + CHAMFER_ORTHO)
			if j > 0:
				best = mini(best, dist[idx - width] + CHAMFER_ORTHO)
				if i > 0:
					best = mini(best, dist[idx - width - 1] + CHAMFER_DIAG)
				if i < width - 1:
					best = mini(best, dist[idx - width + 1] + CHAMFER_DIAG)
			dist[idx] = best
	for j in range(height - 1, -1, -1):
		for i in range(width - 1, -1, -1):
			var idx := j * width + i
			var best := dist[idx]
			if best == 0:
				continue
			if i < width - 1:
				best = mini(best, dist[idx + 1] + CHAMFER_ORTHO)
			if j < height - 1:
				best = mini(best, dist[idx + width] + CHAMFER_ORTHO)
				if i < width - 1:
					best = mini(best, dist[idx + width + 1] + CHAMFER_DIAG)
				if i > 0:
					best = mini(best, dist[idx + width - 1] + CHAMFER_DIAG)
			dist[idx] = best
