extends GdUnitTestSuite
## Yol birleşim (T / Y / bükülme) geometri sağlamlığı (2026-10-31 kırık/kama düzeltmesi).
## Ölçüt: şerit + kavşak dolgusu birleşimi, merkezden çıkan dikdörtgenlerin birleşimine (gerçek yol şekli) eşit olmalı:
## kama (fazla alan) ve delik (eksik alan) eşik altında, ters sarım yok, çift yüzey yok.
## Sentetik düz dünya; sim/ağ verisi değişmez.

const CENTER := Vector2(1500.0, 1500.0)
## Örnekleme adımı ve değerlendirme kutusu (m): 0.5 m ızgara, merkezden +-40 m.
const STEP_M := 0.5
const BOX_M := 40.0
## Kama/delik üst sınırı (m2): 80x80 m'lik kutuda ideal yol alanının %1'inden azı.
const MAX_WEDGE_FRACTION := 0.01
## Üçgen kenarına bu kadar yakın örnekler çift yüzey sayılmaz (float32 sınır belirsizliği).
const EDGE_TOL_M := 0.02

var _world: WorldData
var _net: WorldNetwork
var _style: RoadStyle


func before_test() -> void:
	_world = NetworkTestSupport.flat_world()
	_net = NetworkTestSupport.empty_network(_world)
	_style = RoadStyle.load_default()
	_style.data["chunk_m"] = 1000.0


## Merkezden `angle` derece yönünde, `length` uzunluğunda kol ekler.
func _arm(center: int, angle_deg: float, length: float, width: float, cls: StringName = &"local",
		draw_scale: float = 1.0) -> Dictionary:
	var dir := Vector2.from_angle(deg_to_rad(angle_deg))
	_net.add_edge_raw(center, _net.add_node_raw(CENTER + dir * length), cls, width)
	return {"dir": dir, "half": width * 0.5 * draw_scale, "length": length}


func _triangles(metro: bool = false) -> Array[PackedVector2Array]:
	var plan := RoadChunkPlan.build(_net, _style)
	var out: Array[PackedVector2Array] = []
	for key in plan.keys():
		var data := RoadMeshBuilder.build(_net, _style, plan, key, metro)
		var vertices: PackedVector3Array = data["vertices"]
		var normals: PackedVector3Array = data["normals"]
		for n in normals:
			assert_float(n.y).is_greater(0.0) # ters sarım yok (yüzey yukarı bakar)
		var origin := plan.rect(key).position
		for i in range(0, vertices.size(), 3):
			out.append(PackedVector2Array([
				Vector2(vertices[i].x, vertices[i].z) + origin,
				Vector2(vertices[i + 1].x, vertices[i + 1].z) + origin,
				Vector2(vertices[i + 2].x, vertices[i + 2].z) + origin]))
	return out


## Nokta üçgenin İÇİNDE ve herhangi bir kenara >= EDGE_TOL_M uzaklıkta mı (ortak kenardaki float32 sınır
## belirsizliği çift yüzey sayılmaz; gerçek çakışma kenardan uzakta da iki üçgene düşer).
func _solid_hit(p: Vector2, t: PackedVector2Array) -> bool:
	if not Geometry2D.is_point_in_polygon(p, t):
		return false
	for i in 3:
		var closest := Geometry2D.get_closest_point_to_segment(p, t[i], t[(i + 1) % 3])
		if closest.distance_to(p) < EDGE_TOL_M:
			return false
	return true


func _in_rect(p: Vector2, arm: Dictionary) -> bool:
	var rel := p - CENTER
	var along := rel.dot(arm["dir"])
	var across := rel.cross(arm["dir"])
	return along >= 0.0 and along <= float(arm["length"]) and absf(across) <= float(arm["half"])


## Kutu içinde ideal birleşim ile mesh örtüşmesini örnekler: [kama m2, delik m2, çift yüzey sayısı, ideal m2].
func _measure(arms: Array[Dictionary], metro: bool = false) -> Array:
	var triangles := _triangles(metro)
	var wedge := 0.0
	var hole := 0.0
	var doubled := 0
	var ideal := 0.0
	var cell := STEP_M * STEP_M
	var steps := int(BOX_M * 2.0 / STEP_M)
	for ix in steps:
		for iz in steps:
			# Üçgen kenarlarına denk gelmesin diye kaydırılmış örnek.
			var p := CENTER + Vector2(-BOX_M + (ix + 0.5) * STEP_M + 0.0173, -BOX_M + (iz + 0.5) * STEP_M + 0.0319)
			var want := false
			for arm in arms:
				if _in_rect(p, arm):
					want = true
					break
			var hits := 0
			var solid := 0
			for t in triangles:
				if Geometry2D.is_point_in_polygon(p, t):
					hits += 1
					if _solid_hit(p, t):
						solid += 1
			if want:
				ideal += cell
			if solid > 1:
				doubled += 1
			if want and hits == 0:
				hole += cell
			elif not want and hits > 0:
				wedge += cell
	return [wedge, hole, doubled, ideal]


func _check(arms: Array[Dictionary], metro: bool = false) -> void:
	var m := _measure(arms, metro)
	var limit := float(m[3]) * MAX_WEDGE_FRACTION
	assert_float(float(m[0])).is_less(limit)   # kama (fazla alan)
	assert_float(float(m[1])).is_less(limit)   # delik
	assert_int(int(m[2])).is_equal(0)          # çift yüzey


func test_t_junction_is_gap_free_wedge_free_at_all_branch_angles() -> void:
	for angle in [90.0, 60.0, 35.0, 20.0, -35.0, -90.0]:
		before_test()
		var center := _net.add_node_raw(CENTER)
		var arms: Array[Dictionary] = []
		arms.append(_arm(center, 0.0, 120.0, 15.0, &"collector"))
		arms.append(_arm(center, 180.0, 120.0, 15.0, &"collector"))
		arms.append(_arm(center, float(angle), 120.0, 10.0))
		_check(arms)


func test_t_junction_with_arterial_through_road_and_narrow_branch() -> void:
	var center := _net.add_node_raw(CENTER)
	var arms: Array[Dictionary] = []
	arms.append(_arm(center, 30.0, 120.0, 22.0, &"arterial"))
	arms.append(_arm(center, 210.0, 120.0, 22.0, &"arterial"))
	arms.append(_arm(center, 100.0, 120.0, 6.0, &"field"))
	_check(arms)


func test_wide_branch_on_narrow_through_road_and_four_way_cross() -> void:
	var center := _net.add_node_raw(CENTER)
	var arms: Array[Dictionary] = []
	arms.append(_arm(center, 0.0, 120.0, 8.0))
	arms.append(_arm(center, 180.0, 120.0, 8.0))
	arms.append(_arm(center, 90.0, 120.0, 20.0, &"arterial"))
	arms.append(_arm(center, 270.0, 120.0, 20.0, &"arterial"))
	_check(arms)


func test_end_to_end_continuation_with_bend_has_no_gap_or_overlap() -> void:
	# Mevcut yolun ucundan devam eden yeni yol (uçtan uca), hafif kıvrılmayla.
	for turn in [0.0, 12.0, -25.0]:
		before_test()
		var center := _net.add_node_raw(CENTER)
		var arms: Array[Dictionary] = []
		arms.append(_arm(center, 180.0, 120.0, 10.0))
		arms.append(_arm(center, float(turn), 120.0, 10.0))
		var m := _measure(arms)
		# Dış köşe pahı/mitre farkı ölçülür; delik ve çift yüzey kabul edilmez.
		assert_float(float(m[1])).is_less(float(m[3]) * MAX_WEDGE_FRACTION)
		assert_int(int(m[2])).is_equal(0)


func test_junction_triangle_budget_stays_small() -> void:
	var center := _net.add_node_raw(CENTER)
	_arm(center, 0.0, 120.0, 15.0, &"collector")
	_arm(center, 180.0, 120.0, 15.0, &"collector")
	_arm(center, 35.0, 120.0, 10.0)
	# Düzeltme öncesi ölçüm: 58 üçgen (120 m kollar, 40 m adım, hücre köşegen bölmeleri dahil). Bütçe aşılmaz.
	assert_int(_triangles().size()).is_less_equal(58)


func test_metro_junction_is_also_wedge_free() -> void:
	var center := _net.add_node_raw(CENTER)
	var arms: Array[Dictionary] = []
	var factor := float(_style.data["metro_width_scale"])
	# Ağdaki gerçek genişlik 15/10; metro çizimi 0,55x (ideal dikdörtgenler çizim genişliğiyle).
	arms.append(_arm(center, 0.0, 400.0, 15.0, &"collector", factor))
	arms.append(_arm(center, 180.0, 400.0, 15.0, &"collector", factor))
	arms.append(_arm(center, 40.0, 400.0, 10.0, &"local", factor))
	var m := _measure(arms, true)
	assert_float(float(m[0])).is_less(float(m[3]) * MAX_WEDGE_FRACTION)
	assert_float(float(m[1])).is_less(float(m[3]) * MAX_WEDGE_FRACTION)


func test_straight_continuation_has_no_junction_patch_and_t_through_road_far_side_is_untrimmed() -> void:
	# Düz devam (uçtan uca, eşit genişlik): kavşak dolgusu/kırpma yok, şeritler merkezde buluşur -> kaldırım kopmaz.
	var center := _net.add_node_raw(CENTER)
	_arm(center, 0.0, 120.0, 10.0)
	_arm(center, 180.0, 120.0, 10.0)
	var plan := RoadChunkPlan.build(_net, _style)
	for t: Vector2 in (plan.arm_trims[center] as Dictionary).values():
		assert_vector(t).is_equal(Vector2.ZERO)
	assert_int(int(RoadMeshBuilder.build(_net, _style, plan, plan.keys()[0])["junctions"])).is_equal(0)
	# T: geçiş yolunun branşa bakmayan (karşı) yan çizgisi kırpılmaz; yalnız branşa bakan yan kırpılır.
	before_test()
	center = _net.add_node_raw(CENTER)
	var through_a := _net.edges.size()
	_arm(center, 0.0, 120.0, 15.0, &"collector")
	_arm(center, 180.0, 120.0, 15.0, &"collector")
	_arm(center, 90.0, 120.0, 10.0)
	plan = RoadChunkPlan.build(_net, _style)
	var trims: Dictionary = plan.arm_trims[center]
	var far := 0
	for eid: int in trims:
		var t: Vector2 = trims[eid]
		if eid in [through_a + 1, through_a + 2]:
			# Eğim yönüne göre sağ/sol: biri 0 (karşı kenar), diğeri branş yarı genişliği (5 m).
			assert_float(minf(t.x, t.y)).is_equal_approx(0.0, 0.001)
			assert_float(maxf(t.x, t.y)).is_equal_approx(5.0, 0.001)
			far += 1
	assert_int(far).is_equal(2)
