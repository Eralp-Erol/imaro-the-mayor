class_name ParcelView
extends SimDto
## Bir parselin UI/görünüm için değer kopyası (ADR-0005). Konum dünya metresidir (WorldData koordinatı, ÇM);
## arazi kullanımı/imar sözlüğü (`land_use`, `zone`) sim yapılandırmasındadır, sözleşme değer kümesini sabitlemez.
## CAN-03: parsel üzerindeki özel gelişme (`development`) yalnız aktör kararıyla değişir; `reason_ids` onu gösterir.

const DEVELOPMENT_VACANT := &"vacant"
const DEVELOPMENT_PLANNED := &"planned"
const DEVELOPMENT_UNDER_CONSTRUCTION := &"under_construction"
const DEVELOPMENT_BUILT := &"built"
const DEVELOPMENT_STALLED := &"stalled"

var id: int = SimContract.NO_ID
## Bölge çalışma kodu (WorldData.region_code_at ile aynı sözlük; kod gömülmez).
var region_code: StringName = &""
## Parsel ağırlık merkezi, dünya metresi (x doğu, z güney).
var center: Vector2 = Vector2.ZERO
var area_m2: int = 0
## Yürürlükteki imar (arazi kullanımı anahtarı) ve bekleyen öneri (yoksa &"").
var zone: StringName = &""
var pending_zone: StringName = &""
var development: StringName = DEVELOPMENT_VACANT
var owner: ActorRef = null
## Birimsiz tamsayı (Q-003).
var land_value: int = 0
## Bu parselin durumunu açıklayan en güncel gerekçeler.
var reason_ids: PackedInt64Array = PackedInt64Array()
var provenance: StringName = SimContract.PROVENANCE_SIM


func ref() -> StringName:
	return SimContract.parcel_ref(id)


func to_dict() -> Dictionary:
	return {
		"id": id, "region_code": region_code, "center": SimContract.vector2_to_array(center), "area_m2": area_m2,
		"zone": zone, "pending_zone": pending_zone, "development": development, "owner": ActorRef.to_variant(owner),
		"land_value": land_value, "reason_ids": reason_ids, "provenance": provenance,
	}


static func from_dict(d: Dictionary) -> ParcelView:
	var p := ParcelView.new()
	p.id = SimContract.to_int(d.get("id"))
	p.region_code = SimContract.to_name(d.get("region_code", ""))
	p.center = SimContract.to_vector2(d.get("center", []))
	p.area_m2 = SimContract.to_int(d.get("area_m2"))
	p.zone = SimContract.to_name(d.get("zone", ""))
	p.pending_zone = SimContract.to_name(d.get("pending_zone", ""))
	p.development = SimContract.to_name(d.get("development", DEVELOPMENT_VACANT))
	p.owner = ActorRef.from_variant(d.get("owner"))
	p.land_value = SimContract.to_int(d.get("land_value"))
	p.reason_ids = SimContract.to_int64_array(d.get("reason_ids", []))
	p.provenance = SimContract.to_name(d.get("provenance", SimContract.PROVENANCE_SIM))
	return p
