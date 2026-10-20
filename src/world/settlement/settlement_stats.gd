class_name SettlementStats
extends RefCounted
## T0 yerleşim ölçüm yardımcıları (T-005): çatı payı, yoğunluk, bitişik nizam, blok çevresi doluluğu, yükseklik
## hiyerarşisi, kompozisyon kuralları (kit spec §3.2/§3.3/§4/§7.1). Testler ve ölçüm aracı (CLI) kullanır; üretici
## kendi çıktısını bu fonksiyonlarla DEĞİL, bağımsız kurallarıyla üretir. Saf, statik.

const PARAPET_M := 0.9
## Cephe kenarından bu kadar (m) içerideki yapı arka sıra sayılır (ön sıra çekmesi en çok ~9 m).
const BACK_ROW_MIN_M := 11.0
const TOWER_FRAME_RADIUS_M := 150.0
const TILE_ROWS: Array[String] = ["R3", "R4", "R5"]
const TERRACE_ROWS: Array[String] = ["R1", "R2"]
const METAL_ROWS: Array[String] = ["R6", "R7"]


# ---------------------------------------------------------------- seçim yardımcıları

static func indices_in_zones(res: SettlementResult, zone_names: Array) -> PackedInt32Array:
	var out := PackedInt32Array()
	var want := {}
	for z in zone_names:
		want[StringName(z)] = true
	for i in res.columns.count:
		if want.has(res.zone_of_building(i)):
			out.append(i)
	return out


static func indices_in_region(res: SettlementResult, code: StringName) -> PackedInt32Array:
	var out := PackedInt32Array()
	for i in res.columns.count:
		var p := res.net.parcel(res.columns.parcel_id[i])
		if p != null and p.region_code == code:
			out.append(i)
	return out


static func _row_names(res: SettlementResult) -> Array[String]:
	var out: Array[String] = []
	out.resize(32)
	for key: String in res.rules.palette_rows:
		out[int(res.rules.palette_rows[key])] = key
	return out


static func roof_class(res: SettlementResult, names: Array[String], i: int) -> StringName:
	var m := res.module_of(i)
	if m.roof_type == &"sawtooth":
		return &"other"
	var row_name := names[res.columns.roof_row[i]]
	if TILE_ROWS.has(row_name):
		return &"tile"
	if TERRACE_ROWS.has(row_name):
		return &"terrace"
	if METAL_ROWS.has(row_name):
		return &"metal"
	return &"other"


## Çatı alanı payları (alan = modül ayak izi). `indices` boşsa tüm yapılar (saat kulesi hariç).
static func roof_shares(res: SettlementResult, indices: PackedInt32Array) -> Dictionary:
	var names := _row_names(res)
	var list := indices
	if list.is_empty():
		for i in res.columns.count:
			list.append(i)
	var area := {"terrace": 0.0, "tile": 0.0, "metal": 0.0, "other": 0.0}
	var tones := {}
	var total := 0.0
	for i in list:
		if i == res.tower_index:
			continue
		var m := res.module_of(i)
		var a := m.w * m.d
		var cls := roof_class(res, names, i)
		area[cls] += a
		total += a
		if cls == &"tile":
			var tone := names[res.columns.roof_row[i]]
			tones[tone] = float(tones.get(tone, 0.0)) + a
	var out := {"area": total, "tile_tones": tones.size(), "r3_of_tile": 0.0}
	for key: StringName in area:
		out[key] = area[key] / maxf(total, 1.0)
	if area["tile"] > 0.0:
		out["r3_of_tile"] = float(tones.get("R3", 0.0)) / float(area["tile"])
	return out


## Kayan pencere (yarım adım kaydırmalı iki ızgara): en kiremitli pencerenin kiremit payı. `min_count` altı
## pencere sayılmaz.
## Küçük merkez/köy/tarla dokusu çoğunlukta olan pencereler kentsel sayılmaz (kit §3.2 tablosunda kendi aralıkları var).
static func window_tile_max(res: SettlementResult, window_m: float, min_count: int,
		small_zones: Array = [&"village", &"hillside", &"farm"]) -> Dictionary:
	var names := _row_names(res)
	var small := {}
	for z in small_zones:
		small[StringName(z)] = true
	var best := 0.0
	var worst := Vector2.ZERO
	var windows := 0
	for shift in [0.0, 0.5]:
		var cells := {}
		for i in res.columns.count:
			if i == res.tower_index:
				continue
			var key := Vector2i(floori(res.columns.x[i] / window_m + shift), floori(res.columns.z[i] / window_m + shift))
			if not cells.has(key):
				cells[key] = []
			(cells[key] as Array).append(i)
		for key: Vector2i in cells:
			var list: Array = cells[key]
			if list.size() < min_count:
				continue
			var small_count := 0
			for i in list:
				if small.has(res.zone_of_building(i)):
					small_count += 1
			if small_count * 2 >= list.size():
				continue
			windows += 1
			var tile := 0.0
			var total := 0.0
			for i in list:
				var m := res.module_of(i)
				total += m.w * m.d
				if roof_class(res, names, i) == &"tile":
					tile += m.w * m.d
			var share := tile / maxf(total, 1.0)
			if share > best:
				best = share
				worst = Vector2((float(key.x) - shift) * window_m, (float(key.y) - shift) * window_m)
	return {"windows": windows, "max_tile": best, "worst_origin": worst}


# ---------------------------------------------------------------- bölge yoğunluğu ve karışımı

static func region_density(res: SettlementResult, code: StringName) -> Dictionary:
	var world := res.net.world
	var region := world.region_by_code(code)
	var cells := 0
	for rid in world.region_ids:
		if rid == region.id:
			cells += 1
	var area_km2 := float(cells) * world.cell_size * world.cell_size / 1.0e6
	var gfa := 0.0
	var count := 0
	var floors := 0.0
	for i in indices_in_region(res, code):
		var m := res.module_of(i)
		if m.floors <= 0:
			continue
		gfa += m.w * m.d * float(m.floors)
		floors += float(m.floors)
		count += 1
	return {"buildings": count, "area_km2": area_km2, "gfa_per_km2": gfa / maxf(area_km2, 0.001),
			"buildings_per_km2": float(count) / maxf(area_km2, 0.001), "mean_floors": floors / maxf(float(count), 1.0)}


static func region_mix(res: SettlementResult, code: StringName) -> Dictionary:
	var out := {"buildings": 0, "housing": 0, "shops": 0, "workplaces": 0, "civic": 0}
	for i in indices_in_region(res, code):
		var m := res.module_of(i)
		out["buildings"] += 1
		if m.family.begins_with("res_"):
			out["housing"] += 1
		if (res.columns.flags[i] & BuildingColumns.FLAG_GROUND_SHOP) != 0:
			out["shops"] += 1
		if m.family.begins_with("ind_"):
			out["workplaces"] += 1
		if m.family.begins_with("civ_"):
			out["civic"] += 1
	return out


# ---------------------------------------------------------------- sokak sırası, komşu kuralları

## Sokak cephesi gruplarındaki yapılar cephe boyunca sıralı: [{"order": PackedInt32Array, "ppos": PackedInt32Array}].
## `ppos` yapının parselinin gruptaki sırası (komşu parsel denetimi için).
static func street_groups(res: SettlementResult) -> Array:
	if res.cache.has("street_groups"):
		return res.cache["street_groups"]
	var by_parcel := {}
	for i in res.columns.count:
		var pid := res.columns.parcel_id[i]
		if not by_parcel.has(pid):
			by_parcel[pid] = []
		(by_parcel[pid] as Array).append(i)
	var ids := PackedInt32Array()
	for pid: int in by_parcel:
		ids.append(pid)
	ids.sort()
	var groups: Array = []
	for g in SettlementGroups.build(res.net, ids):
		var e: WorldRoadEdge = res.net.edges[int(g["edge"])]
		var a := res.net.node_pos(e.a)
		var dir := (res.net.node_pos(e.b) - a).normalized()
		var parcels: PackedInt32Array = g["parcels"]
		var rows: Array = [[], []]
		for pos in parcels.size():
			for i: int in (by_parcel[parcels[pos]] as Array):
				if i == res.tower_index:
					continue
				var along := float((res.columns.position_of(i) - a).dot(dir))
				(rows[building_row(res, i, a, dir)] as Array).append(Vector3(along, i, pos))
		for items: Array in rows:
			items.sort_custom(func(l: Vector3, r: Vector3) -> bool: return l.x < r.x or (l.x == r.x and l.y < r.y))
			var order := PackedInt32Array()
			var ppos := PackedInt32Array()
			for it: Vector3 in items:
				order.append(int(it.y))
				ppos.append(int(it.z))
			if not order.is_empty():
				groups.append({"order": order, "ppos": ppos, "dir": dir, "edge": int(g["edge"]),
						"row": rows.find(items)})
	res.cache["street_groups"] = groups
	return groups


## Yapının cephe sırası: 0 = sokağa dönük ön sıra, 1 = arka sıra (cephe çizgisinden uzaklık - yarım derinlik > eşik).
static func building_row(res: SettlementResult, i: int, edge_a: Vector2, dir: Vector2) -> int:
	var m := res.module_of(i)
	var d := absf(float((res.columns.position_of(i) - edge_a).cross(dir)))
	return 1 if d - m.d * 0.5 > BACK_ROW_MIN_M else 0


static func street_order(res: SettlementResult) -> Array[PackedInt32Array]:
	var out: Array[PackedInt32Array] = []
	for g: Dictionary in street_groups(res):
		out.append(g["order"])
	return out


## Komşu kuralları: aynı (mesh + duvar) komşu sayısı, art arda aynı (varyant+kat+duvar) en uzun dizi, 9'lu pencerede
## >= 3 mesh ve >= 3 duvar rengi (ihlal oranı).
static func neighbour_rules(res: SettlementResult, skip_zones: Array = [&"yard", &"farm"]) -> Dictionary:
	var c := res.columns
	var skip := {}
	for z in skip_zones:
		skip[StringName(z)] = true
	var pairs := 0
	var same := 0
	var max_run := 1
	var windows := 0
	var window_fail := 0
	for g: Dictionary in street_groups(res):
		var order := _without_zones(res, g["order"], skip)
		var run := 1
		for k in range(1, order.size()):
			var a := order[k - 1]
			var b := order[k]
			pairs += 1
			if c.module_idx[a] == c.module_idx[b] and c.wall_row[a] == c.wall_row[b]:
				same += 1
				run += 1
				max_run = maxi(max_run, run)
			else:
				run = 1
		for k in range(0, order.size() - 8):
			windows += 1
			var meshes := {}
			var walls := {}
			for q in 9:
				meshes[c.module_idx[order[k + q]]] = true
				walls[c.wall_row[order[k + q]]] = true
			if meshes.size() < 3 or walls.size() < 3:
				window_fail += 1
	return {"pairs": pairs, "same_mesh_wall_neighbours": same, "max_identical_run": max_run, "windows": windows,
			"window_fail_ratio": float(window_fail) / maxf(float(windows), 1.0)}


static func _without_zones(res: SettlementResult, order: PackedInt32Array, skip: Dictionary) -> PackedInt32Array:
	if skip.is_empty():
		return order
	var out := PackedInt32Array()
	for i in order:
		if not skip.has(res.zone_of_building(i)):
			out.append(i)
	return out


## 9 ardışık KONUT (res_mid/old/late) yapısında kat sayısı std >= 1 olan pencerelerin oranı (verilen dokularda).
## `min_mean`: yalnız ortalama katı bu değerin üstündeki ("orta yoğun") pencereler sayılır; alçak sıralar hariç.
static func floor_variety(res: SettlementResult, zone_names: Array, min_mean: float = 0.0) -> Dictionary:
	var want := {}
	for z in zone_names:
		want[StringName(z)] = true
	var windows := 0
	var ok := 0
	for g: Dictionary in street_groups(res):
		var floors: Array[float] = []
		for i in g["order"]:
			var m := res.module_of(i)
			if want.has(res.zone_of_building(i)) and (m.family == "res_mid" or m.family == "res_old" \
					or m.family == "res_late"):
				floors.append(float(m.floors))
		for k in range(0, floors.size() - 8):
			var mean := 0.0
			for q in 9:
				mean += floors[k + q]
			mean /= 9.0
			if mean < min_mean:
				continue
			windows += 1
			var acc := 0.0
			for q in 9:
				acc += (floors[k + q] - mean) * (floors[k + q] - mean)
			if sqrt(acc / 9.0) >= 1.0:
				ok += 1
	return {"windows": windows, "ok_ratio": float(ok) / maxf(float(windows), 1.0)}


## 200 x 200 m hücrelerde benzersiz (mesh, kat, duvar) kombinasyonu oranı >= %60 olan hücrelerin oranı
## (`min_count` altı yapılı hücreler sayılmaz). Kat mesh'ten türer; kombinasyon = (mesh, duvar).
static func unique_combo_ratio(res: SettlementResult, cell_m: float, min_count: int) -> Dictionary:
	var cells := {}
	for i in res.columns.count:
		if i == res.tower_index:
			continue
		var key := Vector2i(floori(res.columns.x[i] / cell_m), floori(res.columns.z[i] / cell_m))
		if not cells.has(key):
			cells[key] = []
		(cells[key] as Array).append(res.columns.module_idx[i] * 64 + res.columns.wall_row[i])
	var counted := 0
	var ok := 0
	var worst := 1.0
	for key: Vector2i in cells:
		var list: Array = cells[key]
		if list.size() < min_count:
			continue
		var seen := {}
		for v in list:
			seen[v] = true
		var ratio := float(seen.size()) / float(list.size())
		counted += 1
		worst = minf(worst, ratio)
		if ratio >= 0.60:
			ok += 1
	return {"cells": counted, "ok_ratio": float(ok) / maxf(float(counted), 1.0), "min_ratio": worst}


# ---------------------------------------------------------------- bitişik nizam, blok çevresi

## Ardışık yapı çiftleri (aynı sokak cephesi grubu, parseller komşu: ara boş lot yok) için cephe boyunca aralığı <=
## `max_gap` olanların oranı; iki yapı da verilen dokularda olmalı.
static func adjacency(res: SettlementResult, zone_names: Array, max_gap: float) -> Dictionary:
	var want := {}
	for z in zone_names:
		want[StringName(z)] = true
	var pairs := 0
	var tight := 0
	var c := res.columns
	for g: Dictionary in street_groups(res):
		if int(g["row"]) > 0:
			continue
		var order: PackedInt32Array = g["order"]
		var ppos: PackedInt32Array = g["ppos"]
		var dir: Vector2 = g["dir"]
		for k in range(1, order.size()):
			var a := order[k - 1]
			var b := order[k]
			if ppos[k] - ppos[k - 1] > 1:
				continue
			if not want.has(res.zone_of_building(a)) or not want.has(res.zone_of_building(b)):
				continue
			var ea := _extent_along(res, a, dir)
			var eb := _extent_along(res, b, dir)
			var gap := eb.x - ea.y
			pairs += 1
			if gap <= max_gap:
				tight += 1
	return {"pairs": pairs, "tight": tight, "ratio": float(tight) / maxf(float(pairs), 1.0)}


static func _extent_along(res: SettlementResult, i: int, dir: Vector2) -> Vector2:
	var m := res.module_of(i)
	var c := res.columns
	var lo := INF
	var hi := -INF
	for p in SettlementObb.corners(c.x[i], c.z[i], c.yaw[i], m.w, m.d):
		var d := float(p.dot(dir))
		lo = minf(lo, d)
		hi = maxf(hi, d)
	return Vector2(lo, hi)


## D1/D6 gibi bölgelerin parsellenmiş blokları: cephe uzunluğunun yapıyla kaplanan payı.
## coverage = tüm parseller; coverage_occupied = yapısı olan (veya sivil yapıya katılan) parseller.
static func block_frontage_fill(res: SettlementResult, region_codes: Array) -> Dictionary:
	var width_by_parcel := {}
	for i in res.columns.count:
		if i == res.tower_index:
			continue
		var pid := res.columns.parcel_id[i]
		var pe := res.net.parcel(pid)
		var edge := res.net.edge(pe.frontage_edge)
		if edge != null and building_row(res, i, res.net.node_pos(edge.a),
				(res.net.node_pos(edge.b) - res.net.node_pos(edge.a)).normalized()) > 0:
			continue
		width_by_parcel[pid] = float(width_by_parcel.get(pid, 0.0)) + res.module_of(i).w
	var built_total := 0.0
	var front_total := 0.0
	var built_occ := 0.0
	var front_occ := 0.0
	var per_block: Array[float] = []
	for bid: int in res.net.blocks:
		var b: WorldBlock = res.net.blocks[bid]
		if b.kind != WorldBlock.KIND_PARCELIZED or not region_codes.has(b.region_code) or b.parcel_ids.size() < 4:
			continue
		var bf := 0.0
		var bb := 0.0
		for pid in b.parcel_ids:
			var p: WorldParcel = res.net.parcels[pid]
			var w := minf(float(width_by_parcel.get(pid, 0.0)), p.front_length)
			bf += p.front_length
			bb += w
			if width_by_parcel.has(pid) or res.consumed.has(pid):
				front_occ += p.front_length
				built_occ += w
		built_total += bb
		front_total += bf
		per_block.append(bb / maxf(bf, 1.0))
	per_block.sort()
	return {"blocks": per_block.size(), "coverage": built_total / maxf(front_total, 1.0),
			"coverage_occupied": built_occ / maxf(front_occ, 1.0),
			"median_block": 0.0 if per_block.is_empty() else per_block[per_block.size() / 2]}


# ---------------------------------------------------------------- yükseklik hiyerarşisi

## Bölgede (konut, kule hariç) ortalama kat: yoğun dokunun iç (t < 0,55) / dış (t >= 0,75) kuşağı, tarihî çekirdek
## ve ana cadde / yerel sokak cephesi.
static func height_hierarchy(res: SettlementResult, code: StringName) -> Dictionary:
	var fp := res.net.rules.footprint_by_id(code)
	var keys := ["dense_inner", "dense_outer", "historic", "main", "local"]
	var sums := {}
	var counts := {}
	for k in keys:
		sums[k] = 0.0
		counts[k] = 0
	for i in indices_in_region(res, code):
		var m := res.module_of(i)
		if not (m.family == "res_mid" or m.family == "res_old" or m.family == "res_late"):
			continue
		var p := res.net.parcel(res.columns.parcel_id[i])
		var t := fp.norm_dist(p.centroid)
		var zone := res.zone_of_building(i)
		var f := float(m.floors)
		if zone == &"dense" and t < 0.55:
			sums["dense_inner"] += f
			counts["dense_inner"] += 1
		elif zone == &"dense" and t >= 0.75:
			sums["dense_outer"] += f
			counts["dense_outer"] += 1
		elif zone == &"historic":
			sums["historic"] += f
			counts["historic"] += 1
		var edge := res.net.edge(p.frontage_edge)
		var key := "main" if edge.road_class in [WorldRoadEdge.CLASS_ARTERIAL, WorldRoadEdge.CLASS_COLLECTOR] else "local"
		sums[key] += f
		counts[key] += 1
	var out := {"counts": counts}
	for k in keys:
		out[k] = sums[k] / maxf(float(counts[k]), 1.0)
	return out


# ---------------------------------------------------------------- saat kulesi

static func tower_frame(res: SettlementResult, radius_m: float = TOWER_FRAME_RADIUS_M) -> Dictionary:
	if res.tower_index < 0:
		return {"count": 0, "h_s": 0.0, "ratio": 99.0, "max_floors": 0.0, "mean_floors": 0.0}
	var c := res.columns
	var center := c.position_of(res.tower_index)
	var tower_h := res.module_of(res.tower_index).total_m
	var h_s := 0.0
	var count := 0
	var max_floors := 0.0
	var sum_floors := 0.0
	for i in c.count:
		if i == res.tower_index or c.position_of(i).distance_to(center) > radius_m:
			continue
		var m := res.module_of(i)
		count += 1
		h_s = maxf(h_s, m.eave_m + PARAPET_M)
		max_floors = maxf(max_floors, float(m.floors))
		sum_floors += float(m.floors)
	return {"count": count, "h_s": h_s, "ratio": tower_h / maxf(h_s, 0.001), "max_floors": max_floors,
			"mean_floors": sum_floors / maxf(float(count), 1.0), "tower_h": tower_h}


## Kule çevresinde açık meydan: kule merkezinden L-sonsuz uzaklıkta en yakın yapı -> temiz kare kenarı (m) ve meydan
## dikdörtgenini kesen yapı sayısı (kule hariç). Kare, meydan eksenine hizalıdır.
static func plaza_clear_report(res: SettlementResult, min_m: float) -> Dictionary:
	if res.tower_index < 0 or res.plaza.is_empty():
		return {"intruders": 999, "clear_m": 0.0}
	var c := res.columns
	var center := c.position_of(res.tower_index)
	var axis: Vector2 = res.plaza["axis"]
	var perp := Vector2(-axis.y, axis.x)
	var half := min_m * 0.5
	var square := PackedVector2Array([center - axis * half - perp * half, center + axis * half - perp * half,
			center + axis * half + perp * half, center - axis * half + perp * half])
	var intruders := 0
	var nearest := INF
	for i in c.count:
		if i == res.tower_index:
			continue
		if c.position_of(i).distance_to(center) > 140.0:
			continue
		var m := res.module_of(i)
		var corners := SettlementObb.corners(c.x[i], c.z[i], c.yaw[i], m.w, m.d)
		if SettlementObb.overlap(corners, square, 0.02):
			intruders += 1
		for k in 4:
			var a := corners[k]
			var b := corners[(k + 1) % 4]
			for s in 5:
				var q := a.lerp(b, float(s) / 4.0) - center
				nearest = minf(nearest, maxf(absf(float(q.dot(axis))), absf(float(q.dot(perp)))))
	return {"intruders": intruders, "clear_m": 2.0 * nearest}
