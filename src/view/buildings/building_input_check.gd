class_name BuildingInputCheck
extends RefCounted
## BuildingColumns -> render girdi denetimi (T-012 ölçüt 7 olumsuz varyantlar). Geçersiz girdi çizilmez, sessizce
## düzeltilmez: hata listesi döner (BuildingView.set_columns reddeder, mevcut görüntü bozulmaz).

const MAX_ERRORS := 12
## Sütun şeması: palet satırı 0..31 (BuildingColumns bayt sütunları; hero modülde hep 0, görünüm palet kullanmaz).
const PALETTE_ROWS := 32


## Boş liste = geçerli. Sütun uzunlukları (`BuildingColumns.shape_errors`), modül aralığı, palet satırı, sonlu
## konum/yön.
static func errors(cols: BuildingColumns, module_count: int) -> PackedStringArray:
	var out := PackedStringArray()
	if cols == null:
		out.append("sütun nesnesi yok")
		return out
	out.append_array(cols.shape_errors())
	if not out.is_empty():
		return out
	for i in cols.count:
		var m := cols.module_idx[i]
		if m < 0 or m >= module_count:
			out.append("satır %d: module_idx %d aralık dışı [0, %d)" % [i, m, module_count])
		elif not is_finite(cols.x[i]) or not is_finite(cols.z[i]) or not is_finite(cols.yaw[i]):
			out.append("satır %d: konum/yön sonlu değil" % i)
		elif cols.wall_row[i] >= PALETTE_ROWS or cols.roof_row[i] >= PALETTE_ROWS \
				or cols.accent_row[i] >= PALETTE_ROWS:
			out.append("satır %d: palet satırı >= %d" % [i, PALETTE_ROWS])
		if out.size() >= MAX_ERRORS:
			out.append("... (daha fazla hata kesildi)")
			break
	return out
