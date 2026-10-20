class_name ParcelRegions
extends RefCounted
## Parsel kimliği -> bölge kodu dizini (T-017): imar önerilerinin ve proje nedenlerinin hangi bölgeye düştüğünü
## söyler. Kaynak `ParcelSource`tur (dünya verisi); bölge kodu gömülü değildir. Kurulumda bir kez kurulur, durumsuzdur.

var _ids: PackedInt64Array = PackedInt64Array()
var _codes: PackedStringArray = PackedStringArray()


static func create(parcels: ParcelSource) -> ParcelRegions:
	var index := ParcelRegions.new()
	if parcels == null:
		return index
	index._ids = parcels.parcel_ids()
	for id in index._ids:
		index._codes.append(String(parcels.template(id).region_code))
	return index


func count() -> int:
	return _ids.size()


## Parselin bölge kodu; bilinmeyen parsel için "".
func code_of(parcel_id: int) -> String:
	var i := _ids.bsearch(parcel_id)
	return _codes[i] if i < _ids.size() and _ids[i] == parcel_id else ""


## Sıra indeksine (EconomyState parsel sütunları ile aynı sıra) göre parsel kimliği.
func id_at(index: int) -> int:
	return _ids[index]


func code_at(index: int) -> String:
	return _codes[index]
