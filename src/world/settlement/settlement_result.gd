class_name SettlementResult
extends RefCounted
## `T0Settlement.generate_detailed` çıktısı (T-005): sözleşme sütunları + hata ayıklama/test için türetilmiş bilgi.
## Yalnız `columns` (BuildingColumns) T-012/T-013 sözleşmesidir; kalanı salt okunur tanı verisidir.

var columns: BuildingColumns = BuildingColumns.new()
var rules: SettlementRules = null
var net: WorldNetwork = null
## Parsel kimliği -> bölge dokusu adı (StringName); yerleşim dışı parseller yoktur.
var zone_by_parcel: Dictionary = {}
## Çok parselli sivil yapıya katılıp boş kalan parseller (parsel kimliği -> true).
var consumed: Dictionary = {}
## Meydan: {"block_id", "center": Vector2, "axis": Vector2, "size": Vector2}; kule yoksa boş.
var plaza: Dictionary = {}
var tower_index: int = -1
## Doluluk kurasına (parsel `detail`'inden türer; yerleşim tohumundan bağımsız) giren parseller, sıralı.
var lottery_parcels: PackedInt32Array = PackedInt32Array()
var stats: Dictionary = {}
## Hesaplanmış tanı önbelleği (SettlementStats); `with_columns` kopyalamaz (sütunlar değişince geçersizdir).
var cache: Dictionary = {}


## Aynı ağ/kurallarla, yalnız sütunları değiştirilmiş kopya (testlerde bilerek bozulmuş çıktı üretmek için).
static func with_columns(src: SettlementResult, cols: BuildingColumns) -> SettlementResult:
	var out := SettlementResult.new()
	out.columns = cols
	out.rules = src.rules
	out.net = src.net
	out.zone_by_parcel = src.zone_by_parcel
	out.consumed = src.consumed
	out.plaza = src.plaza
	out.tower_index = src.tower_index
	out.lottery_parcels = src.lottery_parcels
	out.stats = src.stats
	return out


func zone_of_building(i: int) -> StringName:
	return zone_by_parcel.get(columns.parcel_id[i], &"")


func module_of(i: int) -> SettlementModule:
	return rules.modules[columns.module_idx[i]]


## Topoloji özeti: tohumdan bağımsız kalması beklenen yapı (dolu parseller + meydan); sütun ayrıntısı DEĞİL.
func topology_hash() -> String:
	var center: Vector2 = plaza.get("center", Vector2.ZERO)
	return StateHash.of({"lottery": lottery_parcels, "plaza_block": int(plaza.get("block_id", -1)),
			"plaza_center": [center.x, center.y]})
