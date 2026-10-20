class_name TopologyLabelPlacer
extends RefCounted
## Etiket yerleştirici (T-028 ölçüt 5): sabit pencerede aday konumları (çapanın çevresinde, giderek uzayan halkalar)
## dener, daha önce yerleşen etiketlere ve engellere (işaretler, paneller) çarpmayan ilkini seçer. Çakışmasız yer
## yoksa en az örtüşeni seçer ve `collided = true` döner (çağıran görür). Saf: Node/Time/OS yok; sonuç deterministik.

const GAP := 6.0
## Aday halkaları: çapa uzaklığı çarpanı (etiket yüksekliği cinsinden).
const RINGS: Array[float] = [0.0, 1.0, 2.2, 3.6, 5.2, 7.2]

var bounds: Rect2 = Rect2()
var placed: Array[Rect2] = []
var obstacles: Array[Rect2] = []


func _init(p_bounds: Rect2 = Rect2()) -> void:
	bounds = p_bounds


func add_obstacle(rect: Rect2) -> void:
	obstacles.append(rect)


## Etiket çapası `anchor`, boyutu `size`. Dönüş: {"rect": Rect2, "moved": bool, "collided": bool, "distance": float}.
## `moved` = ilk tercih edilen konum alınamadı; `distance` = çapadan etikete en yakın nokta uzaklığı (px).
## `centered` = ilk aday çapanın üstünde ortalanmış (alan etiketi); aksi halde işaretin sağında.
func place(anchor: Vector2, size: Vector2, centered: bool = false) -> Dictionary:
	var best := Rect2()
	var best_cost := INF
	var best_index := 0
	var index := 0
	for ring in RINGS:
		for rect in _candidates(anchor, size, ring, centered):
			var clamped := _clamp(rect)
			var cost := _overlap_area(clamped) + (clamped.position - rect.position).length() * 40.0
			if cost < best_cost - 1.0e-6:
				best_cost = cost
				best = clamped
				best_index = index
			if cost <= 0.0:
				return _finish(best, anchor, best_index, false)
			index += 1
	return _finish(best, anchor, best_index, best_cost > 0.0)


## Verilen dikdörtgenler arasındaki çakışan çift sayısı (kenar teması çakışma sayılmaz).
static func count_overlaps(rects: Array) -> int:
	var n := 0
	for i in rects.size():
		for j in range(i + 1, rects.size()):
			if (rects[i] as Rect2).intersects(rects[j]):
				n += 1
	return n


func _finish(rect: Rect2, anchor: Vector2, index: int, collided: bool) -> Dictionary:
	placed.append(rect)
	var nearest := Vector2(clampf(anchor.x, rect.position.x, rect.end.x), clampf(anchor.y, rect.position.y, rect.end.y))
	return {"rect": rect, "moved": index > 0, "collided": collided, "distance": nearest.distance_to(anchor)}


func _candidates(anchor: Vector2, size: Vector2, ring: float, centered: bool) -> Array[Rect2]:
	var out: Array[Rect2] = []
	if ring == 0.0:
		if centered:
			out.append(Rect2(anchor - size * 0.5, size))
		else:
			out.append(Rect2(anchor + Vector2(GAP, -size.y * 0.5), size))
			out.append(Rect2(anchor + Vector2(-GAP - size.x, -size.y * 0.5), size))
		return out
	var d := ring * size.y + GAP
	var hw := size.x * 0.5
	out.append(Rect2(anchor + Vector2(d, -size.y * 0.5), size))
	out.append(Rect2(anchor + Vector2(-d - size.x, -size.y * 0.5), size))
	out.append(Rect2(anchor + Vector2(-hw, -d - size.y), size))
	out.append(Rect2(anchor + Vector2(-hw, d), size))
	out.append(Rect2(anchor + Vector2(d, -d - size.y), size))
	out.append(Rect2(anchor + Vector2(-d - size.x, -d - size.y), size))
	out.append(Rect2(anchor + Vector2(d, d), size))
	out.append(Rect2(anchor + Vector2(-d - size.x, d), size))
	return out


func _clamp(rect: Rect2) -> Rect2:
	if bounds.size == Vector2.ZERO:
		return rect
	var pos := rect.position
	pos.x = clampf(pos.x, bounds.position.x, bounds.end.x - rect.size.x)
	pos.y = clampf(pos.y, bounds.position.y, bounds.end.y - rect.size.y)
	return Rect2(pos, rect.size)


func _overlap_area(rect: Rect2) -> float:
	var total := 0.0
	for other in placed:
		total += rect.intersection(other).get_area()
	for other in obstacles:
		total += rect.intersection(other).get_area()
	return total
