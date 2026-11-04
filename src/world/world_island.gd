class_name WorldIsland
extends RefCounted
## Ada (WLD-03): T0'da küçük, yeşil, alçak. Ada sayısı/şekli KİLİTLİ DEĞİL; veri dosyasından gelir.

var id: StringName = &""
## T0 etiketleri (örn. "natural", "low_density"). T0'da liman/sanayi etiketi taşımaz (WLD-03);
## ileride ada genişlemesi oyuncu kararıdır, bu veri onu yasaklamaz.
var t0_tags: PackedStringArray = PackedStringArray()
## Raster'daki kara kütlesi kimliği (WorldData.landmass_ids); 0 = üretimde karaya düşmedi.
var landmass_id: int = 0
var area_m2: float = 0.0
var centroid: Vector2 = Vector2.ZERO
var peak_m: float = 0.0
var basis: String = ""


func state_dict() -> Dictionary:
	return {
		"id": id, "tags": t0_tags, "landmass": landmass_id, "area": area_m2,
		"centroid": [centroid.x, centroid.y], "peak": peak_m,
	}
