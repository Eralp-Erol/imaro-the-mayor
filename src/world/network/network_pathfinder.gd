class_name NetworkPathfinder
extends RefCounted
## WorldNetwork üzerinde en kısa yol (A*, Öklid sezgisi). Kara/ray/feribot AYRI kiplerdir; kapalı kenar geçilmez.
## Eşitlikte düğüm kimliği küçük olan önce çıkar: aynı ağ + aynı girdi → aynı yol (deterministik). Saf.

## Dönüş: {"found": bool, "nodes": PackedInt32Array, "edges": PackedInt32Array, "length": float}.
## `class_scale` (isteğe bağlı): sınıf adı -> maliyet çarpanı (0 < çarpan ≤ 1; üretecin omurga seçimi için). Dönen
## `length`
## her zaman gerçek uzunluktur.
static func shortest_path(net: WorldNetwork, from_id: int, to_id: int, mode: StringName,
		class_scale: Dictionary = {}) -> Dictionary:
	var result := {"found": false, "nodes": PackedInt32Array(), "edges": PackedInt32Array(), "length": 0.0}
	if not net.nodes.has(from_id) or not net.nodes.has(to_id):
		return result
	if from_id == to_id:
		result["found"] = true
		result["nodes"] = PackedInt32Array([from_id])
		return result
	var goal: Vector2 = (net.nodes[to_id] as WorldRoadNode).pos
	var min_scale := 1.0
	for scale in class_scale.values():
		min_scale = minf(min_scale, float(scale))
	var g := {from_id: 0.0}
	var came_node := {}
	var came_edge := {}
	var closed := {}
	var heap_keys := PackedFloat64Array()
	var heap_vals := PackedInt32Array()
	heap_push(heap_keys, heap_vals, ((net.nodes[from_id] as WorldRoadNode).pos).distance_to(goal) * min_scale, from_id)
	while not heap_vals.is_empty():
		var cur := heap_pop(heap_keys, heap_vals)
		if closed.has(cur):
			continue
		closed[cur] = true
		if cur == to_id:
			break
		var cur_g: float = g[cur]
		for eid in net.adjacency[cur]:
			var e: WorldRoadEdge = net.edges[eid]
			if not e.open or e.mode() != mode:
				continue
			var nxt := e.other(cur)
			if closed.has(nxt):
				continue
			var ng := cur_g + e.length * float(class_scale.get(e.road_class, 1.0))
			if not g.has(nxt) or ng < float(g[nxt]) - 1.0e-9:
				g[nxt] = ng
				came_node[nxt] = cur
				came_edge[nxt] = eid
				heap_push(heap_keys, heap_vals, ng + (net.nodes[nxt] as WorldRoadNode).pos.distance_to(goal) * min_scale, nxt)
	if not closed.has(to_id):
		return result
	var path_nodes: Array[int] = []
	var path_edges: Array[int] = []
	var at := to_id
	while at != from_id:
		path_nodes.append(at)
		path_edges.append(int(came_edge[at]))
		at = int(came_node[at])
	path_nodes.append(from_id)
	path_nodes.reverse()
	path_edges.reverse()
	result["found"] = true
	result["nodes"] = PackedInt32Array(path_nodes)
	result["edges"] = PackedInt32Array(path_edges)
	var real := 0.0
	for eid in path_edges:
		real += (net.edges[eid] as WorldRoadEdge).length
	result["length"] = real
	return result


static func _less(keys: PackedFloat64Array, vals: PackedInt32Array, i: int, j: int) -> bool:
	if keys[i] != keys[j]:
		return keys[i] < keys[j]
	return vals[i] < vals[j]


## İkili yığın (en küçük anahtar; eşitlikte küçük değer) — `NetworkRouter` da kullanır.
static func heap_push(keys: PackedFloat64Array, vals: PackedInt32Array, key: float, val: int) -> void:
	keys.append(key)
	vals.append(val)
	var i := keys.size() - 1
	while i > 0:
		var parent := (i - 1) >> 1
		if not _less(keys, vals, i, parent):
			break
		_swap(keys, vals, i, parent)
		i = parent


static func heap_pop(keys: PackedFloat64Array, vals: PackedInt32Array) -> int:
	var top := vals[0]
	var last := keys.size() - 1
	keys[0] = keys[last]
	vals[0] = vals[last]
	keys.resize(last)
	vals.resize(last)
	var i := 0
	var n := last
	while true:
		var l := 2 * i + 1
		var r := l + 1
		var smallest := i
		if l < n and _less(keys, vals, l, smallest):
			smallest = l
		if r < n and _less(keys, vals, r, smallest):
			smallest = r
		if smallest == i:
			break
		_swap(keys, vals, i, smallest)
		i = smallest
	return top


static func _swap(keys: PackedFloat64Array, vals: PackedInt32Array, i: int, j: int) -> void:
	var tk := keys[i]
	keys[i] = keys[j]
	keys[j] = tk
	var tv := vals[i]
	vals[i] = vals[j]
	vals[j] = tv
