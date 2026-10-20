class_name TopologyRaster
extends RefCounted
## Topoloji haritası raster katmanları (T-028): WorldData'dan doğrudan örneklenen zemin görüntüsü (yükselti kuşakları,
## tepe gölgeleme, derinlik, bölge tonu), yoğunluk ızgarası ve yapı noktaları. Ayrı veri yoktur (WLD-01, TEK-03):
## her piksel `WorldData` yüksekliğinden/maskelerinden hesaplanır. Saf: Node/Time/OS yok.

const REGION_COLORS: Array[Color] = [
	Color(0.84, 0.22, 0.22), Color(0.58, 0.30, 0.78), Color(0.15, 0.42, 0.88),
	Color(0.12, 0.62, 0.28), Color(0.92, 0.52, 0.10), Color(0.80, 0.62, 0.05),
]
const WATER_SHALLOW := Color(0.66, 0.85, 0.92)
const WATER_DEEP := Color(0.20, 0.40, 0.62)
const PLAIN_LOW := Color(0.88, 0.92, 0.68)
const PLAIN_HIGH := Color(0.80, 0.88, 0.60)
const SLOPE_LOW := Color(0.68, 0.80, 0.50)
const SLOPE_HIGH := Color(0.52, 0.66, 0.38)
const RIDGE_LOW := Color(0.70, 0.63, 0.50)
const RIDGE_HIGH := Color(0.88, 0.84, 0.78)
const ISLAND_TINT := Color(0.98, 0.80, 0.42)
const WATER_DEPTH_FULL_M := 80.0


static func region_color(region_id: int) -> Color:
	return REGION_COLORS[(region_id - 1) % REGION_COLORS.size()]


## `world_rect` penceresini (dünya m) `px` boyutlu RGB8 görüntüye örnekler. Su = bilineer yükseklik < deniz seviyesi.
static func terrain_image(world: WorldData, world_rect: Rect2, px: Vector2i, region_tint: float,
		island_tint: float) -> Image:
	var img := Image.create(px.x, px.y, false, Image.FORMAT_RGB8)
	var w := world.width
	var h := world.height
	var heights := world.heights
	var cell := world.cell_size
	var sea := world.sea_level
	var step := Vector2(world_rect.size.x / float(px.x), world_rect.size.y / float(px.y))
	for py in px.y:
		var wz := world_rect.position.y + (float(py) + 0.5) * step.y
		var fz := clampf((wz - world.origin.y) / cell, 0.0, float(h - 1))
		var j0 := mini(int(fz), h - 2)
		var tz := fz - j0
		for pxx in px.x:
			var wx := world_rect.position.x + (float(pxx) + 0.5) * step.x
			var fx := clampf((wx - world.origin.x) / cell, 0.0, float(w - 1))
			var i0 := mini(int(fx), w - 2)
			var tx := fx - i0
			var idx := j0 * w + i0
			var e00 := heights[idx]
			var e10 := heights[idx + 1]
			var e01 := heights[idx + w]
			var e11 := heights[idx + w + 1]
			var eh := lerpf(lerpf(e00, e10, tx), lerpf(e01, e11, tx), tz)
			if eh < sea:
				img.set_pixel(pxx, py, WATER_SHALLOW.lerp(WATER_DEEP, sqrt(clampf((sea - eh) / WATER_DEPTH_FULL_M, 0.0, 1.0))))
				continue
			var gx := (lerpf(e10, e11, tz) - lerpf(e00, e01, tz)) / cell
			var gz := (lerpf(e01, e11, tx) - lerpf(e00, e10, tx)) / cell
			var shade := clampf(0.94 + 3.0 * (gx + gz), 0.62, 1.22)
			var col := _land_color(eh - sea)
			col = Color(col.r * shade, col.g * shade, col.b * shade)
			var near := world.world_to_index(wx, wz)
			var rid := world.region_ids[near]
			if region_tint > 0.0 and rid != WorldData.REGION_NONE:
				col = col.lerp(region_color(rid), region_tint)
			if island_tint > 0.0 and world.landmass_ids[near] > WorldData.LANDMASS_MAINLAND:
				col = col.lerp(ISLAND_TINT, island_tint)
			img.set_pixel(pxx, py, col)
	return img


static func _land_color(e: float) -> Color:
	if e < TopologyModel.PLAIN_MAX_M:
		return PLAIN_LOW.lerp(PLAIN_HIGH, e / TopologyModel.PLAIN_MAX_M)
	if e < TopologyModel.SLOPE_MAX_M:
		var t := (e - TopologyModel.PLAIN_MAX_M) / (TopologyModel.SLOPE_MAX_M - TopologyModel.PLAIN_MAX_M)
		return SLOPE_LOW.lerp(SLOPE_HIGH, t)
	return RIDGE_LOW.lerp(RIDGE_HIGH, clampf((e - TopologyModel.SLOPE_MAX_M) / 450.0, 0.0, 1.0))


## Yoğunluk renk rampası (yapı/km², `ref` = doygunluk): 0 şeffaf -> sarı -> turuncu -> kırmızı -> koyu kırmızı.
static func density_color(per_km2: float, ref: float) -> Color:
	if per_km2 <= 0.0:
		return Color(0, 0, 0, 0)
	var t := clampf(per_km2 / maxf(ref, 1.0), 0.0, 1.0)
	t = pow(t, 0.6)
	if t < 0.34:
		return Color(1.0, 0.92, 0.25, 0.30 + 0.35 * (t / 0.34))
	if t < 0.67:
		return Color(1.0, 0.62, 0.10, 0.65 + 0.10 * ((t - 0.34) / 0.33))
	return Color(0.82, 0.08, 0.10, 0.78 + 0.12 * ((t - 0.67) / 0.33))


## Model yoğunluk ızgarası -> RGBA görüntü (1 piksel = 1 yoğunluk hücresi; NEAREST ile çizilmelidir).
static func density_image(m: TopologyModel) -> Image:
	var img := Image.create(m.density_w, m.density_h, false, Image.FORMAT_RGBA8)
	for iy in m.density_h:
		for ix in m.density_w:
			img.set_pixel(ix, iy, density_color(m.density_per_km2(ix, iy), m.density_ref_per_km2))
	return img


## Pencere içindeki yapılar (nokta, kat sayısına göre renk) -> RGBA görüntü; yerleşim yoksa boş (şeffaf).
static func building_dots(m: TopologyModel, world_rect: Rect2, px: Vector2i, dot: int) -> Image:
	var img := Image.create(px.x, px.y, false, Image.FORMAT_RGBA8)
	if m.result == null:
		return img
	var cols := m.result.columns
	var scale := Vector2(float(px.x) / world_rect.size.x, float(px.y) / world_rect.size.y)
	for i in cols.count:
		var x := cols.x[i]
		var z := cols.z[i]
		if x < world_rect.position.x or z < world_rect.position.y or x >= world_rect.end.x or z >= world_rect.end.y:
			continue
		var sx := int((x - world_rect.position.x) * scale.x)
		var sy := int((z - world_rect.position.y) * scale.y)
		var floors := cols.floors[i]
		var col := Color(0.97, 0.62, 0.25, 0.95)
		if floors >= 5:
			col = Color(0.62, 0.05, 0.12, 1.0)
		elif floors >= 3:
			col = Color(0.88, 0.25, 0.12, 1.0)
		for oy in dot:
			for ox in dot:
				if sx + ox < px.x and sy + oy < px.y:
					img.set_pixel(sx + ox, sy + oy, col)
	return img
