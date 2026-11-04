class_name BlocSignals
extends RefCounted
## Seçmen kesimi sinyalleri (T-017, characters-npc §6.5-§6.6): bölge ekonomi satırından (EconomyQuery.region_stats)
## 0..1000 ölçekli (pm) tamsayı sinyaller türetir. Kesimin sinyali, bölge sinyallerinin kesim bölge payıyla (exposure)
## ağırlıklı toplamıdır. SAF ve durumsuz; ad/bölge kodu gömülü değil. Sinyal adları `data/politics/blocs.json`
## kurallarında kullanılır (kapalı küme: yazım hatası yükleme hatasıdır).

const SCALE := 1000
const NAMES: Array[String] = [
	"construction_burden", "infra_stress", "service_gap", "service_level", "demand_shortage", "supply_added",
]
## T-042b · İsteğe bağlı sinyaller: yalnız yol kamulaştırma yaptıysa hesaplanır ve kesim durumuna yazılır (yolsuz
## koşuda durum ve hash'ler değişmez). `displacement`: yerinden edilen hane / bölge hanesi; `proximity`: yola yakın
## (yerinden edilmeyen) hane x mesafe ağırlığı / bölge hanesi. İkisi de zamanla söner (`reaction.window_days`).
const OPTIONAL_NAMES: Array[String] = ["displacement", "proximity"]
const ALL_NAMES: Array[String] = [
	"construction_burden", "infra_stress", "service_gap", "service_level", "demand_shortage", "supply_added",
	"displacement", "proximity",
]
const DEFAULT_WINDOW_DAYS := 360
## Kesim büyüklüğü kaynakları (hane kohortu).
const SIZE_SOURCES: Array[String] = ["housed_hh", "seeking_hh"]


## Bölge sinyalleri. `row`: EconomyQuery.region_row; `base_supply`: ilk taramadaki biten + boru hattı konut birimi.
@warning_ignore("integer_division")
static func of_region(row: Dictionary, base_supply: int) -> Dictionary:
	var latent := maxi(int(row["latent_hh"]), 1)
	var pipe := int(row["res_pipe"]) + int(row["com_pipe"])
	var supply := int(row["res_built"]) + int(row["res_pipe"])
	return {
		"construction_burden": clampi(pipe * SCALE / latent, 0, SCALE),
		"infra_stress": clampi(int(row["infra_load_pm"]), 0, 2 * SCALE),
		"service_gap": clampi(SCALE - int(row["service_pm"]), 0, SCALE),
		"service_level": clampi(int(row["service_pm"]), 0, SCALE),
		"demand_shortage": clampi((int(row["demand_res_pm"]) - 500) * 2, 0, SCALE),
		"supply_added": clampi((supply - base_supply) * SCALE / latent, 0, SCALE),
	}


## Kohort büyüklüğü (hane): barınan = min(bekleyen, biten konut); arayan = kalan.
static func size_of(source: String, row: Dictionary) -> int:
	var housed := int(row["housed_hh"])
	return housed if source == "housed_hh" else maxi(int(row["latent_hh"]) - housed, 0)


## Bölge payları (pm, toplamı SCALE ya da boşken 0) ve toplam büyüklük: {shares: {kod: pm}, size: int}.
@warning_ignore("integer_division")
static func exposure(rows: Array[Dictionary], source: String) -> Dictionary:
	var sizes: Array[int] = []
	var total := 0
	for row in rows:
		sizes.append(size_of(source, row))
		total += sizes[sizes.size() - 1]
	var raw: Array[int] = []
	for s in sizes:
		raw.append(s)
	var parts := ActorMath.apportion(raw, SCALE) if total > 0 else raw
	var shares := {}
	for i in rows.size():
		if parts[i] > 0:
			shares[String(rows[i]["code"])] = parts[i]
	return {"shares": shares, "size": total}


## Kesim sinyali (pm). `mean`: bölge sinyallerinin pay-ağırlıklı ortalaması; `peak`: payı `min_share` ve üstü
## bölgelerin en yüksek sinyali (yerel baskı yerel tepki doğurur; çok bölgeli kesimde ortalama onu sulandırır).
## `by_region`: {kod: {sinyal: pm}}; `shares`: {kod: pay pm}.
@warning_ignore("integer_division")
static func blend(by_region: Dictionary, shares: Dictionary, signal_name: String, peak: bool = false,
		min_share: int = 0) -> int:
	var codes: Array = shares.keys()
	codes.sort()
	if peak:
		var best := 0
		for code: String in codes:
			if int(shares[code]) >= min_share:
				best = maxi(best, int(by_region.get(code, {}).get(signal_name, 0)))
		return best
	var total := 0
	var weight := 0
	for code: String in codes:
		total += int(shares[code]) * int(by_region.get(code, {}).get(signal_name, 0))
		weight += int(shares[code])
	return 0 if weight == 0 else total / weight


## T-042b · Tepki defterinden bölge sinyali (pm). `rows`: [[tick, değer, komut]...]; satır `window` gün boyunca doğrusal
## söner. `value_scale`: displacement için SCALE (değer = hane), proximity için 1 (değer zaten hane x ağırlık_pm).
@warning_ignore("integer_division")
static func reaction_pm(rows: Array, tick: int, window: int, latent_hh: int, value_scale: int) -> int:
	var total := 0
	for row: Array in rows:
		var age := tick - int(row[0])
		if age >= 0 and age < window:
			total += int(row[1]) * (window - age) * value_scale / window
	return clampi(total / maxi(latent_hh, 1), 0, SCALE)
