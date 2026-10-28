class_name VegetationColumns
extends RefCounted
## T0 bitki yerleşim çıktısı (T-062 B0; WLD-01, TEK-03, VIS-01/02): ağaç/çalı/çit örnekleri, sütunlu ve saf.
## B1 (görünüm) bunu OKUR; sim'e girmez (görünüm süsü, sim hash'ini etkilemez).
##
## Satır i = bir örnek. Sütunlar (hepsi `count` uzunluğunda):
##   species  PackedByteArray    `species_ids` dizini (`game_plants.json` sırası, LibraryGate'ten geçen)
##   x, z     PackedFloat32Array dünya metresi, GLB orijini (gövde tabanı); yükseklik: WorldData.height_at
##   yaw      PackedFloat32Array Y ekseni dönüşü (rad); BuildingColumns ile AYNI sözleşme (yerel +X -> (cos, -sin))
##   scale    PackedFloat32Array düzgün ölçek (1,0 = GLB boyutu)
##   layer    PackedByteArray    kaynak katman (LAYER_*): tanı/test içindir, görünüm bunu çizmeye kullanmaz
## Hücre indeksi (`finalize`): satırlar (hücre anahtarı, tür, üretim sırası) ile SIRALANIR; `cell_keys` sıralı benzersiz
## dolu hücre anahtarları (cz * cells_w + cx; hücre = `cell_m` kenarlı, dünya `origin`inden), `cell_start`
## (cell_keys.size() + 1) her hücrenin [başlangıç, bitiş) satır aralığı. Hücre içinde türe göre kümelidir (tür başına
## MultiMesh için bitişik aralık).

const LAYER_STREET := 0
const LAYER_YARD := 1
const LAYER_HEDGE := 2
const LAYER_GROVE := 3
const LAYER_COAST := 4
const LAYER_RURAL := 5
const LAYER_NAMES: Array[StringName] = [&"street", &"yard", &"hedge", &"grove", &"coast", &"rural"]
const MAX_SPECIES := 16
const _SHIFT := 24

var count: int = 0
## Tür dizini -> kütüphane kimliği (ör. veg_hero_plane_a); sıra tablo sırasıdır.
var species_ids: PackedStringArray = PackedStringArray()
var species: PackedByteArray = PackedByteArray()
var x: PackedFloat32Array = PackedFloat32Array()
var z: PackedFloat32Array = PackedFloat32Array()
var yaw: PackedFloat32Array = PackedFloat32Array()
var scale: PackedFloat32Array = PackedFloat32Array()
var layer: PackedByteArray = PackedByteArray()

var origin: Vector2 = Vector2.ZERO
var cell_m: float = 256.0
var cells_w: int = 0
var cells_h: int = 0
var cell_keys: PackedInt32Array = PackedInt32Array()
var cell_start: PackedInt32Array = PackedInt32Array()
## Tanı (hash'e girmez): katman sayıları, ret nedenleri, kırpma, süre dışı bilgiler.
var stats: Dictionary = {}


func add(p_species: int, p_x: float, p_z: float, p_yaw: float, p_scale: float, p_layer: int) -> int:
	species.append(p_species)
	x.append(p_x)
	z.append(p_z)
	yaw.append(p_yaw)
	scale.append(p_scale)
	layer.append(p_layer)
	count += 1
	return count - 1


func position_of(i: int) -> Vector2:
	return Vector2(x[i], z[i])


## Dünya konumu -> hücre anahtarı (sınır dışı kenara kenetlenir).
func cell_key_of(px: float, pz: float) -> int:
	var cx := clampi(int(floor((px - origin.x) / cell_m)), 0, maxi(cells_w - 1, 0))
	var cz := clampi(int(floor((pz - origin.y) / cell_m)), 0, maxi(cells_h - 1, 0))
	return cz * cells_w + cx


## Satırları hücre-tür sırasına dizer ve hücre indeksini kurar. `world_origin`/`world_size`: hücre ızgarası sınırı.
func finalize(world_origin: Vector2, world_size: Vector2, p_cell_m: float) -> void:
	origin = world_origin
	cell_m = p_cell_m
	cells_w = maxi(1, int(ceil(world_size.x / cell_m)))
	cells_h = maxi(1, int(ceil(world_size.y / cell_m)))
	var keyed := PackedInt64Array()
	keyed.resize(count)
	for i in count:
		var sort_key: int = cell_key_of(x[i], z[i]) * MAX_SPECIES + species[i]
		keyed[i] = (sort_key << _SHIFT) | i
	keyed.sort()
	var order := PackedInt32Array()
	order.resize(count)
	var mask := (1 << _SHIFT) - 1
	for k in count:
		order[k] = int(keyed[k]) & mask
	species = _permute_bytes(species, order)
	layer = _permute_bytes(layer, order)
	x = _permute_floats(x, order)
	z = _permute_floats(z, order)
	yaw = _permute_floats(yaw, order)
	scale = _permute_floats(scale, order)
	cell_keys = PackedInt32Array()
	cell_start = PackedInt32Array()
	var last := -1
	for i in count:
		var key := cell_key_of(x[i], z[i])
		if key != last:
			cell_keys.append(key)
			cell_start.append(i)
			last = key
	cell_start.append(count)


## [başlangıç, bitiş) satır aralığı; hücre boşsa (0, 0).
func cell_range(key: int) -> Vector2i:
	var at := cell_keys.bsearch(key)
	if at >= cell_keys.size() or cell_keys[at] != key:
		return Vector2i.ZERO
	return Vector2i(cell_start[at], cell_start[at + 1])


## Hücre içinde tek türün [başlangıç, bitiş) aralığı (türe göre kümeli olduğundan bitişik).
func species_range(key: int, species_idx: int) -> Vector2i:
	var r := cell_range(key)
	var lo := r.x
	while lo < r.y and species[lo] < species_idx:
		lo += 1
	var hi := lo
	while hi < r.y and species[hi] == species_idx:
		hi += 1
	return Vector2i(lo, hi)


## Hücre başına en çok örnek ve o hücrenin anahtarı: Vector2i(sayı, anahtar).
func peak_cell() -> Vector2i:
	var best := Vector2i.ZERO
	for k in cell_keys.size():
		var n := cell_start[k + 1] - cell_start[k]
		if n > best.x:
			best = Vector2i(n, cell_keys[k])
	return best


func species_counts() -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(maxi(species_ids.size(), 1))
	for i in count:
		out[species[i]] += 1
	return out


func layer_counts() -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(LAYER_NAMES.size())
	for i in count:
		out[layer[i]] += 1
	return out


## Sütun uzunlukları ve hücre indeksi tutarlı mı: hata metinleri (boş = tutarlı).
func shape_errors() -> PackedStringArray:
	var out := PackedStringArray()
	var sizes := {"species": species.size(), "x": x.size(), "z": z.size(), "yaw": yaw.size(),
			"scale": scale.size(), "layer": layer.size()}
	for key: String in sizes:
		if int(sizes[key]) != count:
			out.append("sütun %s uzunluğu %d, count %d" % [key, int(sizes[key]), count])
	if not out.is_empty():
		return out
	if cell_start.size() != cell_keys.size() + 1:
		out.append("cell_start uzunluğu %d, cell_keys %d" % [cell_start.size(), cell_keys.size()])
		return out
	if cell_start[cell_start.size() - 1] != count or (count > 0 and cell_start[0] != 0):
		out.append("cell_start uçları [%d..%d], count %d" % [cell_start[0], cell_start[cell_start.size() - 1], count])
		return out
	for k in cell_keys.size():
		if k > 0 and cell_keys[k] <= cell_keys[k - 1]:
			out.append("cell_keys sıralı/benzersiz değil: %d" % k)
		if cell_start[k + 1] <= cell_start[k]:
			out.append("boş hücre aralığı: %d" % k)
			continue
		var prev_species := -1
		for i in range(cell_start[k], cell_start[k + 1]):
			if cell_key_of(x[i], z[i]) != cell_keys[k]:
				out.append("satır %d hücre %d dışında" % [i, cell_keys[k]])
				break
			if species[i] < prev_species:
				out.append("hücre %d içinde tür sırası bozuk (satır %d)" % [cell_keys[k], i])
				break
			prev_species = species[i]
	return out


## Kanonik durum sözlüğü: büyük sütunlar ham bayt SHA-256 ile özetlenir.
func state_dict() -> Dictionary:
	return {"count": count, "species_ids": Array(species_ids), "species": _sha(species),
			"x": _sha(x.to_byte_array()), "z": _sha(z.to_byte_array()), "yaw": _sha(yaw.to_byte_array()),
			"scale": _sha(scale.to_byte_array()), "layer": _sha(layer), "cell_m": cell_m,
			"cell_keys": _sha(cell_keys.to_byte_array()), "cell_start": _sha(cell_start.to_byte_array())}


func state_hash() -> String:
	return StateHash.of(state_dict())


static func _permute_bytes(src: PackedByteArray, order: PackedInt32Array) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(order.size())
	for k in order.size():
		out[k] = src[order[k]]
	return out


static func _permute_floats(src: PackedFloat32Array, order: PackedInt32Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(order.size())
	for k in order.size():
		out[k] = src[order[k]]
	return out


static func _sha(bytes: PackedByteArray) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(bytes if not bytes.is_empty() else PackedByteArray([0]))
	return ctx.finish().hex_encode()
