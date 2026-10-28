class_name VegetationLod
extends RefCounted
## Bitki kademe seçimi (T-062 B1; T-057 Karar 5): saf, veri güdümlü. Zincir: LOD0 (< lod0_end_m) -> LOD1
## (< lod1_end_m) -> yok (hücre lekesi o mesafeyi gölgelendiricide üstlenir). PROXY'si olan türler (palmiye) için LOD1
## ile `palm_proxy_end_m` arası 40 üçgenlik PROXY. Mesafe = kameradan ağaç gövde tabanına 3B uzaklık (örnek başına).
## Sınır: `d < end` o kademede; `d == end` bir sonrakinde (yarı açık aralıklar, boşluk/çakışma yok).

enum Tier { LOD0, LOD1, PROXY, NONE }

## `uniform_tier` karışık sonuç değeri.
const MIXED := -1

var lod0_end_m: float = 120.0
var lod1_end_m: float = 400.0
var palm_proxy_end_m: float = 1500.0


static func from_config(config: VegetationViewConfig) -> VegetationLod:
	var lod := VegetationLod.new()
	lod.lod0_end_m = config.lod0_end_m
	lod.lod1_end_m = config.lod1_end_m
	lod.palm_proxy_end_m = config.palm_proxy_end_m
	return lod


## Mesafeye göre kademe; `has_proxy` türün PROXY seviyesi var mı.
func tier_for(distance_m: float, has_proxy: bool) -> Tier:
	if distance_m < lod0_end_m:
		return Tier.LOD0
	if distance_m < lod1_end_m:
		return Tier.LOD1
	if has_proxy and distance_m < palm_proxy_end_m:
		return Tier.PROXY
	return Tier.NONE


## Bu türün ağaç düğümü gerektirdiği en uzak mesafe (hücre açma yarıçapı).
func reach_end_m(has_proxy: bool) -> float:
	return palm_proxy_end_m if has_proxy else lod1_end_m


## Kamera noktasından eksen hizalı kutuya (min, max) en kısa ve en uzun 3B uzaklık.
static func box_distance_range(cam: Vector3, box_min: Vector3, box_max: Vector3) -> Vector2:
	var near_sq := 0.0
	var far_sq := 0.0
	for axis in 3:
		var c := cam[axis]
		var lo := box_min[axis]
		var hi := box_max[axis]
		var nearest := 0.0
		if c < lo:
			nearest = lo - c
		elif c > hi:
			nearest = c - hi
		var farthest := maxf(absf(c - lo), absf(c - hi))
		near_sq += nearest * nearest
		far_sq += farthest * farthest
	return Vector2(sqrt(near_sq), sqrt(far_sq))


## Kutu içindeki tüm örnekler aynı kademede mi: kademe, değilse NONE'dan farklı `MIXED` = -1 döner.
## (Palmiye PROXY'si ve NONE da kademedir.) Dönüş: Tier değeri ya da MIXED.
func uniform_tier(range_m: Vector2, has_proxy: bool) -> int:
	var a := tier_for(range_m.x, has_proxy)
	var b := tier_for(range_m.y, has_proxy)
	return int(a) if a == b else MIXED


## Tutarlılık hataları (boş = geçerli).
func problems() -> PackedStringArray:
	var out := PackedStringArray()
	if lod0_end_m <= 0.0:
		out.append("lod0_end_m <= 0")
	if lod1_end_m <= lod0_end_m:
		out.append("lod1_end_m <= lod0_end_m")
	if palm_proxy_end_m < lod1_end_m:
		out.append("palm_proxy_end_m < lod1_end_m")
	return out
