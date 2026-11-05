extends GdUnitTestSuite
## T-050 · Yaşam sayısı SİM VERİSİNDEN gelir (aktivite yoksa sahte trafik yok), yerleşim saf ve deterministik:
## aynı (ağ, durum, seed) -> aynı satırlar; seed yalnız konum/faz üretir, SAYIYI değiştirmez; sayı arttıkça eski örnek
## yerinden oynamaz. Sentetik 3x3 yerel yol ızgarası (blok başına parseller), kesin sayılarla.

const DX := 160.0
const DZ := 100.0
const ORIGIN := Vector2(500.0, 500.0)

var _world: WorldData
var _cfg: LifeConfig


func before() -> void:
	_world = NetworkTestSupport.flat_world(3000.0)
	_cfg = LifeConfig.load_default()


func _net() -> WorldNetwork:
	return NetworkTestSupport.grid_network(_world, 3, 3, DX, DZ, ORIGIN)


func _activity(net: WorldNetwork) -> LifeEdgeActivity:
	return LifeEdgeActivity.create(net, _cfg)


func _fill(act: LifeEdgeActivity, state: Vector3i) -> void:
	for pid: int in act.net.parcels:
		act.set_parcel(pid, state)


func _ground(_x: float, _z: float) -> float:
	return 10.0


func _build(act: LifeEdgeActivity, cell: Vector2i, world_seed: int = 7, density: float = 1.0) -> Dictionary:
	return LifeLayout.build_cell(act, cell, world_seed, density, _ground, PackedInt32Array([3, 4, 5]),
			LifeLayout.sidewalk_table())


func _totals(act: LifeEdgeActivity, world_seed: int = 7, density: float = 1.0) -> Vector3i:
	var out := Vector3i.ZERO
	for cell: Vector2i in act.cells():
		var counts := (_build(act, cell, world_seed, density)["counts"]) as PackedInt32Array
		out += Vector3i(counts[LifeLayout.KIND_CAR], counts[LifeLayout.KIND_NEUTRAL], counts[LifeLayout.KIND_BROAD])
	return out


func _row_set(rows: PackedFloat32Array) -> Dictionary:
	var out := {}
	for i in rows.size() / LifeLayout.ROW:
		var parts: PackedStringArray = PackedStringArray()
		for v in rows.slice(i * LifeLayout.ROW, (i + 1) * LifeLayout.ROW):
			parts.append("%.3f" % v)
		out[",".join(parts)] = true
	return out


func test_no_sim_activity_means_no_cars_and_no_people() -> void:
	var act := _activity(_net())
	assert_int(act.stats["edges_eligible"]).is_greater(0)
	assert_vector(act.totals(1.0)).is_equal(Vector2.ZERO)
	assert_vector(Vector3(_totals(act))).is_equal(Vector3.ZERO)


func test_residential_stock_creates_activity_on_the_frontage_edges() -> void:
	var act := _activity(_net())
	_fill(act, Vector3i(4, 0, 0))
	act.step_rebuild(1000000)
	var totals := act.totals(1.0)
	assert_float(totals.x).is_greater(0.0)
	assert_float(totals.y).is_greater(0.0)
	var made := _totals(act)
	assert_int(made.x).is_greater(0)
	assert_int(made.y + made.z).is_greater(0)


func test_more_units_never_means_fewer_instances_and_old_ones_stay_in_place() -> void:
	var net := _net()
	var low := _activity(net)
	_fill(low, Vector3i(2, 0, 0))
	var high := _activity(net)
	_fill(high, Vector3i(10, 0, 0))
	var low_total := _totals(low)
	var high_total := _totals(high)
	assert_int(high_total.x).is_greater_equal(low_total.x)
	assert_int(high_total.y + high_total.z).is_greater_equal(low_total.y + low_total.z)
	for cell: Vector2i in low.cells():
		var a := _build(low, cell)
		var b := _build(high, cell)
		for kind in LifeLayout.KIND_COUNT:
			var set_b := _row_set(b["rows"][kind] as PackedFloat32Array)
			for key in _row_set(a["rows"][kind] as PackedFloat32Array):
				assert_bool(set_b.has(key)).override_failure_message("örnek yerinden oynadı: %s" % key).is_true()


func test_commercial_units_weigh_more_than_residential_units() -> void:
	var net := _net()
	var res := _activity(net)
	_fill(res, Vector3i(5, 0, 0))
	var com := _activity(net)
	_fill(com, Vector3i(0, 5, 0))
	assert_float(com.totals(1.0).x).is_greater(res.totals(1.0).x)


func test_construction_sites_show_activity_before_the_building_is_finished() -> void:
	var act := _activity(_net())
	_fill(act, Vector3i(0, 0, 6))
	assert_float(act.totals(1.0).x).is_greater(0.0)


func test_low_occupancy_reduces_residential_activity_only() -> void:
	var net := _net()
	var full := _activity(net)
	_fill(full, Vector3i(8, 0, 0))
	var half := _activity(net)
	half.occupancy[&"D1"] = 0.25
	_fill(half, Vector3i(8, 0, 0))
	assert_float(half.totals(1.0).x).is_less(full.totals(1.0).x)
	var shops := _activity(net)
	shops.occupancy[&"D1"] = 0.25
	_fill(shops, Vector3i(0, 8, 0))
	var shops_full := _activity(net)
	_fill(shops_full, Vector3i(0, 8, 0))
	assert_float(shops.totals(1.0).x).is_equal_approx(shops_full.totals(1.0).x, 0.0001)


func test_clearing_a_parcel_removes_its_contribution() -> void:
	var act := _activity(_net())
	_fill(act, Vector3i(6, 0, 0))
	var before_total := act.totals(1.0).x
	for pid: int in act.net.parcels:
		act.set_parcel(pid, Vector3i.ZERO)
	assert_float(before_total).is_greater(0.0)
	assert_float(act.totals(1.0).x).is_equal(0.0)
	assert_int(act.edge_units.size()).is_equal(0)


func test_counts_never_exceed_the_class_cap() -> void:
	var act := _activity(_net())
	_fill(act, Vector3i(500, 500, 500))
	var cap := _cfg.class_row(&"local")
	# Tavan merkez çarpanı kadar yükselir (D-014 §4): aşırı yükte kenar en çok tavan x çarpan taşır.
	var scale := maxf(1.0, _cfg.centrality("center_multiplier"))
	for eid: int in act.eligible:
		var e: WorldRoadEdge = act.net.edges[eid]
		var ex := act.expected(eid, 1.0)
		assert_float(ex.x).is_less_equal(float(cap["cars_cap_per_100m"]) * e.length / 100.0 * scale + 0.0001)
		assert_float(ex.y).is_less_equal(float(cap["people_cap_per_100m"]) * e.length / 100.0 * scale + 0.0001)


func test_layout_is_deterministic_and_seed_changes_positions_not_counts() -> void:
	var act := _activity(_net())
	_fill(act, Vector3i(6, 2, 1))
	var cell: Vector2i = act.cells()[0]
	var a := _build(act, cell, 7)
	var b := _build(act, cell, 7)
	for kind in LifeLayout.KIND_COUNT:
		assert_array(Array(a["rows"][kind] as PackedFloat32Array)).is_equal(Array(b["rows"][kind] as PackedFloat32Array))
	assert_vector(Vector3(_totals(act, 7))).is_equal(Vector3(_totals(act, 7)))
	# Seed sayıyı belirlemez: toplam araç/insan sayısı yuvarlama dışında aynı kalır (beklenen sayı aynı),
	# konum/faz değişir.
	var t7 := _totals(act, 7)
	var t99 := _totals(act, 99)
	assert_int(absi(t7.x - t99.x)).is_less_equal(maxi(2, int(t7.x * 0.25)))
	var rows_a := a["rows"][LifeLayout.KIND_CAR] as PackedFloat32Array
	var rows_c := _build(act, cell, 99)["rows"][LifeLayout.KIND_CAR] as PackedFloat32Array
	assert_bool(rows_a == rows_c).is_false()


func test_rows_are_well_formed_and_sit_inside_the_reported_bounds() -> void:
	var act := _activity(_net())
	_fill(act, Vector3i(8, 3, 0))
	for cell: Vector2i in act.cells():
		var res := _build(act, cell)
		var counts := res["counts"] as PackedInt32Array
		for kind in LifeLayout.KIND_COUNT:
			var rows := res["rows"][kind] as PackedFloat32Array
			assert_int(rows.size()).is_equal(counts[kind] * LifeLayout.ROW)
			for i in counts[kind]:
				var o := i * LifeLayout.ROW
				assert_float(rows[o + 5]).is_greater(0.0)   # parça uzunluğu
				assert_float(rows[o + 4]).is_between(0.5, 1.5)   # ölçek
				var packed := int(rows[o + 8])
				assert_int(packed & 1023).is_between(0, 1023)
				assert_int((packed >> 10) & 15).is_between(0, 15)
				var local := Vector3(rows[o], rows[o + 1], rows[o + 2])
				assert_bool((res["bounds"] as AABB).grow(1.0).has_point(local)).is_true()


func test_graph_change_reindexes_edges_and_new_roads_gain_life() -> void:
	var net := _net()
	var act := _activity(net)
	_fill(act, Vector3i(4, 0, 0))
	act.step_rebuild(1000000)
	var edges_before: int = act.stats["edges_eligible"]
	var graph_before := net.graph_version
	var edge_count_before := net.edges.size()
	var path := PackedVector2Array([ORIGIN + Vector2(0, -150.0), ORIGIN + Vector2(3 * DX, -150.0)])
	var res := net.add_road(path, WorldRoadEdge.CLASS_LOCAL)
	assert_bool(bool(res.get("ok", false))).override_failure_message(str(res)).is_true()
	assert_int(net.edges.size()).override_failure_message(str(res)).is_greater(edge_count_before)
	assert_int(net.graph_version).is_greater(graph_before)
	act.index_edges()
	assert_int(act.stats["edges_eligible"]).is_greater(edges_before)


## B-040: kare dilimli dizin + parsel toplamı (yol onayı sonrası ana iş parçacığı sıçramasını önler) SENKRON yolla AYNI
## sonucu verir; her dilimde en az 32 kenar/parsel ilerler (bütçe 0 olsa da takılmaz); sürerken `is_rebuilding()` true.
func test_sliced_refresh_matches_the_synchronous_result() -> void:
	var net := _net()
	var sync_act := _activity(net)
	_fill(sync_act, Vector3i(4, 2, 1))
	sync_act.step_rebuild(1000000)
	var path := PackedVector2Array([ORIGIN + Vector2(0, -150.0), ORIGIN + Vector2(3 * DX, -150.0)])
	assert_bool(bool(net.add_road(path, WorldRoadEdge.CLASS_LOCAL).get("ok", false))).is_true()
	sync_act.index_edges()
	sync_act.begin_rebuild()
	sync_act.step_rebuild(1000000)
	var sliced := _activity(net)
	_fill(sliced, Vector3i(4, 2, 1))
	var calls := 1
	var done := sliced.step_refresh(0, true)
	assert_bool(done).is_false()
	while not done:
		assert_bool(sliced.is_rebuilding()).is_true()
		done = sliced.step_refresh(0)
		calls += 1
		assert_int(calls).is_less(100000)
	assert_bool(sliced.is_rebuilding()).is_false()
	assert_int(sliced.stats["edges_eligible"]).is_equal(sync_act.stats["edges_eligible"])
	assert_array(sliced.eligible.keys()).is_equal(sync_act.eligible.keys())
	assert_array(sliced.cells()).is_equal(sync_act.cells())
	for eid: int in sync_act.eligible:
		assert_vector(Vector3(sliced.edge_units.get(eid, Vector3i.ZERO))).is_equal(
				Vector3(sync_act.edge_units.get(eid, Vector3i.ZERO)))
	assert_vector(sliced.totals(1.0)).is_equal(sync_act.totals(1.0))
	assert_int(sliced.stats["parcels_mapped"]).is_equal(sync_act.stats["parcels_mapped"])


func test_sliced_refresh_restarts_cleanly_and_nothing_to_do_returns_true() -> void:
	var act := _activity(_net())
	_fill(act, Vector3i(3, 0, 0))
	act.step_rebuild(1000000)
	assert_bool(act.step_refresh(0)).is_true()  # iş yok
	var totals_before := act.totals(1.0)
	var keys_before := act.eligible.keys()
	assert_bool(act.step_refresh(0, true)).is_false()
	assert_bool(act.step_refresh(0, true)).is_false()  # sürerken yeniden başlatma: baştan, bozulma yok
	var guard := 0
	while not act.step_refresh(0):
		guard += 1
		assert_int(guard).is_less(100000)
	assert_array(act.eligible.keys()).is_equal(keys_before)
	assert_vector(act.totals(1.0)).is_equal(totals_before)


## B-041: `begin_rebuild` parsel kimliklerini PackedInt64Array ile sıralar (Array.sort'tan ~3x hızlı); işleme sırası
## `parcel_state` ekleme sırasından bağımsız, artan kimliktir (sonuç sözlüklerinin ekleme sırası aynı kalır).
func test_rebuild_visits_parcels_in_ascending_id_order_regardless_of_insertion_order() -> void:
	var act := _activity(_net())
	var ids: Array = act.net.parcels.keys()
	ids.sort()
	assert_int(ids.size()).is_greater(3)
	var reversed := ids.duplicate()
	reversed.reverse()
	for pid: int in reversed:
		act.parcel_state[pid] = Vector3i(2, 1, 0)  # tersten ekle: dict ekleme sırası azalan
	assert_array(act.parcel_state.keys()).is_equal(reversed)
	act.begin_rebuild()
	assert_bool(act.step_rebuild(1000000)).is_true()
	var placed: Array = act._placed.keys()
	assert_int(placed.size()).is_greater(0)
	var sorted_placed := placed.duplicate()
	sorted_placed.sort()
	assert_array(placed).is_equal(sorted_placed)


func test_rebuild_with_no_parcels_finishes_immediately() -> void:
	var act := _activity(_net())
	act.begin_rebuild()
	assert_bool(act.is_rebuilding()).is_true()
	assert_bool(act.step_rebuild(10)).is_true()
	assert_bool(act.is_rebuilding()).is_false()
	assert_int(act.stats["parcels_mapped"]).is_equal(0)
