class_name NetworkDelta
extends RefCounted
## Taban ağın üstündeki DEĞİŞEN katman: oyuncunun yol ekleme/silme/açma-kapama komutları sırayla (CAN-04, T-011).
## Tohum + kontrol verisi tabanı yeniden üretir; kayıt yalnız bu delta'yı saklar (taban + delta). Saf veri.
## Op sözlükleri JSON güvenlidir: koordinatlar santimetre TAMSAYI (kayan nokta dolaşımı yok), genişlik desimetre.
##   {"op": "add_road", "pts_cm": [[x, y], ...], "class": "local", "width_dm": 100}
##   {"op": "remove_edge", "edge": 12}
##   {"op": "set_open", "edge": 12, "open": false}
## Kenar kimlikleri, deltanın uygulandığı ağın o anki durumuna göredir (tabandan itibaren yeniden oynatma
## deterministiktir).

const VERSION := 1

## Delta'nın uygulandığı tabanın özeti; uyuşmazsa yeniden oynatma reddedilir (veri/üreteç değişmiş olabilir).
var base_hash: String = ""
var ops: Array[Dictionary] = []


func to_dict() -> Dictionary:
	return {"version": VERSION, "base_hash": base_hash, "ops": ops.duplicate(true)}


static func from_dict(data: Dictionary) -> NetworkDelta:
	var d := NetworkDelta.new()
	d.base_hash = str(data.get("base_hash", ""))
	for op: Dictionary in data.get("ops", []):
		d.ops.append(op)
	return d


static func encode_points(points: PackedVector2Array) -> Array:
	var out: Array = []
	for p in points:
		out.append([int(round(p.x * 100.0)), int(round(p.y * 100.0))])
	return out


static func decode_points(pts_cm: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for pair: Array in pts_cm:
		out.append(Vector2(int(pair[0]) * 0.01, int(pair[1]) * 0.01))
	return out
