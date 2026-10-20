class_name NetworkRouter
extends RefCounted
## WorldData üzerinde kaba maliyet ızgarası + A* ile yol/ray güzergâhı (T-011 üreteci). Koordinat gömme yok: maliyet
## kıyıdan (kara/su, kıyı payı), eğimden ve kentsel ayak izlerinden türer. Saf, deterministik: eşitlikte hücre indeksi
## küçük olan önce çıkar; RNG yok. Profiller: &"road", &"rail", &"coast" (kıyı konturunu izler).

const PROFILE_ROAD := &"road"
const PROFILE_RAIL := &"rail"
const PROFILE_COAST := &"coast"
const SEGMENT_SAMPLE_M := 40.0

var world: WorldData = null
var cell: float = 250.0
var cols: int = 0
var rows: int = 0
var cfg: Dictionary = {}
var footprints: Array[NetworkFootprint] = []

var _known: PackedByteArray = PackedByteArray()
var _slope: PackedFloat32Array = PackedFloat32Array()
var _shore: PackedFloat32Array = PackedFloat32Array()
var _land: PackedByteArray = PackedByteArray()
var _foot: PackedByteArray = PackedByteArray()
var _max_segment: float = 350.0


func _init(p_world: WorldData, routing_cfg: Dictionary, p_footprints: Array[NetworkFootprint],
		max_segment_m: float = 350.0) -> void:
	world = p_world
	cfg = routing_cfg
	footprints = p_footprints
	cell = float(cfg.get("cell_m", 250.0))
	cols = int(ceil(world.size.x / cell))
	rows = int(ceil(world.size.y / cell))
	_known.resize(cols * rows)
	_slope.resize(cols * rows)
	_shore.resize(cols * rows)
	_land.resize(cols * rows)
	_foot.resize(cols * rows)
	_max_segment = max_segment_m


## Başlangıç ve bitiş arasında güzergâh (yol kırıkları dünya metresi); bulunamazsa boş dizi. İlk ve son nokta aynen
## `a` ve `b`dir (hücre merkezi değil).
func route(a: Vector2, b: Vector2, profile: StringName) -> PackedVector2Array:
	var base_slope := float(cfg.get("rail_max_slope_deg" if profile == PROFILE_RAIL else "road_max_slope_deg", 13.0))
	for factor in cfg.get("relax_steps", [1.0, 1.5, 2.2]):
		var cells := _astar(a, b, profile, base_slope * float(factor))
		if not cells.is_empty():
			return _to_polyline(cells, a, b)
	return PackedVector2Array()


func _cell_of(p: Vector2) -> int:
	var i := clampi(int(floor((p.x - world.origin.x) / cell)), 0, cols - 1)
	var j := clampi(int(floor((p.y - world.origin.y) / cell)), 0, rows - 1)
	return j * cols + i


@warning_ignore("integer_division")
func _center(idx: int) -> Vector2:
	return world.origin + Vector2(float(idx % cols) + 0.5, float(idx / cols) + 0.5) * cell


func _ensure(idx: int) -> void:
	if _known[idx] == 1:
		return
	_known[idx] = 1
	var c := _center(idx)
	var wi := world.world_to_index(c.x, c.y)
	_land[idx] = 1 if (world.landmass_ids[wi] == WorldData.LANDMASS_MAINLAND and not world.is_water(c.x, c.y)) else 0
	_shore[idx] = world.shore_distance[wi]
	_slope[idx] = world.slope_degrees_at(c.x, c.y)
	var inflate := float(cfg.get("footprint_inflate_m", 150.0))
	var inside := 0
	for fp in footprints:
		if fp.contains(c, inflate):
			inside = 1
			break
	_foot[idx] = inside


func _passable(idx: int, slope_limit: float, force: bool) -> bool:
	_ensure(idx)
	if _land[idx] == 0:
		return false
	if force:
		return true
	if _shore[idx] < float(cfg.get("shore_margin_m", 90.0)):
		return false
	return _slope[idx] <= slope_limit


func _step_cost(idx: int, profile: StringName) -> float:
	var c := 1.0 + float(cfg.get("slope_cost_per_deg", 0.2)) * _slope[idx]
	if _foot[idx] == 1:
		c += float(cfg.get("footprint_penalty", 6.0))
	if profile == PROFILE_COAST:
		var offset := float(cfg.get("coast_offset_m", 280.0))
		c += float(cfg.get("coast_weight", 3.0)) * clampf(absf(_shore[idx] - offset) / offset, 0.0, 3.0)
	return c


@warning_ignore("integer_division")
func _astar(a: Vector2, b: Vector2, profile: StringName, slope_limit: float) -> PackedInt32Array:
	var start := _cell_of(a)
	var goal := _cell_of(b)
	var count := cols * rows
	var g := PackedFloat32Array()
	g.resize(count)
	g.fill(INF)
	var came := PackedInt32Array()
	came.resize(count)
	came.fill(-1)
	var closed := PackedByteArray()
	closed.resize(count)
	var keys := PackedFloat64Array()
	var vals := PackedInt32Array()
	g[start] = 0.0
	NetworkPathfinder.heap_push(keys, vals, _center(start).distance_to(_center(goal)), start)
	var found := false
	while not vals.is_empty():
		var cur := NetworkPathfinder.heap_pop(keys, vals)
		if closed[cur] == 1:
			continue
		closed[cur] = 1
		if cur == goal:
			found = true
			break
		var ci := cur % cols
		var cj := cur / cols
		for dj in range(-1, 2):
			for di in range(-1, 2):
				if di == 0 and dj == 0:
					continue
				var ni := ci + di
				var nj := cj + dj
				if ni < 0 or nj < 0 or ni >= cols or nj >= rows:
					continue
				var nxt := nj * cols + ni
				if closed[nxt] == 1:
					continue
				if not _passable(nxt, slope_limit, nxt == goal or nxt == start):
					continue
				var step := 1.0
				if di != 0 and dj != 0:
					# Köşe kesmeyi önle: iki dik komşu da geçilebilir olmalı.
					if not _passable(cj * cols + ni, slope_limit, false) or \
							not _passable(nj * cols + ci, slope_limit, false):
						continue
					step = 1.41421356
				var ng := g[cur] + step * cell * 0.5 * (_step_cost(cur, profile) + _step_cost(nxt, profile))
				if ng < g[nxt]:
					g[nxt] = ng
					came[nxt] = cur
					NetworkPathfinder.heap_push(keys, vals, ng + _center(nxt).distance_to(_center(goal)), nxt)
	if not found:
		return PackedInt32Array()
	var path: Array[int] = []
	var at := goal
	while at != -1:
		path.append(at)
		at = came[at]
	path.reverse()
	return PackedInt32Array(path)


func _to_polyline(cells: PackedInt32Array, a: Vector2, b: Vector2) -> PackedVector2Array:
	var pts := PackedVector2Array()
	pts.append(a)
	for k in range(1, cells.size() - 1):
		pts.append(_center(cells[k]))
	pts.append(b)
	var simple := _simplify(pts, float(cfg.get("simplify_m", 150.0)))
	return _subdivide(simple)


## Douglas-Peucker + kara doğrulaması: sapma sınırı aşılırsa VEYA doğru parça suya değiyorsa ayrıştırılır.
func _simplify(pts: PackedVector2Array, eps: float) -> PackedVector2Array:
	var n := pts.size()
	if n <= 2:
		return pts
	var keep := PackedByteArray()
	keep.resize(n)
	keep[0] = 1
	keep[n - 1] = 1
	var stack: Array[Vector2i] = [Vector2i(0, n - 1)]
	while not stack.is_empty():
		var r: Vector2i = stack.pop_back()
		if r.y - r.x < 2:
			continue
		var worst := -1.0
		var worst_idx := -1
		for k in range(r.x + 1, r.y):
			var d := NetworkGeometry.distance_point_segment(pts[k], pts[r.x], pts[r.y])
			if d > worst:
				worst = d
				worst_idx = k
		if worst > eps or not _segment_dry(pts[r.x], pts[r.y]):
			var split_at := worst_idx if worst > eps else (r.x + r.y) >> 1
			keep[split_at] = 1
			stack.append(Vector2i(r.x, split_at))
			stack.append(Vector2i(split_at, r.y))
	var out := PackedVector2Array()
	for k in n:
		if keep[k] == 1:
			out.append(pts[k])
	return out


func _segment_dry(a: Vector2, b: Vector2) -> bool:
	var steps := maxi(1, int(ceil(a.distance_to(b) / SEGMENT_SAMPLE_M)))
	for s in range(1, steps):
		var p := a.lerp(b, float(s) / float(steps))
		if world.is_water(p.x, p.y) or world.landmass_at(p.x, p.y) != WorldData.LANDMASS_MAINLAND:
			return false
	return true


func _subdivide(pts: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for k in range(pts.size() - 1):
		var a := pts[k]
		var b := pts[k + 1]
		out.append(a)
		var pieces := int(ceil(a.distance_to(b) / _max_segment))
		for s in range(1, pieces):
			out.append(a.lerp(b, float(s) / float(pieces)))
	out.append(pts[pts.size() - 1])
	return out
