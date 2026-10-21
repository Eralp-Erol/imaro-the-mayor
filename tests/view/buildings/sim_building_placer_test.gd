extends GdUnitTestSuite
## T-040 · SimBuildingPlacer / SimBuildingMapping (başsız, saf): eşleme verisi geçerli; yerleşim deterministik ve parsel
## içinde; kat kademesi (kit modülleriyle) tek yönlü artar ve tamamda nihai modül; çok parselli T0 yapısına katılmış
## parsel ve geçersiz girdi yerleşmez. Gerçek küçük dünya: tests/game/m2_render_support.gd.

var _placer: SimBuildingPlacer
var _settlement: SettlementResult
var _ids: PackedInt64Array


func before() -> void:
	var fx := M2RenderSupport.fixture()
	_settlement = fx["settlement"]
	_placer = SimBuildingPlacer.create(_settlement, SimBuildingMapping.load_default(), M2RenderSupport.SEED)
	_ids = PackedInt64Array()
	var occupied := {}
	for pid in _settlement.columns.occupied_parcels():
		occupied[int(pid)] = true
	for v: ParcelView in fx["views"]:
		if not occupied.has(v.id) and _ids.size() < 12:
			_ids.append(v.id)


func _signature(plan: SimBuildingPlacer.Plan) -> String:
	var parts := PackedStringArray()
	for p in plan.pieces:
		parts.append("%s@%.3f,%.3f,%d,%d,%d" % [p.module.id, p.u0, p.v0, p.wall, p.roof, p.accent])
	return ";".join(parts)


func _edge_distance(p: Vector2, poly: PackedVector2Array) -> float:
	var best := INF
	for i in poly.size():
		best = minf(best, NetworkGeometry.distance_point_segment(p, poly[i], poly[(i + 1) % poly.size()]))
	return best


func test_default_mapping_is_valid_and_a_broken_one_is_rejected() -> void:
	var m := SimBuildingMapping.load_default()
	assert_bool(m.is_valid()).is_true()
	assert_bool(m.knows(&"residential")).is_true()
	assert_bool(m.knows(&"commercial")).is_true()
	assert_bool(m.wants_ground_shop(&"commercial")).is_true()
	assert_bool(m.wants_ground_shop(&"residential")).is_false()
	assert_bool(SimBuildingMapping.from_dict({}).is_valid()).is_false()
	assert_bool(SimBuildingMapping.from_dict({"uses": {}}).is_valid()).is_false()
	assert_object(SimBuildingPlacer.create(_settlement, SimBuildingMapping.from_dict({}), 1)).is_null()
	assert_object(SimBuildingPlacer.create(null, m, 1)).is_null()


func test_plans_are_deterministic_and_stay_inside_the_parcel() -> void:
	var net: WorldNetwork = M2RenderSupport.fixture()["net"]
	var placed := 0
	for pid in _ids:
		var a := _placer.plan(int(pid), &"residential", 4)
		var b := _placer.plan(int(pid), &"residential", 4)
		assert_bool(a == null).is_equal(b == null)
		if a == null:
			continue
		placed += 1
		assert_str(_signature(a)).is_equal(_signature(b))
		var wp: WorldParcel = net.parcels[int(pid)]
		for piece in a.pieces:
			var center := a.lot.to_world(piece.u0 + piece.module.w * 0.5, piece.v0 + piece.module.d * 0.5)
			for c in SettlementObb.corners(center.x, center.y, a.lot.yaw(), piece.module.w, piece.module.d):
				assert_bool(NetworkGeometry.point_in_polygon(c, wp.outline) or _edge_distance(c, wp.outline) < 0.5) \
						.override_failure_message("parsel %d: ayak izi köşesi dışarıda" % pid).is_true()
	assert_int(placed).is_greater(3)


func test_staging_is_monotonic_keeps_the_row_count_and_ends_in_the_final_module() -> void:
	var staged_any := false
	for pid in _ids:
		var plan := _placer.plan(int(pid), &"residential", 5)
		if plan == null:
			continue
		var final_rows := _placer.rows_for(plan, SimBuildingPlacer.FULL)
		var last_total := 0
		for progress in [0, 100, 250, 400, 600, 800, 999]:
			var rows := _placer.rows_for(plan, progress)
			assert_int(rows.size()).is_equal(final_rows.size())
			var total := 0
			for r in rows:
				total += r.floors
			assert_int(total).override_failure_message("parsel %d: kat azaldı (%d -> %d)" % [pid, last_total, total]) \
					.is_greater_equal(last_total)
			last_total = total
		var final_total := 0
		for i in final_rows.size():
			assert_int(final_rows[i].module).is_equal(plan.pieces[i].module.idx)
			final_total += final_rows[i].floors
		assert_int(last_total).is_less_equal(final_total)
		staged_any = staged_any or _placer.rows_for(plan, 1)[0].module != final_rows[0].module
	assert_bool(staged_any).override_failure_message("hiçbir parselde kat kademesi yok").is_true()


func test_commercial_plans_use_ground_shop_modules_and_residential_ones_do_not() -> void:
	var seen := 0
	for pid in _ids:
		var com := _placer.plan(int(pid), &"commercial", 3)
		if com != null:
			seen += 1
			for r in _placer.rows_for(com, SimBuildingPlacer.FULL):
				assert_int(r.flags & BuildingColumns.FLAG_GROUND_SHOP).is_equal(BuildingColumns.FLAG_GROUND_SHOP)
		var res := _placer.plan(int(pid), &"residential", 3)
		if res != null:
			for r in _placer.rows_for(res, SimBuildingPlacer.FULL):
				assert_int(r.flags & BuildingColumns.FLAG_GROUND_SHOP).is_equal(0)
	assert_int(seen).is_greater(0)


func test_invalid_requests_and_t0_consumed_parcels_are_not_placed() -> void:
	var pid := int(_ids[0])
	assert_object(_placer.plan(pid, &"industrial", 3)).is_null()
	assert_object(_placer.plan(pid, &"residential", 0)).is_null()
	assert_object(_placer.plan(-5, &"residential", 3)).is_null()
	assert_bool(_placer.plan(pid, &"residential", 3) != null).is_true()
	var copy := SettlementResult.with_columns(_settlement, _settlement.columns)
	copy.consumed = {pid: true}
	var blocked := SimBuildingPlacer.create(copy, SimBuildingMapping.load_default(), M2RenderSupport.SEED)
	assert_object(blocked.plan(pid, &"residential", 3)).override_failure_message(
			"çok parselli T0 yapısına katılmış parsele sim yapısı yerleşti").is_null()


func test_different_seed_or_units_may_change_the_plan_but_not_validity() -> void:
	var other := SimBuildingPlacer.create(_settlement, SimBuildingMapping.load_default(), M2RenderSupport.SEED + 1)
	var differing := 0
	for pid in _ids:
		var a := _placer.plan(int(pid), &"residential", 4)
		var b := other.plan(int(pid), &"residential", 4)
		if a != null and b != null and _signature(a) != _signature(b):
			differing += 1
	assert_int(differing).override_failure_message("tohum plana etki etmiyor").is_greater(0)


func test_next_stage_progress_marks_exactly_where_the_visible_stage_changes() -> void:
	var checked := 0
	for pid in _ids:
		var plan := _placer.plan(int(pid), &"residential", 5)
		if plan == null:
			continue
		checked += 1
		var p := 0
		while p < SimBuildingPlacer.FULL:
			var nxt := _placer.next_stage_progress(plan, p)
			assert_int(nxt).is_greater(p)
			assert_int(nxt).is_less_equal(SimBuildingPlacer.FULL)
			var sig := _rows_signature(plan, p)
			for q in range(p, mini(nxt, SimBuildingPlacer.FULL)):
				assert_str(_rows_signature(plan, q)).override_failure_message(
						"parsel %d: %d..%d arasında kademe değişti (q=%d)" % [pid, p, nxt, q]).is_equal(sig)
			p = nxt
	assert_int(checked).is_greater(3)


func _rows_signature(plan: SimBuildingPlacer.Plan, progress: int) -> String:
	var parts := PackedStringArray()
	for r in _placer.rows_for(plan, progress):
		parts.append(r.signature())
	return ";".join(parts)
