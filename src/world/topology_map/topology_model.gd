class_name TopologyModel
extends RefCounted
## Ismeral etiketli topoloji haritasının VERİ modeli (T-028, Q-015 incelemesi). Ayrı bir "harita kaynağı" DEĞİLDİR
## (WLD-01, TEK-03): her değer `WorldData` + `WorldNetwork` + `SettlementResult`'tan çalışma zamanında hesaplanır;
## üretilmiş koordinat verisi saklanmaz/commit'lenmez. Coğrafya ONAYSIZ çalışma verisidir (ÇM/OY/ÇIKARIM); görünüm
## bunu damgalar. Saf: Node/Time/OS/global rastgelelik yok. Yer adı yoktur (CAN-01): yalnız D-kodları, D2 "Orven"
## (veriden) ve ada kimlikleri.

const STAMP := "ÇALIŞMA VERİSİ — ONAYSIZ (Q-015); koordinatlar kilitli değil"
## Yükselti kuşakları (deniz seviyesinden m): GÖSTERİM eşikleri, kanon değil (TEKNİK/ÇM).
const PLAIN_MAX_M := 40.0
const SLOPE_MAX_M := 250.0
const CONTOUR_LEVELS_M: Array[float] = [40.0, 250.0, 500.0]
## Çok küçük kontur halkaları (gürültü) çizilmez: sınır kutusu bu boydan küçükse atlanır (m).
const MIN_CONTOUR_LOOP_M := 500.0
const DENSITY_CELL_M := 250.0
const ELLIPSE_POINTS := 72
const BACKBONE_CLASSES: Array[StringName] = [&"arterial", &"collector", &"rail", &"ferry"]
const GAP_WATER_SAMPLES := 48
## Etiket konumu seçiminde harita kenarından ve kıyıdan asgari uzaklık (m).
const LABEL_EDGE_MARGIN_M := 3000.0
const LABEL_CLEARANCE_M := 1500.0
const LABEL_LAND_CLEARANCE_M := 3500.0

var world: WorldData = null
var net: WorldNetwork = null
var result: SettlementResult = null

var bounds: Rect2 = Rect2()
## Kıyı zincirleri: {"points", "closed", "landmass", "kind": &"gulf"|&"open"|&"island"}.
var coast_chains: Array[Dictionary] = []
## Kontur zincirleri: {"level_m", "points", "closed"}.
var contours: Array[Dictionary] = []
var regions: Array[RegionMark] = []
var islands: Array[IslandMark] = []
var sites: Array[SiteMark] = []
## T0 liman/ilk sanayi sahası yapıları (FLAG_PORT_YARD): {"count", "rect": Rect2, "min_shore_m"}; yerleşim yoksa 0.
var yard: Dictionary = {"count": 0, "rect": Rect2(), "min_shore_m": 0.0}
## Körfez: analyze_bay özeti + etiket konumları.
var bay: Dictionary = {}
var has_gulf: bool = false
var gulf_label_pos: Vector2 = Vector2.ZERO
var open_sea_label_pos: Vector2 = Vector2.ZERO
var mainland_label_pos: Vector2 = Vector2.ZERO
## Kara alanı özeti (km² ve ana kara kuşak payları).
var land_stats: Dictionary = {}
var building_total: int = 0
var density_w: int = 0
var density_h: int = 0
var density_counts: PackedInt32Array = PackedInt32Array()
## Yoğunluk renk ölçeği referansı: dolu hücrelerin %95'i (yapı/km²).
var density_ref_per_km2: float = 1.0
## Sınıf -> çift çift uç noktalar (dünya m) PackedVector2Array; sınıf -> kenar sayısı.
var network_segments: Dictionary = {}
var network_edge_counts: Dictionary = {}
## D1 <-> D6 en kısa su aralığı: {"valid", "a", "b" (kıyı noktaları), "water_gap_m", "centers_m", "water_fraction",
## "ferry_length_m"}.
var gap: Dictionary = {"valid": false}
## WLD-03 denetimi: ana kara dışındaki saha kimlikleri ve yasak etiket taşıyan adalar.
var sites_off_mainland: Array[StringName] = []
var islands_with_forbidden_tags: Array[StringName] = []


class RegionMark:
	extends RefCounted
	var code: StringName = &""
	var display_name: String = ""
	var region_id: int = 0
	var anchor: Vector2 = Vector2.ZERO
	var centroid: Vector2 = Vector2.ZERO
	var radius: Vector2 = Vector2.ZERO
	var rotation_deg: float = 0.0
	## Yaklaşık eliptik kapsam (dünya m); sınırlar AÇIK, veri çapa + yarıçaptır.
	var outline: PackedVector2Array = PackedVector2Array()
	var land_km2: float = 0.0
	var buildings: int = 0
	var buildings_per_km2: float = 0.0
	var mean_floors: float = 0.0


class IslandMark:
	extends RefCounted
	var id: StringName = &""
	var landmass_id: int = 0
	var position: Vector2 = Vector2.ZERO
	var area_km2: float = 0.0
	var peak_m: float = 0.0
	var tags: PackedStringArray = PackedStringArray()


class SiteMark:
	extends RefCounted
	var id: StringName = &""
	var kind: StringName = &""
	var position: Vector2 = Vector2.ZERO
	var landmass_id: int = 0
	var on_mainland: bool = false
	## Kıyıya işaretli uzaklık (m; karada +).
	var shore_m: float = 0.0
	var region_code: StringName = &""


## Modeli verilen dünya/ağ/yerleşimden hesaplar. `net` ve `result` boş olabilir (ilgili katmanlar boş kalır).
static func build(p_world: WorldData, p_net: WorldNetwork = null, p_result: SettlementResult = null) -> TopologyModel:
	var m := TopologyModel.new()
	m.world = p_world
	m.net = p_net
	m.result = p_result
	m.bounds = p_world.bounds()
	m.bay = WorldInvariants.analyze_bay(p_world)
	m._build_labels_and_gulf()
	m._build_coast()
	m._build_contours()
	m._build_land_stats()
	m._build_regions()
	m._build_islands()
	m._build_sites()
	m._build_buildings()
	m._build_network()
	m._build_gap()
	return m


## Küçük özet (determinizm/tohum karşılaştırması): sayılar ve alanlar, ayrıntı değil.
func summary() -> Dictionary:
	return {
		"land_km2": snappedf(float(land_stats.get("land_km2", 0.0)), 0.001),
		"plain_share": snappedf(float(land_stats.get("plain_share", 0.0)), 0.0001),
		"regions": regions.size(), "islands": islands.size(), "sites": sites.size(),
		"buildings": building_total, "coast_chains": coast_chains.size(),
		"contour_chains": contours.size(), "edges": network_edge_counts.duplicate(),
		"gap_m": snappedf(float(gap.get("water_gap_m", -1.0)), 0.1),
	}


## Bölge işareti (kodla).
func region_mark(code: StringName) -> RegionMark:
	for r in regions:
		if r.code == code:
			return r
	return null


func site_mark(kind: StringName) -> SiteMark:
	for s in sites:
		if s.kind == kind:
			return s
	return null


## Yoğunluk hücresi (ix, iy) yapı/km².
func density_per_km2(ix: int, iy: int) -> float:
	return float(density_counts[iy * density_w + ix]) / (DENSITY_CELL_M * DENSITY_CELL_M / 1.0e6)


# ---------------------------------------------------------------- kıyı, körfez, kontur

## Etiket konumları (veriden): körfez = körfez suyunun merkezine en yakın yeterince derin su hücresi; açık deniz =
## körfez dışı suyun merkezine en yakın derin hücre; ana kara = harita ortasına en yakın, bölge dışı (yeşil kuşak)
## iç kara hücresi. Hepsi harita kenarından `LABEL_EDGE_MARGIN_M` içeride kalır (etiket kesilmez). Aday yoksa en
## uzak hücre.
@warning_ignore("integer_division")
func _build_labels_and_gulf() -> void:
	var gulf_mask: PackedByteArray = bay["mask"]
	has_gulf = int(bay.get("cells", 0)) > 0
	var open_sum := Vector2.ZERO
	var open_n := 0
	for idx in world.heights.size():
		if world.land_mask[idx] == 0 and gulf_mask[idx] == 0:
			open_sum += world.cell_to_world(idx % world.width, idx / world.width)
			open_n += 1
	var open_center := open_sum / float(maxi(open_n, 1))
	var gulf_center: Vector2 = bay.get("centroid", bounds.get_center())
	var best := {"gulf": INF, "open": INF, "main": INF}
	var fallback := {"gulf": -INF, "open": -INF, "main": -INF}
	for idx in world.heights.size():
		var pos := world.cell_to_world(idx % world.width, idx / world.width)
		var inner := bounds.grow(-LABEL_EDGE_MARGIN_M).has_point(pos)
		var sd := world.shore_distance[idx]
		if world.land_mask[idx] == 0:
			if gulf_mask[idx] == 1:
				_consider("gulf", pos, -sd, inner and -sd >= LABEL_CLEARANCE_M, pos.distance_to(gulf_center), best,
						fallback)
			else:
				_consider("open", pos, -sd, inner and -sd >= LABEL_CLEARANCE_M, pos.distance_to(open_center), best,
						fallback)
		elif world.landmass_ids[idx] == WorldData.LANDMASS_MAINLAND:
			var free := world.region_ids[idx] == WorldData.REGION_NONE
			var score := pos.distance_to(bounds.get_center())
			var ok := inner and free and sd >= LABEL_LAND_CLEARANCE_M and score < float(best["main"])
			_consider("main", pos, sd, ok and _clear_of_water(pos, LABEL_LAND_CLEARANCE_M * 0.7), score, best,
					fallback)


## `pos` çevresinde `radius` içinde (8 yön) su yoksa true.
func _clear_of_water(pos: Vector2, radius: float) -> bool:
	for k in 8:
		var dir := Vector2.from_angle(TAU * float(k) / 8.0)
		for step in range(1, 5):
			var p := pos + dir * radius * float(step) / 4.0
			if world.is_water(p.x, p.y):
				return false
	return true


func _consider(key: String, pos: Vector2, depth: float, ok: bool, score: float, best: Dictionary,
		fallback: Dictionary) -> void:
	var target: String = {"gulf": "gulf_label_pos", "open": "open_sea_label_pos", "main": "mainland_label_pos"}[key]
	if ok and score < float(best[key]):
		best[key] = score
		set(target, pos)
	elif float(best[key]) == INF and depth > float(fallback[key]):
		fallback[key] = depth
		set(target, pos)


func _build_coast() -> void:
	var gulf_mask: PackedByteArray = bay["mask"]
	for chain in TopologyContour.trace(world, world.sea_level):
		if int(chain["landmass"]) != WorldData.LANDMASS_MAINLAND:
			coast_chains.append({"points": chain["points"], "closed": chain["closed"],
					"landmass": chain["landmass"], "kind": &"island"})
			continue
		for run in _split_by_gulf(chain, gulf_mask):
			coast_chains.append(run)


## Ana kara kıyı zincirini körfez / açık deniz parçalarına böler (parçalar uç noktayı paylaşır).
func _split_by_gulf(chain: Dictionary, gulf_mask: PackedByteArray) -> Array[Dictionary]:
	var pts: PackedVector2Array = chain["points"]
	if chain["closed"]:
		pts = pts.duplicate()
		pts.append(pts[0])
	var runs: Array[Dictionary] = []
	var cur := PackedVector2Array()
	var cur_kind: StringName = &""
	for k in pts.size() - 1:
		var kind := _segment_kind(pts[k], pts[k + 1], gulf_mask)
		if kind != cur_kind and not cur.is_empty():
			cur.append(pts[k])
			runs.append({"points": cur, "closed": false, "landmass": chain["landmass"], "kind": cur_kind})
			cur = PackedVector2Array()
		if cur.is_empty():
			cur_kind = kind
		cur.append(pts[k])
	if not cur.is_empty():
		cur.append(pts[pts.size() - 1])
		runs.append({"points": cur, "closed": false, "landmass": chain["landmass"], "kind": cur_kind})
	return runs


## Parça orta noktasının 3x3 komşuluğunda körfez suyu varsa körfez kıyısı, yoksa açık deniz kıyısı.
func _segment_kind(a: Vector2, b: Vector2, gulf_mask: PackedByteArray) -> StringName:
	var mid := (a + b) * 0.5
	var ci := clampi(int(round((mid.x - world.origin.x) / world.cell_size)), 0, world.width - 1)
	var cj := clampi(int(round((mid.y - world.origin.y) / world.cell_size)), 0, world.height - 1)
	for dj in range(-1, 2):
		for di in range(-1, 2):
			var i := clampi(ci + di, 0, world.width - 1)
			var j := clampi(cj + dj, 0, world.height - 1)
			var idx := j * world.width + i
			if gulf_mask[idx] == 1 and world.land_mask[idx] == 0:
				return &"gulf"
	return &"open"


func _build_contours() -> void:
	for level in CONTOUR_LEVELS_M:
		for chain in TopologyContour.trace(world, world.sea_level + level):
			var pts: PackedVector2Array = chain["points"]
			if chain["closed"] and _extent(pts) < MIN_CONTOUR_LOOP_M:
				continue
			contours.append({"level_m": level, "points": pts, "closed": chain["closed"]})


static func _extent(pts: PackedVector2Array) -> float:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in pts:
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
	return maxf(hi.x - lo.x, hi.y - lo.y)


func _build_land_stats() -> void:
	var cell_km2 := world.cell_size * world.cell_size / 1.0e6
	var land := 0
	var mainland := 0
	var plain := 0
	var slope := 0
	var ridge := 0
	for idx in world.heights.size():
		if world.land_mask[idx] == 0:
			continue
		land += 1
		if world.landmass_ids[idx] != WorldData.LANDMASS_MAINLAND:
			continue
		mainland += 1
		var e := world.heights[idx] - world.sea_level
		if e < PLAIN_MAX_M:
			plain += 1
		elif e < SLOPE_MAX_M:
			slope += 1
		else:
			ridge += 1
	var denom := float(maxi(mainland, 1))
	land_stats = {
		"land_km2": land * cell_km2, "mainland_km2": mainland * cell_km2,
		"island_km2": (land - mainland) * cell_km2,
		"plain_km2": plain * cell_km2, "slope_km2": slope * cell_km2, "ridge_km2": ridge * cell_km2,
		"plain_share": plain / denom, "slope_share": slope / denom, "ridge_share": ridge / denom,
		"gulf_km2": float(bay.get("area_km2", 0.0)),
	}


# ---------------------------------------------------------------- işaretler

func _build_regions() -> void:
	for r in world.regions:
		var mark := RegionMark.new()
		mark.code = r.code
		mark.display_name = r.display_name
		mark.region_id = r.id
		mark.anchor = r.anchor
		mark.centroid = r.centroid
		mark.radius = r.radius
		mark.rotation_deg = r.rotation_deg
		mark.outline = _ellipse(r.anchor, r.radius, r.rotation_deg)
		mark.land_km2 = r.cell_count * world.cell_size * world.cell_size / 1.0e6
		regions.append(mark)


static func _ellipse(center: Vector2, radius: Vector2, rotation_deg: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var rot := deg_to_rad(rotation_deg)
	for k in ELLIPSE_POINTS:
		var a := TAU * float(k) / float(ELLIPSE_POINTS)
		out.append(center + Vector2(cos(a) * radius.x, sin(a) * radius.y).rotated(rot))
	return out


func _build_islands() -> void:
	for isl in world.islands:
		var mark := IslandMark.new()
		mark.id = isl.id
		mark.landmass_id = isl.landmass_id
		mark.position = isl.centroid
		mark.area_km2 = isl.area_m2 / 1.0e6
		mark.peak_m = isl.peak_m
		mark.tags = isl.t0_tags
		islands.append(mark)
		for tag in isl.t0_tags:
			if WorldInvariants.FORBIDDEN_ISLAND_TAGS.has(tag):
				islands_with_forbidden_tags.append(isl.id)
				break


func _build_sites() -> void:
	for s in world.sites:
		var mark := SiteMark.new()
		mark.id = s.id
		mark.kind = s.kind
		mark.position = s.position
		mark.landmass_id = world.landmass_at(s.position.x, s.position.y)
		mark.on_mainland = mark.landmass_id == WorldData.LANDMASS_MAINLAND
		mark.shore_m = world.shore_distance[world.world_to_index(s.position.x, s.position.y)]
		mark.region_code = world.region_code_at(s.position.x, s.position.y)
		sites.append(mark)
		if not mark.on_mainland:
			sites_off_mainland.append(s.id)


## Yerleşim sonucundan: bölge başına yapı, yoğunluk ızgarası, liman sahası.
func _build_buildings() -> void:
	density_w = int(ceil(world.size.x / DENSITY_CELL_M))
	density_h = int(ceil(world.size.y / DENSITY_CELL_M))
	density_counts.resize(density_w * density_h)
	if result == null:
		return
	var cols := result.columns
	building_total = cols.count
	var per_region := {}
	var floors := {}
	var yard_lo := Vector2(INF, INF)
	var yard_hi := Vector2(-INF, -INF)
	var yard_count := 0
	var yard_shore := INF
	for i in cols.count:
		var x := cols.x[i]
		var z := cols.z[i]
		var cx := clampi(int((x - world.origin.x) / DENSITY_CELL_M), 0, density_w - 1)
		var cy := clampi(int((z - world.origin.y) / DENSITY_CELL_M), 0, density_h - 1)
		density_counts[cy * density_w + cx] += 1
		var rid := world.region_at(x, z)
		per_region[rid] = int(per_region.get(rid, 0)) + 1
		floors[rid] = int(floors.get(rid, 0)) + cols.floors[i]
		if (cols.flags[i] & BuildingColumns.FLAG_PORT_YARD) != 0:
			yard_count += 1
			yard_lo = Vector2(minf(yard_lo.x, x), minf(yard_lo.y, z))
			yard_hi = Vector2(maxf(yard_hi.x, x), maxf(yard_hi.y, z))
			yard_shore = minf(yard_shore, world.shore_distance[world.world_to_index(x, z)])
	for mark in regions:
		mark.buildings = int(per_region.get(mark.region_id, 0))
		mark.buildings_per_km2 = mark.buildings / maxf(mark.land_km2, 0.001)
		mark.mean_floors = float(floors.get(mark.region_id, 0)) / maxf(float(mark.buildings), 1.0)
	if yard_count > 0:
		yard = {"count": yard_count, "rect": Rect2(yard_lo, yard_hi - yard_lo), "min_shore_m": yard_shore}
	density_ref_per_km2 = _density_reference()


func _density_reference() -> float:
	var filled: Array[int] = []
	for c in density_counts:
		if c > 0:
			filled.append(c)
	if filled.is_empty():
		return 1.0
	filled.sort()
	var q := filled[int(float(filled.size() - 1) * 0.95)]
	return maxf(float(q) / (DENSITY_CELL_M * DENSITY_CELL_M / 1.0e6), 1.0)


# ---------------------------------------------------------------- ağ ve D1 <-> D6

func _build_network() -> void:
	for cls in WorldRoadEdge.ALL_CLASSES:
		network_segments[cls] = PackedVector2Array()
		network_edge_counts[cls] = 0
	if net == null:
		return
	for eid in net.edges:
		var e: WorldRoadEdge = net.edges[eid]
		var segs: PackedVector2Array = network_segments[e.road_class]
		segs.append(net.node_pos(e.a))
		segs.append(net.node_pos(e.b))
		network_segments[e.road_class] = segs
		network_edge_counts[e.road_class] = int(network_edge_counts[e.road_class]) + 1


@warning_ignore("integer_division")
func _build_gap() -> void:
	var d1 := world.region_by_code(&"D1")
	var d6 := world.region_by_code(&"D6")
	if d1 == null or d6 == null:
		return
	var a_cells := _coast_cells(d1.id)
	var b_cells := _coast_cells(d6.id)
	if a_cells.is_empty() or b_cells.is_empty():
		return
	var best := INF
	var best_a := 0
	var best_b := 0
	for ia in a_cells:
		var pa := world.cell_to_world(ia % world.width, ia / world.width)
		for ib in b_cells:
			var d := pa.distance_to(world.cell_to_world(ib % world.width, ib / world.width))
			if d < best:
				best = d
				best_a = ia
				best_b = ib
	var ca := world.cell_to_world(best_a % world.width, best_a / world.width)
	var cb := world.cell_to_world(best_b % world.width, best_b / world.width)
	var dir := (cb - ca).normalized()
	var sa := maxf(world.shore_distance[best_a], 0.0)
	var sb := maxf(world.shore_distance[best_b], 0.0)
	var shore_a := ca + dir * sa
	var shore_b := cb - dir * sb
	var water := 0
	for k in GAP_WATER_SAMPLES:
		var p := shore_a.lerp(shore_b, (float(k) + 0.5) / float(GAP_WATER_SAMPLES))
		if world.is_water(p.x, p.y):
			water += 1
	var ferry_len := 0.0
	if net != null:
		for eid in net.edges:
			var e: WorldRoadEdge = net.edges[eid]
			if e.road_class == WorldRoadEdge.CLASS_FERRY:
				ferry_len += e.length
	gap = {"valid": true, "a": shore_a, "b": shore_b, "centers_m": best,
			"water_gap_m": maxf(best - sa - sb, 0.0), "water_fraction": float(water) / float(GAP_WATER_SAMPLES),
			"ferry_length_m": ferry_len}


## Bölgenin kıyıdaki kara hücreleri (4-komşudan en az biri su).
@warning_ignore("integer_division")
func _coast_cells(region_id: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	var w := world.width
	for idx in world.heights.size():
		if world.land_mask[idx] == 0 or world.region_ids[idx] != region_id:
			continue
		var i := idx % w
		var j := idx / w
		var wet := false
		if i > 0 and world.land_mask[idx - 1] == 0:
			wet = true
		elif i < w - 1 and world.land_mask[idx + 1] == 0:
			wet = true
		elif j > 0 and world.land_mask[idx - w] == 0:
			wet = true
		elif j < world.height - 1 and world.land_mask[idx + w] == 0:
			wet = true
		if wet:
			out.append(idx)
	return out
