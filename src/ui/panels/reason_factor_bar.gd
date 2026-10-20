class_name ReasonFactorBar
extends Control
## Etken çubuğu: ortadan sağa (lehte) ya da sola (aleyhte) uzanır; uzunluk |değer×ağırlık|'ın kaydın en büyük
## katkısına oranıdır (`ReasonModel.Row.bar_fraction`). Renk yönü TEK BAŞINA taşımaz: çubuğun tarafı + yanındaki
## yön simgesi ve metni (Lehte/Aleyhte) anlamı verir. Tahmini etken çerçeve alır (ve satırda "tahmin" metni
## vardır).

var fraction: float = 0.0
var is_estimate: bool = false
var is_info_only: bool = false
var color_for: Color = Color.GREEN
var color_against: Color = Color.RED
var color_track: Color = Color.DIM_GRAY
var color_axis: Color = Color.WHITE


static func create(ctx: UiContext, row: ReasonModel.Row) -> ReasonFactorBar:
	var b := ReasonFactorBar.new()
	b.fraction = row.bar_fraction
	b.is_estimate = row.is_estimate
	b.is_info_only = row.is_info_only
	b.color_for = ctx.tokens.color("ok")
	b.color_against = ctx.tokens.color("danger")
	b.color_track = ctx.tokens.color("panel_bg_alt")
	b.color_axis = ctx.tokens.color("text_muted")
	b.custom_minimum_size = Vector2(0.0, maxf(10.0, ctx.px(12.0)))
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b


## Çubuğun dolu kısmı (yerel koordinat); bilgi-yalnız ya da etkisiz için boş.
func fill_rect() -> Rect2:
	if is_info_only or fraction == 0.0:
		return Rect2()
	var half := size.x * 0.5
	var length := half * absf(fraction)
	return Rect2(half if fraction > 0.0 else half - length, 1.0, length, size.y - 2.0)


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), color_track)
	var fill := fill_rect()
	if fill.size.x > 0.0:
		draw_rect(fill, color_for if fraction > 0.0 else color_against)
		if is_estimate:
			draw_rect(fill, color_axis, false, 2.0)
	draw_line(Vector2(size.x * 0.5, 0.0), Vector2(size.x * 0.5, size.y), color_axis, 2.0)
