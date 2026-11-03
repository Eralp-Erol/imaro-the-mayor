class_name NetworkLandReuse
extends RefCounted
## T-066 / D-018: emekli parsel geometrisini kaynak journal'dan klonlar; eski binaları/sahipliği geri getirmez.
## Yeni kimlik üretmez. Yalnız parcel_revision değişir; yol işçisinin düğüm/kenar verisi sabit kalır.


static func available(net: WorldNetwork, source_op: int, parcel_ids: PackedInt64Array) -> Dictionary:
	var plan := _plan(net, source_op, parcel_ids)
	return {"ok": plan["ok"], "error": plan["error"], "parcel_ids": Array(parcel_ids) if plan["ok"] else []}


static func archive_rows(net: WorldNetwork, source_op: int, parcel_ids: PackedInt64Array) -> Array:
	var archives := _archives(net, source_op)
	var rows: Array = []
	for id in parcel_ids:
		if not archives.has(id):
			continue
		var parcel: WorldParcel = archives[id]
		rows.append({"id": id, "area_m2": roundi(parcel.area), "region_code": String(parcel.region_code),
			"center_x_cm": roundi(parcel.centroid.x * 100.0), "center_z_cm": roundi(parcel.centroid.y * 100.0)})
	return rows


static func apply(net: WorldNetwork, op: Dictionary, journal: NetworkOpJournal, report: Dictionary) -> void:
	var source: Variant = op.get("source_op", null)
	var raw: Variant = op.get("parcel_ids", null)
	if journal == null or not (source is int or source is float) or float(source) != float(int(source)) \
			or not raw is Array:
		report["ok"] = false
		report["error"] = "arsa geri açma işlemi biçimsiz"
		return
	var ids := PackedInt64Array()
	for id: Variant in raw:
		if not (id is int or id is float) or float(id) != float(int(id)):
			report["ok"] = false
			report["error"] = "arsa kimliği tamsayı olmalı"
			return
		ids.append(int(id))
	var plan := _plan(net, int(source), ids)
	if not bool(plan["ok"]):
		report["ok"] = false
		report["error"] = plan["error"]
		return
	for row: Dictionary in plan["rows"]:
		var archive: WorldParcel = row["parcel"]
		var block: WorldBlock = row["block"]
		var parcel := _clone(archive)
		parcel.block_id = block.id
		parcel.frontage_edge = row["frontage"]
		journal.on_block_parcels(block)
		if not journal.land_blocks_before.has(block.id):
			journal.land_blocks_before[block.id] = {"kind": block.kind,
				"buildable": block.buildable.duplicate(), "area": block.area}
		if block.buildable.is_empty():
			block.buildable = _buildable(net, block)
			block.area = NetworkGeometry.signed_area(block.buildable)
		block.kind = WorldBlock.KIND_PARCELIZED
		block.parcel_ids.append(parcel.id)
		block.parcel_ids.sort()
		journal.on_edge_parcels(parcel.frontage_edge, net._edge_parcels.get(parcel.frontage_edge))
		var front: PackedInt32Array = net._edge_parcels.get(parcel.frontage_edge, PackedInt32Array())
		front.append(parcel.id)
		front.sort()
		net._edge_parcels[parcel.frontage_edge] = front
		NetworkRestore.reinstate_parcel(net, parcel)
		journal.reactivated_parcels.append(parcel.id)
		(report["added_parcels"] as Array).append(parcel.id)


static func _plan(net: WorldNetwork, source_op: int, ids: PackedInt64Array) -> Dictionary:
	var out := {"ok": false, "error": "", "rows": []}
	if not net.sealed or not net.rules.keep_parcels_on_delta:
		out["error"] = "arsa geri açma mühürlü ve parsel koruyan ağ gerektirir"
		return out
	var archives := _archives(net, source_op)
	if archives.is_empty() or ids.is_empty():
		out["error"] = "kamulaştırma arşivi ya da arsa seçimi yok"
		return out
	var previous := 0
	for id in ids:
		if id <= previous or not archives.has(id) or net.parcels.has(id) or _latest_source(net, id) != source_op:
			out["error"] = "arsa kimliği sırasız, yinelenmiş, açık ya da kaynakla uyuşmuyor"
			return out
		previous = id
		var parcel: WorldParcel = archives[id]
		if _covered(net, parcel):
			out["error"] = "arsa hâlâ bir yol tarafından kaplanıyor"
			return out
		var block := _block_for(net, parcel.centroid)
		var frontage := -1 if block == null else _frontage_for(net, block, parcel)
		if block == null or frontage < 0:
			out["error"] = "arsa için geçerli blok ya da yol cephesi yok"
			return out
		(out["rows"] as Array).append({"parcel": parcel, "block": block, "frontage": frontage})
	out["ok"] = true
	return out


static func _archives(net: WorldNetwork, source_op: int) -> Dictionary:
	var out := {}
	if source_op < 0 or source_op >= net._undo_stack.size():
		return out
	var source: NetworkOpJournal = net._undo_stack[source_op]
	if not source.expropriating:
		return out
	for collection in [source.parcels_removed, source.parcels_retired]:
		for parcel: WorldParcel in collection:
			if source.taken_set.has(parcel.id):
				out[parcel.id] = parcel
	return out


static func _latest_source(net: WorldNetwork, parcel_id: int) -> int:
	for i in range(net._undo_stack.size() - 1, -1, -1):
		if (net._undo_stack[i] as NetworkOpJournal).taken_set.has(parcel_id):
			return i
	return -1


static func _covered(net: WorldNetwork, parcel: WorldParcel) -> bool:
	for id: int in net.edges:
		var edge: WorldRoadEdge = net.edges[id]
		if edge.layer != WorldRoadEdge.LAYER_DELTA or edge.mode() == WorldNetwork.MODE_FERRY:
			continue
		if NetworkGeometry.segment_polygon_distance(net.node_pos(edge.a), net.node_pos(edge.b), parcel.outline) \
				<= edge.width * 0.5 + net.rules.expropriation_margin_m:
			return true
	return false


static func _block_for(net: WorldNetwork, center: Vector2) -> WorldBlock:
	var best: WorldBlock = null
	var best_area := INF
	var ids: Array = net.blocks.keys()
	ids.sort()
	for id: int in ids:
		var block: WorldBlock = net.blocks[id]
		var area := absf(NetworkGeometry.signed_area(block.outline))
		if area < best_area and NetworkGeometry.point_in_polygon(center, block.outline) \
				and NetworkGeometry.point_in_polygon(center, _buildable(net, block)):
			best = block
			best_area = area
	return best


static func _buildable(net: WorldNetwork, block: WorldBlock) -> PackedVector2Array:
	if not block.buildable.is_empty():
		return block.buildable
	var offsets := PackedFloat64Array()
	for id in block.edge_ids:
		offsets.append((net.edges[id] as WorldRoadEdge).width * 0.5)
	var inset := NetworkGeometry.inset_polygon(block.outline, offsets)
	return inset["points"] if not (inset["points"] as PackedVector2Array).is_empty() else block.outline


static func _frontage_for(net: WorldNetwork, block: WorldBlock, parcel: WorldParcel) -> int:
	var best := -1
	var distance := INF
	var ids := block.edge_ids.duplicate()
	ids.sort()
	for id in ids:
		var edge: WorldRoadEdge = net.edges[id]
		if not WorldRoadEdge.is_road_class(edge.road_class):
			continue
		var d := NetworkGeometry.distance_point_segment(parcel.front_mid, net.node_pos(edge.a), net.node_pos(edge.b))
		if d <= edge.width * 0.5 + NetworkInvariants.FRONTAGE_TOLERANCE_M and d < distance:
			best = id
			distance = d
	return best


static func _clone(source: WorldParcel) -> WorldParcel:
	var parcel := WorldParcel.new()
	parcel.id = source.id
	parcel.block_id = source.block_id
	parcel.outline = source.outline.duplicate()
	parcel.centroid = source.centroid
	parcel.area = source.area
	parcel.frontage_edge = source.frontage_edge
	parcel.front_length = source.front_length
	parcel.front_mid = source.front_mid
	parcel.region_code = source.region_code
	parcel.fabric = source.fabric
	parcel.detail = source.detail
	return parcel
