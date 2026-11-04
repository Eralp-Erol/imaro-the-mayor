class_name RoadJunction
extends RefCounted
## Kavşak geometrisi (saf, salt okunur ağ). Önceki model düğüm başına TEK kırpma mesafesi + kol uçlarının konveks
## zarfıydı: tek dar açılı çift (ör. T'nin 35 derecelik kolu) düğümdeki TÜM kolları aynı büyük mesafeye kırpıyor,
## dev bir kama dolgusu bırakıyor ve geçiş yolunun karşı kaldırımını koparıyordu.
##
## Şimdi her kolun iki yan çizgisi (sağ/sol) AÇISAL KOMŞUSUYLA kendi yan çizgilerinin kesiştiği noktaya kadar kırpılır
## (mitre): komşu kolların birbirine bakan yan çizgileri aynı noktada (P) buluşur, şeritler çakışmadan ve boşluksuz
## döşenir; komşusuyla geniş açı yapan (> MAX_GAP ya da dışbükey taraf) yan hiç kırpılmaz, böylece düz geçen yolun
## karşı kenarı ve kaldırımı kavşaktan kesintisiz geçer. Dolgu, kolların uç köşeleri (+ dış bükey mitre) açı
## sırasıyla bir çokgendir; konveks zarf değil (kendini keserse konveks zarfa düşer).
##
## Kol kırpması `Vector2(sağ, sol)`dir: kolun düğümden dışarı yönüne göre sağ (-normal) ve sol (+normal) yan çizgisinin
## başlangıç mesafesi (m, tam genişlikte); metro görünümünde çağıran `metro_width_scale` ile çarpar (benzer geometri).

## Bu açıdan (rad) geniş komşu açılarda yan çizgiler kesişmeye zorlanmaz (düz/bükülmüş geçiş).
const MAX_GAP := PI * 170.0 / 180.0
## Çok dar açılarda formülün patlamaması için alt sınır (rad, ~8 derece).
const MIN_GAP := 0.14
## Dışbükey (dış) köşede mitre bu açının ötesinde (rad, 190 derece) eklenir; altında pah (kırpılmamış kenar) yeterli.
const MITER_MIN_GAP := PI * 190.0 / 180.0
## Dış mitre, en geniş yarı genişliğin bu katından uzaksa pah bırakılır (çok keskin dönüşte sivri uç yok).
const MITER_LIMIT := 3.0
## Kırpma kenar uzunluğunun bu oranını geçmez (iki uçtan toplam 0,9).
const MAX_TRIM_FRACTION := 0.45
const _EPS := 0.001


## Düğümdeki şerit kollar, açıya göre artan sırada: [{eid, dir, half, ang}] (half = yarı genişlik, `metro` ölçekli).
static func arms(net: WorldNetwork, style: RoadStyle, nid: int, connected: Array, metro: bool = false) -> Array:
	var center := net.node_pos(nid)
	var list: Array = []
	for eid: int in connected:
		var edge: WorldRoadEdge = net.edges[eid]
		var dir := (net.node_pos(edge.other(nid)) - center).normalized()
		list.append({"eid": eid, "dir": dir, "half": style.width_of(edge, metro) * 0.5, "ang": dir.angle()})
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["ang"] < b["ang"] or (a["ang"] == b["ang"] and a["eid"] < b["eid"]))
	return list


## Kol kimliği -> Vector2(sağ, sol) kırpma (tam genişlik, metro ölçeksiz). Saf ve deterministik.
static func arm_trims(net: WorldNetwork, style: RoadStyle, nid: int, connected: Array) -> Dictionary:
	var list := arms(net, style, nid, connected)
	var count := list.size()
	var right: Dictionary = {}
	var left: Dictionary = {}
	for arm: Dictionary in list:
		right[arm["eid"]] = 0.0
		left[arm["eid"]] = 0.0
	if count >= 2:
		for i in count:
			var a: Dictionary = list[i]
			var b: Dictionary = list[(i + 1) % count]
			var gap := _gap(a, b)
			if gap > MAX_GAP:
				continue
			var g := maxf(gap, MIN_GAP)
			var sin_g := sin(g)
			var cos_g := cos(g)
			var ha := float(a["half"])
			var hb := float(b["half"])
			# a'nın SOL yan çizgisi ile b'nin SAĞ yan çizgisinin kesişimi P; kolların eksenine izdüşümleri:
			left[a["eid"]] = maxf(float(left[a["eid"]]), maxf(0.0, (ha * cos_g + hb) / sin_g))
			right[b["eid"]] = maxf(float(right[b["eid"]]), maxf(0.0, (ha + hb * cos_g) / sin_g))
	var out: Dictionary = {}
	for arm: Dictionary in list:
		var eid: int = arm["eid"]
		var cap := (net.edges[eid] as WorldRoadEdge).length * MAX_TRIM_FRACTION
		out[eid] = Vector2(minf(float(right[eid]), cap), minf(float(left[eid]), cap))
	return out


## Saat yönünün tersine a'dan b'ye açı (0, TAU]; aynı yönlü iki kol TAU sayılmaz, MIN_GAP'e düşer.
static func _gap(a: Dictionary, b: Dictionary) -> float:
	var gap := fposmod(float(b["ang"]) - float(a["ang"]), TAU)
	if gap < 1e-6 and a["eid"] != b["eid"]:
		return MIN_GAP
	return gap if gap > 0.0 else TAU


## Kavşak dolgusu çokgeni (sıralı köşeler; kısaysa/dejenere ise boş). `arm_trims`: bu düğümün `arm_trims` çıktısı.
static func polygon(net: WorldNetwork, style: RoadStyle, nid: int, connected: Array, trims_of: Dictionary,
		metro: bool) -> PackedVector2Array:
	var factor := float(style.data["metro_width_scale"]) if metro else 1.0
	var center := net.node_pos(nid)
	var list := arms(net, style, nid, connected, metro)
	var count := list.size()
	var points := PackedVector2Array()
	for i in count:
		var arm: Dictionary = list[i]
		var dir: Vector2 = arm["dir"]
		var half := float(arm["half"])
		var normal := Vector2(-dir.y, dir.x)
		var t: Vector2 = trims_of.get(arm["eid"], Vector2.ZERO) * factor
		points.append(center + dir * t.x - normal * half)
		points.append(center + dir * t.y + normal * half)
		if count < 2:
			continue
		var next: Dictionary = list[(i + 1) % count]
		var gap := _gap(arm, next)
		if gap > MITER_MIN_GAP and gap < TAU - MIN_GAP:
			var hb := float(next["half"])
			var s := (half * cos(gap) + hb) / sin(gap)
			var miter := center + dir * s + normal * half
			if miter.distance_to(center) <= MITER_LIMIT * maxf(half, hb):
				points.append(miter)
	points = _dedupe(points)
	if points.size() < 3:
		return PackedVector2Array()
	var hull := _simple(points)
	return hull


## Ardışık (ve kapanışta ilk-son) yinelenen köşeleri atar.
static func _dedupe(points: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in points:
		if out.is_empty() or out[out.size() - 1].distance_to(p) > _EPS:
			out.append(p)
	while out.size() > 1 and out[0].distance_to(out[out.size() - 1]) <= _EPS:
		out.resize(out.size() - 1)
	return out


## Çokgen basit değilse (kendini kesen sıralama; aşırı dar/aykırı açı) konveks zarfa düşer. Alan ilk köşeye göre.
static func _simple(points: PackedVector2Array) -> PackedVector2Array:
	var local := PackedVector2Array()
	for p in points:
		local.append(p - points[0])
	var twice := 0.0
	for i in range(1, local.size() - 1):
		twice += local[i].cross(local[i + 1])
	if absf(twice) < 1e-6:
		return PackedVector2Array()
	if twice < 0.0:
		local.reverse()
	if not Geometry2D.triangulate_polygon(local).is_empty() and not _self_intersects(points):
		return points
	var hull := Geometry2D.convex_hull(points)
	if hull.size() > 3:
		hull.resize(hull.size() - 1) # convex_hull ilk köşeyi sonda tekrarlar.
	return hull


static func _self_intersects(points: PackedVector2Array) -> bool:
	var count := points.size()
	for i in count:
		var a := points[i]
		var b := points[(i + 1) % count]
		for j in range(i + 2, count):
			if (j + 1) % count == i:
				continue
			var c := points[j]
			var d := points[(j + 1) % count]
			if Geometry2D.segment_intersects_segment(a, b, c, d) != null:
				return true
	return false
