class_name BuildingKit
extends RefCounted
## Render için kit tablosu (T-012): `kit_manifest.json` `modules[]` SIRASI = `BuildingColumns.module_idx`. Manifestten
## boyutlar (footprint, yükseklik), mesh varlığı ve HLOD1 için PROXY şablonları. Bina bilgisi YALNIZ buradan/manifestten
## okunur (kit spec §8); koda gömülü bina bilgisi yok.
##
## PROXY şablonu (`ProxyTemplate`): indekssiz üçgen listesi, köşeler (parça, gölge) GRUPLARINA göre sıralı -> HLOD1
## birleştirmede renk, grup başına tek `fill` ile üretilir (köşe başına döngü yok). Renk = palet[satır] x parça çarpanı
## x gölge x parlaklık: `mat_kit` shader'ının albedo'su ile AYNI formül (LOD1 <-> HLOD1'de ton kayması olmasın).

const SLOT_WALL := 0
const SLOT_ROOF := 1
const SLOT_ACCENT := 2
const SLOT_FIXED := 3

var library: KitLibrary = null
var count: int = 0
var ids: PackedStringArray = PackedStringArray()
var kinds: PackedStringArray = PackedStringArray()
var footprint_w: PackedFloat32Array = PackedFloat32Array()
var footprint_d: PackedFloat32Array = PackedFloat32Array()
## Toplam yükseklik (LOD0 AABB tepe, m) ve saçak yüksekliği (m).
var height_m: PackedFloat32Array = PackedFloat32Array()
var eave_m: PackedFloat32Array = PackedFloat32Array()
var lod0_tris: PackedInt32Array = PackedInt32Array()
var lod1_tris: PackedInt32Array = PackedInt32Array()
var has_lod1: PackedByteArray = PackedByteArray()
var is_landmark: PackedByteArray = PackedByteArray()
## Palet satır renkleri (sRGB, 32 satır); `KitMaterial` ile aynı kaynak.
var palette: PackedColorArray = PackedColorArray()
## Modül başına PROXY şablonu (BuildingKit.ProxyTemplate) ya da null (şablonsuz modül HLOD1'de yok sayılır).
var proxies: Array = []

var _part_slot: PackedInt32Array = PackedInt32Array()
var _part_row: PackedInt32Array = PackedInt32Array()
var _part_mul: PackedFloat32Array = PackedFloat32Array()


## PROXY şablonu: HLOD1 birleştirmede kullanılan, gruplara göre sıralı üçgen listesi.
class ProxyTemplate:
	extends RefCounted
	var vertices: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	## Grup başına: bellek içi köşe sayısı, renk yuvası (SLOT_*), sabit palet satırı (yuva sabitse), çarpan.
	var group_len: PackedInt32Array = PackedInt32Array()
	var group_slot: PackedInt32Array = PackedInt32Array()
	var group_row: PackedInt32Array = PackedInt32Array()
	var group_mul: PackedFloat32Array = PackedFloat32Array()

	func triangle_count() -> int:
		return vertices.size() / 3


## Yalnız manifest sözlüğünden (mesh yüklemeden): boyutlar ve tablo. Testler ve başsız denetim için.
static func from_manifest(manifest: Dictionary) -> BuildingKit:
	var kit := BuildingKit.new()
	var modules: Array = manifest.get("modules", [])
	kit.count = modules.size()
	for e: Dictionary in modules:
		kit.ids.append(str(e["id"]))
		kit.kinds.append(str(e.get("kind", "")))
		var fp: Array = e.get("footprint_m", [0.0, 0.0])
		kit.footprint_w.append(float(fp[0]))
		kit.footprint_d.append(float(fp[1]))
		var aabb: Dictionary = e.get("aabb_lod0_m", {})
		var top := 0.0
		if aabb.has("max"):
			top = float((aabb["max"] as Array)[1])
		kit.height_m.append(top)
		kit.eave_m.append(float(e.get("eave_height_m", top)))
		var lods: Dictionary = e.get("lods", {})
		kit.lod0_tris.append(int((lods.get("LOD0", {}) as Dictionary).get("tris", 0)))
		kit.lod1_tris.append(int((lods.get("LOD1", {}) as Dictionary).get("tris", 0)))
		kit.has_lod1.append(1 if lods.has("LOD1") else 0)
		kit.is_landmark.append(1 if str(e.get("kind", "")) == "landmark" else 0)
		kit.proxies.append(null)
	kit._load_palette()
	return kit


## Kütüphaneden: manifest + PROXY şablonları (ana iş parçacığında çağrılır; mesh okur).
static func from_library(lib: KitLibrary) -> BuildingKit:
	var kit := from_manifest(lib.manifest)
	kit.library = lib
	for i in kit.count:
		var mesh := lib.mesh(kit.ids[i], "PROXY")
		if mesh != null and mesh.get_surface_count() > 0:
			kit.proxies[i] = kit._make_template(mesh)
	return kit


func module_index(id: String) -> int:
	return ids.find(id)


## Modül LOD mesh'i (ana iş parçacığı); yoksa null.
func mesh(module: int, lod: String) -> Mesh:
	if library == null or module < 0 or module >= count:
		return null
	return library.mesh(ids[module], lod)


## Palet satırı rengi (sRGB) x çarpan, 0..1'e kırpılmış.
func shaded(row: int, mul: float) -> Color:
	var c := palette[clampi(row, 0, palette.size() - 1)]
	return Color(minf(c.r * mul, 1.0), minf(c.g * mul, 1.0), minf(c.b * mul, 1.0), 1.0)


func _load_palette() -> void:
	palette.resize(KitMaterial.ROW_COUNT)
	for r in KitMaterial.ROW_COUNT:
		palette[r] = Color(1.0, 0.0, 1.0)
	for row_entry: Dictionary in KitMaterial.palette().get("rows", []):
		palette[int(row_entry["row"])] = Color.html(str(row_entry["hex"]))
	_part_slot.resize(KitMaterial.PART_COUNT)
	_part_row.resize(KitMaterial.PART_COUNT)
	_part_mul.resize(KitMaterial.PART_COUNT)
	for p in KitMaterial.PART_COUNT:
		_part_slot[p] = SLOT_FIXED
		_part_row[p] = 0
		_part_mul[p] = 1.0
	for part: Dictionary in KitMaterial.palette().get("parts", []):
		var pid := int(part["id"])
		_part_mul[pid] = float(part.get("mul", 1.0))
		if part.has("row"):
			_part_slot[pid] = SLOT_FIXED
			_part_row[pid] = int(part["row"])
		else:
			_part_slot[pid] = {"x": SLOT_WALL, "y": SLOT_ROOF, "z": SLOT_ACCENT}[str(part["src"])]


## Mesh -> ProxyTemplate: indeks açılır, üçgenler (yuva, satır, çarpan) grubuna göre kararlı sıralanır.
func _make_template(mesh: Mesh) -> ProxyTemplate:
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	if idx.is_empty():
		idx.resize(verts.size())
		for i in verts.size():
			idx[i] = i
	var tris: Array[Dictionary] = []
	for t in range(0, idx.size() - 2, 3):
		var v0 := idx[t]
		var part := clampi(int(floor(uvs[v0].x * float(KitMaterial.PART_COUNT))), 0, KitMaterial.PART_COUNT - 1)
		var slot := _part_slot[part]
		var row := _part_row[part] if slot == SLOT_FIXED else -1
		var mul := _part_mul[part] * uvs[v0].y
		tris.append({"tri": t, "slot": slot, "row": row, "mul": snappedf(mul, 0.0001),
				"key": slot * 1000000 + (row + 1) * 10000 + int(snappedf(mul, 0.0001) * 1000.0)})
	tris.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["key"]) < int(b["key"]) or (int(a["key"]) == int(b["key"]) and int(a["tri"]) < int(b["tri"])))
	var tpl := ProxyTemplate.new()
	var last_key := -1
	for tri in tris:
		var t := int(tri["tri"])
		for k in 3:
			tpl.vertices.append(verts[idx[t + k]])
			tpl.normals.append(normals[idx[t + k]])
		if int(tri["key"]) != last_key:
			last_key = int(tri["key"])
			tpl.group_len.append(0)
			tpl.group_slot.append(int(tri["slot"]))
			tpl.group_row.append(int(tri["row"]))
			tpl.group_mul.append(float(tri["mul"]))
		tpl.group_len[tpl.group_len.size() - 1] += 3
	return tpl
