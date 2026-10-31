extends SceneTree
## T-042b ölçüm probu (SİM tarafı): kamulaştırmalı yolun tick maliyeti ve önizleme maliyeti. Dünya köprüsü TEST İKİZİdir
## (gerçek ağ, enjekte alınan küme): `add_road` ve graf özeti maliyeti dünya hattının işidir ve her iki yolda da vardır;
## burada ölçülen FARK = sim'in kamulaştırma eki (plan + yakınlık + uygulama + gerekçe + olay). Duvar saati yalnız
## ölçüm içindir (kabul kararı değildir, makineye bağlıdır).
## Çalıştır: godot --headless --path . --script res://tests/sim/perf/t042b_expropriation_probe.gd

const P := preload("res://tests/sim/public_works/public_works_support.gd")
const COLS_N := 200
const ROWS_N := 100
const SPACING_M := 15.0
const TAKE_WITHIN_M := 8.0
const REPEATS := 5


func _init() -> void:
	var views: Array[ParcelView] = []
	var stock_rows: Array = []
	var diagonal := PackedInt64Array([110000, 110000, 126000, 120000])
	var taken: Array = []
	var next_id := 1
	for j in ROWS_N:
		for i in COLS_N:
			var v := ParcelView.new()
			v.id = next_id
			v.center = Vector2(10.0 + i * SPACING_M, 10.0 + j * SPACING_M)
			v.region_code = P.CODE_A if v.center.x < P.SPLIT_X else P.CODE_B
			v.area_m2 = P.AREA_M2
			v.zone = P.ZONE
			v.land_value = 1000
			views.append(v)
			if next_id % 3 != 0:
				stock_rows.append({"parcel_id": next_id, "use": "residential", "units": 6, "owner": 1})
			var d2 := PriorityReview.dist2_to_polyline(int(v.center.x * 100.0), int(v.center.y * 100.0),
				[[110000, 110000], [126000, 120000]])
			if d2 <= TAKE_WITHIN_M * TAKE_WITHIN_M * 10000.0:
				taken.append(next_id)
			next_id += 1
	var results := {"task": "T-042b", "parcels": views.size(), "taken": taken.size(), "runs": []}
	for rep in REPEATS:
		results["runs"].append(_run(views, stock_rows, diagonal, taken))
	print(JSON.stringify(results, "  "))
	quit()


func _run(views: Array[ParcelView], stock_rows: Array, diagonal: PackedInt64Array, taken: Array) -> Dictionary:
	var net := P.network()
	var source := ListParcelSource.create(&"t042b.probe", views)
	var stock := ListStockSource.create(stock_rows)
	var cfg := EconomyTestSupport.config(P.economy_patch())
	var h := EconomyBootstrap.create(P.SEED, source, cfg, stock)
	var ctx := PublicWorksContext.create(net, RoadDraftRules.new(), PublicWorksConfig.load_default())
	var fake := FakeExpropriationWorld.new(net)
	fake.take(diagonal, taken)
	ctx.set_expropriation(fake)
	h.facade.attach_public_works(ctx)
	h.facade.advance(2)
	var f := h.facade
	var out := {}
	var cols: Dictionary = h.system.static_columns()
	var t0 := Time.get_ticks_usec()
	var plan := ParcelExpropriation.plan(f.game_state(), cols, PackedInt64Array(taken), &"return_to_latent")
	out["plan_ms"] = float(Time.get_ticks_usec() - t0) / 1000.0
	t0 = Time.get_ticks_usec()
	var near := ParcelExpropriation.nearby(f.game_state(), cols, PackedInt64Array(taken),
		[[110000, 110000], [126000, 120000]], 60)
	out["nearby_ms"] = float(Time.get_ticks_usec() - t0) / 1000.0
	out["nearby_parcels"] = near["parcels"]
	out["plan_ok"] = plan["ok"]
	t0 = Time.get_ticks_usec()
	var preview := f.validate_command(SimCommand.public_work_road(diagonal, &"local", true))
	out["preview_ms"] = float(Time.get_ticks_usec() - t0) / 1000.0
	out["preview_status"] = String(preview.status)
	f.submit_command(SimCommand.public_work_road(P.spur_a_cm(), &"local", false))
	t0 = Time.get_ticks_usec()
	f.advance(1)
	out["plain_road_tick_ms"] = float(Time.get_ticks_usec() - t0) / 1000.0
	f.submit_command(SimCommand.public_work_undo_last())
	f.advance(1)
	f.submit_command(SimCommand.public_work_road(diagonal, &"local", true))
	t0 = Time.get_ticks_usec()
	f.advance(1)
	out["expropriating_road_tick_ms"] = float(Time.get_ticks_usec() - t0) / 1000.0
	out["taken_views"] = f.public_works()[0].taken_parcel_ids.size() if not f.public_works().is_empty() else -1
	f.submit_command(SimCommand.public_work_undo_last())
	t0 = Time.get_ticks_usec()
	f.advance(1)
	out["undo_expropriation_tick_ms"] = float(Time.get_ticks_usec() - t0) / 1000.0
	t0 = Time.get_ticks_usec()
	f.advance(1)
	out["next_plain_tick_ms"] = float(Time.get_ticks_usec() - t0) / 1000.0
	return out
