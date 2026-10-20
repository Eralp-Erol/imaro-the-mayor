class_name NetworkBlocks
extends RefCounted
## Yol grafından blok yüzlerini türetir (T-011): düzlemsel grafın yüz yürüyüşü (yarım kenar). Feribot kenarları yüz
## oluşturmaz; ray kenarları yüz sınırıdır (cephe vermez). Saf; yalnız WorldNetwork'ün düğüm/kenar tablolarını okur.
## Yüz yönelimi: iç solda → işaretli alan > 0. En dış yüz negatiftir ve blok olmaz.

const SIGNATURE_DIGITS := 100.0


## Dönüş: pozitif yüzlerin listesi (sıra: yarım kenar kimliği). Her yüz:
## {"points": PackedVector2Array, "edge_ids": PackedInt32Array (i -> i+1 kenarı), "spurs": PackedInt32Array,
##  "area": float, "holed": bool, "signature": String}
static func extract(net: WorldNetwork) -> Array[Dictionary]:
	var order := _rotation_order(net)
	var edge_ids: Array = net.edges.keys()
	edge_ids.sort()
	var visited := {}
	var faces: Array[Dictionary] = []
	var outer_faces: Array[Dictionary] = []
	for eid: int in edge_ids:
		var edge: WorldRoadEdge = net.edges[eid]
		if edge.mode() == &"ferry":
			continue
		for dir in 2:
			var start := eid * 2 + dir
			if visited.has(start):
				continue
			var cycle := _walk(net, order, start, visited)
			var face := _face_from_cycle(net, cycle)
			if face.is_empty():
				continue
			if float(face["area"]) > 0.0:
				faces.append(face)
			else:
				outer_faces.append(face)
	_mark_holes(net, faces, outer_faces)
	for face in faces:
		face["signature"] = _signature(net, face)
	return faces


## Düğüm başına, kenarları (ferry hariç) açıya göre artan sıralı kimlik listesi.
static func _rotation_order(net: WorldNetwork) -> Dictionary:
	var order := {}
	for nid: int in net.nodes.keys():
		var node: WorldRoadNode = net.nodes[nid]
		var ids := PackedInt32Array()
		var angles := PackedFloat64Array()
		for eid in net.adjacency[nid]:
			var e: WorldRoadEdge = net.edges[eid]
			if e.mode() == &"ferry":
				continue
			var other: WorldRoadNode = net.nodes[e.other(nid)]
			var d := other.pos - node.pos
			var angle := atan2(d.y, d.x)
			var at := ids.size()
			ids.append(eid)
			angles.append(angle)
			# Ekleme sıralaması (küçük listeler).
			while at > 0 and (angles[at - 1] > angle or (angles[at - 1] == angle and ids[at - 1] > eid)):
				angles[at] = angles[at - 1]
				ids[at] = ids[at - 1]
				at -= 1
			angles[at] = angle
			ids[at] = eid
		order[nid] = ids
	return order


static func _walk(net: WorldNetwork, order: Dictionary, start: int, visited: Dictionary) -> PackedInt32Array:
	var cycle := PackedInt32Array()
	var cur := start
	var guard := 0
	while guard < 1000000:
		guard += 1
		visited[cur] = true
		cycle.append(cur)
		var eid := cur >> 1
		var edge: WorldRoadEdge = net.edges[eid]
		var to_id := edge.b if (cur & 1) == 0 else edge.a
		var around: PackedInt32Array = order[to_id]
		var k := around.find(eid)
		var next_eid := around[(k - 1 + around.size()) % around.size()]
		var next_edge: WorldRoadEdge = net.edges[next_eid]
		cur = next_eid * 2 + (0 if next_edge.a == to_id else 1)
		if cur == start:
			break
	return cycle


## Yarım kenar çevriminden çokgen: sivri uçlar (aynı kenarın gidiş-dönüşü) ayıklanır; ayıklanan kenarlar `spurs`.
static func _face_from_cycle(net: WorldNetwork, cycle: PackedInt32Array) -> Dictionary:
	var stack := PackedInt32Array()
	var spurs := PackedInt32Array()
	for h in cycle:
		if not stack.is_empty() and (stack[stack.size() - 1] >> 1) == (h >> 1):
			spurs.append(h >> 1)
			stack.resize(stack.size() - 1)
		else:
			stack.append(h)
	# Çevrim başı/sonu da sivri uç oluşturabilir.
	while stack.size() >= 2 and (stack[0] >> 1) == (stack[stack.size() - 1] >> 1):
		spurs.append(stack[0] >> 1)
		stack.remove_at(stack.size() - 1)
		stack.remove_at(0)
	if stack.size() < 3:
		return {}
	var points := PackedVector2Array()
	var edge_ids := PackedInt32Array()
	for h in stack:
		var edge: WorldRoadEdge = net.edges[h >> 1]
		var from_id := edge.a if (h & 1) == 0 else edge.b
		points.append((net.nodes[from_id] as WorldRoadNode).pos)
		edge_ids.append(h >> 1)
	return {"points": points, "edge_ids": edge_ids, "spurs": spurs, "area": NetworkGeometry.signed_area(points),
			"holed": false, "first_node": _from_node(net, stack[0])}


static func _from_node(net: WorldNetwork, half_edge: int) -> int:
	var edge: WorldRoadEdge = net.edges[half_edge >> 1]
	return edge.a if (half_edge & 1) == 0 else edge.b


## Bağlantısız (başka bileşene ait) ağ parçası bir yüzün içindeyse o yüz `holed` olur.
static func _mark_holes(net: WorldNetwork, faces: Array[Dictionary], outer_faces: Array[Dictionary]) -> void:
	if outer_faces.size() <= 1:
		return
	var comp := _components(net)
	for face in faces:
		face["comp"] = int(comp.get(int(face["first_node"]), -1))
	for outer in outer_faces:
		var c := int(comp.get(int(outer["first_node"]), -2))
		var probe: Vector2 = (outer["points"] as PackedVector2Array)[0]
		var parent: Dictionary = {}
		var parent_area := INF
		for face in faces:
			if int(face["comp"]) == c or float(face["area"]) >= parent_area:
				continue
			if NetworkGeometry.bounds(face["points"]).has_point(probe) and \
					NetworkGeometry.point_in_polygon(probe, face["points"]):
				parent = face
				parent_area = float(face["area"])
		if not parent.is_empty():
			parent["holed"] = true


static func _components(net: WorldNetwork) -> Dictionary:
	var comp := {}
	var next_id := 0
	for nid: int in net.nodes.keys():
		if comp.has(nid):
			continue
		comp[nid] = next_id
		var queue: Array[int] = [nid]
		while not queue.is_empty():
			var cur: int = queue.pop_back()
			for eid in net.adjacency[cur]:
				var e: WorldRoadEdge = net.edges[eid]
				if e.mode() == &"ferry":
					continue
				var other := e.other(cur)
				if not comp.has(other):
					comp[other] = next_id
					queue.append(other)
		next_id += 1
	return comp


## Geometri imzası: eşdoğrusal ve aynı sınıf/genişlikteki ardışık kenarlar birleştirilir (kenar bölünmesi imzayı
## değiştirmez), başlangıç en küçük (x, y) köşesine döndürülür; santimetre yuvarlama; MD5 hex.
static func _signature(net: WorldNetwork, face: Dictionary) -> String:
	var pts: PackedVector2Array = face["points"]
	var ids: PackedInt32Array = face["edge_ids"]
	var n := pts.size()
	var keep: Array[int] = []
	for i in n:
		var prev_e: WorldRoadEdge = net.edges[ids[(i + n - 1) % n]]
		var cur_e: WorldRoadEdge = net.edges[ids[i]]
		var d1 := pts[i] - pts[(i + n - 1) % n]
		var d2 := pts[(i + 1) % n] - pts[i]
		var collinear := absf(float(d1.x) * float(d2.y) - float(d1.y) * float(d2.x)) <= 1.0e-4 * d1.length() * d2.length() \
				and float(d1.dot(d2)) > 0.0
		var same_props := prev_e.road_class == cur_e.road_class and absf(prev_e.width - cur_e.width) < 0.01
		if not (collinear and same_props):
			keep.append(i)
	if keep.is_empty():
		keep.append(0)
	var best := 0
	for k in keep.size():
		var a := pts[keep[k]]
		var b := pts[keep[best]]
		if a.x < b.x or (a.x == b.x and a.y < b.y):
			best = k
	var parts := PackedStringArray()
	for off in keep.size():
		var i := keep[(best + off) % keep.size()]
		var e: WorldRoadEdge = net.edges[ids[i]]
		parts.append("%d,%d,%s,%d" % [int(round(pts[i].x * SIGNATURE_DIGITS)), int(round(pts[i].y * SIGNATURE_DIGITS)),
				String(e.road_class), int(round(e.width * 10.0))])
	return (";".join(parts) + ("#H" if face["holed"] else "")).md5_text()
