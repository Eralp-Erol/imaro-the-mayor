extends GdUnitTestSuite
## T-049 A3 · Bağlantısız parçaları ana ağa bağlama: `NetworkGenerator._closest_pair` brute-force ile BİREBİR aynı
## sonucu vermeli (en yakın çift; eşitlikte küçük comp kimliği, sonra küçük ana kimliği). A3 öncesi sürüm bu işi
## ~25 s'de yapıyordu (A2 ağ üretimini 7 s -> 31 s'ye çıkaran kök neden); ızgaralı sürüm çıktıyı değiştirmemeli.
## Sentetik düz dünya, tohumlu rastgele noktalar; Q-015: koordinat verisi yok.

var _world: WorldData


func before() -> void:
	_world = NetworkTestSupport.flat_world(3000.0)


## `count` rastgele düğümü zincirle bağlar (tek bileşen); düğüm kimlikleri dizisini döndürür.
func _cluster(net: WorldNetwork, rng: RandomNumberGenerator, rect: Rect2, count: int) -> PackedInt32Array:
	var ids := PackedInt32Array()
	for _i in count:
		var p := rect.position + Vector2(rng.randf() * rect.size.x, rng.randf() * rect.size.y)
		ids.append(net.add_node_raw(p))
	for k in range(ids.size() - 1):
		net.add_edge_raw(ids[k], ids[k + 1], WorldRoadEdge.CLASS_LOCAL, 10.0)
	return ids


static func _brute_force(net: WorldNetwork, comp: PackedInt32Array, main_index: int) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d := INF
	for a in comp:
		for b in net.components(WorldNetwork.MODE_ROAD)[main_index]:
			var d := net.node_pos(a).distance_to(net.node_pos(b))
			if d < best_d or (d == best_d and (a < best.x or (a == best.x and b < best.y))):
				best_d = d
				best = Vector2i(a, b)
	return best


func _main_index(comps: Array[PackedInt32Array]) -> int:
	var mi := 0
	for k in comps.size():
		if comps[k].size() > comps[mi].size():
			mi = k
	return mi


func test_closest_pair_matches_brute_force_on_random_clusters() -> void:
	for seed_value in [11, 12, 13, 14, 15]:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		var net := NetworkTestSupport.empty_network(_world)
		_cluster(net, rng, Rect2(100, 100, 1200, 1200), 250)
		_cluster(net, rng, Rect2(1700, 400, 600, 500), 40)
		_cluster(net, rng, Rect2(500, 2200, 400, 300), 12)
		var comps := net.components(WorldNetwork.MODE_ROAD)
		assert_int(comps.size()).is_equal(3)
		var main_index := _main_index(comps)
		for k in comps.size():
			if k == main_index:
				continue
			var got := NetworkGenerator._closest_pair(net, comps[k], main_index)
			var want := _brute_force(net, comps[k], main_index)
			assert_that(got).is_equal(want)
			assert_bool(got.x >= 0 and got.y >= 0).is_true()


func test_closest_pair_ties_prefer_smaller_ids() -> void:
	# Ana: (0,0) ve (200,0); parça: tek düğüm (100,0): iki ana düğüme tam eşit uzaklık -> küçük kimlik.
	var net := NetworkTestSupport.empty_network(_world)
	var a := net.add_node_raw(Vector2(1000, 1000))
	var b := net.add_node_raw(Vector2(1200, 1000))
	var c := net.add_node_raw(Vector2(1000, 1200))
	net.add_edge_raw(a, b, WorldRoadEdge.CLASS_LOCAL, 10.0)
	net.add_edge_raw(a, c, WorldRoadEdge.CLASS_LOCAL, 10.0)
	var s1 := net.add_node_raw(Vector2(1100, 1000))
	var s2 := net.add_node_raw(Vector2(1100, 1050))
	net.add_edge_raw(s1, s2, WorldRoadEdge.CLASS_LOCAL, 10.0)
	var comps := net.components(WorldNetwork.MODE_ROAD)
	var main_index := _main_index(comps)
	var small: PackedInt32Array = comps[1 - main_index]
	assert_that(NetworkGenerator._closest_pair(net, small, main_index)).is_equal(Vector2i(s1, a))


func test_closest_pair_far_satellite_is_found() -> void:
	# Ana ağın ızgara hücresi sınırlarından çok uzak parça: halka büyür, yine en yakın çifti bulur.
	var net := NetworkTestSupport.empty_network(_world)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	_cluster(net, rng, Rect2(50, 50, 300, 300), 60)
	_cluster(net, rng, Rect2(2600, 2600, 300, 300), 8)
	var comps := net.components(WorldNetwork.MODE_ROAD)
	var main_index := _main_index(comps)
	var small: PackedInt32Array = comps[1 - main_index]
	var got := NetworkGenerator._closest_pair(net, small, main_index)
	assert_that(got).is_equal(_brute_force(net, small, main_index))
