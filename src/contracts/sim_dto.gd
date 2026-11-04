@abstract
class_name SimDto
extends RefCounted
## Sözleşme DTO'larının tabanı (ADR-0005). Her DTO bir DEĞER kopyasıdır: tüketicinin değiştirmesi sim'i etkilemez.
##
## Kural: `to_dict()` yalnız StateHash'in desteklediği türleri üretir (int/float/bool/String/StringName/null,
## düz `Array`, `Dictionary`, Packed*Array). Tekil Vector2 yok ([x, y]); tipli Array yok (bayt kodlaması farklıdır).
## Her alt sınıf `static func from_dict(d: Dictionary) -> <Sınıf>` sağlar; JSON'dan gelen float sayıları tamsayıya
## zorlar, bilinmeyen alanları yok sayar (ileri uyum), eksik alanlara varsayılan verir (geri uyum).
## Serileştirme: `var_to_bytes(to_dict())`; karşılaştırma: `StateHash.of(to_dict())` veya bayt eşitliği.


@abstract func to_dict() -> Dictionary


func to_bytes() -> PackedByteArray:
	return var_to_bytes(to_dict())


## Kanonik bayt eşitliği (tür duyarlı: StringName ≠ String).
func same_as(other: SimDto) -> bool:
	return other != null and to_bytes() == other.to_bytes()


## Yardımcı: DTO dizisini düz `Array` sözlük listesine çevirir.
static func dicts_of(items: Array) -> Array:
	var out: Array = []
	for item: SimDto in items:
		out.append(item.to_dict())
	return out
