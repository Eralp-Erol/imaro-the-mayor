extends GdUnitTestSuite
## T-062 B1 · disk önbelleği ve yükleyici: aynı girdi -> aynı sütunlar (isabet = üretim), bozuk/yanlış anahtarlı dosya
## reddedilir, arka thread görevi ana iş parçacığı beklemeden biter.

var _dir: String = ""


func before_test() -> void:
	_dir = "user://test-veg-cache-%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(_dir)


func after_test() -> void:
	for f in DirAccess.get_files_at(_dir):
		DirAccess.remove_absolute("%s/%s" % [_dir, f])
	DirAccess.remove_absolute(_dir)


func test_save_and_load_round_trip_is_identical() -> void:
	var cols := VegetationTestSupport.light()
	var path := "%s/rt.bin" % _dir
	assert_bool(VegetationCache.save(path, cols, "k1")).is_true()
	var back := VegetationCache.load_path(path, "k1")
	assert_object(back).is_not_null()
	assert_str(back.state_hash()).is_equal(cols.state_hash())
	assert_int(back.count).is_equal(cols.count)
	assert_array(Array(back.x.to_byte_array())).is_equal(Array(cols.x.to_byte_array()))
	assert_array(Array(back.cell_start.to_byte_array())).is_equal(Array(cols.cell_start.to_byte_array()))
	assert_array(Array(back.species_ids)).is_equal(Array(cols.species_ids))
	assert_array(Array(back.shape_errors())).is_empty()


func test_wrong_key_missing_corrupt_and_tampered_files_are_rejected() -> void:
	var cols := VegetationTestSupport.light()
	var path := "%s/bad.bin" % _dir
	VegetationCache.save(path, cols, "k1")
	assert_object(VegetationCache.load_path(path, "other-key")).is_null()
	assert_object(VegetationCache.load_path("%s/yok.bin" % _dir, "k1")).is_null()
	# bozuk bayt
	var f := FileAccess.open("%s/junk.bin" % _dir, FileAccess.WRITE)
	f.store_buffer(PackedByteArray([1, 2, 3, 4, 5]))
	f.close()
	assert_object(VegetationCache.load_path("%s/junk.bin" % _dir, "k1")).is_null()
	# içerik kurcalanmış (x sütunu değişti, state_hash eski): reddedilir
	var d: Dictionary = bytes_to_var(FileAccess.get_file_as_bytes(path))
	var xs: PackedFloat32Array = d["x"]
	xs[0] += 1.0
	d["x"] = xs
	var t := FileAccess.open("%s/tamper.bin" % _dir, FileAccess.WRITE)
	t.store_buffer(var_to_bytes(d))
	t.close()
	assert_object(VegetationCache.load_path("%s/tamper.bin" % _dir, "k1")).is_null()


func test_key_depends_on_every_input_part() -> void:
	var parts := {"seed": 1, "rules_sha": "a", "species_ids": ["x"], "plants_sha": "p", "world_hash": "w",
			"columns_hash": "c", "net_hash": "n", "topology_hash": "t"}
	var base := VegetationCache.key_of(parts)
	assert_str(VegetationCache.key_of(parts.duplicate(true))).is_equal(base)
	for field: String in parts:
		var changed := parts.duplicate(true)
		changed[field] = "changed" if not (parts[field] is int) else 2
		assert_str(VegetationCache.key_of(changed)).is_not_equal(base)


func test_loader_miss_then_hit_yield_the_same_columns_as_direct_generation() -> void:
	var res := SettlementTestSupport.light()
	var world := res.net.world
	var species := VegetationTestSupport.species()
	var rules := VegetationTestSupport.rules()
	var direct := VegetationPlacement.generate(res, species, rules, VegetationPlacement.default_seed(world))
	var first := VegetationLoader.start(res, species, rules, world, true, true, _dir)
	assert_int(first.state).is_equal(VegetationLoader.State.READY)
	assert_str(str(first.stats["cache"])).is_equal("miss")
	assert_str(first.columns.state_hash()).is_equal(direct.state_hash())
	var second := VegetationLoader.start(res, species, rules, world, true, true, _dir)
	assert_str(str(second.stats["cache"])).is_equal("hit")
	assert_str(second.columns.state_hash()).is_equal(direct.state_hash())
	assert_int(second.layout.y.size()).is_equal(direct.count)
	assert_array(Array(second.layout.y.to_byte_array())).is_equal(Array(first.layout.y.to_byte_array()))
	# önbellek kapalı: yine aynı çıktı
	var off := VegetationLoader.start(res, species, rules, world, true, false, _dir)
	assert_str(str(off.stats["cache"])).is_equal("off")
	assert_str(off.columns.state_hash()).is_equal(direct.state_hash())


func test_loader_background_task_completes_and_matches_the_blocking_result() -> void:
	var res := SettlementTestSupport.light()
	var world := res.net.world
	var species := VegetationTestSupport.species()
	var rules := VegetationTestSupport.rules()
	var bg := VegetationLoader.start(res, species, rules, world, false, true, _dir)
	assert_int(bg.state).is_equal(VegetationLoader.State.RUNNING)   # çağıran beklemedi
	bg.wait()
	assert_bool(bg.poll()).is_true()
	var direct := VegetationPlacement.generate(res, species, rules, VegetationPlacement.default_seed(world))
	assert_str(bg.columns.state_hash()).is_equal(direct.state_hash())


func test_loader_fails_closed_when_the_species_table_is_empty() -> void:
	var res := SettlementTestSupport.light()
	var gate := LibraryGate.new()
	gate.report_errors = false
	var empty := VegetationSpecies.from_gate(gate)
	var rules := VegetationRules.from_control(VegetationTestSupport.control(), empty)
	var loader := VegetationLoader.start(res, empty, rules, res.net.world, true, false, _dir)
	assert_int(loader.state).is_equal(VegetationLoader.State.FAILED)
	assert_object(loader.layout).is_null()
