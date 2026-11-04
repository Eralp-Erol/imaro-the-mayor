class_name KitMaterial
extends RefCounted
## Kit malzeme fabrikası (T-004, design/specs/art/building-kit-v0.md bölüm 6). Palet ve parça tablosu TEK kaynaktan
## (`kit_palette.json`) okunur; shader parametreleri buradan üretilir (elle iki yerde tutulmaz).
## Örnek verisi (MultiMesh custom data) = Color(duvar, çatı, aksan satırı, parlaklık) / 32 → `encode_instance`.

const PALETTE_PATH := "res://assets/kit/kit_palette.json"
const SHADER_PATH := "res://assets/shaders/mat_kit.gdshader"
const PROXY_SHADER_PATH := "res://assets/shaders/mat_kit_proxy.gdshader"
const ROW_COUNT := 32
const PART_COUNT := 16
const INSTANCE_SCALE := 32.0

static var _palette: Dictionary = {}


static func palette() -> Dictionary:
	if _palette.is_empty():
		var text := FileAccess.get_file_as_string(PALETTE_PATH)
		var parsed: Variant = JSON.parse_string(text)
		if parsed is Dictionary:
			_palette = parsed
		else:
			push_error("kit_palette.json okunamadı: %s" % PALETTE_PATH)
	return _palette


## Satır adı ("W1", "R3", "A2") → satır indeksi; yoksa -1.
static func row_index(row_name: String) -> int:
	for r in palette().get("rows", []):
		if str(r["name"]) == row_name:
			return int(r["row"])
	return -1


## Satırın sRGB rengi.
static func row_color(row: int) -> Color:
	for r in palette().get("rows", []):
		if int(r["row"]) == row:
			return Color.html(str(r["hex"]))
	return Color.MAGENTA


static func encode_instance(wall_row: int, roof_row: int, accent_row: int, brightness: float = 1.0) -> Color:
	return Color(wall_row / INSTANCE_SCALE, roof_row / INSTANCE_SCALE, accent_row / INSTANCE_SCALE,
			brightness / INSTANCE_SCALE)


static func create() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.resource_name = "mat_kit"
	mat.shader = load(SHADER_PATH)
	var pal := PackedVector3Array()
	pal.resize(ROW_COUNT)
	for r in palette().get("rows", []):
		var c := Color.html(str(r["hex"]))
		pal[int(r["row"])] = Vector3(c.r, c.g, c.b)
	var part_row := PackedFloat32Array()
	var part_mul := PackedFloat32Array()
	part_row.resize(PART_COUNT)
	part_mul.resize(PART_COUNT)
	for p in palette().get("parts", []):
		var id := int(p["id"])
		part_mul[id] = float(p.get("mul", 1.0))
		if p.has("row"):
			part_row[id] = float(p["row"])
		else:
			part_row[id] = {"x": -1.0, "y": -2.0, "z": -3.0}[str(p["src"])]
	mat.set_shader_parameter("palette", pal)
	mat.set_shader_parameter("part_row", part_row)
	mat.set_shader_parameter("part_mul", part_mul)
	mat.set_shader_parameter("instance_scale", INSTANCE_SCALE)
	return mat


static func create_proxy() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.resource_name = "mat_kit_proxy"
	mat.shader = load(PROXY_SHADER_PATH)
	return mat
