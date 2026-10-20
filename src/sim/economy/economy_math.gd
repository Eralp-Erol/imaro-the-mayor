class_name EconomyMath
extends RefCounted
## Ekonomi çekirdeğinin saf, durumsuz tamsayı matematiği (T-013). Float yok; bölmeler sıfıra doğru keser (GDScript
## int bölmesi), platformlar arası aynıdır (PLT-04). Formüller: design/specs/economy-core-v0.md §3-§4.

const SCALE := 1000


@warning_ignore("integer_division")
static func ratio_pm(numerator: int, denominator: int) -> int:
	return numerator * SCALE / maxi(denominator, 1)


## Talep endeksi 0..1000 (500 = arz talebe eşit): `need` talep eden birim, `supply` mevcut + boru hattı arzı.
## Talep eden yoksa (need <= 0) talep de yoktur: 0 (müşterisiz dükkân/hanesiz konut yatırımı çekmez).
@warning_ignore("integer_division")
static func demand_index_pm(need: int, supply: int, gain_pm: int) -> int:
	if need <= 0:
		return 0
	var shortage_pm := ratio_pm(need - supply, need)
	return clampi(500 + shortage_pm * gain_pm / SCALE, 0, SCALE)


## Talep endeksinden yatırımcı etken değeri: -1000..1000 (500 -> 0).
static func demand_value(index_pm: int) -> int:
	return clampi((index_pm - 500) * 2, -SCALE, SCALE)


## Kira çarpanı ‰: talep arttıkça kira tabandan tavana çıkar.
@warning_ignore("integer_division")
static func rent_mult_pm(index_pm: int, floor_pm: int, cap_pm: int) -> int:
	return floor_pm + index_pm * (cap_pm - floor_pm) / SCALE


## Proje birimi: alan x birim/1000 m2 x yoğunluk, yükseklik sınırıyla kat oranı. `max_height_m < 0` = sınır yok.
## 0 dönerse (yoğunluk 0 ya da yükseklik bir kata yetmiyor) imar yapılanmaya kapalı sayılır.
@warning_ignore("integer_division")
static func project_units(area_m2: int, units_per_1000m2: int, density_pm: int, max_height_m: int, storey_m: int,
		reference_floors: int) -> int:
	if density_pm <= 0:
		return 0
	var floors := reference_floors
	if max_height_m >= 0:
		floors = mini(max_height_m / storey_m, reference_floors)
	if floors <= 0:
		return 0
	var base := area_m2 * units_per_1000m2 * density_pm / 1_000_000
	return maxi(1, base * floors / reference_floors)


## Aylık kesir birikimli oransal değişim: (değer * oran_pm + kalan) / 1000; yeni kalan ayrıca döner.
## Dönüş: [değişim, yeni_kalan]. Sıfıra doğru kesme yanlılığı kalan ile giderilir.
@warning_ignore("integer_division")
static func accumulate_pm(value: int, rate_pm: int, remainder: int) -> Array[int]:
	var total := value * rate_pm + remainder
	var change := total / SCALE
	return [change, total - change * SCALE]


## Bölgenin altyapı yükü: (biten + boru hattı birimleri) x birim başına altyapı tüketimi.
static func infra_load(cfg: EconomyConfig, regions: Dictionary, r: int) -> int:
	var res_units: int = (regions["res_built"] as PackedInt64Array)[r] + (regions["res_pipe"] as PackedInt64Array)[r]
	var com_units: int = (regions["com_built"] as PackedInt64Array)[r] + (regions["com_pipe"] as PackedInt64Array)[r]
	return res_units * cfg.use_param(EconomyConfig.USE_RESIDENTIAL, "infra_per_unit") \
		+ com_units * cfg.use_param(EconomyConfig.USE_COMMERCIAL, "infra_per_unit")


## Bölgenin kullanım talebi endeksi (0..1000; 500 = denge). `extra_units`: değerlendirilen projenin eklediği arz.
## Konut: talep = bekleyen hane; ticaret: talep = barınan hane x dükkân/hane x gelir (desteklenen dükkân birimi).
@warning_ignore("integer_division")
static func region_demand_pm(cfg: EconomyConfig, regions: Dictionary, r: int, use: int, extra_units: int) -> int:
	var latent: int = (regions["latent_hh"] as PackedInt64Array)[r]
	var gain := cfg.p("demand_gain_pm")
	if use == EconomyConfig.USE_RESIDENTIAL:
		var supply: int = (regions["res_built"] as PackedInt64Array)[r] + (regions["res_pipe"] as PackedInt64Array)[r]
		return demand_index_pm(latent, supply + extra_units, gain)
	var housed := mini(latent, (regions["res_built"] as PackedInt64Array)[r])
	var need: int = housed * cfg.p("shops_per_household_pm") * (regions["income_pm"] as PackedInt64Array)[r] / 1_000_000
	var com_supply: int = (regions["com_built"] as PackedInt64Array)[r] + (regions["com_pipe"] as PackedInt64Array)[r]
	return demand_index_pm(need, com_supply + extra_units, gain)
