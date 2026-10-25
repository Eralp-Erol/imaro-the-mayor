class_name NetworkNoise
extends RefCounted
## Tohumlu, deterministik, tamsayı-hash'li değer gürültüsü (T-049 A: organik şehir formu). Platformdan bağımsız
## (yalnız 32-bit tamsayı karışımı + float lerp); Node/Time/OS/global rastgelelik yok. Çıktı aralığı [-1, 1].

const _MASK32 := 0xFFFFFFFF
const _OCTAVE_SALT := 40503


## Tamsayı hücre köşesi için [0, 1) hash değeri.
static func hash01(seed_hash: int, i: int, j: int) -> float:
	var x := (seed_hash ^ (i * 73856093) ^ (j * 19349663)) & _MASK32
	x = ((x ^ (x >> 16)) * 2246822519) & _MASK32
	x = ((x ^ (x >> 13)) * 3266489917) & _MASK32
	x = x ^ (x >> 16)
	return float(x & 0xFFFFFF) / 16777216.0


## Tek oktav yumuşatılmış değer gürültüsü, [-1, 1]; `cell_m` = özellik boyu (m).
static func value(seed_hash: int, p: Vector2, cell_m: float) -> float:
	var fx := p.x / maxf(cell_m, 1.0)
	var fy := p.y / maxf(cell_m, 1.0)
	var ix := int(floor(fx))
	var iy := int(floor(fy))
	var tx := fx - float(ix)
	var ty := fy - float(iy)
	tx = tx * tx * (3.0 - 2.0 * tx)
	ty = ty * ty * (3.0 - 2.0 * ty)
	var top := lerpf(hash01(seed_hash, ix, iy), hash01(seed_hash, ix + 1, iy), tx)
	var bottom := lerpf(hash01(seed_hash, ix, iy + 1), hash01(seed_hash, ix + 1, iy + 1), tx)
	return lerpf(top, bottom, ty) * 2.0 - 1.0


## Çok oktavlı toplam: sum(amps[k] * value(cells[k])); oktavlar bağımsız tohumlanır.
static func fbm(seed_hash: int, p: Vector2, cells: Array, amps: Array) -> float:
	var sum := 0.0
	for k in mini(cells.size(), amps.size()):
		sum += float(amps[k]) * value((seed_hash + k * _OCTAVE_SALT) & _MASK32, p, float(cells[k]))
	return sum
