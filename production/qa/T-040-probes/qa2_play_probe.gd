extends SceneTree
## QA T-040 2. tur (B-002, gerçek playable.tscn): her yeni sim gününde kâhin (ekonomi durum sütunları, feed'den bağımsız)
## ile projector'ın gösterdiği parseller karşılaştırılır: çizilme gecikmesi (gün), koşu sonu tam tarama <-> çizili,
## hiç çizilmeyen. Kâhin her yeni günde ekonomi 'active' kümesini okur (kare bütçesini bozmamak için ucuz). Oyun argümanları -- sonrası; --qa-frames=N. `--fixed-fps 60` ile 60 fps kare akışı benzetilir.

const QW := preload("qa_world.gd")


func _initialize() -> void:
	var frames := 1500
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--qa-frames="):
			frames = int(a.split("=")[1])
	var scene: Node = load("res://scenes/game/playable.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	var t0_view: BuildingView = scene.get("_buildings")
	var sim_view: BuildingView = scene.get("_sim_buildings")
	var t0_rebuilds := [0]
	var sim_rebuilds := [0, 0]
	t0_view.cells_rebuilt.connect(func(_keys: Array) -> void: t0_rebuilds[0] += 1)
	sim_view.cells_rebuilt.connect(func(keys: Array) -> void:
		sim_rebuilds[0] += 1
		sim_rebuilds[1] = maxi(sim_rebuilds[1], keys.size()))
	var f: SimFacade = scene.get("_facade")
	var impl := f as SimFacadeImpl
	var proj: SimBuildingProjector = scene.get("_projector")
	var settlement: SettlementResult = scene.get("_settlement")
	var t0 := {}
	for pid in settlement.columns.occupied_parcels():
		t0[int(pid)] = true
	var start_tick := f.current_tick()
	var first_truth := {}
	var first_shown := {}
	var unplaceable := {}
	var last_tick := -1
	var day_frames := {}
	var full_frames := 0
	var t := Time.get_ticks_msec()
	for i in frames:
		await process_frame
		var tick := f.current_tick()
		day_frames[tick] = int(day_frames.get(tick, 0)) + 1
		if proj.full_sync_active():
			full_frames += 1
		if tick == last_tick:
			continue
		last_tick = tick
		var d := EconomyState.data(impl.game_state())
		if d.is_empty():
			continue
		var ids: PackedInt64Array = d["parcel_ids"]
		var stage: PackedByteArray = d["stage"]
		var code: PackedByteArray = d["last_code"]
		var units: PackedInt32Array = d["units"]
		var use: PackedByteArray = d["use"]
		# Ucuz kâhin: yalnız ekonominin 'active' kümesi (onaydan tamamlanmaya kadar; inşaat >30 gün sürer, kaçırılmaz).
		for kk in (d["active"] as Dictionary).keys():
			var k := int(kk)
			var pid := int(ids[k])
			if first_truth.has(pid) or unplaceable.has(pid) or t0.has(pid):
				continue
			var s := stage[k]
			if code[k] != EconomyState.CODE_APPROVED or units[k] <= 0 or use[k] == EconomyConfig.USE_NONE:
				continue
			if s != EconomyState.STAGE_UNDER_CONSTRUCTION and s != EconomyState.STAGE_BUILT and s != EconomyState.STAGE_STALLED:
				continue
			if proj.placer().plan(pid, EconomyState.use_name(use[k]), units[k]) == null:
				unplaceable[pid] = true
				continue
			first_truth[pid] = tick
		for pid in proj.parcel_ids():
			if not first_shown.has(int(pid)):
				first_shown[int(pid)] = tick
	var end_tick := f.current_tick()
	var lags := []
	var never := []
	for pid: int in first_truth:
		if first_shown.has(pid):
			lags.append(maxi(0, int(first_shown[pid]) - int(first_truth[pid])))
		else:
			never.append([pid, first_truth[pid]])
	lags.sort()
	var fpd := []
	for k: int in day_frames:
		fpd.append(int(day_frames[k]))
	fpd.sort()
	var shown := {}
	for pid in proj.parcel_ids():
		shown[int(pid)] = true
	var missing := 0
	for pid: int in first_truth:
		if not shown.has(pid):
			missing += 1
	var extra := 0
	for pid: int in shown:
		if not first_truth.has(pid):
			extra += 1
	print("QA2_PLAY frames=%d ticks=%d->%d wall_ms=%d frames_per_day p50=%s min=%s max=%s full_sync_frames=%d full_syncs=%d" % [
			frames, start_tick, end_tick, Time.get_ticks_msec() - t, _q(fpd, 0.5), _q(fpd, 0.0), _q(fpd, 1.0), full_frames,
			int(proj.stats["full_syncs"])])
	print("QA2_PLAY t0_view_rebuild_signals=%d sim_view_rebuilds=%d sim_cells_max_per_rebuild=%d" % [t0_rebuilds[0],
			sim_rebuilds[0], sim_rebuilds[1]])
	print("QA2_PLAY lag_days n=%d p50=%s p95=%s max=%s never=%d never_sample=%s" % [lags.size(), _q(lags, 0.5), _q(lags, 0.95),
			_q(lags, 1.0), never.size(), str(never.slice(0, 8))])
	print("QA2_PLAY end truth=%d shown=%d missing=%d extra=%d backlog=%d unplaced=%d reasons=%s truth_unplaceable=%d" % [
			first_truth.size(), shown.size(), missing, extra, proj.backlog_ticks(), proj.unplaced_count(),
			proj.unplaced_reason_counts(), unplaceable.size()])
	quit(0)


func _q(arr: Array, q: float) -> String:
	if arr.is_empty():
		return "-"
	return str(arr[mini(int(arr.size() * q), arr.size() - 1)])
