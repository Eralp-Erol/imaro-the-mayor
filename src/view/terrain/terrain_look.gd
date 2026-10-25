class_name TerrainLook
extends RefCounted
## Arazi görünüm parametreleri (T-049b, VIS-01/VIS-04): `data/view/terrain_look.json` → harman gölgeleme eşikleri +
## ayrıntı gölgelendiricisi (`art/shaders/terrain_land.gdshader`) uniform'ları + deterministik gürültü dokusu.
## Renk/eşik KODDA değil veride. Saf okuma; WorldData'ya dokunmaz. Aynı veri + tohum → aynı görüntü.

const DATA_PATH := "res://data/view/terrain_look.json"
const SHADER_PATH := "res://art/shaders/terrain_land.gdshader"

static var _cache: TerrainLook = null

var data: Dictionary = {}


## Önbellekli varsayılan (dosya). İş parçacıklarından ÖNCE ana iş parçacığında çağrılmalı.
static func shared() -> TerrainLook:
	if _cache == null:
		_cache = TerrainLook.from_file(DATA_PATH)
	return _cache


static func from_file(path: String) -> TerrainLook:
	var look := TerrainLook.new()
	var text := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		look.data = parsed
	return look


func is_valid() -> bool:
	for key in ["shading", "noise", "detail", "patches", "coast", "rock", "haze"]:
		if not data.has(key) or not (data[key] is Dictionary):
			return false
	return true


## Üçgen faset ağırlığı eşiği (derece): altında yumuşak, üstünde keskin (low-poly yamaç kenarı).
func facet_slope_deg() -> Vector2:
	return _vec2(data["shading"]["facet_slope_deg"])


## Faset ağırlığı [0, 1] (üçgenin gerçek eğimi): 0 = tam yumuşak normal, 1 = tam faset.
func facet_weight(tri_slope_deg: float) -> float:
	var e := facet_slope_deg()
	return smoothstep(e.x, e.y, tri_slope_deg)


## Kıyı kumu ağırlığı [0, 1] (CPU aynası; gölgelendirici aynı kuralı uygular): deniz seviyesinden yükseklik ve eğim.
func sand_weight(height_above_sea_m: float, slope_deg: float, shore_m: float = 0.0) -> float:
	var c: Dictionary = data["coast"]
	var band := _vec2(c["sand_height_m"])
	var t := 1.0 - smoothstep(band.x, band.y, height_above_sea_m)
	t *= 1.0 - smoothstep(float(c["max_slope_deg"]) * 0.5, float(c["max_slope_deg"]), slope_deg)
	t *= 1.0 - smoothstep(_vec2(c["sand_shore_m"]).x, _vec2(c["sand_shore_m"]).y, shore_m)
	return t * float(c["strength"])


## Dik yamaç kaya ağırlığı [0, 1] (CPU aynası).
func rock_weight(slope_deg: float) -> float:
	var r: Dictionary = data["rock"]
	var e := _vec2(r["slope_deg"])
	return smoothstep(e.x, e.y, slope_deg) * float(r["strength"])


## Tileable değer gürültüsü dokusu (RGBA8, mipmap'li): kanal başına farklı kafes. Deterministik (tohum + veri).
func make_noise_texture() -> ImageTexture:
	var n: Dictionary = data["noise"]
	var size := int(n["size_px"])
	var lattice: Array = n["lattice"]
	var seed_v := int(n["seed"])
	var img := Image.create(size, size, true, Image.FORMAT_RGBA8)
	var chans: Array = []
	for c in 4:
		chans.append(_lattice_values(int(lattice[c]), seed_v + 977 * (c + 1)))
	for y in size:
		for x in size:
			var col := Color(0, 0, 0, 1)
			for c in 4:
				var cells := int(lattice[c])
				col[c] = _tile_noise(chans[c], cells, float(x) / size * cells, float(y) / size * cells)
			img.set_pixel(x, y, col)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func make_material() -> ShaderMaterial:
	var d: Dictionary = data["detail"]
	var p: Dictionary = data["patches"]
	var c: Dictionary = data["coast"]
	var r: Dictionary = data["rock"]
	var h: Dictionary = data["haze"]
	var m := ShaderMaterial.new()
	m.shader = load(SHADER_PATH)
	m.set_shader_parameter("noise_tex", make_noise_texture())
	m.set_shader_parameter("scale_fine", float(d["scale_fine_m"]))
	m.set_shader_parameter("scale_mid", float(d["scale_mid_m"]))
	m.set_shader_parameter("scale_patch", float(d["scale_patch_m"]))
	m.set_shader_parameter("patch_rot", float(d["patch_rotation_rad"]))
	m.set_shader_parameter("tone_fine", float(d["tone_fine"]))
	m.set_shader_parameter("tone_mid", float(d["tone_mid"]))
	m.set_shader_parameter("fine_fade", _vec2(d["fine_fade_m"]))
	m.set_shader_parameter("dark_color", _color(p["dark_color"]))
	m.set_shader_parameter("dark_threshold", _vec2(p["dark_threshold"]))
	m.set_shader_parameter("dark_strength", float(p["dark_strength"]))
	m.set_shader_parameter("dry_color", _color(p["dry_color"]))
	m.set_shader_parameter("dry_threshold", _vec2(p["dry_threshold"]))
	m.set_shader_parameter("dry_strength", float(p["dry_strength"]))
	m.set_shader_parameter("patch_max_slope", float(p["max_slope_deg"]))
	m.set_shader_parameter("patch_max_height", float(p["max_height_m"]))
	m.set_shader_parameter("sea_level", float(c["sea_level_m"]))
	m.set_shader_parameter("sand_color", _color(c["sand_color"]))
	m.set_shader_parameter("gravel_color", _color(c["gravel_color"]))
	m.set_shader_parameter("sand_height", _vec2(c["sand_height_m"]))
	m.set_shader_parameter("sand_shore", _vec2(c["sand_shore_m"]))
	m.set_shader_parameter("gravel_height", float(c["gravel_height_m"]))
	m.set_shader_parameter("coast_max_slope", float(c["max_slope_deg"]))
	m.set_shader_parameter("coast_strength", float(c["strength"]))
	m.set_shader_parameter("rock_color", _color(r["color"]))
	m.set_shader_parameter("rock_color_dark", _color(r["color_dark"]))
	m.set_shader_parameter("rock_slope", _vec2(r["slope_deg"]))
	m.set_shader_parameter("rock_strength", float(r["strength"]))
	m.set_shader_parameter("strata_period", float(r["strata_period_m"]))
	m.set_shader_parameter("strata_amount", float(r["strata_amount"]))
	m.set_shader_parameter("haze_color", _color(h["color"]))
	m.set_shader_parameter("haze_range", Vector2(float(h["start_m"]), float(h["end_m"])))
	m.set_shader_parameter("haze_amount", float(h["amount"]))
	_apply_urban_params(m)
	return m


## Kent zemini renk/eşik uniform'ları (T-051); bölüm yoksa maske zaten uygulanmaz.
func _apply_urban_params(m: ShaderMaterial) -> void:
	if not data.has("urban"):
		return
	var u: Dictionary = data["urban"]
	m.set_shader_parameter("urban_res_a", _color(u["residential"]["color_a"]))
	m.set_shader_parameter("urban_res_b", _color(u["residential"]["color_b"]))
	m.set_shader_parameter("urban_ind_a", _color(u["industrial"]["color_a"]))
	m.set_shader_parameter("urban_ind_b", _color(u["industrial"]["color_b"]))
	m.set_shader_parameter("urban_strength", float(u["strength"]))
	m.set_shader_parameter("urban_edge", _vec2(u["edge"]))
	m.set_shader_parameter("urban_sharp_fade", _vec2(u["sharp_fade_m"]))
	m.set_shader_parameter("urban_slope", _vec2(u["slope_deg"]))
	m.set_shader_parameter("urban_tone", float(u["tone"]))


## Maske parametreleri (UrbanGroundMask.build girdisi); bölüm yoksa boş.
func urban_mask_params() -> Dictionary:
	return (data["urban"]["mask"] as Dictionary) if data.has("urban") else {}


static func _vec2(a: Array) -> Vector2:
	return Vector2(float(a[0]), float(a[1]))


static func _color(a: Array) -> Color:
	return Color(float(a[0]), float(a[1]), float(a[2]))


static func _lattice_values(cells: int, seed_v: int) -> PackedFloat32Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var out := PackedFloat32Array()
	out.resize(cells * cells)
	for k in out.size():
		out[k] = rng.randf()
	return out


## Periyodik (tileable) kafes değer gürültüsü: kafes `cells` x `cells`, kenarlar sarılır.
static func _tile_noise(values: PackedFloat32Array, cells: int, u: float, v: float) -> float:
	var iu := floori(u)
	var iv := floori(v)
	var fu := smoothstep(0.0, 1.0, u - iu)
	var fv := smoothstep(0.0, 1.0, v - iv)
	var u0 := posmod(iu, cells)
	var v0 := posmod(iv, cells)
	var u1 := posmod(iu + 1, cells)
	var v1 := posmod(iv + 1, cells)
	var a := values[v0 * cells + u0]
	var b := values[v0 * cells + u1]
	var c := values[v1 * cells + u0]
	var d := values[v1 * cells + u1]
	return lerpf(lerpf(a, b, fu), lerpf(c, d, fu), fv)
