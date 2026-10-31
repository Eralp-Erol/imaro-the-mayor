extends SceneTree
## T-050 pencereli yakalama + ölçüm probu: gerçek `playable.tscn` (gerçek sim + yol ağı + yaşam görünümü) üstünde
## sokak/mahalle/ilçe kareleri ve kare süresi. Sim'e YAZMAZ (yalnız kamera + okuma). Duvar saati yalnız ölçümdür
## (Intel Mac, iPad DEĞİL). Başsız ÇALIŞMAZ (dummy renderer görüntü üretmez).
##   tools/godot.sh --path . --resolution 1600x900 --script res://tools/godot/life_probe.gd -- \
##       --shots=/private/tmp/claude-501/t050_screens [--prefix=life] [--perf-frames=240] [--no-life] [--ab] \
##       [--poses=a,b,c]
## Kalan argümanlar oyuna geçer (--demo, --hide=hud, --life-time=5 ...). Çıktı satırları: LIFEPROBE_*.
## Pozlar: `street` (en yoğun kenarın yakınında), `street_far` (aynı kenar, daha uzak), `neigh` (mahalle), `district`
## (ilçe), `edge2` (ikinci en yoğun kenar), `ped` (yaya ölçeği, çok yakın), `top` (kuşbakışı).

const SCENE := "res://scenes/game/playable.tscn"

var _args: Dictionary = {}
var _scene: Node = null
var _frame_ms: Array[float] = []


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.trim_prefix("--").split("=", true, 1)
			_args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var shots_dir := str(_args.get("shots", ""))
	if not shots_dir.is_empty():
		DirAccess.make_dir_recursive_absolute(shots_dir)
	var prefix := str(_args.get("prefix", "life"))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var packed: PackedScene = load(SCENE)
	_scene = packed.instantiate()
	root.add_child(_scene)
	for _i in 30:
		await process_frame
	var life: Node = _scene.get_node_or_null("Life")
	var view: LifeView = life.view if life != null else null
	var activity: LifeEdgeActivity = life.activity if life != null else null
	if view != null:
		for _i in 120:
			await process_frame
	print("LIFEPROBE_STATE ", JSON.stringify(life.stats if life != null else {}))
	var edges := _busiest_edges(activity)
	_print_distribution(activity)
	for k in mini(3, edges.size()):
		var ee: WorldRoadEdge = _scene._net.edges[int(edges[k][1])]
		var ex := activity.expected(int(edges[k][1]), 1.0)
		var eid := int(edges[k][1])
		print("LIFEPROBE_EDGE rank=%d id=%d class=%s len=%.0f width=%.1f units=%s activity=%.1f exp_cars=%.2f "
				% [k, eid, String(ee.road_class), ee.length, ee.width, str(activity.edge_units.get(eid)),
				activity.activity(eid), ex.x] + "exp_people=%.2f" % ex.y)
	var poses := str(_args.get("poses", "street,street_far,neigh,district")).split(",", false)
	for pose in poses:
		var close := str(pose) in ["car", "person", "car_front", "person_front"]
		if close and view != null and not _args.has("life-time"):
			# Yakın plan: yaşam saatini dondur (örnek konumu hesaplandığı yerde kalsın).
			life._args["life-time"] = "1"
			view.set_running(false)
		var st := _pose_state(str(pose), edges)
		if st == null:
			continue
		_scene._camera.apply_state(st, true)
		for _i in (40 if close else 90):
			await process_frame
		await _shot(shots_dir, prefix, str(pose))
		if close and view != null:
			# Hareket kanıtı: aynı kamera, saat ileri (araç ~7,5 m/sn, yaya ~1,35 m/sn).
			var t0 := view.time_seconds()
			view.set_time_fixed(t0 + (1.0 if str(pose).begins_with("car") else 3.0))
			for _i in 6:
				await process_frame
			await _shot(shots_dir, prefix, str(pose) + "_t1")
			view.set_time_fixed(t0)
			continue
		if _args.has("ab") and view != null:
			await _measure_ab(str(pose), view)
		else:
			await _measure(str(pose))
	print("LIFEPROBE_FINAL ", JSON.stringify(life.stats if life != null else {}))
	quit(0)


## Beklenen araç+yaya toplamı en yüksek kenarlar (uzunluk >= 70 m): yakalama pozları bunlardan seçilir.
func _busiest_edges(activity: LifeEdgeActivity) -> Array:
	var out: Array = []
	if activity == null:
		return out
	for eid in activity.eligible:
		var e: WorldRoadEdge = activity.net.edges[eid]
		if e.length < 90.0:
			continue
		var w := activity.expected(int(eid), 1.0)
		out.append([w.x + w.y, int(eid)])
	out.sort_custom(func(a: Array, b: Array) -> bool:
		return float(a[0]) > float(b[0]) or (float(a[0]) == float(b[0]) and int(a[1]) < int(b[1])))
	return out


func _pose_state(pose: String, edges: Array) -> CameraState:
	var cam: CameraRig = _scene._camera
	var st := cam.target_state()
	if pose in ["car", "person", "car_front", "person_front"]:
		return _pose_on_instance(pose.begins_with("car"), st, 180.0 if pose.ends_with("_front") else 0.0)
	if pose == "district":
		var r := CameraPresets.resolve("district:D1", _scene._world)
		return r["state"] as CameraState if r["ok"] else null
	if edges.is_empty():
		return null
	var pick := 1 if pose == "edge2" else 0
	var e: WorldRoadEdge = _scene._net.edges[int(edges[mini(pick, edges.size() - 1)][1])]
	var a: Vector2 = _scene._net.node_pos(e.a)
	var b: Vector2 = _scene._net.node_pos(e.b)
	var mid := (a + b) * 0.5
	st.focus_x = mid.x
	st.focus_z = mid.y
	var dir := (b - a).normalized()
	var heading := rad_to_deg(atan2(dir.x, -dir.y))   # 0 = kuzey (-z), 90 = doğu
	match pose:
		"street", "edge2":
			st.distance = 38.0
			st.pitch_deg = 14.0
			st.heading_deg = heading + 5.0
		"street_far":
			st.distance = 90.0
			st.pitch_deg = 16.0
			st.heading_deg = heading + 5.0
		"ped":
			st.distance = 18.0
			st.pitch_deg = 8.0
			st.heading_deg = heading + 12.0
		"neigh":
			st.distance = 320.0
			st.pitch_deg = 32.0
			st.heading_deg = heading
		"top":
			st.distance = 140.0
			st.pitch_deg = 70.0
			st.heading_deg = heading
		_:
			return null
	return st


func _shot(shots_dir: String, prefix: String, pose: String) -> void:
	if shots_dir.is_empty():
		return
	await RenderingServer.frame_post_draw
	var path := "%s/%s-%s.png" % [shots_dir, prefix, pose]
	root.get_viewport().get_texture().get_image().save_png(path)
	print("LIFEPROBE_SHOT ", path)


## Kare süresi örnekleri: {times, dc, prims}.
func _sample(frames: int) -> Dictionary:
	var times: Array[float] = []
	var last := Time.get_ticks_usec()
	var dc := 0.0
	var prims := 0.0
	var gpu := 0.0
	var rcpu := 0.0
	var vp := root.get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp, true)
	for _i in frames:
		await process_frame
		var now := Time.get_ticks_usec()
		times.append((now - last) / 1000.0)
		last = now
		gpu += RenderingServer.viewport_get_measured_render_time_gpu(vp)
		rcpu += RenderingServer.viewport_get_measured_render_time_cpu(vp)
		dc += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		prims += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	return {"times": times, "dc": dc, "prims": prims, "gpu": gpu, "rcpu": rcpu, "n": frames}


func _report(label: String, parts: Array) -> void:
	var times: Array[float] = []
	var dc := 0.0
	var prims := 0.0
	var gpu := 0.0
	var rcpu := 0.0
	var n := 0
	for part in parts:
		times.append_array(part["times"] as Array[float])
		dc += float(part["dc"])
		prims += float(part["prims"])
		gpu += float(part["gpu"])
		rcpu += float(part["rcpu"])
		n += int(part["n"])
	times.sort()
	var sum := 0.0
	for t in times:
		sum += t
	print("LIFEPROBE_PERF pose=%s mean_ms=%.2f median_ms=%.2f p95_ms=%.2f max_ms=%.2f draw_calls=%.0f tris=%.0f "
			% [label, sum / times.size(), times[times.size() / 2], times[int(times.size() * 0.95)], times[-1], dc / n,
			prims / n] + "gpu_ms=%.2f render_cpu_ms=%.2f n=%d" % [gpu / n, rcpu / n, n])


func _measure(label: String) -> void:
	var frames := int(str(_args.get("perf-frames", "180")))
	if frames <= 0:
		return
	_report(label, [await _sample(frames)])


## Aynı dünyada, aynı kamerada araya serpiştirilmiş A/B (makine gürültüsü iki tarafa eşit dağılır): yaşam görünümü
## açık / kapalı (gizli + işlemi kapalı: çizim ve CPU maliyeti yok).
## Blok `--ab-block` kare (25) x `--ab-rounds` tur (8).
func _measure_ab(label: String, view: LifeView) -> void:
	var frames := int(str(_args.get("ab-block", "25")))
	var rounds := int(str(_args.get("ab-rounds", "8")))
	var on_parts: Array = []
	var off_parts: Array = []
	for _r in rounds:
		on_parts.append(await _sample(frames))
		view.visible = false
		view.set_process(false)
		for _i in 8:
			await process_frame
		off_parts.append(await _sample(frames))
		view.visible = true
		view.set_process(true)
		for _i in 8:
			await process_frame
	_report(label + "_on", on_parts)
	_report(label + "_off", off_parts)


## Kalibrasyon: yaşam taşıyan kenarlarda 100 m başına beklenen araç/yaya dağılımı (sınıf başına) ve dünya toplamı.
func _print_distribution(activity: LifeEdgeActivity) -> void:
	if activity == null:
		return
	var per_class: Dictionary = {}
	var tot := Vector2.ZERO
	var len_sum := 0.0
	for eid in activity.eligible:
		var e: WorldRoadEdge = activity.net.edges[eid]
		var w := activity.expected(int(eid), 1.0)
		tot += w
		len_sum += e.length
		var key := String(e.road_class)
		if not per_class.has(key):
			per_class[key] = {"cars": [], "people": [], "n": 0, "empty": 0}
		var row: Dictionary = per_class[key]
		row["n"] += 1
		if w.x <= 0.0 and w.y <= 0.0:
			row["empty"] += 1
			continue
		(row["cars"] as Array).append(w.x / e.length * 100.0)
		(row["people"] as Array).append(w.y / e.length * 100.0)
	var out := {}
	for key in per_class:
		var row: Dictionary = per_class[key]
		var cars: Array = row["cars"]
		var ppl: Array = row["people"]
		cars.sort()
		ppl.sort()
		out[key] = {"n": row["n"], "empty": row["empty"],
				"cars_per100_p50_p90_max": [snappedf(cars[cars.size() / 2], 0.01) if not cars.is_empty() else 0,
						snappedf(cars[int(cars.size() * 0.9)], 0.01) if not cars.is_empty() else 0,
						snappedf(cars[-1], 0.01) if not cars.is_empty() else 0],
				"people_per100_p50_p90_max": [snappedf(ppl[ppl.size() / 2], 0.01) if not ppl.is_empty() else 0,
						snappedf(ppl[int(ppl.size() * 0.9)], 0.01) if not ppl.is_empty() else 0,
						snappedf(ppl[-1], 0.01) if not ppl.is_empty() else 0]}
	print("LIFEPROBE_DIST ", JSON.stringify({"world_cars": snappedf(tot.x, 1.0), "world_people": snappedf(tot.y, 1.0),
			"road_km": snappedf(len_sum / 1000.0, 0.1), "by_class": out}))


## Yakın plan: en yakın hücrenin ilk araç/insan örneği (gölgelendirici konumu aynı formülle hesaplanır).
func _pose_on_instance(car: bool, st: CameraState, flip_deg: float) -> CameraState:
	var life: Node = _scene.get_node_or_null("Life")
	if life == null or life.view == null:
		return null
	var view: LifeView = life.view
	var cfgd: Dictionary = life.config.data["movement"]
	var t := view.time_seconds()
	for cell in view._cells:
		var node: Node3D = view._cells[cell]["node"]
		if node == null:
			continue
		var mmi := node.get_node_or_null("Cars" if car else "Human0L1") as MultiMeshInstance3D
		if mmi == null:
			continue
		var mm := mmi.multimesh
		var xf := mm.get_instance_transform(0)
		var cd := mm.get_instance_custom_data(0)
		var pk := int(cd.a + 0.5)
		var phase := float(pk & 1023) / 1024.0
		var sq := float((pk >> 10) & 15) / 15.0
		var base_speed := float(cfgd["car_speed_mps" if car else "person_speed_mps"])
		var spd := base_speed * (1.0 + float(cfgd["speed_spread"]) * (sq * 2.0 - 1.0))
		var d := fposmod(t * spd + phase * cd.r, cd.r)
		var fwd := xf.basis.z.normalized()
		var pos := node.position + xf.origin + fwd * d
		st.focus_x = pos.x
		st.focus_z = pos.z
		st.distance = float(_args.get("close-distance", "8"))
		st.pitch_deg = float(_args.get("close-pitch", "14"))
		st.heading_deg = rad_to_deg(atan2(fwd.x, -fwd.z)) + flip_deg + float(_args.get("close-heading", "18"))
		print("LIFEPROBE_INSTANCE kind=%s pos=%s fwd=%s d=%.1f len=%.1f" % [
				"car" if car else "person", str(pos), str(fwd), d, cd.r])
		return st
	return null
