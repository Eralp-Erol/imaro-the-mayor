extends SceneTree
## Yol çizimi maliyet ölçümü (T-042 kullanıcı denemesi: araç açıkken kare süresi 28 -> 69 ms, yol onayında 1,3 sn).
## Başsız: tools/godot.sh --headless --path . --script res://tools/godot/road_ux_probe.gd -- [--n=200]
## Ölçer (ms, ana iş parçacığı, GERÇEK Ismeral dünyası, tohum = world.json default_seed):
##  (1) RoadDraftCheck.check (imleç önizlemesinin sim kuru koşusunun çekirdeği),
##  (2) yol onayı: add_road (tick içinde), RoadEditSync.begin_async (ana iş parçacığı kısmı), arka plan işi (bekleme),
##      poll/install (ana iş parçacığı kısmı) -> PLAYABLE_ROADS'taki `ms` BU ÜÇÜNÜN DUVAR toplamıdır, ana iş parçacığı yükü değil,
##  (3) panel: imleç hareketi başına RoadDrawPanel yeniden çizimi (sentetik dünya; gerçek sim facade'i).
## Render/FPS ölçmez. Üretim kodu değildir.

const DATA_DIR := "res://data/world/ismeral"
const P := preload("res://tests/sim/public_works/public_works_support.gd")

var _n := 200


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--n="):
			_n = int(arg.trim_prefix("--n="))
	var control := WorldControlData.load_dir(DATA_DIR)
	var world_seed := int(control["world"]["default_seed"])
	var world := WorldGenerator.generate(control, world_seed, {})
	var net_control: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("%s/network.json" % DATA_DIR))
	var net := NetworkGenerator.generate(world, net_control, world_seed)
	var rules := RoadDraftRules.from_control(net_control)
	rules.jurisdiction_regions = []
	print("ROAD_UX seed=%d counts=%s" % [world_seed, str(net.counts())])
	var drafts := _drafts(net, world_seed, _n)
	_probe_check(net, rules, drafts)
	await _probe_commit(net, rules, drafts)
	await _probe_panel()
	quit(0)


func _drafts(net: WorldNetwork, world_seed: int, count: int) -> Array[PackedVector2Array]:
	var rng := RandomNumberGenerator.new()
	rng.seed = NetworkRules.stream_seed(world_seed, "road_ux_probe")
	var ids: Array = net.edges.keys()
	ids.sort()
	var out: Array[PackedVector2Array] = []
	while out.size() < count:
		var e: WorldRoadEdge = net.edges[ids[rng.randi() % ids.size()]]
		var a := net.node_pos(e.a).lerp(net.node_pos(e.b), rng.randf())
		var b := a + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(40.0, 300.0)
		out.append(PackedVector2Array([a, b]))
	return out


func _stats(values: Array[float]) -> String:
	if values.is_empty():
		return "n=0"
	var v := values.duplicate()
	v.sort()
	var sum := 0.0
	for x in v:
		sum += x
	return "n=%d ort=%.2f ms ortanca=%.2f p95=%.2f en çok=%.2f" % [v.size(), sum / v.size(), v[v.size() / 2],
			v[int(v.size() * 0.95)], v[v.size() - 1]]


func _probe_check(net: WorldNetwork, rules: RoadDraftRules, drafts: Array[PackedVector2Array]) -> void:
	var all_ms: Array[float] = []
	var ok_ms: Array[float] = []
	var rej_ms: Array[float] = []
	for pts in drafts:
		var t0 := Time.get_ticks_usec()
		var res := RoadDraftCheck.check(net, pts, WorldRoadEdge.CLASS_LOCAL, rules)
		var dt := (Time.get_ticks_usec() - t0) / 1000.0
		all_ms.append(dt)
		(ok_ms if bool(res["ok"]) else rej_ms).append(dt)
	print("ROAD_UX_CHECK tümü: %s" % _stats(all_ms))
	print("ROAD_UX_CHECK geçerli: %s" % _stats(ok_ms))
	print("ROAD_UX_CHECK reddedilen: %s" % _stats(rej_ms))


func _probe_commit(net: WorldNetwork, rules: RoadDraftRules, drafts: Array[PackedVector2Array]) -> void:
	var holder := Node3D.new()
	root.add_child(holder)
	var view := RoadView.new()
	holder.add_child(view)
	var style := RoadStyle.load_default()
	var t0 := Time.get_ticks_usec()
	view.build(net, style)
	print("ROAD_UX_VIEW ilk tam kurulum (RoadView.build) %.1f ms" % [(Time.get_ticks_usec() - t0) / 1000.0])
	var sync := RoadEditSync.create(net, view)
	var add_ms: Array[float] = []
	var begin_ms: Array[float] = []
	var wait_ms: Array[float] = []
	var install_ms: Array[float] = []
	var wall_ms: Array[float] = []
	var done := 0
	for pts in drafts:
		var res := RoadDraftCheck.check(net, pts, WorldRoadEdge.CLASS_LOCAL, rules)
		if not bool(res["ok"]):
			continue
		var w0 := Time.get_ticks_usec()
		var t1 := Time.get_ticks_usec()
		RoadDraftCheck.apply(net, pts, WorldRoadEdge.CLASS_LOCAL, rules)
		add_ms.append((Time.get_ticks_usec() - t1) / 1000.0)
		var t2 := Time.get_ticks_usec()
		sync.begin_async()
		begin_ms.append((Time.get_ticks_usec() - t2) / 1000.0)
		var t3 := Time.get_ticks_usec()
		while sync.is_busy() and not WorkerThreadPool.is_task_completed(sync._task):
			OS.delay_msec(1)
		wait_ms.append((Time.get_ticks_usec() - t3) / 1000.0)
		var t4 := Time.get_ticks_usec()
		var rep := sync.poll()
		install_ms.append((Time.get_ticks_usec() - t4) / 1000.0)
		wall_ms.append((Time.get_ticks_usec() - w0) / 1000.0)
		done += 1
		if done >= 12:
			break
		await process_frame
	print("ROAD_UX_COMMIT add_road (tick içinde, ana iş parçacığı): %s" % _stats(add_ms))
	print("ROAD_UX_COMMIT begin_async (ana iş parçacığı): %s" % _stats(begin_ms))
	print("ROAD_UX_COMMIT arka plan chunk verisi (ana iş parçacığı BEKLEMEZ; burada beklendi): %s" % _stats(wait_ms))
	print("ROAD_UX_COMMIT poll/install (ana iş parçacığı): %s" % _stats(install_ms))
	print("ROAD_UX_COMMIT toplam duvar (PLAYABLE_ROADS ms'ine karşılık): %s" % _stats(wall_ms))
	holder.queue_free()


func _probe_panel() -> void:
	var run_d := P.setup()
	var facade: SimFacadeImpl = run_d["facade"]
	var tool := RoadDrawTool.create(run_d["net"], facade)
	tool.activate()
	var ctx := UiContext.for_profile_name(&"desktop")
	var holder := Control.new()
	holder.theme = UiTheme.build(ctx)
	holder.size = Vector2(440.0, 1400.0)
	root.add_child(holder)
	var panel := RoadDrawPanel.create(ctx, facade, tool)
	holder.add_child(panel)
	panel.size = holder.size
	await process_frame
	tool.tap_at(P.GRID_ORIGIN, 5.0)
	var renders := [0]
	var hover_ms: Array[float] = []
	var panel_ms: Array[float] = []
	tool.changed.connect(func() -> void:
		var t := Time.get_ticks_usec()
		panel.refresh()
		panel_ms.append((Time.get_ticks_usec() - t) / 1000.0)
		renders[0] += 1)
	for i in 120:
		var p := P.GRID_ORIGIN + Vector2(0.0, -20.0 - float(i))   # her adım 1 m (HOVER_EPSILON_M = 0.5 üstü)
		var t0 := Time.get_ticks_usec()
		tool.hover_at(p, 1.0)
		hover_ms.append((Time.get_ticks_usec() - t0) / 1000.0)
		await process_frame
	print("ROAD_UX_HOVER 120 adım (1 m): hover_at toplam (panel yeniden çizimi DAHİL): %s" % _stats(hover_ms))
	print("ROAD_UX_HOVER panel.refresh çağrısı: %s | changed -> yeniden çizim sayısı=%d" % [_stats(panel_ms), renders[0]])
	holder.queue_free()
