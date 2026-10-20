class_name SettlementGroups
extends RefCounted
## Sokak cephesi grupları (T-005): aynı yol kenarına, aynı yanda cephe veren parseller kenar boyunca sıralı.
## Üreteç (komşu kuralı, bitişik nizam) ve testler aynı sıralamayı kullanır. Saf.


## Dönüş: [{"edge": int, "side": int, "parcels": PackedInt32Array (cephe boyunca sıralı)}, ...] kenar/yan sıralı.
static func build(net: WorldNetwork, parcel_ids: PackedInt32Array) -> Array[Dictionary]:
	var by_key := {}
	for pid in parcel_ids:
		var p: WorldParcel = net.parcels[pid]
		if p.frontage_edge < 0 or not net.edges.has(p.frontage_edge):
			continue
		var e: WorldRoadEdge = net.edges[p.frontage_edge]
		var a := net.node_pos(e.a)
		var dir := (net.node_pos(e.b) - a).normalized()
		var side := 1 if float(dir.cross(p.centroid - p.front_mid)) > 0.0 else 0
		var key := p.frontage_edge * 2 + side
		var along := float((p.front_mid - a).dot(dir))
		if not by_key.has(key):
			by_key[key] = []
		(by_key[key] as Array).append(Vector2(along, pid))
	var keys: Array = by_key.keys()
	keys.sort()
	var out: Array[Dictionary] = []
	for key: int in keys:
		var items: Array = by_key[key]
		items.sort_custom(func(l: Vector2, r: Vector2) -> bool: return l.x < r.x or (l.x == r.x and l.y < r.y))
		var ids := PackedInt32Array()
		for it: Vector2 in items:
			ids.append(int(it.y))
		out.append({"edge": key >> 1, "side": key & 1, "parcels": ids})
	return out
