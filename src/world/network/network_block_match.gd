class_name NetworkBlockMatch
extends RefCounted
## Yeni yüzleri mevcut bloklarla eşler (T-042 adım 1): önce geometri imzası, sonra (yalnız `keep_parcels_on_delta`)
## KÖŞE anahtarı. Köşe anahtarı, kenar bölünmesinden doğan neredeyse eşdoğrusal köşeleri (<= `CORNER_TOL_M`) yok sayar:
## `NetworkBlocks._signature` göreli 1e-4 eşdoğrusallık kullanır, 0,01 m'ye yuvarlanmış kısa kenar bölünmesi bunu
## aşıp parselli
## komşu bloğun imzasını değiştirebilir ve parsellerini yeniden ürettirirdi. Eşleşen blok kimliğini, parsellerini ve
## `owner_id`lerini korur; imzası yeni yüzün imzasına bağlanır (`WorldNetwork._update_matched_block`).
## Saf; WorldNetwork'ün `_`-önekli üyelerine bilerek erişir.

const CORNER_TOL_M := 0.03


## Eşleşen yüzleri günceller (`matched` işaretlenir); eşleşmeyenleri sırayla döndürür (çağıran `_build_block` yapar).
## `candidates`: tolerans eşlemesine aday blok kimlikleri (kimlik -> true).
static func match_faces(net: WorldNetwork, faces: Array[Dictionary], matched: Dictionary,
		candidates: Dictionary) -> Array[Dictionary]:
	var pending: Array[Dictionary] = []
	for face in faces:
		var old_id := int(net._block_by_sig.get(face["signature"], -1))
		if old_id >= 0 and not matched.has(old_id) and net.blocks.has(old_id):
			matched[old_id] = true
			net._update_matched_block(net.blocks[old_id], face)
		else:
			pending.append(face)
	if not net.rules.keep_parcels_on_delta or pending.is_empty():
		return pending
	var keys := {}
	var ids: Array = candidates.keys()
	ids.sort()
	for bid: int in ids:
		if matched.has(bid) or not net.blocks.has(bid) or (net.blocks[bid] as WorldBlock).parcel_ids.is_empty():
			continue
		keys[corner_key((net.blocks[bid] as WorldBlock).outline)] = bid
	var rest: Array[Dictionary] = []
	for face in pending:
		var bid := int(keys.get(corner_key(face["points"]), -1))
		if bid >= 0 and not matched.has(bid):
			matched[bid] = true
			net._update_matched_block(net.blocks[bid], face)
		else:
			rest.append(face)
	return rest


## Köşe anahtarı: poligonun gerçek köşeleri (komşu köşelerin kirişine uzaklığı > tolerans ya da geri dönüş), en küçük
## (x, y) köşeden başlayarak santimetre yuvarlamalı, MD5.
static func corner_key(points: PackedVector2Array) -> String:
	var n := points.size()
	var corners: Array[Vector2] = []
	for i in n:
		var prev := points[(i + n - 1) % n]
		var cur := points[i]
		var nxt := points[(i + 1) % n]
		var chord := nxt - prev
		var chord_len := chord.length()
		var dist := INF if chord_len < 1.0e-6 else absf(chord.cross(cur - prev)) / chord_len
		if dist > CORNER_TOL_M or (cur - prev).dot(nxt - cur) <= 0.0:
			corners.append(cur)
	if corners.is_empty():
		return ""
	var best := 0
	for k in corners.size():
		var a := corners[k]
		var b := corners[best]
		if a.x < b.x or (a.x == b.x and a.y < b.y):
			best = k
	var parts := PackedStringArray()
	for off in corners.size():
		var c := corners[(best + off) % corners.size()]
		parts.append("%d,%d" % [int(round(c.x * 100.0)), int(round(c.y * 100.0))])
	return ";".join(parts).md5_text()


## Parselin cephe kenarı (bölünme sonrası kısalmış olabilir) cephe orta noktasına hâlâ bakıyor mu?
static func frontage_holds(net: WorldNetwork, parcel: WorldParcel) -> bool:
	var e: WorldRoadEdge = net.edges.get(parcel.frontage_edge, null)
	if e == null:
		return false
	var d := NetworkGeometry.distance_point_segment(parcel.front_mid, net.node_pos(e.a), net.node_pos(e.b))
	return d <= e.width * 0.5 + NetworkInvariants.FRONTAGE_TOLERANCE_M

