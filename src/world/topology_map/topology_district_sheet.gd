class_name TopologyDistrictSheet
extends Control
## D1–D6 yakın kesit sayfası (T-028 ölçüt 5): her bölge için 12 km'lik pencere (WorldData zemini, T0 yapıları nokta,
## yol/ray/feribot, kıyı, kapsam elipsi). Ayrı veri yoktur (WLD-01, TEK-03): her şey modelden. Damga her sayfada.
## `setup(model, [])` hepsini 3x2 ızgarada, tek kod verilirse o bölgeyi büyük çizer. Tasarım uzayı 2000x2000 px.

const DESIGN := 2000.0
const WINDOW_M := 12000.0
const GRID_TOP := 190.0
const GAP_PX := 30.0
const LEGEND_TOP := 1735.0

var model: TopologyModel = null

## Panel: {"code", "rect": Rect2 (tasarım), "map": Rect2, "proj": TopologyProjection, "terrain": ImageTexture,
## "dots": ImageTexture, "window": Rect2 (dünya m)}.
var _panels: Array[Dictionary] = []


@warning_ignore("integer_division")
func setup(p_model: TopologyModel, codes: Array, with_textures: bool = true) -> void:
	model = p_model
	_panels.clear()
	var wanted: Array[StringName] = []
	for r in model.regions:
		if codes.is_empty() or codes.has(r.code):
			wanted.append(r.code)
	var single := wanted.size() == 1
	var cols := 1 if single else 3
	var rows := 1 if single else int(ceil(float(wanted.size()) / 3.0))
	var avail := Vector2(DESIGN - 2.0 * 30.0, 1500.0)
	var cell_w := (avail.x - GAP_PX * float(cols - 1)) / float(cols)
	var cell_h := (avail.y - GAP_PX * float(rows - 1)) / float(rows)
	var edge := minf(cell_w, cell_h - 120.0)
	for i in wanted.size():
		var col := i % cols
		var row := i / cols
		var origin := Vector2(30.0 + col * (cell_w + GAP_PX), GRID_TOP + row * (cell_h + GAP_PX))
		_panels.append(_build_panel(wanted[i], origin, edge, with_textures))
	queue_redraw()


func panels() -> Array[Dictionary]:
	return _panels


## Test için: {"kind": &"stamp"|&"panel", "text": String, "code": StringName}.
func labels() -> Array[Dictionary]:
	var out: Array[Dictionary] = [{"kind": &"stamp", "text": TopologyModel.STAMP, "code": &""}]
	for p in _panels:
		out.append({"kind": &"panel", "text": _panel_title(p["code"]), "code": p["code"]})
	return out


func _build_panel(code: StringName, origin: Vector2, edge: float, with_textures: bool) -> Dictionary:
	var r := model.region_mark(code)
	var win := _window_for(r.centroid)
	var map_rect := Rect2(origin + Vector2(0.0, 48.0), Vector2(edge, edge))
	var px := Vector2i(int(minf(edge, 640.0)), int(minf(edge, 640.0)))
	var terrain: ImageTexture = null
	var dots: ImageTexture = null
	if with_textures:
		terrain = ImageTexture.create_from_image(TopologyRaster.terrain_image(model.world, win, px, 0.0, 0.25))
		dots = ImageTexture.create_from_image(
				TopologyRaster.building_dots(model, win, Vector2i(int(edge), int(edge)), 2 if edge < 900.0 else 3))
	return {"code": code, "rect": Rect2(origin, Vector2(edge, edge + 120.0)), "map": map_rect,
			"proj": TopologyProjection.fit(win, map_rect), "terrain": terrain, "dots": dots, "window": win}


## Bölge ağırlık merkezinde WINDOW_M kenarlı pencere; dünya sınırı içinde kalacak biçimde kaydırılır.
func _window_for(center: Vector2) -> Rect2:
	var half := WINDOW_M * 0.5
	var pos := center - Vector2(half, half)
	pos.x = clampf(pos.x, model.bounds.position.x, model.bounds.end.x - WINDOW_M)
	pos.y = clampf(pos.y, model.bounds.position.y, model.bounds.end.y - WINDOW_M)
	return Rect2(pos, Vector2(WINDOW_M, WINDOW_M))


func _panel_title(code: StringName) -> String:
	var r := model.region_mark(code)
	var name_part := "" if r.display_name.is_empty() else " · %s" % r.display_name
	return "%s%s" % [r.code, name_part]


func _draw() -> void:
	if model == null or _panels.is_empty() or _panels[0]["terrain"] == null:
		return
	var k := minf(size.x, size.y) / DESIGN
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(k, k))
	draw_rect(Rect2(Vector2.ZERO, Vector2(DESIGN, DESIGN)), TopologyStyle.PAPER)
	TopologyStyle.text(self, Vector2(30, 14), "%s — D1–D6 yakın kesit (%d km pencere)" % [
			TopologyTexts.TITLE, int(WINDOW_M / 1000.0)], 40)
	draw_rect(Rect2(30, 70, 1500, 54), TopologyStyle.STAMP_FILL)
	draw_rect(Rect2(30, 70, 1500, 54), TopologyStyle.STAMP_INK, false, 3.0)
	TopologyStyle.text(self, Vector2(46, 78), TopologyModel.STAMP, 32, TopologyStyle.STAMP_INK)
	TopologyStyle.text(self, Vector2(30, 134), "%s · %s" % [TopologyTexts.BOUNDARY_NOTE, TopologyTexts.TRACE_NOTE], 21,
			TopologyStyle.INK_SOFT)
	for p in _panels:
		_draw_panel(p)
	_draw_legend()


func _draw_panel(p: Dictionary) -> void:
	var proj: TopologyProjection = p["proj"]
	var map: Rect2 = p["map"]
	var win: Rect2 = p["window"]
	var r := model.region_mark(p["code"])
	var rect: Rect2 = p["rect"]
	draw_rect(Rect2(rect.position, Vector2(map.size.x, 44.0)), TopologyRaster.region_color(r.region_id).darkened(0.25))
	TopologyStyle.text(self, rect.position + Vector2(10, 6), _panel_title(r.code), 30, Color.WHITE)
	draw_texture_rect(p["terrain"], map, false)
	draw_texture_rect(p["dots"], map, false)
	_draw_network(proj, win)
	_draw_coast(proj, win)
	_draw_ellipse(proj, win, r)
	_draw_site_marks(proj, win)
	draw_rect(map, TopologyStyle.INK, false, 3.0)
	var stats := "kara %s km² · yapı %d · %s yapı/km² · ort. %s kat" % [TopologyTexts.num(r.land_km2, 1), r.buildings,
			TopologyTexts.num(r.buildings_per_km2, 0), TopologyTexts.num(r.mean_floors, 1)]
	TopologyStyle.text(self, Vector2(map.position.x, map.end.y + 8.0), stats, 21)
	var note := "pencere merkezi ≈ bölge ağırlık merkezi · merkez/çapa sabit değil"
	TopologyStyle.text(self, Vector2(map.position.x, map.end.y + 36.0), note, 17, TopologyStyle.INK_SOFT)
	_draw_mini_scale(proj, map)


func _clip_lines(proj: TopologyProjection, win: Rect2, pts: PackedVector2Array, color: Color, width: float,
		closed: bool = false) -> void:
	var count := pts.size() - (0 if closed else 1)
	for i in count:
		var seg := TopologyStyle.clip_segment(pts[i], pts[(i + 1) % pts.size()], win)
		if seg.size() == 2:
			draw_line(proj.to_screen(seg[0]), proj.to_screen(seg[1]), color, width)


func _draw_network(proj: TopologyProjection, win: Rect2) -> void:
	var style := {&"local": [TopologyStyle.ROAD_LOCAL, 1.2], &"field": [Color(0.5, 0.45, 0.3, 0.5), 1.0],
			&"collector": [TopologyStyle.ROAD_COLLECTOR, 2.2], &"arterial": [TopologyStyle.ROAD_ARTERIAL, 3.6],
			&"rail": [TopologyStyle.RAIL, 3.6], &"ferry": [TopologyStyle.FERRY, 4.0]}
	for cls in [&"field", &"local", &"collector", &"arterial", &"rail", &"ferry"]:
		var segs: PackedVector2Array = model.network_segments[cls]
		var col: Color = style[cls][0]
		var width: float = style[cls][1]
		for i in range(0, segs.size(), 2):
			var seg := TopologyStyle.clip_segment(segs[i], segs[i + 1], win)
			if seg.size() == 2:
				draw_line(proj.to_screen(seg[0]), proj.to_screen(seg[1]), col, width)


func _draw_coast(proj: TopologyProjection, win: Rect2) -> void:
	for c in model.coast_chains:
		var col := TopologyStyle.COAST_ISLAND
		if c["kind"] == &"gulf":
			col = TopologyStyle.COAST_GULF
		elif c["kind"] == &"open":
			col = TopologyStyle.COAST_OPEN
		_clip_lines(proj, win, c["points"], col, 3.4)


func _draw_ellipse(proj: TopologyProjection, win: Rect2, r: TopologyModel.RegionMark) -> void:
	var pts := PackedVector2Array()
	for q in r.outline:
		pts.append(q)
	var col := TopologyRaster.region_color(r.region_id).darkened(0.2)
	_clip_lines(proj, win, pts, Color(col.r, col.g, col.b, 0.9), 3.0, true)


func _draw_site_marks(proj: TopologyProjection, win: Rect2) -> void:
	for s in model.sites:
		if not win.has_point(s.position):
			continue
		var pt := proj.to_screen(s.position)
		if s.kind == &"port":
			draw_circle(pt, 12.0, Color.WHITE)
			draw_circle(pt, 9.0, TopologyStyle.PORT)
			TopologyStyle.text(self, pt + Vector2(16, -12), "T0 liman sahası", 22, TopologyStyle.PORT, 6)
		else:
			draw_rect(Rect2(pt - Vector2(10, 10), Vector2(20, 20)), Color.WHITE)
			draw_rect(Rect2(pt - Vector2(7, 7), Vector2(14, 14)), TopologyStyle.INDUSTRY)
			TopologyStyle.text(self, pt + Vector2(16, -12), "ilk sanayi", 22, TopologyStyle.INDUSTRY, 6)


func _draw_mini_scale(proj: TopologyProjection, map: Rect2) -> void:
	var bar := proj.scale_bar(map.size.x * 0.3)
	var x0 := map.position.x + 14.0
	var y0 := map.end.y - 30.0
	draw_rect(Rect2(x0 - 6.0, y0 - 30.0, float(bar["pixels"]) + 90.0, 52.0), Color(1, 1, 1, 0.85))
	draw_rect(Rect2(x0, y0, float(bar["pixels"]), 8.0), TopologyStyle.INK)
	TopologyStyle.text(self, Vector2(x0, y0 - 26.0), "%s km" % TopologyTexts.num(float(bar["meters"]) / 1000.0, 0), 20)
	var c := Vector2(map.end.x - 40.0, map.position.y + 110.0)
	draw_rect(Rect2(c.x - 26.0, map.position.y + 6.0, 52.0, 118.0), Color(1, 1, 1, 0.8))
	TopologyStyle.arrow(self, c, c + proj.north_on_screen() * 66.0, TopologyStyle.INK, 4.0, 20.0)
	TopologyStyle.text(self, Vector2(c.x - 9.0, map.position.y + 8.0), "K", 28, TopologyStyle.INK)


func _draw_legend() -> void:
	TopologyStyle.panel(self, Rect2(30, LEGEND_TOP, 1940, 235))
	var x := 50.0
	var y := LEGEND_TOP + 12.0
	TopologyStyle.text(self, Vector2(x, y), "Gösterim", 24)
	y += 40.0
	var items := [
		[Color(0.97, 0.62, 0.25), "yapı noktası: ≤2 kat"], [Color(0.88, 0.25, 0.12), "3–4 kat"],
		[Color(0.62, 0.05, 0.12), "≥5 kat (T0Settlement sütunları)"],
	]
	for it in items:
		draw_rect(Rect2(x, y + 2.0, 24.0, 16.0), it[0])
		TopologyStyle.text(self, Vector2(x + 34.0, y), it[1], 20)
		x += 36.0 + TopologyStyle.text_size(it[1], 20).x + 40.0
	x = 50.0
	y += 38.0
	var lines := [
		[TopologyStyle.ROAD_ARTERIAL, "ana cadde"], [TopologyStyle.ROAD_COLLECTOR, "toplayıcı"],
		[TopologyStyle.ROAD_LOCAL, "yerel sokak"], [TopologyStyle.RAIL, "ray"], [TopologyStyle.FERRY, "feribot"],
		[TopologyStyle.COAST_GULF, "kıyı (körfez/açık deniz/ada)"],
		[Color(0.6, 0.1, 0.1), "bölge kapsamı: yaklaşık elips (AÇIK)"],
	]
	for it in lines:
		draw_line(Vector2(x, y + 11.0), Vector2(x + 36.0, y + 11.0), it[0], 4.0)
		TopologyStyle.text(self, Vector2(x + 46.0, y), it[1], 20)
		x += 54.0 + TopologyStyle.text_size(it[1], 20).x + 30.0
	x = 50.0
	y += 38.0
	var bands := [[TopologyRaster.PLAIN_HIGH, "düz ova (<40 m)"], [TopologyRaster.SLOPE_HIGH, "yamaç (40–250 m)"],
			[TopologyRaster.RIDGE_HIGH, "sırt / yüksek (≥250 m)"]]
	for it in bands:
		draw_rect(Rect2(x, y + 2.0, 36.0, 18.0), it[0])
		draw_rect(Rect2(x, y + 2.0, 36.0, 18.0), TopologyStyle.INK_SOFT, false, 1.0)
		TopologyStyle.text(self, Vector2(x + 46.0, y), it[1], 20)
		x += 54.0 + TopologyStyle.text_size(it[1], 20).x + 30.0
	var foot := "Her pencere aynı WorldData / WorldNetwork / T0Settlement verisinin kesitidir; "
	foot += "ayrı yakın-plan verisi yoktur (WLD-01)."
	TopologyStyle.text(self, Vector2(50.0, y + 36.0), foot, 20, TopologyStyle.INK_SOFT)
