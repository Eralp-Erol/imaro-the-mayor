class_name PlanHintScan
extends RefCounted
## Yol sonrası "imar planı yok" ipucu taraması, KARE DİLİMLİ (saf mantık; facade bilmez, Callable alır).
## Eski tek seferlik tarama: bölge kodları sırasıyla `ids_of(kod)` listesinin ilk `limit` parselinde `needs(id)` ilk
## doğruda durur. Ölçüm (Intel Mac, pencereli): `parcel_ids(bölge)` 40 bin parselde ~40 ms, 600 `plan_state` ~5-8 ms; ikisi
## de yol onayından sonraki ilk karede panel imzasında yapılıyordu. Burada: (1) bölge kimlik listeleri işçi iş
## parçacığında hazırlanır (`ids_of` iş parçacığı güvenli OLMALI: salt okur, çağıran durumu değiştirmez), (2) `needs`
## çağrıları `step(budget_us)` ile kare dilimlerine bölünür. Sıra ve üst sınır eskisiyle AYNIDIR: aynı girdi -> aynı `found`.

var found: bool = false
var done: bool = false
## Kaç parsel denetlendi (test/ölçüm).
var checked: int = 0

var _codes: Array = []
var _ids_of: Callable = Callable()
var _needs: Callable = Callable()
var _limit: int = 0
var _tasks: Dictionary = {}
var _ci: int = 0
var _i: int = 0
var _ids: PackedInt64Array = PackedInt64Array()
var _loaded: bool = false


static func create(codes: Array, ids_of: Callable, needs: Callable, limit: int) -> PlanHintScan:
	var scan := PlanHintScan.new()
	scan._codes = codes.duplicate()
	scan._ids_of = ids_of
	scan._needs = needs
	scan._limit = limit
	scan.done = codes.is_empty()
	return scan


## Bölge kimlik listelerini işçi iş parçacıklarında hazırlamaya başlar (`step` bitmeyenleri beklemeden döner).
func start() -> void:
	for code: Variant in _codes:
		_spawn(code)


func _spawn(code: Variant) -> void:
	if _tasks.has(code):
		return
	var box: Array = [PackedInt64Array()]
	var ids_of := _ids_of
	var task := WorkerThreadPool.add_task(func() -> void: box[0] = ids_of.call(code), false, "PlanHintScan ids")
	_tasks[code] = {"task": task, "box": box}


## Bütçe (µs) dolana kadar parsel denetler (en az bir iş). true = tarama bitti (`found` sonucu verir).
func step(budget_us: int) -> bool:
	if done:
		return true
	var t0 := Time.get_ticks_usec()
	var worked := false
	while _ci < _codes.size():
		if worked and Time.get_ticks_usec() - t0 >= budget_us:
			return false
		if not _loaded:
			if not _load_ids(false):
				return false   # işçi henüz bitirmedi: bu karede iş yok
			worked = true
			continue
		if _i >= mini(_ids.size(), _limit):
			_ci += 1
			_loaded = false
			continue
		var id := _ids[_i]
		_i += 1
		checked += 1
		worked = true
		if bool(_needs.call(id)):
			found = true
			done = true
			return true
	done = true
	return true


## Taramayı sonuna kadar (bloklayarak) yürütür; sonuç `found`. Testler ve kapanış.
func settle() -> bool:
	while not step(1 << 40):
		_load_ids(true)
	return found


func _load_ids(block: bool) -> bool:
	var code: Variant = _codes[_ci]
	_spawn(code)
	var entry: Dictionary = _tasks[code]
	var task: int = entry["task"]
	if not block and not WorkerThreadPool.is_task_completed(task):
		return false
	WorkerThreadPool.wait_for_task_completion(task)
	_ids = (entry["box"] as Array)[0]
	_tasks.erase(code)
	_i = 0
	_loaded = true
	return true


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		for entry: Dictionary in _tasks.values():
			WorkerThreadPool.wait_for_task_completion(int(entry["task"]))
		_tasks.clear()
