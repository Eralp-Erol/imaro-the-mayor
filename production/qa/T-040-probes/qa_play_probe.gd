extends SceneTree
## QA T-040 (d): gerçek playable.tscn'de T0 görünümünün hücre yeniden kurulumu ve sim görünümünün hücre-yerel
## güncellemesi; sonunda projector satırları tam taramayla karşılaştırılır. Oyun argümanları -- sonrası; qa-frames=N.

const QW := preload("qa_world.gd")


func _initialize() -> void:
	var frames := 900
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--qa-frames="):
			frames = int(a.split("=")[1])
	var scene: Node = load("res://scenes/game/playable.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var t0_view: BuildingView = scene.get("_buildings")
	var sim_view: BuildingView = scene.get("_sim_buildings")
	var t0_rebuilds := [0, 0]
	var sim_rebuilds := [0, 0, 0]
	t0_view.cells_rebuilt.connect(func(keys: Array) -> void:
		t0_rebuilds[0] += 1
		t0_rebuilds[1] += keys.size())
	sim_view.cells_rebuilt.connect(func(keys: Array) -> void:
		sim_rebuilds[0] += 1
		sim_rebuilds[1] += keys.size()
		sim_rebuilds[2] = maxi(sim_rebuilds[2], keys.size()))
	var f: SimFacade = scene.get("_facade")
	var start_tick := f.current_tick()
	var t := Time.get_ticks_msec()
	for i in frames:
		await process_frame
	var proj: SimBuildingProjector = scene.get("_projector")
	print("QA_PLAY frames=%d ticks=%d->%d wall_ms=%d t0_view_rebuild_signals=%d t0_cells=%d sim_view_rebuilds=%d sim_cells_total=%d sim_cells_max_per_rebuild=%d t0_total_cells=%d sim_rows=%d" % [
			frames, start_tick, f.current_tick(), Time.get_ticks_msec() - t, t0_rebuilds[0], t0_rebuilds[1],
			sim_rebuilds[0], sim_rebuilds[1], sim_rebuilds[2], int(t0_view.stats.get("cells", -1)),
			proj.columns().count])
	# Projector'ın sahnedeki durumu vs tam tarama (sim ilerlemeden, şu an)
	var settlement: SettlementResult = scene.get("_settlement")
	var t0occ := {}
	for pid in settlement.columns.occupied_parcels():
		t0occ[int(pid)] = true
	var truth := {}
	var t0_by_sim := 0
	var ids := f.parcel_ids()
	var i := 0
	while i < ids.size():
		var chunk := ids.slice(i, mini(i + 500, ids.size()))
		i += chunk.size()
		for v in f.parcel_views(chunk):
			if t0occ.has(v.id) and v.developed_by_sim:
				t0_by_sim += 1
			if v.developed_by_sim and v.units > 0 and v.development in [ParcelView.DEVELOPMENT_UNDER_CONSTRUCTION,
					ParcelView.DEVELOPMENT_BUILT, ParcelView.DEVELOPMENT_STALLED] \
					and proj.placer().plan(v.id, v.use, v.units) != null:
				truth[v.id] = true
	var shown := {}
	for pid in proj.parcel_ids():
		shown[int(pid)] = true
	var missing := 0
	for pid in truth:
		if not shown.has(pid):
			missing += 1
	var extra := 0
	for pid in shown:
		if not truth.has(pid):
			extra += 1
	print("QA_PLAY truth=%d shown=%d missing=%d extra=%d t0_by_sim=%d backlog=%d unresolved=%d unplaced=%d view_rows=%d" % [
			truth.size(), shown.size(), missing, extra, t0_by_sim, proj.backlog_ticks(),
			int(proj.stats["unresolved_missing"]), proj.unplaced().size(), int(sim_view.stats.get("buildings", -1))])
	quit(0)
