class_name HudLayout
extends RefCounted
## HUD yerleşimi: SAF hesap (düğüm yok, test edilebilir). Aynı bileşenler, profile göre farklı yerleşim
## (ux-layout-v0).
##   masaüstü            : üst şerit, altta ortada araç çubuğu, sağda L2 yan panel (en çok %28 genişlik, 400
##   tavan)
##   dokunmatik yatay    : üst şerit, alt araç çubuğu, sağda L2 yan panel (en çok %38)
##   dokunmatik dikey    : araç çubuğu iki satır, L2 ALT SAYFA (araç çubuğu dahil en çok %45 yükseklik)
## Girdi `frame` güvenli alan içi çerçeve boyutudur (UiContext.frame_size). Çıktı çerçeve koordinatlarında
## Rect2'ler.

const MODE_SIDE := &"side"
const MODE_SHEET := &"sheet"
## Araç çubuğu satırı sayısı: dikey dokunmatikte 2 (ux-layout §3.3).
const TOOLBAR_ROWS_PORTRAIT := 2

var panel_mode: StringName = MODE_SIDE
var top: Rect2 = Rect2()
var banner: Rect2 = Rect2()
var notifications: Rect2 = Rect2()
var toolbar: Rect2 = Rect2()
var toolbar_rows: int = 1
## Açık değilse boyutu sıfır.
var panel: Rect2 = Rect2()
var map_region: Rect2 = Rect2()


## `top_min_height`: üst şeridin içeriğinden gelen asgari yükseklik (iki satıra sarıldıysa tabandan
## büyüktür).
static func compute(ctx: UiContext, frame: Vector2, panel_open: bool, show_banner: bool,
		top_min_height: float = 0.0) -> HudLayout:
	var l := HudLayout.new()
	var tk := ctx.tokens
	var margin := ctx.edge_margin()
	var gap := ctx.spacing()
	var portrait_touch := ctx.is_touch() and frame.y > frame.x
	l.panel_mode = MODE_SHEET if portrait_touch else MODE_SIDE
	l.toolbar_rows = TOOLBAR_ROWS_PORTRAIT if portrait_touch else 1

	l.top = Rect2(0.0, 0.0, frame.x, maxf(ctx.bar_top_height(), top_min_height))
	var y := l.top.end.y
	if show_banner:
		l.banner = Rect2(0.0, y, frame.x, ctx.banner_height())
		y = l.banner.end.y

	var row_h := ctx.bar_toolbar_height()
	var toolbar_h := row_h * float(l.toolbar_rows) + gap * float(l.toolbar_rows - 1)
	var panel_w := 0.0
	if panel_open and l.panel_mode == MODE_SIDE:
		var frac := tk.limit("panel_frac_side_touch") if ctx.is_touch() else tk.limit("panel_frac_side_desktop")
		panel_w = minf(ctx.px(tk.size("panel_width")), floorf(frame.x * frac))
	l.map_region = Rect2(0.0, y, frame.x - panel_w, frame.y - y)

	# Araç çubuğu: harita bölgesinin alt kenarında. Masaüstünde ortada ve sınırlı genişlikte, dokunmatikte tam genişlik.
	var tb_w := l.map_region.size.x - 2.0 * margin
	if not ctx.is_touch():
		tb_w = minf(tb_w, ctx.px(tk.size("toolbar_max_width")))
	var tb_x := l.map_region.position.x + (l.map_region.size.x - tb_w) * 0.5
	l.toolbar = Rect2(tb_x, frame.y - margin - toolbar_h, tb_w, toolbar_h)

	l.notifications = Rect2(margin, y + gap, minf(ctx.px(tk.size("notif_width")), l.map_region.size.x * 0.45), 0.0)

	if panel_open:
		if l.panel_mode == MODE_SIDE:
			l.panel = Rect2(frame.x - panel_w, y, panel_w, frame.y - y)
		else:
			# Alt sayfa + araç çubuğu birlikte en çok %45 yükseklik: ekranın ortası hiçbir zaman örtülmez.
			var budget := frame.y * tk.limit("sheet_frac")
			var sheet_h := minf(ctx.px(tk.size("sheet_max_height")), budget - (toolbar_h + margin + gap))
			sheet_h = maxf(sheet_h, 0.0)
			l.panel = Rect2(0.0, l.toolbar.position.y - gap - sheet_h, frame.x, sheet_h)
	return l


## Açık panel varken haritanın MERKEZ bölgesinin (orta %50 × %50) ne kadarının HUD tarafından örtülmediği
## (0..1).
## Ölçüt: ux-ia §3 / ux-layout §6 "harita merkezi ≥ yarı görünür" (ekran görüntüsü ölçümünün
## düzen karşılığı).
func center_visible_fraction(frame: Vector2) -> float:
	var center := Rect2(frame * 0.25, frame * 0.5)
	var covered: Array[Rect2] = [top, banner, toolbar, panel]
	var steps := 40
	var visible := 0
	for ix in steps:
		for iy in steps:
			var p := center.position + Vector2((ix + 0.5) / steps * center.size.x, (iy + 0.5) / steps * center.size.y)
			var hit := false
			for r in covered:
				if r.size.x > 0.0 and r.size.y > 0.0 and r.has_point(p):
					hit = true
					break
			if not hit:
				visible += 1
	return float(visible) / float(steps * steps)
