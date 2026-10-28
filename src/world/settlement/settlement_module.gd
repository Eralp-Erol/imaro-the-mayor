class_name SettlementModule
extends RefCounted
## Modülün yerleşimciye gereken özeti (T-005; T-062 A2). Kaynak YALNIZ oyun bina tablosu
## (`data/library/game_buildings.json`, onaylı hero; `SettlementRules._build_modules`): kimlik, aile, kat, ayak izi
## (w = cephe, d = derinlik), saçak, çatı tipi, dönem. Palet satırları hero modüllerde BOŞTUR (renk atlas dokusundan).
## Aile ROLLERİ (konut, ev, sanayi, sivil, zemin dükkân, miras adayı, çok parselli) `settlement.json` `family_roles`
## verisinden gelir; kodda aile adı yoktur. Saf veri.

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
## Zemin kat dükkân rolü (`family_roles.ground_shop`; FLAG_GROUND_SHOP, zone.gf_main/gf_local çarpanı).
var gf: bool = false
## Aile rolleri (settlement.json `family_roles`).
var housing: bool = false
var floor_rule: bool = false
var house: bool = false
var industry: bool = false
var civic: bool = false
var heritage_eligible: bool = false
var wide_allowed: bool = false
var wide_only: bool = false
## Çok parselli yerleşimde yaw + 90 derece dönerek de sığabilir (`family_roles.rotate_fit`; ayak izi lot derinliğinden
## uzun, sokak boyunca yatay sığan sanayi kütlesi; T-062 A2-düzeltme).
var rotate_fit: bool = false
## Kat sayısı katalogda bilinmiyor ve `family_roles.floors_unknown` ÇALIŞMA DEĞERİ kullanıldı mı.
var floors_working_value: bool = false
var era: int = BuildingColumns.ERA_NONE
var wall_rows: PackedInt32Array = PackedInt32Array()
var roof_rows: PackedInt32Array = PackedInt32Array()
var accent_rows: PackedInt32Array = PackedInt32Array()
## Çatı satırlarından biri kiremit mi (kiremit payı bütçesi için; yalnız kiremit satırı olan modüller).
var tile_roof: bool = false


## Palet satırı taşımıyor mu (hero modül): duvar/çatı/vurgu satırı 0 yazılır, renk seçimi yapılmaz.
func palette_free() -> bool:
	return wall_rows.is_empty() and roof_rows.is_empty() and accent_rows.is_empty()


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
