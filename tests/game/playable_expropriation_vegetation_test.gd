extends GdUnitTestSuite
## T-042b · alınan parselin İÇİNDEKİ bitki örtüsü: `PlayableExpropriation` alınan parseli (yapılı olsun olmasın)
## `VegetationView`dan gizler, geri alınca geri getirir; bitki yerleşimi geç gelirse de, değişim günlüğü eksikse de aynı
## sonuç; parsel dışı (sokak) ağaçlar ve yol koridoru kaynağı etkilenmez. Gerçek `WorldNetwork`, gerçek `VegetationView`
## (mesh'siz, yalnız sayılar), sim yok. Başsız.

const DX := 160.0
const DZ := 100.0
const ORIGIN := Vector2(500.0, 500.0)
const LOCAL := WorldRoadEdge.CLASS_LOCAL
const THROUGH: Array = [Vector2(580, 500), Vector2(580, 600)]
const TREES_PER_PARCEL := 4

var _net_world: WorldData
var _view_world: WorldData
var _kit: BuildingKit


func before() -> void:
	_net_world = NetworkTestSupport.flat_world(3000.0)
	_view_world = BuildingTestSupport.flat_world(8000.0, 100.0, Rect2(), 15.0)
	_kit = BuildingTestSupport.kit()


func _in_range_config() -> VegetationViewConfig:
	var cfg := VegetationViewConfig.load_default()
	cfg.blob_enabled = false
	cfg.lod0_end_m = 1.0e9
	cfg.lod1_end_m = 2.0e9
	cfg.palm_proxy_end_m = 3.0e9
	return cfg


## Her parselin içinde `TREES_PER_PARCEL` ağaç (merkez çevresinde) + sokakta (parsel dışı) bir ağaç.
func _veg_layout(net: WorldNetwork, ids: Array) -> VegetationLayout:
	var vc := VegetationColumns.new()
	for pid: int in ids:
		var parcel := net.parcels[pid] as WorldParcel
		for n in TREES_PER_PARCEL:
			var p := parcel.centroid + Vector2(float(n) - 1.5, float(n % 2) - 0.5) * 1.5
			assert_bool(Geometry2D.is_point_in_polygon(p, parcel.outline)).is_true()
			vc.add(0, p.x, p.y, 0.0, 1.0, VegetationColumns.LAYER_YARD)
	vc.add(0, ORIGIN.x - 20.0, ORIGIN.y - 20.0, 0.0, 1.0, VegetationColumns.LAYER_STREET)   # hiçbir parselin içinde değil
	vc.finalize(Vector2.ZERO, Vector2(3000.0, 3000.0), 256.0)
	return VegetationLayout.build(vc, null, VegetationViewTestSupport.species().height_m,
			VegetationViewTestSupport.has_proxy())


func _veg_view(lay: VegetationLayout, cam: Vector3) -> VegetationView:
	var view: VegetationView = auto_free(VegetationView.new())
	add_child(view)
	view.setup(VegetationViewTestSupport.look_numbers(), _in_range_config())
	view.set_layout(lay)
	view.track_camera(cam)
	view.settle()
	return view


## Izgara ağı, yalnız çift sıradaki parsellerde T0 yapısı (tek sıradakiler boş arsa), `holder.v` bitki görünümü.
func _fixture(with_veg_view: bool = true) -> Dictionary:
	var net := NetworkTestSupport.grid_network(_net_world, 3, 3, DX, DZ, ORIGIN, 7, NetworkTestSupport.KEEP_PARCELS)
	var ids: Array = net.parcels.keys()
	ids.sort()
	var module := _kit.module_index(BuildingTestSupport.MID_A)
	var rows: Array = []
	for n in ids.size():
		if n % 2 == 0:
			var c := (net.parcels[ids[n]] as WorldParcel).centroid
			rows.append({"m": module, "x": c.x, "z": c.y, "parcel": ids[n]})
	var cols := BuildingTestSupport.columns(rows)
	var bview: BuildingView = auto_free(BuildingView.new())
	add_child(bview)
	var cfg := BuildingViewConfig.new()
	cfg.use_threads = false
	bview.setup(_view_world, _kit, cfg)
	bview.set_columns(cols, 1)
	var occupied := {}
	for r: Dictionary in rows:
		occupied[int(r["parcel"])] = true
	var lay := _veg_layout(net, ids)
	var holder := {"v": null}
	var cam := Vector3(ORIGIN.x + DX, 5.0, ORIGIN.y + DZ)
	if with_veg_view:
		holder["v"] = _veg_view(lay, cam)
	var follow := PlayableExpropriation.create(net, cols, bview, occupied, null, Callable(),
			func() -> Object: return holder["v"])
	return {"net": net, "ids": ids, "lay": lay, "holder": holder, "follow": follow, "cam": cam, "cols": cols}


func _take(net: WorldNetwork) -> PackedInt32Array:
	var rep := net.add_road_expropriating(PackedVector2Array(THROUGH), LOCAL)
	assert_bool(rep["ok"]).override_failure_message(str(rep)).is_true()
	var removed := PackedInt32Array()
	for pid in rep["removed_parcels"]:
		removed.append(int(pid))
	return removed


## Satırın hangi parselin içinde olduğu (ağ verisi; -1 = hiçbiri).
func _parcel_of_row(lay: VegetationLayout, snap: Dictionary, row: int) -> int:
	var p := Vector2(lay.cols.x[row], lay.cols.z[row])
	for pid: int in snap:
		if Geometry2D.is_point_in_polygon(p, (snap[pid] as WorldParcel).outline):
			return pid
	return -1


func _hidden_rows(lay: VegetationLayout) -> PackedInt32Array:
	var out := PackedInt32Array()
	for i in lay.cols.count:
		if lay.is_hidden(i):
			out.append(i)
	return out


func test_trees_inside_taken_parcels_are_hidden_with_or_without_a_building_and_undo_brings_them_back() -> void:
	var fx := _fixture()
	var net: WorldNetwork = fx["net"]
	var lay: VegetationLayout = fx["lay"]
	var view: VegetationView = fx["holder"]["v"]
	var follow: PlayableExpropriation = fx["follow"]
	var snap := net.parcels.duplicate()
	var all := lay.cols.count
	assert_int(view.visible_instances().x).is_equal(all)
	var removed := _take(net)
	assert_int(removed.size()).is_greater(1)
	var with_building := 0
	for pid in removed:
		with_building += 1 if (fx["cols"] as BuildingColumns).occupied_parcels().has(pid) else 0
	assert_int(with_building).is_less(removed.size())   # boş arsa da alındı: bitkisi gizlenmeli
	follow.settle()
	view.settle()
	var hidden := _hidden_rows(lay)
	assert_int(hidden.size()).is_equal(removed.size() * TREES_PER_PARCEL)
	for row in hidden:
		assert_bool(removed.has(_parcel_of_row(lay, snap, row))).is_true()   # yalnız alınan parsellerin içindekiler
	assert_int(view.visible_instances().x).is_equal(all - hidden.size())
	# sokak ağacı ve alınmayan parsellerin ağaçları duruyor
	assert_int(_hidden_rows(lay).size()).is_equal(removed.size() * TREES_PER_PARCEL)
	assert_int(int(follow.stats.get("veg_parcels", 0))).is_equal(removed.size())
	# geri alma: parsellerin kimlikleriyle geri gelen parseller bitkisini geri alır
	net.undo_last_op()
	follow.settle()
	view.settle()
	assert_int(lay.hidden_count).is_equal(0)
	assert_int(view.visible_instances().x).is_equal(all)
	assert_bool(follow.busy()).is_false()


func test_vegetation_that_arrives_after_the_takeover_is_masked_when_it_appears() -> void:
	var fx := _fixture(false)
	var net: WorldNetwork = fx["net"]
	var lay: VegetationLayout = fx["lay"]
	var follow: PlayableExpropriation = fx["follow"]
	var removed := _take(net)
	follow.settle()   # bitki görünümü yok: iş beklemez, busy değil
	assert_bool(follow.busy()).is_false()
	fx["holder"]["v"] = _veg_view(lay, fx["cam"])
	assert_bool(follow.busy()).is_true()
	follow.settle()
	assert_int(lay.hidden_count).is_equal(removed.size() * TREES_PER_PARCEL)
	# yeni yerleşim (set_layout) gelirse baştan istenir
	var lay2 := _veg_layout(net, (fx["ids"] as Array).filter(func(p: int) -> bool: return net.parcels.has(p)))
	(fx["holder"]["v"] as VegetationView).set_layout(lay2)
	follow.settle()
	assert_int(lay2.hidden_count).is_equal(0)   # bu yerleşimde alınan parsellerin içinde ağaç yok


func test_a_change_log_gap_gives_the_same_vegetation_mask() -> void:
	var fx := _fixture()
	var net: WorldNetwork = fx["net"]
	var lay: VegetationLayout = fx["lay"]
	var follow: PlayableExpropriation = fx["follow"]
	var removed := _take(net)
	net.change_log.clear()
	assert_bool(net.change_log_covers(0)).is_false()
	var rep := follow.reconcile()
	assert_bool(rep["full"]).is_true()
	follow.settle()
	assert_int(lay.hidden_count).is_equal(removed.size() * TREES_PER_PARCEL)
	assert_int(int(follow.stats["veg_parcels"])).is_equal(removed.size())


func test_corridor_refresh_does_not_unhide_taken_parcel_trees_and_each_source_clears_on_its_own() -> void:
	var fx := _fixture()
	var net: WorldNetwork = fx["net"]
	var lay: VegetationLayout = fx["lay"]
	var view: VegetationView = fx["holder"]["v"]
	var follow: PlayableExpropriation = fx["follow"]
	var removed := _take(net)
	follow.settle()
	var parcel_hidden := lay.hidden_count
	assert_int(parcel_hidden).is_equal(removed.size() * TREES_PER_PARCEL)
	# playable `_refresh_vegetation_corridors` her yol değişiminde koridor kaynağını baştan kurar
	view.set_corridors(VegetationCorridor.from_network(net, RoadStyle.load_default()))
	view.settle()
	assert_int(lay.hidden_count).is_greater_equal(parcel_hidden)
	net.undo_last_op()
	view.set_corridors(VegetationCorridor.from_network(net, RoadStyle.load_default()))
	follow.settle()
	view.settle()
	assert_int(lay.hidden_count).is_equal(0)


func test_scan_is_sliced_across_polls_with_a_tiny_budget() -> void:
	var fx := _fixture()
	var net: WorldNetwork = fx["net"]
	var lay: VegetationLayout = fx["lay"]
	var follow: PlayableExpropriation = fx["follow"]
	var removed := _take(net)
	var polls := 0
	while follow.busy() and polls < 5000:
		follow.poll(1)   # 1 us bütçe: her çağrıda en az bir dilim ilerler, hiçbir çağrı tüm işi yapmaz
		polls += 1
	assert_bool(follow.busy()).is_false()
	assert_int(lay.hidden_count).is_equal(removed.size() * TREES_PER_PARCEL)
	assert_int(polls).is_greater(1)
