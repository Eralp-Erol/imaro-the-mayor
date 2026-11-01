class_name NetworkExpropriation
extends RefCounted
## Kamulaştırmalı yol işlemi (T-042b dünya adımı; CAN-04, D-009, D-011, ADR-0005 Ek F, plan §1 seçenek A).
##
## Parsel kümesi SABİT kimlikli kalır: yolun koridoruna giren parsel BÜTÜNÜYLE alınır (dünyadan emekliye ayrılır,
## journal'a yazılır, geri almada kimliği ve `owner_id`siyle geri konur); alınmayan parseller KİMLİĞİ ve ÇOKGENİYLE yeni
## yüzlere taşınır. YENİ parsel hiç üretilmez (`added_parcels` boş; kimlik sayacı ilerlemez).
##
## Alınan küme = koridor kesişimi: parsel çokgenine yolun eksen çizgisinden uzaklık <= yarı genişlik +
## `expropriation_margin_m` (`taken_parcels`). Aynı işlev hem önizlemede (`RoadDraftCheck.taken_parcels`, ağa dokunmaz)
## hem uygulamada (op'a `taken` olarak yazılır) çalışır; uygulama raporu `removed_parcels` bununla BİREBİR aynı olmak
## zorundadır.
##
## Yenileme ("havuzlu"): işlem bloğu bölünce eşleşmeyen eski blokların (STALE) alınmayan parselleri bir HAVUZa konur;
## yeni yüzler kurulur ve havuzdan merkezi yüzün içinde kalan parselleri kimlikleriyle alır (cephe yeniden atanır:
## `NetworkBlockBuild.update_matched_block` mantığı); eski bloklar silinir (taşınanlar silinmez, rapora girmez). Bloğu
## korunan (örn. çıkmaz sokağın yalnız yanından geçilen) bloklarda alınan parseller tek tek emekliye ayrılır. Tam
## (`refresh_blocks`) ve yerel (`NetworkLocalRefresh`) yenileme AYNI `rebuild` işlevini çağırır. Sonuç parsel kümesi
## geometriden, op'tan ve eski kümeden türer (yenileme yolundan bağımsız); yalnız blok kimlikleri yola göre farklı
## olabilir.
##
## Düğüm/kenar tablolarına DOKUNMAZ: graf özeti ve türev önbellekler (hash, dönüş sırası, bileşen) parsel değişiminden
## etkilenmez; kirli işaretleme gerekmez. Saf; WorldNetwork'ün `_`-önekli üyelerine bilerek erişir (arkadaş sınıf).

const KEY_FLAG := "expropriate"
const KEY_TAKEN := "taken"


## `add_road` op sözlüğü + kamulaştırma bayrağı.
static func road_op(net: WorldNetwork, points: PackedVector2Array, road_class: StringName, width_m: float,
		saved_taken: Variant = null) -> Dictionary:
	var width := width_m if width_m > 0.0 else net.rules.width_of(road_class)
	var op := {"op": "add_road", "pts_cm": NetworkDelta.encode_points(points), "class": String(road_class),
			"width_dm": int(round(width * 10.0)), KEY_FLAG: true}
	if saved_taken != null:
		op[KEY_TAKEN] = (saved_taken as Array).duplicate()
	return op


static func is_flagged(op: Dictionary) -> bool:
	return bool(op.get(KEY_FLAG, false))


## Şu an kamulaştırmalı ya da (keep_parcels açıkken) yıkım işlemi yenileniyor mu? Yıkım da havuzlu kurar: birleşen
## yüzün parselleri kimlikleriyle taşınır, baştan parsellenmez (alınmış parseller dönmez, yeni parsel doğmaz).
static func active(net: WorldNetwork) -> bool:
	return net._journal != null and (net._journal.expropriating or (net.rules.keep_parcels_on_delta \
			and str(net._journal.op.get("op", "")) == "remove_edge"))


## Alınacak parseller (artan kimlik): parsel çokgenine çizginin uzaklığı <= yarı genişlik + pay. `width_m` op'taki gibi
## desimetreye yuvarlanır (önizleme ve uygulama aynı sayıyı görür). Ağa dokunmaz.
static func taken_parcels(net: WorldNetwork, pts: PackedVector2Array, width_m: float) -> PackedInt64Array:
	var reach := float(roundi(width_m * 10.0)) * 0.05 + net.rules.expropriation_margin_m
	var found := {}
	for i in range(pts.size() - 1):
		var a := pts[i]
		var b := pts[i + 1]
		var box := Rect2(a, Vector2.ZERO).expand(b).grow(reach)
		for pid in net._parcel_grid.query_rect(box):
			if not found.has(pid) and NetworkGeometry.segment_polygon_distance(a, b,
					(net.parcels[pid] as WorldParcel).outline) <= reach:
				found[pid] = true
	var out := PackedInt64Array(found.keys())
	out.sort()
	return out


## Op uygulanmadan önce (WorldNetwork._op_add_road): alınan kümeyi hesaplar, günlüğe ve op'a yazar. Kayıttan yeniden
## oynatmada op'ta `taken` varsa yeniden hesaplananla AYNI olmalı (aksi halde ağa dokunmadan hata: `network_mismatch`).
## Dönüş: hata metni ya da "".
static func begin(net: WorldNetwork, op: Dictionary, journal: NetworkOpJournal) -> String:
	if not is_flagged(op):
		return ""
	if journal == null or not net.rules.keep_parcels_on_delta:
		return "kamulaştırma kayıtlı işlem ve keep_parcels kuralı gerektirir"
	var taken := taken_parcels(net, NetworkDelta.decode_points(op.get("pts_cm", [])),
			float(op.get("width_dm", 100)) * 0.1)
	if op.has(KEY_TAKEN):
		var saved := PackedInt64Array()
		for id: Variant in op[KEY_TAKEN]:
			saved.append(int(id))
		saved.sort()
		if saved != taken:
			return "network_mismatch: alınan parseller kayıttakinden farklı (%d <> %d)" % [saved.size(), taken.size()]
	else:
		op[KEY_TAKEN] = Array(taken)
	journal.expropriating = true
	journal.taken = taken
	for id in taken:
		journal.taken_set[id] = true
	return ""


## Havuzlu yeniden kurma. `pending`: eşleşmeyen yeni yüzler, `matched`: eşleşen/kurulan blok kimlikleri, `candidates`:
## eşleşme adayı eski blok kimlikleri (eşleşmeyenler STALE). Eski bloklar silinir, yeni bloklar kurulur ve `report`
## doldurulur.
static func rebuild(net: WorldNetwork, pending: Array[Dictionary], matched: Dictionary, report: Dictionary,
		candidates: Array) -> void:
	var j := net._journal
	var stale: Array = []
	for bid: int in candidates:
		if not matched.has(bid) and net.blocks.has(bid):
			stale.append(bid)
	stale.sort()
	var stale_set := {}
	for bid: int in stale:
		stale_set[bid] = true
	_retire_in_kept_blocks(net, j, stale_set, report)
	var pool: Array[WorldParcel] = []
	for bid: int in stale:
		for pid in (net.blocks[bid] as WorldBlock).parcel_ids:
			if not j.taken_set.has(pid):
				pool.append(net.parcels[pid])
	var claimed := {}
	for face in pending:
		var block: WorldBlock = NetworkBlockBuild.build_block(net, face, report)
		matched[block.id] = true
		_claim(net, j, block, face, pool, claimed)
		WorldNetwork.report_add(report, "added_blocks", block.id)
	for bid: int in stale:
		NetworkBlockBuild.remove_block(net, bid, report, claimed)
		WorldNetwork.report_add(report, "removed_blocks", bid)
	(report["removed_parcels"] as Array).sort()


## Alınan ama bloğu KORUNAN (eşleşen) parselleri tek tek emekliye ayırır (çıkmaz sokak yanı gibi).
static func _retire_in_kept_blocks(net: WorldNetwork, j: NetworkOpJournal, stale_set: Dictionary,
		report: Dictionary) -> void:
	for pid in j.taken:
		var parcel: WorldParcel = net.parcels.get(pid, null)
		if parcel == null or stale_set.has(parcel.block_id):
			continue
		var block: WorldBlock = net.blocks[parcel.block_id]
		j.on_block_parcels(block)
		j.on_edge_parcels(parcel.frontage_edge, net._edge_parcels.get(parcel.frontage_edge))
		var at := block.parcel_ids.find(pid)
		if at >= 0:
			block.parcel_ids.remove_at(at)
		var list: PackedInt32Array = net._edge_parcels.get(parcel.frontage_edge, PackedInt32Array())
		var in_list := list.find(pid)
		if in_list >= 0:
			list.remove_at(in_list)
			net._edge_parcels[parcel.frontage_edge] = list
		net.parcels.erase(pid)
		net._parcel_grid.remove(pid)
		j.parcels_retired.append(parcel)
		WorldNetwork.report_add(report, "removed_parcels", pid)


## Yeni yüzün içinde merkezi kalan havuz parsellerini bloğa alır (parselli blok olur). Yüz deliklidir ya da hiç parsel
## yoksa blok `NetworkBlockBuild.build_block`un verdiği türde (açık arazi/su/sliver) kalır.
static func _claim(net: WorldNetwork, j: NetworkOpJournal, block: WorldBlock, face: Dictionary,
		pool: Array[WorldParcel], claimed: Dictionary) -> void:
	if pool.is_empty() or bool(face["holed"]) or not block.parcel_ids.is_empty():
		return
	var outline: PackedVector2Array = face["points"]
	var rect := NetworkGeometry.bounds(outline)
	var ids := PackedInt32Array()
	for parcel in pool:
		if not claimed.has(parcel.id) and rect.has_point(parcel.centroid) \
				and NetworkGeometry.point_in_polygon(parcel.centroid, outline):
			ids.append(parcel.id)
	if ids.is_empty():
		return
	var offsets := PackedFloat64Array()
	for eid in block.edge_ids:
		offsets.append((net.edges[eid] as WorldRoadEdge).width * 0.5)
	var inset := NetworkGeometry.inset_polygon(block.outline, offsets)
	block.buildable = inset["points"] if not (inset["points"] as PackedVector2Array).is_empty() else block.outline
	block.area = NetworkGeometry.signed_area(block.buildable)
	block.kind = WorldBlock.KIND_PARCELIZED
	block.parcel_ids = ids
	for pid in ids:
		claimed[pid] = true
		var parcel: WorldParcel = net.parcels[pid]
		j.parcels_moved.append([parcel, parcel.block_id, parcel.frontage_edge])
		# Geri almada yeni blok silinirken taşınan parseller cephe dizininden de düşer: listeyi ÖNCEDEN günlüğe yaz.
		j.on_edge_parcels(parcel.frontage_edge, net._edge_parcels.get(parcel.frontage_edge))
		parcel.block_id = block.id
		if not (block.edge_ids.has(parcel.frontage_edge) and NetworkBlockMatch.frontage_holds(net, parcel)):
			_reassign_frontage(net, block, parcel)


## Cephe kenarı artık bu bloğun sınırında değil ya da bölünmeyle kaydı: en yakın yol kenarı
## (`NetworkBlockBuild.update_matched_block`).
static func _reassign_frontage(net: WorldNetwork, block: WorldBlock, parcel: WorldParcel) -> void:
	var best := -1
	var best_d := INF
	for eid in block.edge_ids:
		var e: WorldRoadEdge = net.edges[eid]
		if not WorldRoadEdge.is_road_class(e.road_class):
			continue
		var d := NetworkGeometry.distance_point_segment(parcel.front_mid, net.node_pos(e.a), net.node_pos(e.b))
		if d < best_d - 1.0e-9:
			best_d = d
			best = eid
	if best >= 0 and best != parcel.frontage_edge:
		NetworkBlockBuild.set_frontage(net, parcel, best)
