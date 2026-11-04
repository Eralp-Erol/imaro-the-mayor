class_name ResettlementConfig
extends RefCounted
## T-065 Aşama 1 · Kamulaştırmada yeniden iskân yükümlülüğünün ÇALIŞMA sayıları (`data/sim/public_works/road_works.json`
## `expropriation.resettlement`; spec `design/specs/resettlement-social-security-v0.md` §4/§6). Hepsi ÇALIŞMA MODELİ
## (F05-C): ayarlanabilir, kanon DEĞİL, kodda gömülü değil. Bölüm yoksa özellik KURULU DEĞİLDİR (`available == false`:
## `policy.set` `system.not_built` ile reddedilir). Politikanın varsayılanı (kapalı) VERİDE değil, sabit kuraldır
## (ADR-0009 A): veri varsayılanı eski kayıtların davranışını sessizce çevirirdi.
##
## - `max_fill_pm`        bir yolun hedef bölgenin boş evlerinden en çok alacağı pay (‰); tek yol hepsini tüketmesin
## - `rent_tolerance_pm`  hedef kira <= kaynak kira x (1000 + tolerans) / 1000 (kira şartı)
## - `max_distance_m`     hedef bölgenin yola en yakın yapılı konut parseli bu uzaklıktan yakınsa "yer" şartı tamam
## - `partial_relief_pm`  şartlardan YALNIZ biri aşılıyorsa ("kısmi ev") tepkideki azalma (‰)
## - `residual_reaction_pm` tam uygun ev bulunan ailenin kalan tepkisi (‰); D-016 §2 "biraz kalsın": 0 DEĞİL (0 = eski
##                        D-014 "hiç olmasın" davranışı, ayar olarak mümkün)
## - `support_months`     bedel: hedef bölgenin aylık konut kirası x bu ay sayısı (gösterge)
## - `move_grant`         bedel: hane başına taşınma yardımı (AÇIK, Q-003/T-014: sayı verilmedi, 0)

const KEYS: Array[String] = ["_note", "max_fill_pm", "rent_tolerance_pm", "max_distance_m", "partial_relief_pm",
	"residual_reaction_pm", "support_months", "move_grant"]
const PM := 1000

var available: bool = false
var error: String = ""
var max_fill_pm: int = 0
var rent_tolerance_pm: int = 0
var max_distance_m: int = 0
var partial_relief_pm: int = 0
var residual_reaction_pm: int = 0
var support_months: int = 0
var move_grant: int = 0


## Bölüm sözlüğünden. Geçersizse `error` dolu (yol: `expropriation.resettlement.<anahtar>`) ve `available == false`.
static func from_dict(section: Variant) -> ResettlementConfig:
	var cfg := ResettlementConfig.new()
	if not (section is Dictionary):
		cfg.error = "expropriation.resettlement sözlük olmalı"
		return cfg
	for key: Variant in section:
		if not KEYS.has(str(key)):
			cfg.error = "expropriation.resettlement.%s bilinmeyen anahtar" % str(key)
			return cfg
	var limits := {"max_fill_pm": [0, PM], "rent_tolerance_pm": [0, 100000], "max_distance_m": [0, 1000000],
		"partial_relief_pm": [0, PM], "residual_reaction_pm": [0, PM], "support_months": [0, 1200],
		"move_grant": [0, 1000000000]}
	for key: String in limits:
		var value: Variant = section.get(key, null)
		var range_pair: Array = limits[key]
		if not _is_whole(value) or int(value) < int(range_pair[0]) or int(value) > int(range_pair[1]):
			cfg.error = "expropriation.resettlement.%s %d..%d aralığında tamsayı olmalı" % [key, range_pair[0],
				range_pair[1]]
			return cfg
		cfg.set(key, int(value))
	cfg.available = true
	return cfg


static func _is_whole(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or (typeof(value) == TYPE_FLOAT and value == floorf(value))
