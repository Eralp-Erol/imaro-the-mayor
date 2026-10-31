class_name NetworkColumns
extends RefCounted
## WorldNetwork kanonik durum sütunları (hash girdisi; T-011). Kimliğe göre SIRALI, ham bayt (kayan nokta ikili);
## WorldNetwork.state_dict/graph_hash bunları SHA-256 ile özetler. Davranış değişmez; yalnız dosya boyutu için ayrıldı.


static func nodes(net: WorldNetwork) -> PackedByteArray:
	var ids: Array = net.nodes.keys()
	ids.sort()
	var nums := PackedFloat64Array()
	var text := PackedStringArray()
	for nid: int in ids:
		var n: WorldRoadNode = net.nodes[nid]
		nums.append_array(PackedFloat64Array([nid, n.pos.x, n.pos.y]))
		text.append(String(n.kind))
	return nums.to_byte_array() + ",".join(text).to_utf8_buffer()


static func edges(net: WorldNetwork) -> PackedByteArray:
	var ids: Array = net.edges.keys()
	ids.sort()
	var nums := PackedFloat64Array()
	var text := PackedStringArray()
	for eid: int in ids:
		var e: WorldRoadEdge = net.edges[eid]
		nums.append_array(PackedFloat64Array([eid, e.a, e.b, e.width, 1.0 if e.open else 0.0, e.layer]))
		text.append(String(e.road_class))
	return nums.to_byte_array() + ",".join(text).to_utf8_buffer()


static func blocks(net: WorldNetwork) -> PackedByteArray:
	var ids: Array = net.blocks.keys()
	ids.sort()
	var nums := PackedFloat64Array()
	var text := PackedStringArray()
	for bid: int in ids:
		var b: WorldBlock = net.blocks[bid]
		nums.append_array(PackedFloat64Array([bid, b.area, b.parcel_ids.size()]))
		text.append("%s|%s|%s|%s" % [String(b.kind), String(b.region_code), String(b.fabric), b.signature])
	return nums.to_byte_array() + ",".join(text).to_utf8_buffer()


static func parcels(net: WorldNetwork, include_owner: bool) -> PackedByteArray:
	var ids: Array = net.parcels.keys()
	ids.sort()
	var nums := PackedFloat64Array()
	var text := PackedStringArray()
	for pid: int in ids:
		var p: WorldParcel = net.parcels[pid]
		nums.append_array(PackedFloat64Array([pid, p.block_id, p.frontage_edge, p.area, p.front_length, p.detail,
				p.owner_id if include_owner else 0]))
		for v in p.outline:
			nums.append_array(PackedFloat64Array([v.x, v.y]))
		text.append("%s|%s" % [String(p.region_code), String(p.fabric)])
	return nums.to_byte_array() + ",".join(text).to_utf8_buffer()


## `WorldNetwork.graph_hash` önbelleksiz referans hesabı (taban özeti: düğüm + kenar sütunları, hub'lar, tohum).
static func graph_hash_full(net: WorldNetwork) -> String:
	return StateHash.of({"schema": WorldNetwork.SCHEMA_VERSION, "seed": net.net_seed, "nodes_sha": sha(nodes(net)),
			"edges_sha": sha(edges(net)), "hubs": net._hubs_dict()})


static func sha(bytes: PackedByteArray) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(bytes if not bytes.is_empty() else PackedByteArray([0]))
	return ctx.finish().hex_encode()


## Yalnız topoloji: düğüm/kenar çiftleri, sınıf, açıklık, bloğun kenar çevrimleri (koordinat ve parsel ayrıntısı YOK).
static func topology_hash(net: WorldNetwork) -> String:
	var ids: Array = net.nodes.keys()
	ids.sort()
	var parts := PackedStringArray()
	for nid: int in ids:
		parts.append("n%d:%s" % [nid, String((net.nodes[nid] as WorldRoadNode).kind)])
	var eids: Array = net.edges.keys()
	eids.sort()
	for eid: int in eids:
		var e: WorldRoadEdge = net.edges[eid]
		parts.append("e%d:%d-%d:%s:%d" % [eid, e.a, e.b, String(e.road_class), 1 if e.open else 0])
	var bids: Array = net.blocks.keys()
	bids.sort()
	for bid: int in bids:
		var b: WorldBlock = net.blocks[bid]
		var cycle := PackedStringArray()
		for eid in b.edge_ids:
			cycle.append(str(eid))
		parts.append("b%d:%s" % [bid, ",".join(cycle)])
	return StateHash.of({"topology": "\n".join(parts), "hubs": net._hubs_dict()})
