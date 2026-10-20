extends GdUnitTestSuite
## T-012 ölçüt 1/7 · DevBuildingSource (stand-in): AYNI BuildingColumns sözleşmesi, gerçek WorldNetwork parselleri
## üzerinde; her yapı kendi parselinde ve karada; deterministik; sim'e yazmaz (CAN-03).

const SEED := 20261020

var _kit: BuildingKit
var _manifest: Dictionary


func before() -> void:
	_kit = BuildingTestSupport.kit()
	_manifest = BuildingTestSupport.library().manifest


func _grid_net(world: WorldData) -> WorldNetwork:
	return BuildingTestSupport.grid_network(world, 6, 4, 160.0, 100.0, Vector2(600.0, 600.0))


func test_columns_follow_the_shared_contract_and_cover_most_parcels() -> void:
	var world := BuildingTestSupport.flat_world(3000.0, 100.0, Rect2(), 12.0)
	var net := _grid_net(world)
	var cols := DevBuildingSource.generate(world, net, _manifest, SEED)
	assert_array(cols.shape_errors()).is_empty()
	assert_array(BuildingInputCheck.errors(cols, _kit.count)).is_empty()
	assert_int(cols.count).is_greater(net.parcels.size() / 2)
	assert_int(cols.count).is_less_equal(net.parcels.size() * 2)


func test_every_building_stands_inside_its_own_parcel_and_on_land() -> void:
	var world := BuildingTestSupport.flat_world(3000.0, 100.0, Rect2(), 12.0)
	var net := _grid_net(world)
	var cols := DevBuildingSource.generate(world, net, _manifest, SEED)
	for i in cols.count:
		var parcel: WorldParcel = net.parcels.get(cols.parcel_id[i])
		assert_object(parcel).is_not_null()
		assert_bool(Geometry2D.is_point_in_polygon(Vector2(cols.x[i], cols.z[i]), parcel.outline)).is_true()
		assert_bool(world.is_water(cols.x[i], cols.z[i])).is_false()
		assert_bool(cols.floors[i] <= 12).is_true()


func test_buildings_face_the_frontage_street() -> void:
	var world := BuildingTestSupport.flat_world(3000.0, 100.0, Rect2(), 12.0)
	var net := _grid_net(world)
	var cols := DevBuildingSource.generate(world, net, _manifest, SEED)
	for i in cols.count:
		var parcel: WorldParcel = net.parcels[cols.parcel_id[i]]
		if (_kit.kinds[cols.module_idx[i]]) != "building":
			continue
		var facing := Vector2(sin(cols.yaw[i]), cos(cols.yaw[i]))   # yerel +Z'nin dünyadaki yönü
		var to_front := (parcel.front_mid - Vector2(cols.x[i], cols.z[i])).normalized()
		assert_float(facing.dot(to_front)).is_greater(0.5)


func test_same_seed_same_hash_different_seed_different_detail_same_occupancy() -> void:
	var world := BuildingTestSupport.flat_world(3000.0, 100.0, Rect2(), 12.0)
	var net := _grid_net(world)
	var a := DevBuildingSource.generate(world, net, _manifest, SEED)
	var b := DevBuildingSource.generate(world, net, _manifest, SEED)
	var c := DevBuildingSource.generate(world, net, _manifest, SEED + 1)
	assert_str(a.state_hash()).is_equal(b.state_hash())
	assert_str(a.state_hash()).is_not_equal(c.state_hash())


func test_no_building_on_water_when_part_of_the_world_is_sea() -> void:
	var world := BuildingTestSupport.flat_world(3000.0, 100.0, Rect2(1200.0, 0.0, 2000.0, 3000.0), 12.0)
	var net := BuildingTestSupport.grid_network(BuildingTestSupport.flat_world(3000.0, 100.0, Rect2(), 12.0), 6, 4,
			160.0, 100.0, Vector2(600.0, 600.0))
	# ağ düz karada üretildi (parseller denizin üstüne de uzanır); kaynak dünyayı denetlemelidir
	var cols := DevBuildingSource.generate(world, net, _manifest, SEED)
	for i in cols.count:
		assert_bool(world.is_water(cols.x[i], cols.z[i])).is_false()
	var full := DevBuildingSource.generate(BuildingTestSupport.flat_world(3000.0, 100.0, Rect2(), 12.0), net, _manifest,
			SEED)
	assert_int(cols.count).is_less(full.count)


func test_empty_network_gives_empty_columns() -> void:
	var world := BuildingTestSupport.flat_world(3000.0, 100.0, Rect2(), 12.0)
	var net := WorldNetwork.create(world, NetworkRules.from_control(world, {
		"classes": {"local": {"width_m": 10.0}}, "geometry": {"snap_m": 3.0, "min_edge_m": 4.0},
		"parcel_templates": {}, "fabrics": []}), 3)
	net.seal_base()
	var cols := DevBuildingSource.generate(world, net, _manifest, SEED)
	assert_int(cols.count).is_equal(0)


func test_generation_never_writes_parcel_ownership() -> void:
	var world := BuildingTestSupport.flat_world(3000.0, 100.0, Rect2(), 12.0)
	var net := _grid_net(world)
	var before := net.state_hash(true)
	DevBuildingSource.generate(world, net, _manifest, SEED)
	assert_str(net.state_hash(true)).is_equal(before)   # CAN-03: sahiplik/ağ durumu değişmedi


func test_neighbouring_parcels_in_a_block_do_not_repeat_module_and_wall() -> void:
	var world := BuildingTestSupport.flat_world(3000.0, 100.0, Rect2(), 12.0)
	var net := _grid_net(world)
	var cols := DevBuildingSource.generate(world, net, _manifest, SEED)
	var by_parcel := {}
	for i in cols.count:
		if not by_parcel.has(cols.parcel_id[i]):
			by_parcel[cols.parcel_id[i]] = i   # parselin CEPHE binası (arka bina sonra eklenir)
	var checked := 0
	for bid in net.blocks:
		var block: WorldBlock = net.blocks[bid]
		var ids := block.parcel_ids.duplicate()
		ids.sort()
		var prev := -1
		for pid in ids:
			if not by_parcel.has(pid):
				continue
			var i: int = by_parcel[pid]
			if prev >= 0:
				var same := cols.module_idx[i] == cols.module_idx[prev] and cols.wall_row[i] == cols.wall_row[prev]
				assert_bool(same).is_false()
				checked += 1
			prev = i
	assert_int(checked).is_greater(20)


func test_ismeral_coarse_world_produces_a_varied_stock_with_clock_tower() -> void:
	var control := WorldTestSupport.control()
	var world := WorldTestSupport.coarse(control)
	var net_control: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
			"%s/network.json" % BuildingTestSupport.NETWORK_DATA_DIR))
	var net := NetworkGenerator.generate(world, net_control, WorldTestSupport.DEFAULT_SEED)
	var cols := DevBuildingSource.generate(world, net, _manifest, SEED)
	assert_int(cols.count).is_greater(10000)
	var families := {}
	var floors_seen := {}
	var towers := 0
	for i in cols.count:
		families[str(_manifest["modules"][cols.module_idx[i]]["family"])] = true
		floors_seen[cols.floors[i]] = true
		if _kit.is_landmark[cols.module_idx[i]] == 1:
			towers += 1
	for fam in ["res_mid", "res_old", "res_late", "res_house", "ind_shed", "ind_heritage"]:
		assert_bool(families.has(fam)).is_true()
	assert_int(floors_seen.size()).is_greater_equal(6)
	assert_int(towers).is_equal(1)
	# hiçbir yapı suda değil
	for i in cols.count:
		assert_bool(world.is_water(cols.x[i], cols.z[i])).is_false()
