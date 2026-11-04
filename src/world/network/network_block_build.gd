class_name NetworkBlockBuild
extends RefCounted
## Blok/parsel türetme bölümü (`WorldNetwork`ten taşındı, ADR-0005 Ek J takip f; DAVRANIŞ DEĞİŞMEDİ): yüzleri bloklara
## eşler/yeniden üretir (`refresh`), bloğu parsellere böler (`build_block`, `parcelize_block`, `make_parcel`), bloğu
## siler (`remove_block`), cephe kenarını atar (`set_frontage`) ve kıyı/çıkmaz-sokak denetimlerini yapar.
## `WorldNetwork.refresh_blocks()` bu sınıfa ince sarmalayıcıdır; `NetworkBlockMatch`, `NetworkExpropriation`,
## `NetworkLocalRefresh` ve `NetworkRestore` doğrudan buraya çağırır.
##
## Parsel kimliği yalnız `parcelize_block` -> `make_parcel` içinde, MÜHÜRDEN ÖNCE doğar: mühürlü ve
## `keep_parcels_on_delta` açık dünyada `build_block` hiçbir yüzü parsellemez (ADR-0005 Ek J kural 1).
## Saf; WorldNetwork'ün `_`-önekli üyelerine bilerek erişir (arkadaş sınıf, `NetworkExpropriation` gibi).

## Parsel kara denetimi: blok merkezi kıyıdan bu kadar (blok çapı + pay) uzaktaysa tek tek denetim atlanır.
const LAND_FAST_PATH_MARGIN_M := 60.0
## Parsel bölge kodu bloktan alınır (blok bu boyuttan küçükse); aksi halde parsel merkezine göre.
const BLOCK_REGION_MAX_M := 400.0
## Ofseti geçersiz bir yüz bu alandan büyükse sliver değil parselsiz açık arazi (kama) sayılır.
const OPEN_WEDGE_MIN_AREA_M2 := 20000.0


## Yüzleri yeniden türetir; geometri imzası aynı olan bloklar (ve parselleri, mülkiyet yuvaları dahil) KORUNUR,
## değişenler yeniden üretilir. Dönüş: {added_blocks, removed_blocks, added_parcels, removed_parcels}.
static func refresh(net: WorldNetwork) -> Dictionary:
	var report := {"added_blocks": [], "removed_blocks": [], "added_parcels": [], "removed_parcels": []}
	var matched := {}
	var candidates := {}
	for old_id: int in net.blocks:
		candidates[old_id] = true
	var pending := NetworkBlockMatch.match_faces(net, NetworkBlocks.extract(net), matched, candidates)
	if NetworkExpropriation.active(net):  # tam ve yerel yenileme AYNI havuzlu yeniden kurma işlevini kullanır
		NetworkExpropriation.rebuild(net, pending, matched, report, net.blocks.keys())
		pending.clear()
	for face in pending:
		var block := build_block(net, face, report)
		matched[block.id] = true
		WorldNetwork.report_add(report, "added_blocks", block.id)
	for old_id: int in net.blocks.keys():
		if not matched.has(old_id):
			remove_block(net, old_id, report)
			WorldNetwork.report_add(report, "removed_blocks", old_id)
	net._blocks_single_comp = NetworkBlocks.component_count(net) == 1
	return report


static func update_matched_block(net: WorldNetwork, block: WorldBlock, face: Dictionary) -> void:
	var new_edges: PackedInt32Array = face["edge_ids"]
	var new_sig: String = face["signature"]
	if net._journal != null \
			and (new_edges != block.edge_ids or block.outline != face["points"] or new_sig != block.signature):
		var front := {}
		for pid in block.parcel_ids:
			front[pid] = (net.parcels[pid] as WorldParcel).frontage_edge
		net._journal.on_block_updated(block, front)
	block.outline = face["points"]
	if new_sig != block.signature:
		# Köşe anahtarıyla eşleşme (kenar bölünmesi imzayı kaydırdı): blok ve parselleri korunur, imza yenisine bağlanır.
		if int(net._block_by_sig.get(block.signature, -1)) == block.id:
			net._block_by_sig.erase(block.signature)
		block.signature = new_sig
		net._block_by_sig[new_sig] = block.id
	if new_edges == block.edge_ids:
		return
	block.edge_ids = new_edges
	for pid in block.parcel_ids:
		var parcel: WorldParcel = net.parcels[pid]
		if new_edges.has(parcel.frontage_edge) and NetworkBlockMatch.frontage_holds(net, parcel):
			continue  # Cephe kenarı hâlâ blok sınırında ve parsele bakıyor: parselin kendi cephesi korunur.
		var best := -1
		var best_d := INF
		for eid in new_edges:
			var e: WorldRoadEdge = net.edges[eid]
			if not WorldRoadEdge.is_road_class(e.road_class):
				continue
			var d := NetworkGeometry.distance_point_segment(parcel.front_mid, net.node_pos(e.a), net.node_pos(e.b))
			if d < best_d - 1.0e-9:
				best_d = d
				best = eid
		if best >= 0 and best != parcel.frontage_edge:
			set_frontage(net, parcel, best)


static func build_block(net: WorldNetwork, face: Dictionary, report: Dictionary) -> WorldBlock:
	var block := WorldBlock.new()
	block.id = net._next_block_id
	net._next_block_id += 1
	block.outline = face["points"]
	block.edge_ids = face["edge_ids"]
	block.signature = face["signature"]
	var center := NetworkGeometry.centroid(block.outline)
	block.region_code = net.rules.region_code_at(net.world, center)
	block.fabric = net.rules.template_at(center)
	var face_area := float(face["area"])
	if bool(face["holed"]):
		block.kind = WorldBlock.KIND_HOLED
	elif face_area > float(net.rules.template_params(block.fabric).get("max_block_area_m2",
			net.rules.max_block_area_m2)):
		block.kind = WorldBlock.KIND_OPEN
	elif net.world.is_water(center.x, center.y):
		block.kind = WorldBlock.KIND_UNBUILDABLE
	elif net.rules.keep_parcels_on_delta and net.sealed:
		# v0: mühür sonrası yeni yüz (yol çevirdi/yıkım birleştirdi) PARSELLENMEZ; parseller kimlikle taşınır (T-042b).
		block.kind = WorldBlock.KIND_OPEN
	else:
		parcelize_block(net, block, face, report)
	net.blocks[block.id] = block
	if net._journal != null:
		net._journal.on_block_added(block.id)
	net._block_by_sig[block.signature] = block.id
	net._block_grid.insert(block.id, NetworkGeometry.bounds(block.outline))
	return block


static func parcelize_block(net: WorldNetwork, block: WorldBlock, face: Dictionary, report: Dictionary) -> void:
	var offsets := PackedFloat64Array()
	for eid in block.edge_ids:
		offsets.append((net.edges[eid] as WorldRoadEdge).width * 0.5)
	var inset := NetworkGeometry.inset_polygon(block.outline, offsets)
	if (inset["points"] as PackedVector2Array).is_empty():
		# Ofset geçersiz: küçükse sliver; büyük düzensiz kama (paralel yollar arası) parselsiz açık arazi sayılır.
		block.kind = WorldBlock.KIND_OPEN if float(face["area"]) > OPEN_WEDGE_MIN_AREA_M2 else WorldBlock.KIND_SLIVER
		return
	block.buildable = inset["points"]
	block.area = NetworkGeometry.signed_area(block.buildable)
	if block.area < net.rules.min_block_area_m2:
		block.kind = WorldBlock.KIND_SLIVER
		return
	var tags := PackedInt32Array()
	for original: int in inset["edge_of"]:
		var tag := -1
		if original >= 0:
			var e: WorldRoadEdge = net.edges[block.edge_ids[original]]
			if WorldRoadEdge.is_road_class(e.road_class):
				tag = e.id
		tags.append(tag)
	var rng := RandomNumberGenerator.new()
	rng.seed = NetworkRules.stream_seed(net.net_seed, "parcels:" + block.signature)
	var params := net.rules.template_params(block.fabric)
	var lots := NetworkParcelizer.subdivide(block.buildable, tags, params, rng)
	var check_land := needs_land_check(net, block)
	var block_rect := NetworkGeometry.bounds(block.outline)
	var spurs: PackedInt32Array = face["spurs"]
	block.kind = WorldBlock.KIND_PARCELIZED
	for lot in lots:
		var outline: PackedVector2Array = lot["outline"]
		if check_land and not outline_on_land(net, outline):
			continue
		if not spurs.is_empty() and touches_spur(net, outline, spurs):
			continue
		var parcel := make_parcel(net, block, block_rect, lot, rng)
		WorldNetwork.report_add(report, "added_parcels", parcel.id)


static func make_parcel(net: WorldNetwork, block: WorldBlock, block_rect: Rect2, lot: Dictionary,
		rng: RandomNumberGenerator) -> WorldParcel:
	var parcel := WorldParcel.new()
	parcel.id = net._next_parcel_id
	net._next_parcel_id += 1
	parcel.block_id = block.id
	parcel.outline = lot["outline"]
	parcel.centroid = NetworkGeometry.average(parcel.outline)
	parcel.area = NetworkGeometry.signed_area(parcel.outline)
	parcel.front_length = float(lot["front_len"])
	parcel.front_mid = lot["front_mid"]
	# Küçük blokta bölge/doku bloktan; büyük (kırsal) blokta parsel merkezine göre (bölge sınırı bloğu kesebilir).
	if block_rect.size.x < BLOCK_REGION_MAX_M and block_rect.size.y < BLOCK_REGION_MAX_M:
		parcel.region_code = block.region_code
		parcel.fabric = block.fabric
	else:
		parcel.region_code = net.rules.region_code_at(net.world, parcel.centroid)
		parcel.fabric = net.rules.template_at(parcel.centroid)
	parcel.detail = rng.randi()
	net.parcels[parcel.id] = parcel
	block.parcel_ids.append(parcel.id)
	net._parcel_grid.insert(parcel.id, NetworkGeometry.bounds(parcel.outline))
	set_frontage(net, parcel, int(lot["frontage"]))
	return parcel


static func set_frontage(net: WorldNetwork, parcel: WorldParcel, edge_id: int) -> void:
	if net._journal != null:
		if parcel.frontage_edge >= 0:
			net._journal.on_edge_parcels(parcel.frontage_edge, net._edge_parcels.get(parcel.frontage_edge))
		net._journal.on_edge_parcels(edge_id, net._edge_parcels.get(edge_id))
	if parcel.frontage_edge >= 0 and net._edge_parcels.has(parcel.frontage_edge):
		var old: PackedInt32Array = net._edge_parcels[parcel.frontage_edge]
		var at := old.find(parcel.id)
		if at >= 0:
			old.remove_at(at)
		net._edge_parcels[parcel.frontage_edge] = old
	parcel.frontage_edge = edge_id
	var list: PackedInt32Array = net._edge_parcels.get(edge_id, PackedInt32Array())
	list.append(parcel.id)
	net._edge_parcels[edge_id] = list


## `keep`: yeni bloğa taşınan (kamulaştırma, T-042b) parsel kimlikleri; silinmez, rapora girmez.
static func remove_block(net: WorldNetwork, block_id: int, report: Dictionary, keep: Dictionary = {}) -> void:
	var block: WorldBlock = net.blocks[block_id]
	if net._journal != null:
		var gone: Array[WorldParcel] = []
		for pid in block.parcel_ids:
			var p: WorldParcel = net.parcels[pid]
			if not keep.has(pid):
				gone.append(p)
				net._journal.on_edge_parcels(p.frontage_edge, net._edge_parcels.get(p.frontage_edge))
		net._journal.on_block_removed(block, gone)
	for pid in block.parcel_ids:
		if keep.has(pid):
			continue
		var parcel: WorldParcel = net.parcels[pid]
		if net._edge_parcels.has(parcel.frontage_edge):
			var list: PackedInt32Array = net._edge_parcels[parcel.frontage_edge]
			var at := list.find(pid)
			if at >= 0:
				list.remove_at(at)
			net._edge_parcels[parcel.frontage_edge] = list
		net.parcels.erase(pid)
		net._parcel_grid.remove(pid)
		WorldNetwork.report_add(report, "removed_parcels", pid)
	if int(net._block_by_sig.get(block.signature, -1)) == block_id:
		net._block_by_sig.erase(block.signature)
	net.blocks.erase(block_id)
	net._block_grid.remove(block_id)


## Blok kıyıya yakınsa parseller tek tek kara denetiminden geçer (hızlı yol: iç bölgedeki bloklar).
static func needs_land_check(net: WorldNetwork, block: WorldBlock) -> bool:
	var rect := NetworkGeometry.bounds(block.outline)
	var center := rect.get_center()
	var idx := net.world.world_to_index(center.x, center.y)
	return float(net.world.shore_distance[idx]) < rect.size.length() * 0.5 + LAND_FAST_PATH_MARGIN_M \
			or net.world.landmass_ids[idx] != WorldData.LANDMASS_MAINLAND


static func outline_on_land(net: WorldNetwork, outline: PackedVector2Array) -> bool:
	for p in outline:
		if net.world.is_water(p.x, p.y):
			return false
	var c := NetworkGeometry.centroid(outline)
	return not net.world.is_water(c.x, c.y)


static func touches_spur(net: WorldNetwork, outline: PackedVector2Array, spurs: PackedInt32Array) -> bool:
	for eid in spurs:
		if not net.edges.has(eid):
			continue
		var e: WorldRoadEdge = net.edges[eid]
		if NetworkGeometry.segment_polygon_distance(net.node_pos(e.a), net.node_pos(e.b), outline) <= e.width * 0.5 + 0.5:
			return true
	return false
