class_name NetworkPlanarizer
extends RefCounted
## Çok çizgili yolu mevcut ağa düzlemsel biçimde işler (T-011; CAN-04): kesişimleri düğüme çevirir, yakın düğümlere
## yapışır (snap), kenarın ortasına değen uçlar için kenarı böler, çakışan (eşdoğrusal) parçaları yinelemez.
## Taban üretimi ve oyuncu yolu AYNI yolu kullanır. Saf; yalnız WorldNetwork'ün ham düzenleme işlevlerini çağırır.

const T_EPS := 1.0e-6


## Dönüş: {"edges": Array[int] (çizilen/yeniden kullanılan kenarlar), "split_edges": Array[int],
## "nodes": Array[int] (zincirdeki düğümler)}.
static func draw(net: WorldNetwork, points: PackedVector2Array, road_class: StringName, width: float,
		layer: int) -> Dictionary:
	var report := {"edges": [], "split_edges": [], "nodes": []}
	if points.size() < 2:
		return report
	var prev := resolve_point(net, points[0], report)
	WorldNetwork.report_add(report, "nodes", prev)
	for k in range(1, points.size()):
		prev = _draw_segment(net, prev, points[k], road_class, width, layer, report)
	return report


## Konuma düğüm bul/üret: yakın düğüme yapış; kenar üzerindeyse kenarı böl; değilse yeni düğüm.
static func resolve_point(net: WorldNetwork, pos: Vector2, report: Dictionary) -> int:
	var snap := net.rules.snap_m
	var near := net.nearest_node_within(pos, snap)
	if near >= 0:
		return near
	var best_edge := -1
	var best_dist := snap
	for eid in net.edge_ids_in_rect(Rect2(pos, Vector2.ZERO).grow(snap)):
		var e: WorldRoadEdge = net.edges[eid]
		if e.road_class == WorldRoadEdge.CLASS_FERRY:
			continue
		var d := NetworkGeometry.distance_point_segment(pos, net.node_pos(e.a), net.node_pos(e.b))
		if d < best_dist:
			best_dist = d
			best_edge = eid
	if best_edge < 0:
		return net.add_node_raw(pos)
	var e2: WorldRoadEdge = net.edges[best_edge]
	var a := net.node_pos(e2.a)
	var b := net.node_pos(e2.b)
	var split_at := a + (b - a) * NetworkGeometry.project_param(pos, a, b)
	return _split(net, best_edge, split_at, report)


static func _split(net: WorldNetwork, edge_id: int, at: Vector2, report: Dictionary) -> int:
	var node_id := net.add_node_raw(at)
	net.split_edge_raw(edge_id, node_id)
	WorldNetwork.report_add(report, "split_edges", edge_id)
	return node_id


static func _draw_segment(net: WorldNetwork, start_id: int, target: Vector2, road_class: StringName, width: float,
		layer: int, report: Dictionary) -> int:
	var target_id := resolve_point(net, target, report)
	if target_id == start_id:
		return start_id
	var p := net.node_pos(start_id)
	var q := net.node_pos(target_id)
	var seg_len := p.distance_to(q)
	var snap := net.rules.snap_m
	var box := Rect2(p, Vector2.ZERO).expand(q).grow(snap)
	# (t, düğüm) çiftleri: segmentin iç noktalarında, mevcut düğümler veya mevcut kenarlarla kesişimler.
	var hits: Array[Vector3] = []   # (t, düğüm kimliği veya -1, kenar kimliği)
	for nid in net.node_ids_in_rect(box):
		if nid == start_id or nid == target_id:
			continue
		var pos := net.node_pos(nid)
		var t := NetworkGeometry.project_param(pos, p, q)
		if t > T_EPS and t < 1.0 - T_EPS and pos.distance_to(p + (q - p) * t) <= snap:
			hits.append(Vector3(t, nid, -1))
	for eid in net.edge_ids_in_rect(box):
		var e: WorldRoadEdge = net.edges[eid]
		if e.road_class == WorldRoadEdge.CLASS_FERRY:
			continue
		if e.a == start_id or e.b == start_id or e.a == target_id or e.b == target_id:
			continue
		var a := net.node_pos(e.a)
		var b := net.node_pos(e.b)
		var params := NetworkGeometry.segment_params(p, q, a, b)
		if is_inf(params.x) or params.x <= T_EPS or params.x >= 1.0 - T_EPS or params.y <= 0.0 or params.y >= 1.0:
			continue
		var cross_at := p + (q - p) * params.x
		# Kenarın veya segmentin uçlarına snap kadar yakın kesişim düğüm sorgusunda (yukarıda) zaten yakalanır.
		if cross_at.distance_to(a) <= snap or cross_at.distance_to(b) <= snap:
			continue
		if cross_at.distance_to(p) <= snap or cross_at.distance_to(q) <= snap:
			continue
		hits.append(Vector3(params.x, -1, eid))
	hits.sort_custom(func(l: Vector3, r: Vector3) -> bool: return l.x < r.x or (l.x == r.x and l.y < r.y))
	var chain: Array[int] = [start_id]
	for h in hits:
		var hit_node := int(h.y)
		if hit_node < 0:
			hit_node = _split(net, int(h.z), p + (q - p) * h.x, report)
		if hit_node != chain[chain.size() - 1]:
			chain.append(hit_node)
	if chain[chain.size() - 1] != target_id:
		chain.append(target_id)
	for k in range(chain.size() - 1):
		var a_id := chain[k]
		var b_id := chain[k + 1]
		if net.node_pos(a_id).distance_to(net.node_pos(b_id)) < 0.01:
			continue
		var edge_id := net.add_edge_raw(a_id, b_id, road_class, width, layer)
		if not (report["edges"] as Array).has(edge_id):
			WorldNetwork.report_add(report, "edges", edge_id)
	WorldNetwork.report_add(report, "nodes", target_id)
	return target_id
