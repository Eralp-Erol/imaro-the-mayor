class_name VegetationCorridor
extends RefCounted
## T-042 sanat düzeltmesi · oyuncu yolunun üstünde kalan ağaç/çalıları gizler (GÖRÜNÜM kuralı; sim'e yazmaz, bitki
## sütunlarına dokunmaz). Koridor = yarı genişlik + bordür (`surface.curb_m`) + `vegetation_clear_margin_m`
## (`data/view/road_style.json`). Kural SAF ve deterministiktir: ağın GÜNCEL durumundaki delta katmanı (oyuncu çizimi)
## yol kenarları -> koridorlar -> bitki satırları; aynı ağ + aynı sütunlar -> aynı gizli küme. Geri almada kenar ağdan
## çıkar, koridoru kalkar, bitki geri gelir (maske her seferinde baştan kurulur, birikmez). Taban yollar zaten
## bitkisizdir (yerleşim kuralları), bu yüzden yalnız delta katmanı taranır.


## Koridorlar: Array of [a: Vector2, b: Vector2, yarıçap: float], kenar kimliğine göre sıralı (deterministik).
static func from_network(net: WorldNetwork, style: RoadStyle) -> Array:
	var out: Array = []
	if net == null or style == null:
		return out
	var margin := float(style.data.get("vegetation_clear_margin_m", 1.0)) + float(style.data["surface"].get("curb_m", 0.0))
	var ids := net.edges.keys()
	ids.sort()
	for eid: int in ids:
		var edge: WorldRoadEdge = net.edges[eid]
		if edge.layer != WorldRoadEdge.LAYER_DELTA or not RoadChunkPlan.is_strip(edge):
			continue
		out.append([net.node_pos(edge.a), net.node_pos(edge.b), style.width_of(edge) * 0.5 + margin])
	return out


## Koridorların içindeki bitki satırları (artan, tekil).
## Yalnız koridor kutusuna değen 256 m hücrelerin satırları taranır.
static func rows_inside(layout: VegetationLayout, corridors: Array) -> PackedInt32Array:
	var seen := {}
	var cols := layout.cols
	for c: Array in corridors:
		var a: Vector2 = c[0]
		var b: Vector2 = c[1]
		var r: float = c[2]
		var box := Rect2(a, Vector2.ZERO).expand(b).grow(r)
		var cx0 := clampi(int(floor((box.position.x - cols.origin.x) / cols.cell_m)), 0, cols.cells_w - 1)
		var cx1 := clampi(int(floor((box.end.x - cols.origin.x) / cols.cell_m)), 0, cols.cells_w - 1)
		var cz0 := clampi(int(floor((box.position.y - cols.origin.y) / cols.cell_m)), 0, cols.cells_h - 1)
		var cz1 := clampi(int(floor((box.end.y - cols.origin.y) / cols.cell_m)), 0, cols.cells_h - 1)
		var r2 := r * r
		for cz in range(cz0, cz1 + 1):
			for cx in range(cx0, cx1 + 1):
				var k := layout.index_of_key(cz * cols.cells_w + cx)
				if k < 0:
					continue
				for i in range(cols.cell_start[k], cols.cell_start[k + 1]):
					var p := Vector2(cols.x[i], cols.z[i])
					if box.has_point(p) and p.distance_squared_to(Geometry2D.get_closest_point_to_segment(p, a, b)) <= r2:
						seen[i] = true
	var out := PackedInt32Array(seen.keys())
	out.sort()
	return out
