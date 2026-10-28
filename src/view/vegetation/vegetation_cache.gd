class_name VegetationCache
extends RefCounted
## B0 bitki sütunlarının disk önbelleği (T-062 B1, dünya yükleme): yerleşim ~14 sn sürer (headless ölçüm), önbellek
## isabetinde milisaniye. DETERMİNİZM: önbellek yalnız aynı GİRDİ anahtarı için geçerlidir; anahtar tohum, kural JSON'u,
## tür tablosu, dünya/yerleşim/ağ özetleri ve üreteç kaynak dosyalarının özetini kapsar. Dosya içeriği ayrıca
## `state_hash` ile doğrulanır; bozuk/eksik dosya = isabetsizlik (yeniden üretilir), asla sessiz yanlış veri değil.
## Konum `user://cache/` (depoda DEĞİL). Saf veri katmanı: node yok.

const MAGIC := "imaro-veg-cache/1"
## Üreteç davranışı kaynak dosyası okunamıyorsa (dışa aktarım) elle artırılan sürüm: yerleşim mantığı değişince
## arttırın.
const GENERATOR_VERSION := "b0-1"
const DIR := "user://cache"
const SOURCE_FILES: Array[String] = [
	"res://src/world/vegetation/vegetation_placement.gd", "res://src/world/vegetation/vegetation_obstacles.gd",
	"res://src/world/vegetation/vegetation_columns.gd", "res://src/world/vegetation/vegetation_rules.gd",
	"res://src/world/vegetation/vegetation_species.gd",
]


## Girdi anahtarı (hex). `parts`: {seed, rules_json, species_ids, plants_sha, world_hash, columns_hash, net_hash,
## topology_hash}. Üreteç kaynak özetleri burada eklenir.
static func key_of(parts: Dictionary) -> String:
	var all := parts.duplicate()
	all["generator_version"] = GENERATOR_VERSION
	var src := PackedStringArray()
	for f in SOURCE_FILES:
		src.append(FileAccess.get_sha256(f))
	all["sources"] = Array(src)
	return StateHash.of(all)


static func path_for(key: String) -> String:
	return "%s/vegetation-%s.bin" % [DIR, key.substr(0, 24)]


static func save(path: String, cols: VegetationColumns, key: String) -> bool:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	var d := {
		"magic": MAGIC, "key": key, "count": cols.count, "species_ids": Array(cols.species_ids),
		"species": cols.species, "x": cols.x, "z": cols.z, "yaw": cols.yaw, "scale": cols.scale, "layer": cols.layer,
		"origin": cols.origin, "cell_m": cols.cell_m, "cells_w": cols.cells_w, "cells_h": cols.cells_h,
		"cell_keys": cols.cell_keys, "cell_start": cols.cell_start, "state_hash": cols.state_hash(),
		"stats_json": JSON.stringify(cols.stats),
	}
	f.store_buffer(var_to_bytes(d))
	f.close()
	return true


## Geçerli dosya -> sütunlar; yoksa/bozuksa/anahtar uyuşmazsa null.
static func load_path(path: String, key: String) -> VegetationColumns:
	if not FileAccess.file_exists(path):
		return null
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		return null
	var d: Variant = bytes_to_var(bytes)
	if not (d is Dictionary):
		return null
	var m := d as Dictionary
	if str(m.get("magic", "")) != MAGIC or str(m.get("key", "")) != key:
		return null
	for field in ["species", "x", "z", "yaw", "scale", "layer", "cell_keys", "cell_start", "origin", "species_ids"]:
		if not m.has(field):
			return null
	var cols := VegetationColumns.new()
	cols.count = int(m["count"])
	cols.species_ids = PackedStringArray(m["species_ids"])
	cols.species = m["species"]
	cols.x = m["x"]
	cols.z = m["z"]
	cols.yaw = m["yaw"]
	cols.scale = m["scale"]
	cols.layer = m["layer"]
	cols.origin = m["origin"]
	cols.cell_m = float(m["cell_m"])
	cols.cells_w = int(m["cells_w"])
	cols.cells_h = int(m["cells_h"])
	cols.cell_keys = m["cell_keys"]
	cols.cell_start = m["cell_start"]
	var stats: Variant = JSON.parse_string(str(m.get("stats_json", "{}")))
	cols.stats = stats if stats is Dictionary else {}
	if not cols.shape_errors().is_empty() or cols.state_hash() != str(m.get("state_hash", "")):
		return null
	return cols
