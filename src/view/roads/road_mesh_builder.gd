class_name RoadMeshBuilder
extends RefCounted
## Saf render türevi. Şeritler/kavşaklar chunk sınırına ve arazi üçgenlerine kırpılır:
## bilineer height_at ile gerçek düz arazi üçgeni farkı yolu zemine gömemez.
## Aynı TerrainMeshBuilder köşegen kuralı, stride=1 (playable varsayılanı).
##
## Hız (T-048 sonrası): arazi kırpması Geometry2D yerine hücre ızgarası + köşegen doğrusu boyunca
## yarım-düzlem bölmesidir (çokgen başına birkaç doğru, her biri tek tarama); kavşak dolgusu yalnız
## şerit ucu gerçekten hull'a taşıyorsa kırpılır. Yükseklik, çokgenin düştüğü arazi üçgeninin düzleminden
## gelir (TerrainMeshBuilder köşegen kuralı; `terrain_height` ile aynı sonuç, köşe başına arama yok).
## Sonuç geometri aynıdır; yalnız kırpıcının köşe sırası/dilim bölünmesi değişebilir.
## Çıktı dizileri yerinde büyütülür (Dictionary içindeki PackedArray'i her eklemede kopyalamaz).

## Köşe testi toleransı (m): bu kadar taşma/temas "içeride/dışarıda" sayılır.
const EPS_M := 0.001
const _MIN_AREA_M2 := 0.0001
const _DIAGONAL := 0.70710678118654752440

static var _triangle := PackedInt32Array([0, 1, 2])
static var _triangle_clockwise := PackedInt32Array([2, 1, 0])


class Sink:
	extends RefCounted
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	## true: şerit parçası kavşak kırpmasından çıktı, içbükey olabilir -> Geometry2D yoluyla işlenir.
	var concave := false
	var color := Color.WHITE
	var offset := 0.0
	var origin := Vector2.ZERO
	# Geçerli arazi üçgeni düzlemi: h(p) = base + gx*(p.x-anchor.x) + gz*(p.y-anchor.y).
	var anchor := Vector2.ZERO
	var base := 0.0
	var gx := 0.0
	var gz := 0.0


## `patch_cache`: çağıranın aynı toplu işte (ör. rebuild_chunks) paylaştığı kavşak dolgusu önbelleği;
## boş geçilirse yalnız bu çağrı içinde geçerli olur.
static func build(net: WorldNetwork, style: RoadStyle, plan: RoadChunkPlan, key: Vector2i,
		metro: bool = false, patch_cache: Dictionary = {}) -> Dictionary:
	var sink := Sink.new()
	var strips := 0
	var junctions := 0
	if plan.cells.has(key):
		var bucket: Dictionary = plan.cells[key]
		var chunk := plan.rect(key)
		sink.offset = float(style.data["surface_offset_m"])
		sink.origin = chunk.position
		var step := float(style.data["metro_step_m"] if metro else style.data["near_step_m"])
		var factor := float(style.data["metro_width_scale"]) if metro else 1.0
		var patches: Dictionary = {}
		for eid: int in bucket["edges"]:
			var edge: WorldRoadEdge = net.edges[eid]
			for nid: int in [edge.a, edge.b]:
				if plan.junctions.has(nid) and not patches.has(nid):
					patches[nid] = _patch(net, style, plan, nid, metro, patch_cache)
		for eid: int in bucket["edges"]:
			var edge: WorldRoadEdge = net.edges[eid]
			var a := net.node_pos(edge.a)
			var b := net.node_pos(edge.b)
			var direction := (b - a).normalized()
			var normal := Vector2(-direction.y, direction.x) * style.width_of(edge, metro) * 0.5
			var color := style.color_of(edge)
			a += direction * float(plan.trims.get(edge.a, 0.0)) * factor
			b -= direction * float(plan.trims.get(edge.b, 0.0)) * factor
			var patch_a: Array = patches.get(edge.a, [])
			var patch_b: Array = patches.get(edge.b, [])
			# Hull şeridin uç çizgisinin gerisinde kalıyorsa (olağan kavşak) şeritle kesişimi sıfır alandır.
			if not patch_a.is_empty() and _behind(patch_a[0], a, direction):
				patch_a = []
			if not patch_b.is_empty() and _behind(patch_b[0], b, -direction):
				patch_b = []
			var count := maxi(1, ceili(a.distance_to(b) / step))
			var before := sink.vertices.size()
			for s in count:
				var start := a.lerp(b, float(s) / count)
				var end := a.lerp(b, float(s + 1) / count)
				var pieces: Array[PackedVector2Array] = [PackedVector2Array(
					[start + normal, start - normal, end - normal, end + normal])]
				# Dar açılı kavşakta hull şeridin ucunu aşabilir; ortak düzlemde çift yüzey bırakma.
				sink.concave = false
				if not patch_a.is_empty():
					pieces = _minus_patch(pieces, patch_a, sink)
				if not patch_b.is_empty():
					pieces = _minus_patch(pieces, patch_b, sink)
				for piece in pieces:
					_emit(piece, color, net.world, chunk, sink)
			if sink.vertices.size() > before:
				strips += 1
		for nid: int in bucket["nodes"]:
			var dominant: WorldRoadEdge = net.edges[(plan.junctions[nid] as Array)[0]]
			for eid: int in plan.junctions[nid]:
				var edge: WorldRoadEdge = net.edges[eid]
				if WorldRoadEdge.rank(edge.road_class) > WorldRoadEdge.rank(dominant.road_class):
					dominant = edge
			var patch: Array = _patch(net, style, plan, nid, metro, patch_cache)
			sink.concave = false
			_emit(patch[0], style.color_of(dominant), net.world, chunk, sink)
			junctions += 1
	return {"vertices": sink.vertices, "normals": sink.normals, "colors": sink.colors,
		"strips": strips, "junctions": junctions}


## [hull, hull sınırı (EPS_M büyütülmüş)] — sınır, kırpmaya hiç girmeyecek parçaları ayıklar.
static func _patch(net: WorldNetwork, style: RoadStyle, plan: RoadChunkPlan, nid: int, metro: bool,
		cache: Dictionary) -> Array:
	var cache_key := nid * 2 + (1 if metro else 0)
	if cache.has(cache_key):
		return cache[cache_key]
	var hull := _junction(net, style, plan, nid, metro)
	var entry: Array = [hull, _bounds(hull).grow(EPS_M * 10.0)]
	cache[cache_key] = entry
	return entry


## Tüm hull köşeleri, `from` noktasından `toward` yönüne dik çizginin (EPS_M toleranslı) gerisinde mi?
static func _behind(hull: PackedVector2Array, from: Vector2, toward: Vector2) -> bool:
	for v in hull:
		if (v - from).dot(toward) > EPS_M:
			return false
	return true


static func _minus_patch(pieces: Array[PackedVector2Array], patch: Array, sink: Sink) -> Array[PackedVector2Array]:
	var rect: Rect2 = patch[1]
	var remaining: Array[PackedVector2Array] = []
	for piece in pieces:
		if rect.intersects(_bounds(piece)):
			remaining.append_array(Geometry2D.clip_polygons(piece, patch[0]))
			sink.concave = true
		else:
			remaining.append(piece)
	return remaining


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


static func _bounds(polygon: PackedVector2Array) -> Rect2:
	var low := polygon[0]
	var high := low
	for p in polygon:
		low = Vector2(minf(low.x, p.x), minf(low.y, p.y))
		high = Vector2(maxf(high.x, p.x), maxf(high.y, p.y))
	return Rect2(low, high - low)


static func _emit(polygon: PackedVector2Array, color: Color, world: WorldData, chunk: Rect2,
		sink: Sink) -> void:
	if polygon.is_empty():
		return
	sink.color = color
	var bounds := _bounds(polygon)
	if chunk.encloses(bounds):
		_emit_world(polygon, bounds, world, sink)
		return
	var box := PackedVector2Array([chunk.position, Vector2(chunk.end.x, chunk.position.y),
		chunk.end, Vector2(chunk.position.x, chunk.end.y)])
	for clipped: PackedVector2Array in Geometry2D.intersect_polygons(polygon, box):
		_emit_world(clipped, _bounds(clipped), world, sink)


## Dünya ızgarasının dışı atılır (eski davranış: yalnız [0, width-2] hücreleri), içi hücrelere bölünür.
static func _emit_world(polygon: PackedVector2Array, bounds: Rect2, world: WorldData, sink: Sink) -> void:
	var extent := Rect2(world.origin, Vector2(world.width - 1, world.height - 1) * world.cell_size)
	if extent.encloses(bounds):
		_emit_grid(polygon, bounds, world, sink)
		return
	var box := PackedVector2Array([extent.position, Vector2(extent.end.x, extent.position.y),
		extent.end, Vector2(extent.position.x, extent.end.y)])
	for clipped: PackedVector2Array in Geometry2D.intersect_polygons(polygon, box):
		_emit_grid(clipped, _bounds(clipped), world, sink)


static func _emit_grid(polygon: PackedVector2Array, bounds: Rect2, world: WorldData, sink: Sink) -> void:
	var cell := world.cell_size
	var first := Vector2i(((bounds.position - world.origin) / cell).floor())
	var last := Vector2i(((bounds.end - world.origin) / cell).floor())
	if sink.concave:
		_emit_grid_clipped(polygon, first, last, world, sink)
		return
	if first == last:
		_emit_cell(polygon, first.x, first.y, world, sink)
		return
	# Dikey ızgara çizgileriyle sütunlara, her sütun yatay çizgilerle hücrelere böl.
	var rest := polygon
	for x in range(first.x, last.x + 1):
		var column := rest
		if x < last.x:
			var parts := _split(rest, 1.0, 0.0, world.origin.x + (x + 1) * cell)
			column = parts[0]
			rest = parts[1]
		if _area(column) < _MIN_AREA_M2:
			continue
		var column_bounds := _bounds(column)
		var z0 := floori((column_bounds.position.y - world.origin.y) / cell)
		var z1 := floori((column_bounds.end.y - world.origin.y) / cell)
		var cells := column
		for z in range(z0, z1 + 1):
			var piece := cells
			if z < z1:
				var parts := _split(cells, 0.0, 1.0, world.origin.y + (z + 1) * cell)
				piece = parts[0]
				cells = parts[1]
			if _area(piece) >= _MIN_AREA_M2:
				_emit_cell(piece, x, z, world, sink)


## İçbükey olabilecek (kavşak kırpmasından çıkan) çokgenler için: üçgen başına Geometry2D kırpması.
static func _emit_grid_clipped(polygon: PackedVector2Array, first: Vector2i, last: Vector2i,
		world: WorldData, sink: Sink) -> void:
	var cell := world.cell_size
	var h := world.heights
	for z in range(maxi(0, first.y), mini(world.height - 2, last.y) + 1):
		for x in range(maxi(0, first.x), mini(world.width - 2, last.x) + 1):
			var index := z * world.width + x
			var h00 := h[index]
			var h10 := h[index + 1]
			var h01 := h[index + world.width]
			var h11 := h[index + world.width + 1]
			var p00 := world.origin + Vector2(x, z) * cell
			var p10 := p00 + Vector2(cell, 0.0)
			var p01 := p00 + Vector2(0.0, cell)
			var p11 := p00 + Vector2.ONE * cell
			sink.anchor = p00
			var main := TerrainMeshBuilder.uses_main_diagonal(h00, h10, h01, h11, cell)
			var first_triangle := PackedVector2Array([p00, p10, p11]) if main \
					else PackedVector2Array([p00, p10, p01])
			var second_triangle := PackedVector2Array([p00, p11, p01]) if main \
					else PackedVector2Array([p10, p11, p01])
			# Ana köşegende (p00,p10,p11)=pozitif, (p00,p11,p01)=negatif;
			# diğerinde (p00,p10,p01)=negatif, (p10,p11,p01)=pozitif.
			_set_plane(sink, h00, h10, h01, h11, cell, main, main)
			for part: PackedVector2Array in Geometry2D.intersect_polygons(polygon, first_triangle):
				_append(part, sink)
			_set_plane(sink, h00, h10, h01, h11, cell, main, not main)
			for part: PackedVector2Array in Geometry2D.intersect_polygons(polygon, second_triangle):
				_append(part, sink)


## Tek hücredeki çokgeni görünür köşegenle iki arazi üçgenine ayırır ve ekler.
static func _emit_cell(polygon: PackedVector2Array, x: int, z: int, world: WorldData, sink: Sink) -> void:
	if x < 0 or z < 0 or x > world.width - 2 or z > world.height - 2:
		return
	var cell := world.cell_size
	var h := world.heights
	var index := z * world.width + x
	var h00 := h[index]
	var h10 := h[index + 1]
	var h01 := h[index + world.width]
	var h11 := h[index + world.width + 1]
	var p00 := world.origin + Vector2(x, z) * cell
	sink.anchor = p00
	var nx := _DIAGONAL
	var ny := -_DIAGONAL
	var c := _DIAGONAL * (p00.x - p00.y)
	var main := TerrainMeshBuilder.uses_main_diagonal(h00, h10, h01, h11, cell)
	if not main:
		ny = _DIAGONAL
		c = _DIAGONAL * (p00.x + p00.y + cell)
	var low := INF
	var high := -INF
	for v in polygon:
		var d := nx * v.x + ny * v.y - c
		low = minf(low, d)
		high = maxf(high, d)
	# Pozitif taraf: ana köşegende (p00,p10,p11), diğerinde (p10,p11,p01); negatif: (p00,p11,p01) / (p00,p10,p01).
	if high > EPS_M:
		var positive := polygon
		var negative := PackedVector2Array()
		if low < -EPS_M:
			var parts := _split(polygon, nx, ny, c)
			negative = parts[0]
			positive = parts[1]
		_set_plane(sink, h00, h10, h01, h11, cell, main, true)
		_append(positive, sink)
		if not negative.is_empty():
			_set_plane(sink, h00, h10, h01, h11, cell, main, false)
			_append(negative, sink)
	elif low < -EPS_M:
		_set_plane(sink, h00, h10, h01, h11, cell, main, false)
		_append(polygon, sink)


static func _set_plane(sink: Sink, h00: float, h10: float, h01: float, h11: float, cell: float,
		main: bool, positive: bool) -> void:
	if main:
		sink.base = h00
		if positive:
			sink.gx = (h10 - h00) / cell
			sink.gz = (h11 - h10) / cell
		else:
			sink.gx = (h11 - h01) / cell
			sink.gz = (h01 - h00) / cell
	elif positive:
		sink.base = h10 + h01 - h11
		sink.gx = (h11 - h01) / cell
		sink.gz = (h11 - h10) / cell
	else:
		sink.base = h00
		sink.gx = (h10 - h00) / cell
		sink.gz = (h01 - h00) / cell


## n.p = c doğrusuyla böl: [negatif taraf, pozitif taraf]. Doğru üstündeki köşe (|d| <= EPS_M) iki tarafa da girer.
static func _split(polygon: PackedVector2Array, nx: float, ny: float, c: float) -> Array[PackedVector2Array]:
	var negative := PackedVector2Array()
	var positive := PackedVector2Array()
	var prev := polygon[polygon.size() - 1]
	var prev_d := nx * prev.x + ny * prev.y - c
	for cur in polygon:
		var cur_d := nx * cur.x + ny * cur.y - c
		if (prev_d < -EPS_M and cur_d > EPS_M) or (prev_d > EPS_M and cur_d < -EPS_M):
			var crossing := prev + (cur - prev) * (prev_d / (prev_d - cur_d))
			negative.append(crossing)
			positive.append(crossing)
		if cur_d <= EPS_M:
			negative.append(cur)
		if cur_d >= -EPS_M:
			positive.append(cur)
		prev = cur
		prev_d = cur_d
	return [negative, positive]


## Alan (m2). Köşeler ilk köşeye göre alınır: 30 km'lik mutlak koordinatlarda float32 çarpımı alanı bozar.
static func _area(polygon: PackedVector2Array) -> float:
	var count := polygon.size()
	if count < 3:
		return 0.0
	var origin := polygon[0]
	var total := 0.0
	var prev := polygon[1] - origin
	for i in range(2, count):
		var cur := polygon[i] - origin
		total += prev.cross(cur)
		prev = cur
	return absf(total) * 0.5


static func _append(polygon: PackedVector2Array, sink: Sink) -> void:
	var count := polygon.size()
	if count < 3:
		return
	# Alan/yön ilk köşeye göre: 30 km'lik mutlak koordinatta float32 çarpımı hem alanı hem Godot'nun
	# üçgenlemesini bozar (eski sürümde sessizce delik bırakıyordu). Godot "saat yönü" = çapraz toplam < 0.
	var anchor := polygon[0]
	var twice := 0.0
	var prev := polygon[1] - anchor
	for i in range(2, count):
		var cur := polygon[i] - anchor
		twice += prev.cross(cur)
		prev = cur
	if absf(twice) < 2.0 * _MIN_AREA_M2:
		return
	var ring := polygon
	var indices: PackedInt32Array
	if count == 3:
		indices = _triangle_clockwise if twice < 0.0 else _triangle
	else:
		var local := PackedVector2Array()
		for p in polygon:
			local.append(p - anchor)
		if twice < 0.0:
			ring = polygon.duplicate()
			ring.reverse()
			local.reverse()
		indices = Geometry2D.triangulate_polygon(local)
	var lift := sink.base + sink.offset
	var gx := sink.gx
	var gz := sink.gz
	var ax := sink.anchor.x
	var az := sink.anchor.y
	var ox := sink.origin.x
	var oz := sink.origin.y
	var color := sink.color
	var vertices := sink.vertices
	var normals := sink.normals
	var colors := sink.colors
	for i in range(0, indices.size(), 3):
		var p0 := ring[indices[i]]
		var p1 := ring[indices[i + 1]]
		var p2 := ring[indices[i + 2]]
		var v0 := Vector3(p0.x - ox, lift + gx * (p0.x - ax) + gz * (p0.y - az), p0.y - oz)
		var v1 := Vector3(p1.x - ox, lift + gx * (p1.x - ax) + gz * (p1.y - az), p1.y - oz)
		var v2 := Vector3(p2.x - ox, lift + gx * (p2.x - ax) + gz * (p2.y - az), p2.y - oz)
		var normal := (v2 - v0).cross(v1 - v0).normalized()
		if normal.length_squared() < 0.5:
			continue
		vertices.append(v0)
		vertices.append(v1)
		vertices.append(v2)
		normals.append(normal)
		normals.append(normal)
		normals.append(normal)
		colors.append(color)
		colors.append(color)
		colors.append(color)


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
