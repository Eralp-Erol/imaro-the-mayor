class_name EmptyStockSource
extends ExistingStockSource
## Stoksuz dünya: hiçbir parsel önceden yapılı değildir (varsayılan; T-005 gelene dek).


func parcel_ids() -> PackedInt64Array:
	return PackedInt64Array()


func use_of(_parcel_id: int) -> StringName:
	return &""


func units_of(_parcel_id: int) -> int:
	return 0


func owner_of(_parcel_id: int) -> int:
	return 0
