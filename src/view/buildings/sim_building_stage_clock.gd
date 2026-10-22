class_name SimBuildingStageClock
extends RefCounted
## İnşaattaki parselin kat kademesinin değişeceği günü kestirir (B-002: feed `progress_pm`i kapsamaz).
##
## Model (sim sözleşmesi; ADR-0005 Ek D notu "aşama ve süreden türetin"): inşaat her gün 1 ilerler ve
## `progress_pm = min(999, floor(1000 * geçen_gün / toplam_gün))`; toplam gün (T) aynı (kullanım, birim) için aynıdır.
## Durma/devam feed'de gelir; çağıran o zaman örneği sıfırlar. T sim yapılandırmasından OKUNMAZ (view sim verisine
## bağlanmaz): aynı parselin iki ardışık okumasından `T` adayları çıkarılır ve aynı anahtardaki sonraki okumalar
## adayları
## daraltır. Aday kümesi boşalırsa (model ihlali) anahtar sıfırlanır ve `-1` döner: çağıran güvenli yoklamaya düşer.
##
## Güvence: dönen aralık, tüm tutarlı (T, geçen_gün) adayları arasında EN KISA olandır; model doğruysa kademe değişimi
## yoklamadan ÖNCE değil SONRA değildir (geç kalmaz; fazla erken yoklayabilir).

const T_MIN := 4
const T_MAX := 999
const SCALE := 1000

var stats: Dictionary = {"learned": 0, "violations": 0, "unknown": 0}

## anahtar -> tutarlı toplam gün adayları (artan).
var _known: Dictionary = {}


func reset() -> void:
	_known = {}


## Anahtarın şu anki T adayları (boş = bilinmiyor).
func candidates(key: String) -> PackedInt32Array:
	return _known.get(key, PackedInt32Array())


## `prev` = (gün, ilerleme) önceki okuma (gün < 0: yok). `now`/`progress`: bu okuma. `next_progress`: kademenin
## değişeceği
## ilk ilerleme (‰, < SCALE). Dönüş: sonraki okumaya kadar gün (>= 1) ya da bilinmiyorsa -1.
func gap(key: String, prev: Vector2i, now: int, progress: int, next_progress: int) -> int:
	var totals: PackedInt32Array = _known.get(key, PackedInt32Array())
	if prev.x >= 0 and now > prev.x and progress >= prev.y:
		var dt := now - prev.x
		if totals.is_empty():
			totals = _consistent(_all(), prev.y, progress, dt)
			if not totals.is_empty():
				stats["learned"] += 1
		else:
			var narrowed := _consistent(totals, prev.y, progress, dt)
			if narrowed.is_empty():
				stats["violations"] += 1
				narrowed = _consistent(_all(), prev.y, progress, dt)   # model ihlali: yalnız bu çiftten yeniden öğren
			totals = narrowed
		if totals.is_empty():
			_known.erase(key)
		else:
			_known[key] = totals
	if totals.is_empty():
		stats["unknown"] += 1
		return -1
	var best := -1
	for total in totals:
		var elapsed := _elapsed(total, progress)
		if elapsed < 0:
			continue
		var gap_days := _first_day(total, next_progress) - elapsed
		if best < 0 or gap_days < best:
			best = gap_days
	return maxi(best, 1) if best >= 0 else -1


## `total` günlük inşaatta ilerleme `progress`'e tam karşılık gelen geçen gün; yoksa -1.
static func _elapsed(total: int, progress: int) -> int:
	var e := (progress * total + SCALE - 1) / SCALE
	return e if mini(SCALE * e / total, SCALE - 1) == progress and e < total else -1


## İlerlemenin `target` ‰'e ulaştığı ilk geçen gün.
static func _first_day(total: int, target: int) -> int:
	return (target * total + SCALE - 1) / SCALE


static func _all() -> PackedInt32Array:
	var out := PackedInt32Array()
	for t in range(T_MIN, T_MAX + 1):
		out.append(t)
	return out


## `candidates` içinden (p1 -> p2, dt gün) çiftiyle tutarlı olanlar.
static func _consistent(candidates_in: PackedInt32Array, p1: int, p2: int, dt: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	for total in candidates_in:
		var e1 := _elapsed(total, p1)
		if e1 < 0:
			continue
		var e2 := e1 + dt
		if e2 < total and mini(SCALE * e2 / total, SCALE - 1) == p2:
			out.append(total)
	return out
