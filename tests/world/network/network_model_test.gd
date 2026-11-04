# gdlint:disable=max-public-methods
extends GdUnitTestSuite
## T-011 ölçüt 1-2 · Ağ veri modeli: yol grafı, bloklar, parseller, base+delta ve sorgu API'si (CAN-03/04/05,
## TEK-01/03).
## Sentetik düz dünya + el yapımı ızgara: kesin sayılarla sınanır, her değişmezin olumsuz karşılığı vardır.

const SOURCE_FILES: Array[String] = [
	"res://src/world/network/world_network.gd", "res://src/world/network/network_geometry.gd",
	"res://src/world/network/network_blocks.gd", "res://src/world/network/network_parcelizer.gd",
	"res://src/world/network/network_planarizer.gd", "res://src/world/network/network_pathfinder.gd",
	"res://src/world/network/network_delta.gd", "res://src/world/network/network_rules.gd",
	"res://src/world/network/network_spatial_hash.gd", "res://src/world/network/world_road_node.gd",
	"res://src/world/network/world_road_edge.gd", "res://src/world/network/world_block.gd",
	"res://src/world/network/world_parcel.gd", "res://src/world/network/network_footprint.gd",
]
const DX := 160.0
const DZ := 100.0
const ORIGIN := Vector2(500.0, 500.0)

var _world: WorldData


func before() -> void:
	_world = NetworkTestSupport.flat_world(3000.0)


func _grid(cols: int = 3, rows: int = 3) -> WorldNetwork:
	return NetworkTestSupport.grid_network(_world, cols, rows, DX, DZ, ORIGIN)


func _parcel_ids_of_blocks(net: WorldNetwork) -> Array:
	var ids: Array = net.parcels.keys()
	ids.sort()
	return ids


# --- Topoloji ve bloklar ---

func test_lattice_has_the_expected_nodes_edges_and_blocks() -> void:
	var net := _grid(3, 3)
	var c := net.counts()
	assert_int(c["nodes"]).is_equal(16)
	assert_int(c["edges"]).is_equal(24)
	assert_int(c["blocks"]).is_equal(9)
	assert_int(c["parcelized_blocks"]).is_equal(9)
	assert_bool(net.sealed).is_true()


func test_block_buildable_area_is_the_face_minus_half_road_widths() -> void:
	var net := _grid(3, 3)
	for b: WorldBlock in net.blocks.values():
		assert_float(NetworkGeometry.signed_area(b.outline)).is_equal_approx(DX * DZ, 1.0)
		assert_float(b.area).is_equal_approx((DX - 10.0) * (DZ - 10.0), 1.0)


func test_parcels_tile_blocks_without_overlap_and_every_parcel_faces_a_road() -> void:
	var net := _grid(2, 2)
	assert_int(net.parcels.size()).is_greater(20)
	for pid: int in net.parcels:
		var p: WorldParcel = net.parcels[pid]
		var e := net.edge(p.frontage_edge)
		assert_object(e).is_not_null()
		assert_bool(WorldRoadEdge.is_road_class(e.road_class)).is_true()
		# Cephe orta noktası yolun yarım genişliği içinde (blok yol kenarından yarım genişlik içeride).
		var d := NetworkGeometry.distance_point_segment(p.front_mid, net.node_pos(e.a), net.node_pos(e.b))
		assert_float(d).is_equal_approx(e.width * 0.5, 0.6)
		assert_float(p.area).is_greater(100.0)
	for b: WorldBlock in net.blocks.values():
		var total := 0.0
		for pid in b.parcel_ids:
			total += (net.parcels[pid] as WorldParcel).area
		# Parseller bloğu doldurur: toplam alan blok alanını aşmaz, çoğunu kapsar.
		assert_float(total).is_less(b.area + 0.5)
		assert_float(total).is_greater(b.area * 0.9)
		for i in b.parcel_ids.size():
			for j in range(i + 1, b.parcel_ids.size()):
				var pa: WorldParcel = net.parcels[b.parcel_ids[i]]
				var pb: WorldParcel = net.parcels[b.parcel_ids[j]]
				assert_bool(NetworkGeometry.convex_overlap(pa.outline, pb.outline, 0.05)).is_false()


func test_owner_slot_is_empty_and_the_network_never_sets_it() -> void:
	# CAN-03: ağ katmanı mülkiyet/bina üretmez; owner_id yuvası boş.
	var net := _grid(2, 2)
	for p: WorldParcel in net.parcels.values():
		assert_int(p.owner_id).is_equal(0)


# --- Sorgu API'si ---

func test_parcel_at_block_at_and_region_queries() -> void:
	var net := _grid(2, 2)
	var inside := ORIGIN + Vector2(DX * 0.5, DZ * 0.5)
	var parcel := net.parcel_at(inside.x, inside.y)
	assert_object(parcel).is_not_null()
	assert_bool(NetworkGeometry.point_in_polygon(inside, parcel.outline)).is_true()
	assert_str(String(net.region_of_parcel(parcel.id))).is_equal("D1")
	var block := net.block_at(inside.x, inside.y)
	assert_object(block).is_not_null()
	assert_bool(block.parcel_ids.has(parcel.id)).is_true()
	# Olumsuz: yolun ortası ve ağın dışı parsel değildir.
	assert_object(net.parcel_at(ORIGIN.x + DX, ORIGIN.y + DZ * 0.5)).is_null()
	assert_int(net.parcel_id_at(10.0, 10.0)).is_equal(-1)
	assert_object(net.block_at(10.0, 10.0)).is_null()


func test_edges_near_neighbors_and_parcels_in_rect() -> void:
	var net := _grid(2, 2)
	var near := net.edges_near(ORIGIN.x + DX * 0.5, ORIGIN.y + 2.0, 6.0)
	assert_int(near.size()).is_equal(1)
	# Kavşak düğümü (orta): 4 komşu; köşe düğümü: 2 komşu.
	var center := net.nearest_node(ORIGIN + Vector2(DX, DZ))
	assert_int(net.neighbors(center).size()).is_equal(4)
	var corner := net.nearest_node(ORIGIN)
	assert_int(net.neighbors(corner).size()).is_equal(2)
	var rect := Rect2(ORIGIN + Vector2(10, 10), Vector2(DX - 20.0, DZ - 20.0))
	var ids := net.parcels_in_rect(rect)
	assert_int(ids.size()).is_greater(0)
	for pid in ids:
		assert_bool(NetworkGeometry.polygon_intersects_rect((net.parcels[pid] as WorldParcel).outline, rect)).is_true()
	# Olumsuz: ağdan uzak dikdörtgende parsel yok.
	assert_int(net.parcels_in_rect(Rect2(2500, 2500, 100, 100)).size()).is_equal(0)


func test_queries_are_sorted_and_deterministic() -> void:
	var net := _grid(2, 2)
	var ids := net.parcels_in_rect(Rect2(0, 0, 3000, 3000))
	var sorted_copy := PackedInt32Array(ids)
	sorted_copy.sort()
	assert_array(ids).is_equal(sorted_copy)


# --- Planarizasyon ---

func test_crossing_polyline_creates_a_shared_junction_node() -> void:
	var net := NetworkTestSupport.empty_network(_world)
	net.author_polyline(PackedVector2Array([Vector2(100, 200), Vector2(300, 200)]), WorldRoadEdge.CLASS_LOCAL)
	net.author_polyline(PackedVector2Array([Vector2(200, 100), Vector2(200, 300)]), WorldRoadEdge.CLASS_LOCAL)
	assert_int(net.nodes.size()).is_equal(5)
	assert_int(net.edges.size()).is_equal(4)
	var hub := net.nearest_node(Vector2(200, 200))
	assert_int(net.neighbors(hub).size()).is_equal(4)


func test_t_junction_and_collinear_overlap_do_not_duplicate_edges() -> void:
	var net := NetworkTestSupport.empty_network(_world)
	net.author_polyline(PackedVector2Array([Vector2(100, 100), Vector2(400, 100)]), WorldRoadEdge.CLASS_LOCAL)
	# Ucu mevcut yolun ortasına değen yol: kenar bölünür (T kavşağı).
	net.author_polyline(PackedVector2Array([Vector2(250, 100), Vector2(250, 300)]), WorldRoadEdge.CLASS_LOCAL)
	assert_int(net.edges.size()).is_equal(3)
	# Aynı yolu üst üste çizmek yeni kenar eklemez.
	net.author_polyline(PackedVector2Array([Vector2(100, 100), Vector2(400, 100)]), WorldRoadEdge.CLASS_LOCAL)
	assert_int(net.edges.size()).is_equal(3)


func test_overlapping_road_of_a_higher_class_upgrades_instead_of_duplicating() -> void:
	var net := NetworkTestSupport.empty_network(_world)
	net.author_polyline(PackedVector2Array([Vector2(100, 100), Vector2(400, 100)]), WorldRoadEdge.CLASS_LOCAL)
	net.author_polyline(PackedVector2Array([Vector2(100, 100), Vector2(400, 100)]), WorldRoadEdge.CLASS_ARTERIAL)
	assert_int(net.edges.size()).is_equal(1)
	assert_str(String((net.edges.values()[0] as WorldRoadEdge).road_class)).is_equal("arterial")


# --- En kısa yol: kipler ayrı ---

func test_shortest_path_modes_are_separate() -> void:
	var net := NetworkTestSupport.empty_network(_world)
	# Yol: A - B - C (kara); ray: A - C doğrudan (kısa yol); feribot: C - D.
	net.author_polyline(PackedVector2Array([Vector2(100, 100), Vector2(300, 400)]), WorldRoadEdge.CLASS_LOCAL)
	net.author_polyline(PackedVector2Array([Vector2(300, 400), Vector2(600, 100)]), WorldRoadEdge.CLASS_LOCAL)
	net.author_polyline(PackedVector2Array([Vector2(100, 100), Vector2(600, 100)]), WorldRoadEdge.CLASS_RAIL)
	var a := net.nearest_node(Vector2(100, 100))
	var c := net.nearest_node(Vector2(600, 100))
	var road := net.shortest_path(a, c, WorldNetwork.MODE_ROAD)
	var rail := net.shortest_path(a, c, WorldNetwork.MODE_RAIL)
	assert_bool(road["found"]).is_true()
	assert_bool(rail["found"]).is_true()
	assert_float(rail["length"]).is_equal_approx(500.0, 0.1)
	assert_float(road["length"]).is_greater(rail["length"])
	# Ray kenarı kara yolu olarak kullanılmaz; kara kenarı feribot/ray olarak da.
	for eid in road["edges"]:
		assert_str(String(net.edge(eid).road_class)).is_equal("local")
	assert_bool(net.shortest_path(a, c, WorldNetwork.MODE_FERRY)["found"]).is_false()


func test_closed_edge_is_not_routable_and_reopening_restores_the_path() -> void:
	var net := _grid(2, 2)
	var a := net.nearest_node(ORIGIN)
	var b := net.nearest_node(ORIGIN + Vector2(DX * 2, 0))
	var before_len: float = net.shortest_path(a, b)["length"]
	var on_path: PackedInt32Array = net.shortest_path(a, b)["edges"]
	assert_bool(net.set_edge_open(on_path[0], false)["ok"]).is_true()
	var detour := net.shortest_path(a, b)
	assert_bool(detour["found"]).is_true()
	assert_float(detour["length"]).is_greater(before_len)
	assert_bool(net.set_edge_open(on_path[0], true)["ok"]).is_true()
	assert_float(net.shortest_path(a, b)["length"]).is_equal_approx(before_len, 0.01)


# --- Oyuncu yol ekleme/silme (CAN-04) ---

func test_player_road_splits_a_block_and_untouched_parcels_keep_ids_and_owners() -> void:
	var net := _grid(3, 3)
	var far := ORIGIN + Vector2(DX * 2.5, DZ * 2.5)
	var far_parcel := net.parcel_at(far.x, far.y)
	var far_id := far_parcel.id
	net.parcels[far_id].owner_id = 42  # sim'in yazdığı mülkiyet
	var blocks_before: int = net.counts()["blocks"]
	var target := net.block_at(ORIGIN.x + DX * 0.5, ORIGIN.y + DZ * 0.5)
	var old_parcels := PackedInt32Array(target.parcel_ids)
	# Hedef bloğu ikiye bölen yol (üst ve alt kenarlar arasında dikey).
	var report := net.add_road(PackedVector2Array([ORIGIN + Vector2(DX * 0.5, 0), ORIGIN + Vector2(DX * 0.5, DZ)]),
			WorldRoadEdge.CLASS_LOCAL)
	assert_bool(report["ok"]).override_failure_message(str(report)).is_true()
	assert_int(net.counts()["blocks"]).is_equal(blocks_before + 1)
	assert_int((report["removed_blocks"] as Array).size()).is_equal(1)
	assert_int((report["added_blocks"] as Array).size()).is_equal(2)
	# Etkilenen blokun parselleri gitti, yenileri eklendi; hepsi tutarlı.
	for pid in old_parcels:
		assert_bool(net.parcels.has(pid)).is_false()
	assert_array(report["removed_parcels"]).contains_exactly_in_any_order(Array(old_parcels))
	# Dokunulmamış blok: aynı parsel, aynı sahiplik yuvası.
	assert_object(net.parcel(far_id)).is_not_null()
	assert_int(net.parcel(far_id).owner_id).is_equal(42)
	assert_array(NetworkInvariants.check_graph_integrity(net)).is_empty()
	assert_array(NetworkInvariants.check_parcels(net)).is_empty()
	# Yeni yolun komşu parselleri artık ona cepheli.
	assert_int(net.edge_parcels(int(report["added_edges"][0])).size()).is_greater(0)


func test_player_road_connects_a_previously_unreachable_node() -> void:
	var net := _grid(2, 2)
	var island := net.add_road(PackedVector2Array([Vector2(1800, 1800), Vector2(2000, 1800)]), WorldRoadEdge.CLASS_LOCAL)
	assert_bool(island["ok"]).is_true()
	var a := net.nearest_node(ORIGIN)
	var b := net.nearest_node(Vector2(2000, 1800))
	assert_bool(net.shortest_path(a, b)["found"]).is_false()
	assert_bool(net.same_component(a, b)).is_false()
	# Köprü yol: bağlantı kurulur, yol bulunur, ızgaranın parselleri etkilenmez.
	var parcels_before := net.parcels.size()
	var link := net.add_road(PackedVector2Array([ORIGIN + Vector2(DX * 2, DZ * 2), Vector2(1800, 1800)]),
			WorldRoadEdge.CLASS_COLLECTOR)
	assert_bool(link["ok"]).is_true()
	assert_bool(net.shortest_path(a, b)["found"]).is_true()
	assert_bool(net.same_component(a, b)).is_true()
	assert_int(net.parcels.size()).is_equal(parcels_before)


func test_removing_a_road_merges_blocks_and_changes_connectivity() -> void:
	var net := _grid(2, 1)
	assert_int(net.counts()["blocks"]).is_equal(2)
	# İki bloğun ortak dikey kenarı (x = ORIGIN.x + DX).
	var mid := net.edges_near(ORIGIN.x + DX, ORIGIN.y + DZ * 0.5, 4.0)
	assert_int(mid.size()).is_equal(1)
	var report := net.remove_edge(mid[0].id)
	assert_bool(report["ok"]).is_true()
	assert_int(net.counts()["blocks"]).is_equal(1)
	assert_int((report["removed_blocks"] as Array).size()).is_equal(2)
	assert_int((report["added_blocks"] as Array).size()).is_equal(1)
	assert_array(NetworkInvariants.check_graph_integrity(net)).is_empty()
	assert_array(NetworkInvariants.check_parcels(net)).is_empty()


func test_removing_the_only_link_disconnects_the_network() -> void:
	var net := NetworkTestSupport.empty_network(_world)
	net.author_polyline(PackedVector2Array([Vector2(100, 100), Vector2(300, 100), Vector2(500, 100),
			Vector2(700, 100)]), WorldRoadEdge.CLASS_LOCAL)
	net.seal_base()
	var a := net.nearest_node(Vector2(100, 100))
	var b := net.nearest_node(Vector2(700, 100))
	assert_bool(net.shortest_path(a, b)["found"]).is_true()
	assert_int(net.components(WorldNetwork.MODE_ROAD).size()).is_equal(1)
	var link := net.edges_near(400.0, 100.0, 3.0)[0]
	assert_bool(net.remove_edge(link.id)["ok"]).is_true()
	assert_bool(net.shortest_path(a, b)["found"]).is_false()
	assert_bool(net.same_component(a, b)).is_false()
	assert_int(net.components(WorldNetwork.MODE_ROAD).size()).is_equal(2)
	# Olumsuz: uçtaki tek kenar silinince yalnız kalan düğüm de kaldırılır (artık düğüm bırakılmaz).
	var tail := net.edges_near(200.0, 100.0, 3.0)[0]
	assert_bool(net.remove_edge(tail.id)["ok"]).is_true()
	assert_bool(net.nodes.has(a)).is_false()
	assert_array(NetworkInvariants.check_graph_integrity(net)).is_empty()


func test_add_then_remove_the_player_road_restores_the_base_state() -> void:
	var net := _grid(3, 3)
	var base_state := net.state_hash()
	var base_dict := net.state_dict()
	var add := net.add_road(PackedVector2Array([ORIGIN + Vector2(DX * 0.5, -60.0),
			ORIGIN + Vector2(DX * 0.5, DZ * 3 + 60.0)]),
			WorldRoadEdge.CLASS_LOCAL)
	assert_bool(add["ok"]).is_true()
	assert_str(net.state_hash()).is_not_equal(base_state)
	for eid in add["added_edges"]:
		if net.edges.has(eid):
			assert_bool(net.remove_edge(eid)["ok"]).is_true()
	assert_array(NetworkInvariants.check_graph_integrity(net)).is_empty()
	assert_int(net.edges.size()).is_equal(24)
	assert_int(net.nodes.size()).is_equal(16)
	# Graf (düğüm + kenar sütunları) tabanla BİT BİT aynı: bölünen kenarlar birleşti, kimlikler korundu.
	var after := net.state_dict()
	assert_str(after["nodes_sha"]).is_equal(base_dict["nodes_sha"])
	assert_str(after["edges_sha"]).is_equal(base_dict["edges_sha"])
	assert_int(net.counts()["blocks"]).is_equal(9)


func test_player_road_across_water_is_rejected_and_not_recorded() -> void:
	var wet := NetworkTestSupport.flat_world(3000.0, 100.0, Rect2(1200, 1200, 600, 600))
	var net := NetworkTestSupport.grid_network(wet, 2, 2, DX, DZ, ORIGIN)
	var edges_before := net.edges.size()
	var report := net.add_road(PackedVector2Array([Vector2(1000, 1500), Vector2(2000, 1500)]), WorldRoadEdge.CLASS_LOCAL)
	assert_bool(report["ok"]).is_false()
	assert_str(report["error"]).contains("su")
	assert_int(net.edges.size()).is_equal(edges_before)
	assert_int(net.delta.ops.size()).is_equal(0)


func test_invalid_player_commands_are_rejected_without_side_effects() -> void:
	var net := _grid(2, 2)
	var state := net.state_hash()
	assert_bool(net.remove_edge(99999)["ok"]).is_false()
	assert_bool(net.set_edge_open(99999, false)["ok"]).is_false()
	assert_bool(net.add_road(PackedVector2Array([Vector2(100, 100)]), WorldRoadEdge.CLASS_LOCAL)["ok"]).is_false()
	assert_bool(net.add_road(PackedVector2Array([Vector2(100, 100), Vector2(101, 100)]),
			WorldRoadEdge.CLASS_LOCAL)["ok"]).is_false()
	assert_bool(net.add_road(PackedVector2Array([Vector2(100, 100), Vector2(300, 100)]),
			WorldRoadEdge.CLASS_FERRY)["ok"]).is_false()
	assert_str(net.state_hash()).is_equal(state)
	assert_int(net.delta.ops.size()).is_equal(0)


# --- Base + delta kayıt/yükleme ---

func test_delta_roundtrip_through_json_reproduces_the_exact_state() -> void:
	var net := _grid(3, 3)
	assert_bool(net.add_road(PackedVector2Array([ORIGIN + Vector2(DX * 0.5, -40.0),
			ORIGIN + Vector2(DX * 0.5, DZ * 3.0 + 40.0)]),
			WorldRoadEdge.CLASS_COLLECTOR)["ok"]).is_true()
	var victim := net.edges_near(ORIGIN.x + DX * 2.0, ORIGIN.y + DZ * 1.5, 4.0)
	assert_bool(net.remove_edge(victim[0].id)["ok"]).is_true()
	var open_edge := net.edges_near(ORIGIN.x + DX * 1.5, ORIGIN.y, 4.0)
	assert_bool(net.set_edge_open(open_edge[0].id, false)["ok"]).is_true()
	assert_int(net.delta.ops.size()).is_equal(3)
	var text := JSON.stringify(net.delta.to_dict())
	var parsed: Variant = JSON.parse_string(text)
	assert_bool(parsed is Dictionary).is_true()
	# Yeni ağ: aynı tabandan (taban deterministik), JSON'dan okunan delta.
	var fresh := _grid(3, 3)
	assert_str(fresh.base_hash).is_equal(net.base_hash)
	var applied := fresh.apply_delta(NetworkDelta.from_dict(parsed))
	assert_bool(applied["ok"]).override_failure_message(str(applied)).is_true()
	assert_str(fresh.state_hash()).is_equal(net.state_hash())
	assert_str(fresh.topology_hash()).is_equal(net.topology_hash())


func test_delta_for_a_different_base_is_refused() -> void:
	var net := _grid(3, 3)
	var added := net.add_road(PackedVector2Array([Vector2(100, 2000), Vector2(400, 2000)]), WorldRoadEdge.CLASS_LOCAL)
	assert_bool(added["ok"]).is_true()
	var other := NetworkTestSupport.grid_network(_world, 2, 2, DX, DZ, ORIGIN)
	var result := other.apply_delta(net.delta)
	assert_bool(result["ok"]).is_false()
	assert_str(result["error"]).contains("taban")


func test_edges_carry_their_layer_base_or_player() -> void:
	var net := _grid(2, 2)
	for e: WorldRoadEdge in net.edges.values():
		assert_int(e.layer).is_equal(WorldRoadEdge.LAYER_BASE)
	var report := net.add_road(PackedVector2Array([Vector2(100, 2000), Vector2(400, 2000)]), WorldRoadEdge.CLASS_LOCAL)
	for eid in report["added_edges"]:
		assert_int(net.edge(eid).layer).is_equal(WorldRoadEdge.LAYER_DELTA)


# --- Tohum/hash ---

func test_same_inputs_same_hash_and_different_seed_changes_detail_not_topology() -> void:
	var a := NetworkTestSupport.grid_network(_world, 3, 3, DX, DZ, ORIGIN, 7)
	var b := NetworkTestSupport.grid_network(_world, 3, 3, DX, DZ, ORIGIN, 7)
	var c := NetworkTestSupport.grid_network(_world, 3, 3, DX, DZ, ORIGIN, 8)
	assert_str(a.state_hash()).is_equal(b.state_hash())
	assert_str(a.state_hash()).is_not_equal(c.state_hash())
	assert_str(a.detail_hash()).is_not_equal(c.detail_hash())
	assert_str(a.topology_hash()).is_equal(c.topology_hash())


func test_owner_slot_is_excluded_from_the_geometry_hash_but_included_in_the_full_hash() -> void:
	var net := _grid(2, 2)
	var geometry := net.state_hash(false)
	var full := net.state_hash(true)
	net.parcels[net.parcels.keys()[0]].owner_id = 9
	assert_str(net.state_hash(false)).is_equal(geometry)
	assert_str(net.state_hash(true)).is_not_equal(full)


# --- TEK-03: ağ su/yükseklik kopyası tutmaz ---

func test_network_holds_a_world_reference_not_raster_copies() -> void:
	var net := _grid(2, 2)
	assert_object(net.world).is_same(_world)
	for prop in net.get_property_list():
		if int(prop["usage"]) & PROPERTY_USAGE_SCRIPT_VARIABLE == 0:
			continue
		var value: Variant = net.get(prop["name"])
		assert_bool(value is PackedFloat32Array or value is PackedByteArray).override_failure_message(
				"raster kopyası olabilir: %s" % prop["name"]).is_false()
	assert_bool(net.state_dict().has("heights_sha256")).is_false()


# --- Saflık (TEK-01/02) ---

func test_network_sources_have_no_forbidden_apis() -> void:
	for path in SOURCE_FILES:
		assert_str(FileAccess.get_file_as_string(path)).is_not_empty()
		assert_array(WorldTestSupport.forbidden_api_hits(path)).override_failure_message(path).is_empty()
