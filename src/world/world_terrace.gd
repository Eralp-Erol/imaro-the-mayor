class_name WorldTerrace
extends RefCounted
## Yerleşim sekisi (settlement terrace): yamaç bölgesinin alt kotunda, eğimi ve rölyefi bilerek sönümlenmiş düz
## yerleşilebilir alan (T0'da merkez/çarşı/konut için; WLD-04). `terrain.json: settlement_terraces` verisinden çözülür;
## merkez bölge çapasından + normalize ofsetten türetilebilir (sabit koordinat yok). Statü ÇALIŞMA MODELİ: yer, boyut ve
## eğim kanon değildir, serbestçe düzenlenir.
##
## Geometri: eliptik çekirdek (`radius`) içinde ağırlık 1 (arazi tamamen sekinin eğik düzlemi), çekirdeğin dışında
## `falloff` * radius genişliğinde smoothstep ile orijinal araziye karışır (uçurum değil, rampa); sırt/rölyef gürültüsü
## ayrıca daha geniş `detail_falloff` bandında önceden sönümlenir.

var id: StringName = &""
## Türetildiği bölge kodu (&"D5"); mutlak merkez verildiyse boş.
var region_code: StringName = &""
## false = seki kapalı: ayak izi korunur ama arazi değiştirilmez (olumsuz test / karşılaştırma).
var enabled: bool = true
## Dünya metresi: çekirdek merkezi, eliptik çekirdek yarıçapı.
var center: Vector2 = Vector2.ZERO
var radius: Vector2 = Vector2.ZERO
## Çekirdek dışı karışım genişliği (çekirdek yarıçapının katı); toplam etki alanı radius * (1 + falloff).
var falloff: float = 1.2
## Sırt + rölyef gürültüsünün sönüm bandı genişliği (çekirdek yarıçapının katı); düzlem bandından geniştir, böylece
## seki kenarında rölyef önce yumuşar, sonra düzleme geçilir (varsayılan 2 * falloff).
var detail_falloff: float = 2.4
## Hedef eğim (derece) ve yukarı (masife) yön birim vektörü (dünya x, z); varsayılan bölge çapasına doğru.
var slope_deg: float = 5.0
var uphill: Vector2 = Vector2.RIGHT
## Düzlem üstü mikro rölyef (m, tepeden tepeye ≈ 2x).
var micro_relief_m: float = 1.5
## Seki düzlemi merkez yüksekliği (m, deniz seviyesine göre). < 0 = türet: çekirdekteki gürültüsüz masif rölyefi
## ortalaması ile kıyıdan hedef eğimle yükselen rampanın küçüğü (üretici çözümleyip buraya yazar).
var center_height_m: float = -1.0
var basis: String = ""


## Normalize eliptik uzaklık: 0 merkez, 1 çekirdek kenarı, 1 + falloff etki alanının sonu.
func normalized_distance(p: Vector2) -> float:
	var d := p - center
	return sqrt((d.x / radius.x) * (d.x / radius.x) + (d.y / radius.y) * (d.y / radius.y))


## Seki ağırlığı: çekirdekte 1, etki alanı dışında 0, arada smoothstep.
func weight(p: Vector2) -> float:
	return 1.0 - smoothstep(1.0, 1.0 + falloff, normalized_distance(p))


## Çekirdek içinde mi (u <= 1)?
func in_core(p: Vector2) -> bool:
	return normalized_distance(p) <= 1.0


func state_dict() -> Dictionary:
	return {
		"id": id, "region": region_code, "enabled": enabled, "center": [center.x, center.y],
		"radius": [radius.x, radius.y], "falloff": falloff, "detail_falloff": detail_falloff, "slope_deg": slope_deg,
		"uphill": [uphill.x, uphill.y], "micro_relief_m": micro_relief_m, "center_height_m": center_height_m,
	}
