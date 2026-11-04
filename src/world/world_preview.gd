class_name WorldPreview
extends RefCounted
## WorldData → Image (hata ayıklama/önizleme; oyun içi "harita resmi" DEĞİL, WLD-01). Yalnız WorldData okur.
## Modlar: MASK (kara/su/ada/bölge), RELIEF (hipsometrik renk + tepe gölgeleme + sığ/derin su + T0 sahaları).

enum Mode { MASK, RELIEF }

const REGION_COLORS: Array[Color] = [
	Color(0.82, 0.25, 0.25), Color(0.62, 0.36, 0.78), Color(0.2, 0.45, 0.85),
	Color(0.35, 0.65, 0.2), Color(0.8, 0.5, 0.25), Color(0.95, 0.65, 0.15),
]


static func render(world: WorldData, mode: Mode, pixel_scale: int = 1) -> Image:
	var img := Image.create(world.width * pixel_scale, world.height * pixel_scale, false, Image.FORMAT_RGB8)
	for j in world.height:
		for i in world.width:
			var c := _mask_color(world, i, j) if mode == Mode.MASK else _relief_color(world, i, j)
			for py in pixel_scale:
				for px in pixel_scale:
					img.set_pixel(i * pixel_scale + px, j * pixel_scale + py, c)
	_mark_sites(world, img, pixel_scale)
	return img


static func _mask_color(world: WorldData, i: int, j: int) -> Color:
	var idx := j * world.width + i
	if world.land_mask[idx] == 0:
		return Color(0.08, 0.2, 0.42)
	var lm := world.landmass_ids[idx]
	if lm > WorldData.LANDMASS_MAINLAND:
		return Color(0.55, 0.85, 0.35)
	var rid := world.region_ids[idx]
	if rid == WorldData.REGION_NONE:
		return Color(0.72, 0.7, 0.55)
	return REGION_COLORS[(rid - 1) % REGION_COLORS.size()]


static func _relief_color(world: WorldData, i: int, j: int) -> Color:
	var idx := j * world.width + i
	var h := world.heights[idx]
	if world.land_mask[idx] == 0:
		var depth := world.sea_level - h
		var t := clampf(depth / 60.0, 0.0, 1.0)
		return Color(0.25, 0.62, 0.78).lerp(Color(0.02, 0.1, 0.3), sqrt(t))
	var e := h - world.sea_level
	var base: Color
	if e < 40.0:
		base = Color(0.55, 0.72, 0.38).lerp(Color(0.62, 0.7, 0.35), e / 40.0)
	elif e < 250.0:
		base = Color(0.62, 0.7, 0.35).lerp(Color(0.3, 0.5, 0.22), (e - 40.0) / 210.0)
	else:
		base = Color(0.3, 0.5, 0.22).lerp(Color(0.55, 0.5, 0.42), clampf((e - 250.0) / 450.0, 0.0, 1.0))
	# Tepe gölgeleme: ışık kuzeybatıdan.
	var il := maxi(i - 1, 0)
	var ir := mini(i + 1, world.width - 1)
	var ju := maxi(j - 1, 0)
	var jd := mini(j + 1, world.height - 1)
	var gx := (world.heights[j * world.width + ir] - world.heights[j * world.width + il]) / (2.0 * world.cell_size)
	var gz := (world.heights[jd * world.width + i] - world.heights[ju * world.width + i]) / (2.0 * world.cell_size)
	var shade := clampf(0.78 + 3.5 * (gx + gz) * -0.5 * 2.0, 0.45, 1.25)
	var c := Color(base.r * shade, base.g * shade, base.b * shade)
	var rid := world.region_ids[idx]
	if rid != WorldData.REGION_NONE:
		c = c.lerp(REGION_COLORS[(rid - 1) % REGION_COLORS.size()], 0.18)
	return c


static func _mark_sites(world: WorldData, img: Image, scale: int) -> void:
	for site in world.sites:
		var p := (site.position - world.origin) / world.cell_size * scale
		var color := Color(1, 0, 0) if site.kind == &"port" else Color(1, 1, 0)
		for dy in range(-3, 4):
			for dx in range(-3, 4):
				var x := int(p.x) + dx
				var y := int(p.y) + dy
				if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
					img.set_pixel(x, y, color)
