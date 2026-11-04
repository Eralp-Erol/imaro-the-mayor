# gdlint:disable=function-arguments-number
class_name VegetationPlacement
extends RefCounted
## T0 bitki yerleşimi (T-062 B0; WLD-01, WLD-08, TEK-01/02/03, VIS-01/02): dünya verisinden (yol ağı, parsel/blok, bina
## ayak izi, arazi sınıfı/eğim/kıyı) SEED'Lİ, deterministik, sütunlu ağaç/çalı/çit örnekleri. Saf: Node/Time/OS/global
## rastgelelik yok; her rastgele değer (akış, anahtar, tuz) tamsayı karmasından gelir (`_h`), akış tohumları mevcut
## `NetworkRules.stream_seed` kalıbıyla türer. Sim'e girmez; T0Settlement / sim hash'ine DOKUNMAZ (yalnız okur).
##
## Katmanlar (sırayla, `budget.layer_order`): street (yol kenarı), yard (parsel boşlukları), hedge (parsel sınırı),
## grove (kırsal zeytinlik), coast (kıyı şeridi), rural (kent çevresi yamaç/ova). Parametreler `vegetation.json`.
## Kurallar: gövde bina ayak izi / yol kesiti / su / uçurum içine düşmez; ağaçlar arası en az
## sep_frac x (erişim toplamı); sokak ağacı kaldırım bandında durur. Bütçe: katman başı ve toplam üst sınır,
## şehre yakın öncelikli (deterministik kırpma).

const TWO_PI := 6.283185307179586
const MASK32 := 0xFFFFFFFF
const MASK_CELL_M := 25.0

var _res: SettlementResult = null
var _world: WorldData = null
var _net: WorldNetwork = null
var _species: VegetationSpecies = null
var _rules: VegetationRules = null
var _cfg: Dictionary = {}
var _ob: VegetationObstacles = null
var _veg_seed: int = 0
var _streams: PackedInt64Array = PackedInt64Array()
# Ayrıştırılmış sık kullanılan parametreler.
var _min_above: float = 0.0
var _max_slope: PackedFloat32Array = PackedFloat32Array()
var _trunk: float = 0.7
var _cap: float = 12.0
var _frac_street: float = 0.3
var _frac_yard: float = 0.45
var _frac_grove: float = 0.3
var _frac_scatter: float = 0.3
var _road_edge: float = 0.8
var _boundary: float = 0.8
var _overhang: float = 2.5
var _sep_frac: float = 0.45
var _hedge_tree_sep: float = 1.6
var _hedge_building: float = 0.6
var _sep_cell: float = 12.0
var _reach: PackedFloat32Array = PackedFloat32Array()
## Tür dizini -> ortalama ölçekte gereken bina uzaklığı (katman taç oranına göre).
var _clr_street: PackedFloat32Array = PackedFloat32Array()
var _clr_yard: PackedFloat32Array = PackedFloat32Array()
var _clr_grove: PackedFloat32Array = PackedFloat32Array()
var _clr_scatter: PackedFloat32Array = PackedFloat32Array()
var _street_density: Dictionary = {}
var _street_classes: Dictionary = {}
var _street_palm_groups: Dictionary = {}
var _street_palm_shore: float = 0.0
var _street_palm_share: float = 0.0
var _field_density: float = 0.0
var _lot_reach: float = 60.0
var _coast_palm_ud: float = 0.0
var _coast_palm_shore: float = 0.0
var _coast_palm_share: float = 0.0
var _rank_w: float = 0.6
var _rank_dist: float = 5000.0
var _palm_on: bool = false
var _palm_mult: float = 1.0
var _hedge_idx: int = -1
var _olive_open_idx: int = -1
var _olive_twisted_idx: int = -1
var _zone_groups: Dictionary = {}
## Geçerli kenarın iki yanı için cephe parsellerinin kenar boyu konumu ve bölge grubu (`_edge_lots`).
## Meydan (varsa): ağaçsız dikdörtgen (T0 meydanı yapı barındırmaz, bitki de barındırmaz).
var _plaza_on: bool = false
var _plaza_center: Vector2 = Vector2.ZERO
var _plaza_axis: Vector2 = Vector2.RIGHT
var _plaza_half: Vector2 = Vector2.ZERO
var _lot_t: Array[PackedFloat32Array] = [PackedFloat32Array(), PackedFloat32Array()]
var _lot_group: Array[PackedStringArray] = [PackedStringArray(), PackedStringArray()]
var _yard_zone: Dictionary = {}
# Ham örnekler (katman kırpması `_skeep` ile; ızgara hayalet kayıtları taşır).
var _sx: PackedFloat32Array = PackedFloat32Array()
var _sz: PackedFloat32Array = PackedFloat32Array()
var _sy: PackedFloat32Array = PackedFloat32Array()
var _ss: PackedFloat32Array = PackedFloat32Array()
var _sr: PackedFloat32Array = PackedFloat32Array()
var _sp: PackedByteArray = PackedByteArray()
var _sl: PackedByteArray = PackedByteArray()
var _skeep: PackedByteArray = PackedByteArray()
var _srank: PackedFloat32Array = PackedFloat32Array()
var _shedge: PackedByteArray = PackedByteArray()
var _grid: Dictionary = {}
var _rejects: Array[Dictionary] = []
var _kept_total: int = 0
var _layer_stats: Dictionary = {}


## Saf giriş: `res` (T0 yerleşim sonucu: ağ + bina sütunları + modül ayak izleri + bölge dokusu), onaylı bitki tablosu,
## doğrulanmış kurallar, tohum. Geçersiz/boş girdi -> boş sütunlar + `stats["error"]`.
## `report_errors=false`: geçersiz girdi `push_error` yazmaz (testler); iz her zaman `stats["error"]`dadır.
static func generate(res: SettlementResult, species: VegetationSpecies, rules: VegetationRules,
		veg_seed: int, report_errors: bool = true) -> VegetationColumns:
	return VegetationPlacement.new()._run(res, species, rules, veg_seed, report_errors)


## Dünya tohumundan "veg" etiketli alt akış tohumu (yeni global akış yok).
static func default_seed(world: WorldData) -> int:
	return NetworkRules.stream_seed(world.world_seed, "veg")


func _run(res: SettlementResult, species: VegetationSpecies, rules: VegetationRules, veg_seed: int,
		report_errors: bool) -> VegetationColumns:
	var out := VegetationColumns.new()
	out.species_ids = species.ids.duplicate() if species != null else PackedStringArray()
	var problem := ""
	if species == null or species.size() == 0:
		problem = "bitki tablosu boş (LibraryGate kapalı/onaysız)"
	elif rules == null or not rules.is_valid():
		problem = "kurallar geçersiz: %s" % ("yok" if rules == null else "; ".join(rules.errors))
	elif res == null or res.net == null or res.rules == null:
		problem = "yerleşim sonucu yok"
	if not problem.is_empty():
		if report_errors:
			push_error("VegetationPlacement: %s" % problem)
		out.stats = {"error": problem}
		out.finalize(Vector2.ZERO, Vector2.ONE, 256.0)
		return out
	_res = res
	_net = res.net
	_world = res.net.world
	_species = species
	_rules = rules
	_cfg = rules.cfg
	_veg_seed = veg_seed
	_load_params()
	if not res.plaza.is_empty():
		_plaza_on = true
		_plaza_center = res.plaza["center"]
		_plaza_axis = (res.plaza["axis"] as Vector2).normalized()
		_plaza_half = (res.plaza["size"] as Vector2) * 0.5
	_ob = VegetationObstacles.new()
	_ob.build(res, _world, _cfg["sidewalk_m"], _cap, float(_cfg["clearance"]["junction_pad_m"]), MASK_CELL_M)
	var budget: Dictionary = _cfg["budget"]
	var order: Array = budget["layer_order"]
	for layer_name: String in order:
		var layer := VegetationColumns.LAYER_NAMES.find(StringName(layer_name))
		var first := _sx.size()
		match layer:
			VegetationColumns.LAYER_STREET:
				_run_street()
				_run_plaza()
			VegetationColumns.LAYER_YARD:
				_run_yard()
			VegetationColumns.LAYER_HEDGE:
				_run_hedge()
			VegetationColumns.LAYER_GROVE:
				_run_grove()
			VegetationColumns.LAYER_COAST:
				_run_scatter(true)
			VegetationColumns.LAYER_RURAL:
				_run_scatter(false)
		_close_layer(layer, first, int(budget["layer_caps"][layer_name]), int(budget["max_instances"]))
	return _assemble(out)


func _load_params() -> void:
	var cl: Dictionary = _cfg["clearance"]
	_min_above = float(_cfg["terrain"]["min_above_sea_m"])
	_max_slope.resize(VegetationColumns.LAYER_NAMES.size())
	for k in VegetationColumns.LAYER_NAMES.size():
		_max_slope[k] = float(_cfg["terrain"]["max_slope_deg"][String(VegetationColumns.LAYER_NAMES[k])])
	_trunk = float(cl["trunk_m"])
	_cap = float(cl["room_cap_m"])
	_frac_street = float(cl["crown_frac"]["street"])
	_frac_yard = float(cl["crown_frac"]["yard"])
	_frac_grove = float(cl["crown_frac"]["grove"])
	_frac_scatter = float(cl["crown_frac"]["scatter"])
	_road_edge = float(cl["road_edge_m"])
	_boundary = float(cl["boundary_m"])
	_overhang = float(cl["overhang_m"])
	_sep_frac = float(cl["sep_frac"])
	_hedge_tree_sep = float(cl["hedge_tree_sep_m"])
	_hedge_building = float(cl["hedge_building_m"])
	_rank_w = float(_cfg["budget"]["rank_distance_weight"])
	_rank_dist = float(_cfg["budget"]["rank_distance_m"])
	_palm_on = bool(_cfg["palm"]["enabled"])
	_palm_mult = float(_cfg["palm"]["multiplier"])
	_hedge_idx = _species.index_of("hedge")
	_olive_open_idx = _species.index_of("olive_open")
	_olive_twisted_idx = _species.index_of("olive_twisted")
	_reach.resize(_species.size())
	var max_r := 0.0
	for i in _species.size():
		_reach[i] = _species.reach_m[i]
		max_r = maxf(max_r, _species.reach_m[i] * _rules.scale_hi[i])
	for k in _species.size():
		_clr_street.append(_clearance_of(k, _mean_scale(k), _frac_street))
		_clr_yard.append(_clearance_of(k, _mean_scale(k), _frac_yard))
		_clr_grove.append(_clearance_of(k, _mean_scale(k), _frac_grove))
		_clr_scatter.append(_clearance_of(k, _mean_scale(k), _frac_scatter))
	var sc: Dictionary = _cfg["street"]
	_street_density = (sc["density"] as Dictionary).duplicate()
	_street_classes = (sc["classes"] as Dictionary).duplicate(true)
	for g: String in (_cfg["palm"]["street"]["groups"] as Array):
		_street_palm_groups[g] = true
	_street_palm_shore = float(_cfg["palm"]["street"]["max_shore_m"])
	_street_palm_share = float(_cfg["palm"]["street"]["share"])
	_field_density = float(sc["field_density"])
	_lot_reach = float(sc["lot_reach_m"])
	_coast_palm_ud = float(_cfg["palm"]["coast"]["max_urban_dist_m"])
	_coast_palm_shore = float(_cfg["palm"]["coast"]["max_shore_m"])
	_coast_palm_share = float(_cfg["palm"]["coast"]["share"])
	_sep_cell = maxf(maxf(8.0, ceil(_sep_frac * 2.0 * max_r) + 1.0), _hedge_tree_sep + 1.0)
	_zone_groups = (_cfg["zone_groups"] as Dictionary).duplicate()
	for zone: String in (_cfg["yard"]["zones"] as Dictionary):
		var zc: Dictionary = (_cfg["yard"]["zones"][zone] as Dictionary).duplicate()
		zc["weights"] = _rules.yard_weights[str(zc["group"])]
		_yard_zone[zone] = zc
	var stream_names := PackedStringArray()
	for n in VegetationColumns.LAYER_NAMES:
		stream_names.append(String(n))
	stream_names.append("noise")
	for label in stream_names:
		_streams.append(NetworkRules.stream_seed(_veg_seed, "%s/%s" % [str(_cfg.get("seed_label", "veg")), label]))
	for k in VegetationColumns.LAYER_NAMES.size():
		_rejects.append({})


# ---------------------------------------------------------------- yardımcılar

## Tamsayı karması -> [0, 1). Akış tohumu + iki anahtar; küresel durum yok. Çarpanlar < 2^31 (tamsayı taşması yok).
func _h(stream: int, a: int, b: int = 0) -> float:
	var h := (stream ^ 0x27D4EB2F) & MASK32
	h = ((h ^ (a & MASK32)) * 0x45D9F3B) & MASK32
	h = ((h ^ (h >> 15) ^ (b & MASK32)) * 0x6C8E9CF5) & MASK32
	h ^= h >> 13
	h = (h * 0x7FEB352D) & MASK32
	h ^= h >> 16
	h = (h * 0x165667B1) & MASK32
	h ^= h >> 15
	return float(h) / 4294967296.0


func _stream(layer: int) -> int:
	return int(_streams[layer])


func _noise_stream() -> int:
	return int(_streams[VegetationColumns.LAYER_NAMES.size()])


func _reject(layer: int, reason: String) -> void:
	var d: Dictionary = _rejects[layer]
	d[reason] = int(d.get(reason, 0)) + 1


## Değer gürültüsü [0, 1] (bilineer, yumuşatılmış); `salt` bağımsız gürültü alanı verir.
func _value_noise(px: float, pz: float, cell: float, salt: int) -> float:
	var fx := px / cell
	var fz := pz / cell
	var ix := int(floor(fx))
	var iz := int(floor(fz))
	var tx := fx - float(ix)
	var tz := fz - float(iz)
	tx = tx * tx * (3.0 - 2.0 * tx)
	tz = tz * tz * (3.0 - 2.0 * tz)
	var stream := _noise_stream()
	var k0 := (iz + 65536) * 8 + salt
	var k1 := (iz + 1 + 65536) * 8 + salt
	var a := lerpf(_h(stream, ix + 65536, k0), _h(stream, ix + 1 + 65536, k0), tx)
	var b := lerpf(_h(stream, ix + 65536, k1), _h(stream, ix + 1 + 65536, k1), tx)
	return lerpf(a, b, tz)


## Küme çarpanı [0, 1]: iki oktav değer gürültüsünden smoothstep(lo, hi).
func _cluster_mult(px: float, pz: float) -> float:
	var cl: Dictionary = _cfg["clusters"]
	var w := float(cl["small_weight"])
	var n := _value_noise(px, pz, float(cl["large_m"]), 0) * (1.0 - w) + _value_noise(px, pz, float(cl["small_m"]), 1) * w
	return smoothstep(float(cl["lo"]), float(cl["hi"]), n)


func _ground_ok(px: float, pz: float, layer: int) -> bool:
	if not _world.contains(px, pz):
		return false
	if _plaza_on:
		var rel := Vector2(px, pz) - _plaza_center
		var perp := Vector2(-_plaza_axis.y, _plaza_axis.x)
		if absf(rel.dot(_plaza_axis)) < _plaza_half.x and absf(rel.dot(perp)) < _plaza_half.y:
			return false
	if _world.height_at(px, pz) < _world.sea_level + _min_above:
		return false
	return _world.slope_degrees_at(px, pz) <= _max_slope[layer]


func _rank(u: float, px: float, pz: float) -> float:
	return lerpf(u, clampf(_ob.urban_distance(px, pz) / _rank_dist, 0.0, 1.0), _rank_w)


## Bu erişimde (ortalama ölçek) gövde için gereken minimum bina uzaklığı.
func _clearance_of(sp: int, scl: float, crown_frac: float) -> float:
	return maxf(_trunk, crown_frac * _reach[sp] * scl)


## Ağırlıklı tür seçimi: yalnız `room` (m) içine sığan (ortalama ölçekte) türler; yoksa -1.
func _pick(weights: PackedFloat32Array, room: float, clr: PackedFloat32Array, u: float) -> int:
	var total := 0.0
	for i in weights.size():
		if weights[i] > 0.0 and clr[i] <= room:
			total += weights[i]
	if total <= 0.0:
		return -1
	var t := u * total
	var acc := 0.0
	var last := -1
	for i in weights.size():
		if weights[i] > 0.0 and clr[i] <= room:
			acc += weights[i]
			last = i
			if t < acc:
				return i
	return last


func _mean_scale(sp: int) -> float:
	return (_rules.scale_lo[sp] + _rules.scale_hi[sp]) * 0.5


func _scale_of(sp: int, u: float) -> float:
	return lerpf(_rules.scale_lo[sp], _rules.scale_hi[sp], u)


## `base` ağırlıklarını `1 - share`, palmiye ağırlıklarını `share` ile karıştırır (Q-018: azaltılabilir).
func _blend_palm(base: PackedFloat32Array, share: float) -> PackedFloat32Array:
	var s := clampf(share * _palm_mult, 0.0, 1.0)
	if s <= 0.0:
		return base
	var out := PackedFloat32Array()
	out.resize(base.size())
	var bt := 0.0
	var pt := 0.0
	for i in base.size():
		bt += base[i]
		pt += _rules.palm_weights[i]
	for i in base.size():
		out[i] = (base[i] / bt) * (1.0 - s) + (_rules.palm_weights[i] / pt) * s
	return out


func _poly_edge_distance(p: Vector2, poly: PackedVector2Array) -> float:
	var best := INF
	var n := poly.size()
	for i in n:
		var d := NetworkGeometry.distance_point_segment(p, poly[i], poly[(i + 1) % n])
		if d < best:
			best = d
	return best


## Örneği ham listeye ekler (kapıdan geçtiyse). Çağıran ground/bina/yol denetimlerini yapmış olmalı DEĞİL: burada
## bina uzaklığı (`bd`), yol boşluğu ve ağaç aralığı denetlenir. true = eklendi.
func _place(layer: int, sp: int, px: float, pz: float, yaw: float, scl: float, bd: float, crown_frac: float,
		carriage: bool, skip_edge: int, u_rank: float) -> bool:
	var r := _reach[sp] * scl
	if bd < _clearance_of(sp, scl, crown_frac):
		_reject(layer, "building")
		return false
	if _ob.road_gap(px, pz, carriage, skip_edge) < _road_edge:
		_reject(layer, "road")
		return false
	if not _sep_ok(px, pz, r, false):
		_reject(layer, "separation")
		return false
	_add(layer, sp, px, pz, yaw, scl, r, false, _rank(u_rank, px, pz))
	return true


func _add(layer: int, sp: int, px: float, pz: float, yaw: float, scl: float, r: float, is_hedge: bool,
		rank: float) -> void:
	var idx := _sx.size()
	_sx.append(px)
	_sz.append(pz)
	_sy.append(yaw)
	_ss.append(scl)
	_sr.append(r)
	_sp.append(sp)
	_sl.append(layer)
	_skeep.append(1)
	_srank.append(rank)
	_shedge.append(1 if is_hedge else 0)
	var key := _gkey(px, pz)
	if _grid.has(key):
		var list: PackedInt32Array = _grid[key]
		list.append(idx)
		_grid[key] = list
	else:
		_grid[key] = PackedInt32Array([idx])


func _gkey(px: float, pz: float) -> int:
	return (int(floor(px / _sep_cell)) + 2048) + (int(floor(pz / _sep_cell)) + 2048) * 8192


func _sep_ok(px: float, pz: float, r: float, is_hedge: bool) -> bool:
	var cx := int(floor(px / _sep_cell)) + 2048
	var cz := int(floor(pz / _sep_cell)) + 2048
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var gk := (cx + dx) + (cz + dz) * 8192
			if not _grid.has(gk):
				continue
			var list: PackedInt32Array = _grid[gk]
			for j in list:
				var other_hedge := _shedge[j] == 1
				var need := 0.0
				if is_hedge and other_hedge:
					continue
				if is_hedge != other_hedge:
					need = _hedge_tree_sep
				else:
					need = _sep_frac * (r + _sr[j])
				var ddx := px - _sx[j]
				var ddz := pz - _sz[j]
				if ddx * ddx + ddz * ddz < need * need:
					return false
	return true


## Katman satırlarını (first..son) katman ve toplam sınırına göre kırpar: EN BÜYÜK sıra anahtarlıları düşer.
func _close_layer(layer: int, first: int, layer_cap: int, max_total: int) -> void:
	var n := _sx.size() - first
	var allowed := maxi(0, mini(layer_cap, max_total - _kept_total))
	var dropped := 0
	if n > allowed:
		var ranks := PackedFloat32Array()
		for i in range(first, first + n):
			ranks.append(_srank[i])
		ranks.sort()
		var threshold := ranks[allowed - 1] if allowed > 0 else -1.0
		var kept := 0
		for i in range(first, first + n):
			if _srank[i] < threshold:
				kept += 1
			elif _srank[i] > threshold:
				_skeep[i] = 0
		for i in range(first, first + n):
			if _srank[i] == threshold:
				if kept < allowed:
					kept += 1
				else:
					_skeep[i] = 0
		dropped = n - kept
	_kept_total += n - dropped
	_layer_stats[String(VegetationColumns.LAYER_NAMES[layer])] = {
		"generated": n, "kept": n - dropped, "dropped_by_cap": dropped, "layer_cap": layer_cap}


func _assemble(out: VegetationColumns) -> VegetationColumns:
	for i in _sx.size():
		if _skeep[i] == 1:
			out.add(_sp[i], _sx[i], _sz[i], _sy[i], _ss[i], _sl[i])
	out.finalize(_world.origin, _world.size, float(_cfg["cell_m"]))
	var rej := {}
	for k in VegetationColumns.LAYER_NAMES.size():
		rej[String(VegetationColumns.LAYER_NAMES[k])] = _rejects[k]
	out.stats = {"layers": _layer_stats, "rejects": rej, "ghosts": _sx.size() - out.count,
			"max_instances": int(_cfg["budget"]["max_instances"]), "buildings": _ob.building_count(),
			"road_segments": _ob.segment_count(), "plaza": not _res.plaza.is_empty()}
	return out


# ---------------------------------------------------------------- street (yol kenarı)

func _run_street() -> void:
	var layer := VegetationColumns.LAYER_STREET
	var st := _stream(layer)
	var sc: Dictionary = _cfg["street"]
	var end_margin := float(sc["end_margin_m"])
	var jitter := float(sc["jitter"])
	var field_offset := float(sc["field_offset_m"])
	var ids := PackedInt32Array(_net.edges.keys())
	ids.sort()
	for eid in ids:
		var e: WorldRoadEdge = _net.edges[eid]
		var cls := String(e.road_class)
		if not _street_classes.has(cls):
			continue
		var a := _net.node_pos(e.a)
		var b := _net.node_pos(e.b)
		var length := a.distance_to(b)
		if length < 2.0 * end_margin + 1.0:
			continue
		var dir := (b - a) / length
		var nrm := Vector2(-dir.y, dir.x)
		var half := e.width * 0.5
		var sw := float(_cfg["sidewalk_m"].get(cls, 0.0))
		var lateral := (half - sw * 0.5) if sw > 0.0 else (half + field_offset)
		var spacing := float(_street_classes[cls]["spacing_m"])
		var r_a := _ob.node_radius(e.a)
		var r_b := _ob.node_radius(e.b)
		_edge_lots(eid, a, dir, nrm)
		for side in 2:
			var sgn := -1.0 if side == 0 else 1.0
			var key := eid * 2 + side
			var t := end_margin + _h(st, key, 0) * spacing
			var k := 1
			while t <= length - end_margin:
				if t >= r_a and length - t >= r_b:
					var p := a + dir * t + nrm * (sgn * lateral)
					var outward := nrm * sgn
					_street_slot(e, key, k, t, p, side, cls)
				t += spacing * (1.0 + (_h(st, key, k * 32 + 1) - 0.5) * 2.0 * jitter)
				k += 1


func _street_slot(e: WorldRoadEdge, key: int, k: int, t: float, p: Vector2, side: int, cls: String) -> void:
	var layer := VegetationColumns.LAYER_STREET
	var st := _stream(layer)
	var group := VegetationRules.GROUP_FIELD_ROAD
	var density := _field_density
	if cls != "field":
		group = _street_group(side, t)
		density = float(_street_density.get(group, 0.0))
	if _h(st, key, k * 32 + 2) >= density:
		return
	if not _ground_ok(p.x, p.y, layer):
		_reject(layer, "ground")
		return
	var weights: PackedFloat32Array = _rules.street_weights[group]
	if _palm_on and _street_palm_groups.has(group):
		var shore := float(_world.shore_distance[_world.world_to_index(p.x, p.y)])
		if shore > 0.0 and shore <= _street_palm_shore:
			weights = _blend_palm(weights, _street_palm_share)
	var bd := _ob.building_distance(p.x, p.y)
	var sp := _pick(weights, bd, _clr_street, _h(st, key, k * 32 + 3))
	if sp < 0:
		_reject(layer, "no_room")
		return
	var scl := _scale_of(sp, _h(st, key, k * 32 + 4))
	_place(layer, sp, p.x, p.y, _h(st, key, k * 32 + 5) * TWO_PI, scl, bd, _frac_street, true, e.id,
			_h(st, key, k * 32 + 6))


## Yolun o yanındaki cephe parsellerinden `t`ye en yakının bölge grubu (`lot_reach_m` içinde); yoksa "rural".
func _street_group(side: int, t: float) -> String:
	var ts := _lot_t[side]
	var best := _lot_reach
	var group := "rural"
	for i in ts.size():
		var d := absf(ts[i] - t)
		if d < best:
			best = d
			group = _lot_group[side][i]
	return group


## Kenarın cephe parsellerini yanlara (-nrm / +nrm) ayırır: kenar boyu konum + yerleşim bölgesinin grubu.
func _edge_lots(eid: int, a: Vector2, dir: Vector2, nrm: Vector2) -> void:
	for side in 2:
		_lot_t[side].clear()
		_lot_group[side].clear()
	var pids := _net.edge_parcels(eid)
	for pid in pids:
		var parcel: WorldParcel = _net.parcels[pid]
		var rel := parcel.centroid - a
		var side := 0 if rel.dot(nrm) < 0.0 else 1
		_lot_t[side].append(rel.dot(dir))
		_lot_group[side].append(str(_zone_groups.get(String(_res.zone_by_parcel.get(pid, &"")), "rural")))


## Meydan çevresi (T0'da meydan varsa): dikdörtgenin dışında `offset_m` kenar boyunca `spacing_m` aralıkla sıra;
## palmiye payı `palm.plaza.share` (Q-018: azaltılabilir). Meydan yoksa (bugün: kule onaylı değil) iş yapmaz.
func _run_plaza() -> void:
	var plaza: Dictionary = _res.plaza
	if plaza.is_empty():
		return
	var layer := VegetationColumns.LAYER_STREET
	var st := _stream(layer)
	var center: Vector2 = plaza["center"]
	var axis: Vector2 = (plaza["axis"] as Vector2).normalized()
	var size: Vector2 = plaza["size"]
	var perp := Vector2(-axis.y, axis.x)
	var off := float(_cfg["palm"]["plaza"]["offset_m"])
	var step := float(_cfg["palm"]["plaza"]["spacing_m"])
	var hx := size.x * 0.5 + off
	var hz := size.y * 0.5 + off
	var corners := [center - axis * hx - perp * hz, center + axis * hx - perp * hz, center + axis * hx + perp * hz,
			center - axis * hx + perp * hz]
	var base: PackedFloat32Array = _rules.street_weights["core"]
	var share := float(_cfg["palm"]["plaza"]["share"])
	for side in 4:
		var c0: Vector2 = corners[side]
		var c1: Vector2 = corners[(side + 1) % 4]
		var length := c0.distance_to(c1)
		var n := int(length / step)
		for m in range(1, n + 1):
			var p := c0.lerp(c1, float(m) / float(n + 1))
			var key := 900000000 + side * 100000 + m
			if not _ground_ok(p.x, p.y, layer):
				continue
			var bd := _ob.building_distance(p.x, p.y)
			var weights := _blend_palm(base, share) if _palm_on else base
			var sp := _pick(weights, bd, _clr_street, _h(st, key, 3))
			if sp < 0:
				continue
			_place(layer, sp, p.x, p.y, _h(st, key, 5) * TWO_PI, _scale_of(sp, _h(st, key, 4)), bd, _frac_street,
					false, -1, _h(st, key, 6))


# ---------------------------------------------------------------- yard (parsel boşlukları)

func _run_yard() -> void:
	var layer := VegetationColumns.LAYER_YARD
	var sy := _stream(layer)
	var yc: Dictionary = _cfg["yard"]
	var tries := int(yc["tries"])
	var pids := PackedInt32Array(_net.parcels.keys())
	pids.sort()
	for pid in pids:
		var parcel: WorldParcel = _net.parcels[pid]
		var zone := String(_res.zone_by_parcel.get(pid, &""))
		if not _yard_zone.has(zone) or parcel.outline.size() < 3:
			continue
		var zc: Dictionary = _yard_zone[zone]
		var buildings := _ob.buildings_of(pid)
		var vacant := buildings.is_empty()
		var green := lerpf(float(yc["green_min"]), 1.0, _h(sy, pid, 1))
		if _h(sy, pid, 2) < float(yc["green_parcel_p"]):
			green *= float(yc["green_mult"])
		var near := bool(zc.get("near_building", false))
		var expect := 0.0
		if near:
			expect = float(buildings.size()) * float(zc["per_building"]) * green
		else:
			var free_ha := maxf(parcel.area - _ob.built_area_of(pid), 0.0) / 10000.0
			expect = free_ha * float(zc["per_ha"]) * green * (float(zc["vacant_mult"]) if vacant else 1.0)
		var n := int(expect)
		if _h(sy, pid, 3) < expect - float(n):
			n += 1
		if n <= 0:
			continue
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for q in parcel.outline:
			lo = Vector2(minf(lo.x, q.x), minf(lo.y, q.y))
			hi = Vector2(maxf(hi.x, q.x), maxf(hi.y, q.y))
		for k in n:
			_yard_tree(parcel, zc, buildings, lo, hi, k, tries)


func _yard_tree(parcel: WorldParcel, zc: Dictionary, buildings: PackedInt32Array, lo: Vector2, hi: Vector2, k: int,
		tries: int) -> void:
	var layer := VegetationColumns.LAYER_YARD
	var sy := _stream(layer)
	var pid := parcel.id
	var near := bool(zc.get("near_building", false))
	var radius := float(_cfg["yard"]["near_building_m"])
	for a in tries:
		var salt := 16 + (k * tries + a) * 8
		var px := 0.0
		var pz := 0.0
		if near:
			var rect := _ob.building_rect(buildings[int(_h(sy, pid, salt) * buildings.size()) % buildings.size()])
			var ang := _h(sy, pid, salt + 1) * TWO_PI
			var rad := sqrt(_h(sy, pid, salt + 2)) * radius
			px = rect[0] + cos(ang) * rad
			pz = rect[1] + sin(ang) * rad
		else:
			px = lerpf(lo.x, hi.x, _h(sy, pid, salt))
			pz = lerpf(lo.y, hi.y, _h(sy, pid, salt + 1))
		var p := Vector2(px, pz)
		if not Geometry2D.is_point_in_polygon(p, parcel.outline):
			continue
		if not _ground_ok(px, pz, layer):
			_reject(layer, "ground")
			continue
		var edge_d := _poly_edge_distance(p, parcel.outline)
		if edge_d < _boundary:
			_reject(layer, "edge")
			continue
		var bd := _ob.building_distance(px, pz)
		var room := minf(bd, edge_d + _overhang)
		var sp := _pick(zc["weights"], room, _clr_yard, _h(sy, pid, salt + 3))
		if sp < 0:
			_reject(layer, "no_room")
			continue
		var scl := _scale_of(sp, _h(sy, pid, salt + 4))
		if _place(layer, sp, px, pz, _h(sy, pid, salt + 5) * TWO_PI, scl, bd, _frac_yard, false, -1,
				_h(sy, pid, salt + 6)):
			return


# ---------------------------------------------------------------- hedge (parsel sınırı)

func _run_hedge() -> void:
	var layer := VegetationColumns.LAYER_HEDGE
	var sh := _stream(layer)
	var hc: Dictionary = _cfg["hedge"]
	var pids := PackedInt32Array(_net.parcels.keys())
	pids.sort()
	for pid in pids:
		var parcel: WorldParcel = _net.parcels[pid]
		var zone := String(_res.zone_by_parcel.get(pid, &""))
		var zone_p := float((hc["zone_p"] as Dictionary).get(zone, 0.0))
		if zone_p <= 0.0 or parcel.outline.size() < 3 or _h(sh, pid, 1) >= zone_p:
			continue
		var outline := parcel.outline
		var n := outline.size()
		var front := _front_edge(parcel)
		for i in n:
			if i == front or _h(sh, pid, 100 + i) >= float(hc["edge_p"]):
				continue
			_hedge_edge(parcel, outline[i], outline[(i + 1) % n], i)


## Cephe kenarı: orta noktası `front_mid`e en yakın dış hat kenarı.
func _front_edge(parcel: WorldParcel) -> int:
	var best := -1
	var best_d := INF
	var n := parcel.outline.size()
	for i in n:
		var mid := (parcel.outline[i] + parcel.outline[(i + 1) % n]) * 0.5
		var d := mid.distance_to(parcel.front_mid)
		if d < best_d:
			best_d = d
			best = i
	return best


func _hedge_edge(parcel: WorldParcel, v0: Vector2, v1: Vector2, edge_i: int) -> void:
	var layer := VegetationColumns.LAYER_HEDGE
	var sh := _stream(layer)
	var hc: Dictionary = _cfg["hedge"]
	var pid := parcel.id
	var length := v0.distance_to(v1)
	var pad := float(hc["end_pad_m"])
	if length < float(hc["min_edge_m"]):
		return
	var d := (v1 - v0) / length
	var inward := Vector2(-d.y, d.x)
	if not Geometry2D.is_point_in_polygon((v0 + v1) * 0.5 + inward * 0.5, parcel.outline):
		inward = -inward
	var cover: Array = hc["cover"]
	var run := lerpf(float(cover[0]), float(cover[1]), _h(sh, pid, 200 + edge_i)) * (length - 2.0 * pad)
	var start := pad + _h(sh, pid, 300 + edge_i) * (length - 2.0 * pad - run)
	var count := maxi(1, int(run / float(hc["stride_m"])))
	var yaw := atan2(-d.y, d.x)
	for m in count:
		var tpos := start + (float(m) + 0.5) * run / float(count)
		var p := v0 + d * tpos + inward * float(hc["inset_m"])
		var salt := 1000 + edge_i * 64 + m
		var scl := _scale_of(_hedge_idx, _h(sh, pid, salt))
		var half_len := _reach[_hedge_idx] * scl * 0.9
		if not Geometry2D.is_point_in_polygon(p, parcel.outline) or not _ground_ok(p.x, p.y, layer):
			_reject(layer, "ground")
			continue
		var need := _hedge_building + 0.63 * scl
		if minf(_ob.building_distance(p.x, p.y), minf(_ob.building_distance(p.x + d.x * half_len, p.y + d.y * half_len),
				_ob.building_distance(p.x - d.x * half_len, p.y - d.y * half_len))) < need:
			_reject(layer, "building")
			continue
		if _ob.road_gap(p.x, p.y, false, -1) < _road_edge:
			_reject(layer, "road")
			continue
		if not _sep_ok(p.x, p.y, 0.0, true):
			_reject(layer, "separation")
			continue
		_add(layer, _hedge_idx, p.x, p.y, yaw, scl, 0.0, true, _rank(_h(sh, pid, salt + 500), p.x, p.y))


# ---------------------------------------------------------------- grove (kırsal zeytinlik)

func _run_grove() -> void:
	var gc: Dictionary = _cfg["grove"]
	var layer := VegetationColumns.LAYER_GROVE
	var sg := _stream(layer)
	var pids := PackedInt32Array(_net.parcels.keys())
	pids.sort()
	for pid in pids:
		var parcel: WorldParcel = _net.parcels[pid]
		if parcel.fabric != &"rural" or parcel.outline.size() < 3:
			continue
		var mult := float((gc["region_mult"] as Dictionary).get(String(parcel.region_code),
				(gc["region_mult"] as Dictionary)["default"]))
		if _h(sg, pid, 1) < float(gc["parcel_p"]) * mult:
			_grove(parcel.outline, pid)
	var bids := PackedInt32Array(_net.blocks.keys())
	bids.sort()
	for bid in bids:
		var block: WorldBlock = _net.blocks[bid]
		if block.kind != WorldBlock.KIND_OPEN or block.outline.size() < 3:
			continue
		if _h(sg, 500000 + bid, 1) < float(gc["open_block_p"]):
			_grove(block.outline, 500000 + bid)


## Çokgenin en uzun kenarına hizalı ızgarada zeytin; `key` (parsel/blok) ızgara ve karışımı belirler.
func _grove(outline: PackedVector2Array, key: int) -> void:
	var layer := VegetationColumns.LAYER_GROVE
	var sg := _stream(layer)
	var gc: Dictionary = _cfg["grove"]
	var n := outline.size()
	var axis := Vector2.RIGHT
	var best := -1.0
	for i in n:
		var seg := outline[(i + 1) % n] - outline[i]
		if seg.length() > best:
			best = seg.length()
			axis = seg / maxf(seg.length(), 1.0e-6)
	var perp := Vector2(-axis.y, axis.x)
	var u_lo := INF
	var u_hi := -INF
	var v_lo := INF
	var v_hi := -INF
	for q in outline:
		u_lo = minf(u_lo, q.dot(axis))
		u_hi = maxf(u_hi, q.dot(axis))
		v_lo = minf(v_lo, q.dot(perp))
		v_hi = maxf(v_hi, q.dot(perp))
	var ext: Array = gc["extent"]
	var fu := lerpf(float(ext[0]), float(ext[1]), _h(sg, key, 2))
	var fv := lerpf(float(ext[0]), float(ext[1]), _h(sg, key, 3))
	var span_u := (u_hi - u_lo) * fu
	var span_v := (v_hi - v_lo) * fv
	var u0 := u_lo + ((u_hi - u_lo) - span_u) * _h(sg, key, 4)
	var v0 := v_lo + ((v_hi - v_lo) - span_v) * _h(sg, key, 5)
	var sp_range: Array = gc["spacing_m"]
	var spacing := lerpf(float(sp_range[0]), float(sp_range[1]), _h(sg, key, 6))
	var cells := (span_u / spacing + 1.0) * (span_v / spacing + 1.0)
	if cells > float(gc["max_per_grove"]):
		spacing *= sqrt(cells / float(gc["max_per_grove"]))
	var tw_range: Array = gc["twisted_share"]
	var twisted := lerpf(float(tw_range[0]), float(tw_range[1]), _h(sg, key, 7))
	var ni := int(span_u / spacing) + 1
	var nj := int(span_v / spacing) + 1
	var jit := float(gc["jitter_frac"]) * spacing
	for j in nj:
		for i in ni:
			var salt := 64 + (j * ni + i) * 8
			var du := u0 + float(i) * spacing + (_h(sg, key, salt) - 0.5) * 2.0 * jit
			var dv := v0 + float(j) * spacing + (_h(sg, key, salt + 1) - 0.5) * 2.0 * jit
			_grove_tree(outline, axis * du + perp * dv, key, salt, twisted)


func _grove_tree(outline: PackedVector2Array, p: Vector2, key: int, salt: int, twisted: float) -> void:
	var layer := VegetationColumns.LAYER_GROVE
	var sg := _stream(layer)
	var gc: Dictionary = _cfg["grove"]
	if not Geometry2D.is_point_in_polygon(p, outline):
		return
	if not _ground_ok(p.x, p.y, layer):
		_reject(layer, "ground")
		return
	if _poly_edge_distance(p, outline) < float(gc["edge_margin_m"]):
		_reject(layer, "edge")
		return
	var bd := _ob.building_distance(p.x, p.y)
	if bd < float(gc["building_margin_m"]) or _ob.road_gap(p.x, p.y, false, -1) < float(gc["road_margin_m"]):
		_reject(layer, "building_or_road")
		return
	var sp := _olive_twisted_idx if _h(sg, key, salt + 2) < twisted else _olive_open_idx
	var scl := _scale_of(sp, _h(sg, key, salt + 3))
	_place(layer, sp, p.x, p.y, _h(sg, key, salt + 4) * TWO_PI, scl, bd, _frac_grove, false, -1,
			_h(sg, key, salt + 5))


# ---------------------------------------------------------------- coast / rural (arazi sınıfına göre serpilme)

func _run_scatter(coast_pass: bool) -> void:
	var layer := VegetationColumns.LAYER_COAST if coast_pass else VegetationColumns.LAYER_RURAL
	var ss := _stream(layer)
	var cc: Dictionary = _cfg["coast"]
	var rc: Dictionary = _cfg["rural"]
	var min_shore := float(cc["min_shore_m"])
	var band := float(cc["band_m"])
	var max_ud := float(cc["max_urban_dist_m"]) if coast_pass else float(rc["max_urban_dist_m"])
	var cell_ha := _world.cell_size * _world.cell_size / 10000.0
	var pocket: Dictionary = rc["olive_pocket"]
	for j in _world.height - 1:
		for i in _world.width - 1:
			var k := j * _world.width + i
			if _world.land_mask[k] == 0:
				continue
			var shore := _world.shore_distance[k]
			var in_coast := shore > 0.0 and shore <= band
			if shore < min_shore or in_coast != coast_pass:
				continue
			var ud := _ob.urban_distance_at_index(k)
			if ud > max_ud:
				continue
			var c := _world.cell_to_world(i, j) + Vector2(_world.cell_size, _world.cell_size) * 0.5
			var nmul := _cluster_mult(c.x, c.y)
			if nmul <= 0.0:
				continue
			var per_ha := 0.0
			var weights := PackedFloat32Array()
			if coast_pass:
				per_ha = float(cc["per_ha"])
				weights = _rules.coast_weights
			else:
				var cls := _rural_class(c)
				if cls < 0:
					continue
				per_ha = float(rc["classes"][cls]["per_ha"])
				weights = _rules.rural_weights[cls]
				if _value_noise(c.x, c.y, float(pocket["cell_m"]), 2) > float(pocket["threshold"]) \
						and _world.slope_degrees_at(c.x, c.y) <= float(pocket["max_slope_deg"]):
					per_ha = float(pocket["per_ha"])
					weights = _rules.pocket_weights
			var falloff := lerpf(1.0, float(rc["falloff_min"]), clampf(ud / max_ud, 0.0, 1.0))
			var expect := cell_ha * per_ha * nmul * falloff
			var cnt := int(expect)
			if _h(ss, k, 1) < expect - float(cnt):
				cnt += 1
			for t in cnt:
				_scatter_tree(layer, coast_pass, k, t, i, j, weights, shore, ud)


## Hücre merkezi için eğim/yükseklik sınıfı (ilk eşleşen); eşleşme yoksa -1.
func _rural_class(c: Vector2) -> int:
	var slope := _world.slope_degrees_at(c.x, c.y)
	var elev := _world.height_at(c.x, c.y) - _world.sea_level
	var classes: Array = _cfg["rural"]["classes"]
	for k in classes.size():
		var cls: Dictionary = classes[k]
		var s: Array = cls["slope_deg"]
		var e: Array = cls["elev_m"]
		if slope >= float(s[0]) and slope < float(s[1]) and elev >= float(e[0]) and elev < float(e[1]):
			return k
	return -1


func _scatter_tree(layer: int, coast_pass: bool, k: int, t: int, i: int, j: int, weights: PackedFloat32Array,
		shore: float, ud: float) -> void:
	var ss := _stream(layer)
	var salt := 8 + t * 8
	var px := _world.origin.x + (float(i) + _h(ss, k, salt)) * _world.cell_size
	var pz := _world.origin.y + (float(j) + _h(ss, k, salt + 1)) * _world.cell_size
	if _ob.in_urban_block(px, pz):
		_reject(layer, "urban_block")
		return
	if not _ground_ok(px, pz, layer):
		_reject(layer, "ground")
		return
	var w := weights
	if coast_pass and _palm_on and ud <= _coast_palm_ud and shore <= _coast_palm_shore:
		w = _blend_palm(weights, _coast_palm_share)
	var bd := _ob.building_distance(px, pz)
	var sp := _pick(w, bd, _clr_scatter, _h(ss, k, salt + 2))
	if sp < 0:
		_reject(layer, "no_room")
		return
	var scl := _scale_of(sp, _h(ss, k, salt + 3))
	_place(layer, sp, px, pz, _h(ss, k, salt + 4) * TWO_PI, scl, bd, _frac_scatter, false, -1, _h(ss, k, salt + 5))
