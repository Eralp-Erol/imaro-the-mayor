class_name MeterBar
extends Control
## Yatay oran çubuğu (koltuk payı, gider payı, oy dağılımı). Değer HER ZAMAN yanında sayı/metinle verilir; çubuk
## yalnız görseldir (renk tek başına anlam taşımaz). Çerçeve çizilir ki dolu/boş renge bakmadan ayırt edilsin.

var permille: int = 0
var color_fill: Color = Color.CORNFLOWER_BLUE
var color_track: Color = Color.DIM_GRAY
var color_frame: Color = Color.WHITE


static func create(ctx: UiContext, value_permille: int, fill_token: String = "accent") -> MeterBar:
	var m := MeterBar.new()
	m.permille = clampi(value_permille, 0, 1000)
	m.color_fill = ctx.tokens.color(fill_token)
	m.color_track = ctx.tokens.color("panel_bg")
	m.color_frame = ctx.tokens.color("text_muted")
	m.custom_minimum_size = Vector2(0.0, maxf(10.0, ctx.px(12.0)))
	m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	m.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return m


## Dolu bölümün dikdörtgeni (yerel koordinat).
func fill_rect() -> Rect2:
	return Rect2(1.0, 1.0, maxf(0.0, (size.x - 2.0) * float(permille) / 1000.0), maxf(0.0, size.y - 2.0))


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), color_track)
	var fill := fill_rect()
	if fill.size.x > 0.0:
		draw_rect(fill, color_fill)
	draw_rect(Rect2(Vector2.ZERO, size), color_frame, false, 1.0)
