class_name SettlementObb
extends RefCounted
## Yönlü dikdörtgen (yapı ayak izi) yardımcıları (T-005). Modül yerel ekseni: +X sağ, +Z cephe (sokağa bakar);
## Y ekseni dönüşü `yaw`: yerel +X -> (cos, -sin), yerel +Z -> (sin, cos) (dünya x, z). Saf, statik.


## Merkez (cx, cz), yön, genişlik (yerel X) ve derinlik (yerel Z) -> 4 köşe (dünya x, z).
static func corners(cx: float, cz: float, yaw: float, w: float, d: float) -> PackedVector2Array:
	var ax := Vector2(cos(yaw), -sin(yaw)) * (w * 0.5)
	var az := Vector2(sin(yaw), cos(yaw)) * (d * 0.5)
	var c := Vector2(cx, cz)
	return PackedVector2Array([c - ax - az, c + ax - az, c + ax + az, c - ax + az])


## İki dikdörtgenin gerçek çakışması (nüfuz derinliği > eps; yalnız değme çakışma sayılmaz).
static func overlap(a: PackedVector2Array, b: PackedVector2Array, eps: float = 0.02) -> bool:
	return NetworkGeometry.convex_overlap(a, b, eps)


## Köşeleri merkeze doğru `inset` metre daraltır (sınır kararsızlığına karşı nokta-poligon denetimi için).
static func shrunk(corner_points: PackedVector2Array, inset: float) -> PackedVector2Array:
	var center := Vector2.ZERO
	for p in corner_points:
		center += p
	center /= float(corner_points.size())
	var out := PackedVector2Array()
	for p in corner_points:
		var d := center - p
		var l := d.length()
		out.append(p + d * (minf(inset, l * 0.5) / maxf(l, 1.0e-6)))
	return out
