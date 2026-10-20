class_name NetworkSpatialHash
extends RefCounted
## Dikdörtgen kutulu nesneler için tek düzey ızgara karma (T-011). Sorgu sonuçları KİMLİĞE göre sıralı ve tekildir
## (deterministik). Saf; Dictionary anahtarı = hücre indeksi (cx + cy * STRIDE).

const STRIDE := 1 << 16

var cell: float = 128.0
var _cells: Dictionary = {}
var _rects: Dictionary = {}


func _init(cell_size: float = 128.0) -> void:
	cell = cell_size


func clear() -> void:
	_cells.clear()
	_rects.clear()


func size() -> int:
	return _rects.size()


func has_id(id: int) -> bool:
	return _rects.has(id)


func insert(id: int, rect: Rect2) -> void:
	if _rects.has(id):
		remove(id)
	_rects[id] = rect
	var x0 := int(floor(rect.position.x / cell)) + 1024
	var y0 := int(floor(rect.position.y / cell)) + 1024
	var x1 := int(floor(rect.end.x / cell)) + 1024
	var y1 := int(floor(rect.end.y / cell)) + 1024
	for cy in range(y0, y1 + 1):
		for cx in range(x0, x1 + 1):
			var key := cx + cy * STRIDE
			var list: PackedInt32Array = _cells.get(key, PackedInt32Array())
			list.append(id)
			_cells[key] = list


func remove(id: int) -> void:
	if not _rects.has(id):
		return
	var rect: Rect2 = _rects[id]
	for key in _keys(rect):
		if not _cells.has(key):
			continue
		var list: PackedInt32Array = _cells[key]
		var at := list.find(id)
		if at >= 0:
			list.remove_at(at)
		if list.is_empty():
			_cells.erase(key)
		else:
			_cells[key] = list
	_rects.erase(id)


func rect_of(id: int) -> Rect2:
	return _rects.get(id, Rect2())


## Kutusu `rect` ile çakışan kimlikler (sıralı, tekil). Kutu çakışması yaklaşıktır; çağıran kesin sınama yapar.
func query_rect(rect: Rect2) -> PackedInt32Array:
	var seen := {}
	var out := PackedInt32Array()
	for key in _keys(rect):
		if not _cells.has(key):
			continue
		for id in (_cells[key] as PackedInt32Array):
			if seen.has(id):
				continue
			seen[id] = true
			if rect.intersects(_rects[id], true):
				out.append(id)
	out.sort()
	return out


func query_point(p: Vector2) -> PackedInt32Array:
	return query_rect(Rect2(p, Vector2.ZERO))


func _keys(rect: Rect2) -> PackedInt32Array:
	var x0 := int(floor(rect.position.x / cell))
	var y0 := int(floor(rect.position.y / cell))
	var x1 := int(floor(rect.end.x / cell))
	var y1 := int(floor(rect.end.y / cell))
	var out := PackedInt32Array()
	for cy in range(y0, y1 + 1):
		for cx in range(x0, x1 + 1):
			out.append((cx + 1024) + (cy + 1024) * STRIDE)
	return out
