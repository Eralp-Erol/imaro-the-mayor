class_name ListStockSource
extends ExistingStockSource
## Bellek içi listeden stok (fixture/test/geliştirme). Girdi: [{"parcel_id", "use", "units", "owner"}]. Geçersiz girdide
## `errors` dolu ve kaynak boştur; çağıran `is_valid()` denetler.

const USES: Array[StringName] = [&"residential", &"commercial"]

var errors: PackedStringArray = PackedStringArray()

var _by_id: Dictionary = {}  # int -> {"use", "units", "owner"}
var _ids: PackedInt64Array = PackedInt64Array()


static func create(entries: Array) -> ListStockSource:
	var src := ListStockSource.new()
	for i in entries.size():
		var e: Variant = entries[i]
		if not (e is Dictionary):
			src.errors.append("stok[%d] nesne değil" % i)
			continue
		var id: int = SimContract.to_int(e.get("parcel_id", 0))
		var use := StringName(str(e.get("use", "")))
		var units: int = SimContract.to_int(e.get("units", 0))
		var owner: int = SimContract.to_int(e.get("owner", 0))
		if id < 1:
			src.errors.append("stok[%d].parcel_id >= 1 olmalı" % i)
		elif src._by_id.has(id):
			src.errors.append("stok[%d] tekrarlı parsel %d" % [i, id])
		elif not USES.has(use):
			src.errors.append("stok[%d].use bilinmeyen '%s'" % [i, use])
		elif units < 1:
			src.errors.append("stok[%d].units >= 1 olmalı" % i)
		elif owner < 0:
			src.errors.append("stok[%d].owner >= 0 olmalı" % i)
		else:
			src._by_id[id] = {"use": use, "units": units, "owner": owner}
	if not src.errors.is_empty():
		src._by_id = {}
		return src
	var ids: Array = src._by_id.keys()
	ids.sort()
	src._ids = PackedInt64Array(ids)
	return src


func is_valid() -> bool:
	return errors.is_empty()


func parcel_ids() -> PackedInt64Array:
	return _ids.duplicate()


func use_of(parcel_id: int) -> StringName:
	return (_by_id[parcel_id] as Dictionary)["use"] if _by_id.has(parcel_id) else &""


func units_of(parcel_id: int) -> int:
	return (_by_id[parcel_id] as Dictionary)["units"] if _by_id.has(parcel_id) else 0


func owner_of(parcel_id: int) -> int:
	return (_by_id[parcel_id] as Dictionary)["owner"] if _by_id.has(parcel_id) else 0
