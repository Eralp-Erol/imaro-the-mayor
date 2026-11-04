class_name TopologyMapView
extends Control
## Ismeral etiketli topoloji haritası — TAM HARİTA sayfası (T-028, Q-015 incelemesi). Yalnız `TopologyModel`i çizer;
## ayrı
## harita kaynağı yoktur (WLD-01, TEK-03). Tasarım uzayı 2000x2000 px'tir; kontrol boyutuna göre ölçeklenir.
## Her çizilen öğenin etiketi `compute_labels()` listesindedir (testler sayıları bu listeden doğrular).
## Damga "ÇALIŞMA VERİSİ — ONAYSIZ (Q-015)" her sayfada görünür; yer adı yok (CAN-01).

const DESIGN := 2000.0
const MAP_RECT := Rect2(30.0, 190.0, 1500.0, 1500.0)
const SIDE_RECT := Rect2(1550.0, 190.0, 430.0, 1500.0)
const TABLE_RECT := Rect2(30.0, 1706.0, 1950.0, 270.0)
const COMPASS_RECT := Rect2(44.0, 204.0, 170.0, 210.0)
const SCALE_MAX_PX := 480.0
const TERRAIN_PX_PER_SAMPLE := 3
const DENSITY_UPSCALE := 6

var model: TopologyModel = null
var show_density: bool = true
var show_network: bool = true
var show_contours: bool = true
var show_regions: bool = true

var _proj: TopologyProjection = null
var _terrain_tex: ImageTexture = null
var _density_tex: ImageTexture = null
var _labels: Array[Dictionary] = []
var _world_tag: String = ""


## `with_textures = false` yalnız etiket/geometri hesaplar (headless testler; raster üretimi atlanır).
func setup(p_model: TopologyModel, with_textures: bool = true) -> void:
	model = p_model
	_proj = TopologyProjection.fit(model.bounds, MAP_RECT)
	_world_tag = "tohum %d · dünya '%s' · hücre %d m · özet %s" % [model.world.world_seed, model.world.world_id,
			int(model.world.cell_size), model.world.state_hash().substr(0, 10)]
	_labels = compute_labels()
	if with_textures:
		_build_textures()
	queue_redraw()


func _build_textures() -> void:
	var px := Vector2i((model.world.width - 1) * TERRAIN_PX_PER_SAMPLE, (model.world.height - 1) * TERRAIN_PX_PER_SAMPLE)
	_terrain_tex = ImageTexture.create_from_image(TopologyRaster.terrain_image(model.world, model.bounds, px, 0.0, 0.3))
	var dens := TopologyRaster.density_image(model)
	dens.resize(dens.get_width() * DENSITY_UPSCALE, dens.get_height() * DENSITY_UPSCALE, Image.INTERPOLATE_NEAREST)
	_density_tex = ImageTexture.create_from_image(dens)


func projection() -> TopologyProjection:
	return _proj


func labels() -> Array[Dictionary]:
	return _labels


## Tüm etiketler (tasarım uzayı): {"kind", "text", "rect": Rect2, "anchor": Vector2, "leader": bool, "color", "size"}.
func compute_labels() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	_add_fixed_labels(out)
	var placer := TopologyLabelPlacer.new(MAP_RECT)
	placer.add_obstacle(COMPASS_RECT)
	placer.add_obstacle(_scale_rect())
	for s in model.sites:
		placer.add_obstacle(Rect2(_proj.to_screen(s.position) - Vector2(13, 13), Vector2(26, 26)))
	for isl in model.islands:
		placer.add_obstacle(Rect2(_proj.to_screen(isl.position) - Vector2(5, 5), Vector2(10, 10)))
	if int(model.yard["count"]) > 0:
		placer.add_obstacle(_proj.rect_to_screen((model.yard["rect"] as Rect2).grow(160.0)))
	for s in model.sites:
		_place(out, placer, _site_kind(s.kind), _site_text(s), _proj.to_screen(s.position), 22, _site_color(s.kind),
				false)
	for r in model.regions:
		var text := String(r.code) if r.display_name.is_empty() else "%s · %s" % [r.code, r.display_name]
		_place(out, placer, &"region", text, _proj.to_screen(r.centroid), 36,
				TopologyRaster.region_color(r.region_id).darkened(0.35), true)
	for isl in model.islands:
		_place(out, placer, &"island", String(isl.id), _proj.to_screen(isl.position), 24,
				TopologyStyle.COAST_ISLAND.darkened(0.2), false)
	if model.has_gulf:
		_place(out, placer, &"gulf", "KÖRFEZ", _proj.to_screen(model.gulf_label_pos), 34, TopologyStyle.COAST_GULF, true)
	_place(out, placer, &"open_sea", "AÇIK DENİZ", _proj.to_screen(model.open_sea_label_pos), 34,
			TopologyStyle.COAST_OPEN, true)
	_place(out, placer, &"mainland", "ANA KARA", _proj.to_screen(model.mainland_label_pos), 38,
			Color(0.20, 0.32, 0.12), true)
	if bool(model.gap.get("valid", false)):
		var mid := _proj.to_screen(((model.gap["a"] as Vector2) + (model.gap["b"] as Vector2)) * 0.5)
		var text := "D1↔D6 en kısa su aralığı ≈ %s km" % TopologyTexts.num(float(model.gap["water_gap_m"]) / 1000.0, 1)
		_place(out, placer, &"gap", text, mid, 24, TopologyStyle.GAP_LINE, false)
	return out


func _add_fixed_labels(out: Array[Dictionary]) -> void:
	out.append(_fixed(&"title", TopologyTexts.TITLE, Vector2(30, 14), 44, TopologyStyle.INK))
	var stamp_size := TopologyStyle.text_size(TopologyModel.STAMP, 32)
	out.append({"kind": &"stamp", "text": TopologyModel.STAMP, "rect": Rect2(Vector2(46, 78), stamp_size),
			"anchor": Vector2(46, 78), "leader": false, "color": TopologyStyle.STAMP_INK, "size": 32})
	out.append(_fixed(&"north", "K", COMPASS_RECT.position + Vector2(COMPASS_RECT.size.x * 0.5 - 12.0, 8), 40,
			TopologyStyle.INK))
	var bar := _proj.scale_bar(SCALE_MAX_PX)
	var km := TopologyTexts.num(float(bar["meters"]) / 1000.0, 0)
	out.append(_fixed(&"scale", "%s km" % km, _scale_rect().position + Vector2(8, 6), 22, TopologyStyle.INK))


func _fixed(kind: StringName, text: String, pos: Vector2, size: int, color: Color) -> Dictionary:
	return {"kind": kind, "text": text, "rect": Rect2(pos, TopologyStyle.text_size(text, size)), "anchor": pos,
			"leader": false, "color": color, "size": size}


func _place(out: Array[Dictionary], placer: TopologyLabelPlacer, kind: StringName, text: String, anchor: Vector2,
		size: int, color: Color, centered: bool) -> void:
	var placed := placer.place(anchor, TopologyStyle.text_size(text, size) + Vector2(4, 2), centered)
	out.append({"kind": kind, "text": text, "rect": placed["rect"], "anchor": anchor,
			"leader": bool(placed["moved"]) and not centered and float(placed["distance"]) > 36.0, "color": color, "size": size})


func _scale_rect() -> Rect2:
	var bar := _proj.scale_bar(SCALE_MAX_PX)
	return Rect2(MAP_RECT.position.x + 14.0, MAP_RECT.end.y - 78.0, float(bar["pixels"]) + 80.0, 64.0)


static func _site_kind(kind: StringName) -> StringName:
	return &"industry" if kind == &"first_industry" else kind


func _site_text(s: TopologyModel.SiteMark) -> String:
	if s.kind == &"port":
		return "T0 liman sahası · kıyıdan %s m" % TopologyTexts.num(s.shore_m, 0)
	if s.kind == &"first_industry":
		return "ilk sanayi · kıyıdan %s m" % TopologyTexts.num(s.shore_m, 0)
	return String(s.kind)


static func _site_color(kind: StringName) -> Color:
	return TopologyStyle.PORT if kind == &"port" else TopologyStyle.INDUSTRY


# ---------------------------------------------------------------- çizim

func _draw() -> void:
	if model == null or _proj == null or _terrain_tex == null:
		return
	var k := minf(size.x, size.y) / DESIGN
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(k, k))
	draw_rect(Rect2(Vector2.ZERO, Vector2(DESIGN, DESIGN)), TopologyStyle.PAPER)
	_draw_header()
	_draw_map()
	_draw_labels()
	_draw_compass_and_scale()
	_draw_side()
	_draw_table()


func _draw_header() -> void:
	draw_rect(Rect2(30, 70, 1500, 54), TopologyStyle.STAMP_FILL)
	draw_rect(Rect2(30, 70, 1500, 54), TopologyStyle.STAMP_INK, false, 3.0)
	for l in _labels:
		if l["kind"] == &"title" or l["kind"] == &"stamp":
			TopologyStyle.text(self, (l["rect"] as Rect2).position, l["text"], l["size"], l["color"])
	TopologyStyle.text(self, Vector2(30, 134), _world_tag, 22, TopologyStyle.INK_SOFT)
	TopologyStyle.text(self, Vector2(30, 160), TopologyTexts.TRACE_NOTE, 22, TopologyStyle.INK_SOFT)


func _poly(pts: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(pts.size())
	for i in pts.size():
		out[i] = _proj.to_screen(pts[i])
	return out


func _draw_map() -> void:
	draw_texture_rect(_terrain_tex, _proj.screen_rect, false)
	if show_density:
		draw_texture_rect(_density_tex, _proj.screen_rect, false)
	if show_contours:
		for c in model.contours:
			var width := 1.0 + 0.5 * float(TopologyModel.CONTOUR_LEVELS_M.find(c["level_m"]))
			draw_polyline(_poly(c["points"]), TopologyStyle.CONTOUR, width, true)
	if show_regions:
		for r in model.regions:
			var col := TopologyRaster.region_color(r.region_id)
			var ring := _poly(r.outline)
			ring.append(ring[0])
			var frame := _proj.screen_rect
			var box := PackedVector2Array([frame.position, Vector2(frame.end.x, frame.position.y), frame.end,
					Vector2(frame.position.x, frame.end.y)])
			for piece in Geometry2D.intersect_polyline_with_polygon(ring, box):
				TopologyStyle.dashed_polyline(self, piece, col.darkened(0.15), 3.5, 16.0, 10.0)
	_draw_coast()
	if show_network:
		_draw_network()
	_draw_markers()
	draw_rect(_proj.screen_rect, TopologyStyle.INK, false, 3.0)


func _draw_coast() -> void:
	for c in model.coast_chains:
		var col := TopologyStyle.COAST_ISLAND
		var width := 3.0
		match c["kind"]:
			&"gulf":
				col = TopologyStyle.COAST_GULF
				width = 4.5
			&"open":
				col = TopologyStyle.COAST_OPEN
				width = 4.5
		draw_polyline(_poly(c["points"]), col, width, true)


func _draw_network() -> void:
	_draw_class(&"arterial", TopologyStyle.ROAD_ARTERIAL, 3.2)
	_draw_class(&"collector", TopologyStyle.ROAD_COLLECTOR, 1.6)
	_draw_class(&"rail", TopologyStyle.RAIL, 3.4)
	_draw_class(&"rail", Color(1, 1, 1, 0.9), 1.1)
	for i in range(0, (model.network_segments[&"ferry"] as PackedVector2Array).size(), 2):
		var segs: PackedVector2Array = model.network_segments[&"ferry"]
		var pts := PackedVector2Array([_proj.to_screen(segs[i]), _proj.to_screen(segs[i + 1])])
		TopologyStyle.dashed_polyline(self, pts, TopologyStyle.FERRY, 4.5, 12.0, 8.0)


func _draw_class(cls: StringName, color: Color, width: float) -> void:
	var segs: PackedVector2Array = model.network_segments[cls]
	if segs.is_empty():
		return
	draw_multiline(_poly(segs), color, width)


func _draw_markers() -> void:
	if int(model.yard["count"]) > 0:
		var r := _proj.rect_to_screen((model.yard["rect"] as Rect2).grow(160.0))
		var rect_pts := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end,
				Vector2(r.position.x, r.end.y)])
		TopologyStyle.dashed_polyline(self, rect_pts, TopologyStyle.PORT, 3.0, 12.0, 7.0, true)
	for s in model.sites:
		var p := _proj.to_screen(s.position)
		if s.kind == &"port":
			draw_circle(p, 11.0, Color.WHITE)
			draw_circle(p, 8.0, TopologyStyle.PORT)
		else:
			draw_rect(Rect2(p - Vector2(9, 9), Vector2(18, 18)), Color.WHITE)
			draw_rect(Rect2(p - Vector2(6.5, 6.5), Vector2(13, 13)), TopologyStyle.INDUSTRY)
	for isl in model.islands:
		draw_circle(_proj.to_screen(isl.position), 4.0, TopologyStyle.COAST_ISLAND.darkened(0.3))
	if bool(model.gap.get("valid", false)):
		var a := _proj.to_screen(model.gap["a"])
		var b := _proj.to_screen(model.gap["b"])
		draw_line(a, b, Color.WHITE, 8.0)
		draw_line(a, b, TopologyStyle.GAP_LINE, 4.5)
		draw_circle(a, 7.0, TopologyStyle.GAP_LINE)
		draw_circle(b, 7.0, TopologyStyle.GAP_LINE)


func _draw_labels() -> void:
	for l in _labels:
		var kind: StringName = l["kind"]
		if kind in [&"title", &"stamp", &"north", &"scale"]:
			continue
		var rect: Rect2 = l["rect"]
		if bool(l["leader"]):
			var anchor: Vector2 = l["anchor"]
			var near := Vector2(clampf(anchor.x, rect.position.x, rect.end.x), clampf(anchor.y, rect.position.y, rect.end.y))
			draw_line(anchor, near, (l["color"] as Color), 1.8)
		var outline := 7 if kind in [&"gulf", &"open_sea", &"mainland"] else 6
		TopologyStyle.text(self, rect.position + Vector2(2, 1), l["text"], l["size"], l["color"], outline)


func _draw_compass_and_scale() -> void:
	TopologyStyle.panel(self, COMPASS_RECT, Color(1, 1, 1, 0.85))
	var cx := COMPASS_RECT.position.x + COMPASS_RECT.size.x * 0.5
	var north_screen := _proj.north_on_screen()
	var base := Vector2(cx, COMPASS_RECT.position.y + 150.0)
	TopologyStyle.arrow(self, base, base + north_screen * 96.0, TopologyStyle.INK, 5.0, 28.0)
	TopologyStyle.text(self, COMPASS_RECT.position + Vector2(COMPASS_RECT.size.x * 0.5 - 12.0, 8), "K", 40,
			TopologyStyle.INK)
	TopologyStyle.text(self, COMPASS_RECT.position + Vector2(12, 164), "kuzey = −z", 18, TopologyStyle.INK_SOFT)
	TopologyStyle.text(self, COMPASS_RECT.position + Vector2(12, 184), "(teknik sözleşme)", 15, TopologyStyle.INK_SOFT)
	var rect := _scale_rect()
	TopologyStyle.panel(self, rect, Color(1, 1, 1, 0.85))
	var bar := _proj.scale_bar(SCALE_MAX_PX)
	var x0 := rect.position.x + 20.0
	var y0 := rect.position.y + 36.0
	var half: float = float(bar["pixels"]) * 0.5
	draw_rect(Rect2(x0, y0, half, 12.0), TopologyStyle.INK)
	draw_rect(Rect2(x0 + half, y0, half, 12.0), Color.WHITE)
	draw_rect(Rect2(x0, y0, half * 2.0, 12.0), TopologyStyle.INK, false, 2.0)
	var meters: float = bar["meters"]
	TopologyStyle.text(self, Vector2(x0 - 4.0, rect.position.y + 6.0), "0", 20, TopologyStyle.INK)
	TopologyStyle.text(self, Vector2(x0 + half - 8.0, rect.position.y + 6.0), TopologyTexts.num(meters / 2000.0, 0), 20,
			TopologyStyle.INK)
	var end_text := "%s km" % TopologyTexts.num(meters / 1000.0, 0)
	TopologyStyle.text(self, Vector2(x0 + half * 2.0 - 10.0, rect.position.y + 6.0), end_text, 20, TopologyStyle.INK)


func _draw_side() -> void:
	TopologyStyle.panel(self, SIDE_RECT)
	var x := SIDE_RECT.position.x + 16.0
	var y := SIDE_RECT.position.y + 12.0
	y = _section(x, y, "Gösterim (açıklama)")
	y = _legend_line(x, y, TopologyStyle.COAST_GULF, "ana kara · körfez kıyısı", true)
	y = _legend_line(x, y, TopologyStyle.COAST_OPEN, "ana kara · açık deniz kıyısı", true)
	y = _legend_line(x, y, TopologyStyle.COAST_ISLAND, "ada kıyısı (turuncu ton)", true)
	y = _swatch(x, y, TopologyRaster.PLAIN_HIGH, "düz ova (<%d m)" % int(TopologyModel.PLAIN_MAX_M))
	y = _swatch(x, y, TopologyRaster.SLOPE_HIGH, "yamaç (%d–%d m)" % [int(TopologyModel.PLAIN_MAX_M),
			int(TopologyModel.SLOPE_MAX_M)])
	y = _swatch(x, y, TopologyRaster.RIDGE_HIGH, "sırt / yüksek (≥%d m)" % int(TopologyModel.SLOPE_MAX_M))
	y = _legend_line(x, y, TopologyStyle.CONTOUR, "kontur 40 / 250 / 500 m", true)
	y = _legend_line(x, y, TopologyStyle.ROAD_ARTERIAL, "ana cadde", true)
	y = _legend_line(x, y, TopologyStyle.ROAD_COLLECTOR, "toplayıcı", true)
	y = _legend_line(x, y, TopologyStyle.RAIL, "ray", true)
	y = _legend_line(x, y, TopologyStyle.FERRY, "feribot (kesikli)", true)
	y = _legend_line(x, y, TopologyStyle.GAP_LINE, "D1↔D6 en kısa su aralığı", true)
	y = _legend_line(x, y, Color(0.6, 0.1, 0.1), "bölge kapsamı (kesikli elips, AÇIK)", true)
	y = _density_ramp(x, y)
	y += 8.0
	y = _section(x, y, "Bölgeler (kapsam yaklaşık/AÇIK)")
	for r in model.regions:
		var label := String(r.code) if r.display_name.is_empty() else "%s · %s" % [r.code, r.display_name]
		y = _swatch(x, y, TopologyRaster.region_color(r.region_id), label)
	y += 8.0
	y = _section(x, y, "Sayımlar (veriden)")
	var yard_n: int = int(model.yard["count"])
	var lines := PackedStringArray([
		"bölge %d · ada %d · saha işareti %d" % [model.regions.size(), model.islands.size(), model.sites.size()],
		"yapı %d (T0Settlement)" % model.building_total, "liman sahası yapısı %d" % yard_n,
		"omurga kenarı %d (yol/ray/feribot)" % TopologyTexts.backbone_edge_count(model),
		"kara %s km² · ana kara %s km²" % [TopologyTexts.num(float(model.land_stats["land_km2"]), 0),
				TopologyTexts.num(float(model.land_stats["mainland_km2"]), 0)],
		"körfez suyu ≈ %s km²" % TopologyTexts.num(float(model.land_stats["gulf_km2"]), 0),
		"ova %%%s · yamaç %%%s · sırt %%%s" % [TopologyTexts.pct(float(model.land_stats["plain_share"])),
				TopologyTexts.pct(float(model.land_stats["slope_share"])),
				TopologyTexts.pct(float(model.land_stats["ridge_share"]))],
		"WLD-03: ana kara dışı saha %d · ada liman etiketi %d" % [model.sites_off_mainland.size(),
				model.islands_with_forbidden_tags.size()],
	])
	for line in lines:
		y += TopologyStyle.paragraph(self, Vector2(x, y), line, SIDE_RECT.size.x - 32.0, 19) + 5.0


func _section(x: float, y: float, title: String) -> float:
	TopologyStyle.text(self, Vector2(x, y), title, 24, TopologyStyle.INK)
	draw_line(Vector2(x, y + 30.0), Vector2(x + SIDE_RECT.size.x - 32.0, y + 30.0), TopologyStyle.INK_SOFT, 1.5)
	return y + 38.0


func _legend_line(x: float, y: float, color: Color, text: String, line: bool) -> float:
	if line:
		draw_line(Vector2(x, y + 11.0), Vector2(x + 46.0, y + 11.0), color, 4.0)
	TopologyStyle.text(self, Vector2(x + 58.0, y), text, 19, TopologyStyle.INK)
	return y + 27.0


func _swatch(x: float, y: float, color: Color, text: String) -> float:
	draw_rect(Rect2(x, y + 1.0, 46.0, 20.0), color)
	draw_rect(Rect2(x, y + 1.0, 46.0, 20.0), TopologyStyle.INK_SOFT, false, 1.0)
	TopologyStyle.text(self, Vector2(x + 58.0, y), text, 19, TopologyStyle.INK)
	return y + 27.0


func _density_ramp(x: float, y: float) -> float:
	TopologyStyle.text(self, Vector2(x, y), "T0 yapı yoğunluğu (250 m hücre)", 19, TopologyStyle.INK)
	y += 26.0
	var steps := 8
	for i in steps:
		var v := model.density_ref_per_km2 * float(i + 1) / float(steps)
		draw_rect(Rect2(x + i * 48.0, y, 48.0, 20.0), Color(0.9, 0.9, 0.85))
		draw_rect(Rect2(x + i * 48.0, y, 48.0, 20.0), TopologyRaster.density_color(v, model.density_ref_per_km2))
	TopologyStyle.text(self, Vector2(x, y + 22.0), "az", 17, TopologyStyle.INK_SOFT)
	var top := "çok (≥ %s yapı/km²)" % TopologyTexts.num(model.density_ref_per_km2, 0)
	TopologyStyle.text(self, Vector2(x + 8.0 * 48.0 - TopologyStyle.text_size(top, 17).x, y + 22.0), top, 17,
			TopologyStyle.INK_SOFT)
	return y + 52.0


func _draw_table() -> void:
	TopologyStyle.panel(self, TABLE_RECT)
	var x := TABLE_RECT.position.x + 16.0
	var y := TABLE_RECT.position.y + 10.0
	var title := "Bölge çalışma kapsamı (D1–D6) · %s" % TopologyTexts.BOUNDARY_NOTE
	TopologyStyle.text(self, Vector2(x, y), title, 22, TopologyStyle.INK)
	y += 34.0
	var cols := [0.0, 90.0, 250.0, 420.0, 600.0, 800.0, 1010.0]
	var heads := ["Kod", "Ad", "Kara km²", "Yapı", "Yapı/km²", "Ort. kat", "Kapsam yarıçapı (km)"]
	for c in cols.size():
		TopologyStyle.text(self, Vector2(x + float(cols[c]), y), heads[c], 20, TopologyStyle.INK_SOFT)
	y += 28.0
	for r in model.regions:
		draw_rect(Rect2(x - 6.0, y + 4.0, 14.0, 20.0), TopologyRaster.region_color(r.region_id))
		var row := [String(r.code), r.display_name if not r.display_name.is_empty() else "—",
				TopologyTexts.num(r.land_km2, 1), str(r.buildings), TopologyTexts.num(r.buildings_per_km2, 0),
				TopologyTexts.num(r.mean_floors, 1),
				"%s × %s" % [TopologyTexts.num(r.radius.x / 1000.0, 1), TopologyTexts.num(r.radius.y / 1000.0, 1)]]
		for c in cols.size():
			var cx := x + float(cols[c]) + (14.0 if c == 0 else 0.0)
			TopologyStyle.text(self, Vector2(cx, y), row[c], 21, TopologyStyle.INK)
		y += 29.0
