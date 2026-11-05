extends SceneTree
## Yol onayı penceresi kare dökümü (ADR-0010 Karar 5, B-040). Gerçek `playable.tscn --demo`'yu PENCERELİ ve motorun gerçek
## deltasıyla sürer, `--at-tick` gününde bir yol komutu gönderir ve gönderimden sonraki `--window` karenin HER KARESİ için
## toplam süreyi ve (`--split` ile) alt sistem dökümünü yazar. Sim'e ve sahneye yazmaz; yalnız komut gönderir (oyuncu gibi).
## Çalıştır (tek Godot; kilit: mkdir /tmp/imaro-godot.lock):
##   tools/godot.sh --path . --resolution 1600x900 --script res://tools/godot/road_window_probe.gd -- \
##       [--demo] [--at-tick=835] [--window=150] [--speed=3] [--split] [--out=/abs/x.json]
## `--split`: sahnenin kare işi (`_process`) probe'dan çağrılır ve yol tüketicileri (`PlayableRoads.pump` + `
## PlayableExpropriation.poll` + bitki koridoru) aynı sırayla ama AYRI ayrı zamanlanır (kalem başına ms). Kalemler:
##   reconcile, bld_pump, ground, veg (kamulaştırma takibi) · prepare (RoadEditSync._prepare + işçi başlatma) ·
##   roadpoll_join/install/far (RoadEditSync.poll durumuna göre) · corridor · proc (sahnenin kalan `_process`i).
##   `rest` = toplam - (proc + kalemler) = çizim/takas/motor payı (GL tampon yüklemesi, ilk çizimde derleme).
## Split OLMADAN kare yalnız toplam süredir (motor sürer; önce/sonra karşılaştırması bu kipte yapılır).
## Duvar saati ölçümdür: makineye bağlı (Intel Mac, iPad DEĞİL); yük 8'in üstündeyse anlamsızdır.

const SCENE := "res://scenes/game/playable.tscn"
const NETWORK_PATH := "res://data/world/ismeral/network.json"
const NEAR_M := 150.0
const SEG_TRIES := 600

var _args: Dictionary = {}
var _scene: Node = null
var _draw_t0: int = 0
var _draw_ms: float = 0.0
var _nodes: Array[Node] = []
var _phys: Array[Node] = []


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	_args = _parse(OS.get_cmdline_user_args())
	var at_tick := int(_args.get("at-tick", "835"))
	var window := int(_args.get("window", "150"))
	var speed := int(_args.get("speed", "3"))
	var split := _args.has("split")
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	RenderingServer.frame_pre_draw.connect(func() -> void: _draw_t0 = Time.get_ticks_usec())
	RenderingServer.frame_post_draw.connect(func() -> void: _draw_ms = (Time.get_ticks_usec() - _draw_t0) / 1000.0)
	var t_setup := Time.get_ticks_usec()
	_scene = (load(SCENE) as PackedScene).instantiate()
	root.add_child(_scene)
	var setup_s := (Time.get_ticks_usec() - t_setup) / 1e6
	var facade: SimFacade = _scene._facade
	if facade == null:
		printerr("road_window_probe: facade yok")
		quit(2)
		return
	var pr: PlayableRoads = _scene._pr
	var f: PlayableExpropriation = pr.follow if pr != null else null
	var sync: RoadEditSync = pr.sync if pr != null else null
	if split and (pr == null or f == null or sync == null):
		printerr("road_window_probe: --split için yol bağlaması/takipçi yok")
		quit(2)
		return
	if _args.has("no-far"):
		(_scene._roads as RoadView).build_far_mesh = false
	var frames := 0
	var guard := 0
	while guard < 400000 and facade.current_tick() < at_tick:
		# Ölçüm öncesi: sim hızlı sürsün, yük ısınması örtü altında bitsin. Hız ayarı oyuncunun HUD'u gibi facade'den.
		if frames == 60:
			facade.set_speed(speed)
		await process_frame
		frames += 1
		guard += 1
	# Kısa durulma: önceki işler (bitki yerleşimi, bina kuyruğu, ısınma) bitsin; yol penceresi temiz başlasın.
	var settle := 0
	while settle < 240 or (f != null and f.busy()) or (sync != null and sync.world_busy()):
		await process_frame
		settle += 1
		if settle > 4000:
			break
	if _args.has("life-old"):
		# A/B: B-040 öncesi davranış (yol onayı sonrası kenar dizini + parsel toplamı TEK karede, 5000 parsel/kare).
		var lh: Node = _scene.get_node_or_null("Life")
		if lh != null:
			lh._booted = false
	var roads_n := int(_args.get("roads", "1"))
	var all_out: Array[Dictionary] = []
	var all_rows: Array = []
	for ri in roads_n:
		if ri > 0:
			settle = 0
			while settle < 300 or (f != null and f.busy()) or (sync != null and sync.world_busy()):
				await process_frame
				settle += 1
				if settle > 4000:
					break
		var out := {"road": ri, "at_tick": facade.current_tick(), "speed": speed, "split": split,
				"setup_s": snappedf(setup_s, 0.1), "settle_frames": settle}
		var rows: Array[Dictionary] = []
		var sent_us := Time.get_ticks_usec()
		var t_cmd := Time.get_ticks_usec()
		var road_ok := _send_road(facade, out, 4311 + ri)
		out["submit_ms"] = snappedf((Time.get_ticks_usec() - t_cmd) / 1000.0, 0.01)
		if not road_ok:
			quit(3)
			return
		var last := Time.get_ticks_usec()
		var saved_pr: PlayableRoads = pr
		var prev_cpu := 0.0
		if _args.has("nodes"):
			_collect(_scene)
		if split:
			_scene.set_process(false)  # sahnenin kare işini aşağıda biz çağırırız (alt sistemler ayrı zamanlanır)
		for k in window:
			await process_frame
			var now := Time.get_ticks_usec()
			var total_ms := (now - last) / 1000.0
			last = now
			var row := {"k": k, "total_ms": total_ms, "tick": facade.current_tick(), "draw_ms": _draw_ms}
			if split:
				# Bu satırın toplamı, ÖNCEKİ satırda zamanlanan kare işini de içerir: `rest` buna göre hesaplanır.
				row["rest_ms"] = total_ms - prev_cpu
				var delta := total_ms / 1000.0
				var t0 := Time.get_ticks_usec()
				var items: Dictionary = {}
				# --- PlayableRoads.pump() / PlayableExpropriation.poll() aynı sırayla, kalem kalem ---
				var t := Time.get_ticks_usec()
				var rep := {}
				if f._net.graph_version != f._seen_version:
					rep = f.reconcile()
				items["reconcile"] = _since(t)
				var left := maxi(PlayableExpropriation.BUDGET_US - (Time.get_ticks_usec() - t), 0)
				t = Time.get_ticks_usec()
				if f._view != null and f._view.pending_work() > 0:
					f._view.pump_pending(left)
				items["bld_pump"] = _since(t)
				t = Time.get_ticks_usec()
				if (f._has_ground_dirty or (f._terrain != null and f._terrain.urban_update_pending())) \
						and (f._view == null or f._view.pending_work() == 0):
					f._update_ground(PlayableExpropriation.BUDGET_US)
				items["ground"] = _since(t)
				t = Time.get_ticks_usec()
				f._poll_vegetation(maxi(PlayableExpropriation.BUDGET_US - (Time.get_ticks_usec() - t0),
						PlayableExpropriation.VEG_MIN_SLICE_US))
				items["veg"] = _since(t)
				t = Time.get_ticks_usec()
				if pr.due and not sync.is_busy():
					pr.due = false
					sync.begin_async()
				items["prepare"] = _since(t)
				t = Time.get_ticks_usec()
				var key := "roadpoll_install" if sync._installing else "roadpoll_join"
				if not sync._installing and (sync._task < 0 or not WorkerThreadPool.is_task_completed(sync._task)):
					key = "roadpoll_far"
				var road_rep := sync.poll()
				items[key] = _since(t)
				pr.note_report(road_rep, _scene.sim_stats, facade.current_tick())
				t = Time.get_ticks_usec()
				if pr.corridors_due():
					_scene._refresh_vegetation_corridors()
				items["corridor"] = _since(t)
				# --- sahnenin geri kalanı (yol kalemleri yukarıda yürütüldüğü için `_pr` geçici null) ---
				var roads_ms := (Time.get_ticks_usec() - t0) / 1000.0
				if _args.has("nodes"):
					for n in _nodes:
						if is_instance_valid(n) and n.is_inside_tree():
							var sf: String = (n.get_script() as Script).resource_path.get_file()
							if _args.has("life-split") and sf == "life_host.gd" and n.view != null:
								_life_tick(n, items)
								continue
							var tn := Time.get_ticks_usec()
							n._process(delta)
							var us := Time.get_ticks_usec() - tn
							var nm := "np:%s" % sf
							items[nm] = float(items.get(nm, 0.0)) + us / 1000.0
					for n in _phys:
						if is_instance_valid(n) and n.is_inside_tree():
							var tn := Time.get_ticks_usec()
							n._physics_process(delta)
							var us := Time.get_ticks_usec() - tn
							var nm := "pp:%s" % n.name
							items[nm] = float(items.get(nm, 0.0)) + us / 1000.0
				t = Time.get_ticks_usec()
				_scene._pr = null
				_scene._process(delta)
				_scene._pr = saved_pr
				saved_pr.note_tick()
				items["proc"] = _since(t)
				row["items"] = items
				row["roads_ms"] = roads_ms
				prev_cpu = (Time.get_ticks_usec() - t0) / 1000.0
				row["cpu_ms"] = prev_cpu
			rows.append(row)
		_scene.set_process(true)
		out["window_ms"] = snappedf((Time.get_ticks_usec() - sent_us) / 1000.0, 0.1)
		_report(rows, out)
		all_out.append(out)
		all_rows.append(rows)
	var path := str(_args.get("out", ""))
	if path != "":
		var fa := FileAccess.open(path, FileAccess.WRITE)
		if fa != null:
			fa.store_string(JSON.stringify({"summary": all_out, "rows": all_rows}))
			fa.close()
	quit(0)


## Sahne altındaki betikli düğümlerin `_process`/`_physics_process`ini motordan alıp probe'dan zamanlayarak sürer (`--nodes`).
func _collect(node: Node) -> void:
	for c in node.get_children():
		if c.get_script() != null:
			if c.is_processing() and c.has_method("_process"):
				c.set_process(false)
				_nodes.append(c)
			if c.is_physics_processing() and c.has_method("_physics_process"):
				c.set_physics_process(false)
				_phys.append(c)
		_collect(c)


## B-040 ÖNCESİ `LifeHost._tick` (tek karede `index_edges` + `begin_rebuild` + 5000 parsel/kare) aynı sırayla, kalem kalem
## zamanlanır (`--life-split`; yalnız ölçüm, host'un özel alanlarını okur/yazar). B-040 sonrası kare dilimli yolu ölçmez.
func _life_tick(h: Node, items: Dictionary) -> void:
	var t := Time.get_ticks_usec()
	var tick: int = h._facade.current_tick()
	var ticked: bool = tick != h._tick_seen
	h._tick_seen = tick
	if h._net.graph_version != h._graph_seen:
		h._graph_pending = true
	if h._graph_pending and not h._roads_busy():
		h._graph_pending = false
		h._graph_seen = h._net.graph_version
		var t1 := Time.get_ticks_usec()
		h.activity.index_edges()
		items["life_index_edges"] = _since(t1)
		t1 = Time.get_ticks_usec()
		h.activity.begin_rebuild()
		items["life_begin_rebuild"] = _since(t1)
		t1 = Time.get_ticks_usec()
		h.view.mark_data_changed()
		items["life_mark"] = _since(t1)
	if h.activity.is_rebuilding():
		var t2 := Time.get_ticks_usec()
		h.activity.step_rebuild(h._init_per_frame)
		items["life_step_rebuild"] = _since(t2)
	var t3 := Time.get_ticks_usec()
	h.reader.poll(ticked)
	items["life_reader_poll"] = _since(t3)
	if h.reader.occupancy_changed:
		h.reader.occupancy_changed = false
		h.view.mark_data_changed()
	h.view.set_running(h._facade.speed() > 0 and not h._args.has("life-time"))
	var cam: Vector3 = h._camera.camera.global_position
	h.view.track_camera(cam, Vector2(cam.x + h._camera.rebase_origin.x, cam.z + h._camera.rebase_origin.y))
	items["life_host_total"] = _since(t)


func _since(t_us: int) -> float:
	return (Time.get_ticks_usec() - t_us) / 1000.0


func _report(rows: Array[Dictionary], out: Dictionary) -> void:
	var worst := 0.0
	var worst_k := -1
	var over50 := 0
	var over33 := 0
	var sum := 0.0
	for r in rows:
		var ms := float(r["total_ms"])
		sum += ms
		if ms > worst:
			worst = ms
			worst_k = int(r["k"])
		if ms > 50.0:
			over50 += 1
		if ms > 33.3:
			over33 += 1
	out["worst_ms"] = snappedf(worst, 0.1)
	out["worst_k"] = worst_k
	out["over50"] = over50
	out["over33"] = over33
	out["sum_ms"] = snappedf(sum, 1.0)
	var sc: Dictionary = _scene.sim_stats
	out["road_sync_ms_last"] = sc.get("road_sync_ms_last")
	out["road_sync_chunks"] = sc.get("road_sync_chunks")
	print("ROAD_WINDOW ", JSON.stringify(out))
	# Ağır kareler (> 25 ms) tek tek, kalem dökümüyle.
	for r in rows:
		if float(r["total_ms"]) >= 25.0:
			print("ROAD_WINDOW_FRAME ", JSON.stringify(_rounded(r)))


func _rounded(d: Dictionary) -> Dictionary:
	var o := {}
	for key: String in d:
		var v: Variant = d[key]
		if v is float:
			o[key] = snappedf(float(v), 0.1)
		elif v is Dictionary:
			var inner := {}
			for k2: String in v:
				if float(v[k2]) >= 0.05:
					inner[k2] = snappedf(float(v[k2]), 0.1)
			o[key] = inner
		else:
			o[key] = v
	return o


## demo_frame_probe._send_road ile aynı aday seçimi (tohum 4311): aynı yol, aynı koşul (kayıt: 2026-11-03/05).
func _send_road(facade: SimFacade, out: Dictionary, seed_value: int = 4311) -> bool:
	var net: WorldNetwork = _scene._net
	var rules := RoadDraftRules.load_path(NETWORK_PATH)
	var occupied: Dictionary = _scene._t0_occupied
	var vacant: Array = []
	for v in _scene._views:
		if not occupied.has(v.id):
			vacant.append(v)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var ids: Array = net.edges.keys()
	ids.sort()
	var best: Dictionary = {}
	for n in SEG_TRIES:
		var e: WorldRoadEdge = net.edges[ids[rng.randi() % ids.size()]]
		var a := net.node_pos(e.a).lerp(net.node_pos(e.b), rng.randf())
		var b := a + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(60.0, 250.0)
		var res := RoadDraftCheck.check(net, PackedVector2Array([a, b]), RoadDrawTool.ROAD_CLASS, rules)
		if not bool(res["ok"]):
			continue
		var count := 0
		for v in vacant:
			if _dist_to_segment(v.center, a, b) <= NEAR_M:
				count += 1
		if count >= 6 and (best.is_empty() or count > int(best["count"])):
			best = {"pts": res["points"], "count": count}
	if best.is_empty():
		printerr("road_window_probe: uygun yol adayı yok")
		return false
	var pts: PackedVector2Array = best["pts"]
	var cm := PackedInt64Array()
	for p in pts:
		cm.append(roundi(p.x * 100.0))
		cm.append(roundi(p.y * 100.0))
	var res := facade.submit_command(SimCommand.public_work_road(cm, RoadDrawTool.ROAD_CLASS))
	out["road_status"] = String(res.status)
	out["road_vacant_near"] = best["count"]
	return true


func _dist_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var len2 := ab.length_squared()
	var t := 0.0 if len2 <= 0.0 else clampf((p - a).dot(ab) / len2, 0.0, 1.0)
	return p.distance_to(a + ab * t)


func _parse(args: PackedStringArray) -> Dictionary:
	var out := {}
	for a in args:
		if a.begins_with("--"):
			var kv := a.trim_prefix("--").split("=", true, 1)
			out[kv[0]] = kv[1] if kv.size() > 1 else "1"
	return out
