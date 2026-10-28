class_name TerrainLook
extends RefCounted
## Arazi görünüm parametreleri (T-049b, VIS-01/VIS-04): `data/view/terrain_look.json` → harman gölgeleme eşikleri +
## ayrıntı gölgelendiricisi (`art/shaders/terrain_land.gdshader`) uniform'ları + deterministik gürültü dokusu.
## Renk/eşik KODDA değil veride. Saf okuma; WorldData'ya dokunmaz. Aynı veri + tohum → aynı görüntü.

const DATA_PATH := "res://data/view/terrain_look.json"
const SHADER_PATH := "res://art/shaders/terrain_land.gdshader"
## Zemin rolleri: sıra `terrain_land.gdshader` R_* sabitleriyle AYNI (slot_layer[] indeksi).
## JSON "ground.roles" anahtarları.
const GROUND_ROLES: Array[StringName] = [
	&"natural_default", &"natural_green", &"scrub", &"olive", &"rock", &"coast_sand", &"coast_gravel",
	&"field_a", &"field_b", &"field_edge", &"urban_plaza", &"urban_dirt", &"urban_green", &"urban_industrial",
	&"urban_sidewalk",
]
## Gölgelendirici uniform dizisi boyutu (tile_m[], slot_layer[]).
const MAX_LAYERS := 16

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


## `layers`: onaylı zemin kümesi (null = paylaşılan, `LibraryGate.load_default()`). Ana iş parçacığında çağrılır.
func make_material(layers: GroundLayerSet = null) -> ShaderMaterial:
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
	m.set_shader_parameter("dark_threshold", _vec2(p["dark_threshold"]))
	m.set_shader_parameter("dark_strength", float(p["dark_strength"]))
	m.set_shader_parameter("dry_threshold", _vec2(p["dry_threshold"]))
	m.set_shader_parameter("dry_strength", float(p["dry_strength"]))
	m.set_shader_parameter("patch_max_slope", float(p["max_slope_deg"]))
	m.set_shader_parameter("patch_max_height", float(p["max_height_m"]))
	m.set_shader_parameter("sea_level", float(c["sea_level_m"]))
	m.set_shader_parameter("sand_height", _vec2(c["sand_height_m"]))
	m.set_shader_parameter("sand_shore", _vec2(c["sand_shore_m"]))
	m.set_shader_parameter("gravel_height", float(c["gravel_height_m"]))
	m.set_shader_parameter("coast_max_slope", float(c["max_slope_deg"]))
	m.set_shader_parameter("coast_strength", float(c["strength"]))
	m.set_shader_parameter("rock_slope", _vec2(r["slope_deg"]))
	m.set_shader_parameter("rock_strength", float(r["strength"]))
	m.set_shader_parameter("haze_color", _color(h["color"]))
	m.set_shader_parameter("haze_range", Vector2(float(h["start_m"]), float(h["end_m"])))
	m.set_shader_parameter("haze_amount", float(h["amount"]))
	_apply_urban_params(m)
	_apply_ground_params(m, layers if layers != null else GroundLayerSet.shared())
	return m


## Rol -> katman çözümü: JSON kimliği kümede (kapıdan geçmiş) değilse yüklenmez; kapıya sorulur (ret sayılır) ve
## "ground.fallback" katmanı kullanılır. Dönüş: rol sırasıyla katman indeksleri (GROUND_ROLES).
func resolve_ground_roles(layers: GroundLayerSet) -> PackedInt32Array:
	var out := PackedInt32Array()
	var g: Dictionary = data["ground"]
	var roles: Dictionary = g["roles"]
	var fallback := str(g.get("fallback", ""))
	for role in GROUND_ROLES:
		out.append(layers.resolve(str(roles.get(String(role), "")), fallback))
	return out


## Zemin katmanı uniform'ları (T-062 A4): dizi + tile_m + rol->katman + karışım/uzaklık/alan parametreleri.
func _apply_ground_params(m: ShaderMaterial, layers: GroundLayerSet) -> void:
	if not data.has("ground"):
		return
	var g: Dictionary = data["ground"]
	if layers.array != null:
		m.set_shader_parameter("layers", layers.array)
	var tiles := PackedFloat32Array()
	tiles.resize(MAX_LAYERS)
	for i in mini(layers.count(), MAX_LAYERS):
		tiles[i] = layers.tile_m[i]
	m.set_shader_parameter("tile_m", tiles)
	var slots := PackedFloat32Array()
	slots.resize(MAX_LAYERS)
	var resolved := resolve_ground_roles(layers)
	for i in resolved.size():
		slots[i] = float(resolved[i])
	m.set_shader_parameter("slot_layer", slots)
	var b: Dictionary = g["blend"]
	m.set_shader_parameter("base_weight", float(b["base_weight"]))
	m.set_shader_parameter("blend_width", float(b["blend_width"]))
	m.set_shader_parameter("edge_jitter", float(b["edge_jitter"]))
	var dist: Dictionary = g["distance"]
	m.set_shader_parameter("detail_far", float(dist["detail_far_m"]))
	m.set_shader_parameter("fade_to_mean", _vec2(dist["fade_to_mean_m"]))
	m.set_shader_parameter("far_base_mix", float(dist["far_base_mix"]))
	m.set_shader_parameter("far_base_range", _vec2(dist["far_base_range_m"]))
	m.set_shader_parameter("scale_breaker", float(dist["breaker_scale_m"]))
	var n: Dictionary = g["natural"]
	m.set_shader_parameter("scrub_height", _vec2(n["scrub_height_m"]))
	m.set_shader_parameter("scrub_slope", _vec2(n["scrub_slope_deg"]))
	m.set_shader_parameter("scrub_weight", float(n["scrub_weight"]))
	m.set_shader_parameter("green_bias", float(n["green_bias"]))
	m.set_shader_parameter("green_gain", float(n["green_gain"]))
	m.set_shader_parameter("grove_threshold", _vec2(n["grove_threshold"]))
	m.set_shader_parameter("grove_weight", float(n["grove_weight"]))
	var f: Dictionary = g["fields"]
	m.set_shader_parameter("field_rot", float(f["rotation_rad"]))
	m.set_shader_parameter("field_size", _vec2(f["size_m"]))
	m.set_shader_parameter("field_threshold", _vec2(f["threshold"]))
	m.set_shader_parameter("field_share_a", float(f["share_plowed"]))
	m.set_shader_parameter("field_share_b", float(f["share_stubble"]))
	m.set_shader_parameter("field_edge_m", float(f["edge_m"]))


## Kent zemini uniform'ları (T-051 + T-062 A4); bölüm yoksa maske zaten uygulanmaz.
func _apply_urban_params(m: ShaderMaterial) -> void:
	if not data.has("urban"):
		return
	var u: Dictionary = data["urban"]
	m.set_shader_parameter("urban_strength", float(u["strength"]))
	m.set_shader_parameter("urban_edge", _vec2(u["edge"]))
	m.set_shader_parameter("urban_sharp_fade", _vec2(u["sharp_fade_m"]))
	m.set_shader_parameter("urban_slope", _vec2(u["slope_deg"]))
	if u.has("sidewalk"):
		m.set_shader_parameter("walk_band", _vec2(u["sidewalk"]["band"]))
		m.set_shader_parameter("walk_strength", float(u["sidewalk"]["strength"]))


## Maske parametreleri (UrbanGroundMask.build girdisi); bölüm yoksa boş.
func urban_mask_params() -> Dictionary:
	if not data.has("urban"):
		return {}
	var params: Dictionary = (data["urban"]["mask"] as Dictionary).duplicate()
	if data["urban"].has("variants"):
		params["variants"] = data["urban"]["variants"]
	return params


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
