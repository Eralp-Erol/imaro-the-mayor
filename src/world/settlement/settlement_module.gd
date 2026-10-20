class_name SettlementModule
extends RefCounted
## Kit modülünün yerleşimciye gereken özeti (T-005). Kaynak YALNIZ `kit_manifest.json` (kit spec §8): kimlik, aile, kat,
## ayak izi (w = cephe, d = derinlik), saçak, çatı tipi, zemin kat dükkân, dönem, izinli palet satırları (dizin).
## Saf veri; koda gömülmüş bina bilgisi yoktur.

const ROOF_FLAT := &"flat"

var idx: int = 0
var id: String = ""
var family: String = ""
var floors: int = 0
var w: float = 0.0
var d: float = 0.0
var eave_m: float = 0.0
var total_m: float = 0.0
var roof_type: StringName = &""
var gf: bool = false
var era: int = BuildingColumns.ERA_NONE
var wall_rows: PackedInt32Array = PackedInt32Array()
var roof_rows: PackedInt32Array = PackedInt32Array()
var accent_rows: PackedInt32Array = PackedInt32Array()
## Çatı satırlarından biri kiremit mi (kiremit payı bütçesi için; yalnız kiremit satırı olan modüller).
var tile_roof: bool = false


## Parapet üstü yükseklik (kit spec §4: saat kulesi oranı bununla ölçülür): saçak + parapet.
func top_m(parapet_m: float) -> float:
	return eave_m + parapet_m


static func era_code(label: String) -> int:
	match label:
		"old":
			return BuildingColumns.ERA_OLD
		"mid":
			return BuildingColumns.ERA_MID
		"late":
			return BuildingColumns.ERA_LATE
		"new":
			return BuildingColumns.ERA_NEW
	return BuildingColumns.ERA_NONE
