extends SceneTree
## UI çizim maliyeti ölçümü (T-019 ölçüt 7): pencereli, dikey senkron kapalı; taban (boş sahne) ile ui_lab
## durumlarını
## karşılaştırır. Her durumda N kare: kare süresi (ortalama / p95 / en büyük), çizim çağrısı, düğüm
## sayısı,
## (varsa) viewport CPU/GPU render süresi. Dev aracı; Intel Mac Compatibility üzerinde koşar, iPad ölçümü
## DEĞİLDİR.
## Kullanım: tools/godot.sh --path . --resolution 1600x900 --script res://scenes/dev/ui_lab_perf.gd --
## [--imaro-input-profile=touch]

const FRAMES := 300
const WARMUP := 30
const CASES := [["baseline", ""], ["hud_home", "home"], ["hud_zoning_panel", "zoning"], ["hud_events_reason", "done"]]


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var rid := root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(rid, true)
	for c in CASES:
		await _measure(str(c[0]), str(c[1]), rid)
	quit()


func _measure(label: String, demo: String, rid: RID) -> void:
	var node: Node
	if demo == "":
		var rect := ColorRect.new()
		rect.color = Color("161b21")
		rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		node = rect
	else:
		node = (load("res://scenes/dev/ui_lab.tscn") as PackedScene).instantiate()
	root.add_child(node)
	if demo != "":
		await process_frame
		await process_frame
		node.call("_run_demo", demo)
	for i in WARMUP:
		await process_frame
	var times := PackedFloat64Array()
	var cpu := 0.0
	var gpu := 0.0
	var draws := 0.0
	var last := Time.get_ticks_usec()
	for i in FRAMES:
		await process_frame
		var now := Time.get_ticks_usec()
		times.append(float(now - last) / 1000.0)
		last = now
		cpu += RenderingServer.viewport_get_measured_render_time_cpu(rid)
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(rid)
		draws += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	var sorted := times.duplicate()
	sorted.sort()
	var avg := 0.0
	for t in times:
		avg += t
	avg /= float(times.size())
	var fmt := "PERF %-18s frame_ms avg=%.2f p95=%.2f max=%.2f | render_cpu_ms=%.3f render_gpu_ms=%.3f"
	fmt += " | draw_calls=%.0f nodes=%d"
	print(fmt % [
		label, avg, sorted[int(sorted.size() * 0.95)], sorted[sorted.size() - 1], cpu / FRAMES,
		gpu / FRAMES, draws / FRAMES, int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))])
	node.queue_free()
	await process_frame
