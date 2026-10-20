class_name T0Settlement
extends RefCounted
## T0 yerleşim üreteci v0 (T-005; WLD-03/04/08, VIS-02/04, CAN-03): ağ parselleri + `settlement.json` kuralları +
## `kit_manifest.json` modül tablosu + tohum -> BuildingColumns (T0'da MEVCUT yapı stoğu). Saf: Node/Time/OS/global
## rastgelelik yok; her akış (sokak cephesi grubu) `NetworkRules.stream_seed` ile bağımsız tohumlanır.
##
## Koordinat gömme yok: bölge dokusu (zone) parselin `region_code`/`fabric`ından, bölge ayak izine normalize
## uzaklıktan ve kıyı uzaklığından türer; saat kulesi bölge merkez düğümüne en yakın uygun bloğa konur.
## Doluluk (hangi parsel dolu) parselin kendi `detail` değerinden türer, yerleşim tohumundan BAĞIMSIZDIR (topoloji
## sabit); tohum yalnız modül/duvar/çatı/parlaklık ayrıntısını belirler.
## Yerleşim kuralı (kit spec §3.3/§7.1): sokak cephesi grupları cephe boyunca sırayla doldurulur (bitişik nizam: aynı
## lotta birden çok birim, aralık toleransı), komşu (mesh+duvar) aynı olmaz, 9'lu pencerede >= 3 mesh/duvar, kat
## sayısı bölge merkezine ve ana caddeye yaklaştıkça artar, saat kulesi çerçevesinde en yüksek yapı sınırlıdır.
## T0 stoğu sim başlangıç durumudur: parsel sahipliği/ağ durumuna YAZILMAZ (yalnız BuildingColumns), aktör kararı
## bypass'ı değildir (CAN-03).

const U32 := 4294967296.0
const FRONT_PROBE_M := 0.05
const MID_PROBE_M := 9.0
const WIDE_TRIES := 3
const ROOF_CELL_M := 500.0
const TILE_OVER_CAP_FACTOR := 0.03
const CIVIC_CHAIN_MAX := 6
const CIVIC_TOUCH_M := 0.6
const ROW_ATTEMPTS_DIV := 2
const FRAME_RADIUS_PAD_M := 15.0
## Kıyı uzaklığı bu eşiğin (+ yapı yarıçapı) üstündeyse yapı suya değemez (hücre 100 m; bilineer yüzey payı).
const SHORE_FAST_PATH_M := 150.0

var _world: WorldData = null
var _net: WorldNetwork = null
var _rules: SettlementRules = null
var _seed: int = 0
var _res: SettlementResult = null
var _cols: BuildingColumns = null
var _zone_of: Dictionary = {}
var _t_of: Dictionary = {}
var _footprints: Dictionary = {}
var _used_cells: Dictionary = {}
var _plaza_corners: PackedVector2Array = PackedVector2Array()
var _tower_pos: Vector2 = Vector2.ZERO
var _tower_active: bool = false
var _frame_cap_top: float = INF
var _frame_radius: float = 0.0
var _frame_target: float = 4.6
var _stats: Dictionary = {}
## Sokak yönü ile lot `u` ekseni ters mi (birim sırası sokak sırasına çevrilir).
var _flip: bool = false
var _cur_attempts: int = 8
var _diverge_boost: float = 2.0
var _diverge_dist: float = 1.5
## 500 m hücre -> Vector2(kiremit alanı, toplam alan): kiremit payı bütçesi (zone.tile_cap).
var _roof_cells: Dictionary = {}
var _margin: float = 0.15
var _back_margin: float = 0.6
var _gap_tol: float = 1.0
var _attempts: int = 8
var _window: int = 8
var _min_meshes: int = 3
var _min_walls: int = 3
var _floor_std: float = 1.0
var _floor_window: int = 8
var _parapet: float = 0.9
var _min_frontage: float = 6.5
var _accept_score: float = 0.75
## Çok parselli yapıya katılan (başka yapı almayacak) parseller.
var _skip: Dictionary = {}


## Sözleşme girişi (T-005 ORTAK ARAYÜZ): yalnız BuildingColumns döndürür.
static func generate(world: WorldData, net: WorldNetwork, kit_manifest: Dictionary, settle_seed: int,
		control: Dictionary) -> BuildingColumns:
	return generate_detailed(world, net, kit_manifest, settle_seed, control).columns


## Tanı bilgisiyle (bölge dokusu, meydan, kule dizini, sayaçlar) birlikte üretim.
static func generate_detailed(world: WorldData, net: WorldNetwork, kit_manifest: Dictionary, settle_seed: int,
		control: Dictionary) -> SettlementResult:
	var gen := T0Settlement.new()
	return gen._run(world, net, kit_manifest, settle_seed, control)


class _Hist:
	extends RefCounted
	## Sokak cephesi grubunda son yerleştirilen birimlerin özeti (komşu/pencere/kat çeşitliliği kuralları).
	var mods: PackedInt32Array = PackedInt32Array()
	var walls: PackedInt32Array = PackedInt32Array()
	var res_floors: PackedInt32Array = PackedInt32Array()

	func push(mod: int, wall: int, floors: int, residential: bool) -> void:
		mods.append(mod)
		walls.append(wall)
		if residential:
			res_floors.append(floors)


func _run(world: WorldData, net: WorldNetwork, kit_manifest: Dictionary, settle_seed: int,
		control: Dictionary) -> SettlementResult:
	_world = world
	_net = net
	_seed = settle_seed
	_res = SettlementResult.new()
	_res.net = net
	_cols = _res.columns
	var errors := SettlementRules.validate(control, kit_manifest)
	if not errors.is_empty():
		push_error("T0Settlement: settlement.json geçersiz: %s" % "; ".join(errors))
		return _res
	_rules = SettlementRules.from_control(control, kit_manifest)
	_res.rules = _rules
	var pl := _rules.placement
	_margin = float(pl["side_margin_m"])
	_back_margin = float(pl["back_margin_m"])
	_gap_tol = float(pl["gap_tol_m"])
	_attempts = int(pl["pack_attempts"])
	_window = int(pl["variety_window"])
	_min_meshes = int(pl["min_window_meshes"])
	_min_walls = int(pl["min_window_walls"])
	_floor_std = float(pl["floor_std_min"])
	_floor_window = int(pl["floor_window"])
	_parapet = float(pl["parapet_m"])
	_min_frontage = float(pl["min_frontage_m"])
	_accept_score = float(pl.get("accept_score", 0.75))
	_diverge_boost = float(pl.get("floor_diverge_boost", 2.0))
	_diverge_dist = float(pl.get("floor_diverge_dist_m", 1.5))
	_stats = {"parcels": 0, "zoned": 0, "lottery_built": 0, "units": 0, "dropped_water": 0, "dropped_slope": 0,
			"dropped_fit": 0, "dropped_plaza": 0, "wide": 0, "consumed": 0, "farms": 0}
	for fp in net.rules.footprints:
		_footprints[String(fp.id)] = fp
	var ids := PackedInt32Array(net.parcels.keys())
	ids.sort()
	var zoned := PackedInt32Array()
	for pid in ids:
		var p: WorldParcel = net.parcels[pid]
		_stats["parcels"] += 1
		var zname := _zone_for(p)
		if zname != &"" and _rules.zone(zname) != null:
			_zone_of[pid] = zname
			zoned.append(pid)
	_stats["zoned"] = zoned.size()
	_res.zone_by_parcel = _zone_of
	_find_plaza()
	for group in SettlementGroups.build(net, zoned):
		_process_group(group)
	_add_tower()
	_repair_neighbours()
	_res.stats = _stats
	return _res


## Komşu kuralı onarımı (kit §3.3): sokak sırasında (SettlementStats ile AYNI sıralama) ardışık iki yapı aynı (mesh +
## duvar) ise ikincisinin duvarı, komşularının duvarından farklı bir izinli duvarla değiştirilir. Yerleşim sırası ile
## sokak sırası eğik lot sınırlarında ayrışabildiğinden kural burada kesin sağlanır. Sanayi avlusu/tarla hariç.
func _repair_neighbours() -> void:
	var skip := {&"yard": true, &"farm": true}
	var repaired := 0
	for g: Dictionary in SettlementStats.street_groups(_res):
		var order: PackedInt32Array = g["order"]
		var seq := PackedInt32Array()
		for i in order:
			if not skip.has(_res.zone_of_building(i)):
				seq.append(i)
		for k in range(1, seq.size()):
			var a := seq[k - 1]
			var b := seq[k]
			if _cols.module_idx[a] != _cols.module_idx[b] or _cols.wall_row[a] != _cols.wall_row[b]:
				continue
			var m := _rules.modules[_cols.module_idx[b]]
			var next_mod := -1
			var next_wall := -1
			if k + 1 < seq.size():
				next_mod = _cols.module_idx[seq[k + 1]]
				next_wall = _cols.wall_row[seq[k + 1]]
			for row in m.wall_rows:
				if row != _cols.wall_row[a] and not (next_mod == m.idx and row == next_wall):
					_cols.wall_row[b] = row
					repaired += 1
					break
	_stats["repaired_neighbours"] = repaired


# ---------------------------------------------------------------- bölge dokusu (zone)

func _zone_for(p: WorldParcel) -> StringName:
	var fz := str(_rules.fabric_zones.get(String(p.fabric), ""))
	if not fz.is_empty():
		return StringName(fz)
	var code := String(p.region_code)
	if not _rules.regions.has(code):
		return &""
	var fp: NetworkFootprint = _footprints.get(code, null)
	var t := 1.0 if fp == null else fp.norm_dist(p.centroid)
	_t_of[p.id] = t
	var shore := float(_world.shore_distance[_world.world_to_index(p.centroid.x, p.centroid.y)])
	for ov: Dictionary in _rules.overrides:
		if str(ov["region"]) == code and shore <= float(ov["max_shore_m"]):
			return StringName(str(ov["zone"]))
	for band: Dictionary in (_rules.regions[code] as Dictionary)["bands"]:
		if t <= float(band["max_t"]):
			return StringName(str(band["zone"]))
	return &""


func _lottery(p: WorldParcel, label: String) -> float:
	return float(NetworkRules.stream_seed(p.detail, label)) / U32


func _occupied(p: WorldParcel, zone: SettlementZone) -> bool:
	var prob := 0.0
	if zone.fill_p >= 0.0:
		prob = zone.fill_p
	elif zone.name == &"farm":
		prob = float(_rules.farm.get("house_p", 0.3))
	else:
		var rc: Dictionary = _rules.regions[String(p.region_code)]
		var t := clampf(float(_t_of.get(p.id, 1.0)), 0.0, 1.0)
		prob = lerpf(float(rc["fill"]["center"]), float(rc["fill"]["edge"]), t)
	return _lottery(p, "occupancy") < prob


func _target_floors(p: WorldParcel, zone: SettlementZone, road_class: StringName) -> float:
	var rc: Dictionary = _rules.regions.get(String(p.region_code), {})
	if rc.is_empty():
		return 2.0
	var t := clampf(float(_t_of.get(p.id, 1.0)), 0.0, 1.0)
	var base := lerpf(float(rc["floors"]["center"]), float(rc["floors"]["edge"]), t)
	return base + zone.floors_shift + float(_rules.main_street_bonus.get(String(road_class), 0.0))


# ---------------------------------------------------------------- saat kulesi meydanı

func _find_plaza() -> void:
	var tw := _rules.tower
	if not bool(tw.get("enabled", true)):
		return
	var code := StringName(str(tw["region"]))
	if not _net.hubs.has(code):
		return
	var hub_pos := _net.node_pos(int(_net.hubs[code]))
	var scored: Array[Vector2] = []
	for bid: int in _net.blocks:
		var b: WorldBlock = _net.blocks[bid]
		if b.kind != WorldBlock.KIND_PARCELIZED or b.region_code != code or b.buildable.size() < 3:
			continue
		scored.append(Vector2(NetworkGeometry.centroid(b.buildable).distance_to(hub_pos), bid))
	scored.sort_custom(func(l: Vector2, r: Vector2) -> bool: return l.x < r.x or (l.x == r.x and l.y < r.y))
	var size := Vector2(float(tw["size_m"][0]), float(tw["size_m"][1]))
	var tried := 0
	for item in scored:
		if tried >= int(tw.get("candidate_blocks", 40)):
			break
		tried += 1
		var b: WorldBlock = _net.blocks[int(item.y)]
		var center := NetworkGeometry.centroid(b.buildable)
		var axis := _longest_edge_dir(b.buildable)
		var perp := Vector2(-axis.y, axis.x)
		var probe := _rect_corners(center, axis, perp, size)
		var ok := not _world.is_water(center.x, center.y)
		for q in _rect_probe_points(center, axis, perp, size):
			ok = ok and NetworkGeometry.point_in_polygon(q, b.buildable)
		if ok:
			_res.plaza = {"block_id": b.id, "center": center, "axis": axis, "size": size}
			_plaza_corners = probe
			_tower_pos = center
			_tower_active = true
			_frame_radius = float(tw["frame_radius_m"])
			_frame_cap_top = float(tw["height_m"]) / float(tw["frame_ratio"][0])
			_frame_target = float(tw["frame_floors_target"])
			return


static func _longest_edge_dir(poly: PackedVector2Array) -> Vector2:
	var best := 0.0
	var dir := Vector2.RIGHT
	var count := poly.size()
	for i in count:
		var d := poly[(i + 1) % count] - poly[i]
		if d.length() > best + 1.0e-9:
			best = d.length()
			dir = d / best
	return dir


static func _rect_corners(center: Vector2, axis: Vector2, perp: Vector2, size: Vector2) -> PackedVector2Array:
	var a := axis * (size.x * 0.5)
	var b := perp * (size.y * 0.5)
	return PackedVector2Array([center - a - b, center + a - b, center + a + b, center - a + b])


static func _rect_probe_points(center: Vector2, axis: Vector2, perp: Vector2, size: Vector2) -> PackedVector2Array:
	var out := _rect_corners(center, axis, perp, size)
	var a := axis * (size.x * 0.5)
	var b := perp * (size.y * 0.5)
	out.append_array(PackedVector2Array([center - a, center + a, center - b, center + b]))
	return out


func _add_tower() -> void:
	if not _tower_active:
		return
	var tw := _rules.tower
	var m := _rules.module(str(tw["module"]))
	var block: WorldBlock = _net.blocks[int(_res.plaza["block_id"])]
	var best := -1
	var best_d := INF
	for pid in block.parcel_ids:
		var d := (_net.parcels[pid] as WorldParcel).centroid.distance_to(_tower_pos)
		if d < best_d:
			best_d = d
			best = pid
	if best < 0:
		return
	var axis: Vector2 = _res.plaza["axis"]
	var face := Vector2(-axis.y, axis.x)
	var yaw := atan2(face.x, face.y)
	_res.tower_index = _cols.add(best, m.idx, _tower_pos.x, _tower_pos.y, yaw, m.floors,
			_rules.row_of(str(tw["wall"])), _rules.row_of(str(tw["roof"])), _rules.row_of(str(tw["accent"])), 128,
			BuildingColumns.FLAG_HERITAGE | BuildingColumns.FLAG_LANDMARK, m.era)


# ---------------------------------------------------------------- sokak cephesi grubu

func _process_group(group: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = NetworkRules.stream_seed(_seed, "settle:g:%d:%d" % [int(group["edge"]), int(group["side"])])
	var hist := _Hist.new()
	var back_hist := _Hist.new()
	var parcels: PackedInt32Array = group["parcels"]
	for k in parcels.size():
		var pid := parcels[k]
		var p: WorldParcel = _net.parcels[pid]
		if _world.landmass_at(p.centroid.x, p.centroid.y) != WorldData.LANDMASS_MAINLAND:
			continue
		var zone := _rules.zone(_zone_of[pid])
		if not _occupied(p, zone):
			continue
		# Doluluk kurası tohumdan ve çok parselli yapı tüketiminden bağımsız kaydedilir (topoloji sabit).
		_stats["lottery_built"] += 1
		_res.lottery_parcels.append(pid)
		if _skip.has(pid):
			continue
		var lot := SettlementLot.from_parcel(p)
		if lot == null or lot.front_len < _min_frontage:
			continue
		var edge: WorldRoadEdge = _net.edges[p.frontage_edge]
		_flip = lot.u.dot((_net.node_pos(edge.b) - _net.node_pos(edge.a)).normalized()) < 0.0
		if zone.name == &"farm":
			_place_farm(p, lot, zone, rng, hist)
		elif zone.wide_p > 0.0 and _lottery(p, "wide") < zone.wide_p and _place_wide(parcels, k, lot, zone, rng, hist):
			continue
		else:
			_place_rows(p, lot, zone, edge.road_class, rng, hist, back_hist)


func _place_rows(p: WorldParcel, lot: SettlementLot, zone: SettlementZone, road_class: StringName,
		rng: RandomNumberGenerator, hist: _Hist, back_hist: _Hist) -> void:
	var v_start := rng.randf_range(zone.setback_min, zone.setback_max)
	for row in zone.rows:
		if row > 0:
			if rng.randf() > zone.second_row_p:
				break
			v_start += rng.randf_range(zone.row_gap_min, zone.row_gap_max)
		_cur_attempts = _attempts if row == 0 else maxi(2, _attempts / ROW_ATTEMPTS_DIV)
		var depth := _place_row(p, lot, zone, road_class, v_start, rng, hist if row == 0 else back_hist)
		if depth <= 0.0:
			break
		v_start += depth


## Bir derinlik sırasını doldurur; yerleştirilen en derin birimin derinliğini döndürür (yoksa 0).
func _place_row(p: WorldParcel, lot: SettlementLot, zone: SettlementZone, road_class: StringName, v_start: float,
		rng: RandomNumberGenerator, hist: _Hist) -> float:
	var margin := _margin
	var back_limit := lot.v_max - _back_margin
	var front := lot.interval_at(v_start + FRONT_PROBE_M)
	var mid := lot.interval_at(minf(v_start + MID_PROBE_M, back_limit))
	if front.x > front.y or mid.x > mid.y:
		return 0.0
	var lo := maxf(front.x, mid.x) + margin
	var hi := minf(front.y, mid.y) - margin
	var avail := hi - lo
	var main_street := road_class == WorldRoadEdge.CLASS_ARTERIAL or road_class == WorldRoadEdge.CLASS_COLLECTOR
	var center_w := lot.to_world((lo + hi) * 0.5, v_start + 5.0)
	var near_tower := _tower_active and center_w.distance_to(_tower_pos) <= _frame_radius + FRAME_RADIUS_PAD_M
	var target := _frame_target if near_tower else _target_floors(p, zone, road_class)
	var tile_over := zone.tile_cap < 1.0 and _tile_share(center_w) > zone.tile_cap
	var recent_floors := -1.0
	if hist.res_floors.size() >= 4:
		recent_floors = 0.0
		var from := maxi(0, hist.res_floors.size() - _floor_window)
		for q in range(from, hist.res_floors.size()):
			recent_floors += float(hist.res_floors[q])
		recent_floors /= float(hist.res_floors.size() - from)
	var cands: Array[SettlementModule] = []
	var weights := PackedFloat32Array()
	var min_w := INF
	var parapet := _parapet
	for ci in zone.candidates.size():
		var m := zone.candidates[ci]
		if m.w > avail or v_start + m.d > back_limit:
			continue
		if near_tower and m.top_m(parapet) > _frame_cap_top:
			continue
		var w := zone.base_weights[ci]
		if m.gf:
			w *= zone.gf_main if main_street else zone.gf_local
		var df := (float(m.floors) - target) / zone.floors_sigma
		w *= exp(-0.5 * df * df)
		if tile_over and m.tile_roof:
			w *= TILE_OVER_CAP_FACTOR
		if recent_floors >= 0.0 and _is_residential(m):
			var spread := absf(float(m.floors) - recent_floors)
			if spread >= _diverge_dist:
				w *= _diverge_boost
			elif spread < 0.7:
				w *= 1.0 / _diverge_boost
		if w <= 1.0e-6:
			continue
		cands.append(m)
		weights.append(w)
		min_w = minf(min_w, m.w)
	if cands.is_empty():
		return 0.0
	var plan := _best_plan(cands, weights, min_w, avail, zone, hist, lot, v_start, rng)
	if plan.is_empty():
		return 0.0
	return _commit_plan(p, lot, zone, plan, lo, hi, v_start, rng, hist)


## En iyi aday dizisi: [{"m": SettlementModule, "wall": int}, ...] (kural ihlal puanı en düşük).
func _best_plan(cands: Array[SettlementModule], weights: PackedFloat32Array, min_w: float, avail: float,
		zone: SettlementZone, hist: _Hist, lot: SettlementLot, v_start: float, rng: RandomNumberGenerator) -> Array:
	var best: Array = []
	var best_score := INF
	var cell := _cell_of(lot.to_world(lot.front_len * 0.5, v_start))
	for attempt in _cur_attempts:
		var seq := _sample_sequence(cands, weights, min_w, avail, zone, _gap_tol, rng)
		if seq.is_empty():
			continue
		if _flip:
			seq.reverse()
		var plan: Array = []
		var score := 0.0
		var total := 0.0
		var win_mods := hist.mods.slice(maxi(0, hist.mods.size() - _window))
		var win_walls := hist.walls.slice(maxi(0, hist.walls.size() - _window))
		var win_floors := hist.res_floors.slice(maxi(0, hist.res_floors.size() - _floor_window))
		for m: SettlementModule in seq:
			var wall := _pick_wall(m, win_mods, win_walls, cell, rng, zone)
			score += _unit_penalty(m, wall, win_mods, win_walls, win_floors, cell, zone)
			win_mods.append(m.idx)
			win_walls.append(wall)
			if _is_residential(m):
				win_floors.append(m.floors)
			plan.append({"m": m, "wall": wall})
			total += m.w
		if zone.adjacent:
			score += maxf(0.0, avail - total - _gap_tol) * 0.8
		if score < best_score:
			best_score = score
			best = plan
		if best_score <= _accept_score:
			break
	return best


func _sample_sequence(cands: Array[SettlementModule], weights: PackedFloat32Array, min_w: float, avail: float,
		zone: SettlementZone, tol: float, rng: RandomNumberGenerator) -> Array[SettlementModule]:
	var seq: Array[SettlementModule] = []
	var remaining := avail
	var gap := zone.gap_min
	var count := cands.size()
	var adjusted := PackedFloat32Array()
	adjusted.resize(count)
	while seq.size() < zone.units_max:
		var extra := gap if not seq.is_empty() else 0.0
		var total := 0.0
		for ci in count:
			var need := cands[ci].w + extra
			if need > remaining:
				adjusted[ci] = 0.0
				continue
			var w := weights[ci]
			if zone.adjacent:
				var leftover := remaining - need
				if leftover <= tol:
					w *= 3.0
				elif leftover < min_w + gap:
					w *= 0.2
			adjusted[ci] = w
			total += w
		if total <= 0.0:
			break
		var r := rng.randf() * total
		var pick := -1
		for ci in count:
			var w := adjusted[ci]
			if w <= 0.0:
				continue
			pick = ci
			r -= w
			if r <= 0.0:
				break
		var chosen := cands[pick]
		seq.append(chosen)
		remaining -= chosen.w + (gap if seq.size() > 1 else 0.0)
		if not zone.adjacent and rng.randf() < 0.55:
			break
	return seq


func _pick_wall(m: SettlementModule, win_mods: PackedInt32Array, win_walls: PackedInt32Array, cell: Vector2i,
		rng: RandomNumberGenerator, zone: SettlementZone) -> int:
	var prev_mod := -1 if win_mods.is_empty() else win_mods[win_mods.size() - 1]
	var prev_wall := -1 if win_walls.is_empty() else win_walls[win_walls.size() - 1]
	var need_walls := zone.min_walls if zone.min_walls > 0 else _min_walls
	var need_variety := _distinct_tail(win_walls, _window) < need_walls
	var used: Dictionary = _used_cells.get(cell, {})
	var total := 0.0
	var ws := PackedFloat32Array()
	for row in m.wall_rows:
		var w := float(_rules.wall_weights.get(row, 1.0))
		if prev_mod == m.idx and row == prev_wall:
			w = 0.0
		elif need_variety and _tail_has(win_walls, row, _window):
			w *= 0.25
		if zone.unique_combo and used.has(m.idx * 64 + row):
			w *= 0.3
		ws.append(w)
		total += w
	if total <= 0.0:
		return m.wall_rows[0]
	var r := rng.randf() * total
	for i in ws.size():
		r -= ws[i]
		if r <= 0.0:
			return m.wall_rows[i]
	return m.wall_rows[m.wall_rows.size() - 1]


## Kural ihlal puanı (0 = temiz): 9'lu pencere çeşitliliği, kat çeşitliliği, 200 m hücrede yinelenen kombinasyon.
func _unit_penalty(m: SettlementModule, wall: int, win_mods: PackedInt32Array, win_walls: PackedInt32Array,
		win_floors: PackedInt32Array, cell: Vector2i, zone: SettlementZone) -> float:
	var score := 0.0
	if win_mods.size() >= _window:
		var need_meshes := zone.min_meshes if zone.min_meshes > 0 else _min_meshes
		var need_walls := zone.min_walls if zone.min_walls > 0 else _min_walls
		if _distinct_tail_with(win_mods, m.idx, _window) < need_meshes:
			score += 4.0
		if _distinct_tail_with(win_walls, wall, _window) < need_walls:
			score += 4.0
	if _is_residential(m) and win_floors.size() >= 5 and _std_tail_with(win_floors, m.floors, _floor_window) < _floor_std:
		score += 3.0
	if zone.unique_combo and (_used_cells.get(cell, {}) as Dictionary).has(m.idx * 64 + wall):
		score += 0.7
	if not win_mods.is_empty() and win_mods[win_mods.size() - 1] == m.idx \
			and win_walls[win_walls.size() - 1] == wall:
		score += 50.0
	return score


## Dizinin son `n` elemanındaki benzersiz değer sayısı.
static func _distinct_tail(arr: PackedInt32Array, n: int) -> int:
	var start := maxi(0, arr.size() - n)
	var count := 0
	for i in range(start, arr.size()):
		var dup := false
		for j in range(start, i):
			if arr[j] == arr[i]:
				dup = true
				break
		if not dup:
			count += 1
	return count


## Son `n - 1` eleman + `extra` içindeki benzersiz değer sayısı (aday dahil pencere).
static func _distinct_tail_with(arr: PackedInt32Array, extra: int, n: int) -> int:
	var start := maxi(0, arr.size() - (n - 1))
	var count := 1
	for i in range(start, arr.size()):
		if arr[i] == extra:
			continue
		var dup := false
		for j in range(start, i):
			if arr[j] == arr[i]:
				dup = true
				break
		if not dup:
			count += 1
	return count


static func _tail_has(arr: PackedInt32Array, value: int, n: int) -> bool:
	for i in range(maxi(0, arr.size() - n), arr.size()):
		if arr[i] == value:
			return true
	return false


## Son `n - 1` kat + `extra` kat standart sapması.
static func _std_tail_with(arr: PackedInt32Array, extra: int, n: int) -> float:
	var start := maxi(0, arr.size() - (n - 1))
	var count := float(arr.size() - start + 1)
	var mean := float(extra)
	for i in range(start, arr.size()):
		mean += float(arr[i])
	mean /= count
	var acc := (float(extra) - mean) * (float(extra) - mean)
	for i in range(start, arr.size()):
		acc += (float(arr[i]) - mean) * (float(arr[i]) - mean)
	return sqrt(acc / count)


static func _is_residential(m: SettlementModule) -> bool:
	return m.family == "res_mid" or m.family == "res_old" or m.family == "res_late"


func _tile_share(pos: Vector2) -> float:
	var budget: Vector2 = _roof_cells.get(Vector2i(floori(pos.x / ROOF_CELL_M), floori(pos.y / ROOF_CELL_M)),
			Vector2.ZERO)
	return budget.x / maxf(budget.y, 1.0)


func _cell_of(pos: Vector2) -> Vector2i:
	var size := float(_rules.placement["unique_cell_m"])
	return Vector2i(floori(pos.x / size), floori(pos.y / size))


## Planı lota yerleştirir (ortalı); çoklu birimde aralık uygular. Dönüş: yerleştirilen en derin birim derinliği.
func _commit_plan(p: WorldParcel, lot: SettlementLot, zone: SettlementZone, plan: Array, lo: float, hi: float,
		v_start: float, rng: RandomNumberGenerator, hist: _Hist) -> float:
	var total := 0.0
	for item: Dictionary in plan:
		total += (item["m"] as SettlementModule).w
	var gaps := maxi(plan.size() - 1, 0)
	var gap := rng.randf_range(zone.gap_min, zone.gap_max) if gaps > 0 else 0.0
	if gaps > 0 and total + gap * float(gaps) > hi - lo:
		gap = maxf(0.0, (hi - lo - total) / float(gaps))
	# Plan sokak sırasındadır; lot u ekseni sokak yönüne ters ise başlangıçlar ters sırayla dağıtılır.
	var cursor := lo + (hi - lo - total - gap * float(gaps)) * 0.5
	var starts: Array[float] = []
	starts.resize(plan.size())
	for k in plan.size():
		var idx := plan.size() - 1 - k if _flip else k
		var width := (plan[idx]["m"] as SettlementModule).w
		starts[idx] = cursor
		cursor += width + gap
	var max_depth := 0.0
	for k in plan.size():
		var item: Dictionary = plan[k]
		var m: SettlementModule = item["m"]
		if _try_place(p.id, lot, zone, m, int(item["wall"]), starts[k], v_start, rng, hist):
			max_depth = maxf(max_depth, m.d)
	return max_depth


## Tek birimi doğrular ve ekler: parsel içinde (u aralığı cephe + arka derinlikte), karada, eğim sınırında,
## meydan dışında.
func _try_place(parcel_id: int, lot: SettlementLot, zone: SettlementZone, m: SettlementModule, wall: int, u0: float,
		v0: float, rng: RandomNumberGenerator, hist: _Hist) -> bool:
	var margin := _margin
	var v1 := v0 + m.d
	var iv0 := lot.interval_at(v0 + FRONT_PROBE_M)
	var iv1 := lot.interval_at(v1)
	if iv0.x > iv0.y or iv1.x > iv1.y or v1 > lot.v_max - 0.01:
		_stats["dropped_fit"] += 1
		return false
	var u1 := u0 + m.w
	if u0 < maxf(iv0.x, iv1.x) + margin - 1.0e-6 or u1 > minf(iv0.y, iv1.y) - margin + 1.0e-6:
		_stats["dropped_fit"] += 1
		return false
	var center := lot.to_world(u0 + m.w * 0.5, v0 + m.d * 0.5)
	return _finish_unit(parcel_id, lot.yaw(), center, zone, m, wall, rng, hist)


## Ortak son kontroller + sütunlara yazma (tek yerleşim noktası).
func _finish_unit(parcel_id: int, yaw: float, center: Vector2, zone: SettlementZone, m: SettlementModule,
		wall: int, rng: RandomNumberGenerator, hist: _Hist) -> bool:
	var corners := SettlementObb.corners(center.x, center.y, yaw, m.w, m.d)
	# Kıyıdan uzaktaki (işaretli kıyı uzaklığı > yapı yarıçapı + pay) merkezde su denetimi atlanır.
	var shore := float(_world.shore_distance[_world.world_to_index(center.x, center.y)])
	if shore < SHORE_FAST_PATH_M + 0.5 * sqrt(m.w * m.w + m.d * m.d):
		if _world.is_water(center.x, center.y):
			_stats["dropped_water"] += 1
			return false
		for c in corners:
			if _world.is_water(c.x, c.y):
				_stats["dropped_water"] += 1
				return false
	if _world.slope_degrees_at(center.x, center.y) > float(_rules.placement["max_slope_deg"]):
		_stats["dropped_slope"] += 1
		return false
	if _plaza_corners.size() == 4 and SettlementObb.overlap(corners, _plaza_corners):
		_stats["dropped_plaza"] += 1
		return false
	var roof_weights: Dictionary = _rules.house_roof_weights if m.family == "res_house" else _rules.roof_weights
	var roof := _pick_weighted_row(m.roof_rows, roof_weights, rng)
	var accent := _pick_shop_accent(m, rng)
	var flags := 0
	if m.gf:
		flags |= BuildingColumns.FLAG_GROUND_SHOP
	if m.family.begins_with("ind_"):
		flags |= BuildingColumns.FLAG_INDUSTRY
		if zone.name == &"yard" or zone.name == &"harbor":
			flags |= BuildingColumns.FLAG_PORT_YARD
	if m.family == "civ_hall":
		flags |= BuildingColumns.FLAG_CIVIC
	if m.family == "ind_heritage" or (m.family == "res_old" and zone.heritage_p > 0.0 \
			and float(rng.randf()) < zone.heritage_p):
		flags |= BuildingColumns.FLAG_HERITAGE
	_cols.add(parcel_id, m.idx, center.x, center.y, yaw, m.floors, wall, roof, accent, rng.randi() % 256, flags, m.era)
	var roof_cell := Vector2i(floori(center.x / ROOF_CELL_M), floori(center.y / ROOF_CELL_M))
	var budget: Vector2 = _roof_cells.get(roof_cell, Vector2.ZERO)
	_roof_cells[roof_cell] = budget + Vector2(m.w * m.d if _rules.tile_rows.has(roof) else 0.0, m.w * m.d)
	hist.push(m.idx, wall, m.floors, _is_residential(m))
	var cell := _cell_of(center)
	var used: Dictionary = _used_cells.get(cell, {})
	used[m.idx * 64 + wall] = true
	_used_cells[cell] = used
	_stats["units"] += 1
	return true


func _pick_weighted_row(rows: PackedInt32Array, weights: Dictionary, rng: RandomNumberGenerator) -> int:
	var total := 0.0
	for row in rows:
		total += float(weights.get(row, 1.0))
	var r := rng.randf() * total
	for row in rows:
		r -= float(weights.get(row, 1.0))
		if r <= 0.0:
			return row
	return rows[rows.size() - 1]


func _pick_shop_accent(m: SettlementModule, rng: RandomNumberGenerator) -> int:
	var rows := _rules.shop_accent_rows if m.gf and not _rules.shop_accent_rows.is_empty() else m.accent_rows
	return rows[rng.randi() % rows.size()]


# ---------------------------------------------------------------- sivil yapı (çok parselli)

func _place_wide(parcels: PackedInt32Array, k: int, lot0: SettlementLot, zone: SettlementZone,
		rng: RandomNumberGenerator, hist: _Hist) -> bool:
	if zone.wide_modules.is_empty():
		return false
	var margin := _margin
	var parapet := _parapet
	var order := _weighted_order(zone.wide_weights, rng)
	var v0 := rng.randf_range(zone.setback_min, zone.setback_max)
	for oi in mini(order.size(), WIDE_TRIES):
		var m := zone.wide_modules[order[oi]]
		var v1 := v0 + m.d
		var probes := PackedFloat32Array([v0 + FRONT_PROBE_M, (v0 + v1) * 0.5, v1])
		var chain := _civic_chain(parcels, k, lot0, probes, m.w + 2.0 * margin)
		if chain.is_empty():
			continue
		var lo: float = chain["lo"]
		var hi: float = chain["hi"]
		var u_center := (lo + hi) * 0.5
		var center := lot0.to_world(u_center, v0 + m.d * 0.5)
		if _tower_active and center.distance_to(_tower_pos) <= _frame_radius + FRAME_RADIUS_PAD_M \
				and m.top_m(parapet) > _frame_cap_top:
			continue
		var wall := _pick_wall(m, hist.mods, hist.walls, _cell_of(center), rng, zone)
		var host := _civic_host(parcels, k, int(chain["count"]), lot0, u_center, probes[1])
		if _finish_unit(host, lot0.yaw(), center, zone, m, wall, rng, hist):
			for j in range(k, k + int(chain["count"])):
				_skip[parcels[j]] = true
				if parcels[j] != host:
					_res.consumed[parcels[j]] = true
					_stats["consumed"] += 1
			_stats["wide"] += 1
			return true
	return false


## Sıralı komşu parseller zincirinin üç derinlik probunda kesişen u aralığı; yeterli genişliğe ulaşırsa
## {"lo", "hi", "count"}; ulaşamazsa boş.
func _civic_chain(parcels: PackedInt32Array, k: int, lot0: SettlementLot, probes: PackedFloat32Array,
		need_w: float) -> Dictionary:
	var margin := _margin
	var polys: Array[PackedVector2Array] = []
	var last := mini(k + CIVIC_CHAIN_MAX, parcels.size())
	for j in range(k, last):
		var pj: WorldParcel = _net.parcels[parcels[j]]
		polys.append(lot0.to_frame_points(pj.outline) if j > k else lot0.pts)
	for count in range(1, polys.size() + 1):
		var lo := -INF
		var hi := INF
		var ok := true
		for v in probes:
			var iv := _union_interval(polys, count, v)
			if iv.x > iv.y:
				ok = false
				break
			lo = maxf(lo, iv.x)
			hi = minf(hi, iv.y)
		if not ok:
			return {}
		if hi - lo >= need_w:
			return {"lo": lo + margin, "hi": hi - margin, "count": count}
	return {}


## İlk `count` parselin v derinliğindeki birleşik (bitişik) u aralığı; ara kopukluk varsa zincir orada biter.
static func _union_interval(polys: Array[PackedVector2Array], count: int, v: float) -> Vector2:
	var first := SettlementLot.interval_of(polys[0], v)
	if first.x > first.y:
		return first
	var lo := first.x
	var hi := first.y
	for j in range(1, count):
		var iv := SettlementLot.interval_of(polys[j], v)
		if iv.x > iv.y or iv.x > hi + CIVIC_TOUCH_M:
			return Vector2(INF, -INF)
		lo = minf(lo, iv.x)
		hi = maxf(hi, iv.y)
	return Vector2(lo, hi)


## Yapının merkezini (u) ortadaki derinlikte kapsayan zincir parseli; yoksa ilk parsel.
func _civic_host(parcels: PackedInt32Array, k: int, count: int, lot0: SettlementLot, u_center: float,
		v_mid: float) -> int:
	for j in range(k, k + count):
		var pj: WorldParcel = _net.parcels[parcels[j]]
		var pts := lot0.pts if j == k else lot0.to_frame_points(pj.outline)
		var iv := SettlementLot.interval_of(pts, v_mid)
		if iv.x <= u_center and u_center <= iv.y:
			return parcels[j]
	return parcels[k]


# ---------------------------------------------------------------- kırsal tarla evi

func _place_farm(p: WorldParcel, lot: SettlementLot, zone: SettlementZone, rng: RandomNumberGenerator,
		hist: _Hist) -> void:
	var houses: Array[SettlementModule] = []
	var house_w := PackedFloat32Array()
	var sheds: Array[SettlementModule] = []
	var shed_w := PackedFloat32Array()
	for ci in zone.candidates.size():
		var m := zone.candidates[ci]
		if m.family == "res_house":
			houses.append(m)
			house_w.append(zone.base_weights[ci])
		elif m.family.begins_with("ind_"):
			sheds.append(m)
			shed_w.append(zone.base_weights[ci])
	if houses.is_empty():
		return
	var margin := _margin
	var v0 := rng.randf_range(zone.setback_min, zone.setback_max)
	var house := houses[_weighted_index(house_w, rng)]
	var cell := _cell_of(lot.to_world(lot.front_len * 0.5, v0))
	var front := lot.interval_at(v0 + FRONT_PROBE_M)
	var back := lot.interval_at(v0 + house.d)
	if front.x > front.y or back.x > back.y:
		return
	var lo := maxf(front.x, back.x) + margin
	var hi := minf(front.y, back.y) - margin
	if hi - lo < house.w:
		return
	var u0 := lo + (hi - lo - house.w) * rng.randf()
	var wall := _pick_wall(house, hist.mods, hist.walls, cell, rng, zone)
	if _try_place(p.id, lot, zone, house, wall, u0, v0, rng, hist):
		_stats["farms"] += 1
	if sheds.is_empty() or rng.randf() >= float(_rules.farm.get("shed_p", 0.4)):
		return
	var shed := sheds[_weighted_index(shed_w, rng)]
	var gap := rng.randf_range(float(_rules.farm["house_gap_m"][0]), float(_rules.farm["house_gap_m"][1]))
	var su0 := u0 + house.w + gap
	if su0 + shed.w > hi:
		su0 = u0 - gap - shed.w
	if su0 < lo:
		return
	var swall := _pick_wall(shed, hist.mods, hist.walls, cell, rng, zone)
	_try_place(p.id, lot, zone, shed, swall, su0, v0, rng, hist)


## Ağırlıklı rastgele sıralama (değiştirmeden çekme): dizin dizisi.
static func _weighted_order(weights: PackedFloat32Array, rng: RandomNumberGenerator) -> PackedInt32Array:
	var pool := PackedInt32Array()
	for i in weights.size():
		pool.append(i)
	var out := PackedInt32Array()
	while not pool.is_empty():
		var total := 0.0
		for i in pool:
			total += weights[i]
		var r := rng.randf() * total
		var pick := pool.size() - 1
		for q in pool.size():
			r -= weights[pool[q]]
			if r <= 0.0:
				pick = q
				break
		out.append(pool[pick])
		pool.remove_at(pick)
	return out


static func _weighted_index(weights: PackedFloat32Array, rng: RandomNumberGenerator) -> int:
	var total := 0.0
	for w in weights:
		total += w
	var r := rng.randf() * total
	for i in weights.size():
		r -= weights[i]
		if r <= 0.0:
			return i
	return weights.size() - 1
