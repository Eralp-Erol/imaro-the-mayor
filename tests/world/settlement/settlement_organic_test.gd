extends GdUnitTestSuite
## T-049 A · Organik doluluk: bölge merkezinden saf radyal değil; yerel kümeleşme/boşluk cepleri, eğim/kıyı kesintisi,
## cephe yolu erişimi; D1+D6 kompakt-gelişmiş çekirdek korunur (WLD-04), bina sayısı aynı mertebede, veri-odaklı.

const URBAN := ["core", "compact", "mixed"]
const CELL_M := 250.0
const MIN_CELL_PARCELS := 15
## Gözlenen hücre doluluk sapması / bağımsız (binom) beklenen sapma: >1 = kümeleşme.
const MIN_CLUSTER_RATIO := 1.8
## Referans bina sayısı (varsayılan test tohumu, tam Ismeral). Tarihçe: T-049 öncesi 54.856 -> T-049 sonrası kit tablosu
## 49.967 -> T-062 A2 hero tablosu 32.264 (-%35: hero ayak izi >= 10,25 m, kit 7 m'ye iniyordu; doluluk/topoloji AYNI,
## lottery_parcels 26.278 değişmedi). Bu test kümeleşme ayarının sayıyı kaydırmadığını korur; referans hero tabanıdır.
const BUILDINGS_T0_BEFORE := 32264
const BUILDINGS_TOLERANCE := 0.25

var _res: SettlementResult
var _occupied: Dictionary = {}


func before() -> void:
	_res = SettlementTestSupport.full()
	for pid in _res.lottery_parcels:
		_occupied[int(pid)] = true


func _urban_rows() -> Array[Dictionary]:
	var net := _res.net
	var rows: Array[Dictionary] = []
	for pid: int in net.parcels:
		var p: WorldParcel = net.parcels[pid]
		if not URBAN.has(String(p.fabric)):
			continue
		var fp := net.rules.footprint_by_id(p.region_code)
		if fp == null:
			continue
		rows.append({"p": p, "t": fp.norm_dist(p.centroid), "occ": _occupied.has(pid),
				"slope": net.world.slope_degrees_at(p.centroid.x, p.centroid.y)})
	return rows


static func _rate(rows: Array[Dictionary], pred: Callable) -> Vector2:
	var n := 0
	var o := 0
	for r in rows:
		if pred.call(r):
			n += 1
			if bool(r["occ"]):
				o += 1
	return Vector2(float(n), float(o) / float(maxi(n, 1)))


func test_building_count_stays_in_the_same_order_of_magnitude() -> void:
	var n := _res.columns.count
	assert_int(n).is_greater(int(BUILDINGS_T0_BEFORE * (1.0 - BUILDINGS_TOLERANCE)))
	assert_int(n).is_less(int(BUILDINGS_T0_BEFORE * (1.0 + BUILDINGS_TOLERANCE)))


func test_core_districts_d1_d6_stay_denser_than_d2_to_d5_centres() -> void:
	var dens := {}
	for code in ["D1", "D2", "D3", "D4", "D5", "D6"]:
		dens[code] = SettlementStats.region_density(_res, StringName(code))["buildings_per_km2"]
	var core_min := minf(float(dens["D1"]), float(dens["D6"]))
	var other_max := 0.0
	for code in ["D2", "D3", "D4", "D5"]:
		other_max = maxf(other_max, float(dens[code]))
	assert_float(core_min).override_failure_message("D1/D6 %s vs diğerleri %s" % [core_min, other_max]) \
			.is_greater(other_max * 1.5)
	# Bölge içi doluluk (kentsel parsel payı, t <= 1): D1/D6 > D2..D5.
	var rows := _urban_rows()
	var core := _rate(rows, func(r: Dictionary) -> bool:
		return (r["p"].region_code == &"D1" or r["p"].region_code == &"D6") and r["t"] <= 1.0)
	var rest := _rate(rows, func(r: Dictionary) -> bool:
		return r["p"].region_code != &"D1" and r["p"].region_code != &"D6" and r["t"] <= 1.0)
	assert_float(core.y).is_greater(rest.y + 0.15)


func test_core_centre_stays_compact_and_dense() -> void:
	var rows := _urban_rows()
	var core := _rate(rows, func(r: Dictionary) -> bool:
		return (r["p"].region_code == &"D1" or r["p"].region_code == &"D6") and r["t"] < 0.3)
	assert_float(core.x).is_greater(1000.0)
	assert_float(core.y).override_failure_message("D1/D6 çekirdek doluluk %.2f" % core.y).is_greater(0.88)


func test_occupancy_falls_from_core_to_edge_but_is_not_a_clean_radial_ramp() -> void:
	var rows := _urban_rows()
	var inner := _rate(rows, func(r: Dictionary) -> bool: return r["t"] < 0.3)
	var outer := _rate(rows, func(r: Dictionary) -> bool: return r["t"] >= 0.6 and r["t"] <= 1.0)
	assert_float(inner.y).is_greater(outer.y + 0.15)


func test_occupancy_is_clustered_with_gaps_not_independent_per_parcel() -> void:
	var cells := {}
	var total := 0.0
	var occ_total := 0.0
	for r in _urban_rows():
		var p: WorldParcel = r["p"]
		if float(r["t"]) <= 0.5 or float(r["t"]) > 1.0 or p.region_code == &"D1" or p.region_code == &"D6":
			continue
		var key := Vector2i(int(floor(p.centroid.x / CELL_M)), int(floor(p.centroid.y / CELL_M)))
		var e: Array = cells.get(key, [0, 0])
		e[0] += 1
		e[1] += 1 if bool(r["occ"]) else 0
		cells[key] = e
		total += 1.0
		occ_total += 1.0 if bool(r["occ"]) else 0.0
	var pbar := occ_total / total
	var sum := 0.0
	var expected := 0.0
	var used := 0
	for key: Vector2i in cells:
		var n := float((cells[key] as Array)[0])
		if n < MIN_CELL_PARCELS:
			continue
		var f := float((cells[key] as Array)[1]) / n
		sum += (f - pbar) * (f - pbar)
		expected += pbar * (1.0 - pbar) / n
		used += 1
	assert_int(used).is_greater(60)
	var ratio := sqrt(sum / float(used)) / sqrt(expected / float(used))
	assert_float(ratio).override_failure_message("kümeleşme oranı %.2f" % ratio).is_greater(MIN_CLUSTER_RATIO)


func test_steep_parcels_are_less_occupied_than_flat_ones_in_the_same_band() -> void:
	var rows := _urban_rows()
	for band in [Vector2(0.3, 0.6), Vector2(0.6, 1.0)]:
		var steep := _rate(rows, func(r: Dictionary) -> bool:
			return r["t"] >= band.x and r["t"] < band.y and r["slope"] >= 6.0)
		var flat := _rate(rows, func(r: Dictionary) -> bool:
			return r["t"] >= band.x and r["t"] < band.y and r["slope"] < 2.5)
		assert_float(steep.x).is_greater(50.0)
		assert_float(steep.y).override_failure_message("band %s eğimli %.2f düz %.2f" % [band, steep.y, flat.y]) \
				.is_less(flat.y - 0.1)


# --- Veri-odaklılık (hafif ağ üzerinde; olumlu/olumsuz) ---

func _light_count(mutate: Callable) -> int:
	var c := SettlementTestSupport.control()
	mutate.call(c)
	return SettlementTestSupport.light_with(SettlementTestSupport.SEED, c).lottery_parcels.size()


func test_occupancy_parameters_change_the_result() -> void:
	var base := _light_count(func(_c: Dictionary) -> void: pass)
	assert_int(base).is_greater(1000)
	assert_int(_light_count(func(c: Dictionary) -> void: c.erase("occupancy"))).is_not_equal(base)
	assert_int(_light_count(func(c: Dictionary) -> void: c["occupancy"]["slope"]["cut"] = 0.0)).is_greater(base)
	assert_int(_light_count(func(c: Dictionary) -> void:
		c["occupancy"]["shore"]["cut"] = 0.9
		c["occupancy"]["shore"]["band_m"] = 4000.0)).is_less(base)
	assert_int(_light_count(func(c: Dictionary) -> void: c["occupancy"]["road_access"]["collector"] = 0.4)) \
			.is_greater(base)
	assert_int(_light_count(func(c: Dictionary) -> void: c["occupancy"]["pocket"]["keep"] = 0.0)).is_less(base)


func test_same_seed_same_occupancy_and_it_is_independent_of_the_settlement_seed() -> void:
	var a := SettlementTestSupport.light_with(SettlementTestSupport.SEED, SettlementTestSupport.control())
	var b := SettlementTestSupport.light_with(SettlementTestSupport.SEED + 1, SettlementTestSupport.control())
	assert_bool(a.lottery_parcels == b.lottery_parcels).is_true()
	assert_bool(a.lottery_parcels == SettlementTestSupport.light().lottery_parcels).is_true()
