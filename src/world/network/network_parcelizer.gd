class_name NetworkParcelizer
extends RefCounted
## Bloğun inşa edilebilir poligonunu parsellere böler (T-011). Kenar etiketi = cephe verebilecek yol kenarı kimliği
## (-1 = ray/kesik hat). Algoritma: dışbükey parçalara ayır; her parçada cephe kenarını seç; derinlik yeterince
## büyükse iki sıraya kes (her iki yarı da cephe tutarsa), sonra cephe boyunca eşit genişlikli şeritlere kes.
## Cephesiz (içte kalan) artıklar parsel olmaz. Tohumlu RNG yalnız lot genişliği çeşitlemesi içindir (topolojik
## değil).

## Derinlik kesimi için eşik: parça derinliği `max_depth_m` × bu katı aşarsa iki sıraya bölünür.
const DEPTH_CUT_FACTOR := 1.5
const MAX_PIECES := 4000


## Dönüş: [{"outline": PackedVector2Array, "frontage": int, "front_len": float, "front_mid": Vector2}, ...]
## (üretim sırası deterministik).
static func subdivide(points: PackedVector2Array, tags: PackedInt32Array, params: Dictionary,
		rng: RandomNumberGenerator) -> Array[Dictionary]:
	var lots: Array[Dictionary] = []
	for piece in NetworkGeometry.convex_decompose(points, tags):
		_subdivide_convex(piece["points"], piece["tags"], params, rng, lots)
	return lots


static func _subdivide_convex(points: PackedVector2Array, tags: PackedInt32Array, params: Dictionary,
		rng: RandomNumberGenerator, lots: Array[Dictionary]) -> void:
	var target_w := float(params.get("lot_width_m", 20.0))
	var jitter := float(params.get("lot_width_jitter", 0.1))
	var max_depth := float(params.get("max_depth_m", 40.0))
	var min_area := float(params.get("min_area_m2", 100.0))
	var min_front := float(params.get("min_frontage_m", 6.0))
	var stack: Array[Dictionary] = [{"points": points, "tags": tags, "axis": Vector2.ZERO}]
	var guard := 0
	while not stack.is_empty() and guard < MAX_PIECES:
		guard += 1
		var piece: Dictionary = stack.pop_back()
		var pts: PackedVector2Array = piece["points"]
		var tgs: PackedInt32Array = piece["tags"]
		if absf(NetworkGeometry.signed_area(pts)) < min_area:
			continue
		var edge_idx := _frontage_edge(pts, tgs, piece["axis"])
		if edge_idx < 0:
			continue
		var n := pts.size()
		var e0 := pts[edge_idx]
		var u := (pts[(edge_idx + 1) % n] - e0).normalized()
		var nin := Vector2(-u.y, u.x)
		var umin := INF
		var umax := -INF
		var vmax := 0.0
		for p in pts:
			var d := p - e0
			var pu := float(d.dot(u))
			umin = minf(umin, pu)
			umax = maxf(umax, pu)
			vmax = maxf(vmax, float(d.dot(nin)))
		if vmax > max_depth * DEPTH_CUT_FACTOR:
			var halves := _cut(pts, tgs, e0 + nin * (vmax * 0.5), nin)
			if _both_viable(halves, min_area, min_front):
				stack.append({"points": halves[1]["points"], "tags": halves[1]["tags"], "axis": u})
				stack.append({"points": halves[0]["points"], "tags": halves[0]["tags"], "axis": u})
				continue
		var length := umax - umin
		var lots_n := maxi(1, int(round(length / maxf(target_w * (1.0 + rng.randf_range(-jitter, jitter)), 1.0))))
		var rest_pts := pts
		var rest_tgs := tgs
		if lots_n >= 2:
			var step := length / float(lots_n)
			for k in range(1, lots_n):
				var at := umin + step * float(k) + rng.randf_range(-jitter, jitter) * step * 0.5
				var strips := _cut(rest_pts, rest_tgs, e0 + u * at, u)
				if strips[0]["points"].size() < 3 or strips[1]["points"].size() < 3:
					continue
				_emit(strips[0]["points"], strips[0]["tags"], u, min_area, min_front, lots)
				rest_pts = strips[1]["points"]
				rest_tgs = strips[1]["tags"]
		_emit(rest_pts, rest_tgs, u, min_area, min_front, lots)


## Parçayı parsel olarak ekler (alan/cephe eşikleri sağlanıyorsa). Cephe kenarı = eksene izdüşümü en uzun etiketli
## kenar.
static func _emit(pts: PackedVector2Array, tgs: PackedInt32Array, axis: Vector2, min_area: float, min_front: float,
		lots: Array[Dictionary]) -> void:
	if absf(NetworkGeometry.signed_area(pts)) < min_area:
		return
	var edge_idx := _frontage_edge(pts, tgs, axis)
	if edge_idx < 0:
		return
	var n := pts.size()
	var front_len := 0.0
	for i in n:
		if tgs[i] == tgs[edge_idx]:
			front_len += pts[i].distance_to(pts[(i + 1) % n])
	if front_len >= min_front:
		lots.append({"outline": pts, "frontage": tgs[edge_idx], "front_len": front_len,
				"front_mid": (pts[edge_idx] + pts[(edge_idx + 1) % n]) * 0.5})


## `axis` sıfırsa en uzun etiketli kenar; değilse eksene izdüşümü en uzun etiketli kenar. Etiketli kenar yoksa -1.
static func _frontage_edge(pts: PackedVector2Array, tgs: PackedInt32Array, axis: Vector2) -> int:
	var n := pts.size()
	var best := -1
	var best_score := 0.0
	for i in n:
		if tgs[i] < 0:
			continue
		var d := pts[(i + 1) % n] - pts[i]
		var score := d.length() if axis == Vector2.ZERO else absf(float(d.dot(axis)))
		if score > best_score + 1.0e-9:
			best_score = score
			best = i
	return best


## Çizgi (origin, normal): [normal'in TERS tarafı (<= çizgi), normal tarafı (>= çizgi)].
static func _cut(pts: PackedVector2Array, tgs: PackedInt32Array, origin: Vector2, normal: Vector2) -> Array[Dictionary]:
	return NetworkGeometry.split_line(pts, tgs, origin, normal)


static func _both_viable(halves: Array[Dictionary], min_area: float, min_front: float) -> bool:
	for h in halves:
		var pts: PackedVector2Array = h["points"]
		if pts.size() < 3 or absf(NetworkGeometry.signed_area(pts)) < min_area:
			return false
		if min_front > 0.0 and not _has_front(pts, h["tags"], min_front):
			return false
	return true


static func _has_front(pts: PackedVector2Array, tgs: PackedInt32Array, min_front: float) -> bool:
	var n := pts.size()
	for i in n:
		if tgs[i] >= 0 and pts[i].distance_to(pts[(i + 1) % n]) >= min_front:
			return true
	return false
