class_name NetworkLocalRefresh
extends RefCounted
## YEREL blok yenilemesi (T-042 adım 1): bir delta işleminden sonra yalnız KOMŞULUĞU değişen düğümlerden geçen yüzleri
## yeniden çıkarır (`refresh_blocks` tüm ağı tarar: gerçek Ismeral'da ~300 ms). Sonuç tam yenilemeyle AYNI bloklar,
## türler ve parsellerdir (kimlik atama sırası farklı olabilir; kimlikler hash'e girmez, ADR-0005 Ek E).
##
## Koşul (çağıran denetler): ağ ferry dışı kenarlarla TEK bileşen, işlemden önce de öyleydi. Böylece "deliği olan yüz"
## (`holed`) hiç yoktur ve dış yüz tektir. Aksi halde WorldNetwork tam yenilemeye düşer.
##
## Yüz etkilenir ⇔ çevrimi komşuluğu değişen bir düğümden geçer ya da silinen/özelliği değişen bir kenar içerir.
## Saf; WorldNetwork'ün `_`-önekli üyelerine bilerek erişir (arkadaş sınıf).


static func refresh(net: WorldNetwork, j: NetworkOpJournal) -> Dictionary:
	var report := {"added_blocks": [], "removed_blocks": [], "added_parcels": [], "removed_parcels": []}
	var touched := j.touched_nodes()
	var seeds := PackedInt32Array()
	var seen := {}
	for nid: int in touched:
		if not net.adjacency.has(nid):
			continue
		for eid in net.adjacency[nid]:
			if not seen.has(eid):
				seen[eid] = true
				seeds.append(eid)
	for eid: int in j.changed_edge_ids:
		if net.edges.has(eid) and not seen.has(eid):
			seen[eid] = true
			seeds.append(eid)
	seeds.sort()
	var affected := _affected_blocks(net, j, touched)
	var matched := {}
	var faces := NetworkBlocks.extract_local(net, seeds)
	var pending := NetworkBlockMatch.match_faces(net, faces, matched, affected)
	if NetworkExpropriation.active(net):  # tam yenilemeyle AYNI havuzlu yeniden kurma işlevi (T-042b)
		NetworkExpropriation.rebuild(net, pending, matched, report, affected.keys())
		return report
	for face in pending:
		var block: WorldBlock = net._build_block(face, report)
		matched[block.id] = true
		WorldNetwork.report_add(report, "added_blocks", block.id)
	var stale: Array = affected.keys()
	stale.sort()
	for old_id: int in stale:
		if not matched.has(old_id):
			net._remove_block(old_id, report)
			WorldNetwork.report_add(report, "removed_blocks", old_id)
	return report


## Çevrimi dokunulan düğümlerden geçen ya da silinen/değişen kenar içeren mevcut bloklar (kimlik -> true).
static func _affected_blocks(net: WorldNetwork, j: NetworkOpJournal, touched: Dictionary) -> Dictionary:
	var out := {}
	for nid: int in touched:
		for bid in net._block_grid.query_rect(Rect2(touched[nid], Vector2.ZERO).grow(1.0)):
			if out.has(bid):
				continue
			var block: WorldBlock = net.blocks[bid]
			for eid in block.edge_ids:
				var e: WorldRoadEdge = net.edges.get(eid, null)
				if e == null or j.changed_edge_ids.has(eid) or touched.has(e.a) or touched.has(e.b):
					out[bid] = true
					break
	return out
