extends SceneTree
## Render performans ölçümü (T-001 ölçüt 6, ADR-0001 "Render kare süresi" + "Draw call"). Sahneyi PENCERELİ açar,
## ilk `--warmup` kareyi atar, sonraki kareleri ölçer; JSON yazar ve özet basar. tools/perf.sh sarar.
##   godot --path . [--resolution WxH] --script res://tools/godot/perf_probe.gd -- --scene=res://x.tscn
##         --out=/abs/x.json
##         [--frames=360] [--warmup=60] [--name=ad] [sahneye geçecek argümanlar, örn. --preset=metro]
## Kare süresi = ardışık process_frame duvar saati (VSync KAPALI zorlanır; CPU+GPU+takas dahil). Draw call/obje/üçgen
## Performance monitörleri ile (RENDER_TOTAL_*_IN_FRAME) ve RenderingServer.get_rendering_info ile çapraz okunur.
## GPU süresi Compatibility renderer'da ölçülemeyebilir (viewport_get_measured_render_time_gpu → 0 ise raporlanır).
## Sahnede `perf_tag() -> String` varsa her kare etiketlenir ve `by_tag` altında etiket başına kare süresi / draw call /
## üçgen ayrıca raporlanır (T-003: otomatik yörünge+zoom taramasında metro/district/local/street aşamaları).
## --headless ile ÇALIŞMAZ (dummy renderer).


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	var scene_path := ""
	var out_path := ""
	var frames := 360
	var warmup := 60
	var run_name := "perf"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--scene="):
			scene_path = arg.trim_prefix("--scene=")
		elif arg.begins_with("--out="):
			out_path = arg.trim_prefix("--out=")
		elif arg.begins_with("--frames="):
			frames = maxi(10, int(arg.trim_prefix("--frames=")))
		elif arg.begins_with("--warmup="):
			warmup = maxi(0, int(arg.trim_prefix("--warmup=")))
		elif arg.begins_with("--name="):
			run_name = arg.trim_prefix("--name=")
	if scene_path == "" or not ResourceLoader.exists(scene_path):
		printerr("perf_probe: sahne yok: '%s'" % scene_path)
		quit(2)
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var vp := root.get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)

	var t_load := Time.get_ticks_usec()
	var scene: Node = (load(scene_path) as PackedScene).instantiate()
	root.add_child(scene)
	var scene_ready_ms := (Time.get_ticks_usec() - t_load) / 1000.0

	var frame_ms: Array[float] = []
	var cpu_ms: Array[float] = []
	var gpu_ms: Array[float] = []
	var draw_calls: Array[float] = []
	var objects: Array[float] = []
	var primitives: Array[float] = []
	var tags: Array[String] = []
	var tagged: bool = scene.has_method("perf_tag")
	var last := Time.get_ticks_usec()
	for k in warmup + frames:
		await process_frame
		var now := Time.get_ticks_usec()
		if k >= warmup:
			frame_ms.append((now - last) / 1000.0)
			cpu_ms.append(RenderingServer.viewport_get_measured_render_time_cpu(vp))
			gpu_ms.append(RenderingServer.viewport_get_measured_render_time_gpu(vp))
			draw_calls.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
			objects.append(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
			primitives.append(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
			if tagged:
				tags.append(str(scene.call("perf_tag")))
		last = now
	var rs_draw_calls := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	var rs_objects := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)
	var rs_prims := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)

	var report := {
		"name": run_name, "scene": scene_path, "args": OS.get_cmdline_user_args(),
		"renderer": String(ProjectSettings.get_setting("rendering/renderer/rendering_method", "?")),
		"gpu": RenderingServer.get_video_adapter_name(), "godot": Engine.get_version_info()["string"],
		"window": [root.size.x, root.size.y], "vsync": "disabled (forced)",
		"frames_measured": frames, "warmup_frames_skipped": warmup,
		"frame_ms": _stats(frame_ms), "render_cpu_ms": _stats(cpu_ms), "render_gpu_ms": _stats(gpu_ms),
		"draw_calls": _stats(draw_calls), "objects": _stats(objects), "primitives": _stats(primitives),
		"rendering_info_last_frame": {"draw_calls": rs_draw_calls, "objects": rs_objects, "primitives": rs_prims},
		"memory_mb": {
			"static": snappedf(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, 0.1),
			"video": snappedf(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0, 0.1),
			"texture": snappedf(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0, 0.1),
			"buffer": snappedf(Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED) / 1048576.0, 0.1),
		},
		"node_count": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"scene_ready_ms": snappedf(scene_ready_ms, 0.1),
		"scene_build_stats": scene.get("build_stats") if scene.get("build_stats") != null else {},
	}
	if tagged:
		report["by_tag"] = _by_tag(tags, frame_ms, draw_calls, primitives)
	report["hitches"] = _hitches(frame_ms, tags)
	var text := JSON.stringify(report, "\t")
	print("PERF_PROBE ", JSON.stringify(report))
	if out_path != "":
		DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
		var f := FileAccess.open(out_path, FileAccess.WRITE)
		if f != null:
			f.store_string(text)
	quit(0)


## Tek tek takılmalar: 50 ms üstü kareler (kare sırası ölçüm başından, etiket varsa o karedeki etiket). En çok 12.
func _hitches(frame_ms: Array[float], tags: Array[String]) -> Array:
	var out: Array = []
	for k in frame_ms.size():
		if frame_ms[k] > 50.0 and out.size() < 12:
			out.append({"frame": k, "ms": snappedf(frame_ms[k], 0.1), "tag": tags[k] if k < tags.size() else ""})
	return out


func _by_tag(tags: Array[String], frame_ms: Array[float], draw_calls: Array[float],
		primitives: Array[float]) -> Dictionary:
	var order: Array[String] = []
	for tag in tags:
		if not order.has(tag):
			order.append(tag)
	var out := {}
	for tag in order:
		var f: Array[float] = []
		var d: Array[float] = []
		var p: Array[float] = []
		for k in tags.size():
			if tags[k] == tag:
				f.append(frame_ms[k])
				d.append(draw_calls[k])
				p.append(primitives[k])
		out[tag] = {"frames": f.size(), "frame_ms": _stats(f), "draw_calls": _stats(d), "primitives": _stats(p)}
	return out


func _stats(values: Array[float]) -> Dictionary:
	if values.is_empty():
		return {}
	var sorted := values.duplicate()
	sorted.sort()
	var total := 0.0
	for v in values:
		total += v
	var n := sorted.size()
	return {
		"mean": snappedf(total / n, 0.01), "p50": snappedf(sorted[n / 2], 0.01),
		"p95": snappedf(sorted[mini(n - 1, int(ceil(n * 0.95)) - 1)], 0.01),
		"p99": snappedf(sorted[mini(n - 1, int(ceil(n * 0.99)) - 1)], 0.01),
		"max": snappedf(sorted[n - 1], 0.01), "min": snappedf(sorted[0], 0.01),
	}
