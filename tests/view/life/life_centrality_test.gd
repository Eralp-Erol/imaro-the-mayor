extends GdUnitTestSuite
## D-014 §4 (Q-026) · Merkez/çeper yoğunluğu: araç/yaya sayısı kenarın çevresindeki SİM yapılaşma yoğunluğuna göre
## ölçeklenir (merkezde 2 kat, çeperde 0,8 kat; `data/view/life.json` "centrality"). Sayı hâlâ sim faaliyetinden türer:
## faaliyet 0 ise merkezde de araç/yaya yok. Profil tavanları (max_cars / max_people) aşılmaz. Deterministik.
## Sentetik yerel yol ızgarası; sayılar elle hesaplanmış kesin değerlerdir (çarpan 2,0 / 0,8, oran 2,5).

const DX := 160.0
const DZ := 100.0
const ORIGIN := Vector2(500.0, 500.0)

var _world: WorldData
var _long_world: WorldData


func before() -> void:
	_world = NetworkTestSupport.flat_world(3000.0)
	_long_world = NetworkTestSupport.flat_world(8000.0)


func _cfg(lo: float, hi: float, edge_m: float, center_m: float, profile: StringName = &"desktop") -> LifeConfig:
	var cfg := LifeConfig.load_default(profile)
	cfg.data["centrality"]["density_lo_per_km2"] = lo
	cfg.data["centrality"]["density_hi_per_km2"] = hi
	cfg.data["centrality"]["edge_multiplier"] = edge_m
	cfg.data["centrality"]["center_multiplier"] = center_m
	return cfg


func _small_net() -> WorldNetwork:
	return NetworkTestSupport.grid_network(_world, 3, 3, DX, DZ, ORIGIN)


## 20 x 2 blok = 3,2 km x 200 m uzun şerit (batıdan doğuya).
func _strip_net() -> WorldNetwork:
	return NetworkTestSupport.grid_network(_long_world, 20, 2, DX, DZ, ORIGIN)


func _act(net: WorldNetwork, cfg: LifeConfig, units: Vector3i) -> LifeEdgeActivity:
	var act := LifeEdgeActivity.create(net, cfg)
	for pid: int in net.parcels:
		act.set_parcel(pid, units)
	return act


func _ground(_x: float, _z: float) -> float:
	return 10.0


func test_default_config_has_the_user_ratios_2x_center_and_not_denser_rim() -> void:
	var cfg := LifeConfig.load_default()
	assert_float(cfg.centrality("center_multiplier")).is_equal(2.0)
	assert_float(cfg.centrality("edge_multiplier")).is_less_equal(1.0)
	assert_float(cfg.centrality("edge_multiplier")).is_greater(0.0)
	assert_float(cfg.centrality("density_hi_per_km2")).is_greater(cfg.centrality("density_lo_per_km2"))


func test_dense_surroundings_give_the_center_multiplier_and_sparse_the_edge_multiplier() -> void:
	var net := _small_net()
	var dense := _act(net, _cfg(100.0, 200.0, 0.8, 2.0), Vector3i(40, 0, 0))
	var sparse := _act(net, _cfg(1.0e9, 2.0e9, 0.8, 2.0), Vector3i(40, 0, 0))
	assert_int(dense.eligible.size()).is_greater(0)
	for eid: int in dense.eligible:
		assert_float(dense.edge_multiplier(eid)).is_equal_approx(2.0, 0.0001)
		assert_float(sparse.edge_multiplier(eid)).is_equal_approx(0.8, 0.0001)


func test_center_is_exactly_2x_todays_value_and_2_5x_the_rim_for_the_same_sim_activity() -> void:
	# Aynı sim birimleri (aynı faaliyet): yalnız çarpan farklı. Küçük birim = tavana çarpmaz (saf oran).
	var net := _small_net()
	var units := Vector3i(2, 0, 0)
	var flat := _act(net, _cfg(100.0, 200.0, 1.0, 1.0), units)   # bugünkü düz yoğunluk
	var center := _act(net, _cfg(0.001, 0.002, 0.8, 2.0), units)
	var rim := _act(net, _cfg(1.0e9, 2.0e9, 0.8, 2.0), units)
	var f := flat.totals(1.0)
	var c := center.totals(1.0)
	var r := rim.totals(1.0)
	assert_float(f.x).is_greater(0.0)
	assert_float(c.x / f.x).is_equal_approx(2.0, 0.0001)
	assert_float(c.y / f.y).is_equal_approx(2.0, 0.0001)
	assert_float(r.x / f.x).is_equal_approx(0.8, 0.0001)
	assert_float(c.x / r.x).is_equal_approx(2.5, 0.0001)


func test_zero_sim_activity_means_zero_cars_and_people_even_in_the_center() -> void:
	var net := _small_net()
	var act := LifeEdgeActivity.create(net, _cfg(0.001, 0.002, 0.8, 2.0))
	assert_vector(act.totals(1.0)).is_equal(Vector2.ZERO)
	# Merkez çarpanı faaliyeti olmayan kenara hiçbir şey eklemez: yalnız bir parsel dolu, uzak kenarlar boş kalır.
	var pid := int(net.parcels.keys()[0])
	act.set_parcel(pid, Vector3i(30, 0, 0))
	var far_empty := 0
	for eid: int in act.eligible:
		if act.activity(eid) == 0.0:
			far_empty += 1
			assert_vector(act.expected(eid, 1.0)).is_equal(Vector2.ZERO)
	assert_int(far_empty).is_greater(0)
	act.set_parcel(pid, Vector3i.ZERO)
	assert_vector(act.totals(1.0)).is_equal(Vector2.ZERO)


func test_density_fades_from_center_to_rim_along_a_gradient() -> void:
	# Batı ucunda yoğun, doğuya doğru doğrusal azalan yapılaşma (sim birimleri): merkezilik tek yönlü söner.
	var net := _strip_net()
	var cfg := LifeConfig.load_default()
	var act := LifeEdgeActivity.create(net, cfg)
	for pid: int in net.parcels:
		var p: WorldParcel = net.parcels[pid]
		var k := clampf(1.0 - (p.centroid.x - ORIGIN.x) / (20.0 * DX), 0.0, 1.0)
		act.set_parcel(pid, Vector3i(int(round(200.0 * k * k)), 0, 0))
	var by_x: Dictionary = {}
	for eid: int in act.eligible:
		var e: WorldRoadEdge = net.edges[eid]
		var mid := (net.node_pos(e.a) + net.node_pos(e.b)) * 0.5
		var cell := act.cell_of(mid)
		by_x[cell.x] = maxf(float(by_x.get(cell.x, 0.0)), act.centrality(cell))
	var xs: Array = by_x.keys()
	xs.sort()
	assert_int(xs.size()).is_greater(5)
	# Batı ucundaki ilk hücre yarım komşuluk görür (şeridin dışı boş); tek yönlü sönüm ikinci hücreden başlar.
	var prev := 2.0
	for i in range(1, xs.size()):
		assert_float(float(by_x[xs[i]])).is_less_equal(prev + 0.0001)
		prev = float(by_x[xs[i]])
	assert_float(float(by_x[xs[1]])).is_greater(0.9)   # merkez
	assert_float(float(by_x[xs[-1]])).is_less(0.05)   # çeper
	var west_mult := 0.0
	var east_mult := 99.0
	var west_x: float = INF
	var east_x: float = -INF
	for eid: int in act.eligible:
		var e: WorldRoadEdge = net.edges[eid]
		var mx := (net.node_pos(e.a).x + net.node_pos(e.b).x) * 0.5
		if mx < west_x:
			west_x = mx
			west_mult = act.edge_multiplier(eid)
		if mx > east_x:
			east_x = mx
			east_mult = act.edge_multiplier(eid)
	assert_float(west_mult).is_greater(1.8)
	assert_float(east_mult).is_less_equal(1.0)


func test_class_caps_scale_with_the_center_multiplier_so_the_2x_is_not_clipped() -> void:
	var net := _small_net()
	var act := _act(net, LifeConfig.load_default(), Vector3i(500, 500, 500))
	var cap := act.cfg.class_row(&"local")
	var mult := act.cfg.centrality("center_multiplier")
	var clipped := 0
	for eid: int in act.eligible:
		var e: WorldRoadEdge = net.edges[eid]
		var ex := act.expected(eid, 1.0)
		var limit_cars := float(cap["cars_cap_per_100m"]) * e.length / 100.0 * mult
		assert_float(ex.x).is_less_equal(limit_cars + 0.0001)
		assert_float(ex.y).is_less_equal(float(cap["people_cap_per_100m"]) * e.length / 100.0 * mult + 0.0001)
		if absf(ex.x - limit_cars) < 0.0001:
			clipped += 1
	assert_int(clipped).is_greater(0)   # aşırı yük gerçekten tavanda durur (taşma emniyeti çalışıyor)


func test_clearing_the_center_returns_the_edge_multiplier_and_dirty_marks_neighbours() -> void:
	var net := _small_net()
	var act := LifeEdgeActivity.create(net, LifeConfig.load_default())
	act.step_rebuild(1)
	for pid: int in net.parcels:
		act.set_parcel(pid, Vector3i(60, 0, 0))
	assert_float(act.centrality(Vector2i(2, 2))).is_greater(0.9)
	act.take_dirty_cells()
	for pid: int in net.parcels:
		act.set_parcel(pid, Vector3i.ZERO)
	assert_float(act.centrality(Vector2i(2, 2))).is_equal(0.0)
	for eid: int in act.eligible:
		assert_float(act.edge_multiplier(eid)).is_equal_approx(act.cfg.centrality("edge_multiplier"), 0.0001)


func test_rebuild_gives_the_same_centrality_as_incremental_updates() -> void:
	var net := _small_net()
	var inc := LifeEdgeActivity.create(net, LifeConfig.load_default())
	var full := LifeEdgeActivity.create(net, LifeConfig.load_default())
	for pid: int in net.parcels:
		inc.set_parcel(pid, Vector3i(7, 3, 2))
		full.parcel_state[pid] = Vector3i(7, 3, 2)
	full.begin_rebuild()
	full.step_rebuild(1000000)
	for cell: Vector2i in inc.cells():
		assert_float(full.built_density_per_km2(cell)).is_equal_approx(inc.built_density_per_km2(cell), 0.001)
		assert_float(full.centrality(cell)).is_equal_approx(inc.centrality(cell), 0.00001)


func test_layout_with_centrality_is_deterministic() -> void:
	var net := _small_net()
	var a := _act(net, LifeConfig.load_default(), Vector3i(12, 4, 0))
	var b := _act(net, LifeConfig.load_default(), Vector3i(12, 4, 0))
	var cell: Vector2i = a.cells()[0]
	var ra := LifeLayout.build_cell(a, cell, 7, 1.0, _ground, PackedInt32Array([3, 4]), LifeLayout.sidewalk_table())
	var rb := LifeLayout.build_cell(b, cell, 7, 1.0, _ground, PackedInt32Array([3, 4]), LifeLayout.sidewalk_table())
	for kind in LifeLayout.KIND_COUNT:
		assert_array(Array(ra["rows"][kind] as PackedFloat32Array)).is_equal(Array(rb["rows"][kind] as PackedFloat32Array))
	assert_array(Array(ra["counts"] as PackedInt32Array)).is_equal(Array(rb["counts"] as PackedInt32Array))


func test_view_never_exceeds_the_profile_ceilings_even_with_the_2x_center() -> void:
	var net := _small_net()
	var cfg := LifeConfig.load_default()
	var act := _act(net, cfg, Vector3i(80, 20, 0))
	# Hücre başına sayıları ölç; tavanı "en büyük hücre + 1" yap: >= 2 hücre sığmaz, bütçe devreye girmeli.
	var gate := LibraryGate.new()
	gate.report_errors = false
	gate.load_game_tables(PackedStringArray(LibraryGate.LIFE_TABLE_PATHS), LibraryGate.CATALOG_PATH)
	var assets := LifeAssets.load_default(gate)
	var max_car_cell := 0
	var max_ppl_cell := 0
	var tot_cars := 0
	var tot_ppl := 0
	for cell: Vector2i in act.cells():
		var counts := LifeLayout.build_cell(act, cell, 7, cfg.density(), _ground, assets.car_rows,
				LifeLayout.sidewalk_table())["counts"] as PackedInt32Array
		var ppl := counts[LifeLayout.KIND_NEUTRAL] + counts[LifeLayout.KIND_BROAD]
		max_car_cell = maxi(max_car_cell, counts[LifeLayout.KIND_CAR])
		max_ppl_cell = maxi(max_ppl_cell, ppl)
		tot_cars += counts[LifeLayout.KIND_CAR]
		tot_ppl += ppl
	var car_ceiling := max_car_cell + 1
	var ppl_ceiling := max_ppl_cell + 1
	assert_int(tot_cars).is_greater(car_ceiling)   # önkoşul: tavan gerçekten kısıtlayıcı
	assert_int(tot_ppl).is_greater(ppl_ceiling)
	cfg.data["profiles"]["desktop"]["max_cars"] = car_ceiling
	cfg.data["profiles"]["desktop"]["max_people"] = ppl_ceiling
	var view := LifeView.new()
	add_child(view)
	auto_free(view)
	view.setup(cfg, assets, act, 7, _ground)
	view.track_camera(Vector3.ZERO, ORIGIN + Vector2(DX * 1.5, DZ * 1.5))
	view.settle()
	assert_int(view.stats["cars"]).is_less_equal(car_ceiling)
	assert_int(view.stats["people"]).is_less_equal(ppl_ceiling)
	assert_int(view.stats["cars"]).is_greater(0)
	assert_int(view.stats["skipped_over_budget"]).is_greater(0)


func test_default_profile_ceilings_are_unchanged() -> void:
	var cfg := LifeConfig.load_default()
	assert_int(int(cfg.profile_value("max_cars"))).is_equal(1600)
	assert_int(int(cfg.profile_value("max_people"))).is_equal(1400)


func test_bad_centrality_values_are_rejected() -> void:
	var raw := JSON.parse_string(FileAccess.get_file_as_string(LifeConfig.PATH)) as Dictionary
	var cases := {
		"bölüm yok": func(d: Dictionary) -> void: d.erase("centrality"),
		"hi <= lo": func(d: Dictionary) -> void: d["centrality"]["density_hi_per_km2"] = 10.0,
		"negatif çarpan": func(d: Dictionary) -> void: d["centrality"]["edge_multiplier"] = -0.5,
		"anahtar eksik": func(d: Dictionary) -> void: (d["centrality"] as Dictionary).erase("center_multiplier"),
	}
	for label in cases:
		var data := raw.duplicate(true)
		(cases[label] as Callable).call(data)
		var path := "user://life_cen_bad_%d.json" % absi(String(label).hash())
		var fh := FileAccess.open(path, FileAccess.WRITE)
		fh.store_string(JSON.stringify(data))
		fh.close()
		assert_bool(LifeConfig.load_path(path).valid()).override_failure_message("%s kabul edildi" % label).is_false()
		DirAccess.remove_absolute(path)
