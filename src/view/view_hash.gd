class_name ViewHash
extends RefCounted
## Görünüm katmanı için saf, deterministik 32-bit karma (T-062 A4): parsel/yol kimliğinden zemin/asfalt seçimi.
## RNG akışı, zaman, kare sırası YOK: aynı (kimlik, tohum) -> aynı değer, her koşuda ve her platformda.
## Simülasyon bunu KULLANMAZ (görünüm süsü; sim hash'ini etkilemez).

const _MASK32 := 0xFFFFFFFF


## [0, 1) değeri.
static func hash01(id: int, variant_seed: int) -> float:
	var x := ((id + 1) * 2654435761 + variant_seed * 40503) & _MASK32
	x ^= x >> 15
	x = (x * 2246822519) & _MASK32
	x ^= x >> 13
	x = (x * 3266489917) & _MASK32
	x ^= x >> 16
	return float(x & _MASK32) / 4294967296.0
