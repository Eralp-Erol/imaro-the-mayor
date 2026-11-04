extends GdUnitTestSuite
## T-005 · BuildingColumns (T-012 ile ORTAK ARAYÜZ SÖZLEŞMESİ): sütun adları/türleri/bayrak bitleri kilitli.
## Sözleşme değişirse bu test kırmızı olur (koordinatör onayı gerekir).


func _filled(n: int) -> BuildingColumns:
	var cols := BuildingColumns.new()
	for i in n:
		cols.add(i + 1, i % 5, 10.0 * i, -3.5 * i, 0.25 * i, 2 + i % 4, i % 13, 13 + i % 5, 22 + i % 3, (i * 37) % 256,
				BuildingColumns.FLAG_GROUND_SHOP if i % 2 == 0 else 0, i % 3)
	return cols


func test_contract_column_types_are_exactly_the_agreed_ones() -> void:
	var cols := BuildingColumns.new()
	assert_int(cols.count).is_equal(0)
	assert_int(typeof(cols.parcel_id)).is_equal(TYPE_PACKED_INT32_ARRAY)
	assert_int(typeof(cols.module_idx)).is_equal(TYPE_PACKED_INT32_ARRAY)
	assert_int(typeof(cols.x)).is_equal(TYPE_PACKED_FLOAT32_ARRAY)
	assert_int(typeof(cols.z)).is_equal(TYPE_PACKED_FLOAT32_ARRAY)
	assert_int(typeof(cols.yaw)).is_equal(TYPE_PACKED_FLOAT32_ARRAY)
	for name in ["floors", "wall_row", "roof_row", "accent_row", "bright", "flags", "era"]:
		assert_int(typeof(cols.get(name))).override_failure_message(name).is_equal(TYPE_PACKED_BYTE_ARRAY)


func test_add_keeps_all_columns_the_same_length_and_count_in_sync() -> void:
	var cols := _filled(7)
	assert_int(cols.count).is_equal(7)
	assert_int(cols.parcel_id.size()).is_equal(7)
	assert_int(cols.yaw.size()).is_equal(7)
	assert_int(cols.era.size()).is_equal(7)
	assert_array(cols.shape_errors()).is_empty()
	assert_int(cols.parcel_id[3]).is_equal(4)
	assert_float(cols.x[3]).is_equal_approx(30.0, 0.001)
	assert_int(cols.flags[2]).is_equal(BuildingColumns.FLAG_GROUND_SHOP)


func test_flag_bits_are_the_documented_values() -> void:
	assert_int(BuildingColumns.FLAG_GROUND_SHOP).is_equal(1)
	assert_int(BuildingColumns.FLAG_HERITAGE).is_equal(2)
	assert_int(BuildingColumns.FLAG_LANDMARK).is_equal(4)
	assert_int(BuildingColumns.FLAG_INDUSTRY).is_equal(8)
	assert_int(BuildingColumns.FLAG_CIVIC).is_equal(16)
	assert_int(BuildingColumns.FLAG_PORT_YARD).is_equal(32)
	assert_int(BuildingColumns.ERA_OLD).is_equal(0)
	assert_int(BuildingColumns.ERA_MID).is_equal(1)
	assert_int(BuildingColumns.ERA_LATE).is_equal(2)
	assert_int(BuildingColumns.ERA_NEW).is_equal(3)


func test_state_hash_is_stable_and_every_column_matters() -> void:
	var a := _filled(20)
	var b := _filled(20)
	assert_str(a.state_hash()).is_equal(b.state_hash())
	assert_str(a.state_hash()).has_length(64)
	var mutations: Array[Callable] = [
		func(c: BuildingColumns) -> void: c.parcel_id[5] += 1,
		func(c: BuildingColumns) -> void: c.module_idx[5] += 1,
		func(c: BuildingColumns) -> void: c.x[5] += 0.5,
		func(c: BuildingColumns) -> void: c.z[5] += 0.5,
		func(c: BuildingColumns) -> void: c.yaw[5] += 0.1,
		func(c: BuildingColumns) -> void: c.floors[5] += 1,
		func(c: BuildingColumns) -> void: c.wall_row[5] += 1,
		func(c: BuildingColumns) -> void: c.roof_row[5] += 1,
		func(c: BuildingColumns) -> void: c.accent_row[5] += 1,
		func(c: BuildingColumns) -> void: c.bright[5] += 1,
		func(c: BuildingColumns) -> void: c.flags[5] ^= 2,
		func(c: BuildingColumns) -> void: c.era[5] += 1,
	]
	for i in mutations.size():
		var m := _filled(20)
		mutations[i].call(m)
		assert_str(m.state_hash()).override_failure_message("sütun mutasyonu %d hash'i değiştirmedi" % i) \
				.is_not_equal(a.state_hash())


func test_topology_hash_ignores_detail_but_not_occupancy() -> void:
	var a := _filled(20)
	var b := _filled(20)
	b.wall_row[3] += 1
	b.x[4] += 1.0
	b.module_idx[6] += 1
	assert_str(a.topology_hash()).is_equal(b.topology_hash())
	assert_str(a.detail_hash()).is_not_equal(b.detail_hash())
	var c := _filled(20)
	c.parcel_id[3] = 999
	assert_str(a.topology_hash()).is_not_equal(c.topology_hash())


func test_shape_errors_catch_a_ragged_column() -> void:
	var cols := _filled(5)
	cols.wall_row.append(3)
	assert_bool(cols.shape_errors().is_empty()).is_false()


func test_bright_factor_maps_byte_to_a_six_percent_band() -> void:
	var cols := BuildingColumns.new()
	cols.add(1, 0, 0.0, 0.0, 0.0, 3, 0, 13, 22, 0, 0, 1)
	cols.add(1, 0, 0.0, 0.0, 0.0, 3, 0, 13, 22, 255, 0, 1)
	assert_float(cols.bright_factor(0)).is_equal_approx(0.94, 0.0005)
	assert_float(cols.bright_factor(1)).is_equal_approx(1.06, 0.0005)
