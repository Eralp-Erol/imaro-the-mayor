class_name RoadDraftParcelScan
extends RefCounted
## `RoadDraftCheck.first_parcel_hit` için ucuz ön eleme (T-051; yol gönderim denetimi maliyeti). Taslak örneklerinin
## çok büyük çoğunluğu parselli olmayan bloklara (ya da hiçbir bloğa) düşer; `WorldNetwork.block_at` ise örnek başına
## ızgara sorgusu + (bazen yüzlerce köşeli) çokgen içinde-mi sınaması yapar. Özgün denetim (`_in_parcelized_block`)
## "örneği içeren İLK blok parselli mi" diye bakar; hiçbir PARSELLİ blok örneği içermiyorsa o blok (varsa) parselsizdir
## ve sonuç zaten false. Bu yüzden önce yalnız parselli blokların (taslak kutusuyla çakışanların; küçük çokgenler)
## kutu + çokgen sınaması yapılır; hiçbiri içermiyorsa `block_at` hiç çağrılmaz. Biri içeriyorsa (nadir) özgün denetim
## AYNEN çalışır, bu yüzden sonuç ve `at` değişmez. Saf; WorldNetwork'ün `_`-önekli üyelerine bilerek erişir.

var _rects: Array[Rect2] = []
var _outlines: Array[PackedVector2Array] = []


## `box` ile kutusu çakışan PARSELLİ blokların ızgara kutuları ve çokgenleri (blok kimliği sırasıyla).
static func create(net: WorldNetwork, box: Rect2) -> RoadDraftParcelScan:
	var scan := RoadDraftParcelScan.new()
	for bid in net._block_grid.query_rect(box):
		var block: WorldBlock = net.blocks.get(bid, null)
		if block != null and not block.parcel_ids.is_empty():
			scan._rects.append(net._block_grid.rect_of(bid))
			scan._outlines.append(block.outline)
	return scan


## Taslağın tüm örneklerini kapsayan kutu (köşeler + yarı genişlik + 1 m pay).
static func sample_box(pts: PackedVector2Array, half_width_m: float) -> Rect2:
	var box := Rect2(pts[0], Vector2.ZERO)
	for p in pts:
		box = box.expand(p)
	return box.grow(half_width_m + 1.0)


func is_empty() -> bool:
	return _rects.is_empty()


## Nokta parselli bloklardan birinin içinde mi (kutu sınaması `query_point` ile aynı: kenarlar dahil)?
func covers(p: Vector2) -> bool:
	var probe := Rect2(p, Vector2.ZERO)
	for i in _rects.size():
		if probe.intersects(_rects[i], true) and NetworkGeometry.point_in_polygon(p, _outlines[i]):
			return true
	return false
