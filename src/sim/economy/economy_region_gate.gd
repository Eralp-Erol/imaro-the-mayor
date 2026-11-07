class_name EconomyRegionGate
extends RefCounted
## Ekonomi bölge değiştirici kapısı (T-078; ADR öngörüsü: teknik direktör M3 notu §2 "bölge değiştirici kapısı").
## Dış sistemler (komşu ilçe belediyeleri, makro; M3 hatları) ekonomi bölge sütunlarına YALNIZ buradan girer; ekonomi
## dosyasına/sütunlarına başka yerden yazılmaz. Kapı yalnız bir izin listesindeki sütunlara tamsayı DELTA uygular,
## sınırlar içinde tutar ve bilinmeyen bölge/sütunu durumu değiştirmeden reddeder. Bugün çağıran yoktur (davranış
## değişmez); çağıran kendi kararının gerekçesini kendi kaydeder (SIM-12). Rastgelelik yoktur.

const REASON_NOT_STARTED := &"economy.not_started"
const REASON_UNKNOWN_REGION := &"gate.unknown_region"
const REASON_UNKNOWN_COLUMN := &"gate.unknown_column"
## Kapıdan değiştirilebilen sütunlar -> üst sınır (-1 = sınırsız). Alt sınır hep 0. ‰ sütunları 0..1000 aralığındadır.
const COLUMN_LIMITS := {
	&"access_pm": 1000,  # erişim ‰
	&"service_pm": 1000,  # kamu hizmeti ‰
	&"latent_hh": -1,  # gizli hane talebi (göç)
	&"infra_cap": -1,  # altyapı kapasitesi (birim)
}


## `d` = `state.systems["economy"]` (boşsa ekonomi kurulmamıştır). Başarıda &"", aksi halde ret kodu.
static func apply(d: Dictionary, region_code: StringName, column: StringName, amount: int) -> StringName:
	if d.is_empty():
		return REASON_NOT_STARTED
	if not COLUMN_LIMITS.has(column):
		return REASON_UNKNOWN_COLUMN
	var regions: Dictionary = d["regions"]
	var r := (regions["codes"] as PackedStringArray).find(String(region_code))
	if r < 0:
		return REASON_UNKNOWN_REGION
	var values: PackedInt64Array = regions[String(column)]
	var limit: int = COLUMN_LIMITS[column]
	var value := maxi(0, values[r] + amount)
	values[r] = value if limit < 0 else mini(value, limit)
	return &""
