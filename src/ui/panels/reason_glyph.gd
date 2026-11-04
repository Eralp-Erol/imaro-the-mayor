class_name ReasonGlyph
extends Control
## Yön/uyarı simgesi, ÇİZİLİR (yazı tipi karakterine bağlı değil: ▲▼ glifleri varsayılan fontta olmayabilir).
## Renk tek başına anlam taşımaz (ux-states-a11y §1): simge her zaman yanında bir metinle kullanılır
## (Lehte/Aleyhte/Etkisiz/Veri hatası); `tooltip_text` aynı metni taşır.

enum Kind { UP, DOWN, FLAT, WARN }

var kind: Kind = Kind.FLAT
var color: Color = Color.WHITE


static func create(ctx: UiContext, glyph_kind: Kind, glyph_color: Color, caption: String) -> ReasonGlyph:
	var g := ReasonGlyph.new()
	g.kind = glyph_kind
	g.color = glyph_color
	var side := float(ctx.font_body())
	g.custom_minimum_size = Vector2(side, side)
	g.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	g.tooltip_text = caption
	return g


func _draw() -> void:
	var s := minf(size.x, size.y)
	var o := (size - Vector2(s, s)) * 0.5
	var pad := s * 0.12
	var left := o.x + pad
	var right := o.x + s - pad
	var top := o.y + pad
	var bottom := o.y + s - pad
	var mid_x := o.x + s * 0.5
	var mid_y := o.y + s * 0.5
	match kind:
		Kind.UP:
			draw_colored_polygon(PackedVector2Array([Vector2(mid_x, top), Vector2(right, bottom),
				Vector2(left, bottom)]), color)
		Kind.DOWN:
			draw_colored_polygon(PackedVector2Array([Vector2(left, top), Vector2(right, top),
				Vector2(mid_x, bottom)]), color)
		Kind.FLAT:
			draw_rect(Rect2(left, mid_y - s * 0.1, right - left, s * 0.2), color)
		Kind.WARN:
			draw_colored_polygon(PackedVector2Array([Vector2(mid_x, top), Vector2(right, bottom),
				Vector2(left, bottom)]), color)
			var dark := Color(0.06, 0.07, 0.09)
			draw_rect(Rect2(mid_x - s * 0.06, top + s * 0.32, s * 0.12, s * 0.28), dark)
			draw_rect(Rect2(mid_x - s * 0.06, bottom - s * 0.2, s * 0.12, s * 0.1), dark)
