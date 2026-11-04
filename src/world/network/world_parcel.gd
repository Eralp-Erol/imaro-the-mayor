class_name WorldParcel
extends RefCounted
## Parsel: blok içi alt bölüm (T-011, CAN-03/05). Cephe yolu (`frontage_edge`), alan, bölge kodu (D1–D6) ve mülkiyet
## için BOŞ `owner_id` yuvası taşır; sahiplik/imar/yapı sim'indir (T-013), ağ katmanı bunları üretmez (CAN-03).

var id: int = 0
var block_id: int = 0
var outline: PackedVector2Array = PackedVector2Array()
var centroid: Vector2 = Vector2.ZERO
var area: float = 0.0
## Cephe yolu kenarı (WorldRoadEdge.id) ve cephe uzunluğu (m).
var frontage_edge: int = -1
var front_length: float = 0.0
## Cephe kenarının orta noktası (cephe yolu eşlemesi için; türev veri, hash'e girmez).
var front_mid: Vector2 = Vector2.ZERO
## Çalışma bölge kodu: &"D1" … &"D6" (WorldRegion.code; resmî ilçe değil).
var region_code: StringName = &""
## Parsel şablonu (örn. &"core", &"industrial", &"rural"): T-005 arazi kullanımı için yalnız ipucu.
var fabric: StringName = &""
## Mülkiyet yuvası: 0 = boş. Sim (T-013) doldurur; ağ katmanı değiştirmez.
var owner_id: int = 0
## Tohumlu ayrıntı değeri (cephe/doku çeşitliliği); topolojiyi etkilemez.
var detail: int = 0


func state_row(include_owner: bool) -> Array:
	var row: Array = [id, block_id, frontage_edge, area, String(region_code), String(fabric), detail]
	if include_owner:
		row.append(owner_id)
	return row
