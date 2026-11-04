class_name EconomyStockColumns
extends RefCounted
## T0 mevcut stoğun ekonomi sütunları (T-050; ilk tick maliyeti). `EconomySystem._apply_stock` bu hesabı ilk tick'te
## ~24 000 stoklu parsel için parsel başına bsearch + stok çağrılarıyla yapıyordu (~107 ms, gerçek Ismeral); stok
## STATİKTİR (ExistingStockSource sözleşmesi), bu yüzden sütunlar kurulumda (tick dışında) bir kez türetilir, ilk tick
## yalnız kopyalar. Değerler eski döngüyle BİREBİR aynıdır. Saf: RefCounted, durum tutmaz, rastgelelik/zaman yok.


## Dönüş: {stage, use, units, owner (parsel indeksli), res_built, com_built (bölge indeksli, PackedInt64Array)}.
@warning_ignore("integer_division")
static func build(ids: PackedInt64Array, region_of: PackedInt32Array, region_count: int,
		stock: ExistingStockSource) -> Dictionary:
	var n := ids.size()
	var stage := PackedByteArray()
	stage.resize(n)
	var use_col := PackedByteArray()
	use_col.resize(n)
	var units_col := PackedInt32Array()
	units_col.resize(n)
	var owner_col := PackedInt32Array()
	owner_col.resize(n)
	var res_built := PackedInt64Array()
	res_built.resize(region_count)
	var com_built := PackedInt64Array()
	com_built.resize(region_count)
	for id in stock.parcel_ids():
		var i := ids.bsearch(id)
		if not (i < n and ids[i] == id):
			i = -1  # EconomyState.index_of ile aynı (stok kimlikleri parsel kümesindedir; setup_problem denetler)
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
