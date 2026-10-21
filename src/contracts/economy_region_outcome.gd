class_name EconomyRegionOutcome
extends SimDto
## Bir bölgenin ölçülebilir ekonomik durumu (v1.1, ADR-0005 Ek C): `EconomyOutcomeView.regions` satırı. Tüm değerler
## sim'in ekonomi kohortlarından okunur (hane, konut/ticaret stoğu, talep, altyapı yükü); uydurma sayı yoktur.
## Birimler: hane/konut/dükkân birimi tamsayı; talep ve yük ‰ (`SimContract.FIXED_SCALE`, 500 talep dengesi).

## `EconomyOutcomeView.metrics(code)` anahtarları (sayısal alanlar).
const METRIC_KEYS: Array[String] = [
	"households", "housed_households", "residential_units", "commercial_units", "residential_pipeline",
	"commercial_pipeline", "sim_residential_units", "sim_commercial_units", "demand_residential_pm",
	"demand_commercial_pm", "infrastructure_load_pm",
]

var region_code: StringName = &""
## Barınma arayan toplam hane kohortu (mevcut + yeni gelen; "latent" hane).
var households: int = 0
## Barınan hane = min(households, residential_units).
var housed_households: int = 0
## Biten konut / ticaret birimi (T0 stoku DAHİL).
var residential_units: int = 0
var commercial_units: int = 0
## Onaylanmış ama bitmemiş (planlı + inşaatta + durmuş) birimler.
var residential_pipeline: int = 0
var commercial_pipeline: int = 0
## Yalnız sim'in sonradan geliştirdiği (T0 stoku olmayan) BİTMİŞ birimler: yeni tamamlanan konut / iş yeri.
var sim_residential_units: int = 0
var sim_commercial_units: int = 0
## Talep endeksleri ‰ (500 = arz talebe eşit; üstü kıtlık). Altyapı yükü / kapasite ‰ (1000 = dolu).
var demand_residential_pm: int = 0
var demand_commercial_pm: int = 0
var infrastructure_load_pm: int = 0


## Sayısal alanların {anahtar: int} sözlüğü (`METRIC_KEYS`).
func metrics() -> Dictionary:
	return {
		"households": households, "housed_households": housed_households, "residential_units": residential_units,
		"commercial_units": commercial_units, "residential_pipeline": residential_pipeline,
		"commercial_pipeline": commercial_pipeline, "sim_residential_units": sim_residential_units,
		"sim_commercial_units": sim_commercial_units, "demand_residential_pm": demand_residential_pm,
		"demand_commercial_pm": demand_commercial_pm, "infrastructure_load_pm": infrastructure_load_pm,
	}


func to_dict() -> Dictionary:
	var d := metrics()
	d["region_code"] = region_code
	return d


static func from_dict(d: Dictionary) -> EconomyRegionOutcome:
	var r := EconomyRegionOutcome.new()
	r.region_code = SimContract.to_name(d.get("region_code", ""))
	r.households = SimContract.to_int(d.get("households"))
	r.housed_households = SimContract.to_int(d.get("housed_households"))
	r.residential_units = SimContract.to_int(d.get("residential_units"))
	r.commercial_units = SimContract.to_int(d.get("commercial_units"))
	r.residential_pipeline = SimContract.to_int(d.get("residential_pipeline"))
	r.commercial_pipeline = SimContract.to_int(d.get("commercial_pipeline"))
	r.sim_residential_units = SimContract.to_int(d.get("sim_residential_units"))
	r.sim_commercial_units = SimContract.to_int(d.get("sim_commercial_units"))
	r.demand_residential_pm = SimContract.to_int(d.get("demand_residential_pm"))
	r.demand_commercial_pm = SimContract.to_int(d.get("demand_commercial_pm"))
	r.infrastructure_load_pm = SimContract.to_int(d.get("infrastructure_load_pm"))
	return r
