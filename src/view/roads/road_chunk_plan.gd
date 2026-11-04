class_name RoadChunkPlan
extends RefCounted
## Salt okunur ağdan mekânsal indeks. Uzun kenarlar geçtiği HER chunk'ta kırpılır.
## T-042: değişiklik öncesi/sonrası edge_keys birleşimi + uç junction_keys -> rebuild_chunks.
## Katman taban/delta kaynağıdır, köprü yüksekliği değildir. Kapalı yollar fiziksel olarak kalır.

var cells: Dictionary = {}
var edge_keys: Dictionary = {}
var junction_keys: Dictionary = {}
## Düğüm -> en büyük kol kırpması (m). Kol başına değerler `arm_trims`te (RoadJunction).
var trims: Dictionary = {}
## Düğüm -> {kenar kimliği: Vector2(sağ, sol) kırpma (m, tam genişlik)}.
var arm_trims: Dictionary = {}
var junctions: Dictionary = {}
var cell_m: float
var origin: Vector2
var strip_count: int = 0
## Kenar kimliği -> [a, b] uç düğümleri (değişim tabanlı güncellemede eski uçları bulmak için).
var edge_nodes: Dictionary = {}


static func build(net: WorldNetwork, style: RoadStyle) -> RoadChunkPlan:
	var plan := RoadChunkPlan.new()
	plan.cell_m = float(style.data["chunk_m"])
	plan.origin = net.world.origin
	var ids := net.edges.keys()
	ids.sort()
	var incident: Dictionary = {}
	for eid: int in ids:
		var edge: WorldRoadEdge = net.edges[eid]
		if not is_strip(edge):
			continue
		plan._add_edge(net, style, eid)
		for nid: int in [edge.a, edge.b]:
			if not incident.has(nid):
				incident[nid] = []
			(incident[nid] as Array).append(eid)
	var node_ids := incident.keys()
	node_ids.sort()
	for nid: int in node_ids:
		plan._add_node(net, style, nid, incident[nid])
	return plan


## Çizilen şerit mi (yol kipi, sıfır olmayan uzunluk)? Kapalı yol da şerittir (fiziksel yüzey kalır).
static func is_strip(edge: WorldRoadEdge) -> bool:
	return edge.mode() == WorldNetwork.MODE_ROAD and edge.length > 0.001


## T-042 adım 3 · DEĞİŞİM TABANLI güncelleme: `build` ile BİREBİR aynı planı (hücre içerikleri sıralı, edge_keys,
## junction_keys, trims) yalnız değişen kenar/düğümler için üretir. Tam `build` gerçek ağda (~7000 kenar) ~350 ms
## (ölçüm: dev Mac, başsız); bu yol O(değişim). `changes`: `WorldNetwork.changes_since` kayıtları; sonuç ağın GÜNCEL
## durumuna göredir (kayıtların sırası/çakışması önemsizdir: her kenar/düğüm son durumuyla yeniden değerlendirilir).
## Döndürür: dokunulan hücre anahtarları (sıralı, tekil).
func apply_changes(net: WorldNetwork, style: RoadStyle, changes: Array[NetworkChange]) -> Array[Vector2i]:
	var edge_ids: Dictionary = {}
	var node_ids: Dictionary = {}
	for change in changes:
		for list: PackedInt32Array in [change.edges_added, change.edges_removed, change.edges_changed]:
			for eid in list:
				edge_ids[eid] = true
		for list: PackedInt32Array in [change.nodes_added, change.nodes_removed]:
			for nid in list:
				node_ids[nid] = true
	var touched: Dictionary = {}
	for eid: int in edge_ids:
		for nid: int in _remove_edge(eid, touched):
			node_ids[nid] = true
	for eid: int in edge_ids:
		var edge: WorldRoadEdge = net.edges.get(eid)
		if edge != null and is_strip(edge):
			_add_edge(net, style, eid, touched)
			node_ids[edge.a] = true
			node_ids[edge.b] = true
	for nid: int in node_ids:
		_remove_node(nid, touched)
		var connected := _strip_edges_at(net, nid)
		if not connected.is_empty():
			_add_node(net, style, nid, connected, touched)
	var out: Array[Vector2i] = []
	for key: Vector2i in touched:
		out.append(key)
		if cells.has(key):
			for kind: String in ["edges", "nodes"]:
				(cells[key][kind] as Array).sort()
	out.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x < b.x or (a.x == b.x and a.y < b.y))
	strip_count = edge_keys.size()
	return out


func keys() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for key: Vector2i in cells:
		result.append(key)
	result.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x < b.x or (a.x == b.x and a.y < b.y))
	return result


func rect(key: Vector2i) -> Rect2:
	return Rect2(origin + Vector2(key) * cell_m, Vector2.ONE * cell_m)


func _add_edge(net: WorldNetwork, style: RoadStyle, eid: int, touched: Dictionary = {}) -> void:
	var edge: WorldRoadEdge = net.edges[eid]
	strip_count += 1
	var half := style.width_of(edge) * 0.5
	var a := net.node_pos(edge.a)
	var b := net.node_pos(edge.b)
	edge_keys[eid] = _insert(Rect2(a, Vector2.ZERO).expand(b).grow(half), "edges", eid, touched)
	edge_nodes[eid] = [edge.a, edge.b]


func _add_node(net: WorldNetwork, style: RoadStyle, nid: int, connected: Array, touched: Dictionary = {}) -> void:
	var trim := 0.0
	var per_arm: Dictionary = {}
	if connected.size() > 1:
		# Kol başına, açısal komşusuyla yan çizgi kesişimine kadar (RoadJunction): dar açılı tek çift tüm kolları şişirmez.
		per_arm = RoadJunction.arm_trims(net, style, nid, connected)
		for t: Vector2 in per_arm.values():
			trim = maxf(trim, maxf(t.x, t.y))
	trims[nid] = trim
	if connected.size() < 2:
		return
	arm_trims[nid] = per_arm
	junctions[nid] = connected
	var radius := trim
	for eid: int in connected:
		radius = maxf(radius, trim + style.width_of(net.edges[eid]) * 0.5)
	junction_keys[nid] = _insert(Rect2(net.node_pos(nid), Vector2.ZERO).grow(radius), "nodes", nid, touched)


## Düğümün şerit kenarları (sıralı kimlik): `build`in `incident` listesiyle aynı küme.
func _strip_edges_at(net: WorldNetwork, nid: int) -> Array:
	var out: Array = []
	if not net.adjacency.has(nid):
		return out
	for eid: int in net.adjacency[nid]:
		if is_strip(net.edges[eid]):
			out.append(eid)
	out.sort()
	return out


## Kenarın kayıtlarını siler; eski uç düğümlerini döndürür (kavşakları yeniden hesaplanmalı).
func _remove_edge(eid: int, touched: Dictionary) -> Array:
	var ends: Array = edge_nodes.get(eid, [])
	for key: Vector2i in edge_keys.get(eid, []):
		_erase_from_cell(key, "edges", eid, touched)
	edge_keys.erase(eid)
	edge_nodes.erase(eid)
	return ends


func _remove_node(nid: int, touched: Dictionary) -> void:
	for key: Vector2i in junction_keys.get(nid, []):
		_erase_from_cell(key, "nodes", nid, touched)
	junction_keys.erase(nid)
	junctions.erase(nid)
	arm_trims.erase(nid)
	trims.erase(nid)


func _erase_from_cell(key: Vector2i, kind: String, id: int, touched: Dictionary) -> void:
	touched[key] = true
	if not cells.has(key):
		return
	(cells[key][kind] as Array).erase(id)
	if (cells[key]["edges"] as Array).is_empty() and (cells[key]["nodes"] as Array).is_empty():
		cells.erase(key)


func _insert(bounds: Rect2, kind: String, id: int, touched: Dictionary = {}) -> Array[Vector2i]:
	var first := Vector2i(((bounds.position - origin) / cell_m).floor())
	var last := Vector2i(((bounds.end - origin) / cell_m).floor())
	var result: Array[Vector2i] = []
	for x in range(first.x, last.x + 1):
		for z in range(first.y, last.y + 1):
			var key := Vector2i(x, z)
			if not cells.has(key):
				cells[key] = {"edges": [], "nodes": []}
			(cells[key][kind] as Array).append(id)
			result.append(key)
			touched[key] = true
	return result
