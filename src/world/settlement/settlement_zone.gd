class_name SettlementZone
extends RefCounted
## Bir bölge dokusunun (zone) yerleşim parametreleri (settlement.json `zones[ad]`; T-005). Saf veri.

var name: StringName = &""
## Adayları paralel dizilerdir: modül + taban ağırlık (aile ağırlığı / aile kimlik sayısı x id_weights).
var candidates: Array[SettlementModule] = []
var base_weights: PackedFloat32Array = PackedFloat32Array()
var floors_shift: float = 0.0
var floors_sigma: float = 1.3
var gf_main: float = 1.0
var gf_local: float = 1.0
var setback_min: float = 0.3
var setback_max: float = 1.0
var gap_min: float = 0.0
var gap_max: float = 0.4
var adjacent: bool = true
var units_max: int = 3
var rows: int = 1
## Arka sıra (avlu/iç blok) olasılığı ve ön sıra ile arasındaki boşluk [min, max] (m).
var second_row_p: float = 0.7
var row_gap_min: float = 3.0
var row_gap_max: float = 6.0
## Çok parselli ("geniş") yapı olasılığı: lot başına, `wide_*` adaylarından (sivil yapı, atölye/depo) biri komşu
## parselleri birleştirerek yerleşir (ayak izi tek lota sığmaz).
var wide_p: float = 0.0
var wide_modules: Array[SettlementModule] = []
var wide_weights: PackedFloat32Array = PackedFloat32Array()
var heritage_p: float = 0.0
## Sabit doluluk olasılığı (>= 0): bölge t'sine bağlı doluluğu geçersiz kılar (endüstriyel saha); < 0 = bölge doluluğu.
var fill_p: float = -1.0
## Doku başına çeşitlilik penceresi alt sınırı (> 0 ise placement varsayılanını geçersiz kılar; sanayi avlusu).
var min_meshes: int = 0
var min_walls: int = 0
## 200 m hücrede (mesh, duvar) kombinasyonunun yinelenmesini cezalandır (kit §3.3); sanayi avlusu/tarla için kapalı.
var unique_combo: bool = true
## 500 m hücrede kiremit çatı payı bu değeri aşınca kiremit modüllerinin ağırlığı kısılır (kit §3.2: pencere <= %55).
var tile_cap: float = 1.0
