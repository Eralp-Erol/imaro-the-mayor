class_name SimBuildingPlacer
extends RefCounted
## Sim'in tarif ettiği bir projeyi (kullanım + birim) parsel üzerinde kit modüllerine yerleştirir (T-040; render
## tarafı, saf ve deterministik: aynı dünya + tohum + parsel + kullanım + birim -> aynı yerleşim). Sim'e YAZMAZ.
##
## Kaynaklar (yeni sanat kararı yok): modül tablosu `SettlementRules` (kit manifesti), bölge dokusu ağırlıkları ve
## çekme/aralık/kat toleransı `settlement.json` zone'ları (T0 ile aynı kural dosyası), parsel cephe çerçevesi
## `SettlementLot` (yön = cephe sokağa bakar). Köprü sayıları `SimBuildingMapping`. T0Settlement'ın yerleşim
## algoritması kopyalanmaz: burada tek sıra, cephe şeridinde, parsel poligonuna sığan basit bir yerleşim vardır.
##
## İnşaat kademesi: kitte iskele modülü yok; nihai modülün ailesindeki daha az katlı modüllerle kat kademesi
## (`rows_for`). Nihai modül yalnız tamamda (ya da aile içinde daha küçük modül yoksa) görünür.

const FRONT_PROBE_M := 0.05
const MID_PROBE_M := 9.0
const SHORE_FAST_PATH_M := 150.0
const FIT_EPS := 1.0e-4
const FULL := 1000

var _net: WorldNetwork
var _world: WorldData
var _rules: SettlementRules
var _mapping: SimBuildingMapping
var _zone_by_parcel: Dictionary
var _consumed: Dictionary
var _plaza: PackedVector2Array = PackedVector2Array()
var _seed: int = 0
var _margin: float = 0.15
var _back_margin: float = 0.6
var _max_slope_deg: float = 14.0
var _cand_cache: Dictionary = {}
var _family_cache: Dictionary = {}


## Parsel için hesaplanmış nihai yerleşim (parça listesi); ilerleme `rows_for` ile uygulanır.
class Plan:
	extends RefCounted
	var parcel_id: int = 0
	var use: StringName = &""
	var units: int = 0
	var lot: SettlementLot = null
	var pieces: Array[Piece] = []

	func floors_total() -> int:
		var total := 0
		for p in pieces:
			total += p.module.floors
		return total


class Piece:
	extends RefCounted
	var module: SettlementModule = null
	var u0: float = 0.0
	var v0: float = 0.0
	var wall: int = 0
	var roof: int = 0
	var accent: int = 0
	var bright: int = 0
	var flags: int = 0


## BuildingColumns satırı (henüz sütunlara yazılmamış).
class Row:
	extends RefCounted
	var parcel_id: int = 0
	var module: int = 0
	var x: float = 0.0
	var z: float = 0.0
	var yaw: float = 0.0
	var floors: int = 0
	var wall: int = 0
	var roof: int = 0
	var accent: int = 0
	var bright: int = 0
	var flags: int = 0
	var era: int = BuildingColumns.ERA_NONE

	func signature() -> String:
		return "%d|%.3f|%.3f|%.4f|%d|%d|%d|%d|%d" % [module, x, z, yaw, wall, roof, accent, bright, flags]


## `settlement`: T0 yerleşim sonucu (net, rules, zone_by_parcel, consumed, plaza). `world_seed` tohum.
static func create(settlement: SettlementResult, mapping: SimBuildingMapping, world_seed: int) -> SimBuildingPlacer:
	if settlement == null or settlement.net == null or settlement.rules == null or mapping == null \
			or not mapping.is_valid():
		return null
	var p := SimBuildingPlacer.new()
	p._net = settlement.net
	p._world = settlement.net.world
	p._rules = settlement.rules
	p._mapping = mapping
	p._zone_by_parcel = settlement.zone_by_parcel
	p._consumed = settlement.consumed
	p._seed = world_seed
	p._margin = float(p._rules.placement.get("side_margin_m", 0.15))
	p._back_margin = float(p._rules.placement.get("back_margin_m", 0.6))
	p._max_slope_deg = float(p._rules.placement.get("max_slope_deg", 14.0))
	var plaza := settlement.plaza
	if not plaza.is_empty():
		var axis: Vector2 = plaza["axis"]
		var size: Vector2 = plaza["size"]
		var center: Vector2 = plaza["center"]
		var perp := Vector2(-axis.y, axis.x)
		var a := axis * (size.x * 0.5)
		var b := perp * (size.y * 0.5)
		p._plaza = PackedVector2Array([center - a - b, center + a - b, center + a + b, center - a + b])
	return p


## Parsel + kullanım + birim için nihai yerleşim; yerleşemiyorsa (parsel yok, çok parselli T0 yapısına katılmış,
## meydan, su/eğim, hiçbir modül sığmıyor) null.
func plan(parcel_id: int, use: StringName, units: int) -> Plan:
	if units < 1 or not _mapping.knows(use):
		return null
	var parcel: WorldParcel = _net.parcels.get(parcel_id)
	if parcel == null or _consumed.has(parcel_id):
		return null
	var lot := SettlementLot.from_parcel(parcel)
	if lot == null:
		return null
	var zone := _zone_with_candidates(parcel_id, use)
	if zone == null:
		zone = _rules.zone(_mapping.fallback_zone)
		if zone == null:
			return null
	var rng := RandomNumberGenerator.new()
	rng.seed = NetworkRules.stream_seed(parcel.detail, "sim_building.%d.%s.%d" % [_seed, String(use), units])
	var v0 := rng.randf_range(zone.setback_min, zone.setback_max)
	var cand := _candidates(zone, use)
	var result := _pack(parcel_id, use, units, lot, zone, cand, v0, rng)
	if result == null:
		# Doku adayları bu parsele sığmadı: kullanıma uyan TÜM kit modülleri (küçük ev/dükkân dahil) denenir.
		result = _pack(parcel_id, use, units, lot, zone, _all_candidates(use), v0, rng)
	return result


func _pack(parcel_id: int, use: StringName, units: int, lot: SettlementLot, zone: SettlementZone, cand: Dictionary,
		v0: float, rng: RandomNumberGenerator) -> Plan:
	var mods: Array[SettlementModule] = cand["mods"]
	var weights: PackedFloat32Array = cand["weights"]
	var target_total := maxi(1, units / _mapping.units_per_floor)
	var result := Plan.new()
	result.parcel_id = parcel_id
	result.use = use
	result.units = units
	result.lot = lot
	var cursor := -INF
	var placed_floors := 0
	while result.pieces.size() < _mapping.max_buildings and placed_floors < target_total:
		var remaining := target_total - placed_floors
		var opt_idx: Array[int] = []
		var opt_u: Array[float] = []
		var opt_w := PackedFloat32Array()
		for ci in mods.size():
			var m := mods[ci]
			var span := usable(lot, m, v0)
			if span.x > span.y:
				continue
			var u0 := maxf(span.x, cursor)
			if u0 + m.w > span.y + FIT_EPS or not site_ok(lot, m, u0, v0):
				continue
			var df := (float(m.floors) - float(remaining)) / zone.floors_sigma
			var w := weights[ci] * exp(-0.5 * df * df)
			if w <= 1.0e-6:
				continue
			opt_idx.append(ci)
			opt_u.append(u0)
			opt_w.append(w)
		if opt_idx.is_empty():
			break
		var pick := _weighted(opt_w, rng)
		var piece := _make_piece(mods[opt_idx[pick]], opt_u[pick], v0, rng)
		result.pieces.append(piece)
		placed_floors += piece.module.floors
		cursor = piece.u0 + piece.module.w + rng.randf_range(zone.gap_min, zone.gap_max)
	if result.pieces.is_empty():
		return null
	if result.pieces.size() == 1:
		var only := result.pieces[0]
		var span := usable(lot, only.module, v0)
		only.u0 = span.x + (span.y - span.x - only.module.w) * 0.5
	return result


## Sığar mı (hiçbir yapı üretmeden): oynanabilir sahne uygun parsel seçerken kullanır.
func can_place(parcel_id: int, use: StringName, units: int) -> bool:
	return plan(parcel_id, use, units) != null


## İlerleme (‰) için BuildingColumns satırları. `progress_pm >= 1000` nihai yapı; aksi halde kat kademesi.
func rows_for(p: Plan, progress_pm: int) -> Array[Row]:
	var out: Array[Row] = []
	for piece in p.pieces:
		var final_m := piece.module
		var m := final_m
		var u0 := piece.u0
		if progress_pm < FULL and final_m.floors > 1:
			var target := clampi((final_m.floors * maxi(progress_pm, 0) + FULL - 1) / FULL, 1, final_m.floors - 1)
			var stage := _stage_module(p, piece, target)
			if stage != null:
				m = stage
				u0 = piece.u0 + final_m.w * 0.5 - stage.w * 0.5
		out.append(_row(p, piece, m, u0))
	return out


## İlerleme `progress_pm`'den SONRA, görünen kat hedefinin değişeceği ilk ilerleme (‰; en çok FULL). Yoklama zamanlaması
## için: kademe değişmeden satırlar değişmez, parsel okunmasına gerek yoktur.
func next_stage_progress(p: Plan, progress_pm: int) -> int:
	var best := FULL
	for piece in p.pieces:
		var f := piece.module.floors
		if f <= 1:
			continue
		var target := clampi((f * maxi(progress_pm, 0) + FULL - 1) / FULL, 1, f - 1)
		if target < f - 1:
			best = mini(best, target * FULL / f + 1)
	return maxi(best, progress_pm + 1)


## Derinlik `v0`'da modülün sığabileceği u aralığı (lo, hi); sığmıyorsa lo > hi.
func usable(lot: SettlementLot, m: SettlementModule, v0: float) -> Vector2:
	var back := lot.v_max - _back_margin
	if v0 + m.d > back:
		return Vector2(INF, -INF)
	var front := lot.interval_at(v0 + FRONT_PROBE_M)
	var rear := lot.interval_at(v0 + m.d)
	var mid := lot.interval_at(minf(v0 + MID_PROBE_M, back))
	if front.x > front.y or rear.x > rear.y or mid.x > mid.y:
		return Vector2(INF, -INF)
	return Vector2(maxf(maxf(front.x, rear.x), mid.x) + _margin, minf(minf(front.y, rear.y), mid.y) - _margin)


## Ayak izi su/eğim/meydan denetimi (T0 ile aynı eşikler: `placement.max_slope_deg`, kıyı hızlı yolu).
func site_ok(lot: SettlementLot, m: SettlementModule, u0: float, v0: float) -> bool:
	var center := lot.to_world(u0 + m.w * 0.5, v0 + m.d * 0.5)
	var corners := SettlementObb.corners(center.x, center.y, lot.yaw(), m.w, m.d)
	var shore := float(_world.shore_distance[_world.world_to_index(center.x, center.y)])
	if shore < SHORE_FAST_PATH_M + 0.5 * sqrt(m.w * m.w + m.d * m.d):
		if _world.is_water(center.x, center.y):
			return false
		for c in corners:
			if _world.is_water(c.x, c.y):
				return false
	if _world.slope_degrees_at(center.x, center.y) > _max_slope_deg:
		return false
	if _plaza.size() == 4 and SettlementObb.overlap(corners, _plaza):
		return false
	return true


func _row(p: Plan, piece: Piece, m: SettlementModule, u0: float) -> Row:
	var row := Row.new()
	var center := p.lot.to_world(u0 + m.w * 0.5, piece.v0 + m.d * 0.5)
	row.parcel_id = p.parcel_id
	row.module = m.idx
	row.x = center.x
	row.z = center.y
	row.yaw = p.lot.yaw()
	row.floors = m.floors
	row.wall = piece.wall if m.wall_rows.has(piece.wall) else _first(m.wall_rows, piece.wall)
	row.roof = piece.roof if m.roof_rows.has(piece.roof) else _first(m.roof_rows, piece.roof)
	row.accent = piece.accent if m.accent_rows.has(piece.accent) else _first(m.accent_rows, piece.accent)
	row.bright = piece.bright
	row.flags = BuildingColumns.FLAG_GROUND_SHOP if m.gf else 0
	row.era = m.era
	return row


static func _first(rows: PackedInt32Array, fallback: int) -> int:
	return rows[0] if not rows.is_empty() else fallback


## Aynı aile + aynı zemin-dükkân durumunda, `target` kata kadar en yüksek katlı, aynı cephe hizası ve orta eksende
## parsele sığan modül. Hedef katın altında modül yoksa sığan en az katlı olan; hiç yoksa null (nihai modül kalır).
func _stage_module(p: Plan, piece: Piece, target: int) -> SettlementModule:
	var final_m := piece.module
	var best: SettlementModule = null
	var fallback: SettlementModule = null
	for m in _family(final_m):
		if m.idx == final_m.idx or m.floors >= final_m.floors:
			continue
		var u0 := piece.u0 + final_m.w * 0.5 - m.w * 0.5
		var span := usable(p.lot, m, piece.v0)
		if u0 < span.x - FIT_EPS or u0 + m.w > span.y + FIT_EPS or not site_ok(p.lot, m, u0, piece.v0):
			continue
		if m.floors <= target:
			if best == null or m.floors > best.floors or (m.floors == best.floors \
					and absf(m.w * m.d - final_m.w * final_m.d) < absf(best.w * best.d - final_m.w * final_m.d)):
				best = m
		elif fallback == null or m.floors < fallback.floors \
				or (m.floors == fallback.floors and m.w * m.d < fallback.w * fallback.d):
			fallback = m
	return best if best != null else fallback


func _family(final_m: SettlementModule) -> Array[SettlementModule]:
	var key := "%s|%s" % [final_m.family, str(final_m.gf)]
	if not _family_cache.has(key):
		var list: Array[SettlementModule] = []
		for m in _rules.modules:
			if m.family == final_m.family and m.gf == final_m.gf:
				list.append(m)
		_family_cache[key] = list
	return _family_cache[key]


func _all_candidates(use: StringName) -> Dictionary:
	var key := "*|%s" % String(use)
	if _cand_cache.has(key):
		return _cand_cache[key]
	var fams := _mapping.families_of(use)
	var shop := _mapping.wants_ground_shop(use)
	var mods: Array[SettlementModule] = []
	var weights := PackedFloat32Array()
	for m in _rules.modules:
		if fams.has(m.family) and m.gf == shop:
			mods.append(m)
			weights.append(1.0)
	var entry := {"mods": mods, "weights": weights}
	_cand_cache[key] = entry
	return entry


func _zone_with_candidates(parcel_id: int, use: StringName) -> SettlementZone:
	var zone := _rules.zone(_zone_by_parcel.get(parcel_id, &""))
	if zone != null and not (_candidates(zone, use)["mods"] as Array).is_empty():
		return zone
	var fallback := _rules.zone(_mapping.fallback_zone)
	if fallback != null and not (_candidates(fallback, use)["mods"] as Array).is_empty():
		return fallback
	return null


func _candidates(zone: SettlementZone, use: StringName) -> Dictionary:
	var key := "%s|%s" % [String(zone.name), String(use)]
	if _cand_cache.has(key):
		return _cand_cache[key]
	var fams := _mapping.families_of(use)
	var shop := _mapping.wants_ground_shop(use)
	var mods: Array[SettlementModule] = []
	var weights := PackedFloat32Array()
	for i in zone.candidates.size():
		var m := zone.candidates[i]
		if fams.has(m.family) and m.gf == shop:
			mods.append(m)
			weights.append(zone.base_weights[i])
	var entry := {"mods": mods, "weights": weights}
	_cand_cache[key] = entry
	return entry


func _make_piece(m: SettlementModule, u0: float, v0: float, rng: RandomNumberGenerator) -> Piece:
	var piece := Piece.new()
	piece.module = m
	piece.u0 = u0
	piece.v0 = v0
	piece.wall = _pick_row(m.wall_rows, _rules.wall_weights, rng)
	var roof_weights: Dictionary = _rules.house_roof_weights if m.family == "res_house" else _rules.roof_weights
	piece.roof = _pick_row(m.roof_rows, roof_weights, rng)
	var accent_rows := _rules.shop_accent_rows if m.gf and not _rules.shop_accent_rows.is_empty() else m.accent_rows
	piece.accent = accent_rows[rng.randi() % accent_rows.size()] if not accent_rows.is_empty() else 0
	piece.bright = rng.randi() % 256
	piece.flags = BuildingColumns.FLAG_GROUND_SHOP if m.gf else 0
	return piece


static func _pick_row(rows: PackedInt32Array, weights: Dictionary, rng: RandomNumberGenerator) -> int:
	if rows.is_empty():
		return 0
	var total := 0.0
	for row in rows:
		total += float(weights.get(row, 1.0))
	var r := rng.randf() * total
	for row in rows:
		r -= float(weights.get(row, 1.0))
		if r <= 0.0:
			return row
	return rows[rows.size() - 1]


static func _weighted(weights: PackedFloat32Array, rng: RandomNumberGenerator) -> int:
	var total := 0.0
	for w in weights:
		total += w
	var r := rng.randf() * total
	for i in weights.size():
		r -= weights[i]
		if r <= 0.0:
			return i
	return weights.size() - 1
