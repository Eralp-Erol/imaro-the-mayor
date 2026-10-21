class_name ParcelView
extends SimDto
## Bir parselin UI/görünüm için değer kopyası (ADR-0005). Konum dünya metresidir (WorldData koordinatı, ÇM);
## arazi kullanımı/imar sözlüğü (`land_use`, `zone`) sim yapılandırmasındadır, sözleşme değer kümesini sabitlemez.
## CAN-03: parsel üzerindeki özel gelişme (`development`) yalnız aktör kararıyla değişir; `reason_ids` onu gösterir.
## v1.1 (M2, ADR-0005 Ek C): `use/units/progress_pm/developed_by_sim` render'ın yapı üretmesi (SimBuildingProjector)
## için parseldeki proje/yapıyı tarif eder; yalnız sim durumundan okunur, view/UI bunları yazamaz.
## v1.2 (T-045, ADR-0005 Ek D): `decision*` parselin KALICI karar özetidir. Gerekçe günlüğü budanınca kaybolmaz (ekonomi
## durumundaki sütunlardan türer); budanmaya bağlı olan yalnız `decision_reason_id`dir (0'a düşer, bkz. aşağısı).

const DEVELOPMENT_VACANT := &"vacant"
const DEVELOPMENT_PLANNED := &"planned"
const DEVELOPMENT_UNDER_CONSTRUCTION := &"under_construction"
const DEVELOPMENT_BUILT := &"built"
const DEVELOPMENT_STALLED := &"stalled"

## Yatırımcı karar özeti (v1.2): `decision` değerleri.
const DECISION_NONE := &""
const DECISION_APPROVED := &"approved"
const DECISION_DECLINED := &"declined"

## Parseldeki proje/yapının kullanımı (v1.1). Boş = proje yok (`vacant`).
const USE_NONE := &""
const USE_RESIDENTIAL := &"residential"
const USE_COMMERCIAL := &"commercial"
## `progress_pm` ölçeği: 0..PROGRESS_FULL (sabit nokta ‰, `SimContract.FIXED_SCALE`).
const PROGRESS_FULL := 1000

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
## v1.1 · Parseldeki proje ya da yapının kullanımı (`USE_*`); `vacant` iken `USE_NONE`.
var use: StringName = USE_NONE
## v1.1 · Proje/yapı birim sayısı (konutta hane kapasitesi, ticarette dükkân birimi); `vacant` iken 0.
var units: int = 0
## v1.1 · İnşaat ilerlemesi ‰ (0..1000): `vacant`/`planned` 0 (inşaat başlamadı), `under_construction`/`stalled`
## geçen inşaat süresinin toplama oranı (`stalled` iken donar), `built` 1000. T0 stoku `built` doğar: 1000.
var progress_pm: int = 0
## v1.1 · true: bu gelişme sim başlangıcından SONRA bir yatırımcı kararıyla doğdu. false: boş parsel ya da
## T0 mevcut stoku (T0 `BuildingColumns`'ta zaten vardır; render ikinci kez yapı üretmez).
var developed_by_sim: bool = false
## v1.2 · Yatırımcının bu parsel için SON KAYDEDİLEN kararı: `DECISION_NONE` (hiç karar yok ya da imar yürürlüğe
## girince sıfırlandı) / `DECISION_APPROVED` (gelişme başladı; parsel `vacant` DEĞİL) / `DECISION_DECLINED` (parsel
## `vacant`). `approved` kalıcıdır (parsel yapılsa da değişmez); T0 mevcut stoku karar taşımaz (`DECISION_NONE`).
var decision: StringName = DECISION_NONE
## v1.2 · Kararın sonuç kodu (`approved`, `zoning_not_buildable`, `infrastructure_exhausted`, `insufficient_financing`,
## `demand_too_low`, `return_too_low`); `decision` boşsa boş. Ret kodu SON değerlendirmenin kodudur (kod değişince
## ya da tekrarlanabilir ret penceresi dolunca kayıt yazılır; aynı kodlu ara taramalar durumu değiştirmez).
var decision_code: StringName = &""
## v1.2 · Kararın KAYDEDİLDİĞİ tick; yok = -1. Her ret taramasını kaydetmiyoruz (yalnız neden değişince ya da
## tekrarlanabilir ret için pencere dolunca): `declined` iken bu "son KAYDEDİLEN ret"in tick'idir, parselin son
## DEĞERLENDİRİLDİĞİ tick olmayabilir (sonraki aynı kodlu ret taramaları bunu ilerletmez). Öneri anıyla karşılaştırma
## (ör. "öneriden önceki otonom ret") için güvenilir ölçüdür.
var decision_tick: int = -1
## v1.2 · Kararın gerekçe kimliği (`SimFacade.reason`); 0 = karar yok VEYA gerekçe günlükten budandı (bu durumda
## `decision`/`decision_code`/`decision_tick` yine de doğrudur; UI "gerekçe kaydı budandı" yazar). `approved` için
## onay kararının gerekçesidir (sonraki durma/devam gerekçesi değil). Budama bir durum DEĞİŞİKLİĞİ sayılmaz:
## `parcel_changes_since` bu kimliğin 0'a düşmesini bildirmez.
var decision_reason_id: int = 0
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
		"use": use, "units": units, "progress_pm": progress_pm, "developed_by_sim": developed_by_sim,
		"decision": decision, "decision_code": decision_code, "decision_tick": decision_tick,
		"decision_reason_id": decision_reason_id,
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
	p.use = SimContract.to_name(d.get("use", ""))
	p.units = SimContract.to_int(d.get("units"))
	p.progress_pm = SimContract.to_int(d.get("progress_pm"))
	p.developed_by_sim = SimContract.to_bool(d.get("developed_by_sim", false))
	p.decision = SimContract.to_name(d.get("decision", ""))
	p.decision_code = SimContract.to_name(d.get("decision_code", ""))
	p.decision_tick = SimContract.to_int(d.get("decision_tick", -1), -1)
	p.decision_reason_id = SimContract.to_int(d.get("decision_reason_id", 0))
	return p
