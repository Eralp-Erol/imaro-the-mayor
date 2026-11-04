class_name ReasonMeter
extends Control
## Eşik ölçeği: sıfırdan "etkenlerin toplamı"na dolu çubuk + EŞİK ÇİZGİSİ (kalın, üstte ve altta tutamaçlı).
## Marj = toplam − eşik; çubuğun eşik çizgisini aşıp aşmadığı hem çizimle hem altındaki metinle (Marj … eşik
## aşıldı/ulaşılmadı) verilir. Tek bir "iyilik" göstergesi DEĞİLDİR: yalnız bu kararın toplamı ve eşiği.

var model: ReasonModel = null
var color_fill: Color = Color.CORNFLOWER_BLUE
var color_threshold: Color = Color.YELLOW
var color_track: Color = Color.DIM_GRAY
var color_axis: Color = Color.WHITE
## Eşik çizgisinin yanına yazılan kısa etiket (metin çağıranda UiText'ten gelir).
var threshold_caption: String = ""
var caption_color: Color = Color.WHITE
var caption_size: int = 12


static func create(ctx: UiContext, reason_model: ReasonModel, caption: String = "") -> ReasonMeter:
	var m := ReasonMeter.new()
	m.model = reason_model
	m.color_fill = ctx.tokens.color("accent")
	m.color_threshold = ctx.tokens.color("focus")
	m.color_track = ctx.tokens.color("panel_bg_alt")
	m.color_axis = ctx.tokens.color("text_muted")
	m.caption_color = ctx.tokens.color("text")
	m.threshold_caption = caption
	m.caption_size = ctx.font_small()
	m.custom_minimum_size = Vector2(0.0, m.caption_height() + maxf(28.0, ctx.px(28.0)))
	m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return m


## [0,1] x konumları (testler ve çizim aynı hesabı kullanır).
func score_position() -> float:
	return ReasonModel.position_in(float(model.record.score), model.scale_range())


func threshold_position() -> float:
	return ReasonModel.position_in(float(model.record.threshold), model.scale_range())


func zero_position() -> float:
	return ReasonModel.position_in(0.0, model.scale_range())


func _draw() -> void:
	if model == null:
		return
	var top := caption_height()
	var bar_top := top + 6.0
	var bar_h := maxf(8.0, size.y - bar_top - 6.0)
	draw_rect(Rect2(0.0, bar_top, size.x, bar_h), color_track)
	var x0 := zero_position() * size.x
	var xs := score_position() * size.x
	draw_rect(Rect2(minf(x0, xs), bar_top, absf(xs - x0), bar_h), color_fill)
	draw_line(Vector2(x0, bar_top), Vector2(x0, bar_top + bar_h), color_axis, 2.0)
	var xt := threshold_position() * size.x
	draw_line(Vector2(xt, top), Vector2(xt, size.y - 1.0), color_threshold, 4.0)
	if not threshold_caption.is_empty():
		var font := get_theme_default_font()
		var width := font.get_string_size(threshold_caption, HORIZONTAL_ALIGNMENT_LEFT, -1, caption_size).x
		var x := xt - width * 0.5
		x = clampf(x, 0.0, maxf(0.0, size.x - width))
		draw_string(font, Vector2(x, float(caption_size) + 1.0), threshold_caption, HORIZONTAL_ALIGNMENT_LEFT,
			-1, caption_size, caption_color)
	var cap := 6.0
	draw_colored_polygon(PackedVector2Array([Vector2(xt - cap, top), Vector2(xt + cap, top),
		Vector2(xt, top + cap * 1.4)]), color_threshold)


func caption_height() -> float:
	return float(caption_size + 4) if not threshold_caption.is_empty() else 0.0
