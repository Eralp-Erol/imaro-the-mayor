class_name RoadMeshBuilder
extends RefCounted
## Saf render türevi. Şeritler/kavşaklar chunk sınırına ve arazi üçgenlerine kırpılır:
## bilineer height_at ile gerçek düz arazi üçgeni farkı yolu zemine gömemez.
## Aynı TerrainMeshBuilder köşegen kuralı, stride=1 (playable varsayılanı).


static func build(net: WorldNetwork, style: RoadStyle, plan: RoadChunkPlan, key: Vector2i,
		metro: bool = false) -> Dictionary:
	var result := {"vertices": PackedVector3Array(), "normals": PackedVector3Array(),
		"colors": PackedColorArray(), "strips": 0, "junctions": 0}
	if not plan.cells.has(key):
		return result
	var bucket: Dictionary = plan.cells[key]
	var step := float(style.data["metro_step_m"] if metro else style.data["near_step_m"])
	var factor := float(style.data["metro_width_scale"]) if metro else 1.0
	var patches: Dictionary = {}
	for eid: int in bucket["edges"]:
		var edge: WorldRoadEdge = net.edges[eid]
		for nid: int in [edge.a, edge.b]:
			if plan.junctions.has(nid) and not patches.has(nid):
				patches[nid] = _junction(net, style, plan, nid, metro)
	for eid: int in bucket["edges"]:
		var edge: WorldRoadEdge = net.edges[eid]
		var a := net.node_pos(edge.a)
		var b := net.node_pos(edge.b)
		var direction := (b - a).normalized()
		var normal := Vector2(-direction.y, direction.x) * style.width_of(edge, metro) * 0.5
		a += direction * float(plan.trims.get(edge.a, 0.0)) * factor
		b -= direction * float(plan.trims.get(edge.b, 0.0)) * factor
		var count := maxi(1, ceili(a.distance_to(b) / step))
		var before := (result["vertices"] as PackedVector3Array).size()
		for s in count:
			var start := a.lerp(b, float(s) / count)
			var end := a.lerp(b, float(s + 1) / count)
			var pieces: Array[PackedVector2Array] = [PackedVector2Array(
				[start + normal, start - normal, end - normal, end + normal])]
			# Dar açılı kavşakta hull şeridin ucunu aşabilir; ortak düzlemde çift yüzey bırakma.
			for nid: int in [edge.a, edge.b]:
				if not patches.has(nid):
					continue
				var remaining: Array[PackedVector2Array] = []
				for piece in pieces:
					remaining.append_array(Geometry2D.clip_polygons(piece, patches[nid]))
				pieces = remaining
			for piece in pieces:
				_emit(piece, style.color_of(edge), net.world, style, plan.rect(key), result)
		if (result["vertices"] as PackedVector3Array).size() > before:
			result["strips"] += 1
	for nid: int in bucket["nodes"]:
		var dominant: WorldRoadEdge = net.edges[(plan.junctions[nid] as Array)[0]]
		for eid: int in plan.junctions[nid]:
			var edge: WorldRoadEdge = net.edges[eid]
			if WorldRoadEdge.rank(edge.road_class) > WorldRoadEdge.rank(dominant.road_class):
				dominant = edge
		_emit(_junction(net, style, plan, nid, metro), style.color_of(dominant),
				net.world, style, plan.rect(key), result)
		result["junctions"] += 1
	return result


static func _junction(net: WorldNetwork, style: RoadStyle, plan: RoadChunkPlan, nid: int,
		metro: bool) -> PackedVector2Array:
	var points := PackedVector2Array()
	var center := net.node_pos(nid)
	var factor := float(style.data["metro_width_scale"]) if metro else 1.0
	for eid: int in plan.junctions[nid]:
		var edge: WorldRoadEdge = net.edges[eid]
		var direction := (net.node_pos(edge.other(nid)) - center).normalized()
		var normal := Vector2(-direction.y, direction.x) * style.width_of(edge, metro) * 0.5
		var end := center + direction * float(plan.trims[nid]) * factor
		points.append(end + normal)
		points.append(end - normal)
	var hull := Geometry2D.convex_hull(points)
	if hull.size() > 3:
		hull.resize(hull.size() - 1) # convex_hull ilk köşeyi sonda tekrarlar.
	return hull


static func _emit(polygon: PackedVector2Array, color: Color, world: WorldData, style: RoadStyle,
		chunk: Rect2, result: Dictionary) -> void:
	var box := PackedVector2Array([chunk.position, Vector2(chunk.end.x, chunk.position.y),
		chunk.end, Vector2(chunk.position.x, chunk.end.y)])
	for clipped: PackedVector2Array in Geometry2D.intersect_polygons(polygon, box):
		var bounds := Rect2(clipped[0], Vector2.ZERO)
		for p in clipped:
			bounds = bounds.expand(p)
		var first := Vector2i(((bounds.position - world.origin) / world.cell_size).floor())
		var last := Vector2i(((bounds.end - world.origin) / world.cell_size).floor())
		for z in range(maxi(0, first.y), mini(world.height - 2, last.y) + 1):
			for x in range(maxi(0, first.x), mini(world.width - 2, last.x) + 1):
				var p00 := world.cell_to_world(x, z)
				var p10 := p00 + Vector2(world.cell_size, 0.0)
				var p01 := p00 + Vector2(0.0, world.cell_size)
				var p11 := p00 + Vector2.ONE * world.cell_size
				var index := z * world.width + x
				var h := world.heights
				var main := TerrainMeshBuilder.uses_main_diagonal(h[index], h[index + 1],
						h[index + world.width], h[index + world.width + 1], world.cell_size)
				var triangles := [PackedVector2Array([p00, p10, p11]), PackedVector2Array([p00, p11, p01])] \
						if main else [PackedVector2Array([p00, p10, p01]), PackedVector2Array([p10, p11, p01])]
				for triangle: PackedVector2Array in triangles:
					for part: PackedVector2Array in Geometry2D.intersect_polygons(clipped, triangle):
						_append(part, color, world, float(style.data["surface_offset_m"]), chunk.position, result)


static func _append(polygon: PackedVector2Array, color: Color, world: WorldData, offset: float,
		origin: Vector2, result: Dictionary) -> void:
	if Geometry2D.is_polygon_clockwise(polygon):
		polygon.reverse()
	var indices := Geometry2D.triangulate_polygon(polygon)
	var vertices: PackedVector3Array = result["vertices"]
	var normals: PackedVector3Array = result["normals"]
	var colors: PackedColorArray = result["colors"]
	for i in range(0, indices.size(), 3):
		var points: Array[Vector3] = []
		for j in 3:
			var p := polygon[indices[i + j]]
			points.append(Vector3(p.x - origin.x, terrain_height(world, p) + offset, p.y - origin.y))
		var normal := (points[2] - points[0]).cross(points[1] - points[0]).normalized()
		if normal.length_squared() < 0.5:
			continue
		for p in points:
			vertices.append(p)
			normals.append(normal)
			colors.append(color)
	result["vertices"] = vertices
	result["normals"] = normals
	result["colors"] = colors


## Bilineer sorgu yerine görünür terrain üçgeninin barycentrik yüksekliği.
static func terrain_height(world: WorldData, p: Vector2) -> float:
	var grid := (p - world.origin) / world.cell_size
	var x := clampi(floori(grid.x), 0, world.width - 2)
	var z := clampi(floori(grid.y), 0, world.height - 2)
	var tx := clampf(grid.x - x, 0.0, 1.0)
	var tz := clampf(grid.y - z, 0.0, 1.0)
	var index := z * world.width + x
	var h00 := world.heights[index]
	var h10 := world.heights[index + 1]
	var h01 := world.heights[index + world.width]
	var h11 := world.heights[index + world.width + 1]
	if TerrainMeshBuilder.uses_main_diagonal(h00, h10, h01, h11, world.cell_size):
		return h00 + tx * (h10 - h00) + tz * (h11 - h10) if tx >= tz \
				else h00 + tz * (h01 - h00) + tx * (h11 - h01)
	return h00 + tx * (h10 - h00) + tz * (h01 - h00) if tx + tz <= 1.0 \
			else h11 + (1.0 - tz) * (h10 - h11) + (1.0 - tx) * (h01 - h11)
