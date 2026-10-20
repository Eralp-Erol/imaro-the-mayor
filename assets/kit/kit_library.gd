class_name KitLibrary
extends RefCounted
## Kit kataloğu: `kit_manifest.json`'u okur, modül meshlerini (içe aktarılmış .glb'den) çıkarır ve önbellekler.
## T-005 (yerleşim) ve T-012 (MultiMesh/HLOD) bina bilgisini YALNIZ buradan okur (spec bölüm 8).
## Mesh: `mesh(id, "LOD0"|"LOD1"|"PROXY")` → tek surface'li ArrayMesh (malzeme çağırana aittir: `KitMaterial.create()`).

const MANIFEST_PATH := "res://assets/models/buildings/kit_manifest.json"

var manifest: Dictionary = {}
var _by_id: Dictionary = {}
var _mesh_cache: Dictionary = {}


static func load_manifest(path: String = MANIFEST_PATH) -> KitLibrary:
	var lib := KitLibrary.new()
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary:
		lib.manifest = parsed
		for e in lib.manifest.get("modules", []):
			lib._by_id[str(e["id"])] = e
	else:
		push_error("kit_manifest.json okunamadı: %s" % path)
	return lib


func ids() -> PackedStringArray:
	return PackedStringArray(_by_id.keys())


func has_id(id: String) -> bool:
	return _by_id.has(id)


func entry(id: String) -> Dictionary:
	return _by_id.get(id, {})


func entries() -> Array:
	return manifest.get("modules", [])


## Bir ailenin (ör. "res_mid") tüm kimlikleri; `gf` null ise ikisi de, true/false ise yalnız o.
func family_ids(family: String, gf: Variant = null) -> PackedStringArray:
	var out := PackedStringArray()
	for e in entries():
		if str(e["family"]) == family and (gf == null or bool(e["gf"]) == bool(gf)):
			out.append(str(e["id"]))
	return out


## .glb sahnesini örnekler. Önce içe aktarılmış kaynak; yoksa (import koşmamış ortam) çalışma zamanında glTF okuma.
static func instantiate_scene(glb_path: String) -> Node:
	if ResourceLoader.exists(glb_path):
		var packed := load(glb_path) as PackedScene
		if packed != null:
			return packed.instantiate()
	var state := GLTFState.new()
	var doc := GLTFDocument.new()
	if doc.append_from_file(ProjectSettings.globalize_path(glb_path), state) != OK:
		return null
	return doc.generate_scene(state)


func mesh(id: String, lod: String = "LOD0") -> Mesh:
	var key := "%s/%s" % [id, lod]
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var e := entry(id)
	if e.is_empty():
		return null
	var root := instantiate_scene(str(e["glb"]))
	if root == null:
		return null
	var wanted := "%s_%s" % [id, lod]
	var found: Mesh = null
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if n is MeshInstance3D and n.name == wanted:
			found = (n as MeshInstance3D).mesh
	root.free()
	if found != null:
		_mesh_cache[key] = found
	return found
