class_name PlanPreviewView
extends SimDto
## İmar planı ÖNİZLEMESİ (v1.4, ADR-0005 Ek G, T-043A/D-010): `SimFacade.plan_preview(parcel_ids, land_use, density,
## max_height_m)`. Oyuncu seçili parsellere `land_use` teklif ederse yatırımcı karar fonksiyonunun kullanacağı AYNI
## formülle (`EconomyMath.project_units`) potansiyel birim ve altyapı yükü. SONUCU ZORLAMAZ (yatırımcı yine
## getiri/talep/kapasiteye göre karar verir; CAN-03). UI hiçbir sayı üretmez; `ok == false` iken sayılar anlamsızdır
## ve `reason` anahtarı gösterilir. Değer kopyası, salt okunur.
##
## `reason` (ok == false): `plan.not_built` (kaynak plan önizlemesi sunmuyor: mock dahil) | `economy.not_started` |
## `plan.unknown_land_use` | `plan.unknown_parcel`.
## `parcels` satırı: {id, region, use, units, infra_units} (`use` boş = bu kullanımla yapı çıkmaz). `regions` satırı
## (bölge koduna göre sıralı): {code, added_units, added_infra_units, capacity_units, load_units, headroom_units,
## fits} (`fits` = eklenen yük mevcut boş kapasiteye sığar mı). Kesim yarar/zarar işareti YOKTUR (ekonomide yok):
## UI "henüz kurulmadı" yazar.

const REASON_NOT_BUILT := &"plan.not_built"
const PARCEL_ROW := {"id": "int", "region": "name", "use": "name", "units": "int", "infra_units": "int"}
const REGION_ROW := {"code": "name", "added_units": "int", "added_infra_units": "int", "capacity_units": "int",
	"load_units": "int", "headroom_units": "int", "fits": "bool"}

var provenance: StringName = SimContract.PROVENANCE_SIM
var ok: bool = false
var reason: StringName = REASON_NOT_BUILT
var land_use: StringName = &""
var parcels: Array = []
var regions: Array = []
var total_units: int = 0
var total_infra_units: int = 0
## Bir teklifte en çok parsel (`zoning.plan_max_parcels_per_proposal`, sim yapılandırması); 0 = bilinmiyor.
var max_parcels: int = 0
## Öneri meclis oylamasına gider mi (gerçek `requires_council.zoning.propose`)? UI "meclis" sözcüğünü YALNIZ true iken
## yazar. Meclis sürecinin kendisi Q-014 AÇIK; burada yalnız bayrak.
var council_required: bool = false


func to_dict() -> Dictionary:
	return {
		"provenance": provenance, "ok": ok, "reason": reason, "land_use": land_use, "parcels": _rows(parcels, PARCEL_ROW),
		"regions": _rows(regions, REGION_ROW), "total_units": total_units, "total_infra_units": total_infra_units,
		"max_parcels": max_parcels, "council_required": council_required,
	}


static func from_dict(d: Dictionary) -> PlanPreviewView:
	var v := PlanPreviewView.new()
	v.provenance = SimContract.to_name(d.get("provenance", SimContract.PROVENANCE_SIM))
	v.ok = SimContract.to_bool(d.get("ok", false))
	v.reason = SimContract.to_name(d.get("reason", ""))
	v.land_use = SimContract.to_name(d.get("land_use", ""))
	v.parcels = _rows(d.get("parcels", []), PARCEL_ROW)
	v.regions = _rows(d.get("regions", []), REGION_ROW)
	v.total_units = SimContract.to_int(d.get("total_units"))
	v.total_infra_units = SimContract.to_int(d.get("total_infra_units"))
	v.max_parcels = SimContract.to_int(d.get("max_parcels"))
	v.council_required = SimContract.to_bool(d.get("council_required", false))
	return v


## Satır sözlükleri kanonik: anahtar sırası sabit (bayt eşitliği), ad alanları StringName, sayılar int, bayraklar bool
## (JSON gidiş-dönüşünde kayıpsız).
static func _rows(source: Variant, shape: Dictionary) -> Array:
	var out := []
	if not source is Array:
		return out
	var keys: Array = shape.keys()
	keys.sort()
	for row: Variant in source:
		if not row is Dictionary:
			continue
		var norm := {}
		for key: String in keys:
			var value: Variant = (row as Dictionary).get(key)
			match shape[key]:
				"name":
					norm[key] = SimContract.to_name(value)
				"int":
					norm[key] = SimContract.to_int(value)
				_:
					norm[key] = SimContract.to_bool(value)
		out.append(norm)
	return out


## Sim sorgusu sonucundan ({ok, reason, parcels, regions, totals}) satır kopyası kurar. `EconomySystem.plan_preview`
## çıktısını DEĞİŞTİRMEDEN taşır (sayılar aynı).
static func from_economy(raw: Dictionary, source: StringName, use_name: StringName, limit: int, council: bool) \
		-> PlanPreviewView:
	var v := PlanPreviewView.from_dict(raw)
	v.provenance = source
	v.land_use = use_name
	v.max_parcels = limit
	v.council_required = council
	return v
