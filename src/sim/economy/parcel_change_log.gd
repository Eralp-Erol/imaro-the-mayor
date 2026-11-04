class_name ParcelChangeLog
extends RefCounted
## Değişen parsel halkası (T-045, B-002): ekonomi sisteminin parsel aşaması/karar geçişlerinde kimliği buraya yazar;
## facade `parcel_changes_since` buradan O(değişen) okur. Olay günlüğünden ve gerekçe/olay saklama ufkundan BAĞIMSIZDIR.
##
## DURUM DEĞİLDİR: `GameState`'e, kayda ve hash'e girmez (kayıt biçimi/`state_hash` değişmez). Türetilmiş geçici
## veridir: aynı seed + komut dizisi aynı içeriği üretir; kayıt YÜKLENİNCE `reset` ile boşaltılır (geçmiş bilinmez,
## facade epoch'u artırır, tüketici bir kez tam yeniden eşitler). Sınırlıdır: yalnız son `window` tick tutulur.
##
## Düzen (tick başına maliyet için `note` tek ekleme): kimlikler tek sütunda ardışık; her `begin_tick` o tick'in
## başlangıç indeksini bir sınır çiftine (`_bt` tick, `_bs` başlangıç) yazar. `floor`: bu tick'e KADAR (dahil) olan
## değişimler artık tutulmaz; `since_tick >= floor` ise (since_tick, şimdi] aralığı tamdır.
## SÖZLEŞME: her tick'te `note` çağrılarından ÖNCE `begin_tick(tick)` çağrılır (EconomySystem.on_daily başı).

var _window: int
var _bt: PackedInt32Array = PackedInt32Array()
var _bs: PackedInt32Array = PackedInt32Array()
var _ids: PackedInt64Array = PackedInt64Array()
var _b_head: int = 0
var _floor: int = -1


func _init(window_ticks: int = 512) -> void:
	_window = maxi(1, window_ticks)


## Tick başlangıcı: pencereyi kaydırır, eski tick'leri bırakır ve bu tick'in sınırını açar.
func begin_tick(tick: int) -> void:
	_floor = maxi(_floor, tick - _window)
	_bt.append(tick)
	_bs.append(_ids.size())
	while _b_head < _bt.size() and _bt[_b_head] <= _floor:
		_b_head += 1
	if _b_head >= 1024 and _b_head * 2 >= _bt.size():  # amortize sıkıştırma
		_compact()


## `parcel_id` bu tick'te değişti (açık tick = son `begin_tick`). Aynı tick'te tekrar yazılabilir (okurken tekilleşir).
func note(parcel_id: int) -> void:
	_ids.append(parcel_id)


## Kayıt yüklendi: geçmiş bilinmiyor. Yalnız yüklenen tick'ten sonraki değişimler tutulur.
func reset(tick: int) -> void:
	_bt = PackedInt32Array()
	_bs = PackedInt32Array()
	_ids = PackedInt64Array()
	_b_head = 0
	_floor = tick


## `(since_tick, current_tick]` aralığı bu halkayla tam mı? (gelecekten ya da pencereden eski sorgu: hayır.)
func covers(since_tick: int, current_tick: int) -> bool:
	return since_tick >= _floor and since_tick <= current_tick


## `since_tick`ten SONRA değişen kimlikler, artan, tekrarsız. Çağıran `covers` ile doğrulamalıdır.
func ids_since(since_tick: int) -> PackedInt64Array:
	var k := maxi(_bt.bsearch(since_tick, false), _b_head)  # since_tick'ten büyük ilk tick sınırı (sınırlar artan)
	if k >= _bt.size():
		return PackedInt64Array()
	var out := _ids.slice(_bs[k])
	out.sort()
	var write := 0
	for read in out.size():
		if read == 0 or out[read] != out[read - 1]:
			out[write] = out[read]
			write += 1
	out.resize(write)
	return out


## Tutulan girdi sayısı (pencere sınırını doğrulamak için).
func size() -> int:
	return 0 if _b_head >= _bt.size() else _ids.size() - _bs[_b_head]


func floor_tick() -> int:
	return _floor


func window_ticks() -> int:
	return _window


func _compact() -> void:
	var base: int = _bs[_b_head] if _b_head < _bt.size() else _ids.size()
	_ids = _ids.slice(base)
	_bt = _bt.slice(_b_head)
	_bs = _bs.slice(_b_head)
	for k in _bs.size():
		_bs[k] -= base
	_b_head = 0
