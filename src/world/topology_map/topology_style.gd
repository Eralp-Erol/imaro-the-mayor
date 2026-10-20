class_name TopologyStyle
extends RefCounted
## Topoloji haritası çizim yardımcıları (T-028): renkler, yazı tipi (varsayılan tema yazısı), dış çizgili metin, ölçü.
## Çizim `CanvasItem` üzerinde yapılır (Control `_draw`); burada veri yoktur, yalnız biçim.

const INK := Color(0.10, 0.10, 0.12)
const INK_SOFT := Color(0.32, 0.33, 0.36)
const PAPER := Color(0.95, 0.94, 0.91)
const PANEL := Color(0.99, 0.99, 0.97)
const STAMP_INK := Color(0.72, 0.08, 0.08)
const STAMP_FILL := Color(1.0, 0.95, 0.80)
const COAST_GULF := Color(0.05, 0.20, 0.48)
const COAST_OPEN := Color(0.10, 0.34, 0.62)
const COAST_ISLAND := Color(0.80, 0.38, 0.02)
const CONTOUR := Color(0.38, 0.28, 0.14, 0.55)
const ROAD_ARTERIAL := Color(0.15, 0.12, 0.10)
const ROAD_COLLECTOR := Color(0.40, 0.33, 0.28)
const ROAD_LOCAL := Color(0.55, 0.50, 0.45, 0.55)
const RAIL := Color(0.18, 0.18, 0.55)
const FERRY := Color(0.05, 0.45, 0.78)
const GAP_LINE := Color(0.85, 0.05, 0.50)
const PORT := Color(0.85, 0.05, 0.05)
const INDUSTRY := Color(0.18, 0.18, 0.18)


static func font() -> Font:
	return ThemeDB.fallback_font


static func text_size(text: String, size: int) -> Vector2:
	return font().get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size)


## Sol-üst köşesi `top_left` olan metin (taban çizgisi içerde hesaplanır); `outline` > 0 ise açık renkli dış çizgi.
static func text(ci: CanvasItem, top_left: Vector2, content: String, size: int, color: Color = INK,
		outline: int = 0, outline_color: Color = Color(1, 1, 1, 0.9)) -> void:
	var f := font()
	var base := top_left + Vector2(0.0, f.get_ascent(size))
	if outline > 0:
		ci.draw_string_outline(f, base, content, HORIZONTAL_ALIGNMENT_LEFT, -1, size, outline, outline_color)
	ci.draw_string(f, base, content, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


## Genişliğe sarılan çok satırlı metin; çizilen yüksekliği döndürür (`draw = false` yalnız ölçer).
static func paragraph(ci: CanvasItem, top_left: Vector2, content: String, width: float, size: int,
		color: Color = INK, draw: bool = true) -> float:
	var f := font()
	var dims := f.get_multiline_string_size(content, HORIZONTAL_ALIGNMENT_LEFT, width, size)
	if draw:
		var base := top_left + Vector2(0.0, f.get_ascent(size))
		ci.draw_multiline_string(f, base, content, HORIZONTAL_ALIGNMENT_LEFT, width, size, -1, color)
	return dims.y


static func panel(ci: CanvasItem, rect: Rect2, fill: Color = PANEL, border: Color = INK_SOFT,
		width: float = 2.0) -> void:
	ci.draw_rect(rect, fill)
	ci.draw_rect(rect, border, false, width)


## Kesikli kapalı/açık çokgen çizgisi (ekran noktaları); desen çizgi boyunca kesintisiz akar.
static func dashed_polyline(ci: CanvasItem, pts: PackedVector2Array, color: Color, width: float, dash: float,
		gap: float, closed: bool = false) -> void:
	var count := pts.size() - (0 if closed else 1)
	var period := dash + gap
	var phase := 0.0
	for k in count:
		var a := pts[k]
		var b := pts[(k + 1) % pts.size()]
		var seg := a.distance_to(b)
		var dir := (b - a) / maxf(seg, 0.0001)
		var pos := 0.0
		while pos < seg:
			var in_period := fmod(phase, period)
			var limit := dash if in_period < dash else period
			var run := minf(limit - in_period, seg - pos)
			if in_period < dash:
				ci.draw_line(a + dir * pos, a + dir * (pos + run), color, width)
			pos += run
			phase += run


## Okla işaret eden ok (`from` -> `to`).
static func arrow(ci: CanvasItem, from: Vector2, to: Vector2, color: Color, width: float, head: float) -> void:
	var dir := (to - from).normalized()
	var side := Vector2(-dir.y, dir.x)
	ci.draw_line(from, to - dir * head * 0.6, color, width)
	ci.draw_colored_polygon(PackedVector2Array([to, to - dir * head + side * head * 0.5,
			to - dir * head - side * head * 0.5]), color)


## Doğru parçasını dikdörtgene keser (Liang-Barsky); dışarıdaysa boş dizi, değilse [a', b'].
static func clip_segment(a: Vector2, b: Vector2, rect: Rect2) -> PackedVector2Array:
	var t0 := 0.0
	var t1 := 1.0
	var d := b - a
	var p := [-d.x, d.x, -d.y, d.y]
	var q := [a.x - rect.position.x, rect.end.x - a.x, a.y - rect.position.y, rect.end.y - a.y]
	for i in 4:
		if is_zero_approx(p[i]):
			if q[i] < 0.0:
				return PackedVector2Array()
			continue
		var t: float = q[i] / p[i]
		if p[i] < 0.0:
			t0 = maxf(t0, t)
		else:
			t1 = minf(t1, t)
		if t0 > t1:
			return PackedVector2Array()
	return PackedVector2Array([a + d * t0, a + d * t1])
