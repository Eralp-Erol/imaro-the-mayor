extends SimTestBase
## T-050 · `EconomyStockColumns` (kurulumda türetilen T0 stok sütunları) eski `_apply_stock` döngüsüyle BİREBİR aynı:
## parsel indeksli sütunlar ve bölge başına konut/ticaret toplamları. Olumsuz kontrol: stoksuz parsel `vacant` kalır.


## Eski döngü (EconomySystem._apply_stock'un T-049 öncesi hâli) referans olarak.
func _reference(ids: PackedInt64Array, region_of: PackedInt32Array, regions: int,
		stock: ExistingStockSource) -> Dictionary:
	var d := {"parcel_ids": ids}
	var stage := PackedByteArray()
	stage.resize(ids.size())
	var use_col := PackedByteArray()
	use_col.resize(ids.size())
	var units_col := PackedInt32Array()
	units_col.resize(ids.size())
	var owner_col := PackedInt32Array()
	owner_col.resize(ids.size())
	var res_built := PackedInt64Array()
	res_built.resize(regions)
	var com_built := PackedInt64Array()
	com_built.resize(regions)
	for id in stock.parcel_ids():
		var i := EconomyState.index_of(d, id)
		var use := EconomyState.use_id(stock.use_of(id))
		var units := stock.units_of(id)
		stage[i] = EconomyState.STAGE_BUILT
		use_col[i] = use
		units_col[i] = units
		owner_col[i] = stock.owner_of(id)
		if use == EconomyConfig.USE_RESIDENTIAL:
			res_built[region_of[i]] += units
		else:
			com_built[region_of[i]] += units
	return {"stage": stage, "use": use_col, "units": units_col, "owner": owner_col, "res_built": res_built,
			"com_built": com_built}


func test_columns_equal_the_old_apply_stock_loop_on_a_random_stock() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 91
	var ids := PackedInt64Array()
	var region_of := PackedInt32Array()
	var entries: Array = []
	for k in 500:
		var pid := 10 + k * 3
		ids.append(pid)
		region_of.append(rng.randi_range(0, 3))
		if rng.randi_range(0, 2) > 0:
			entries.append({"parcel_id": pid, "use": &"commercial" if rng.randi_range(0, 3) == 0 else &"residential",
					"units": rng.randi_range(1, 40), "owner": rng.randi_range(0, 3)})
	var stock := ListStockSource.create(entries)
	assert_bool(stock.is_valid()).is_true()
	var got := EconomyStockColumns.build(ids, region_of, 4, stock)
	var want := _reference(ids, region_of, 4, stock)
	for key: String in want:
		assert_bool(got[key] == want[key]).override_failure_message("sütun " + key).is_true()
	assert_int((got["stage"] as PackedByteArray).count(EconomyState.STAGE_BUILT)).is_equal(entries.size())
	assert_int((got["res_built"] as PackedInt64Array)[0] + (got["res_built"] as PackedInt64Array)[1]
			+ (got["res_built"] as PackedInt64Array)[2] + (got["res_built"] as PackedInt64Array)[3]).is_greater(0)


func test_empty_stock_leaves_every_parcel_vacant() -> void:
	var ids := PackedInt64Array([5, 6, 7])
	var got := EconomyStockColumns.build(ids, PackedInt32Array([0, 0, 1]), 2, EmptyStockSource.new())
	assert_int((got["stage"] as PackedByteArray).count(EconomyState.STAGE_BUILT)).is_equal(0)
	assert_int((got["res_built"] as PackedInt64Array)[0]).is_equal(0)
	assert_int((got["com_built"] as PackedInt64Array)[1]).is_equal(0)
