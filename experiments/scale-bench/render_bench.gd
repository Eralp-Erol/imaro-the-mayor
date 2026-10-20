extends Node3D
## Disposable render benchmark runner. Usage (user args after `--`):
##   godot --path . [--rendering-method mobile] -- --bench [--n=10000,30000,60000] [--shadows=off,on]
##         [--presets=metro,district,street] [--frames=180] [--warmup=60] [--detail=3000] [--out=name] [--shots=1]

const CityBuilder := preload("res://city_builder.gd")

var opt := {
	"n": "10000,30000,60000", "shadows": "off,on", "presets": "metro,district,street",
	"frames": "180", "warmup": "60", "detail": "3000", "out": "", "shots": "1", "max_seconds": "2400",
}
var cam: Camera3D
var sun: DirectionalLight3D
var builder: RefCounted
var results := {"meta": {}, "builds": [], "cases": []}
var t_start := Time.get_ticks_msec()
var out_path := ""
var shot_dir := ""


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and "=" in a:
			opt[a.get_slice("=", 0).trim_prefix("--")] = a.get_slice("=", 1)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	get_window().size = Vector2i(1366, 1024)
	get_window().position = Vector2i(0, 0)
	var renderer := RenderingServer.get_current_rendering_method()
	var tag: String = opt["out"] if opt["out"] != "" else renderer
	var res_dir := ProjectSettings.globalize_path("res://results")
	out_path = "%s/render-%s.json" % [res_dir, tag]
	shot_dir = "%s/shots/%s" % [res_dir, tag]
	DirAccess.make_dir_recursive_absolute(shot_dir)
	_setup_scene()
	results["meta"] = {
		"godot": Engine.get_version_info()["string"], "renderer": renderer,
		"driver": RenderingServer.get_current_rendering_driver_name(),
		"adapter": RenderingServer.get_video_adapter_name(), "vendor": RenderingServer.get_video_adapter_vendor(),
		"os": OS.get_name() + " " + OS.get_version(), "window": get_window().size, "msaa_3d": get_viewport().msaa_3d,
		"detail_end_m": float(opt["detail"]), "warmup_frames": int(opt["warmup"]), "measure_frames": int(opt["frames"]),
		"vsync_mode": DisplayServer.window_get_vsync_mode(),
	}
	print("META ", JSON.stringify(results["meta"]))
	await _run()
	_write()
	get_tree().quit()


func _setup_scene() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.68, 0.80, 0.88)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.80, 0.88)
	env.ambient_light_energy = 0.6
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	sun.light_energy = 1.1
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 3000.0
	add_child(sun)
	cam = Camera3D.new()
	add_child(cam)
	cam.current = true
	builder = CityBuilder.new()
	builder.detail_end = float(opt["detail"])
	add_child(builder.make_terrain())


func _preset(name: String) -> void:
	var f: Vector3 = builder.focus
	match name:
		"metro":
			cam.projection = Camera3D.PROJECTION_PERSPECTIVE
			cam.fov = 45.0
			cam.near = 500.0
			cam.far = 150000.0
			cam.position = Vector3(0, 36000, 36000)
			cam.look_at(Vector3(0, 0, 0))
		"district":
			cam.projection = Camera3D.PROJECTION_PERSPECTIVE
			cam.fov = 45.0
			cam.near = 5.0
			cam.far = 80000.0
			cam.position = f + Vector3(-300, 1100, 1500)
			cam.look_at(f)
		"street":
			cam.projection = Camera3D.PROJECTION_PERSPECTIVE
			cam.fov = 65.0
			cam.near = 0.5
			cam.far = 80000.0
			var p := Vector3(builder.street_x, 0, f.z - 120.0)
			p.y = builder.mesh_height(p.x, p.z) + 8.0
			cam.position = p
			cam.look_at(p + Vector3(0, -6, 200))


func _run() -> void:
	var rid := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(rid, true)
	for n_str in String(opt["n"]).split(","):
		var n := int(n_str)
		var city: Node3D = builder.make_city(n)
		add_child(city)
		results["builds"].append(builder.stats.duplicate())
		print("BUILD ", JSON.stringify(builder.stats))
		for sh in String(opt["shadows"]).split(","):
			sun.shadow_enabled = (sh == "on")
			for p in String(opt["presets"]).split(","):
				if (Time.get_ticks_msec() - t_start) / 1000.0 > float(opt["max_seconds"]):
					print("ABORT: max_seconds exceeded")
					results["meta"]["aborted_max_seconds"] = true
					return
				_preset(p)
				var c: Dictionary = await _measure(rid)
				c.merge({"n": n, "buildings": builder.stats["buildings"], "preset": p, "shadows": sh})
				var shot := "%s/n%d_%s_sh-%s.png" % [shot_dir, n, p, sh]
				if opt["shots"] == "1":
					await RenderingServer.frame_post_draw
					var img := get_viewport().get_texture().get_image()
					img.save_png(shot)
					c["screenshot"] = shot.replace(ProjectSettings.globalize_path("res://"), "")
					c["screenshot_size"] = "%dx%d" % [img.get_width(), img.get_height()]
				results["cases"].append(c)
				print("CASE ", JSON.stringify(c))
				_write()
		city.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame


func _measure(rid: RID) -> Dictionary:
	for i in int(opt["warmup"]):
		await get_tree().process_frame
	var times: Array[float] = []
	var dc := 0.0
	var prim := 0.0
	var obj := 0.0
	var cpu := 0.0
	var gpu := 0.0
	var frames := int(opt["frames"])
	var wall0 := Time.get_ticks_msec()
	var last := Time.get_ticks_usec()
	for i in frames:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		times.append((now - last) / 1000.0)
		last = now
		dc += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		prim += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		obj += Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
		cpu += RenderingServer.viewport_get_measured_render_time_cpu(rid) + RenderingServer.get_frame_setup_time_cpu()
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(rid)
		if Time.get_ticks_msec() - wall0 > 90000:  # per-case wall-clock cap
			frames = i + 1
			break
	var sorted := times.duplicate()
	sorted.sort()
	var avg := 0.0
	for t in times:
		avg += t
	avg /= times.size()
	var f := float(frames)
	return {
		"frames_measured": frames, "avg_ms": snappedf(avg, 0.01), "fps_avg": snappedf(1000.0 / avg, 0.1),
		"p95_ms": snappedf(sorted[mini(sorted.size() - 1, int(ceil(0.95 * sorted.size())) - 1)], 0.01),
		"max_ms": snappedf(sorted[-1], 0.01), "draw_calls": snappedf(dc / f, 0.1),
		"primitives": int(prim / f), "objects": snappedf(obj / f, 0.1),
		"cpu_render_ms": snappedf(cpu / f, 0.01), "gpu_render_ms": snappedf(gpu / f, 0.01),
		"mem_static_mb": snappedf(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, 0.1),
		"video_mem_mb": snappedf(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0, 0.1),
	}


func _write() -> void:
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	f.store_string(JSON.stringify(results, "  "))
