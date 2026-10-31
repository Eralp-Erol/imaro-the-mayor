extends GdUnitTestSuite
## T-042b (WLD-01, D-011) · Kent zemini maskesinin YEREL yenilenmesi: kamulaştırmada alınan parselin altı artık kent
## zemini
## değildir (ağda parsel yok), geri alınca döner; yenileme pencere dışındaki pikselleri değiştirmez; boyama bütçeyle
## dilimlenebilir. Gerçek `WorldNetwork` (kamulaştırmalı yol + geri alma), başsız.

const PARAMS := {"max_px": 512, "min_cell_m": 10.0, "grow_m": 2.0, "margin_m": 200.0, "block_fill_min": 0.5}
const DX := 160.0
const DZ := 100.0
const ORIGIN := Vector2(500.0, 500.0)
const THROUGH: Array = [Vector2(580, 500), Vector2(580, 600)]

var _world: WorldData


func before() -> void:
	_world = NetworkTestSupport.flat_world(3000.0)


func _fixture() -> Dictionary:
	var net := NetworkTestSupport.grid_network(_world, 3, 3, DX, DZ, ORIGIN, 7, NetworkTestSupport.KEEP_PARCELS)
	var cols := BuildingColumns.new()
	var ids: Array = net.parcels.keys()
	ids.sort()
	for pid: int in ids:
		var c := (net.parcels[pid] as WorldParcel).centroid
		cols.add(pid, 0, c.x, c.y, 0.0, 3, 0, 0, 0, 128, 0, BuildingColumns.ERA_MID)
	var mask := UrbanGroundMask.build(net, cols, PARAMS)
	assert_bool(mask.is_empty()).is_false()
	return {"net": net, "cols": cols, "mask": mask, "image": (mask["image"] as Image).duplicate(),
			"info": {"origin": mask["origin"], "cell_m": mask["cell_m"]}, "occ": UrbanGroundMask.occupancy(cols)}


func _px(fx: Dictionary, p: Vector2) -> Color:
	var origin: Vector2 = fx["info"]["origin"]
	var cell := float(fx["info"]["cell_m"])
	return (fx["image"] as Image).get_pixel(int((p.x - origin.x) / cell), int((p.y - origin.y) / cell))


func _take(net: WorldNetwork) -> Dictionary:
	var rep := net.add_road_expropriating(PackedVector2Array(THROUGH), WorldRoadEdge.CLASS_LOCAL)
	assert_bool(rep["ok"]).override_failure_message(str(rep)).is_true()
	var change: NetworkChange = net.change_log[net.change_log.size() - 1]
	return {"removed": rep["removed_parcels"], "rect": change.dirty_rect}


func test_taken_parcel_ground_is_cleared_and_undo_paints_it_back() -> void:
	var fx := _fixture()
	var net: WorldNetwork = fx["net"]
	var victim := int(RoadDraftCheck.taken_parcels(net, PackedVector2Array(THROUGH), WorldRoadEdge.CLASS_LOCAL)[0])
	var c := net.parcel(victim).centroid
	assert_float(_px(fx, c).r).is_greater(0.9)
	var far := Vector2(2300.0, 2300.0)
	var far_before := _px(fx, far)
	var taken := _take(net)
	var rect: Rect2 = taken["rect"]
	assert_bool(rect.has_area()).is_true()
	var rep := UrbanGroundMask.repaint(fx["image"], fx["info"], net, fx["occ"], PARAMS, rect)
	assert_int(rep["parcels"]).is_greater(0)
	assert_float(_px(fx, c).r).override_failure_message("alınan parselin zemini silinmedi").is_equal(0.0)
	assert_bool(_px(fx, far) == far_before).is_true()   # pencere dışı değişmez
	# Alınmayan komşu parsel hâlâ kent zemini.
	var kept: WorldParcel = null
	for pid: int in net.parcels:
		var p: WorldParcel = net.parcels[pid]
		if rect.has_point(p.centroid):
			kept = p
			break
	assert_object(kept).is_not_null()
	assert_float(_px(fx, kept.centroid).r).is_greater(0.9)
	net.undo_last_op()
	UrbanGroundMask.repaint(fx["image"], fx["info"], net, fx["occ"], PARAMS, rect)
	assert_float(_px(fx, c).r).is_greater(0.9)


func test_repaint_in_slices_equals_one_shot() -> void:
	var fx := _fixture()
	var net: WorldNetwork = fx["net"]
	var taken := _take(net)
	var rect: Rect2 = taken["rect"]
	var one_shot := (fx["image"] as Image).duplicate()
	UrbanGroundMask.repaint(one_shot, fx["info"], net, fx["occ"], PARAMS, rect)
	var sliced: Image = (fx["image"] as Image).duplicate()
	var job := UrbanGroundMask.repaint_begin(sliced, fx["info"], net, PARAMS, rect)
	var steps := 1
	while not UrbanGroundMask.repaint_step(job, sliced, net, fx["occ"], 0):   # bütçe 0: çağrı başına bir parsel
		steps += 1
		assert_int(steps).is_less(100000)
	assert_int(steps).is_greater(1)   # gerçekten dilimlendi
	assert_array(sliced.get_data()).is_equal(one_shot.get_data())
