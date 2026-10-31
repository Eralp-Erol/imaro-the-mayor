extends GdUnitTestSuite
## T-042b adım 2 (sim) · Kamulaştırmanın ekonomi tarafı (`ParcelExpropriation`, D-011): yolun aldığı parsel BÜTÜNÜYLE
## `STAGE_TAKEN` olur (sim parsel kümesi sabit, kimlik silinmez), bina yıkılır (bölge yapılı birimi düşer), yerinden
## edilen hane SİM'in kendi hesabıdır, geri alma alınan satırın anlık görüntüsünü bit-bit geri koyar.
## Dünya yok: saf ekonomi durumu üstünde (gerçek `EconomySystem` + `ListStockSource`).

const P := preload("res://tests/sim/public_works/public_works_support.gd")
const A := &"D1"
const B := &"D2"
const FATE := &"return_to_latent"


## Bölge A: 1 (konut 10 birim), 2 (konut 6), 3 (ticaret 4); bölge B: 5 (konut 8). Diğerleri boş. Bir gün ilerletilmiş.
func _setup(patch: Dictionary = {}) -> Dictionary:
	var stock := ListStockSource.create([
		{"parcel_id": 1, "use": "residential", "units": 10, "owner": 1},
		{"parcel_id": 2, "use": "residential", "units": 6, "owner": 1},
		{"parcel_id": 3, "use": "commercial", "units": 4, "owner": 1},
		{"parcel_id": 5, "use": "residential", "units": 8, "owner": 1}])
	assert_bool(stock.is_valid()).is_true()
	var cfg := EconomyTestSupport.config(patch if not patch.is_empty() else P.economy_patch())
	var h := EconomyBootstrap.create(P.SEED, P.source(), cfg, stock)
	assert_object(h).is_not_null()
	h.facade.advance(1)
	return {"facade": h.facade, "system": h.system, "state": h.facade.game_state(), "cols": h.system.static_columns()}


func _ids(values: Array) -> PackedInt64Array:
	return PackedInt64Array(values)


func _region(state: GameState, code: StringName) -> Dictionary:
	var regions: Dictionary = EconomyState.data(state)["regions"]
	var r := (regions["codes"] as PackedStringArray).find(String(code))
	return {"latent": regions["latent_hh"][r], "res": regions["res_built"][r], "com": regions["com_built"][r],
		"res_pipe": regions["res_pipe"][r]}


# --- Önizleme (saf, durumu değiştirmez) ---

func test_plan_counts_buildings_units_households_and_regions_from_the_state() -> void:
	var run := _setup()
	var state: GameState = run["state"]
	var before := StateHash.of(EconomyState.data(state))
	var plan := ParcelExpropriation.plan(state, run["cols"], _ids([3, 1, 2]), FATE)
	assert_bool(bool(plan["ok"])).is_true()
	var s: Dictionary = plan["summary"]
	assert_array(Array(s["parcel_ids"])).is_equal([1, 2, 3])
	assert_int(int(s["built_parcels"])).is_equal(3)
	assert_int(int(s["project_parcels"])).is_equal(0)
	assert_int(int(s["res_units"])).is_equal(16)
	assert_int(int(s["com_units"])).is_equal(4)
	var region := _region(state, A)
	var expected := mini(region["latent"], region["res"]) - mini(region["latent"], region["res"] - 16)
	assert_int(int(s["households"])).is_equal(expected)
	assert_int(expected).is_greater(0)
	assert_dict(s["regions"]).is_equal({"D1": 3})
	assert_str(StateHash.of(EconomyState.data(state))).is_equal(before)  # önizleme durumu DEĞİŞTİRMEZ


func test_households_are_the_housed_drop_so_spare_units_displace_nobody() -> void:
	var run := _setup({"regions": {"overrides": {"D1": {"initial_households": 2, "infra_capacity_units": 1000}}}})
	var state: GameState = run["state"]
	var region := _region(state, A)
	# bölge: yapılı konut 16, bekleyen hane = 2 + stok*oran; çok az hane var, parsel 2 (6 birim) boşalsa kimse düşmez
	var plan := ParcelExpropriation.plan(state, run["cols"], _ids([2]), FATE)
	var s: Dictionary = plan["summary"]
	var expected := mini(region["latent"], region["res"]) - mini(region["latent"], region["res"] - 6)
	assert_int(int(s["households"])).is_equal(expected)


func test_empty_and_other_region_parcels_are_taken_whole_and_counted_by_region() -> void:
	var run := _setup()
	var plan := ParcelExpropriation.plan(run["state"], run["cols"], _ids([4, 5]), FATE)  # 4 boş (A), 5 yapılı (B)
	var s: Dictionary = plan["summary"]
	assert_int(int(s["built_parcels"])).is_equal(1)
	assert_dict(s["regions"]).is_equal({"D1": 1, "D2": 1})
	assert_int(int(s["res_units"])).is_equal(8)


func test_unknown_and_already_taken_parcels_are_flagged_not_silently_skipped() -> void:
	var run := _setup()
	var unknown := ParcelExpropriation.plan(run["state"], run["cols"], _ids([1, 999]), FATE)
	assert_int(int(unknown["unknown"])).is_equal(1)
	ParcelExpropriation.apply(run["state"], ParcelExpropriation.plan(run["state"], run["cols"], _ids([1]), FATE))
	var again := ParcelExpropriation.plan(run["state"], run["cols"], _ids([1]), FATE)
	assert_int(int(again["unknown"])).is_equal(1)  # alınmış parsel ikinci kez alınamaz


# --- Uygulama ---

func test_apply_takes_whole_parcels_removes_buildings_and_keeps_the_parcel_set() -> void:
	var run := _setup()
	var state: GameState = run["state"]
	var f: SimFacadeImpl = run["facade"]
	var count_before := f.parcel_ids().size()
	var region_before := _region(state, A)
	var plan := ParcelExpropriation.plan(state, run["cols"], _ids([1, 2, 3]), FATE)
	var snapshots := ParcelExpropriation.apply(state, plan)
	assert_int(snapshots.size()).is_equal(3)
	assert_int(f.parcel_ids().size()).is_equal(count_before)  # kimlik silinmedi
	var d := EconomyState.data(state)
	for id in [1, 2, 3]:
		var i := EconomyState.index_of(d, id)
		assert_int((d["stage"] as PackedByteArray)[i]).is_equal(EconomyState.STAGE_TAKEN)
		assert_int((d["units"] as PackedInt32Array)[i]).is_equal(0)
		assert_int((d["owner_id"] as PackedInt32Array)[i]).is_equal(0)
		assert_int((d["last_code"] as PackedByteArray)[i]).is_equal(EconomyState.CODE_NONE)
	var region_after := _region(state, A)
	assert_int(region_after["res"]).is_equal(region_before["res"] - 16)
	assert_int(region_after["com"]).is_equal(region_before["com"] - 4)
	assert_int(region_after["latent"]).is_equal(region_before["latent"])  # hane kaderi varsayılan: bölge talebine döner
	var view := f.parcel_views(_ids([1]))[0]
	assert_str(String(view.development)).is_equal("taken")
	assert_int(view.units).is_equal(0)
	assert_str(String(view.use)).is_equal("")


func test_leave_region_fate_removes_the_displaced_households_from_the_region() -> void:
	var run := _setup()
	var state: GameState = run["state"]
	var region_before := _region(state, A)
	var plan := ParcelExpropriation.plan(state, run["cols"], _ids([1, 2]), &"leave_region")
	var displaced := int(plan["summary"]["households"])
	assert_int(displaced).is_greater(0)
	ParcelExpropriation.apply(state, plan)
	assert_int(_region(state, A)["latent"]).is_equal(region_before["latent"] - displaced)


func _make_project(state: GameState, parcel_id: int, stage_value: int, use_value: int, units: int, days: int) -> void:
	var d := EconomyState.data(state)
	var i := EconomyState.index_of(d, parcel_id)
	var stage: PackedByteArray = d["stage"]
	var use_col: PackedByteArray = d["use"]
	var units_col: PackedInt32Array = d["units"]
	var owner_col: PackedInt32Array = d["owner_id"]
	var days_col: PackedInt32Array = d["days_left"]
	var pipe: PackedInt64Array = (d["regions"] as Dictionary)["res_pipe" if use_value == EconomyConfig.USE_RESIDENTIAL
		else "com_pipe"]
	stage[i] = stage_value
	use_col[i] = use_value
	units_col[i] = units
	owner_col[i] = 1
	days_col[i] = days
	pipe[0] += units  # bölge A = indeks 0 (kodlar sıralı: D1, D2)
	(d["active"] as Dictionary)[i] = true


func test_project_parcels_are_cancelled_and_leave_the_pipeline() -> void:
	var run := _setup()
	var state: GameState = run["state"]
	var d := EconomyState.data(state)
	_make_project(state, 4, EconomyState.STAGE_UNDER_CONSTRUCTION, EconomyConfig.USE_RESIDENTIAL, 7, 20)
	var i := EconomyState.index_of(d, 4)
	var pipe_before: int = _region(state, A)["res_pipe"]
	var plan := ParcelExpropriation.plan(state, run["cols"], _ids([4]), FATE)
	var s: Dictionary = plan["summary"]
	assert_int(int(s["project_parcels"])).is_equal(1)
	assert_int(int(s["built_parcels"])).is_equal(0)
	assert_int(int(s["households"])).is_equal(0)  # proje henüz hane barındırmıyordu
	ParcelExpropriation.apply(state, plan)
	assert_int(_region(state, A)["res_pipe"]).is_equal(pipe_before - 7)
	assert_bool((d["active"] as Dictionary).has(i)).is_false()


# --- Geri alma: anlık görüntü bit-bit geri gelir ---

func test_restore_returns_the_exact_economy_state_when_nothing_else_changed() -> void:
	var run := _setup()
	var state: GameState = run["state"]
	var d := EconomyState.data(state)
	_make_project(state, 4, EconomyState.STAGE_PLANNED, EconomyConfig.USE_COMMERCIAL, 5, 9)  # proje + yapılı birlikte
	var i := EconomyState.index_of(d, 4)
	var last_code: PackedByteArray = d["last_code"]
	var last_tick: PackedInt32Array = d["last_reason_tick"]
	last_code[i] = EconomyState.CODE_APPROVED
	last_tick[i] = 1
	var before := StateHash.of(d)
	var plan := ParcelExpropriation.plan(state, run["cols"], _ids([1, 3, 4]), FATE)
	var snapshots := ParcelExpropriation.apply(state, plan)
	assert_str(StateHash.of(d)).is_not_equal(before)
	ParcelExpropriation.restore(state, {"snapshots": snapshots, "latent_removed": plan["latent_removed"]})
	assert_str(StateHash.of(d)).is_equal(before)


func test_restore_after_leave_region_gives_the_households_back() -> void:
	var run := _setup()
	var state: GameState = run["state"]
	var before := StateHash.of(EconomyState.data(state))
	var plan := ParcelExpropriation.plan(state, run["cols"], _ids([1, 2, 3]), &"leave_region")
	var snapshots := ParcelExpropriation.apply(state, plan)
	ParcelExpropriation.restore(state, {"snapshots": snapshots, "latent_removed": plan["latent_removed"]})
	assert_str(StateHash.of(EconomyState.data(state))).is_equal(before)


# --- Yakınlık (yolun yakınındaki, alınmayan sakinler) ---

func test_nearby_households_weigh_by_distance_and_skip_taken_and_far_parcels() -> void:
	var run := _setup()
	var state: GameState = run["state"]
	# Parsel merkezleri (support): A: x = 300 + 100k m (k = 0..3), z = 300 m. Yol x = 300 m'den 100 m kuzeye uzanır.
	# Parsel 4'ü (x = 600 m) konutlu yap: yoldan 300 m uzakta. Parsel 3 ticaret (sayılmaz).
	var d := EconomyState.data(state)
	var stage: PackedByteArray = d["stage"]
	var use_col: PackedByteArray = d["use"]
	var units_col: PackedInt32Array = d["units"]
	var res_built: PackedInt64Array = (d["regions"] as Dictionary)["res_built"]
	var i4 := EconomyState.index_of(d, 4)
	stage[i4] = EconomyState.STAGE_BUILT
	use_col[i4] = EconomyConfig.USE_RESIDENTIAL
	units_col[i4] = 5
	res_built[0] += 5
	var pts: Array = [[30000, 30000], [30000, 20000]]
	var taken := _ids([1])
	var near := ParcelExpropriation.nearby(state, run["cols"], taken, pts, 150)
	assert_bool(near["by_region"].has("D1")).is_true()
	assert_bool(near["by_region"].has("D2")).is_false()  # 1800 m uzakta
	assert_int(int(near["parcels"])).is_equal(1)  # yalnız parsel 2 (d = 100 m); 1 alındı; 3 ticaret; 4 yarıçap dışı
	var wide := ParcelExpropriation.nearby(state, run["cols"], taken, pts, 350)
	assert_int(int(wide["parcels"])).is_equal(2)  # parsel 4 de (d = 300 m) girer
	assert_int(int(wide["households"])).is_greater(int(near["households"]))
	# ağırlıklı toplam (hane x ağırlık_pm), ham toplamın 1000 katından büyük olamaz; uzak parsel az ağırlık taşır
	var weighted_near: int = near["by_region"]["D1"]
	assert_int(weighted_near).is_less_equal(int(near["households"]) * 1000)
	assert_int(weighted_near).is_greater(0)
	var all_taken := ParcelExpropriation.nearby(state, run["cols"], _ids([1, 2, 4]), pts, 350)
	assert_int(int(all_taken["parcels"])).is_equal(0)  # alınan parseller yakınlık sayılmaz
