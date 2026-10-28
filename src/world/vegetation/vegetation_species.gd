class_name VegetationSpecies
extends RefCounted
## Oyun bitki tablosu (T-062 B0; ADR-0006 §2.1/§4): `data/library/game_plants.json` kayıtları, YALNIZ `LibraryGate`ten
## geçen (approved + hash eşleşen + katalogda approved) kimlikler. Tür anahtarı (`plane`, `pine_brutia` …) tablo
## `species` alanıdır; yerleşim kuralları (JSON) tür anahtarıyla konuşur, kimlik tablodan okunur (kodda kimlik listesi
## yok). Onaysız/bilinmeyen kimlik tabloya GİRMEZ (kapı sayar); kapı kapalıysa (yükleme hatası) hiç tür yoktur ve
## yerleşim üretmez (fail-closed). Saf veri; GLB yüklemez.

## Tür dizini (VegetationColumns.species) -> kütüphane kimliği.
var ids: PackedStringArray = PackedStringArray()
## Tür dizini -> tür anahtarı.
var keys: PackedStringArray = PackedStringArray()
## Tür dizini -> GLB orijininden LOD0 sınır kutusuna en büyük XZ uzaklığı (m, ölçek 1).
var reach_m: PackedFloat32Array = PackedFloat32Array()
var height_m: PackedFloat32Array = PackedFloat32Array()
## Tür dizini -> LOD0/LOD1 üçgen sayısı; PROXY yoksa 0.
var tris_lod0: PackedInt32Array = PackedInt32Array()
var tris_lod1: PackedInt32Array = PackedInt32Array()
var tris_proxy: PackedInt32Array = PackedInt32Array()
var gate: LibraryGate = null

var _index_of_key: Dictionary = {}


## Varsayılan kapıdan (bitki + donatı tabloları + katalog) kurar.
static func load_default() -> VegetationSpecies:
	return from_gate(LibraryGate.load_plants())


## Verilen kapının `vegetation` tablosundaki kimliklerden kurar (tablo sırası). Kapı sorgusu `request` ile yapılır.
static func from_gate(the_gate: LibraryGate) -> VegetationSpecies:
	var out := VegetationSpecies.new()
	out.gate = the_gate
	if not the_gate.load_errors.is_empty():
		return out   # fail-closed: bozuk tablo/katalog -> tür yok
	for id in the_gate.approved_ids_of("vegetation"):
		var rec := the_gate.request(id)
		if rec.is_empty():
			continue
		out._add(rec)
	return out


func size() -> int:
	return ids.size()


func has_key(key: String) -> bool:
	return _index_of_key.has(key)


## Tür anahtarının dizini; yoksa -1.
func index_of(key: String) -> int:
	return int(_index_of_key.get(key, -1))


func has_proxy(idx: int) -> bool:
	return tris_proxy[idx] > 0


func _add(rec: Dictionary) -> void:
	var key := str(rec.get("species", ""))
	if key.is_empty() or _index_of_key.has(key):
		push_error("VegetationSpecies: tür anahtarı boş/yinelenen: '%s'" % key)
		return
	var lods: Dictionary = rec.get("lods", {})
	_index_of_key[key] = ids.size()
	ids.append(str(rec["id"]))
	keys.append(key)
	reach_m.append(float(rec.get("reach_m", 0.0)))
	height_m.append(float(rec.get("height_m", 0.0)))
	tris_lod0.append(int((lods.get("LOD0", {}) as Dictionary).get("tris", 0)))
	tris_lod1.append(int((lods.get("LOD1", {}) as Dictionary).get("tris", 0)))
	tris_proxy.append(int((lods.get("PROXY", {}) as Dictionary).get("tris", 0)))
