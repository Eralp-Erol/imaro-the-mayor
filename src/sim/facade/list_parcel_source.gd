class_name ListParcelSource
extends ParcelSource
## Bellek içi parsel listesinden `ParcelSource` (T-027). T-011 `WorldNetwork` gelene dek fixture/test ve geliştirme
## kaynağı; üretici (test/dev kodu) listeyi dünya verisinden kurar, bu sınıf hiçbir koordinat gömmez.

var errors: PackedStringArray = PackedStringArray()

var _world_id: StringName = &""
var _by_id: Dictionary = {}  # int -> ParcelView
var _ids: PackedInt64Array = PackedInt64Array()


## Girdi kopyalanır. Geçersiz girdide (`errors` dolu) kaynak boştur; çağıran `is_valid()` denetler.
static func create(world_id_value: StringName, views: Array[ParcelView]) -> ListParcelSource:
	var src := ListParcelSource.new()
	if world_id_value == &"":
		src.errors.append("world_id boş")
	src._world_id = world_id_value
	for v in views:
		if v.id <= SimContract.NO_ID:
			src.errors.append("parsel kimliği >= 1 olmalı (%d)" % v.id)
		elif src._by_id.has(v.id):
			src.errors.append("tekrarlı parsel kimliği %d" % v.id)
		else:
			src._by_id[v.id] = ParcelView.from_dict(v.to_dict())
	if not src.errors.is_empty():
		src._by_id = {}
		return src
	var ids: Array = src._by_id.keys()
	ids.sort()
	src._ids = PackedInt64Array(ids)
	return src


func is_valid() -> bool:
	return errors.is_empty()


func world_id() -> StringName:
	return _world_id


func parcel_count() -> int:
	return _ids.size()


func parcel_ids(region_code: StringName = &"") -> PackedInt64Array:
	if region_code == &"":
		return _ids.duplicate()
	var out := PackedInt64Array()
	for id in _ids:
		if (_by_id[id] as ParcelView).region_code == region_code:
			out.append(id)
	return out


func has_parcel(id: int) -> bool:
	return _by_id.has(id)


func template(id: int) -> ParcelView:
	if not _by_id.has(id):
		return null
	return ParcelView.from_dict((_by_id[id] as ParcelView).to_dict())
