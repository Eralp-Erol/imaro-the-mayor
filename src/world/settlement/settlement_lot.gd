class_name SettlementLot
extends RefCounted
## Bir parselin cephe çerçevesi (T-005): başlangıç = cephe kenarının ilk köşesi, `u` cephe doğrultusu, `n` parselin
## İÇİNE bakan normal. Parsel köşeleri (u, v) koordinatlarındadır (v = cepheden derinlik). Parsel dışbükeydir
## (ağ parselleyicisi dışbükey parçalardan üretir); bu yüzden dikdörtgenin içeride olması yalnız cephe ve arka
## derinlikteki u aralıkları ile denetlenir.

var parcel_id: int = 0
var origin: Vector2 = Vector2.ZERO
var u: Vector2 = Vector2.RIGHT
var n: Vector2 = Vector2.DOWN
var pts: PackedVector2Array = PackedVector2Array()
var v_max: float = 0.0
var front_len: float = 0.0


static func from_parcel(parcel: WorldParcel) -> SettlementLot:
	var outline := parcel.outline
	var count := outline.size()
	if count < 3:
		return null
	var best := -1
	var best_d := INF
	for i in count:
		var d := NetworkGeometry.distance_point_segment(parcel.front_mid, outline[i], outline[(i + 1) % count])
		if d < best_d - 1.0e-9:
			best_d = d
			best = i
	var e0 := outline[best]
	var e1 := outline[(best + 1) % count]
	var length := e0.distance_to(e1)
	if length < 0.5:
		return null
	var lot := SettlementLot.new()
	lot.parcel_id = parcel.id
	lot.origin = e0
	lot.u = (e1 - e0) / length
	var normal := Vector2(-lot.u.y, lot.u.x)
	if float((parcel.centroid - parcel.front_mid).dot(normal)) < 0.0:
		normal = -normal
	lot.n = normal
	lot.front_len = length
	lot.pts = lot.to_frame_points(outline)
	for p in lot.pts:
		lot.v_max = maxf(lot.v_max, p.y)
	return lot


## Dünya noktalarını bu çerçevenin (u, v) koordinatlarına çevirir.
func to_frame_points(world_points: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in world_points:
		var d := p - origin
		out.append(Vector2(d.dot(u), d.dot(n)))
	return out


func to_world(pu: float, pv: float) -> Vector2:
	return origin + u * pu + n * pv


## Derinlik v'de çokgenin u aralığı (lo, hi); kesişim yoksa Vector2(INF, -INF).
func interval_at(v: float) -> Vector2:
	return interval_of(pts, v)


static func interval_of(poly: PackedVector2Array, v: float) -> Vector2:
	var lo := INF
	var hi := -INF
	var count := poly.size()
	var j := count - 1
	for i in count:
		var a := poly[i]
		var b := poly[j]
		if (a.y <= v and b.y > v) or (b.y <= v and a.y > v):
			var x_at := a.x + (b.x - a.x) * (v - a.y) / (b.y - a.y)
			lo = minf(lo, x_at)
			hi = maxf(hi, x_at)
		j = i
	return Vector2(lo, hi)


## Yapının yönü (rad): modülün +Z yüzü sokağa (içe bakan normalin tersine) bakar.
func yaw() -> float:
	return atan2(-n.x, -n.y)
