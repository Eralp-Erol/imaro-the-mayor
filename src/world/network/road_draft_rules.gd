class_name RoadDraftRules
extends RefCounted
## Oyuncu yolu taslağı denetiminin kural/yapılandırma kümesi (T-042 adım 1; CAN-04, D-009). `network.json`
## `player_roads` bölümünden okunur: HİÇBİR sayı kodda gömülü değildir, hepsi ÇALIŞMA MODELİdir (ÇM) ve elle düzenlenir.
## Saf veri; denetim `RoadDraftCheck`te.

const DEFAULT_PATH := "res://data/world/ismeral/network.json"
const CROSSING_REJECT := &"reject"
## Aşama 2 (kamulaştırma, T-042b; Q-017 AÇIK): parselli bloğa girişe izin verir. v0'da KULLANILMAZ.
const CROSSING_ALLOW := &"allow"
## T-042b kamulaştırma kipi: DÜZ taslak (`RoadDraftCheck.check`) yine `crosses_parcels` ile reddedilir (davranış
## `reject` ile AYNI); kamulaştırma bağdaştırıcısı (`NetworkExpropriationPort`) bu kipte kullanılabilir ve parselli
## bloktan geçen yolu, parselleri BÜTÜNÜYLE alarak ekler. `keep_parcels` açık olmalıdır.
const CROSSING_EXPROPRIATE := &"expropriate"

## Oyuncunun çizebileceği yol sınıfları (sim'in `road_works.json` listesi bunun alt kümesi olmalı).
var allowed_classes: Array[StringName] = [WorldRoadEdge.CLASS_LOCAL]
var min_length_m: float = 12.0
var max_length_m: float = 400.0
## Örnek noktalarında arazi eğimi bunu aşarsa `slope` reddi (WorldData.slope_degrees_at).
var max_slope_deg: float = 11.0
## Parselli bloğun içine giriş kuralı: CROSSING_REJECT (v0) | CROSSING_EXPROPRIATE (T-042b) | CROSSING_ALLOW (düz
## denetim hiç sormaz).
var crossing_parcels: StringName = CROSSING_REJECT
## Tüm örnekler mevcut yola bu kadar yakınsa taslak `duplicate` sayılır (m).
var duplicate_tolerance_m: float = 3.0
## Parsel içinden geçiş denetimi örnek adımı (m).
var parcel_sample_step_m: float = 2.0
## Yetki alanı: bölge kodları (WorldRegion.code). BOŞ = dünyadaki tüm bölgeler. Öneri: oyuncunun başlangıç bölgesi;
## başlangıç bölgesi seçimi oyuncunundur (CAN-08, D-002), burası yalnız veri parametresidir.
var jurisdiction_regions: Array[StringName] = []


static func from_control(net_control: Dictionary) -> RoadDraftRules:
	var rules := RoadDraftRules.new()
	var data: Dictionary = net_control.get("player_roads", {})
	if data.has("allowed_classes"):
		rules.allowed_classes = []
		for cls in data["allowed_classes"]:
			rules.allowed_classes.append(StringName(str(cls)))
	rules.min_length_m = float(data.get("min_length_m", rules.min_length_m))
	rules.max_length_m = float(data.get("max_length_m", rules.max_length_m))
	rules.max_slope_deg = float(data.get("max_slope_deg", rules.max_slope_deg))
	rules.crossing_parcels = StringName(str(data.get("crossing_parcels", String(rules.crossing_parcels))))
	rules.duplicate_tolerance_m = float(data.get("duplicate_tolerance_m", rules.duplicate_tolerance_m))
	rules.parcel_sample_step_m = maxf(0.5, float(data.get("parcel_sample_step_m", rules.parcel_sample_step_m)))
	for code in data.get("jurisdiction_regions", []):
		rules.jurisdiction_regions.append(StringName(str(code)))
	return rules


static func load_path(path: String = DEFAULT_PATH) -> RoadDraftRules:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return from_control(parsed if parsed is Dictionary else {})


## Dünya kamulaştırma kipi veride açık mı? (Bağdaştırıcının `available()` koşulu; ağ tarafı `keep_parcels` ayrıca
## denetlenir.)
func expropriation_enabled() -> bool:
	return crossing_parcels == CROSSING_EXPROPRIATE


func allows_region(code: StringName) -> bool:
	return code != &"" and (jurisdiction_regions.is_empty() or jurisdiction_regions.has(code))


func to_dict() -> Dictionary:
	var classes: Array[String] = []
	for cls in allowed_classes:
		classes.append(String(cls))
	var regions: Array[String] = []
	for code in jurisdiction_regions:
		regions.append(String(code))
	return {"allowed_classes": classes, "min_length_m": min_length_m, "max_length_m": max_length_m,
			"max_slope_deg": max_slope_deg, "crossing_parcels": String(crossing_parcels),
			"duplicate_tolerance_m": duplicate_tolerance_m, "parcel_sample_step_m": parcel_sample_step_m,
			"jurisdiction_regions": regions}
