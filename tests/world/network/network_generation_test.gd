# gdlint:disable=max-public-methods
extends GdUnitTestSuite
## T-011 ölçüt 3-4 · T0 iskelet ağ üreteci v0: topolojik değişmezler (WLD-01/03/05, CAN-03/04, TEK-01/03).
## Testler TOPOLOJİ sınar, kesin koordinat sınamaz. Her değişmezin OLUMSUZ karşılığı vardır: bilerek bozulmuş veri/ağ
## kırmızı verir. Tam ağ (varsayılan veri) bir kez üretilir; olumsuz/kayıt testleri küçültülmüş (`light`) ağ kullanır.

const SOURCE_FILES: Array[String] = [
	"res://src/world/network/network_generator.gd", "res://src/world/network/network_router.gd",
	"res://src/world/network/network_lattice.gd", "res://src/world/network/network_invariants.gd",
]
const FORBIDDEN_NAMES: Array[String] = ["Ilgın", "Ilgin", "Konak", "Karşıyaka", "Bornova", "Alsancak", "Buca",
		"Bayraklı", "Çiğli", "Balçova", "Narlıdere", "Güzelbahçe", "Kemeraltı", "Gediz", "Kordon"]
const COORDINATE_KEYS: Array[String] = ["pos_km", "center_km", "anchor_km", "coast_path_km", "outline_km"]

var _net: WorldNetwork
var _light: WorldNetwork


func before() -> void:
	_net = NetworkTestSupport.default_network()
	_light = NetworkTestSupport.light_network()


func _contains(violations: PackedStringArray, needle: String) -> bool:
	for v in violations:
		if v.contains(needle):
			return true
	return false


func _island_point(net: WorldNetwork) -> Vector2:
	return net.world.islands[0].centroid


# --- Sağlıklı veri: tüm değişmezler boş ---

func test_generated_ismeral_t0_network_satisfies_every_invariant() -> void:
	var violations := NetworkInvariants.check_all(_net)
	assert_array(violations).override_failure_message("ihlaller: %s" % [violations.slice(0, 10)]).is_empty()
	assert_array(NetworkInvariants.check_all(_light)).is_empty()


func test_network_is_sealed_and_has_meaningful_size() -> void:
	var c := _net.counts()
	assert_bool(_net.sealed).is_true()
	assert_int(c["nodes"]).is_greater(1000)
	assert_int(c["edges"]).is_greater(2000)
	assert_int(c["parcels"]).is_greater(5000)
	assert_float(float(c["parcelized_blocks"]) / float(c["blocks"])).is_greater(0.9)


func test_generation_does_not_modify_the_world_data_and_holds_no_copy() -> void:
	# WLD-01/TEK-03: ağ WorldData'yı okur, değiştirmez; kendi kıyı/yükseklik verisi yok.
	var world := WorldTestSupport.default_world()
	var before_hash := world.state_hash()
	var net := NetworkTestSupport.fresh_light()
	assert_str(world.state_hash()).is_equal(before_hash)
	assert_object(net.world).is_same(world)


# --- Her bölge ana ağa bağlı (olumsuz: bağlantısız bırakılırsa kırmızı) ---

func test_every_region_hub_exists_and_shares_one_road_component() -> void:
	for code in WorldControlData.REGION_CODES:
		assert_bool(_net.hubs.has(StringName(code))).override_failure_message(code).is_true()
	var main := int(_net.hubs[&"D1"])
	for code in WorldControlData.REGION_CODES:
		assert_bool(_net.same_component(main, int(_net.hubs[StringName(code)]))).override_failure_message(code).is_true()


func test_region_connectivity_negative_isolated_d6_is_detected() -> void:
	var control := NetworkTestSupport.light_control()
	NetworkTestSupport.drop_links_touching(control, "D6")
	control["connectors"] = {"enabled": false}
	var broken := NetworkTestSupport.fresh_light(control)
	var violations := NetworkInvariants.check_regions_connected(broken)
	assert_bool(_contains(violations, "D6")).override_failure_message(str(violations)).is_true()
	# D6 yine de kendi içinde bağlı; sorun yalnız ana ağa bağlanmamak.
	assert_bool(broken.hubs.has(&"D6")).is_true()


func test_region_connectivity_negative_removing_the_only_links_in_play() -> void:
	# Oyuncu komutuyla (delta) bir bölgenin tüm çıkışı kapatılırsa bağlantı değişmezi kırmızı verir.
	var net := NetworkTestSupport.fresh_light()
	var d2 := int(net.hubs[&"D2"])
	var fp := net.rules.footprint_by_id(&"D2")
	for eid: int in net.edges.keys():
		if not net.edges.has(eid):
			continue
		var e: WorldRoadEdge = net.edges[eid]
		if e.mode() != &"road":
			continue
		# D2 ayak izinin sınırını geçen kenarlar: bir ucu içeride, bir ucu dışarıda.
		var a_in := fp.contains(net.node_pos(e.a), 40.0)
		var b_in := fp.contains(net.node_pos(e.b), 40.0)
		if a_in != b_in:
			net.set_edge_open(eid, false)
	assert_bool(net.same_component(int(net.hubs[&"D1"]), d2)).is_false()
	assert_bool(_contains(NetworkInvariants.check_regions_connected(net), "D2")).is_true()


# --- Yollar kara üstünde, feribot suyun üstünde (WLD-03, WLD-05) ---

func test_roads_are_on_land_and_ferries_cross_water() -> void:
	assert_array(NetworkInvariants.check_roads_on_land(_net)).is_empty()
	assert_array(NetworkInvariants.check_ferries_over_water(_net)).is_empty()
	var ferries := 0
	for e: WorldRoadEdge in _net.edges.values():
		if e.road_class == WorldRoadEdge.CLASS_FERRY:
			ferries += 1
	assert_int(ferries).is_greater(0)


func test_roads_on_land_negative_a_node_dragged_into_the_bay_is_detected() -> void:
	var net := NetworkTestSupport.fresh_light()
	var water := Vector2.ZERO
	for p in net.world.regions:
		pass
	# Körfez suyu: D1 ve D6 merkezleri arasındaki orta nokta (veriden türetilir, sabit koordinat yok).
	water = (net.node_pos(int(net.hubs[&"D1"])) + net.node_pos(int(net.hubs[&"D6"]))) * 0.5
	assert_bool(net.world.is_water(water.x, water.y)).is_true()
	var victim := int(net.hubs[&"D3"])
	(net.nodes[victim] as WorldRoadNode).pos = water
	var violations := NetworkInvariants.check_roads_on_land(net)
	assert_bool(_contains(violations, "suda")).override_failure_message(str(violations)).is_true()


func test_ferry_negative_a_ferry_over_land_is_detected() -> void:
	var net := NetworkTestSupport.fresh_light()
	var a := int(net.hubs[&"D4"])
	var b := int(net.hubs[&"D2"])
	net.add_edge_raw(a, b, WorldRoadEdge.CLASS_FERRY, 0.0)
	var violations := NetworkInvariants.check_ferries_over_water(net)
	assert_bool(_contains(violations, "suyun üstünden geçmiyor")).override_failure_message(str(violations)).is_true()


# --- WLD-05: D1 <-> D6 ---

func test_d1_d6_are_land_connected_by_a_long_detour_and_ferry_connected_across_water() -> void:
	assert_array(NetworkInvariants.check_d1_d6_relation(_net)).is_empty()
	var d1 := int(_net.hubs[&"D1"])
	var d6 := int(_net.hubs[&"D6"])
	var bird := _net.node_pos(d1).distance_to(_net.node_pos(d6))
	var road := _net.shortest_path(d1, d6, WorldNetwork.MODE_ROAD)
	assert_bool(road["found"]).is_true()
	assert_float(road["length"]).is_greater(NetworkInvariants.MIN_LAND_DETOUR_RATIO * bird)
	# Aralarında su kalır: kuş uçuşu doğrunun büyük kısmı su (doldurma/köprü yok).
	var wet := 0
	for k in 41:
		var p := _net.node_pos(d1).lerp(_net.node_pos(d6), float(k) / 40.0)
		if _net.world.is_water(p.x, p.y):
			wet += 1
	assert_int(wet).is_greater(10)


func test_d1_d6_negative_no_ferry_is_detected() -> void:
	var control := NetworkTestSupport.light_control()
	control["ferries"] = []
	var net := NetworkTestSupport.fresh_light(control)
	var violations := NetworkInvariants.check_d1_d6_relation(net)
	assert_bool(_contains(violations, "feribot hattı yok")).override_failure_message(str(violations)).is_true()


func test_d1_d6_negative_filling_the_bay_breaks_the_detour_rule() -> void:
	# Körfezi yok eden düz kıyı (WLD-05'in tersi): D1/D6 aynı kara kütlesinde kısa yolla bağlanır / ilişki bozulur.
	var control := WorldTestSupport.control()
	WorldTestSupport.straighten_coast(control)
	var world := WorldTestSupport.medium(control)
	var net := NetworkGenerator.generate(world, NetworkTestSupport.light_control(), WorldTestSupport.DEFAULT_SEED)
	var violations := NetworkInvariants.check_d1_d6_relation(net)
	assert_array(violations).override_failure_message("düz kıyıda ilişki sağlanmamalı").is_not_empty()


# --- WLD-03: liman sahası ana karada, D4'ün batısında, ray + yola bağlı; adada altyapı yok ---

func test_t0_port_is_on_the_mainland_west_of_d4_and_connected_by_road_and_rail() -> void:
	assert_array(NetworkInvariants.check_port_connected(_net)).is_empty()
	assert_array(NetworkInvariants.check_port_industry_parcels(_net)).is_empty()
	var port := int(_net.hubs[&"port"])
	assert_int(_net.world.landmass_at(_net.node_pos(port).x, _net.node_pos(port).y)).is_equal(
			WorldData.LANDMASS_MAINLAND)
	var industrial := 0
	for p: WorldParcel in _net.parcels.values():
		if p.fabric == &"industrial":
			industrial += 1
	assert_int(industrial).is_greater(100)


func test_port_negative_without_rail_is_detected() -> void:
	var control := NetworkTestSupport.light_control()
	control["rail"] = []
	var net := NetworkTestSupport.fresh_light(control)
	var violations := NetworkInvariants.check_port_connected(net)
	assert_bool(_contains(violations, "rayla bağlı değil")).override_failure_message(str(violations)).is_true()


func test_port_negative_isolated_by_closing_its_roads_is_detected() -> void:
	var net := NetworkTestSupport.fresh_light()
	var port := int(net.hubs[&"port"])
	for eid in net.adjacency[port]:
		var e: WorldRoadEdge = net.edges[eid]
		if e.mode() == &"road":
			net.set_edge_open(eid, false)
	# Yalnız liman düğümünün kendi kenarları kapatılırsa kara bağlantısı kopar.
	var violations := NetworkInvariants.check_port_connected(net)
	assert_bool(_contains(violations, "kara yoluyla")).override_failure_message(str(violations)).is_true()


func test_port_negative_moved_onto_an_island_or_east_of_d4_is_detected() -> void:
	var net := NetworkTestSupport.fresh_light()
	var port := int(net.hubs[&"port"])
	var original := net.node_pos(port)
	(net.nodes[port] as WorldRoadNode).pos = _island_point(net)
	assert_bool(_contains(NetworkInvariants.check_port_connected(net), "ana karada değil")).is_true()
	assert_bool(_contains(NetworkInvariants.check_no_island_infrastructure(net), "adada")).is_true()
	var d4 := net.world.region_by_code(&"D4")
	(net.nodes[port] as WorldRoadNode).pos = Vector2(d4.centroid.x + 1500.0, original.y)
	assert_bool(_contains(NetworkInvariants.check_port_connected(net), "D4'ün batısında değil")).is_true()
	(net.nodes[port] as WorldRoadNode).pos = original
	assert_array(NetworkInvariants.check_port_connected(net)).is_empty()


func test_no_road_node_or_parcel_on_any_island_at_t0() -> void:
	assert_array(NetworkInvariants.check_no_island_infrastructure(_net)).is_empty()
	for island in _net.world.islands:
		for p: WorldParcel in _net.parcels.values():
			assert_bool(p.centroid.distance_to(island.centroid) < 400.0 and \
					_net.world.landmass_at(p.centroid.x, p.centroid.y) == island.landmass_id).is_false()


func test_island_negative_infrastructure_on_an_island_is_detected() -> void:
	var net := NetworkTestSupport.fresh_light()
	var p := _island_point(net)
	var a := net.add_node_raw(p)
	var b := net.add_node_raw(p + Vector2(60, 0))
	net.add_edge_raw(a, b, WorldRoadEdge.CLASS_LOCAL, 10.0)
	var violations := NetworkInvariants.check_no_island_infrastructure(net)
	assert_bool(_contains(violations, "adada")).override_failure_message(str(violations)).is_true()


# --- Parseller: kara, çakışma, cephe, alan eşiği, bölge kodu (olumsuz varyantlı) ---

func test_every_parcel_is_valid_on_the_full_network() -> void:
	assert_array(NetworkInvariants.check_parcels(_net)).is_empty()
	var regions := {}
	for p: WorldParcel in _net.parcels.values():
		regions[p.region_code] = int(regions.get(p.region_code, 0)) + 1
		assert_int(p.owner_id).is_equal(0)  # CAN-03: sahiplik sim'in
	for code in WorldControlData.REGION_CODES:
		assert_int(int(regions.get(StringName(code), 0))).override_failure_message(code).is_greater(500)


func test_parcel_negatives_each_broken_parcel_is_detected() -> void:
	var net := NetworkTestSupport.fresh_light()
	var block: WorldBlock = null
	for b: WorldBlock in net.blocks.values():
		if b.kind == WorldBlock.KIND_PARCELIZED and b.parcel_ids.size() >= 4 and b.fabric == &"core":
			block = b
			break
	assert_object(block).is_not_null()
	var first: WorldParcel = net.parcels[block.parcel_ids[0]]
	var second: WorldParcel = net.parcels[block.parcel_ids[1]]
	assert_array(NetworkInvariants.check_parcels(net)).is_empty()
	# 1) Çakışma: komşu parsel aynı poligona taşınır.
	var saved_outline := second.outline
	second.outline = first.outline
	assert_bool(_contains(NetworkInvariants.check_parcels(net), "çakışıyor")).is_true()
	second.outline = saved_outline
	# 2) Cephe başka (uzak) bir yola bakıyor.
	var saved_front := first.frontage_edge
	var far_edge := -1
	for eid: int in net.edges:
		if net.node_pos((net.edges[eid] as WorldRoadEdge).a).distance_to(first.centroid) > 3000.0 and \
				WorldRoadEdge.is_road_class((net.edges[eid] as WorldRoadEdge).road_class):
			far_edge = eid
			break
	first.frontage_edge = far_edge
	assert_bool(_contains(NetworkInvariants.check_parcels(net), "cephe yola bakmıyor")).is_true()
	# 3) Cephe bir ray kenarı (yol değil).
	for eid: int in net.edges:
		if (net.edges[eid] as WorldRoadEdge).road_class == WorldRoadEdge.CLASS_RAIL:
			first.frontage_edge = eid
			break
	assert_bool(_contains(NetworkInvariants.check_parcels(net), "cephe kenarı yol değil")).is_true()
	first.frontage_edge = saved_front
	# 4) Alan eşiği: parsel 3x3 m'ye küçülür.
	var saved_area := first.area
	first.area = 9.0
	assert_bool(_contains(NetworkInvariants.check_parcels(net), "alan eşik dışı")).is_true()
	first.area = saved_area
	# 5) Köşe suda.
	var water := (net.node_pos(int(net.hubs[&"D1"])) + net.node_pos(int(net.hubs[&"D6"]))) * 0.5
	var saved_outline_first := first.outline
	var wet := PackedVector2Array(first.outline)
	wet[0] = water
	first.outline = wet
	assert_bool(_contains(NetworkInvariants.check_parcels(net), "köşe suda")).is_true()
	first.outline = saved_outline_first
	# 6) Geçersiz bölge kodu.
	first.region_code = &"D9"
	assert_bool(_contains(NetworkInvariants.check_parcels(net), "bölge kodu")).is_true()
	first.region_code = &"D1"
	assert_array(NetworkInvariants.check_parcels(net)).is_empty()


func test_graph_integrity_negative_dangling_references_are_detected() -> void:
	var net := NetworkTestSupport.fresh_light()
	assert_array(NetworkInvariants.check_graph_integrity(net)).is_empty()
	var pid: int = net.parcels.keys()[0]
	(net.parcels[pid] as WorldParcel).block_id = 987654
	assert_bool(_contains(NetworkInvariants.check_graph_integrity(net), "tutarsız")).is_true()


# --- Tohum, hash, kayıt (TEK-01/02) ---

func test_same_seed_same_hash_and_different_seed_changes_detail_not_topology() -> void:
	var world := WorldTestSupport.default_world()
	var again := NetworkGenerator.generate(world, NetworkTestSupport.light_control(), WorldTestSupport.DEFAULT_SEED)
	assert_str(again.state_hash()).is_equal(_light.state_hash())
	var other := NetworkGenerator.generate(world, NetworkTestSupport.light_control(), WorldTestSupport.DEFAULT_SEED + 1)
	assert_str(other.state_hash()).is_not_equal(_light.state_hash())
	assert_str(other.detail_hash()).is_not_equal(_light.detail_hash())
	assert_str(other.topology_hash()).is_equal(_light.topology_hash())
	assert_array(NetworkInvariants.check_all(other)).is_empty()


func test_player_delta_on_the_generated_network_roundtrips_through_json() -> void:
	var net := NetworkTestSupport.fresh_light()
	var hub := net.node_pos(int(net.hubs[&"D1"]))
	var parcels_before := net.parcels.size()
	var report := net.add_road(PackedVector2Array([hub + Vector2(-300, 90), hub + Vector2(300, 90)]),
			WorldRoadEdge.CLASS_COLLECTOR)
	assert_bool(report["ok"]).override_failure_message(str(report)).is_true()
	var victim := net.edges_near(hub.x + 600.0, hub.y, 150.0)
	if not victim.is_empty():
		assert_bool(net.remove_edge(victim[0].id)["ok"]).is_true()
	assert_array(NetworkInvariants.check_graph_integrity(net)).is_empty()
	assert_array(NetworkInvariants.check_parcels(net)).is_empty()
	assert_int(net.parcels.size()).is_not_equal(parcels_before)
	var parsed: Variant = JSON.parse_string(JSON.stringify(net.delta.to_dict()))
	var fresh := NetworkTestSupport.fresh_light()
	assert_str(fresh.base_hash).is_equal(net.base_hash)
	var applied := fresh.apply_delta(NetworkDelta.from_dict(parsed))
	assert_bool(applied["ok"]).override_failure_message(str(applied)).is_true()
	assert_str(fresh.state_hash()).is_equal(net.state_hash())


# --- Veri odaklı, koordinat gömme yok, kanon adları (CAN-01, WLD-02) ---

func test_network_data_file_has_the_canon_header_no_coordinates_and_no_invented_names() -> void:
	var path := "%s/%s.json" % [NetworkTestSupport.NETWORK_DATA_DIR, NetworkTestSupport.NETWORK_FILE]
	var text := FileAccess.get_file_as_string(path)
	assert_str(text).contains("02_ismeral_t0_vs_mature_SELECTED.jpg")
	assert_str(text).contains("(F04 Referans B) ONAYLANMIŞ YÖN yorumu; koordinatlar kilitli değil (F02, F04)")
	for key in COORDINATE_KEYS:
		assert_bool(text.contains("\"%s\"" % key)).override_failure_message("koordinat anahtarı: %s" % key).is_false()
	for forbidden in FORBIDDEN_NAMES:
		assert_bool(text.contains(forbidden)).override_failure_message(forbidden).is_false()


func test_network_follows_edited_region_anchors_instead_of_hard_coded_positions() -> void:
	# Meşru düzenleme: D2 çapası 700 m doğuya kayar -> D2 merkezi onunla gider, değişmezler yeşil kalır (koordinat
	# gömme yok).
	var control := WorldTestSupport.control()
	var entry := WorldTestSupport.region_entry(control, "D2")
	var original := Vector2(float(entry["anchor_km"][0]), float(entry["anchor_km"][1]))
	entry["anchor_km"] = [original.x + 0.7, original.y]
	var world := WorldGenerator.generate(control, WorldTestSupport.DEFAULT_SEED)
	var net := NetworkGenerator.generate(world, NetworkTestSupport.light_control(), WorldTestSupport.DEFAULT_SEED)
	var hub := net.node_pos(int(net.hubs[&"D2"]))
	var moved_anchor := world.region_by_code(&"D2").anchor
	assert_float(hub.distance_to(moved_anchor)).is_less(1600.0)
	assert_array(NetworkInvariants.check_regions_connected(net)).is_empty()
	assert_array(NetworkInvariants.check_no_island_infrastructure(net)).is_empty()


# --- Saflık ---

func test_generator_sources_have_no_forbidden_apis() -> void:
	for path in SOURCE_FILES:
		assert_str(FileAccess.get_file_as_string(path)).is_not_empty()
		assert_array(WorldTestSupport.forbidden_api_hits(path)).override_failure_message(path).is_empty()
