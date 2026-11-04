class_name ActorMath
extends RefCounted
## Aktör modelinin tamsayı matematiği (T-016, TEK-02/PLT-04). SAF: kayan nokta, üs/log/sin çağrısı yok.
## Üstel çürüme `ppm` (1/1.000.000) sabit noktalı tamsayı çarpımlarıyla yapılır; yarı ömürden günlük tutma oranı
## ikili aramayla BULUNUR (pow/exp/log yok) => platformlar arası aynı sonuç. Tamsayı bölme sıfıra doğru keser
## (GDScript); kesme yönü her yerde budur.

const PPM := 1_000_000
const HALF_PPM := 500_000


## İki ppm değerinin çarpımı (yarıdan yukarı yuvarlanır). Girdiler >= 0.
@warning_ignore("integer_division")
static func mul_ppm(a: int, b: int) -> int:
	return (a * b + PPM / 2) / PPM


## `base_ppm ^ exponent` (ppm), kareleme ile. exponent < 0 sıfır sayılır. 0 üs = PPM.
static func pow_ppm(base_ppm: int, exponent: int) -> int:
	var result := PPM
	var base := base_ppm
	var e := maxi(exponent, 0)
	while e > 0:
		if e & 1 == 1:
			result = mul_ppm(result, base)
		e >>= 1
		if e > 0:
			base = mul_ppm(base, base)
	return result


## Yarı ömür (gün) -> günlük tutma oranı (ppm): `pow_ppm(r, yarı_ömür) >= PPM/2` olan EN KÜÇÜK r (ikili arama).
@warning_ignore("integer_division")
static func retention_for_half_life(half_life_days: int) -> int:
	var low := 0
	var high := PPM
	while low < high:
		var mid := (low + high) / 2
		if pow_ppm(mid, half_life_days) >= HALF_PPM:
			high = mid
		else:
			low = mid + 1
	return low


## Değeri hedefe doğru çürütür: `target + (value - target) * factor_ppm / PPM` (fark sıfıra doğru kesilir, bu yüzden
## hedefe TAM varır ve hiç aşmaz).
@warning_ignore("integer_division")
static func decay_toward(value: int, target: int, factor_ppm: int) -> int:
	return target + (value - target) * factor_ppm / PPM


## a / b (b > 0), yarıdan uzağa yuvarlanır.
@warning_ignore("integer_division")
static func round_div(a: int, b: int) -> int:
	if a >= 0:
		return (2 * a + b) / (2 * b)
	return -((-2 * a + b) / (2 * b))


## a / b (a >= 0, b > 0), yukarı yuvarlanır (hedefe yaklaşan hareketlerin durağanlaşmaması için).
@warning_ignore("integer_division")
static func ceil_div(a: int, b: int) -> int:
	return (a + b - 1) / b


## `raw` (>= 0) oranlarını toplamı tam `target` olacak şekilde paylaştırır (en büyük artık yöntemi; eşitlikte düşük
## indeks). Toplam 0 ise hepsi 0.
@warning_ignore("integer_division")
static func apportion(raw: Array[int], target: int) -> Array[int]:
	var total := 0
	for r in raw:
		total += r
	var shares: Array[int] = []
	if total <= 0:
		shares.resize(raw.size())
		shares.fill(0)
		return shares
	var remainders: Array[int] = []
	var assigned := 0
	for r in raw:
		shares.append(r * target / total)
		remainders.append(r * target % total)
		assigned += shares[shares.size() - 1]
	for i in target - assigned:
		var best := 0
		for j in raw.size():
			if remainders[j] > remainders[best]:
				best = j
		shares[best] += 1
		remainders[best] = -1
	return shares


static func clamp_permille(value: int) -> int:
	return clampi(value, -SimContract.FIXED_SCALE, SimContract.FIXED_SCALE)
