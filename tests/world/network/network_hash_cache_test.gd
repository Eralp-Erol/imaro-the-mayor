extends GdUnitTestSuite
## Artımlı `WorldNetwork.graph_hash()` (NetworkHashCache) tam hesapla (`graph_hash_full()`) BİT-BİT aynıdır: yol ekleme,
## bölme, sınıf yükseltme, kenar silme/açma ve LIFO geri alma dizilerinde her adımda. Ayrıca eski (önbelleksiz) kodun
## ürettiği sabit değerler: GOLDEN/kayıt uyumu için hash DEĞERİ değişmemeli (tick maliyeti işi, T-043B bulgusu).

const DX := 160.0
const DZ := 100.0
const ORIGIN := Vector2(500.0, 500.0)
const LOCAL := WorldRoadEdge.CLASS_LOCAL
const SPUR: Array = [Vector2(580, 500), Vector2(580, 400)]
const LOOP: Array = [Vector2(660, 500), Vector2(660, 400), Vector2(820, 400), Vector2(820, 500)]
const SPLITTER: Array = [Vector2(580, 500), Vector2(580, 600)]
## Önbellek yokken (eski kodla) üretilmiş değerler: 3x3 ızgara, kural {} , tohum 7.
const OLD_G0 := "658858644f520376ccd0ebcb30bca3918cae2bd736791b92def614bd2e8e385f"
const OLD_G1 := "0cf572262733d254e3581e06d5ebf1d1b36817d4588f6774f1accebdf398b323"
const OLD_G2 := "92dbe22d88cd49cd15a2b3b592b11d676e6b6df7d8642ed703f2fe90774cc46c"
const OLD_G3 := "4c8ceccec3b3a5510beb1400d23ba9b3ceda451f9fa11b5d472698eb1eb59ffc"
const OLD_G4 := "c2a6c154eab85a7af4cddb0974d8249b618f5c8b695221163f662b733770e3a6"
const OLD_ISMERAL_BASE := "f09011ab9b7d9c90d39a4a607e2dd1eabc3497677569d7499617308293553013"

var _world: WorldData


func before() -> void:
	_world = NetworkTestSupport.flat_world(3000.0)


func _grid(extra: Dictionary = {}) -> WorldNetwork:
	return NetworkTestSupport.grid_network(_world, 3, 3, DX, DZ, ORIGIN, 7, extra)


func _same(net: WorldNetwork, label: String) -> void:
	assert_str(net.graph_hash()).override_failure_message("artımlı != tam: %s" % label).is_equal(net.graph_hash_full())


func test_old_code_values_are_unchanged_along_a_mixed_sequence() -> void:
	var net := _grid()
	assert_str(net.graph_hash()).is_equal(OLD_G0)
	assert_str(net.base_hash).is_equal(OLD_G0)
	assert_bool(net.add_road(PackedVector2Array(SPUR), LOCAL)["ok"]).is_true()
	assert_str(net.graph_hash()).is_equal(OLD_G1)
	assert_bool(net.add_road(PackedVector2Array(LOOP), LOCAL)["ok"]).is_true()
	assert_str(net.graph_hash()).is_equal(OLD_G2)
	assert_bool(net.set_edge_open(net.edges_near(580.0, 450.0, 3.0)[0].id, false)["ok"]).is_true()
	assert_str(net.graph_hash()).is_equal(OLD_G3)
	assert_bool(net.add_road(PackedVector2Array(SPLITTER), WorldRoadEdge.CLASS_COLLECTOR)["ok"]).is_true()
	assert_str(net.graph_hash()).is_equal(OLD_G4)
	assert_bool(net.undo_last_op()["ok"]).is_true()
	assert_str(net.graph_hash()).is_equal(OLD_G3)


func test_incremental_equals_full_after_every_step_and_undo() -> void:
	for extra: Dictionary in [{}, NetworkTestSupport.KEEP_PARCELS]:
		var net := _grid(extra)
		_same(net, "taban")
		for pts: Array in [SPUR, LOOP, SPLITTER]:
			assert_bool(net.add_road(PackedVector2Array(pts), LOCAL)["ok"]).is_true()
			_same(net, "yol %s" % str(pts))
		assert_bool(net.set_edge_open(net.edges_near(580.0, 450.0, 3.0)[0].id, false)["ok"]).is_true()
		_same(net, "set_open")
		var steps := 0
		while net.can_undo():
			assert_bool(net.undo_last_op()["ok"]).is_true()
			steps += 1
			_same(net, "geri alma %d" % steps)
		assert_int(steps).is_equal(4)
		assert_str(net.graph_hash()).is_equal(net.base_hash)


func test_class_upgrade_of_an_existing_edge_is_seen() -> void:
	# Eski kural: oyuncu yolu mevcut kenarın sınıfını yükseltir (`add_edge_raw` mevcut-kenar dalı); önbellek bunu görmeli.
	var net := _grid({})
	var before_hash := net.graph_hash()
	var along: Array = [ORIGIN, ORIGIN + Vector2(DX, 0.0)]
	assert_bool(net.add_road(PackedVector2Array(along), WorldRoadEdge.CLASS_ARTERIAL)["ok"]).is_true()
	assert_str(net.graph_hash()).is_not_equal(before_hash)
	_same(net, "sınıf yükseltme")
	assert_bool(net.undo_last_op()["ok"]).is_true()
	assert_str(net.graph_hash()).is_equal(before_hash)
	_same(net, "yükseltme geri alma")


func test_removing_edges_and_nodes_matches_full() -> void:
	var net := _grid({})
	assert_bool(net.add_road(PackedVector2Array(SPUR), LOCAL)["ok"]).is_true()
	var spur_edge: WorldRoadEdge = net.edges_near(580.0, 450.0, 3.0)[0]
	assert_bool(net.remove_edge(spur_edge.id)["ok"]).is_true()
	_same(net, "kenar silme")
	assert_bool(net.undo_last_op()["ok"]).is_true()
	_same(net, "silme geri alma")


func test_seeded_random_operation_sequences_match_full() -> void:
	for seed_value in [11, 12, 13]:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		var net := _grid({})
		var classes: Array[StringName] = [LOCAL, WorldRoadEdge.CLASS_COLLECTOR, WorldRoadEdge.CLASS_ARTERIAL]
		for step in 40:
			var pick := rng.randi_range(0, 9)
			if pick <= 4:
				var a := _random_point(rng)
				var b := a + Vector2(float(rng.randi_range(-3, 3)) * 40.0, float(rng.randi_range(-3, 3)) * 40.0)
				net.add_road(PackedVector2Array([a, b]), classes[rng.randi_range(0, 2)])
			elif pick <= 6:
				net.undo_last_op()
			elif pick == 7:
				var ids: Array = net.edges.keys()
				ids.sort()
				net.set_edge_open(ids[rng.randi_range(0, ids.size() - 1)], rng.randi_range(0, 1) == 1)
			else:
				var ids2: Array = net.edges.keys()
				ids2.sort()
				net.remove_edge(ids2[rng.randi_range(0, ids2.size() - 1)])
			_same(net, "tohum %d adım %d" % [seed_value, step])


func test_unsealed_network_hash_is_the_full_computation() -> void:
	var net := NetworkTestSupport.empty_network(_world)
	var a := net.add_node_raw(Vector2(600, 600))
	var b := net.add_node_raw(Vector2(700, 600))
	net.add_edge_raw(a, b, LOCAL, 10.0)
	_same(net, "mühürsüz 1")
	net.add_edge_raw(a, net.add_node_raw(Vector2(600, 700)), LOCAL, 10.0)
	_same(net, "mühürsüz 2")


func test_ismeral_base_graph_hash_matches_old_code_value() -> void:
	var net := NetworkTestSupport.default_network()
	assert_str(net.base_hash).is_equal(OLD_ISMERAL_BASE)
	assert_str(net.graph_hash()).is_equal(OLD_ISMERAL_BASE)


func _random_point(rng: RandomNumberGenerator) -> Vector2:
	return ORIGIN + Vector2(float(rng.randi_range(0, 3)) * DX, float(rng.randi_range(0, 3)) * DZ) \
			+ Vector2(float(rng.randi_range(-2, 2)) * 40.0, float(rng.randi_range(-2, 2)) * 40.0)
