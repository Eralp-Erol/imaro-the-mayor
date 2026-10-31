class_name VegetationParcelMask
extends RefCounted
## T-042b · Alınan (kamulaştırılan) parselin İÇİNDEKİ bitki örneklerini parsel kimliğiyle gizleme kuralı (GÖRÜNÜM; sim'e
## ve bitki sütunlarına yazmaz). `BuildingParcelMask`ın bitki karşılığı: yapı satırı yerine bitki satırı, yapı
## hücre planı yerine `VegetationLayout.CH_PARCEL` maskesi. Kural SAF ve deterministiktir (rastgelelik yok): bitki
## yerleşimi dünya verisinden zaten parsel dış çizgisine göre yapılır (`VegetationPlacement`: avlu/çit/koru
## `is_point_in_polygon(p, parcel.outline)`), burada AYNI sınama tersinden kullanılır: dış çizgi içindeki satırlar.
## Artımlı ve ucuz: yalnız alınan/geri gelen parselin kutusuna değen 256 m hücrelerin satırları taranır; tarama
## `step(budget_us)` ile kare dilimlerine bölünür; hesaplanan satırlar parsel başına saklanır (geri alınca yeniden
## taranmaz). Saf: Node/Mesh yok.

const ROWS_PER_CHECK := 256
const BOX_PAD_M := 0.5

## Parsel kimliği -> hesaplanmış satırlar (artan, tekil).
var rows_of: Dictionary = {}
## Tanı: taranan satır sayısı (toplam).
var rows_scanned: int = 0

var _layout: VegetationLayout = null
var _queue: Array[int] = []
var _job_pid: int = -1
var _job_outline: PackedVector2Array = PackedVector2Array()
var _job_lo: Vector2 = Vector2.ZERO
var _job_hi: Vector2 = Vector2.ZERO
var _job_cells: PackedInt32Array = PackedInt32Array()
var _job_cell_i: int = 0
var _job_row: int = 0
var _job_acc: PackedInt32Array = PackedInt32Array()
var _done_since_union: bool = false


## Yerleşim değiştiyse (ya da ilk kez) tüm hesap düşer; true dönerse çağıran her şeyi yeniden istemeli.
func bind(layout: VegetationLayout) -> bool:
	if layout == _layout:
		return false
	_layout = layout
	rows_of.clear()
	_queue.clear()
	_job_pid = -1
	_done_since_union = true
	return true


## İstenen küme (pid -> true) ile eşitler: artık istenmeyenler düşer, eksikler kuyruğa girer. Dönüş: değişen
## (düşen ya da kuyruğa giren) parsel sayısı. `outlines`: pid -> PackedVector2Array
## (dış çizgisi bilinmeyen parsel atlanır).
func want(wanted: Dictionary, outlines: Dictionary) -> int:
	var changed := 0
	for pid: int in rows_of.keys():
		if not wanted.has(pid):
			rows_of.erase(pid)
			_done_since_union = true
			changed += 1
	var keep: Array[int] = []
	for pid: int in _queue:
		if wanted.has(pid):
			keep.append(pid)
	_queue = keep
	var fresh: Array[int] = []
	for pid: int in wanted:
		if rows_of.has(pid) or _queue.has(pid) or pid == _job_pid or not outlines.has(pid):
			continue
		fresh.append(pid)
	fresh.sort()
	_queue.append_array(fresh)
	changed += fresh.size()
	if _job_pid >= 0 and not wanted.has(_job_pid):
		_job_pid = -1
	return changed


## Bekleyen tarama var mı?
func pending() -> bool:
	return _job_pid >= 0 or not _queue.is_empty()


## Hesaplanmış satır kümesi değişti mi (son `union_rows` çağrısından beri)?
func changed() -> bool:
	return _done_since_union


## En çok `budget_us` mikrosaniye tarar (en az bir dilim). Dönüş: bu çağrıda tamamlanan parsel sayısı.
func step(outlines: Dictionary, budget_us: int) -> int:
	if _layout == null:
		return 0
	var t0 := Time.get_ticks_usec()
	var finished := 0
	while true:
		if _job_pid < 0:
			if _queue.is_empty():
				break
			if not _begin(_queue.pop_front(), outlines):
				continue
		if _scan(t0, budget_us):
			rows_of[_job_pid] = _job_acc
			_job_pid = -1
			_done_since_union = true
			finished += 1
		if Time.get_ticks_usec() - t0 >= budget_us:
			break
	return finished


## Tüm gizli parsellerin satırlarının birleşimi (artan, tekil).
func union_rows() -> PackedInt32Array:
	_done_since_union = false
	var out := PackedInt32Array()
	for pid: int in rows_of:
		out.append_array(rows_of[pid] as PackedInt32Array)
	out.sort()
	var uniq := PackedInt32Array()
	for i in out:
		if uniq.is_empty() or uniq[uniq.size() - 1] != i:
			uniq.append(i)
	return uniq


## Senkron tam tarama (test/araç): dış çizgi içindeki bitki satırları (artan, tekil).
static func rows_in_outline(layout: VegetationLayout, outline: PackedVector2Array) -> PackedInt32Array:
	var m := VegetationParcelMask.new()
	m.bind(layout)
	var outlines := {0: outline}
	m.want({0: true}, outlines)
	m.step(outlines, 1 << 40)
	return m.rows_of.get(0, PackedInt32Array())


func _begin(pid: int, outlines: Dictionary) -> bool:
	var outline: PackedVector2Array = outlines.get(pid, PackedVector2Array())
	if outline.size() < 3:
		rows_of[pid] = PackedInt32Array()
		return false
	_job_pid = pid
	_job_outline = outline
	_job_acc = PackedInt32Array()
	_job_cell_i = 0
	_job_row = -1
	var lo := outline[0]
	var hi := outline[0]
	for p in outline:
		lo = lo.min(p)
		hi = hi.max(p)
	# Kutu payı: `is_point_in_polygon` sınırda bulanıktır (kutunun ~0,06 m dışındaki örneği içeride sayabilir);
	# kaba kutu ayıklaması sonucu DEĞİŞTİRMEMELİ.
	_job_lo = lo - Vector2(BOX_PAD_M, BOX_PAD_M)
	_job_hi = hi + Vector2(BOX_PAD_M, BOX_PAD_M)
	var cols := _layout.cols
	var cx0 := clampi(int(floor((lo.x - cols.origin.x) / cols.cell_m)), 0, cols.cells_w - 1)
	var cx1 := clampi(int(floor((hi.x - cols.origin.x) / cols.cell_m)), 0, cols.cells_w - 1)
	var cz0 := clampi(int(floor((lo.y - cols.origin.y) / cols.cell_m)), 0, cols.cells_h - 1)
	var cz1 := clampi(int(floor((hi.y - cols.origin.y) / cols.cell_m)), 0, cols.cells_h - 1)
	_job_cells = PackedInt32Array()
	for cz in range(cz0, cz1 + 1):
		for cx in range(cx0, cx1 + 1):
			var k := _layout.index_of_key(cz * cols.cells_w + cx)
			if k >= 0:
				_job_cells.append(k)
	return true


## Mevcut parseli sürdürür; bitti mi? Süre her `ROWS_PER_CHECK` satırda bir denetlenir.
func _scan(t0: int, budget_us: int) -> bool:
	var cols := _layout.cols
	var xs := cols.x
	var zs := cols.z
	var minx := _job_lo.x
	var maxx := _job_hi.x
	var minz := _job_lo.y
	var maxz := _job_hi.y
	while _job_cell_i < _job_cells.size():
		var k := _job_cells[_job_cell_i]
		var end := cols.cell_start[k + 1]
		if _job_row < 0:
			_job_row = cols.cell_start[k]
		while _job_row < end:
			var stop := mini(_job_row + ROWS_PER_CHECK, end)
			rows_scanned += stop - _job_row
			for i in range(_job_row, stop):
				var px := xs[i]
				if px < minx or px > maxx:
					continue
				var pz := zs[i]
				if pz < minz or pz > maxz:
					continue
				if Geometry2D.is_point_in_polygon(Vector2(px, pz), _job_outline):
					_job_acc.append(i)
			_job_row = stop
			if Time.get_ticks_usec() - t0 >= budget_us and _job_row < end:
				return false
		_job_cell_i += 1
		_job_row = -1
		if Time.get_ticks_usec() - t0 >= budget_us and _job_cell_i < _job_cells.size():
			return false
	_job_acc.sort()
	return true
