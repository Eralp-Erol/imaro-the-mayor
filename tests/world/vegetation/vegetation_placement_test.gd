extends GdUnitTestSuite
## T-062 B0 · bitki yerleşimi üreteci (hafif ağ): determinizm (aynı tohum bayt-eşit, farklı tohum farklı),
## bütçe kırpması, palmiye parametreleri (Q-018: azaltılabilir), meydan çevresi, hücre indeksi, sim'e dokunmama.


func _bytes_equal(a: VegetationColumns, b: VegetationColumns) -> bool:
	var x := VegetationTestSupport.columns_bytes(a)
	var y := VegetationTestSupport.columns_bytes(b)
	for k in x.size():
		if x[k] != y[k]:
			return false
	return true


func _control_with(mutate: Callable) -> Dictionary:
	var ctl := VegetationTestSupport.control()
	mutate.call(ctl)
	return ctl


# --- determinizm (TEK-01/02) ---

func test_same_seed_gives_byte_equal_output_and_a_different_seed_does_not() -> void:
	var a := VegetationTestSupport.light()
	var b := VegetationTestSupport.light_with(VegetationTestSupport.VEG_SEED, VegetationTestSupport.rules())
	assert_int(a.count).is_greater(10000)
	assert_bool(_bytes_equal(a, b)).is_true()
	assert_str(a.state_hash()).is_equal(b.state_hash())
	var c := VegetationTestSupport.light_with(VegetationTestSupport.VEG_SEED + 1, VegetationTestSupport.rules())
	assert_str(c.state_hash()).is_not_equal(a.state_hash())
	assert_bool(_bytes_equal(a, c)).is_false()
	# Farklı tohum aynı kurallarla aynı mertebede örnek verir (tohum yalnız konumları karıştırır, kuralları değil).
	assert_float(float(c.count) / float(a.count)).is_between(0.9, 1.1)


func test_default_seed_derives_from_the_world_seed_with_the_veg_label() -> void:
	var world := SettlementTestSupport.light().net.world
	assert_int(VegetationPlacement.default_seed(world)).is_equal(NetworkRules.stream_seed(world.world_seed, "veg"))
	var other := NetworkRules.stream_seed(world.world_seed, "settlement")
	assert_int(VegetationPlacement.default_seed(world)).is_not_equal(other)


func test_generation_does_not_touch_the_settlement_or_the_network() -> void:
	var res := SettlementTestSupport.light()
	var before_cols := res.columns.state_hash()
	var before_net := res.net.state_hash()
	var before_topo := res.topology_hash()
	var cols := VegetationTestSupport.light_with(VegetationTestSupport.VEG_SEED + 7, VegetationTestSupport.rules())
	assert_int(cols.count).is_greater(0)
	assert_str(res.columns.state_hash()).is_equal(before_cols)
	assert_str(res.net.state_hash()).is_equal(before_net)
	assert_str(res.topology_hash()).is_equal(before_topo)


func test_generator_sources_use_no_forbidden_apis() -> void:
	for file_name in ["vegetation_placement", "vegetation_obstacles", "vegetation_columns", "vegetation_rules",
			"vegetation_species"]:
		var hits := WorldTestSupport.forbidden_api_hits("res://src/world/vegetation/%s.gd" % file_name)
		assert_array(Array(hits)).override_failure_message("%s: %s" % [file_name, str(hits)]).is_empty()


# --- bütçe ---

func test_tiny_budget_caps_the_total_and_the_layers_and_drops_far_trees_first() -> void:
	var full := VegetationTestSupport.light()
	var ctl := _control_with(func(c: Dictionary) -> void:
		c["budget"]["max_instances"] = 3000
		for k: String in c["budget"]["layer_caps"]:
			c["budget"]["layer_caps"][k] = 700)
	var small := VegetationTestSupport.light_with(VegetationTestSupport.VEG_SEED, VegetationTestSupport.rules(ctl))
	assert_int(small.count).is_less_equal(3000)
	assert_int(small.count).is_greater(1500)
	var counts := small.layer_counts()
	for k in counts.size():
		assert_int(counts[k]).is_less_equal(700)
	# Kırpma kayıp bildirir ve şehre yakın örnekleri tutar: kalanların ortalama şehir uzaklığı <= tam çıktınınkinden.
	var dropped := 0
	for k: String in small.stats["layers"]:
		dropped += int(small.stats["layers"][k]["dropped_by_cap"])
	assert_int(dropped).is_greater(0)
	var cols := SettlementTestSupport.light().columns
	var mean_small := _mean_urban_distance(small, cols)
	var mean_full := _mean_urban_distance(full, cols)
	assert_float(mean_small).is_less_equal(mean_full)
	# Kırpılmış çıktı tam çıktının (aynı tohum) alt kümesi DEĞİL olmak zorunda değil ama kırpma ayrıca deterministiktir.
	var again := VegetationTestSupport.light_with(VegetationTestSupport.VEG_SEED, VegetationTestSupport.rules(ctl))
	assert_str(again.state_hash()).is_equal(small.state_hash())


func _mean_urban_distance(cols: VegetationColumns, bld: BuildingColumns) -> float:
	var sample := PackedVector2Array()
	for i in range(0, bld.count, 7):
		sample.append(bld.position_of(i))
	var total := 0.0
	var n := 0
	for i in range(0, cols.count, 11):
		var best := 1.0e9
		var p := cols.position_of(i)
		for q in sample:
			best = minf(best, p.distance_squared_to(q))
		total += sqrt(best)
		n += 1
	return total / float(maxi(n, 1))


# --- palmiye (Q-018) ---

func test_palms_can_be_disabled_or_scaled_to_zero_by_data() -> void:
	var base := VegetationTestSupport.light()
	var palm_a := VegetationTestSupport.species().index_of("palm_date")
	var palm_b := VegetationTestSupport.species().index_of("palm_slender")
	var counts := base.species_counts()
	assert_int(counts[palm_a] + counts[palm_b]).is_greater(0)
	for mutate in [func(c: Dictionary) -> void: c["palm"]["enabled"] = false,
			func(c: Dictionary) -> void: c["palm"]["multiplier"] = 0.0]:
		var cols := VegetationTestSupport.light_with(VegetationTestSupport.VEG_SEED,
				VegetationTestSupport.rules(_control_with(mutate)))
		var cc := cols.species_counts()
		assert_int(cc[palm_a] + cc[palm_b]).is_equal(0)
		assert_int(cols.count).is_greater(base.count - 3000)
	var doubled := VegetationTestSupport.light_with(VegetationTestSupport.VEG_SEED, VegetationTestSupport.rules(
			_control_with(func(c: Dictionary) -> void: c["palm"]["multiplier"] = 2.0)))
	var dc := doubled.species_counts()
	assert_int(dc[palm_a] + dc[palm_b]).is_greater(counts[palm_a] + counts[palm_b])


func test_plaza_rim_is_planted_only_when_a_plaza_exists_and_never_inside_it() -> void:
	var res := SettlementTestSupport.light()
	var world := res.net.world
	var center := world.region_by_code(&"D4").anchor
	var plaza_res := SettlementResult.with_columns(res, res.columns)
	plaza_res.plaza = {"block_id": 1, "center": center, "axis": Vector2(1, 0), "size": Vector2(60, 40)}
	var ctl := _control_with(func(c: Dictionary) -> void: c["palm"]["plaza"]["share"] = 1.0)
	var with_plaza := VegetationPlacement.generate(plaza_res, VegetationTestSupport.species(),
			VegetationTestSupport.rules(ctl), VegetationTestSupport.VEG_SEED, false)
	var without := VegetationTestSupport.light_with(VegetationTestSupport.VEG_SEED, VegetationTestSupport.rules(ctl))
	assert_bool(bool(with_plaza.stats["plaza"])).is_true()
	assert_bool(bool(without.stats["plaza"])).is_false()
	var rim := Rect2(center - Vector2(45, 35), Vector2(90, 70))
	var inner := Rect2(center - Vector2(30, 20), Vector2(60, 40))
	var in_rim := 0
	var inside := 0
	var palms := 0
	var palm_a := VegetationTestSupport.species().index_of("palm_date")
	var palm_b := VegetationTestSupport.species().index_of("palm_slender")
	for i in with_plaza.count:
		var p := with_plaza.position_of(i)
		if rim.has_point(p) and not inner.has_point(p):
			in_rim += 1
			palms += 1 if with_plaza.species[i] == palm_a or with_plaza.species[i] == palm_b else 0
		if inner.has_point(p):
			inside += 1
	var rim_without := 0
	for i in without.count:
		if rim.has_point(without.position_of(i)) and not inner.has_point(without.position_of(i)):
			rim_without += 1
	assert_int(inside).is_equal(0)
	assert_int(in_rim).is_greater(rim_without + 5)
	assert_int(palms).is_greater(5)


# --- hücre indeksi ---

func test_cell_index_is_consistent_and_species_ranges_are_contiguous() -> void:
	var cols := VegetationTestSupport.light()
	assert_array(Array(cols.shape_errors())).is_empty()
	assert_float(cols.cell_m).is_equal(256.0)
	var covered := 0
	for k in cols.cell_keys.size():
		var r := cols.cell_range(cols.cell_keys[k])
		assert_int(r.y - r.x).is_greater(0)
		covered += r.y - r.x
		var per_species := 0
		for sp in cols.species_ids.size():
			var sr := cols.species_range(cols.cell_keys[k], sp)
			per_species += sr.y - sr.x
			for i in range(sr.x, sr.y):
				assert_int(cols.species[i]).is_equal(sp)
		assert_int(per_species).is_equal(r.y - r.x)
	assert_int(covered).is_equal(cols.count)
	assert_bool(cols.cell_range(-12345) == Vector2i.ZERO).is_true()
	var peak := cols.peak_cell()
	assert_int(peak.x).is_greater(0)
	var pr := cols.cell_range(peak.y)
	assert_int(pr.y - pr.x).is_equal(peak.x)


func test_negative_a_corrupted_cell_index_is_detected() -> void:
	var good := VegetationTestSupport.light()
	var bad := VegetationColumns.new()
	bad.species_ids = good.species_ids
	for i in 2000:
		bad.add(good.species[i], good.x[i], good.z[i], good.yaw[i], good.scale[i], good.layer[i])
	bad.finalize(SettlementTestSupport.light().net.world.origin, SettlementTestSupport.light().net.world.size, 256.0)
	assert_array(Array(bad.shape_errors())).is_empty()
	# Satırı başka hücreye taşı.
	var moved := bad.x[0]
	bad.x[0] = moved + 5000.0
	assert_int(bad.shape_errors().size()).is_greater(0)
	bad.x[0] = moved
	assert_array(Array(bad.shape_errors())).is_empty()
	# cell_start'ı boz.
	var start := bad.cell_start.duplicate()
	bad.cell_start[bad.cell_start.size() - 1] += 1
	assert_int(bad.shape_errors().size()).is_greater(0)
	bad.cell_start = start
	# Tür sırasını boz (hücre içi kümeleme).
	var found := false
	for k in bad.cell_keys.size():
		for i in range(bad.cell_start[k], bad.cell_start[k + 1] - 1):
			if bad.species[i] != bad.species[i + 1]:
				var t := bad.species[i]
				bad.species[i] = bad.species[i + 1]
				bad.species[i + 1] = t
				found = true
				break
		if found:
			break
	assert_bool(found).is_true()
	assert_int(bad.shape_errors().size()).is_greater(0)
	# Sütun uzunluğunu boz.
	var short := VegetationColumns.new()
	short.add(0, 1.0, 1.0, 0.0, 1.0, 0)
	short.x.resize(0)
	assert_int(short.shape_errors().size()).is_greater(0)


func test_finalize_is_stable_for_identical_input_and_orders_by_cell_then_species() -> void:
	var a := VegetationColumns.new()
	var b := VegetationColumns.new()
	for c in [a, b]:
		c.species_ids = PackedStringArray(["s0", "s1", "s2"])
		for i in 300:
			c.add((i * 7) % 3, float((i * 131) % 2000) + 0.5, float((i * 71) % 1500) + 0.5, 0.0, 1.0, i % 6)
		c.finalize(Vector2.ZERO, Vector2(2000, 1500), 256.0)
	assert_str(a.state_hash()).is_equal(b.state_hash())
	assert_array(Array(a.shape_errors())).is_empty()
	var prev := -1
	for i in a.count:
		var key := a.cell_key_of(a.x[i], a.z[i]) * 16 + a.species[i]
		assert_int(key).is_greater_equal(prev)
		prev = key
