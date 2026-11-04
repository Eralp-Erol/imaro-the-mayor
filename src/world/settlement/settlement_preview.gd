class_name SettlementPreview
extends RefCounted
## T0 yerleşim debug görüntüsü (T-005; oyun içi görüntü DEĞİL, render kapısı T-012'dedir). Zemin + yollar
## NetworkPreview'dan, üstüne yapı ayak izleri. Kipler: "height" (kat sayısı), "era" (dönem), "roof" (çatı sınıfı),
## "zone" (doku).
## Yalnız SettlementResult + WorldNetwork okur.

const FLOOR_COLORS: Array[Color] = [
	Color(0.55, 0.78, 0.95), Color(0.45, 0.8, 0.6), Color(0.65, 0.85, 0.4), Color(0.95, 0.9, 0.3),
	Color(0.98, 0.7, 0.25), Color(0.95, 0.45, 0.2), Color(0.85, 0.2, 0.2), Color(0.6, 0.1, 0.4),
]
const ERA_COLORS := {0: Color(0.8, 0.45, 0.25), 1: Color(0.9, 0.85, 0.7), 2: Color(0.5, 0.65, 0.85),
		3: Color(0.3, 0.3, 0.8)}
const ROOF_COLORS := {&"terrace": Color(0.78, 0.78, 0.74), &"tile": Color(0.82, 0.38, 0.25),
		&"metal": Color(0.35, 0.5, 0.7), &"other": Color(0.5, 0.5, 0.5)}
const ZONE_COLORS := {&"center": Color(0.9, 0.2, 0.2), &"historic": Color(0.8, 0.5, 0.2),
		&"dense": Color(0.9, 0.8, 0.3),
		&"town_center": Color(0.4, 0.8, 0.5), &"town": Color(0.5, 0.7, 0.9), &"village": Color(0.6, 0.9, 0.6),
		&"hill_center": Color(0.8, 0.5, 0.8), &"hillside": Color(0.6, 0.5, 0.9), &"harbor": Color(0.2, 0.3, 0.8),
		&"yard": Color(0.3, 0.3, 0.35), &"farm": Color(0.7, 0.7, 0.4)}


static func render(res: SettlementResult, rect: Rect2, px_per_m: float, mode: String = "height") -> Image:
	var layers := {"parcels": false, "blocks": false, "markers": false, "road_scale": 0.6}
	var img := NetworkPreview.render(res.net, rect, px_per_m, layers)
	var names := SettlementStats._row_names(res)
	var bounds := Rect2i(0, 0, img.get_width(), img.get_height())
	var c := res.columns
	for i in c.count:
		var pos := c.position_of(i)
		if not rect.grow(40.0).has_point(pos):
			continue
		var m := res.module_of(i)
		var color := _color(res, names, i, mode)
		if px_per_m < 0.3:
			var q := (pos - rect.position) * px_per_m
			var r := maxi(1, int(round(sqrt(m.w * m.d) * px_per_m * 0.5)))
			img.fill_rect(Rect2i(int(q.x) - r, int(q.y) - r, 2 * r, 2 * r).intersection(bounds), color)
		else:
			_fill_quad(img, SettlementObb.corners(pos.x, pos.y, c.yaw[i], m.w, m.d), rect, px_per_m, color)
	if res.tower_index >= 0 and rect.has_point(c.position_of(res.tower_index)):
		var q2 := (c.position_of(res.tower_index) - rect.position) * px_per_m
		img.fill_rect(Rect2i(int(q2.x) - 3, int(q2.y) - 3, 7, 7).intersection(bounds), Color.MAGENTA)
	return img


static func _color(res: SettlementResult, names: Array[String], i: int, mode: String) -> Color:
	match mode:
		"era":
			return ERA_COLORS.get(int(res.columns.era[i]), Color.GRAY)
		"roof":
			return ROOF_COLORS[SettlementStats.roof_class(res, names, i)]
		"zone":
			return ZONE_COLORS.get(res.zone_of_building(i), Color.GRAY)
	return FLOOR_COLORS[clampi(int(res.columns.floors[i]) - 1, 0, FLOOR_COLORS.size() - 1)]


static func _fill_quad(img: Image, quad: PackedVector2Array, rect: Rect2, s: float, color: Color) -> void:
	var px := PackedVector2Array()
	for p in quad:
		px.append((p - rect.position) * s)
	var box := NetworkGeometry.bounds(px)
	var x0 := maxi(0, int(floor(box.position.x)))
	var x1 := mini(img.get_width() - 1, int(ceil(box.end.x)))
	var y0 := maxi(0, int(floor(box.position.y)))
	var y1 := mini(img.get_height() - 1, int(ceil(box.end.y)))
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			if NetworkGeometry.point_in_polygon(Vector2(x + 0.5, y + 0.5), px):
				img.set_pixel(x, y, color)
