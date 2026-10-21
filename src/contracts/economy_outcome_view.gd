class_name EconomyOutcomeView
extends SimDto
## Ölçülebilir ekonomik sonuç özeti (v1.1, ADR-0005 Ek C, M2 ölçüt 5). `SimFacade.economy_outcome()` her çağrıda yeni
## değer kopyası döner. Bölge satırları ve KÜMÜLATİF sayaçlar sim başlangıcından beri toplamdır; "önce/sonra" farkı
## iki okumanın `delta_since` farkıdır (tick'e bağlı değerler). Sim'de olmayan şey uydurulmaz: `available == false`
## ve `unavailable_reason_key` (ekonomi kurulmamış) ya da `municipal_revenue_available == false` + neden anahtarı
## (belediye geliri/vergisi T-014 ile gelir). `rent_income` YATIRIMCININ kira geliridir, belediye geliri DEĞİLDİR.
## Para birimsiz tamsayıdır (Q-003).

const REASON_NOT_BUILT := &"economy.not_built"
const REASON_MUNICIPAL_REVENUE_NOT_BUILT := &"economy.municipal_revenue.not_built"
## Şehir geneli kümülatif sayaç anahtarları (`metrics()` içinde bölge toplamlarının yanında).
const COUNTER_KEYS: Array[String] = [
	"investments_approved", "investments_declined", "projects_completed", "projects_stalled", "rent_income",
	"land_sales", "construction_spend",
]
## Şehir toplamında bölge değerlerinin TOPLANDIĞI anahtarlar (talep/yük oranları toplanmaz).
const SUMMED_REGION_KEYS: Array[String] = [
	"households", "housed_households", "residential_units", "commercial_units", "residential_pipeline",
	"commercial_pipeline", "sim_residential_units", "sim_commercial_units",
]

var provenance: StringName = SimContract.PROVENANCE_SIM
var tick: int = 0
## false: ekonomi kurulmamış; sayılar anlamsızdır (UI "henüz yok" yazar).
var available: bool = false
var unavailable_reason_key: StringName = REASON_NOT_BUILT
## Bölge kodu sırasıyla.
var regions: Array[EconomyRegionOutcome] = []
## Yatırımcı kararı sayaçları (kümülatif): olumlu karar, olumsuz karar, biten proje, durmuş (kümülatif) proje.
var investments_approved: int = 0
var investments_declined: int = 0
var projects_completed: int = 0
var projects_stalled: int = 0
## Yatırımcıların kümülatif kira geliri, arsa satış bedeli ve inşaat harcaması (birimsiz tamsayı).
var rent_income: int = 0
var land_sales: int = 0
var construction_spend: int = 0
## Belediye geliri/vergisi: sim'de bu özellik yoksa false + neden anahtarı; değer o zaman 0 ve ANLAMSIZDIR.
var municipal_revenue_available: bool = false
var municipal_revenue_reason_key: StringName = REASON_MUNICIPAL_REVENUE_NOT_BUILT
var municipal_revenue: int = 0


## Kurulu olmayan/erişilemeyen kaynak için boş görünüm (`available == false`).
static func unavailable(source: StringName, at_tick: int, reason_key: StringName = REASON_NOT_BUILT) \
		-> EconomyOutcomeView:
	var o := EconomyOutcomeView.new()
	o.provenance = source
	o.tick = at_tick
	o.unavailable_reason_key = reason_key
	return o


func region(code: StringName) -> EconomyRegionOutcome:
	for r in regions:
		if r.region_code == code:
			return r
	return null


## `region_code` boşsa şehir geneli ({bölge toplamları + sayaçlar}); doluysa o bölgenin sayısal alanları.
## Bilinmeyen bölge: boş sözlük.
func metrics(region_code: StringName = &"") -> Dictionary:
	if region_code != &"":
		var r := region(region_code)
		return {} if r == null else r.metrics()
	var out := {}
	for key in SUMMED_REGION_KEYS:
		out[key] = 0
	for r in regions:
		var m := r.metrics()
		for key in SUMMED_REGION_KEYS:
			out[key] += m[key]
	out["investments_approved"] = investments_approved
	out["investments_declined"] = investments_declined
	out["projects_completed"] = projects_completed
	out["projects_stalled"] = projects_stalled
	out["rent_income"] = rent_income
	out["land_sales"] = land_sales
	out["construction_spend"] = construction_spend
	return out


## Bu okuma eksi `before` (aynı anahtarlar; `before` null ya da bölge yoksa sıfırdan). Talep/yük ‰ alanları da
## farktır (işaretli). `region_code` boşsa şehir geneli.
func delta_since(before: EconomyOutcomeView, region_code: StringName = &"") -> Dictionary:
	var now := metrics(region_code)
	var old := {} if before == null else before.metrics(region_code)
	var out := {}
	for key: String in now:
		out[key] = int(now[key]) - int(old.get(key, 0))
	return out


func to_dict() -> Dictionary:
	return {
		"provenance": provenance, "tick": tick, "available": available,
		"unavailable_reason_key": unavailable_reason_key, "regions": SimDto.dicts_of(regions),
		"investments_approved": investments_approved, "investments_declined": investments_declined,
		"projects_completed": projects_completed, "projects_stalled": projects_stalled,
		"rent_income": rent_income, "land_sales": land_sales, "construction_spend": construction_spend,
		"municipal_revenue_available": municipal_revenue_available,
		"municipal_revenue_reason_key": municipal_revenue_reason_key, "municipal_revenue": municipal_revenue,
	}


static func from_dict(d: Dictionary) -> EconomyOutcomeView:
	var o := EconomyOutcomeView.new()
	o.provenance = SimContract.to_name(d.get("provenance", SimContract.PROVENANCE_SIM))
	o.tick = SimContract.to_int(d.get("tick"))
	o.available = SimContract.to_bool(d.get("available", false))
	o.unavailable_reason_key = SimContract.to_name(d.get("unavailable_reason_key", REASON_NOT_BUILT))
	for rd: Variant in d.get("regions", []):
		if rd is Dictionary:
			o.regions.append(EconomyRegionOutcome.from_dict(rd))
	o.investments_approved = SimContract.to_int(d.get("investments_approved"))
	o.investments_declined = SimContract.to_int(d.get("investments_declined"))
	o.projects_completed = SimContract.to_int(d.get("projects_completed"))
	o.projects_stalled = SimContract.to_int(d.get("projects_stalled"))
	o.rent_income = SimContract.to_int(d.get("rent_income"))
	o.land_sales = SimContract.to_int(d.get("land_sales"))
	o.construction_spend = SimContract.to_int(d.get("construction_spend"))
	o.municipal_revenue_available = SimContract.to_bool(d.get("municipal_revenue_available", false))
	o.municipal_revenue_reason_key = SimContract.to_name(
		d.get("municipal_revenue_reason_key", REASON_MUNICIPAL_REVENUE_NOT_BUILT))
	o.municipal_revenue = SimContract.to_int(d.get("municipal_revenue"))
	return o
