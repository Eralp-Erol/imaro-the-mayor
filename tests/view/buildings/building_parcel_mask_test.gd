extends GdUnitTestSuite
## T-042b (WLD-01, D-011) · `BuildingView.set_parcels_hidden`: kamulaştırmada alınan parselin yapıları görünümden
## ARTIMLI süzülür (yalnız etkilenen hücre + süper-chunk kurulur; tüm plan/özet yeniden hesaplanmaz) ve geri alınca
## BİT-BİT aynı görünüm döner. Sütunlar değişmez; çatı dizini (kamera göz açıklığı) da yıkılan yapıyı saymaz.
## Başsız (dummy renderer): düğüm/özet düzeyi; görüntü doğrulaması capture ile.

var _kit: BuildingKit
var _world: WorldData


func before() -> void:
	_kit = BuildingTestSupport.kit()
	_world = BuildingTestSupport.flat_world(8000.0, 100.0, Rect2(), 15.0)


func _view() -> BuildingView:
	var view: BuildingView = auto_free(BuildingView.new())
	add_child(view)
	var cfg := BuildingViewConfig.new()
	cfg.use_threads = false
	view.setup(_world, _kit, cfg)
	return view


## 3 hücre: A (0,0) parsel 1..10 ve 100..109, B (2,0) parsel 300, C (6,6) parsel 301 (başka süper-chunk).
func _cols() -> BuildingColumns:
	var a := _kit.module_index(BuildingTestSupport.MID_A)
	var b := _kit.module_index(BuildingTestSupport.HOUSE_B)
	var rows: Array = []
	for i in 10:
		rows.append({"m": a, "x": 500.0 + i * 40.0, "z": 500.0, "parcel": 1 + i})
		rows.append({"m": b, "x": 500.0 + i * 40.0, "z": 540.0, "parcel": 100 + i})
	rows.append({"m": a, "x": 2600.0, "z": 500.0, "parcel": 300})
	rows.append({"m": a, "x": 6100.0, "z": 6100.0, "parcel": 301})
	return BuildingTestSupport.columns(rows)


func _drain(view: BuildingView) -> void:
	var guard := 0
	while view.pending_work() > 0 and guard < 100:
		view.pump_pending(1000000)
		guard += 1


func test_hiding_parcels_rebuilds_only_the_affected_cell_and_super_chunk() -> void:
	var view := _view()
	view.set_columns(_cols(), 1)
	var other_cell := view.cell_node(Vector2i(2, 0))
	var far_super := view.super_node(Vector2i(1, 1))
	var far_cell := view.cell_node(Vector2i(6, 6))
	var near_cell_before := view.cell_node(Vector2i(0, 0))
	var res := view.set_parcels_hidden(PackedInt32Array([1, 2, 3]), true)
	assert_bool(res["ok"]).is_true()
	assert_int(res["rows"]).is_equal(3)
	assert_int(res["cells"]).is_equal(1)
	assert_int(view.pending_work()).is_greater(0)
	_drain(view)
	assert_int(view.building_count()).is_equal(22 - 3)
	assert_int(int(view.stats["drawn"])).is_equal(19)
	# etkilenmeyen hücreler ve uzak süper-chunk AYNI düğüm (yeniden kurulmadı)
	assert_object(view.cell_node(Vector2i(2, 0))).is_same(other_cell)
	assert_object(view.cell_node(Vector2i(6, 6))).is_same(far_cell)
	assert_object(view.super_node(Vector2i(1, 1))).is_same(far_super)
	assert_object(view.cell_node(Vector2i(0, 0))).is_not_same(near_cell_before)


func test_showing_the_parcels_again_restores_the_exact_view() -> void:
	var view := _view()
	var cols := _cols()
	view.set_columns(cols, 1)
	var before := _signature(view, cols)
	view.set_parcels_hidden(PackedInt32Array([1, 2, 3, 104]), true)
	_drain(view)
	assert_str(_signature(view, cols)).is_not_equal(before)
	view.set_parcels_hidden(PackedInt32Array([1, 2, 3, 104]), false)
	_drain(view)
	assert_str(_signature(view, cols)).is_equal(before)
	assert_int(view.building_count()).is_equal(22)


func test_hidden_set_matches_a_full_rebuild_from_filtered_columns() -> void:
	var view := _view()
	var cols := _cols()
	view.set_columns(cols, 1)
	view.set_parcels_hidden(PackedInt32Array([2, 5, 107, 300]), true)
	_drain(view)
	var ref := _view()
	var kept := _filtered(cols, [2, 5, 107, 300])
	ref.set_columns(kept, 1)
	assert_str(_signature(view, cols)).is_equal(_signature(ref, kept))


func test_hiding_every_row_of_a_cell_removes_the_cell_and_a_second_hide_is_a_noop() -> void:
	var view := _view()
	view.set_columns(_cols(), 1)
	var res := view.set_parcels_hidden(PackedInt32Array([300]), true)
	assert_int(res["cells"]).is_equal(1)
	_drain(view)
	assert_object(view.cell_node(Vector2i(2, 0))).is_null()
	var again := view.set_parcels_hidden(PackedInt32Array([300]), true)
	assert_int(again["rows"]).is_equal(0)
	assert_int(view.pending_work()).is_equal(0)
	# bilinmeyen kimlik zararsız
	assert_int(view.set_parcels_hidden(PackedInt32Array([99999]), true)["rows"]).is_equal(0)


func test_roof_index_ignores_demolished_buildings_and_gets_them_back() -> void:
	var view := _view()
	view.set_columns(_cols(), 1)
	var roofs := view.roof_clearance()
	assert_float(roofs.max_roof_y(2600.0, 500.0, 2.0)).is_greater(RoofClearance.NO_ROOF)
	view.set_parcels_hidden(PackedInt32Array([300]), true)
	assert_float(roofs.max_roof_y(2600.0, 500.0, 2.0)).is_equal(RoofClearance.NO_ROOF)
	view.set_parcels_hidden(PackedInt32Array([300]), false)
	assert_float(roofs.max_roof_y(2600.0, 500.0, 2.0)).is_greater(RoofClearance.NO_ROOF)


func test_pump_respects_the_budget_but_always_makes_progress() -> void:
	var view := _view()
	view.set_columns(_cols(), 1)
	view.set_parcels_hidden(PackedInt32Array([1, 300, 301]), true)   # üç hücre
	var rounds := 0
	while view.pending_work() > 0 and rounds < 100:
		var rep := view.pump_pending(0)   # bütçe 0: tur başına en az bir birim
		assert_int(rep["done"]).is_greater(0)
		rounds += 1
	assert_int(view.pending_work()).is_equal(0)
	assert_int(rounds).is_greater(1)   # tek turda bitmedi: dilimlendi


func test_a_new_set_columns_keeps_the_hidden_parcels_hidden() -> void:
	var view := _view()
	view.set_columns(_cols(), 1)
	view.set_parcels_hidden(PackedInt32Array([1, 2]), true)
	_drain(view)
	view.set_columns(_cols(), 2)   # yeni sürüm: aynı sütunlar
	assert_int(view.building_count()).is_equal(20)
	assert_int(int(view.stats["drawn"])).is_equal(20)


func _filtered(cols: BuildingColumns, drop: Array) -> BuildingColumns:
	var out := BuildingColumns.new()
	for i in cols.count:
		if drop.has(cols.parcel_id[i]):
			continue
		out.add(cols.parcel_id[i], cols.module_idx[i], cols.x[i], cols.z[i], cols.yaw[i], cols.floors[i],
				cols.wall_row[i], cols.roof_row[i], cols.accent_row[i], cols.bright[i], cols.flags[i], cols.era[i])
	return out


## Görünümün içerik imzası: hücre anahtarları + hücrede çizilen yapıların konumları + süper-chunk anahtarları
## (sütun dizini değil: süzülmüş sütunlarla karşılaştırılabilsin).
func _signature(view: BuildingView, cols: BuildingColumns) -> String:
	var parts: Array[String] = []
	for k in view.cell_keys():
		var data := view.cell_summary(k)
		var at: Array[String] = []
		for i in data.kept:
			at.append("%.0f,%.0f" % [cols.x[i], cols.z[i]])
		at.sort()
		parts.append("%s:%d:%s" % [str(k), data.instance_count(), ";".join(at)])
	for k in view.super_keys():
		parts.append("S%s" % str(k))
	parts.sort()
	return "|".join(parts)
