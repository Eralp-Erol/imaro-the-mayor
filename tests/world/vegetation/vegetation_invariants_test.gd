extends GdUnitTestSuite
## T-062 B0 · bitki yerleşimi dünya değişmezleri (tam Ismeral; WLD-01, WLD-08, VIS-01/02, TEK-03): bina ayak izi / yol /
## su / uçurum içine ağaç düşmez, ağaçlar çakışmaz, yalnız onaylı türler, tür-bölge dağılımı sınırları, bütçe.
## Doğrulayıcılar üreteçten AYRI hesaplar (`VegetationTestSupport`); her değişmez olumsuz örnekle de çalışır.

const TOL := 0.05


static func _full() -> VegetationColumns:
	return VegetationTestSupport.full()


# --- bina ayak izi / yol / su / uçurum ---

func test_no_tree_stands_inside_or_too_close_to_a_building_footprint() -> void:
	var res := SettlementTestSupport.full()
	var cols := _full()
	var trunk := float(VegetationTestSupport.control()["clearance"]["trunk_m"])
	var grid := VegetationTestSupport.building_grid(res)
	var worst := 1.0e9
	var bad := 0
	for i in cols.count:
		var d := VegetationTestSupport.building_distance(res, grid, cols.position_of(i))
		worst = minf(worst, d)
		if d < trunk - TOL:
			bad += 1
	assert_int(cols.count).is_greater(100000)
	assert_int(bad).override_failure_message("%d ağaç bina ayak izine < %.2f m (en kötü %.3f)" % [bad, trunk, worst]) \
			.is_equal(0)


func test_crown_clearance_rule_holds_per_species() -> void:
	var res := SettlementTestSupport.full()
	var cols := _full()
	var species := VegetationTestSupport.species()
	var ctl := VegetationTestSupport.control()
	var fracs: Dictionary = ctl["clearance"]["crown_frac"]
	var trunk := float(ctl["clearance"]["trunk_m"])
	var grid := VegetationTestSupport.building_grid(res)
	var layer_frac := {VegetationColumns.LAYER_STREET: "street", VegetationColumns.LAYER_YARD: "yard",
			VegetationColumns.LAYER_GROVE: "grove", VegetationColumns.LAYER_COAST: "scatter",
			VegetationColumns.LAYER_RURAL: "scatter"}
	var bad := 0
	for i in range(0, cols.count, 3):
		if not layer_frac.has(cols.layer[i]):
			continue   # hedge: ayrı kural
		var need := maxf(trunk, float(fracs[layer_frac[cols.layer[i]]]) * species.reach_m[cols.species[i]] * cols.scale[i])
		if VegetationTestSupport.building_distance(res, grid, cols.position_of(i)) < need - TOL:
			bad += 1
	assert_int(bad).is_equal(0)


func test_no_tree_stands_on_a_road_and_street_trees_keep_off_the_carriageway() -> void:
	var res := SettlementTestSupport.full()
	var cols := _full()
	var ctl := VegetationTestSupport.control()
	var edge := float(ctl["clearance"]["road_edge_m"])
	var sidewalk: Dictionary = ctl["sidewalk_m"]
	var on_road := 0
	var on_carriage := 0
	var street_on_sidewalk := 0
	var street_n := 0
	for i in range(0, cols.count, 2):
		var p := cols.position_of(i)
		var is_street := cols.layer[i] == VegetationColumns.LAYER_STREET
		if is_street:
			street_n += 1
			if VegetationTestSupport.road_gap(res.net, p, true, sidewalk) < edge - TOL:
				on_carriage += 1
			if VegetationTestSupport.road_gap(res.net, p, false, sidewalk) < 0.0:
				street_on_sidewalk += 1
		elif VegetationTestSupport.road_gap(res.net, p, false, sidewalk) < edge - TOL:
			on_road += 1
	assert_int(street_n).is_greater(10000)
	assert_int(on_road).override_failure_message("%d ağaç yol kesitine < %.1f m" % [on_road, edge]).is_equal(0)
	assert_int(on_carriage).override_failure_message("%d sokak ağacı araç yolunda" % on_carriage).is_equal(0)
	# Sokak ağaçları gerçekten kaldırım bandında duruyor (kural boş değil): çoğu yol kesiti içinde.
	assert_float(float(street_on_sidewalk) / float(street_n)).is_greater(0.5)


func test_no_tree_in_water_or_on_a_cliff() -> void:
	var cols := _full()
	var world := SettlementTestSupport.full().net.world
	var ctl := VegetationTestSupport.control()
	var above := float(ctl["terrain"]["min_above_sea_m"])
	var cliff := float(ctl["terrain"]["cliff_deg"])
	var caps: Dictionary = ctl["terrain"]["max_slope_deg"]
	var water := 0
	var low := 0
	var steep := 0
	for i in cols.count:
		var p := cols.position_of(i)
		if world.is_water(p.x, p.y):
			water += 1
		if world.height_at(p.x, p.y) < world.sea_level + above - TOL:
			low += 1
		var layer_cap := float(caps[String(VegetationColumns.LAYER_NAMES[cols.layer[i]])])
		if world.slope_degrees_at(p.x, p.y) > minf(layer_cap, cliff) + TOL:
			steep += 1
	assert_int(water).is_equal(0)
	assert_int(low).is_equal(0)
	assert_int(steep).is_equal(0)


func test_negative_the_checkers_do_catch_a_planted_tree_on_a_building_a_road_and_water() -> void:
	var res := SettlementTestSupport.full()
	var world := res.net.world
	var grid := VegetationTestSupport.building_grid(res)
	assert_float(VegetationTestSupport.building_distance(res, grid, res.columns.position_of(0))).is_equal(0.0)
	var e: WorldRoadEdge = res.net.edges[res.net.edges.keys()[0]]
	var mid := (res.net.node_pos(e.a) + res.net.node_pos(e.b)) * 0.5
	assert_float(VegetationTestSupport.road_gap(res.net, mid, false, {})).is_less(0.0)
	var sea := Vector2(world.origin.x + 100.0, world.origin.y + world.size.y * 0.5)
	assert_bool(world.is_water(sea.x, sea.y)).is_true()


# --- ağaç-ağaç aralığı ---

func test_trees_keep_their_separation_and_hedges_keep_off_trees() -> void:
	var cols := _full()
	var species := VegetationTestSupport.species()
	var ctl := VegetationTestSupport.control()
	var sep_frac := float(ctl["clearance"]["sep_frac"])
	var hedge_sep := float(ctl["clearance"]["hedge_tree_sep_m"])
	var hedge := species.index_of("hedge")
	var grid := {}
	for i in cols.count:
		var key := int(floor(cols.x[i] / 12.0)) + 8192 * int(floor(cols.z[i] / 12.0))
		if not grid.has(key):
			grid[key] = []
		(grid[key] as Array).append(i)
	var bad := 0
	for i in cols.count:
		var cx := int(floor(cols.x[i] / 12.0))
		var cz := int(floor(cols.z[i] / 12.0))
		var ri := species.reach_m[cols.species[i]] * cols.scale[i]
		for dz in range(-1, 2):
			for dx in range(-1, 2):
				var key := (cx + dx) + 8192 * (cz + dz)
				if not grid.has(key):
					continue
				for j: int in grid[key]:
					if j <= i:
						continue
					var hi := cols.species[i] == hedge
					var hj := cols.species[j] == hedge
					if hi and hj:
						continue
					var need := hedge_sep if hi != hj else sep_frac * (ri + species.reach_m[cols.species[j]] * cols.scale[j])
					if cols.position_of(i).distance_to(cols.position_of(j)) < need - TOL:
						bad += 1
	assert_int(bad).is_equal(0)


# --- onaylı türler ---

func test_only_approved_species_ids_are_used() -> void:
	var cols := _full()
	var gate := LibraryGate.load_plants()
	gate.report_errors = false
	assert_array(Array(gate.load_errors)).is_empty()
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/library/catalog.json"))
	var status := {}
	for entry: Dictionary in catalog["entries"]:
		status[str(entry["id"])] = str(entry["approval"])
	assert_int(cols.species_ids.size()).is_equal(10)
	for id in cols.species_ids:
		assert_bool(gate.is_approved(id)).override_failure_message("kapıdan geçmiyor: %s" % id).is_true()
		assert_str(str(status.get(id, "yok"))).is_equal("approved")
		assert_bool(id.begins_with("veg_hero_")).is_true()
	assert_bool(Array(cols.species_ids).has("veg_plane")).is_false()
	for i in cols.count:
		assert_int(cols.species[i]).is_less(cols.species_ids.size())
	var counts := cols.species_counts()
	for k in counts.size():
		assert_int(counts[k]).override_failure_message(cols.species_ids[k]).is_greater(0)


# --- tür-bölge dağılımı ---

func test_palms_are_few_and_only_near_the_coast_or_plaza() -> void:
	var cols := _full()
	var species := VegetationTestSupport.species()
	var world := SettlementTestSupport.full().net.world
	var ctl := VegetationTestSupport.control()
	var max_shore := maxf(float(ctl["palm"]["street"]["max_shore_m"]), float(ctl["palm"]["coast"]["max_shore_m"]))
	var palms := 0
	var far := 0
	var wrong_layer := 0
	var kinds := {}
	for i in cols.count:
		var key: String = species.keys[cols.species[i]]
		if not key.begins_with("palm_"):
			continue
		palms += 1
		kinds[key] = true
		var shore := world.shore_distance[world.world_to_index(cols.x[i], cols.z[i])]
		if shore <= 0.0 or shore > max_shore + world.cell_size:
			far += 1
		if cols.layer[i] != VegetationColumns.LAYER_STREET and cols.layer[i] != VegetationColumns.LAYER_COAST:
			wrong_layer += 1
	assert_int(palms).is_greater(20)
	assert_float(float(palms) / float(cols.count)).is_less(0.01)
	assert_int(far).is_equal(0)
	assert_int(wrong_layer).is_equal(0)
	# Q-018: iki tür de eşit ağırlıklı, hiçbiri "seçilmiş" değil.
	assert_int(kinds.size()).is_equal(2)
	var counts := cols.species_counts()
	var a := float(counts[species.index_of("palm_date")])
	var b := float(counts[species.index_of("palm_slender")])
	assert_float(minf(a, b) / maxf(a, b)).is_greater(0.6)


func test_coast_is_pine_dominated_and_hills_carry_maquis_and_stone_pine() -> void:
	var cols := _full()
	var species := VegetationTestSupport.species()
	var world := SettlementTestSupport.full().net.world
	var coast_total := 0
	var coast_pine := 0
	var rural_total := 0
	var rural_hill := 0
	var maquis_total := 0
	var maquis_slope := 0
	var pine_stone_total := 0
	var pine_stone_slope := 0
	for i in cols.count:
		var key: String = species.keys[cols.species[i]]
		if cols.layer[i] == VegetationColumns.LAYER_COAST:
			coast_total += 1
			coast_pine += 1 if key == "pine_brutia" else 0
		elif cols.layer[i] == VegetationColumns.LAYER_RURAL:
			rural_total += 1
			var slope := world.slope_degrees_at(cols.x[i], cols.z[i])
			rural_hill += 1 if slope >= 3.0 else 0
			if key == "maquis":
				maquis_total += 1
				maquis_slope += 1 if slope >= 3.0 else 0
			elif key == "pine_stone":
				pine_stone_total += 1
				pine_stone_slope += 1 if slope >= 3.0 else 0
	assert_int(coast_total).is_greater(1000)
	assert_float(float(coast_pine) / float(coast_total)).is_greater(0.6)
	assert_int(maquis_total).is_greater(1000)
	assert_int(pine_stone_total).is_greater(500)
	assert_float(float(maquis_slope) / float(maquis_total)).is_greater(0.8)
	assert_float(float(pine_stone_slope) / float(pine_stone_total)).is_greater(0.8)
	assert_int(rural_total).is_greater(10000)
	assert_int(rural_hill).is_greater(0)


func test_olive_groves_stand_on_rural_parcels_or_open_blocks_in_a_grid() -> void:
	var cols := _full()
	var net := SettlementTestSupport.full().net
	var total := 0
	var off := 0
	var olives := 0
	for i in range(0, cols.count, 4):
		if cols.layer[i] != VegetationColumns.LAYER_GROVE:
			continue
		total += 1
		var parcel := net.parcel_at(cols.x[i], cols.z[i])
		var block := net.block_at(cols.x[i], cols.z[i])
		var ok := (parcel != null and parcel.fabric == &"rural") or (block != null and block.kind == WorldBlock.KIND_OPEN)
		if not ok:
			off += 1
		var key: String = VegetationTestSupport.species().keys[cols.species[i]]
		olives += 1 if key.begins_with("olive_") else 0
	assert_int(total).is_greater(5000)
	assert_int(off).is_equal(0)
	assert_int(olives).is_equal(total)


func test_hedges_run_along_parcel_boundaries_inside_the_parcel() -> void:
	var cols := _full()
	var net := SettlementTestSupport.full().net
	var species := VegetationTestSupport.species()
	var hedge := species.index_of("hedge")
	var total := 0
	var outside := 0
	var far_from_edge := 0
	for i in range(0, cols.count, 3):
		if cols.species[i] != hedge:
			continue
		total += 1
		var p := cols.position_of(i)
		var parcel := net.parcel_at(p.x, p.y)
		if parcel == null:
			outside += 1
			continue
		var d := 1.0e9
		for k in parcel.outline.size():
			d = minf(d, NetworkGeometry.distance_point_segment(p, parcel.outline[k],
					parcel.outline[(k + 1) % parcel.outline.size()]))
		if d > 2.0:
			far_from_edge += 1
	assert_int(total).is_greater(2000)
	assert_int(outside).is_equal(0)
	assert_int(far_from_edge).is_equal(0)


func test_every_working_region_has_trees_and_the_city_is_not_bare() -> void:
	var cols := _full()
	var world := SettlementTestSupport.full().net.world
	var per_region := {}
	for i in cols.count:
		var code := String(world.region_code_at(cols.x[i], cols.z[i]))
		per_region[code] = int(per_region.get(code, 0)) + 1
	for code in WorldControlData.REGION_CODES:
		assert_int(int(per_region.get(code, 0))).override_failure_message("bölge %s ağaçsız" % code).is_greater(1000)


# --- bütçe ---

func test_instance_count_is_within_the_budget_and_layers_within_their_caps() -> void:
	var cols := _full()
	var ctl := VegetationTestSupport.control()
	var budget: Dictionary = ctl["budget"]
	assert_int(cols.count).is_less_equal(int(budget["max_instances"]))
	var counts := cols.layer_counts()
	for k in VegetationColumns.LAYER_NAMES.size():
		var layer_name := String(VegetationColumns.LAYER_NAMES[k])
		assert_int(counts[k]).override_failure_message(layer_name).is_less_equal(int(budget["layer_caps"][layer_name]))
	assert_int(cols.stats["layers"]["street"]["kept"]).is_equal(counts[VegetationColumns.LAYER_STREET])
	assert_int(cols.shape_errors().size()).is_equal(0)
	assert_str(str(cols.stats.get("error", ""))).is_empty()
