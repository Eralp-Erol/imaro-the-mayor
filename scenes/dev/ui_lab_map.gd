class_name UiLabMap
extends Control
## ui_lab için GEÇİCİ harita yer tutucusu (gerçek dünya render hattındadır, T-003/T-012): yalnız facade'in
## parsel merkezlerini ve imar/bekleyen imar durumunu çizer; seçim `InputProfile.select_requested` ile gelir.
## Gerçek veri DEĞİL: facade MOCK ise MOCK bandı HUD'dadır. Bu dosya oyun UI'ı değildir (scenes/dev).

signal parcel_picked(parcel_id: int)

const DEV_NOTE := "Harita yer tutucusu: yalnız parsel merkezlerini çizer; gerçek dünya render hattındadır."

var selected_id: int = 0

var _facade: SimFacade = null
var _ctx: UiContext = null
var _views: Array[ParcelView] = []
var _fit: Rect2 = Rect2()


func bind(facade: SimFacade, ctx: UiContext) -> void:
	_facade = facade
	_ctx = ctx
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	reload()


func set_fit_rect(rect: Rect2) -> void:
	_fit = rect
	queue_redraw()


func set_context(ctx: UiContext) -> void:
	_ctx = ctx
	queue_redraw()


func reload() -> void:
	if _facade != null:
		_views = _facade.parcel_views(_facade.parcel_ids())
	queue_redraw()


## Ekran konumuna en yakın parsel (dokunma yarıçapı hedef boyutuyla uyumlu); yoksa 0.
func pick(screen_pos: Vector2) -> int:
	var best := 0
	var best_d := _radius() * 1.4
	for v in _views:
		var d := _to_screen(v).distance_to(screen_pos)
		if d <= best_d:
			best_d = d
			best = v.id
	return best


func select(parcel_id: int) -> void:
	selected_id = parcel_id
	queue_redraw()


func marker_rect(parcel_id: int) -> Rect2:
	for v in _views:
		if v.id == parcel_id:
			var r := _radius()
			return Rect2(_to_screen(v) - Vector2(r, r), Vector2(r, r) * 2.0)
	return Rect2()


func _radius() -> float:
	return _ctx.px(28.0) if _ctx != null else 28.0


func _bounds() -> Rect2:
	if _views.is_empty():
		return Rect2(Vector2.ZERO, Vector2.ONE)
	var lo := _views[0].center
	var hi := _views[0].center
	for v in _views:
		lo = lo.min(v.center)
		hi = hi.max(v.center)
	return Rect2(lo, (hi - lo).max(Vector2.ONE))


func _to_screen(v: ParcelView) -> Vector2:
	var b := _bounds()
	var pad := _radius() * 2.0
	var bottom_pad := pad + float(_ctx.font_small() if _ctx != null else 12) * 2.0
	var area := _fit.grow_individual(-pad, -pad, -pad, -bottom_pad)
	var scale_xy := Vector2(area.size.x / b.size.x, area.size.y / b.size.y)
	var s := minf(scale_xy.x, scale_xy.y)
	var used := b.size * s
	var origin := area.position + (area.size - used) * 0.5
	return origin + (v.center - b.position) * s


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("161b21"))
	var font := get_theme_default_font()
	var fs := _ctx.font_small() if _ctx != null else 12
	var step := _radius() * 3.0
	var x := 0.0
	while x < size.x:
		draw_line(Vector2(x, 0), Vector2(x, size.y), Color(1, 1, 1, 0.04))
		x += step
	var y := 0.0
	while y < size.y:
		draw_line(Vector2(0, y), Vector2(size.x, y), Color(1, 1, 1, 0.04))
		y += step
	draw_string(font, Vector2(_fit.position.x + 12.0, _fit.end.y - 10.0), DEV_NOTE, HORIZONTAL_ALIGNMENT_LEFT,
		maxf(_fit.size.x - 24.0, 100.0), fs, Color(1, 1, 1, 0.45))
	var r := _radius()
	for v in _views:
		var c := _to_screen(v)
		var rect := Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0)
		var fill := Color("3a4452") if v.pending_zone == &"" else Color("5a4a2a")
		draw_rect(rect, fill)
		var border := Color("ffd666") if v.id == selected_id else Color("7a8594")
		draw_rect(rect, border, false, 3.0 if v.id == selected_id else 1.5)
		draw_string(font, c + Vector2(-r + 4.0, 5.0), UiText.humanize(v.ref()), HORIZONTAL_ALIGNMENT_CENTER,
			r * 2.0 - 8.0, fs, Color("eef1f4"))
		draw_string(font, c + Vector2(-r - 14.0, r + fs + 4.0), UiText.humanize(v.zone), HORIZONTAL_ALIGNMENT_CENTER,
			r * 2.0 + 28.0, fs, Color("aeb7c1"))
