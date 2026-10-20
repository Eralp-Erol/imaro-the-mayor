class_name NetworkLattice
extends RefCounted
## Bir kentsel doku ayak izi için sokak ızgarası (T-011 üreteci). Izgara hizası ve geçerlilik WorldData'dan türer
## (kıyı teğeti, eğim, kıyı payı, kara kütlesi); koordinat gömme yok. Topoloji (hangi düğüm/kenar var) tohumdan
## BAĞIMSIZDIR (yalnız kontrol verisi + dünya + layout_seed); tohum yalnız konum sapmasını (ayrıntı) belirler.
## Saf; RefCounted.

const SLOPE_PROBE_M := 1500.0
const ANGLE_STEP_DEG := 5.0


## Dönüş: {"nodes": PackedInt32Array, "edges": PackedInt32Array, "hub": int (-1 = boş), "angle_deg": float,
## "jitter": PackedVector2Array (nodes ile hizalı, tohumlu konum sapması)}. Düğümler JİTTERSİZ konumda yaratılır:
## topoloji (kesişim/yapışma kararları) tohumdan bağımsız kalır; sapma üretecin son geçişinde uygulanır.
## `cfg` = fabrics[].lattice veya field_roads girdisi; `excludes` = [{"fp": NetworkFootprint, "inflate": float}].
static func build(net: WorldNetwork, fp: NetworkFootprint, cfg: Dictionary, excludes: Array, world_seed: int,
		layout_seed: int, base_class: StringName) -> Dictionary:
	var world := net.world
	var block_m: Array = cfg.get("block_m", [140.0, 90.0])
	var bu := float(block_m[0])
	var bv := float(block_m[1])
	var angle := _resolve_angle(world, fp, cfg)
	var u := Vector2.from_angle(angle)
	var v := Vector2(-u.y, u.x)
	var ref := fp.center if fp.shape == NetworkFootprint.SHAPE_ELLIPSE else (fp.seg_a + fp.seg_b) * 0.5
	var range_ij := _index_range(fp.bounds(), ref, u, v, bu, bv)
	var jitter := float(cfg.get("jitter_m", 0.0))
	var max_slope := float(cfg.get("max_slope_deg", 9.0))
	var margin := float(cfg.get("shore_margin_m", 120.0))
	var rng := RandomNumberGenerator.new()
	rng.seed = NetworkRules.stream_seed(world_seed, "lattice:" + String(fp.id))
	var fp_hash := NetworkRules.stream_seed(layout_seed, "layout:" + String(fp.id))

	# 1) Geçerli ızgara noktaları (jitter tohumlu RNG'den HER ZAMAN çekilir: geçerlilikten bağımsız sıra).
	var pos := {}
	var jit := {}
	for j in range(range_ij.position.y, range_ij.end.y + 1):
		for i in range(range_ij.position.x, range_ij.end.x + 1):
			var jx := rng.randf_range(-jitter, jitter)
			var jz := rng.randf_range(-jitter, jitter)
			var base := ref + u * (float(i) * bu) + v * (float(j) * bv)
			if _point_ok(world, base, fp, excludes, max_slope, margin):
				pos[Vector2i(i, j)] = base
				jit[Vector2i(i, j)] = Vector2(jx, jz)
	# 2) Adaylar kenarlar (i yönü, j yönü) + isteğe bağlı seyreltme.
	var omit_p := float(cfg.get("omit_local_p", 0.0))
	var every: Array = cfg.get("collector_every", [0, 0])
	var every_u := int(every[0])
	var every_v := int(every[1])
	var adj := {}  # Vector2i -> Array[Vector2i]
	for key: Vector2i in pos:
		adj[key] = []
	var edge_list: Array[Array] = []
	for j in range(range_ij.position.y, range_ij.end.y + 1):
		for i in range(range_ij.position.x, range_ij.end.x + 1):
			var k := Vector2i(i, j)
			if not pos.has(k):
				continue
			for axis in 2:
				var nb := Vector2i(i + 1, j) if axis == 0 else Vector2i(i, j + 1)
				if not pos.has(nb) or not _edge_ok(world, ref, u, v, bu, bv, k, nb, margin):
					continue
				var collector := (axis == 0 and every_v > 0 and posmod(j, every_v) == 0) or \
						(axis == 1 and every_u > 0 and posmod(i, every_u) == 0)
				if omit_p > 0.0 and not collector and _cells_complete(pos, k, axis) and \
						_hash01(fp_hash, i, j, axis) < omit_p:
					continue
				(adj[k] as Array).append(nb)
				(adj[nb] as Array).append(k)
				edge_list.append([k, nb, collector])
	# 3) Ölü uçları buda, merkeze en yakın bileşeni tut.
	var alive := _prune_and_pick_component(adj, pos, ref, u, v, bu, bv)
	# 4) Ağa yaz (deterministik sıra: j, i).
	var ids := {}
	var node_ids := PackedInt32Array()
	var offsets := PackedVector2Array()
	for j in range(range_ij.position.y, range_ij.end.y + 1):
		for i in range(range_ij.position.x, range_ij.end.x + 1):
			var k := Vector2i(i, j)
			if alive.has(k):
				var id := net.add_node_raw(pos[k])
				ids[k] = id
				node_ids.append(id)
				offsets.append(jit[k])
	var edge_ids := PackedInt32Array()
	for e in edge_list:
		var a: Vector2i = e[0]
		var b: Vector2i = e[1]
		if not alive.has(a) or not alive.has(b):
			continue
		var cls := WorldRoadEdge.CLASS_COLLECTOR if bool(e[2]) and base_class == WorldRoadEdge.CLASS_LOCAL else base_class
		edge_ids.append(net.add_edge_raw(int(ids[a]), int(ids[b]), cls, net.rules.width_of(cls)))
	var hub := -1
	var best := INF
	for k: Vector2i in alive:
		var d := (ref + u * (float(k.x) * bu) + v * (float(k.y) * bv)).distance_to(ref)
		if d < best or (d == best and int(ids[k]) < hub):
			best = d
			hub = int(ids[k])
	return {"nodes": node_ids, "edges": edge_ids, "hub": hub, "angle_deg": rad_to_deg(angle), "jitter": offsets}


static func _resolve_angle(world: WorldData, fp: NetworkFootprint, cfg: Dictionary) -> float:
	var spec: Variant = cfg.get("angle_deg", "auto")
	if spec is float or spec is int:
		return deg_to_rad(float(spec))
	if str(spec) == "segment" and fp.shape == NetworkFootprint.SHAPE_CAPSULE:
		return (fp.seg_b - fp.seg_a).angle()
	# auto: kıyı uzaklığı alanının eğimi iç kesimi gösterir; ızgara kıyı teğetine paralel.
	var c := fp.center if fp.shape == NetworkFootprint.SHAPE_ELLIPSE else (fp.seg_a + fp.seg_b) * 0.5
	var gx := _shore_at(world, c + Vector2(SLOPE_PROBE_M, 0)) - _shore_at(world, c - Vector2(SLOPE_PROBE_M, 0))
	var gz := _shore_at(world, c + Vector2(0, SLOPE_PROBE_M)) - _shore_at(world, c - Vector2(0, SLOPE_PROBE_M))
	if absf(gx) + absf(gz) < 100.0:
		return 0.0
	var tangent := Vector2(gx, gz).angle() + PI * 0.5
	var step := deg_to_rad(ANGLE_STEP_DEG)
	return snappedf(tangent, step)


static func _shore_at(world: WorldData, p: Vector2) -> float:
	return world.shore_distance[world.world_to_index(p.x, p.y)]


static func _index_range(rect: Rect2, ref: Vector2, u: Vector2, v: Vector2, bu: float, bv: float) -> Rect2i:
	var lo_i := INF
	var hi_i := -INF
	var lo_j := INF
	var hi_j := -INF
	for corner in [rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]:
		var d: Vector2 = corner - ref
		var proj_i := float(d.dot(u)) / bu
		var proj_j := float(d.dot(v)) / bv
		lo_i = minf(lo_i, proj_i)
		hi_i = maxf(hi_i, proj_i)
		lo_j = minf(lo_j, proj_j)
		hi_j = maxf(hi_j, proj_j)
	var i0 := int(floor(lo_i)) - 1
	var j0 := int(floor(lo_j)) - 1
	return Rect2i(i0, j0, int(ceil(hi_i)) + 1 - i0, int(ceil(hi_j)) + 1 - j0)


static func _point_ok(world: WorldData, p: Vector2, fp: NetworkFootprint, excludes: Array, max_slope: float,
		margin: float) -> bool:
	if not fp.contains(p):
		return false
	for ex: Dictionary in excludes:
		if (ex["fp"] as NetworkFootprint).contains(p, float(ex["inflate"])):
			return false
	var idx := world.world_to_index(p.x, p.y)
	if world.landmass_ids[idx] != WorldData.LANDMASS_MAINLAND or world.shore_distance[idx] < margin:
		return false
	return world.slope_degrees_at(p.x, p.y) <= max_slope


## Kenarın orta ve çeyrek noktaları (jittersiz) kara, kıyı payı yarısı içinde ve eğim sınırı dahilinde.
static func _edge_ok(world: WorldData, ref: Vector2, u: Vector2, v: Vector2, bu: float, bv: float, a: Vector2i,
		b: Vector2i, margin: float) -> bool:
	var pa := ref + u * (float(a.x) * bu) + v * (float(a.y) * bv)
	var pb := ref + u * (float(b.x) * bu) + v * (float(b.y) * bv)
	for t in [0.25, 0.5, 0.75]:
		var p := pa.lerp(pb, t)
		var idx := world.world_to_index(p.x, p.y)
		if world.landmass_ids[idx] != WorldData.LANDMASS_MAINLAND or world.shore_distance[idx] < margin * 0.5:
			return false
	return true


## Seyreltilecek kenarın iki yanındaki hücreler tamamlanmış mı (altı komşu nokta var)?
static func _cells_complete(pos: Dictionary, k: Vector2i, axis: int) -> bool:
	var side := Vector2i(0, 1) if axis == 0 else Vector2i(1, 0)
	var along := Vector2i(1, 0) if axis == 0 else Vector2i(0, 1)
	for s in [-1, 1]:
		if not pos.has(k + side * s) or not pos.has(k + along + side * s):
			return false
	return true


static func _hash01(seed_hash: int, i: int, j: int, axis: int) -> float:
	var x := (seed_hash ^ (i * 73856093) ^ (j * 19349663) ^ (axis * 83492791)) & 0xFFFFFFFF
	x = ((x ^ (x >> 16)) * 2246822519) & 0xFFFFFFFF
	x = ((x ^ (x >> 13)) * 3266489917) & 0xFFFFFFFF
	x = x ^ (x >> 16)
	return float(x & 0xFFFFFF) / 16777216.0


## Derecesi ≤ 1 olan noktaları yinelemeli buda; merkeze (ızgara orijini) en yakın kalan noktanın bileşenini döndürür.
static func _prune_and_pick_component(adj: Dictionary, pos: Dictionary, ref: Vector2, u: Vector2, v: Vector2,
		bu: float, bv: float) -> Dictionary:
	var removed := {}
	var changed := true
	while changed:
		changed = false
		for k: Vector2i in adj:
			if removed.has(k):
				continue
			var deg := 0
			for nb: Vector2i in adj[k]:
				if not removed.has(nb):
					deg += 1
			if deg <= 1:
				removed[k] = true
				changed = true
	var start := Vector2i(0, 0)
	var best := INF
	var found := false
	for k: Vector2i in pos:
		if removed.has(k):
			continue
		var d := (ref + u * (float(k.x) * bu) + v * (float(k.y) * bv)).distance_to(ref)
		if d < best or (d == best and (k.y < start.y or (k.y == start.y and k.x < start.x))):
			best = d
			start = k
			found = true
	var alive := {}
	if not found:
		return alive
	var stack: Array[Vector2i] = [start]
	alive[start] = true
	while not stack.is_empty():
		var cur: Vector2i = stack.pop_back()
		for nb: Vector2i in adj[cur]:
			if not removed.has(nb) and not alive.has(nb):
				alive[nb] = true
				stack.append(nb)
	return alive
