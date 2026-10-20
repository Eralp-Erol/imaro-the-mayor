extends GdUnitTestSuite
## T-012 ölçüt 7 · Geçersiz BuildingColumns reddedilir (sessiz düzeltme yok), geçerli girdi kabul edilir.

var _kit: BuildingKit


func before() -> void:
	_kit = BuildingTestSupport.kit()


func _good() -> BuildingColumns:
	return BuildingTestSupport.grid_columns(_kit.module_index("bld_res_mid_a"), 3, 50.0, 100.0, 100.0)


func test_valid_and_empty_columns_pass() -> void:
	assert_array(BuildingInputCheck.errors(_good(), _kit.count)).is_empty()
	assert_array(BuildingInputCheck.errors(BuildingColumns.new(), _kit.count)).is_empty()


func test_null_columns_are_rejected() -> void:
	assert_array(BuildingInputCheck.errors(null, _kit.count)).is_not_empty()


func test_module_index_out_of_range_is_rejected() -> void:
	var cols := _good()
	cols.module_idx[2] = _kit.count
	assert_str(BuildingInputCheck.errors(cols, _kit.count)[0]).contains("aralık dışı")
	cols.module_idx[2] = -1
	assert_array(BuildingInputCheck.errors(cols, _kit.count)).is_not_empty()


func test_ragged_columns_are_rejected() -> void:
	var cols := _good()
	cols.x.resize(cols.count - 1)
	assert_array(BuildingInputCheck.errors(cols, _kit.count)).is_not_empty()


func test_non_finite_position_or_yaw_is_rejected() -> void:
	var cols := _good()
	cols.z[1] = NAN
	assert_array(BuildingInputCheck.errors(cols, _kit.count)).is_not_empty()
	var cols2 := _good()
	cols2.yaw[0] = INF
	assert_array(BuildingInputCheck.errors(cols2, _kit.count)).is_not_empty()


func test_palette_row_beyond_the_palette_is_rejected() -> void:
	var cols := _good()
	cols.roof_row[0] = 32
	assert_str(BuildingInputCheck.errors(cols, _kit.count)[0]).contains("palet")


func test_error_list_is_capped() -> void:
	var cols := _good()
	for i in cols.count:
		cols.module_idx[i] = 9999
	assert_int(BuildingInputCheck.errors(cols, _kit.count).size()).is_less_equal(BuildingInputCheck.MAX_ERRORS + 1)
