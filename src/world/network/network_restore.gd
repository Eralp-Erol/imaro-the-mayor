class_name NetworkRestore
extends RefCounted
## WorldNetwork iç tablolarını `NetworkOpJournal.undo` için ters yönde düzenleyen yardımcılar (T-042 adım 1).
## WorldNetwork'ün
## `_`-önekli üyelerine bilerek erişir (aynı paket içi "arkadaş" sınıf; dosya satır sınırı nedeniyle ayrı dosyada).
## Hiçbiri günlük yazmaz, `graph_version`'ı artırmaz (çağıran bir kez artırır). Saf.


static func counters(net: WorldNetwork) -> Dictionary:
	return {"node": net._next_node_id, "edge": net._next_edge_id, "block": net._next_block_id,
			"parcel": net._next_parcel_id}


static func set_counters(net: WorldNetwork, c: Dictionary) -> void:
	net._next_node_id = int(c["node"])
	net._next_edge_id = int(c["edge"])
	net._next_block_id = int(c["block"])
	net._next_parcel_id = int(c["parcel"])


static func drop_node(net: WorldNetwork, id: int) -> void:
	net.nodes.erase(id)
	net.adjacency.erase(id)
	net._node_grid.remove(id)


static func reinstate_node(net: WorldNetwork, id: int, pos: Vector2, kind: StringName) -> void:
	var node := WorldRoadNode.new()
	node.id = id
	node.pos = pos
	node.kind = kind
	net.nodes[id] = node
	net.adjacency[id] = PackedInt32Array()
	net._node_grid.insert(id, Rect2(pos, Vector2.ZERO))


static func drop_edge(net: WorldNetwork, id: int) -> void:
	net.edges.erase(id)
	net._edge_grid.remove(id)


## Anlık görüntüden kenarı kurar ya da var olan kenarın alanlarını eski değerlerine döndürür.
static func reinstate_edge(net: WorldNetwork, snap: Dictionary) -> void:
	var id: int = snap["id"]
	var e: WorldRoadEdge = net.edges.get(id, null)
	if e == null:
		e = WorldRoadEdge.new()
		e.id = id
		net.edges[id] = e
	e.a = snap["a"]
	e.b = snap["b"]
	e.road_class = snap["road_class"]
	e.width = snap["width"]
	e.open = snap["open"]
	e.layer = snap["layer"]
	e.length = snap["length"]
	net._edge_grid.insert(id, net._edge_rect(e))


## İşlemin ürettiği bloğu (ve parsellerini) siler; `_edge_parcels` günlükten ayrıca geri yazılır.
static func drop_block(net: WorldNetwork, block_id: int) -> void:
	net._remove_block(block_id, {"removed_parcels": []})


static func reinstate_block(net: WorldNetwork, block: WorldBlock) -> void:
	net.blocks[block.id] = block
	net._block_by_sig[block.signature] = block.id
	net._block_grid.insert(block.id, NetworkGeometry.bounds(block.outline))


static func reinstate_parcel(net: WorldNetwork, parcel: WorldParcel) -> void:
	net.parcels[parcel.id] = parcel
	net._parcel_grid.insert(parcel.id, NetworkGeometry.bounds(parcel.outline))


static func restore_block_geometry(net: WorldNetwork, block: WorldBlock, outline: PackedVector2Array,
		edge_ids: PackedInt32Array, signature: String) -> void:
	block.outline = outline
	block.edge_ids = edge_ids
	if block.signature != signature:
		if int(net._block_by_sig.get(block.signature, -1)) == block.id:
			net._block_by_sig.erase(block.signature)
		block.signature = signature
		net._block_by_sig[signature] = block.id
	net._block_grid.insert(block.id, NetworkGeometry.bounds(outline))


static func restore_edge_parcels(net: WorldNetwork, edge_id: int, before: Variant) -> void:
	if before == null:
		net._edge_parcels.erase(edge_id)
	else:
		net._edge_parcels[edge_id] = before
