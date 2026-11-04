class_name TopologyContour
extends RefCounted
## WorldData yükseklik alanından kontur/kıyı çizgisi (marching squares; T-028). Ayrı kıyı verisi yoktur (WLD-01/TEK-03):
## çizgiler bilineer yüzeyin `level` kesişimidir, yani `WorldData.is_water` ile aynı tanımdır; kenar boyunca
## doğrusal ara değer bilineer yüzeyle tam örtüşür. Saf: Node/Time/OS/rastgelelik yok; sıra hücre tarama
## sırasıyla deterministiktir.
##
## Dönüş her zincir için: {"points": PackedVector2Array (dünya m), "closed": bool, "landmass": int}.
## `landmass` = çizginin kara tarafındaki kara kütlesi kimliği (WorldData.landmass_ids; yalnız anlamlı seviyede).

## Hücre köşeleri: 00 = (i, j), 10 = (i+1, j), 11 = (i+1, j+1), 01 = (i, j+1). Kenarlar: T üst, R sağ, B alt, L sol.
const T := 0
const R := 1
const B := 2
const L := 3


static func trace(world: WorldData, level: float) -> Array[Dictionary]:
	var w := world.width
	var h := world.height
	var heights := world.heights
	var neighbors := {}
	var edge_landmass := {}
	var order: Array[int] = []
	for j in h - 1:
		for i in w - 1:
			var i00 := j * w + i
			var h00 := heights[i00]
			var h10 := heights[i00 + 1]
			var h11 := heights[i00 + w + 1]
			var h01 := heights[i00 + w]
			var code := (1 if h00 >= level else 0) | (2 if h10 >= level else 0) \
					| (4 if h11 >= level else 0) | (8 if h01 >= level else 0)
			if code == 0 or code == 15:
				continue
			var land := _cell_landmass(world, i00, code)
			for pair in _pairs(code, (h00 + h10 + h11 + h01) * 0.25 >= level):
				var ea := _edge_id(i00, w, pair[0])
				var eb := _edge_id(i00, w, pair[1])
				_link(neighbors, order, ea, eb)
				edge_landmass[ea] = land
				edge_landmass[eb] = land
	return _chains(world, level, neighbors, order, edge_landmass)


static func _cell_landmass(world: WorldData, i00: int, code: int) -> int:
	var w := world.width
	var best := 0
	var corners := [i00, i00 + 1, i00 + w + 1, i00 + w]
	for k in 4:
		if (code & (1 << k)) != 0:
			best = maxi(best, world.landmass_ids[corners[k]])
	return best


## Seçilen kenarın benzersiz kimliği: örnek indeksi * 2 + (0 = yatay kenar, 1 = dikey kenar).
static func _edge_id(i00: int, w: int, edge: int) -> int:
	match edge:
		T:
			return i00 * 2
		B:
			return (i00 + w) * 2
		L:
			return i00 * 2 + 1
		_:
			return (i00 + 1) * 2 + 1


## Hücre koduna göre çizgi parçaları (kenar çiftleri). Belirsiz (eyer) durumda merkez değeri kararı verir.
static func _pairs(code: int, center_inside: bool) -> Array:
	match code:
		1:
			return [[L, T]]
		2:
			return [[T, R]]
		3:
			return [[L, R]]
		4:
			return [[R, B]]
		5:
			return [[T, R], [L, B]] if center_inside else [[L, T], [R, B]]
		6:
			return [[T, B]]
		7:
			return [[L, B]]
		8:
			return [[L, B]]
		9:
			return [[T, B]]
		10:
			return [[L, T], [R, B]] if center_inside else [[T, R], [L, B]]
		11:
			return [[R, B]]
		12:
			return [[L, R]]
		13:
			return [[T, R]]
		14:
			return [[L, T]]
	return []


static func _link(neighbors: Dictionary, order: Array[int], a: int, b: int) -> void:
	for pair in [[a, b], [b, a]]:
		var key: int = pair[0]
		if not neighbors.has(key):
			neighbors[key] = []
			order.append(key)
		(neighbors[key] as Array).append(pair[1])


static func _chains(world: WorldData, level: float, neighbors: Dictionary, order: Array[int],
		edge_landmass: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var visited := {}
	# Önce açık uçlu zincirler (harita kenarına dayanan), sonra kapalı döngüler.
	for pass_index in 2:
		for start in order:
			if visited.has(start):
				continue
			var degree := (neighbors[start] as Array).size()
			if pass_index == 0 and degree != 1:
				continue
			out.append(_walk(world, level, neighbors, visited, start, edge_landmass))
	return out


static func _walk(world: WorldData, level: float, neighbors: Dictionary, visited: Dictionary, start: int,
		edge_landmass: Dictionary) -> Dictionary:
	var pts := PackedVector2Array()
	var cur := start
	var closed := false
	while true:
		visited[cur] = true
		pts.append(_edge_point(world, level, cur))
		var nxt := -1
		for cand: int in neighbors[cur] as Array:
			if not visited.has(cand):
				nxt = cand
				break
		if nxt < 0:
			for cand: int in neighbors[cur] as Array:
				if cand == start and pts.size() > 2:
					closed = true
			break
		cur = nxt
	return {"points": pts, "closed": closed, "landmass": int(edge_landmass.get(start, 0))}


@warning_ignore("integer_division")
static func _edge_point(world: WorldData, level: float, edge: int) -> Vector2:
	var idx := edge >> 1
	var i := idx % world.width
	var j := idx / world.width
	var a := world.heights[idx]
	var b := world.heights[idx + 1] if (edge & 1) == 0 else world.heights[idx + world.width]
	var t := 0.5 if is_equal_approx(a, b) else clampf((level - a) / (b - a), 0.0, 1.0)
	var base := world.cell_to_world(i, j)
	if (edge & 1) == 0:
		return base + Vector2(t * world.cell_size, 0.0)
	return base + Vector2(0.0, t * world.cell_size)
