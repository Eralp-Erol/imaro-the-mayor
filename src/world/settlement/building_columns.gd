# gdlint:disable=function-arguments-number
class_name BuildingColumns
extends RefCounted
## T0 yapı stoğu (T-005): sütunlu, saf, `state_hash`'lenebilir. T-012 (render) ile ORTAK ARAYÜZ SÖZLEŞMESİdir;
## sütun adları/türleri/bayrak bitleri koordinatör onayı olmadan DEĞİŞMEZ (testi: building_columns_test.gd).
##
## Satır i = bir yapı. Sütunlar (hepsi `count` uzunluğunda):
##   parcel_id    PackedInt32Array   WorldNetwork parsel kimliği (yapı bu parselin içindedir)
##   module_idx   PackedInt32Array   `kit_manifest.json` `modules[]` sırası (kimlik dizinden okunur)
##   x, z         PackedFloat32Array dünya metresi, ayak izi merkezi (yükseklik render'da WorldData.height_at)
##   yaw          PackedFloat32Array Y ekseni dönüşü (rad); modülün +Z yüzü (cephe) sokağa bakar
##   floors       PackedByteArray    kat sayısı (manifest `floors`; saat kulesinde 0)
##   wall_row, roof_row, accent_row  PackedByteArray  palet satırları (kit_palette.json `rows[].row`; spec §3.3/§5)
##   bright       PackedByteArray    parlaklık sapması: 0..255 -> çarpan 0,94..1,06 (`bright_factor`)
##   flags        PackedByteArray    bit maskesi (FLAG_*)
##   era          PackedByteArray    ERA_* (manifest `era` etiketi)
## Ölçek sütunu YOK: yapı modülün yerel boyutunda (ölçek 1,0) yerleştirilir ve parsel içindedir.
## Sim'e yazmaz: T0 stoğu sim başlangıç durumudur, aktör kararı bypass'ı değildir (CAN-03).

const FLAG_GROUND_SHOP := 1    ## bit0: zemin kat dükkân bandı (`_gf` modül)
const FLAG_HERITAGE := 2       ## bit1: tarihî/miras odağı (saat kulesi, eski sanayi izi, tarihî çekirdek)
const FLAG_LANDMARK := 4       ## bit2: landmark (saat kulesi)
const FLAG_INDUSTRY := 8       ## bit3: sanayi/depo/atölye yapısı
const FLAG_CIVIC := 16         ## bit4: sivil/kamu yapısı
const FLAG_PORT_YARD := 32     ## bit5: T0 liman/ilk sanayi sahası yapısı (D4'ün batısı, ana kara)

const ERA_OLD := 0
const ERA_MID := 1
const ERA_LATE := 2
const ERA_NEW := 3
const ERA_NONE := 255

const BRIGHT_MIN := 0.94
const BRIGHT_MAX := 1.06

var count: int = 0
var parcel_id: PackedInt32Array = PackedInt32Array()
var module_idx: PackedInt32Array = PackedInt32Array()
var x: PackedFloat32Array = PackedFloat32Array()
var z: PackedFloat32Array = PackedFloat32Array()
var yaw: PackedFloat32Array = PackedFloat32Array()
var floors: PackedByteArray = PackedByteArray()
var wall_row: PackedByteArray = PackedByteArray()
var roof_row: PackedByteArray = PackedByteArray()
var accent_row: PackedByteArray = PackedByteArray()
var bright: PackedByteArray = PackedByteArray()
var flags: PackedByteArray = PackedByteArray()
var era: PackedByteArray = PackedByteArray()


## Bir yapı ekler; dönüş: satır dizini.
func add(p_parcel: int, p_module: int, p_x: float, p_z: float, p_yaw: float, p_floors: int, p_wall: int, p_roof: int,
		p_accent: int, p_bright: int, p_flags: int, p_era: int) -> int:
	parcel_id.append(p_parcel)
	module_idx.append(p_module)
	x.append(p_x)
	z.append(p_z)
	yaw.append(p_yaw)
	floors.append(p_floors)
	wall_row.append(p_wall)
	roof_row.append(p_roof)
	accent_row.append(p_accent)
	bright.append(p_bright)
	flags.append(p_flags)
	era.append(p_era)
	count += 1
	return count - 1


## Parlaklık baytının çarpanı (0 -> 0,94; 255 -> 1,06).
func bright_factor(i: int) -> float:
	return BRIGHT_MIN + (BRIGHT_MAX - BRIGHT_MIN) * float(bright[i]) / 255.0


func position_of(i: int) -> Vector2:
	return Vector2(x[i], z[i])


## Sütun uzunlukları `count` ile tutarlı mı: hata metinleri (boş = tutarlı).
func shape_errors() -> PackedStringArray:
	var out := PackedStringArray()
	var sizes := {"parcel_id": parcel_id.size(), "module_idx": module_idx.size(), "x": x.size(), "z": z.size(),
			"yaw": yaw.size(), "floors": floors.size(), "wall_row": wall_row.size(), "roof_row": roof_row.size(),
			"accent_row": accent_row.size(), "bright": bright.size(), "flags": flags.size(), "era": era.size()}
	for key: String in sizes:
		if int(sizes[key]) != count:
			out.append("sütun %s uzunluğu %d, count %d" % [key, int(sizes[key]), count])
	return out


## Kanonik durum sözlüğü: büyük sütunlar ham bayt SHA-256 ile özetlenir.
func state_dict() -> Dictionary:
	return {"count": count, "parcel_id": _sha(parcel_id.to_byte_array()),
			"module_idx": _sha(module_idx.to_byte_array()), "x": _sha(x.to_byte_array()),
			"z": _sha(z.to_byte_array()), "yaw": _sha(yaw.to_byte_array()), "floors": _sha(floors),
			"wall_row": _sha(wall_row), "roof_row": _sha(roof_row), "accent_row": _sha(accent_row),
			"bright": _sha(bright), "flags": _sha(flags), "era": _sha(era)}


func state_hash() -> String:
	return StateHash.of(state_dict())


## Yalnız doluluk: yapı barındıran parsellerin sıralı benzersiz kimlikleri (tohumdan bağımsız kalması beklenir).
func topology_hash() -> String:
	return StateHash.of({"occupied_parcels": occupied_parcels()})


## Ayrıntı: tüm sütunlar (tohum bunu değiştirir; doluluğu değiştirmez).
func detail_hash() -> String:
	return state_hash()


## Yapı barındıran parsellerin sıralı benzersiz kimlikleri.
func occupied_parcels() -> PackedInt32Array:
	var seen := {}
	for pid in parcel_id:
		seen[pid] = true
	var ids: Array = seen.keys()
	ids.sort()
	return PackedInt32Array(ids)


static func _sha(bytes: PackedByteArray) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(bytes if not bytes.is_empty() else PackedByteArray([0]))
	return ctx.finish().hex_encode()
