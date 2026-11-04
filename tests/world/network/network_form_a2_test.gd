extends GdUnitTestSuite
## T-049 A2 · Şehir formu "blok değil": D1/D6 çekirdeği dışbükey, tek yönlü, ızgara hizalı bir blok olmamalı.
## Kanıtlar (ağ düzeyi, tam Ismeral): (1) parsel maskesi dışbükeylik/solidity oranı eşiğin altında, (2) sokak yönelimi
## çekirdekten çevreye değişir (twist) ve tek baskın yöne yığılmaz, (3) cepler/uydu parçalar ayak izi içinde AÇIK arazi
## bırakır. Olumsuz kontrol: bend + pockets kapalı ağ bu eşikleri geçemez (testin gerçekten ölçtüğünün kanıtı).
## Koordinat sınanmaz (Q-015); yalnız biçim metrikleri.

const URBAN := ["core", "compact", "mixed"]
const MASK_CELL_M := 60.0
## Eski (A1) D1/D6 solidity ~0.90-0.93; A2 hedefi belirgin altında.
const MAX_SOLIDITY := 0.86
## Çekirdek (t < 0.25) ile çevre (0.6 < t < 1) ortalama sokak yönü farkı (derece, 90'a göre dairesel).
const MIN_TWIST_DELTA_DEG := 7.0
## Bölgedeki sokak kenarlarının baskın yönün +-10 derecesindeki payı: düz tek ızgara ~1.0.
const MAX_ALIGNED_SHARE := 0.85

var _net: WorldNetwork
var _plain: WorldNetwork


func before() -> void:
	_net = NetworkTestSupport.default_network()
	var c := NetworkTestSupport.network_control()
	for code in ["D1", "D6"]:
		var o: Dictionary = c["organic"]["fabrics"][code]
		o["bend"] = {"twist": {"deg": 0.0, "r0_m": 300.0, "r1_m": 2400.0}, "disp": {"amp_m": 0.0, "cell_m": 600.0}}
		o["pockets"] = {"thr_inner": 9.0, "thr_outer": 9.0}
		# A1 kontrolü: eski (zayıf) sınır gürültüsü/şerit/kıyı — A2 yalnız bend+pockets+güçlü sınır değil, hepsi birlikte.
		o["noise"] = {"cell_m": [1300.0, 500.0], "amp": [0.2, 0.08]}
		o["ribbon"] = {"gain": 0.55, "sigma_m": 330.0}
		o["shore"] = {"near_m": 150.0, "far_m": 800.0, "gain": 0.1}
	_plain = NetworkTestSupport.generate(c)


static func _urban_centroids(net: WorldNetwork, code: StringName) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for pid: int in net.parcels:
		var p: WorldParcel = net.parcels[pid]
		if p.region_code == code and URBAN.has(String(p.fabric)):
			out.append(p.centroid)
	return out


## Parsel maskesinin (1 hücre kapanışlı) alanı / dışbükey zarf alanı.
static func _solidity(points: Array[Vector2]) -> float:
	var filled := {}
	for c in points:
		var k := Vector2i(floori(c.x / MASK_CELL_M), floori(c.y / MASK_CELL_M))
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				filled[k + Vector2i(dx, dy)] = true
	var pts := PackedVector2Array()
	for k: Vector2i in filled:
		pts.append(Vector2(k) * MASK_CELL_M)
	var hull := Geometry2D.convex_hull(pts)
	var area2 := 0.0
	for i in hull.size():
		var a := hull[i]
		var b := hull[(i + 1) % hull.size()]
		area2 += a.x * b.y - b.x * a.y
	return float(filled.size()) * MASK_CELL_M * MASK_CELL_M / maxf(absf(area2) * 0.5, 1.0)


## Sokak kenarı yönleri (rad, [0, PI/2) = 90 derece dönüşlü) — fp içinde, `t_lo <= t < t_hi` bandında.
static func _orientations(net: WorldNetwork, code: StringName, t_lo: float, t_hi: float) -> PackedFloat32Array:
	var fp := net.rules.footprint_by_id(code)
	var out := PackedFloat32Array()
	for eid: int in net.edges:
		var e: WorldRoadEdge = net.edges[eid]
		if e.mode() != &"road" or e.road_class == WorldRoadEdge.CLASS_ARTERIAL:
			continue
		var a := net.node_pos(e.a)
		var b := net.node_pos(e.b)
		var t := fp.norm_dist((a + b) * 0.5)
		if t < t_lo or t >= t_hi or (b - a).length() < 20.0 or (b - a).length() > 400.0:
			continue
		out.append(fposmod((b - a).angle(), PI * 0.5))
	return out


## 90 derece periyotlu dairesel ortalama yön (rad).
static func _mean_axis(values: PackedFloat32Array) -> float:
	var sx := 0.0
	var sy := 0.0
	for v in values:
		sx += cos(4.0 * v)
		sy += sin(4.0 * v)
	return fposmod(atan2(sy, sx) / 4.0, PI * 0.5)


static func _axis_delta_deg(a: float, b: float) -> float:
	var d := absf(a - b)
	d = minf(d, PI * 0.5 - d)
	return rad_to_deg(d)


static func _aligned_share(values: PackedFloat32Array) -> float:
	var axis := _mean_axis(values)
	var n := 0
	for v in values:
		if _axis_delta_deg(v, axis) <= 10.0:
			n += 1
	return float(n) / float(maxi(values.size(), 1))


func test_core_districts_are_not_convex_blocks() -> void:
	for code in [&"D1", &"D6"]:
		var s := _solidity(_urban_centroids(_net, code))
		assert_float(s).override_failure_message("%s solidity %.3f" % [code, s]).is_less(MAX_SOLIDITY)


func test_negative_without_bend_and_pockets_the_core_is_a_convex_block() -> void:
	for code in [&"D1", &"D6"]:
		var plain := _solidity(_urban_centroids(_plain, code))
		var organic := _solidity(_urban_centroids(_net, code))
		assert_float(plain).override_failure_message("%s düz %.3f organik %.3f" % [code, plain, organic]) \
				.is_greater(organic + 0.05)


func test_street_direction_changes_from_the_old_core_to_the_outskirts() -> void:
	for code in [&"D1", &"D6"]:
		var inner := _orientations(_net, code, 0.0, 0.25)
		var outer := _orientations(_net, code, 0.6, 1.0)
		assert_int(inner.size()).is_greater(30)
		assert_int(outer.size()).is_greater(30)
		var delta := _axis_delta_deg(_mean_axis(inner), _mean_axis(outer))
		assert_float(delta).override_failure_message("%s çekirdek/çevre yön farkı %.1f" % [code, delta]) \
				.is_greater(MIN_TWIST_DELTA_DEG)


func test_negative_without_twist_the_direction_is_uniform() -> void:
	for code in [&"D1", &"D6"]:
		var inner := _orientations(_plain, code, 0.0, 0.25)
		var outer := _orientations(_plain, code, 0.6, 1.0)
		var delta := _axis_delta_deg(_mean_axis(inner), _mean_axis(outer))
		assert_float(delta).override_failure_message("%s düz ızgara yön farkı %.1f" % [code, delta]).is_less(4.0)


func test_streets_do_not_collapse_onto_one_grid_direction() -> void:
	for code in [&"D1", &"D6"]:
		var all := _orientations(_net, code, 0.0, 1.0)
		var share := _aligned_share(all)
		assert_float(share).override_failure_message("%s tek yön payı %.2f" % [code, share]) \
				.is_less(MAX_ALIGNED_SHARE)
		var plain := _aligned_share(_orientations(_plain, code, 0.0, 1.0))
		assert_float(plain).override_failure_message("%s düz tek yön payı %.2f, organik %.2f" % [code, plain, share]) \
				.is_greater(share + 0.05)


func test_pockets_leave_open_land_inside_the_footprint() -> void:
	# Cepli ağda D1+D6 sokak düğümü azalır (çıkarılan ızgara noktaları); çekirdek (t < t_min) korunur.
	var with_n := 0
	var without_n := 0
	for code in [&"D1", &"D6"]:
		var fp := _net.rules.footprint_by_id(code)
		for nid: int in _net.nodes:
			if fp.norm_dist(_net.node_pos(nid)) <= 1.0:
				with_n += 1
		var fp2 := _plain.rules.footprint_by_id(code)
		for nid: int in _plain.nodes:
			if fp2.norm_dist(_plain.node_pos(nid)) <= 1.0:
				without_n += 1
	assert_int(with_n).override_failure_message("cepli %d düz %d" % [with_n, without_n]).is_less(without_n)


func test_no_coordinates_in_bend_or_pocket_data() -> void:
	var text := JSON.stringify(NetworkTestSupport.network_control()["organic"])
	for key in ["anchor_km", "pos_km", "center_km", "outline_km", "position"]:
		assert_bool(text.contains(key)).is_false()
