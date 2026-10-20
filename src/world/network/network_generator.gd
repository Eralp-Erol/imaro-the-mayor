class_name NetworkGenerator
extends RefCounted
## T0 iskelet ağ üreteci v0 (T-011; WLD-01/03/05, CAN-04 tabanı). `data/world/<id>/network.json` kontrol verisi +
## WorldData + tohum → mühürlü taban WorldNetwork (yollar, raylar, feribot, bloklar, parseller). Bina YOK
## (T-005/T-004).
##
## Koordinat gömme yok: her şey bölge çapalarından, T0 sahalarından (sites) ve WorldData'dan (kıyı, eğim) türer.
## Topoloji tohumdan BAĞIMSIZDIR; tohum yalnız konum sapmasını ve parsel genişliği çeşitlemesini (ayrıntı) belirler.
## Saflık: Node/Time/OS/global rastgelelik yok; her akış NetworkRules.stream_seed ile bağımsız tohumlanır.
##
## Sıra: (1) doku ızgaraları (T0 saha çıkıntısı önce) → (2) tarla yolları → (3) bölge bağlantıları (A*) → (4) ray →
## (5) feribot → (6) bağlantısız parçaları bağla → (7) mühürle (bloklar + parseller).

const ROAD := &"road"


static func generate(world: WorldData, control: Dictionary, world_seed: int) -> WorldNetwork:
	var rules := NetworkRules.from_control(world, control)
	var net := WorldNetwork.create(world, rules, world_seed)
	var layout_seed := int(control.get("layout_seed", 0))
	var router := NetworkRouter.new(world, control.get("routing", {}), rules.footprints, rules.max_segment_m)
	var fabric_nodes := {}
	var jitter := {}
	_build_lattices(net, world_seed, layout_seed, fabric_nodes, jitter)
	_build_field_roads(net, control, world_seed, layout_seed, fabric_nodes, jitter)
	_mark_port(net, world, fabric_nodes)
	_build_links(net, control, router, fabric_nodes)
	_build_rail(net, control, router, fabric_nodes)
	_build_ferries(net, control, router, fabric_nodes)
	_connect_components(net, control, router)
	_apply_jitter(net, jitter)
	net.seal_base()
	return net


# --- 1) doku ızgaraları ---

static func _build_lattices(net: WorldNetwork, world_seed: int, layout_seed: int, fabric_nodes: Dictionary,
		jitter: Dictionary) -> void:
	var built: Array = []
	for fp in net.rules.footprints:
		var excludes: Array = []
		for other: NetworkFootprint in built:
			excludes.append({"fp": other, "inflate": 120.0})
		var info := NetworkLattice.build(net, fp, fp.lattice, excludes, world_seed, layout_seed,
				WorldRoadEdge.CLASS_LOCAL)
		built.append(fp)
		fabric_nodes[fp.id] = info["nodes"]
		_collect_jitter(info, jitter)
		if int(info["hub"]) >= 0:
			net.hubs[fp.id] = int(info["hub"])
		else:
			push_warning("NetworkGenerator: %s için ızgara boş (kontrol verisi/dünya uyuşmuyor)" % fp.id)


# --- 2) tarla yolları (kırsal ızgara) ---

static func _build_field_roads(net: WorldNetwork, control: Dictionary, world_seed: int, layout_seed: int,
		fabric_nodes: Dictionary, jitter: Dictionary) -> void:
	for entry: Dictionary in control.get("field_roads", []):
		var region := net.world.region_by_code(StringName(str(entry["region"])))
		if region == null:
			continue
		var fp := NetworkFootprint.new()
		fp.id = StringName("field_" + String(region.code))
		fp.region_code = region.code
		fp.template = NetworkRules.TEMPLATE_RURAL
		fp.center = region.anchor
		fp.rotation_rad = deg_to_rad(region.rotation_deg)
		fp.radii = region.radius * float(entry.get("region_norm", 0.95))
		var excludes: Array = []
		for urban in net.rules.footprints:
			excludes.append({"fp": urban, "inflate": float(entry.get("exclude_pad_m", 450.0))})
		var spacing := float(entry.get("spacing_m", 850.0))
		var cfg := {"block_m": [spacing, spacing], "angle_deg": entry.get("angle_deg", "auto"),
				"jitter_m": entry.get("jitter_m", 0.0), "max_slope_deg": entry.get("max_slope_deg", 6.0),
				"shore_margin_m": entry.get("shore_margin_m", 200.0), "collector_every": [0, 0], "omit_local_p": 0.0}
		var info := NetworkLattice.build(net, fp, cfg, excludes, world_seed, layout_seed,
				StringName(str(entry.get("class", "field"))))
		fabric_nodes[fp.id] = info["nodes"]
		_collect_jitter(info, jitter)


static func _collect_jitter(info: Dictionary, jitter: Dictionary) -> void:
	var ids: PackedInt32Array = info["nodes"]
	var offsets: PackedVector2Array = info["jitter"]
	for k in ids.size():
		jitter[ids[k]] = offsets[k]


## Tohumlu konum sapması son geçişte uygulanır (topoloji tohumdan bağımsız kalsın): yalnız tüm komşuları da ızgara
## düğümü olan (kesişim/yapışma/bağlantı düğümü komşusu olmayan) düğümler oynar; böylece düzlemsellik bozulmaz.
static func _apply_jitter(net: WorldNetwork, jitter: Dictionary) -> void:
	var ids: Array = jitter.keys()
	ids.sort()
	var moves := {}
	for nid: int in ids:
		var free := true
		for eid in net.adjacency[nid]:
			var e: WorldRoadEdge = net.edges[eid]
			if e.mode() != &"road" or not jitter.has(e.other(nid)):
				free = false
				break
		if free:
			moves[nid] = net.node_pos(nid) + jitter[nid]
	for nid: int in moves:
		net.move_node_raw(nid, moves[nid])


## T0 liman düğümü: liman çıkıntısı ızgarasında T0 liman sahası işaretine en yakın düğüm (WLD-03: ana karada).
static func _mark_port(net: WorldNetwork, world: WorldData, fabric_nodes: Dictionary) -> void:
	if world.port_site == null:
		return
	for fp in net.rules.footprints:
		if fp.shape != NetworkFootprint.SHAPE_CAPSULE or not fabric_nodes.has(fp.id):
			continue
		var node_id := _nearest_of(net, fabric_nodes[fp.id], world.port_site.position)
		if node_id >= 0:
			(net.nodes[node_id] as WorldRoadNode).kind = WorldRoadNode.KIND_PORT
			net.hubs[&"port"] = node_id
			return


# --- 3) bölge/saha bağlantıları ---

static func _build_links(net: WorldNetwork, control: Dictionary, router: NetworkRouter,
		fabric_nodes: Dictionary) -> void:
	for link: Dictionary in control.get("links", []):
		var a_id := StringName(str(link["from"]))
		var b_id := StringName(str(link["to"]))
		if not net.hubs.has(a_id) or not net.hubs.has(b_id):
			push_warning("NetworkGenerator: bağlantı %s atlandı (hub yok)" % str(link.get("id", "?")))
			continue
		var cls := StringName(str(link.get("class", "arterial")))
		var exit_a := _nearest_of(net, fabric_nodes[a_id], net.node_pos(int(net.hubs[b_id])))
		var exit_b := _nearest_of(net, fabric_nodes[b_id], net.node_pos(int(net.hubs[a_id])))
		_upgrade_spine(net, int(net.hubs[a_id]), exit_a, cls)
		_upgrade_spine(net, int(net.hubs[b_id]), exit_b, cls)
		var profile := NetworkRouter.PROFILE_COAST if str(link.get("style", "")) == "coast" else NetworkRouter.PROFILE_ROAD
		var path := router.route(net.node_pos(exit_a), net.node_pos(exit_b), profile)
		if path.is_empty():
			push_warning("NetworkGenerator: bağlantı %s için güzergâh bulunamadı" % str(link.get("id", "?")))
			continue
		net.author_polyline(path, cls)


## Doku içinde merkezden çıkış düğümüne giden yolu bağlantı sınıfına yükseltir (hiyerarşi: omurga).
static func _upgrade_spine(net: WorldNetwork, hub: int, exit_node: int, cls: StringName) -> void:
	if hub < 0 or exit_node < 0 or hub == exit_node:
		return
	# Omurga mevcut toplayıcı hatlarını tercih eder (merdiven yerine düz hatlar).
	var spine := net.shortest_path(hub, exit_node, WorldNetwork.MODE_ROAD, {WorldRoadEdge.CLASS_COLLECTOR: 0.55,
			WorldRoadEdge.CLASS_ARTERIAL: 0.55})
	if not bool(spine["found"]):
		return
	var nodes_on: PackedInt32Array = spine["nodes"]
	for k in range(nodes_on.size() - 1):
		net.add_edge_raw(nodes_on[k], nodes_on[k + 1], cls, net.rules.width_of(cls))


# --- 4) ray ---

static func _build_rail(net: WorldNetwork, control: Dictionary, router: NetworkRouter,
		fabric_nodes: Dictionary) -> void:
	var lines: Array = control.get("rail", [])
	var stations := _rail_stations(net, lines, fabric_nodes)
	for line: Dictionary in lines:
		var a_id := StringName(str(line["from"]))
		var b_id := StringName(str(line["to"]))
		if not stations.has(a_id) or not stations.has(b_id):
			push_warning("NetworkGenerator: ray %s atlandı (hub yok)" % str(line.get("id", "?")))
			continue
		var end_a: int = stations[a_id]
		var end_b: int = stations[b_id]
		var path := router.route(net.node_pos(end_a), net.node_pos(end_b), NetworkRouter.PROFILE_RAIL)
		if path.is_empty():
			push_warning("NetworkGenerator: ray %s için güzergâh bulunamadı" % str(line.get("id", "?")))
			continue
		net.author_polyline(path, WorldRoadEdge.CLASS_RAIL)
		for end_id in [end_a, end_b]:
			var node := net.nodes[end_id] as WorldRoadNode
			if node.kind == WorldRoadNode.KIND_JUNCTION:
				node.kind = WorldRoadNode.KIND_STATION


## Doku başına TEK istasyon düğümü: "port" = liman düğümü; aksi halde dokunun, o dokuya bağlanan tüm hatların diğer
## uçlarının ağırlık merkezine en yakın düğümü. Böylece hatlar aynı istasyonda buluşur (tek ray ağı).
static func _rail_stations(net: WorldNetwork, lines: Array, fabric_nodes: Dictionary) -> Dictionary:
	var sums := {}
	var counts := {}
	for line: Dictionary in lines:
		var a_id := StringName(str(line["from"]))
		var b_id := StringName(str(line["to"]))
		if not net.hubs.has(a_id) or not net.hubs.has(b_id):
			continue
		for pair in [[a_id, b_id], [b_id, a_id]]:
			var id: StringName = pair[0]
			sums[id] = sums.get(id, Vector2.ZERO) + net.node_pos(int(net.hubs[pair[1]]))
			counts[id] = int(counts.get(id, 0)) + 1
	var stations := {}
	for id: StringName in sums:
		if id == &"port":
			stations[id] = int(net.hubs[&"port"])
		else:
			stations[id] = _nearest_of(net, fabric_nodes[id], (sums[id] as Vector2) / float(counts[id]))
	return stations


# --- 5) feribot ---

static func _build_ferries(net: WorldNetwork, control: Dictionary, router: NetworkRouter,
		fabric_nodes: Dictionary) -> void:
	for ferry: Dictionary in control.get("ferries", []):
		var a_id := StringName(str(ferry["from"]))
		var b_id := StringName(str(ferry["to"]))
		if not net.hubs.has(a_id) or not net.hubs.has(b_id):
			push_warning("NetworkGenerator: feribot %s atlandı (hub yok)" % str(ferry.get("id", "?")))
			continue
		var from_pos := net.node_pos(int(net.hubs[a_id]))
		var to_pos := net.node_pos(int(net.hubs[b_id]))
		var inset := float(ferry.get("pier_inset_m", 35.0))
		var pier_a := _shore_point(net.world, from_pos, to_pos, inset)
		var pier_b := _shore_point(net.world, to_pos, from_pos, inset)
		if pier_a == Vector2.INF or pier_b == Vector2.INF:
			push_warning("NetworkGenerator: feribot %s için kıyı bulunamadı" % str(ferry.get("id", "?")))
			continue
		var node_a := net.add_node_raw(pier_a, WorldRoadNode.KIND_PIER)
		var node_b := net.add_node_raw(pier_b, WorldRoadNode.KIND_PIER)
		var access := StringName(str(ferry.get("access_class", "collector")))
		for pair in [[node_a, a_id], [node_b, b_id]]:
			var pier_id: int = pair[0]
			var land_id := _nearest_of(net, fabric_nodes[pair[1]], net.node_pos(pier_id))
			var path := router.route(net.node_pos(pier_id), net.node_pos(land_id), NetworkRouter.PROFILE_ROAD)
			if path.is_empty():
				path = PackedVector2Array([net.node_pos(pier_id), net.node_pos(land_id)])
			net.author_polyline(path, access)
		net.add_edge_raw(node_a, node_b, WorldRoadEdge.CLASS_FERRY, 0.0)


## `from_pos`tan `to_pos`a doğru yürü: suya ilk girişten `inset` m geride (kıyıda, karada) nokta; yoksa Vector2.INF.
static func _shore_point(world: WorldData, from_pos: Vector2, to_pos: Vector2, inset: float) -> Vector2:
	var dir := (to_pos - from_pos).normalized()
	var total := from_pos.distance_to(to_pos)
	var step := 10.0
	var d := step
	while d < total:
		var p := from_pos + dir * d
		if world.is_water(p.x, p.y):
			return from_pos + dir * maxf(d - step - inset, 0.0)
		d += step
	return Vector2.INF


# --- 6) bağlantısız parçaları ana ağa bağla ---

static func _connect_components(net: WorldNetwork, control: Dictionary, router: NetworkRouter) -> void:
	var connectors: Dictionary = control.get("connectors", {})
	if not bool(connectors.get("enabled", true)):
		return
	var cls := StringName(str(connectors.get("class", "collector")))
	for _round in 80:
		var comps := net.components(WorldNetwork.MODE_ROAD)
		if comps.size() <= 1:
			return
		var main_index := 0
		for k in comps.size():
			if comps[k].size() > comps[main_index].size():
				main_index = k
		var linked := false
		for k in comps.size():
			if k == main_index:
				continue
			var pair := _closest_pair(net, comps[k], main_index)
			if pair.x < 0:
				continue
			var path := router.route(net.node_pos(pair.x), net.node_pos(pair.y), NetworkRouter.PROFILE_ROAD)
			if path.is_empty():
				path = PackedVector2Array([net.node_pos(pair.x), net.node_pos(pair.y)])
				push_warning("NetworkGenerator: bağlantısız parça için doğrudan bağlantı (güzergâh yok)")
			net.author_polyline(path, cls)
			linked = true
			break  # bileşen indeksleri değişti; yeniden hesapla
		if not linked:
			return


## `comp`taki düğümlerden ana bileşendeki en yakın düğüme (x = comp düğümü, y = ana düğüm); yoksa (-1, -1).
static func _closest_pair(net: WorldNetwork, comp: PackedInt32Array, main_index: int) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d := INF
	for nid in comp:
		var pos := net.node_pos(nid)
		var radius := 400.0
		while radius <= 40000.0:
			var found := -1
			var found_d := INF
			for other in net.node_ids_in_rect(Rect2(pos, Vector2.ZERO).grow(radius)):
				if net.component_of(other, WorldNetwork.MODE_ROAD) != main_index:
					continue
				var d := net.node_pos(other).distance_to(pos)
				if d < found_d or (d == found_d and other < found):
					found_d = d
					found = other
			if found >= 0 and found_d <= radius:
				if found_d < best_d or (found_d == best_d and nid < best.x):
					best_d = found_d
					best = Vector2i(nid, found)
				break
			radius *= 2.0
	return best


# --- yardımcılar ---

## `nodes` listesi içinde `target`a en yakın düğüm (eşitlikte küçük kimlik); boşsa -1.
static func _nearest_of(net: WorldNetwork, node_ids: PackedInt32Array, target: Vector2) -> int:
	var best := -1
	var best_d := INF
	for nid in node_ids:
		var d := net.node_pos(nid).distance_to(target)
		if d < best_d or (d == best_d and nid < best):
			best_d = d
			best = nid
	return best
