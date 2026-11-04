class_name NetworkPreview
extends RefCounted
## WorldNetwork -> Image (hata ayıklama/önizleme; oyun içi "harita resmi" DEĞİL, WLD-01). Yalnız WorldNetwork + onun
## WorldData'sını okur. Arazi gölgeli zemin, bloklar, parseller, yol sınıfları, ray, feribot, hub/liman işaretleri.

const REGION_COLORS: Array[Color] = [
	Color(0.85, 0.35, 0.35), Color(0.65, 0.45, 0.8), Color(0.3, 0.5, 0.9),
	Color(0.4, 0.7, 0.3), Color(0.9, 0.6, 0.3), Color(0.95, 0.75, 0.25),
]
const CLASS_COLORS := {
	&"arterial": Color(0.95, 0.45, 0.1), &"collector": Color(0.95, 0.8, 0.2), &"local": Color(0.97, 0.97, 0.95),
	&"field": Color(0.7, 0.6, 0.4), &"rail": Color(0.1, 0.1, 0.1), &"ferry": Color(0.2, 0.9, 0.95),
}
const CLASS_PX := {&"arterial": 3.0, &"collector": 2.4, &"local": 1.4, &"field": 1.2, &"rail": 1.8, &"ferry": 1.6}


## `rect` dünya metresi; `px_per_m` ölçek. Katmanlar: terrain, blocks, parcels, roads, markers.
static func render(net: WorldNetwork, rect: Rect2, px_per_m: float, layers: Dictionary = {}) -> Image:
	var w := maxi(8, int(rect.size.x * px_per_m))
	var h := maxi(8, int(rect.size.y * px_per_m))
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	if layers.get("terrain", true):
		_draw_terrain(net.world, img, rect, px_per_m)
	else:
		img.fill(Color(0.85, 0.85, 0.8))
	if layers.get("blocks", true):
		_draw_blocks(net, img, rect, px_per_m)
	if layers.get("parcels", true):
		_draw_parcels(net, img, rect, px_per_m, bool(layers.get("parcel_outlines", true)))
	if layers.get("roads", true):
		_draw_edges(net, img, rect, px_per_m, float(layers.get("road_scale", 1.0)))
	if layers.get("markers", true):
		_draw_markers(net, img, rect, px_per_m)
	return img


static func _to_px(p: Vector2, rect: Rect2, s: float) -> Vector2:
	return (p - rect.position) * s


static func _draw_terrain(world: WorldData, img: Image, rect: Rect2, s: float) -> void:
	var step := 1 if s >= 1.0 else (2 if s >= 0.2 else 4)
	for y in range(0, img.get_height(), step):
		for x in range(0, img.get_width(), step):
			var p := rect.position + Vector2(x + step * 0.5, y + step * 0.5) / s
			var h := world.height_at(p.x, p.y)
			var c: Color
			if h < world.sea_level:
				var t := clampf((world.sea_level - h) / 60.0, 0.0, 1.0)
				c = Color(0.45, 0.72, 0.85).lerp(Color(0.1, 0.25, 0.5), sqrt(t))
			else:
				var e := h - world.sea_level
				var base := Color(0.78, 0.84, 0.62).lerp(Color(0.52, 0.6, 0.4), clampf(e / 250.0, 0.0, 1.0))
				var d := 60.0
				var gx := (world.height_at(p.x + d, p.y) - world.height_at(p.x - d, p.y)) / (2.0 * d)
				var gz := (world.height_at(p.x, p.y + d) - world.height_at(p.x, p.y - d)) / (2.0 * d)
				var shade := clampf(0.92 - 1.6 * (gx + gz), 0.6, 1.2)
				c = Color(base.r * shade, base.g * shade, base.b * shade)
			for dy in range(step):
				for dx in range(step):
					if x + dx < img.get_width() and y + dy < img.get_height():
						img.set_pixel(x + dx, y + dy, c)


static func _draw_blocks(net: WorldNetwork, img: Image, rect: Rect2, s: float) -> void:
	for bid: int in net.blocks:
		var b: WorldBlock = net.blocks[bid]
		if not NetworkGeometry.bounds(b.outline).intersects(rect):
			continue
		var color := Color(0, 0, 0, 0)
		match b.kind:
			WorldBlock.KIND_OPEN:
				color = Color(0.55, 0.75, 0.4, 0.35)
			WorldBlock.KIND_HOLED:
				color = Color(0.9, 0.4, 0.9, 0.4)
			WorldBlock.KIND_SLIVER:
				color = Color(0.9, 0.2, 0.2, 0.5)
			WorldBlock.KIND_UNBUILDABLE:
				color = Color(0.2, 0.2, 0.2, 0.4)
		if color.a > 0.0:
			_fill_polygon(img, b.outline, rect, s, color)


static func _draw_parcels(net: WorldNetwork, img: Image, rect: Rect2, s: float, outlines: bool) -> void:
	var ids := net.parcels_in_rect(rect)
	for pid in ids:
		var p: WorldParcel = net.parcels[pid]
		var base := REGION_COLORS[(_region_index(net, p.region_code)) % REGION_COLORS.size()]
		var tone := 0.55 + 0.25 * float(p.detail & 0xFF) / 255.0
		var fill := Color(base.r * tone + 0.25, base.g * tone + 0.25, base.b * tone + 0.25, 0.85)
		if p.fabric == &"industrial":
			fill = Color(0.6, 0.6, 0.65, 0.9)
		elif p.fabric == &"rural":
			fill = Color(0.72, 0.82, 0.5, 0.55)
		_fill_polygon(img, p.outline, rect, s, fill)
		if outlines and s >= 0.6:
			_outline_polygon(img, p.outline, rect, s, Color(0.2, 0.2, 0.25, 0.7))


static func _region_index(net: WorldNetwork, code: StringName) -> int:
	for r in net.world.regions:
		if r.code == code:
			return r.id - 1
	return 0


static func _draw_edges(net: WorldNetwork, img: Image, rect: Rect2, s: float, scale: float) -> void:
	# Düşük sınıflar önce, üst sınıflar üstte.
	for cls in [&"field", &"local", &"collector", &"arterial", &"rail", &"ferry"]:
		for eid: int in net.edges:
			var e: WorldRoadEdge = net.edges[eid]
			if e.road_class != cls:
				continue
			var a := net.node_pos(e.a)
			var b := net.node_pos(e.b)
			if not Rect2(a, Vector2.ZERO).expand(b).grow(30.0).intersects(rect):
				continue
			var px := maxf(float(CLASS_PX[cls]) * scale, 1.0)
			if s >= 1.0:
				px = maxf(e.width * s * 0.9, 1.5)
			_line(img, _to_px(a, rect, s), _to_px(b, rect, s), CLASS_COLORS[cls], px, cls == &"ferry")


static func _draw_markers(net: WorldNetwork, img: Image, rect: Rect2, s: float) -> void:
	for nid: int in net.nodes:
		var n: WorldRoadNode = net.nodes[nid]
		if not rect.has_point(n.pos):
			continue
		var color := Color(0, 0, 0, 0)
		match n.kind:
			WorldRoadNode.KIND_PORT:
				color = Color(1, 0, 0)
			WorldRoadNode.KIND_STATION:
				color = Color(0.1, 0.1, 0.1)
			WorldRoadNode.KIND_PIER:
				color = Color(0, 0.6, 1)
		if color.a > 0.0 or n.kind != &"":
			_dot(img, _to_px(n.pos, rect, s), 4, color)
	for key in net.hubs:
		var pos := net.node_pos(int(net.hubs[key]))
		if rect.has_point(pos):
			_dot(img, _to_px(pos, rect, s), 3, Color(0.1, 0.8, 0.2))


static func _dot(img: Image, c: Vector2, r: int, color: Color) -> void:
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			_put(img, int(c.x) + dx, int(c.y) + dy, color)


static func _put(img: Image, x: int, y: int, color: Color) -> void:
	if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
		return
	if color.a >= 0.999:
		img.set_pixel(x, y, Color(color.r, color.g, color.b))
	else:
		var under := img.get_pixel(x, y)
		img.set_pixel(x, y, under.lerp(Color(color.r, color.g, color.b), color.a))


static func _line(img: Image, a: Vector2, b: Vector2, color: Color, width_px: float, dashed: bool) -> void:
	var length := a.distance_to(b)
	var steps := maxi(1, int(ceil(length)))
	var r := int(floor(width_px * 0.5))
	for i in steps + 1:
		if dashed and (i / 6) % 2 == 1:
			continue
		var p := a.lerp(b, float(i) / float(steps))
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				_put(img, int(p.x) + dx, int(p.y) + dy, color)


static func _outline_polygon(img: Image, poly: PackedVector2Array, rect: Rect2, s: float, color: Color) -> void:
	var n := poly.size()
	for i in n:
		_line(img, _to_px(poly[i], rect, s), _to_px(poly[(i + 1) % n], rect, s), color, 1.0, false)


## Çift-tek tarama doldurma.
static func _fill_polygon(img: Image, poly: PackedVector2Array, rect: Rect2, s: float, color: Color) -> void:
	var n := poly.size()
	if n < 3:
		return
	var pts := PackedVector2Array()
	var lo := INF
	var hi := -INF
	for p in poly:
		var q := _to_px(p, rect, s)
		pts.append(q)
		lo = minf(lo, q.y)
		hi = maxf(hi, q.y)
	var y0 := maxi(0, int(floor(lo)))
	var y1 := mini(img.get_height() - 1, int(ceil(hi)))
	for y in range(y0, y1 + 1):
		var yc := float(y) + 0.5
		var xs: Array[float] = []
		for i in n:
			var a := pts[i]
			var b := pts[(i + 1) % n]
			if (a.y <= yc) != (b.y <= yc):
				xs.append(a.x + (yc - a.y) / (b.y - a.y) * (b.x - a.x))
		xs.sort()
		var k := 0
		while k + 1 < xs.size():
			for x in range(maxi(0, int(round(xs[k]))), mini(img.get_width(), int(round(xs[k + 1])))):
				_put(img, x, y, color)
			k += 2
