extends GdUnitTestSuite
## T-062 B1 · `data/view/vegetation_view.json`: veri güdümlü kademe eşikleri, doğrulama ve olumsuz yollar.


func _dict() -> Dictionary:
	return (JSON.parse_string(FileAccess.get_file_as_string(VegetationViewConfig.PATH)) as Dictionary).duplicate(true)


func test_default_config_is_valid_and_carries_the_t057_working_thresholds() -> void:
	var c := VegetationViewConfig.load_default()
	assert_array(Array(c.errors)).is_empty()
	assert_float(c.lod0_end_m).is_equal(120.0)
	assert_float(c.lod1_end_m).is_equal(400.0)
	assert_bool(c.blob_enabled).is_true()
	# Yalnız LOD0 gölge düşürür (bütçe seçimi).
	assert_bool(c.shadow_lod0).is_true()
	assert_bool(c.shadow_lod1).is_false()
	assert_bool(c.shadow_proxy).is_false()


func test_every_game_species_has_a_look_entry_with_a_known_shape() -> void:
	var c := VegetationViewConfig.load_default()
	var sp := VegetationTestSupport.species()
	assert_int(sp.size()).is_equal(10)
	for key in sp.keys:
		var look := c.look_of(key)
		assert_bool(look.is_empty()).override_failure_message("species_look yok: %s" % key).is_false()
		assert_bool(c.blob_shapes.has(str(look["shape"]))).is_true()


func test_thresholds_come_from_the_file_not_from_code() -> void:
	var d := _dict()
	d["tiers"]["lod0_end_m"] = 77.0
	d["tiers"]["lod1_end_m"] = 333.0
	var c := VegetationViewConfig.from_dict(d)
	assert_array(Array(c.errors)).is_empty()
	var lod := VegetationLod.from_config(c)
	assert_float(lod.lod0_end_m).is_equal(77.0)
	assert_float(lod.lod1_end_m).is_equal(333.0)
	assert_int(lod.tier_for(76.9, false)).is_equal(VegetationLod.Tier.LOD0)
	assert_int(lod.tier_for(77.0, false)).is_equal(VegetationLod.Tier.LOD1)


func test_invalid_files_are_rejected_with_a_reason() -> void:
	var bad_order := _dict()
	bad_order["tiers"]["lod1_end_m"] = 50.0   # < lod0_end_m
	assert_bool(VegetationViewConfig.from_dict(bad_order).valid()).is_false()
	var bad_shape := _dict()
	bad_shape["species_look"]["plane"]["shape"] = "nonexistent"
	var c := VegetationViewConfig.from_dict(bad_shape)
	assert_bool(c.valid()).is_false()
	assert_bool("; ".join(c.errors).contains("plane")).is_true()
	var missing := _dict()
	missing.erase("blob")
	assert_bool(VegetationViewConfig.from_dict(missing).valid()).is_false()
	assert_bool(VegetationViewConfig.from_dict({}).valid()).is_false()
	var bad_blob := _dict()
	bad_blob["blob"]["fade_begin_m"] = 100.0   # <= lod1_end_m: leke ile ağaç kademesi çakışır
	assert_bool(VegetationViewConfig.from_dict(bad_blob).valid()).is_false()


func test_blob_clumps_stay_house_scale_after_t062_b5() -> void:
	# B-5: leke yaricapi tavani 8 m (10-14 m evlerden buyuk tumsek yok), kume ızgarasi 24 m; veri dosyasindan.
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/view/vegetation_view.json"))
	var b: Dictionary = d["blob"]
	assert_float(float(b["max_clump_radius_m"])).is_less_equal(8.0)
	assert_float(float(b["radius_mult"])).is_less_equal(1.0)
	assert_float(float(b["clump_m"])).is_less_equal(24.0)
	assert_float(float(b["min_clump_radius_m"])).is_equal(3.0)
