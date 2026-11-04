class_name NetworkGeometry
extends RefCounted
## Ağ katmanının saf 2B geometri yardımcıları (T-011; TEK-01/02). Sahne, zaman, OS, rastgelelik yok.
## Koordinat: x = doğu, y = güney (WorldData ile aynı; Vector2.y dünya z'sidir). "Pozitif yönelim" = işaretli alan
## (ayakkabı bağı) > 0; böyle bir çokgende iç, kenar yönünün SOLUNDADIR (sol normal (-d.y, d.x)).
## Çokgenler PackedVector2Array'dir; kenar etiketi dizisi `tags[i]`, i -> i+1 kenarının etiketidir (-1 =
## etiketsiz/kesik).

const EPS := 1.0e-9
## Sivri köşelerde ofset ucunun (miter) taşma sınırı (ofset katı); aşılırsa köşe iki noktaya (pah) bölünür.
const MITER_LIMIT := 3.0
## `is_simple` kenar-kenar sınaması bu köşe sayısının üstünde atlanır (büyük yüzler için maliyet sınırı).
const SIMPLE_CHECK_MAX_VERTS := 200


static func signed_area(poly: PackedVector2Array) -> float:
	var n := poly.size()
	var s := 0.0
	for i in n:
		var a := poly[i]
		var b := poly[(i + 1) % n]
		s += float(a.x) * float(b.y) - float(b.x) * float(a.y)
	return s * 0.5


static func centroid(poly: PackedVector2Array) -> Vector2:
	var n := poly.size()
	var area2 := 0.0
	var cx := 0.0
	var cy := 0.0
	for i in n:
		var a := poly[i]
		var b := poly[(i + 1) % n]
		var cr := float(a.x) * float(b.y) - float(b.x) * float(a.y)
		area2 += cr
		cx += (float(a.x) + float(b.x)) * cr
		cy += (float(a.y) + float(b.y)) * cr
	if absf(area2) < EPS:
		return average(poly)
	return Vector2(cx / (3.0 * area2), cy / (3.0 * area2))


static func average(poly: PackedVector2Array) -> Vector2:
	var sum := Vector2.ZERO
	for p in poly:
		sum += p
	return sum / float(maxi(poly.size(), 1))


static func bounds(poly: PackedVector2Array) -> Rect2:
	if poly.is_empty():
		return Rect2()
	var lo := poly[0]
	var hi := poly[0]
	for p in poly:
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
	return Rect2(lo, hi - lo)


## Çift-tek kuralı; sınır üzerindeki noktalar belirsizdir.
static func point_in_polygon(p: Vector2, poly: PackedVector2Array) -> bool:
	var inside := false
	var n := poly.size()
	var j := n - 1
	for i in n:
		var a := poly[i]
		var b := poly[j]
		if (a.y > p.y) != (b.y > p.y):
			var x_at := float(b.x - a.x) * float(p.y - a.y) / float(b.y - a.y) + float(a.x)
			if float(p.x) < x_at:
				inside = not inside
		j = i
	return inside


## p + t (q - p) == r + u (s - r) çözümü (t, u); doğrular (neredeyse) paralelse Vector2(INF, INF).
static func segment_params(p: Vector2, q: Vector2, r: Vector2, s: Vector2) -> Vector2:
	var d1 := q - p
	var d2 := s - r
	var denom := float(d1.x) * float(d2.y) - float(d1.y) * float(d2.x)
	if absf(denom) <= 1.0e-9 * maxf(d1.length() * d2.length(), EPS):
		return Vector2(INF, INF)
	var diff := r - p
	var t := (float(diff.x) * float(d2.y) - float(diff.y) * float(d2.x)) / denom
	var u := (float(diff.x) * float(d1.y) - float(diff.y) * float(d1.x)) / denom
	return Vector2(t, u)


## Nokta p'nin a-b doğru parçası üzerindeki izdüşüm parametresi (0..1'e kenetli).
static func project_param(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var len2 := ab.length_squared()
	if len2 < EPS:
		return 0.0
	return clampf(float((p - a).dot(ab)) / len2, 0.0, 1.0)


static func distance_point_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var t := project_param(p, a, b)
	return p.distance_to(a + (b - a) * t)


## İki doğru parçası arasındaki en küçük uzaklık (kesişiyorsa 0).
static func distance_segment_segment(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> float:
	var params := segment_params(a, b, c, d)
	if not is_inf(params.x) and params.x >= 0.0 and params.x <= 1.0 and params.y >= 0.0 and params.y <= 1.0:
		return 0.0
	return minf(minf(distance_point_segment(a, c, d), distance_point_segment(b, c, d)),
			minf(distance_point_segment(c, a, b), distance_point_segment(d, a, b)))


## Doğru parçası ile çokgenin (içi dahil) en küçük uzaklığı; kesişiyor veya içindeyse 0.
static func segment_polygon_distance(a: Vector2, b: Vector2, poly: PackedVector2Array) -> float:
	if point_in_polygon(a, poly) or point_in_polygon(b, poly):
		return 0.0
	var best := INF
	var n := poly.size()
	for i in n:
		best = minf(best, distance_segment_segment(a, b, poly[i], poly[(i + 1) % n]))
		if best <= 0.0:
			return 0.0
	return best


static func is_convex(poly: PackedVector2Array) -> bool:
	var n := poly.size()
	if n < 3:
		return false
	for i in n:
		var a := poly[(i + n - 1) % n]
		var b := poly[i]
		var c := poly[(i + 1) % n]
		if _turn(a, b, c) < -1.0e-6:
			return false
	return true


## Köşe b'de a->b->c dönüşü (normalize edilmiş çarpım); pozitif yönelimde < 0 = içbükey (reflex).
static func _turn(a: Vector2, b: Vector2, c: Vector2) -> float:
	var d1 := b - a
	var d2 := c - b
	var l := d1.length() * d2.length()
	if l < EPS:
		return 0.0
	return (float(d1.x) * float(d2.y) - float(d1.y) * float(d2.x)) / l


## Kendini kesmeyen çokgen mi (komşu olmayan kenar çiftleri kesişmez)?
static func is_simple(poly: PackedVector2Array) -> bool:
	var n := poly.size()
	if n < 3:
		return false
	if n > SIMPLE_CHECK_MAX_VERTS:
		return true
	for i in n:
		var a := poly[i]
		var b := poly[(i + 1) % n]
		for j in range(i + 2, n):
			if i == 0 and j == n - 1:
				continue
			var c := poly[j]
			var d := poly[(j + 1) % n]
			var params := segment_params(a, b, c, d)
			if is_inf(params.x):
				continue
			if params.x > 1.0e-7 and params.x < 1.0 - 1.0e-7 and params.y > 1.0e-7 and params.y < 1.0 - 1.0e-7:
				return false
	return true


## Pozitif yönelimli çokgeni kenar başına `offsets[i]` kadar içe öteler. Dönüş: {"points", "edge_of"}:
## `edge_of[k]` = iç çokgenin k -> k+1 kenarının özgün kenar indeksi (basamak/pah kenarı = -1). Geçersiz sonuç
## (kendini keser, yönelim döner, alan ≤ 0) için `points` boştur.
static func inset_polygon(poly: PackedVector2Array, offsets: PackedFloat64Array) -> Dictionary:
	var n := poly.size()
	var points := PackedVector2Array()
	var edge_of := PackedInt32Array()
	if n < 3:
		return {"points": points, "edge_of": edge_of}
	var normals := PackedVector2Array()
	normals.resize(n)
	for i in n:
		var d := poly[(i + 1) % n] - poly[i]
		var l := d.length()
		normals[i] = Vector2(-d.y, d.x) / maxf(l, EPS)
	for i in n:
		var e_in := (i + n - 1) % n
		var v := poly[i]
		var n1 := normals[e_in]
		var n2 := normals[i]
		var o1 := offsets[e_in]
		var o2 := offsets[i]
		var det := float(n1.x) * float(n2.y) - float(n1.y) * float(n2.x)
		var emit_two := false
		var miter := Vector2.ZERO
		if absf(det) < 1.0e-6:
			if absf(o1 - o2) < 1.0e-6:
				miter = v + n1 * o1
			else:
				emit_two = true
		else:
			var c1 := float(v.x) * float(n1.x) + float(v.y) * float(n1.y) + o1
			var c2 := float(v.x) * float(n2.x) + float(v.y) * float(n2.y) + o2
			miter = Vector2((c1 * float(n2.y) - c2 * float(n1.y)) / det, (float(n1.x) * c2 - float(n2.x) * c1) / det)
			# Neredeyse paralel ve ofsetleri farklı kenarlarda uç çok uzağa kaçar (hem dışbükey hem içbükey köşede):
			# pah.
			if miter.distance_to(v) > MITER_LIMIT * maxf(maxf(o1, o2), EPS):
				emit_two = true
		if emit_two:
			points.append(v + n1 * o1)
			edge_of.append(-1)
			points.append(v + n2 * o2)
			edge_of.append(i)
		else:
			points.append(miter)
			edge_of.append(i)
	if signed_area(points) <= 1.0e-6 or not is_simple(points) or not _edges_keep_direction(poly, points, edge_of):
		return {"points": PackedVector2Array(), "edge_of": PackedInt32Array()}
	# İç çokgen özgün çokgenin içinde kalmalı (aşırı ofset çokgeni ters çevirip geçerli görünebilir).
	for p in points:
		if not point_in_polygon(p, poly):
			return {"points": PackedVector2Array(), "edge_of": PackedInt32Array()}
	return {"points": points, "edge_of": edge_of}


## Aşırı ofset çokgeni "ters çevirir" (yönelim aynı kalır): iç kenar özgün kenarla aynı yönü korumalıdır.
static func _edges_keep_direction(poly: PackedVector2Array, inner: PackedVector2Array,
		edge_of: PackedInt32Array) -> bool:
	var n := poly.size()
	var m := inner.size()
	for k in m:
		var e := edge_of[k]
		if e < 0:
			continue
		var orig := poly[(e + 1) % n] - poly[e]
		var now := inner[(k + 1) % m] - inner[k]
		if float(orig.dot(now)) <= 0.0:
			return false
	return true


## Yarım düzlem kırpma (Sutherland-Hodgman), kenar etiketlerini korur: (p - origin)·normal >= 0 tarafı kalır.
## Kesik hat yeni kenar etiketi -1 alır. Dönüş {"points", "tags"}; ≤ 2 köşe kalırsa boş.
static func clip_halfplane(points: PackedVector2Array, tags: PackedInt32Array, origin: Vector2,
		normal: Vector2) -> Dictionary:
	var n := points.size()
	var out_pts := PackedVector2Array()
	var out_tags := PackedInt32Array()
	for i in n:
		var cur := points[i]
		var nxt := points[(i + 1) % n]
		var sc := float((cur - origin).dot(normal))
		var sn := float((nxt - origin).dot(normal))
		var cur_in := sc >= -EPS
		var nxt_in := sn >= -EPS
		if cur_in:
			out_pts.append(cur)
			out_tags.append(tags[i])
		if cur_in != nxt_in:
			var t := sc / (sc - sn)
			var x := cur + (nxt - cur) * t
			out_pts.append(x)
			out_tags.append(-1 if cur_in else tags[i])
	return _clean_clip(out_pts, out_tags)


## Tek geçişte iki yarım düzleme böl: [normal'in TERS tarafı (<= çizgi), normal tarafı (>= çizgi)]; her biri
## {"points", "tags"} (≤ 2 köşe kalırsa boş). Çizgi üzerindeki köşe iki tarafa da girer. `clip_halfplane` ile aynı
## etiket kuralı.
static func split_line(points: PackedVector2Array, tags: PackedInt32Array, origin: Vector2,
		normal: Vector2) -> Array[Dictionary]:
	var n := points.size()
	var sides := PackedFloat64Array()
	sides.resize(n)
	for i in n:
		sides[i] = float((points[i] - origin).dot(normal))
	var pos_pts := PackedVector2Array()
	var pos_tags := PackedInt32Array()
	var neg_pts := PackedVector2Array()
	var neg_tags := PackedInt32Array()
	for i in n:
		var cur := points[i]
		var nxt := points[(i + 1) % n]
		var sc := sides[i]
		var sn := sides[(i + 1) % n]
		var cur_pos := sc >= -EPS
		var cur_neg := sc <= EPS
		if cur_pos:
			pos_pts.append(cur)
			pos_tags.append(tags[i])
		if cur_neg:
			neg_pts.append(cur)
			neg_tags.append(tags[i])
		if cur_pos != (sn >= -EPS) or cur_neg != (sn <= EPS):
			var x := cur + (nxt - cur) * (sc / (sc - sn))
			if cur_pos != (sn >= -EPS):
				pos_pts.append(x)
				pos_tags.append(-1 if cur_pos else tags[i])
			if cur_neg != (sn <= EPS):
				neg_pts.append(x)
				neg_tags.append(-1 if cur_neg else tags[i])
	return [_clean_clip(neg_pts, neg_tags), _clean_clip(pos_pts, pos_tags)]


static func _clean_clip(pts: PackedVector2Array, tags: PackedInt32Array) -> Dictionary:
	var out_pts := PackedVector2Array()
	var out_tags := PackedInt32Array()
	var n := pts.size()
	for i in n:
		var p := pts[i]
		if not out_pts.is_empty() and p.distance_to(out_pts[out_pts.size() - 1]) < 1.0e-6:
			# Yinelenen köşe: önceki köşenin giden kenarı artık bu köşenin giden kenarıdır.
			out_tags[out_tags.size() - 1] = tags[i]
			continue
		out_pts.append(p)
		out_tags.append(tags[i])
	while out_pts.size() > 1 and out_pts[0].distance_to(out_pts[out_pts.size() - 1]) < 1.0e-6:
		out_pts.remove_at(out_pts.size() - 1)
		out_tags.remove_at(out_tags.size() - 1)
	if out_pts.size() < 3:
		return {"points": PackedVector2Array(), "tags": PackedInt32Array()}
	return {"points": out_pts, "tags": out_tags}


## Çokgeni içbükey köşelerden köşegenle bölerek dışbükey parçalara ayırır. Dönüş: [{"points", "tags"}, ...]
## (köşegen kenarlarının etiketi -1). Köşegen bulunamazsa (dejenere çokgen) parça olduğu gibi döner.
static func convex_decompose(points: PackedVector2Array, tags: PackedInt32Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var stack: Array[Dictionary] = [{"points": points, "tags": tags}]
	var guard := 0
	while not stack.is_empty() and guard < 2000:
		guard += 1
		var piece: Dictionary = stack.pop_back()
		var pts: PackedVector2Array = piece["points"]
		var tgs: PackedInt32Array = piece["tags"]
		var reflex := _first_reflex(pts)
		if reflex < 0:
			out.append(piece)
			continue
		var split := _split_at_reflex(pts, tgs, reflex)
		if split.is_empty():
			out.append(piece)
			continue
		stack.append(split[1])
		stack.append(split[0])
	return out


static func _first_reflex(pts: PackedVector2Array) -> int:
	var n := pts.size()
	for i in n:
		if _turn(pts[(i + n - 1) % n], pts[i], pts[(i + 1) % n]) < -1.0e-6:
			return i
	return -1


## İçbükey köşe i için iki parçayı döndürür ([] = uygun köşegen yok). Köşegen, i'de her iki tarafta da dışbükey
## açı bırakan en kısa geçerli köşegendir; yoksa herhangi bir geçerli köşegen.
static func _split_at_reflex(pts: PackedVector2Array, tgs: PackedInt32Array, i: int) -> Array[Dictionary]:
	var n := pts.size()
	var best := -1
	var best_len := INF
	var fallback := -1
	var fallback_len := INF
	for j in n:
		if j == i or j == (i + 1) % n or j == (i + n - 1) % n:
			continue
		if not _diagonal_inside(pts, i, j):
			continue
		var length := pts[i].distance_to(pts[j])
		if length < fallback_len:
			fallback = j
			fallback_len = length
		var prev_i := pts[(i + n - 1) % n]
		var next_i := pts[(i + 1) % n]
		var convex_both := _turn(prev_i, pts[i], pts[j]) >= -1.0e-6 and _turn(pts[j], pts[i], next_i) >= -1.0e-6
		if convex_both and length < best_len:
			best = j
			best_len = length
	var pick := best if best >= 0 else fallback
	if pick < 0:
		return []
	var a_pts := PackedVector2Array()
	var a_tags := PackedInt32Array()
	var k := i
	while true:
		a_pts.append(pts[k])
		a_tags.append(tgs[k] if k != pick else -1)
		if k == pick:
			break
		k = (k + 1) % n
	var b_pts := PackedVector2Array()
	var b_tags := PackedInt32Array()
	k = pick
	while true:
		b_pts.append(pts[k])
		b_tags.append(tgs[k] if k != i else -1)
		if k == i:
			break
		k = (k + 1) % n
	return [{"points": a_pts, "tags": a_tags}, {"points": b_pts, "tags": b_tags}]


static func _diagonal_inside(pts: PackedVector2Array, i: int, j: int) -> bool:
	var n := pts.size()
	var a := pts[i]
	var b := pts[j]
	for k in n:
		var k2 := (k + 1) % n
		if k == i or k == j or k2 == i or k2 == j:
			continue
		var params := segment_params(a, b, pts[k], pts[k2])
		if is_inf(params.x):
			continue
		if params.x > 1.0e-9 and params.x < 1.0 - 1.0e-9 and params.y > -1.0e-9 and params.y < 1.0 + 1.0e-9:
			return false
	return point_in_polygon((a + b) * 0.5, pts)


## İki DIŞBÜKEY çokgenin gerçek çakışması (ayırıcı eksen; nüfuz derinliği > eps). Yalnız değen çokgenler çakışmaz.
static func convex_overlap(a: PackedVector2Array, b: PackedVector2Array, eps: float) -> bool:
	for poly in [a, b]:
		var pp: PackedVector2Array = poly
		var n := pp.size()
		for i in n:
			var edge := pp[(i + 1) % n] - pp[i]
			var axis := Vector2(-edge.y, edge.x)
			var l := axis.length()
			if l < EPS:
				continue
			axis /= l
			var a_lo := INF
			var a_hi := -INF
			for p in a:
				var d := float(p.dot(axis))
				a_lo = minf(a_lo, d)
				a_hi = maxf(a_hi, d)
			var b_lo := INF
			var b_hi := -INF
			for p in b:
				var d := float(p.dot(axis))
				b_lo = minf(b_lo, d)
				b_hi = maxf(b_hi, d)
			if minf(a_hi, b_hi) - maxf(a_lo, b_lo) <= eps:
				return false
	return true


static func polygon_intersects_rect(poly: PackedVector2Array, rect: Rect2) -> bool:
	if not rect.intersects(bounds(poly), true):
		return false
	for p in poly:
		if rect.has_point(p):
			return true
	var corners := PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end,
			Vector2(rect.position.x, rect.end.y)])
	for c in corners:
		if point_in_polygon(c, poly):
			return true
	var n := poly.size()
	for i in n:
		var a := poly[i]
		var b := poly[(i + 1) % n]
		for k in 4:
			var params := segment_params(a, b, corners[k], corners[(k + 1) % 4])
			if not is_inf(params.x) and params.x >= 0.0 and params.x <= 1.0 and params.y >= 0.0 and params.y <= 1.0:
				return true
	return false


## Douglas-Peucker; `eps` = en büyük sapma (m). Uç noktalar korunur.
static func simplify_polyline(points: PackedVector2Array, eps: float) -> PackedVector2Array:
	var n := points.size()
	if n <= 2:
		return points
	var keep := PackedByteArray()
	keep.resize(n)
	keep[0] = 1
	keep[n - 1] = 1
	var stack: Array[Vector2i] = [Vector2i(0, n - 1)]
	while not stack.is_empty():
		var range_i: Vector2i = stack.pop_back()
		var worst := -1.0
		var worst_idx := -1
		for k in range(range_i.x + 1, range_i.y):
			var d := distance_point_segment(points[k], points[range_i.x], points[range_i.y])
			if d > worst:
				worst = d
				worst_idx = k
		if worst > eps and worst_idx >= 0:
			keep[worst_idx] = 1
			stack.append(Vector2i(range_i.x, worst_idx))
			stack.append(Vector2i(worst_idx, range_i.y))
	var out := PackedVector2Array()
	for k in n:
		if keep[k] == 1:
			out.append(points[k])
	return out
