extends SimTestBase
## T-027 ölçüt 5 · ParcelSource soyutlaması: facade parselleri bir kaynaktan okur (T-011 `WorldNetwork` gelene dek
## WorldFixture'dan beslenen ListParcelSource); kaynak değer kopyası verir, koordinat gömülmez.


func _views() -> Array[ParcelView]:
	var out: Array[ParcelView] = []
	for spec: Array in [[5, &"R2"], [2, &"R1"], [9, &"R1"]]:
		var v := ParcelView.new()
		v.id = spec[0]
		v.region_code = spec[1]
		v.center = Vector2(float(spec[0]) * 10.0, 5.0)
		v.area_m2 = 100 + spec[0]
		v.zone = &"zone.green"
		v.land_value = 7
		out.append(v)
	return out


func test_ids_are_ascending_and_filterable_by_region() -> void:
	var src := ListParcelSource.create(&"w", _views())
	assert_bool(src.is_valid()).override_failure_message(str(src.errors)).is_true()
	assert_array(Array(src.parcel_ids())).is_equal([2, 5, 9])
	assert_array(Array(src.parcel_ids(&"R1"))).is_equal([2, 9])
	assert_array(Array(src.parcel_ids(&"nope"))).is_empty()
	assert_int(src.parcel_count()).is_equal(3)
	assert_bool(src.has_parcel(5)).is_true()
	assert_bool(src.has_parcel(6)).is_false()
	assert_str(String(src.world_id())).is_equal("w")


func test_template_returns_static_data_copy_and_null_for_unknown() -> void:
	var src := ListParcelSource.create(&"w", _views())
	var p := src.template(5)
	assert_int(p.area_m2).is_equal(105)
	assert_str(String(p.region_code)).is_equal("R2")
	assert_str(String(p.zone)).is_equal("zone.green")
	p.area_m2 = 999999
	p.zone = &"tampered"
	assert_int(src.template(5).area_m2).override_failure_message("kaynak kopya vermeli").is_equal(105)
	assert_str(String(src.template(5).zone)).is_equal("zone.green")
	assert_object(src.template(6)).is_null()


func test_constructor_input_is_copied() -> void:
	var views := _views()
	var src := ListParcelSource.create(&"w", views)
	views[0].area_m2 = 424242
	assert_int(src.template(5).area_m2).is_equal(105)


func test_invalid_inputs_are_reported_not_accepted() -> void:
	var dup := _views()
	dup[1].id = 5
	var src := ListParcelSource.create(&"w", dup)
	assert_bool(src.is_valid()).is_false()
	assert_str(" ".join(src.errors)).contains("5")
	var zero := _views()
	zero[0].id = 0
	assert_bool(ListParcelSource.create(&"w", zero).is_valid()).is_false()
	assert_bool(ListParcelSource.create(&"", _views()).is_valid()).is_false()


func test_fixture_source_lies_on_land_in_declared_regions_with_no_embedded_codes() -> void:
	var world := FacadeTestSupport.fixture_world()
	var src := FacadeTestSupport.fixture_source(3)
	assert_bool(src.is_valid()).override_failure_message(str(src.errors)).is_true()
	assert_int(src.parcel_count()).is_equal(world.regions.size() * 3)
	assert_str(String(src.world_id())).is_equal(String(world.world_id))
	for id in src.parcel_ids():
		var p := src.template(id)
		assert_bool(world.is_water(p.center.x, p.center.y)).override_failure_message("parsel %d suda" % id).is_false()
		assert_str(String(world.region_code_at(p.center.x, p.center.y))).is_equal(String(p.region_code))
	for region in world.regions:
		assert_array(Array(src.parcel_ids(region.code))).is_not_empty()
