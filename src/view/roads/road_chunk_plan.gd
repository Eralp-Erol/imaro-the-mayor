class_name RoadChunkPlan
extends RefCounted
## Salt okunur ağdan mekânsal indeks. Uzun kenarlar geçtiği HER chunk'ta kırpılır.
## T-042: değişiklik öncesi/sonrası edge_keys birleşimi + uç junction_keys -> rebuild_chunks.
## Katman taban/delta kaynağıdır, köprü yüksekliği değildir. Kapalı yollar fiziksel olarak kalır.

var cells: Dictionary = {}
var edge_keys: Dictionary = {}
var junction_keys: Dictionary = {}
var trims: Dictionary = {}
var junctions: Dictionary = {}
var cell_m: float
var origin: Vector2
var strip_count: int = 0


static func build(net: WorldNetwork, style: RoadStyle) -> RoadChunkPlan:
	var plan := RoadChunkPlan.new()
	plan.cell_m = float(style.data["chunk_m"])
	plan.origin = net.world.origin
	var ids := net.edges.keys()
	ids.sort()
	var incident: Dictionary = {}
	for eid: int in ids:
		var edge: WorldRoadEdge = net.edges[eid]
		if edge.mode() != WorldNetwork.MODE_ROAD or edge.length <= 0.001:
			continue
		plan.strip_count += 1
		var half := style.width_of(edge) * 0.5
		var a := net.node_pos(edge.a)
		var b := net.node_pos(edge.b)
		plan.edge_keys[eid] = plan._insert(Rect2(a, Vector2.ZERO).expand(b).grow(half), "edges", eid)
		for nid: int in [edge.a, edge.b]:
			if not incident.has(nid):
				incident[nid] = []
			(incident[nid] as Array).append(eid)
	var node_ids := incident.keys()
	node_ids.sort()
	for nid: int in node_ids:
		var connected: Array = incident[nid]
		var trim := 0.0
		if connected.size() > 1:
			for eid: int in connected:
				trim = maxf(trim, style.width_of(net.edges[eid]) * 0.5)
			# Dar açıda birleşme noktasını genişlet: komşu şeritler kavşak dışında üst üste binmesin.
			for i in connected.size():
				var left: WorldRoadEdge = net.edges[connected[i]]
				var a := (net.node_pos(left.other(nid)) - net.node_pos(nid)).normalized()
				for j in range(i + 1, connected.size()):
					var right: WorldRoadEdge = net.edges[connected[j]]
					var b := (net.node_pos(right.other(nid)) - net.node_pos(nid)).normalized()
					var angle := acos(clampf(a.dot(b), -1.0, 1.0))
					var half := maxf(style.width_of(left), style.width_of(right)) * 0.5
					trim = maxf(trim, half / tan(maxf(angle, 0.01) * 0.5))
			for eid: int in connected:
				trim = minf(trim, (net.edges[eid] as WorldRoadEdge).length * 0.45)
		plan.trims[nid] = trim
		if trim <= 0.0:
			continue
		plan.junctions[nid] = connected
		var radius := trim
		for eid: int in connected:
			radius = maxf(radius, trim + style.width_of(net.edges[eid]) * 0.5)
		plan.junction_keys[nid] = plan._insert(Rect2(net.node_pos(nid), Vector2.ZERO).grow(radius), "nodes", nid)
	return plan


func keys() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for key: Vector2i in cells:
		result.append(key)
	result.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x < b.x or (a.x == b.x and a.y < b.y))
	return result


func rect(key: Vector2i) -> Rect2:
	return Rect2(origin + Vector2(key) * cell_m, Vector2.ONE * cell_m)


func _insert(bounds: Rect2, kind: String, id: int) -> Array[Vector2i]:
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
	return result
