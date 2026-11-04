extends SceneTree
## Demo kare takılması ölçümü (2026-10-31, production/log/2026-10-31-demo-kare-takilmasi.md).
## Gerçek `playable.tscn` sahnesini yükler (gerçek dünya, HUD, sim, projector, yol/bitki görünümü) ve demo senaryosunu
## sürer: ısınma -> yol çiz (public_work.road) -> imar teklifi (zoning.propose + sonuç paneli) -> yüksek hız.
## Sahnenin `_process`'i engine yerine BURADAN sabit `dt` ile çağrılır (kare süresi ölçülür, tick sayısı deterministik).
## Kare başına evreler `sim_stats` farklarından okunur: sim sürüşü, hud.poll, projector/görünüm, yol, kalan.
## Duvar saati yalnız ölçümdür (makineye bağlı; Intel Mac, iPad DEĞİL). Başsız çalışmada çizim yok: GPU/çizim maliyeti
## bu ölçüme DAHİL DEĞİLDİR; CPU tarafı (sim, UI yerleşimi, mesh kurulumu GDScript) dahildir.
## Çalıştır (Godot başına tek koşu):
##   tools/godot.sh --headless --path . --script res://tests/sim/perf/demo_frame_probe.gd -- \
##       [--ticks=1700] [--dt=0.016667] [--speed=3] [--no-road] [--top=12] [--legacy-reason] \
##       [--panel=results|inspector|reason|none]
##       [--split] (sahne altındaki düğümlerin `_process`'ini engine yerine buradan, düğüm başına zamanlayarak sürer;
##        `np` sütunu) [--spike-ms=30] (toplam kare süresi bu eşiği aşan kareleri FRAME_PROBE_SPIKE olarak yazar)
##       [--plan-n=12] [--plan-radius=150] (imar önerisindeki boş parsel sayısı / yol çevresi yarıçapı: şehir büyümesi)
##       [--why-poll-ms=15] (HUD yoklaması bu eşiği aşan karelerin olay anahtarları: FRAME_PROBE_WHY)
##       [--calls-at=200,600,1000] (ayırıcı , veya ;) (bu tick'lerde bileşen çağrı süreleri: FRAME_PROBE_CALLS)
##       [--engine] (sahnenin `_process`'ini motor GERÇEK delta ile sürer: tick yetiştirme/sarmal davranışı dahil)
##       Sahneye giden dev argümanları (`--no-life`, `--no-vegetation`...) olduğu gibi geçer (A/B).
## Çıktı: `FRAME_PROBE_WINDOW` (120 karelik pencereler), `FRAME_PROBE_TOP` (en yavaş kareler), `FRAME_PROBE` JSON.

const SCENE := "res://scenes/game/playable.tscn"
const NETWORK_PATH := "res://data/world/ismeral/network.json"
const WARM_FRAMES := 90
const WINDOW := 120
const NEAR_M := 150.0
const SEG_TRIES := 600
const REASON_OPEN_TICK := 150

var _args: Dictionary = {}
var _scene: Node = null
var _rows: Array[Dictionary] = []
var _prev: Dictionary = {}
var _frame_t: int = 0
var _reason_ids: PackedInt64Array = PackedInt64Array()
var _split_nodes: Array[Node] = []
var _split_dt: float = 0.016667


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	_args = _parse(OS.get_cmdline_user_args())
	var dt := float(_args.get("dt", "0.016667"))
	var target_ticks := int(_args.get("ticks", "1700"))
	var speed := int(_args.get("speed", "3"))
	var panel := str(_args.get("panel", "results"))
	var packed: PackedScene = load(SCENE)
	_scene = packed.instantiate()
	root.add_child(_scene)
	await process_frame
	await process_frame
	if not _args.has("engine"):
		_scene.set_process(false)  # kareleri biz süreriz (sabit dt); `--engine`: motor kendi gerçek delta'sıyla sürer
	_split_dt = dt
	var facade: SimFacade = _scene._facade
	if facade == null:
		push_error("probe: facade yok")
		quit(2)
		return
	print("FRAME_PROBE_SETUP ", JSON.stringify(_scene.sim_stats))
	var out := {"dt": dt, "speed": speed, "panel": panel}
	if _args.has("legacy-reason"):
		# Düzeltme ÖNCESİ davranışın taklidi: gerekçe paneli her HUD yenilemesinde koşulsuz yeniden kurulur.
		_scene._hud.refreshed.connect(_legacy_reason_refresh)
		out["legacy_reason_refresh"] = true
	var frame := 0
	var sent_road := -1
	var sent_plan := -1
	var plan_ids := PackedInt64Array()
	var start_us := Time.get_ticks_usec()
	_prev = _snap()
	_frame_t = Time.get_ticks_usec()
	var max_frames := 400000
	var calls_at: Array[int] = []
	for part in str(_args.get("calls-at", "")).replace(";", ",").split(",", false):
		calls_at.append(int(part))
	while frame < max_frames:
		if frame == WARM_FRAMES and not _args.has("no-road"):
			sent_road = facade.current_tick()
			plan_ids = _send_road(facade, out)
		if frame == WARM_FRAMES + 30:
			sent_plan = facade.current_tick()
			_send_plan(facade, plan_ids, panel, out)
		if frame == WARM_FRAMES + 60:
			facade.set_speed(speed)
		if not _reason_ids.is_empty() and facade.current_tick() >= REASON_OPEN_TICK:
			_open_reason_panel(facade)
		_step(frame, dt)
		frame += 1
		if not calls_at.is_empty() and facade.current_tick() >= calls_at[0]:
			print("FRAME_PROBE_CALLS tick=%d %s" % [facade.current_tick(), JSON.stringify(_time_calls())])
			calls_at.remove_at(0)
		await process_frame
		if facade.current_tick() >= target_ticks:
			break
	out["frames"] = frame
	out["end_tick"] = facade.current_tick()
	out["road_tick"] = sent_road
	out["plan_tick"] = sent_plan
	out["wall_s"] = snappedf((Time.get_ticks_usec() - start_us) / 1e6, 0.1)
	_report(out)
	quit(0)


## Bir kare: sahnenin `_process`'i + engine'in geri kalanı (UI yerleşimi, zamanlayıcılar). Evre farkları `sim_stats`tan.
func _step(frame: int, dt: float) -> void:
	var facade: SimFacade = _scene._facade
	var tick0 := facade.current_tick()
	var seq0 := facade.last_event_seq()
	var t0 := Time.get_ticks_usec()
	if not _args.has("engine"):
		_scene._process(dt)
	var proc_us := Time.get_ticks_usec() - t0
	var np: Dictionary = _split_step(frame, dt) if _args.has("split") else {}
	var cur := _snap()
	var row := {
		"f": frame, "tick": facade.current_tick(), "ticks": facade.current_tick() - tick0,
		"events": facade.last_event_seq() - seq0, "proc_ms": proc_us / 1000.0,
		"drive_ms": (int(cur["drive_us"]) - int(_prev["drive_us"])) / 1000.0,
		"poll_ms": (int(cur["poll_us"]) - int(_prev["poll_us"])) / 1000.0,
		"sync_ms": float(cur["sync_ms"]) - float(_prev["sync_ms"]),
		"view_ms": float(cur["view_ms"]) - float(_prev["view_ms"]),
		"views": int(cur["view_n"]) - int(_prev["view_n"]),
		"road_n": int(cur["road_n"]) - int(_prev["road_n"]),
		"veg_ms": float(cur["veg_ms"]),
		"life_builds": int(cur["life_builds"]) - int(_prev["life_builds"]),
		"life_ms": float(cur["life_ms"]) - float(_prev["life_ms"]),
		"np": np,
		"mon": _monitors(),
	}
	if not _args.has("engine") and float(row["poll_ms"]) >= float(_args.get("why-poll-ms", "1000000")):
		# Ağır HUD yoklaması: bu karedeki olay anahtarları (neden ağır sorusu).
		var keys := PackedStringArray()
		for e in facade.events_since(seq0):
			keys.append("%s%s" % [String(e.message_key), "" if e.subjects.is_empty() else "@" + String(e.subjects[0])])
		print("FRAME_PROBE_WHY tick=%d poll_ms=%.1f drive_ms=%.1f events=%s" % [facade.current_tick(),
				float(row["poll_ms"]), float(row["drive_ms"]), ",".join(keys)])
	_prev = cur
	row["_frame_start_us"] = t0
	_rows.append(row)
	# Önceki karenin toplam süresi (engine payı dahil) bir sonraki satırda tamamlanır.
	if _rows.size() >= 2:
		var p := _rows[_rows.size() - 2]
		p["total_ms"] = (t0 - int(p["_frame_start_us"])) / 1000.0
		if _args.has("engine"):
			# Motor kipinde sahnenin kare işi bu `_step`ten SONRA koşar: evre farkları bir sonraki satırda görünür.
			p["ticks"] = int(row["tick"]) - int(p["tick"])
			for key in ["events", "drive_ms", "poll_ms", "sync_ms", "view_ms", "views", "life_ms", "life_builds"]:
				p[key] = row[key]
		if float(p["total_ms"]) >= float(_args.get("spike-ms", "1000000")):
			var c := p.duplicate()
			c.erase("_frame_start_us")
			print("FRAME_PROBE_SPIKE ", JSON.stringify(_rounded(c)))


## Sahne altındaki işlenen düğümleri (betikli) engine'den alıp burada zamanlayarak sürer. Dönüş: "ad:betik" -> ms.
func _split_step(frame: int, dt: float) -> Dictionary:
	if frame % 30 == 0:
		_collect_split(_scene)
	var out := {}
	for n in _split_nodes:
		if not is_instance_valid(n) or not n.is_inside_tree():
			continue
		var t := Time.get_ticks_usec()
		n._process(dt)
		var us := Time.get_ticks_usec() - t
		if us >= 200:
			var sc: Script = n.get_script()
			var key := "%s:%s" % [n.name, sc.resource_path.get_file() if sc != null else n.get_class()]
			out[key] = float(out.get(key, 0.0)) + us / 1000.0
	return out


func _collect_split(node: Node) -> void:
	for c in node.get_children():
		var sc: Script = c.get_script()
		if sc != null and c.is_processing() and c.has_method("_process"):
			c.set_process(false)
			_split_nodes.append(c)
		_collect_split(c)


## Dış gürültü göstergesi: sabit CPU işi (~0,2 ms) süresi. Çekirdek başka süreçlerce çalınırsa şişer; yavaş karelerde
## şişmişse sebep makine yüküdür (kod değil).
func _calibrate() -> float:
	var t := Time.get_ticks_usec()
	var acc := 0.0
	for i in 8000:
		acc += float(i) * 0.5
	if acc < 0.0:
		print(acc)
	return (Time.get_ticks_usec() - t) / 1000.0


func _monitors() -> Dictionary:
	return {
		"cal_ms": snappedf(_calibrate(), 0.01),
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"objs": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		"mem_mb": snappedf(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, 0.1),
		"draws": int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),
		"prims_k": snappedf(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME) / 1000.0, 0.1),
		"tproc_ms": snappedf(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, 0.01),
		"rcpu_ms": snappedf(RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid()), 0.01),
		"rgpu_ms": snappedf(RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()), 0.01),
	}


func _snap() -> Dictionary:
	var s: Dictionary = _scene.sim_stats
	var lf: Variant = _scene.build_stats.get("life")
	var lstats: Dictionary = lf if lf is Dictionary else {}
	return {
		"life_builds": int(lstats.get("cell_builds", 0)), "life_ms": float(lstats.get("build_ms_sum", 0.0)),
		"drive_us": int(s.get("drive_us_sum", 0)), "poll_us": int(s.get("poll_us_sum", 0)),
		"sync_ms": float(s.get("sync_ms_sum", 0.0)), "view_ms": float(s.get("view_ms_sum", 0.0)),
		"view_n": int(s.get("view_n", 0)), "road_n": int(s.get("road_sync_n", 0)),
		"veg_ms": float(s.get("veg_corridor_ms", 0.0)),
	}


func _open_reason_panel(facade: SimFacade) -> void:
	var best := _reason_ids[0]
	var best_n := -1
	for id in _reason_ids:
		var n := facade.reasons_for(SimContract.parcel_ref(int(id))).size()
		if n > best_n:
			best_n = n
			best = id
	var ref := SimContract.parcel_ref(int(best))
	_reason_ids = PackedInt64Array()
	_scene._m2_results.open_reason(func(p: ReasonPanel) -> void: p.show_subject(ref))
	print("FRAME_PROBE_REASON parcel=%d records=%d tick=%d" % [best, best_n, facade.current_tick()])


func _legacy_reason_refresh() -> void:
	var res: M2Results = _scene._m2_results
	if res != null and res.reason_panel() != null:
		res.reason_panel()._render()


func _send_road(facade: SimFacade, out: Dictionary) -> PackedInt64Array:
	var net: WorldNetwork = _scene._net
	var rules := RoadDraftRules.load_path(NETWORK_PATH)
	var occupied: Dictionary = _scene._t0_occupied
	var vacant: Array = []
	for v in _scene._views:
		if not occupied.has(v.id):
			vacant.append(v)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4311
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
			best = {"pts": res["points"], "count": count, "a": a, "b": b}
	if best.is_empty():
		push_error("probe: uygun yol adayı yok")
		return PackedInt64Array()
	var pts: PackedVector2Array = best["pts"]
	var cm := PackedInt64Array()
	for p in pts:
		cm.append(roundi(p.x * 100.0))
		cm.append(roundi(p.y * 100.0))
	var t0 := Time.get_ticks_usec()
	var res := facade.submit_command(SimCommand.public_work_road(cm, RoadDrawTool.ROAD_CLASS))
	out["road_status"] = String(res.status)
	out["road_vacant_near"] = best["count"]
	out["road_submit_ms"] = snappedf((Time.get_ticks_usec() - t0) / 1000.0, 0.01)
	var near := PackedInt64Array()
	var scored: Array = []
	var radius := float(_args.get("plan-radius", str(NEAR_M)))
	for v in vacant:
		var d := _dist_to_segment(v.center, pts[0], pts[pts.size() - 1])
		if d <= radius:
			scored.append([d, v.id])
	scored.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0] or (x[0] == y[0] and x[1] < y[1]))
	for k in mini(int(_args.get("plan-n", "12")), scored.size()):
		near.append(int(scored[k][1]))
	return near


func _send_plan(facade: SimFacade, ids: PackedInt64Array, panel: String, out: Dictionary) -> void:
	if ids.is_empty():
		ids = _scene._pick_demo_parcels(6, 0)
	var res := facade.submit_command(SimCommand.zoning_propose(ids, &"zone.mixed"))
	out["plan_status"] = String(res.status)
	out["plan_parcels"] = ids.size()
	if panel == "results" and _scene._m2_results != null:
		_scene._m2_results.track_parcels(ids)  # demo yolu: öneri sonrası sonuç paneli açılır
	elif panel == "reason":
		_reason_ids = ids  # gerekçe paneli, kayıtlar oluşunca (tick >= REASON_OPEN_TICK) en çok kayıtlı parselle açılır
	elif panel == "inspector" and _scene._inspector != null and not ids.is_empty():
		_scene._set_selection(int(ids[0]))
		_scene._inspector.select_parcel(int(ids[0]))


func _report(out: Dictionary) -> void:
	# 120 karelik pencereler (PLAYABLE_SMOKE ile aynı biçim) + evre ortalamaları.
	var n := _rows.size()
	var k := 0
	while k + WINDOW <= n:
		var w := _rows.slice(k, k + WINDOW)
		print("FRAME_PROBE_WINDOW ", JSON.stringify(_summ(w)))
		k += WINDOW
	var ticked: Array = _rows.filter(func(r: Dictionary) -> bool: return int(r["ticks"]) > 0)
	var idle: Array = _rows.filter(func(r: Dictionary) -> bool: return int(r["ticks"]) == 0)
	out["ticked_frames"] = _summ(ticked)
	out["idle_frames"] = _summ(idle)
	var sorted := _rows.duplicate()
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["proc_ms"]) > float(b["proc_ms"]))
	for i in mini(int(_args.get("top", "12")), sorted.size()):
		var r: Dictionary = sorted[i]
		var c := r.duplicate()
		c.erase("_frame_start_us")
		print("FRAME_PROBE_TOP ", JSON.stringify(_rounded(c)))
	var sc: Dictionary = _scene.sim_stats
	out["sim_stats"] = {"sync_n": sc.get("sync_n"), "view_n": sc.get("view_n"), "road_sync_n": sc.get("road_sync_n"),
			"road_sync_ms_max": sc.get("road_sync_ms_max"), "tick_cost_n": sc.get("tick_cost_n")}
	var bs: Dictionary = _scene.build_stats
	out["sim_sync"] = bs.get("sim_sync")
	out["life"] = bs.get("life")
	var lh: Node = _scene.get_node_or_null("Life")
	if lh != null and lh.get("reader") != null:
		out["life_reader"] = lh.reader.stats
		out["life_activity"] = lh.activity.stats
	out["tick_cost"] = bs.get("tick_cost")
	out["calls_ms"] = _time_calls()
	print("FRAME_PROBE ", JSON.stringify(out))


## Panel yenilemesinin bileşen çağrılarının tek tek süresi (20 çağrı ortalaması; sim durumu bu noktada sabit).
func _time_calls() -> Dictionary:
	var facade: SimFacade = _scene._facade
	var out := {}
	var res: M2Results = _scene._m2_results
	var plan_ids: PackedInt64Array = res.tracked if res != null else PackedInt64Array()
	var calls := {
		"snapshot": func() -> void: facade.snapshot(),
		"economy_outcome": func() -> void: facade.economy_outcome(),
		"events_since_0": func() -> void: facade.events_since(maxi(facade.last_event_seq() - 8, 0)),
		"parcel_views_tracked": func() -> void: facade.parcel_views(plan_ids),
	}
	if res != null:
		calls["m2_build_model"] = func() -> void: res.build_model()
	if not plan_ids.is_empty():
		var ref := SimContract.parcel_ref(int(plan_ids[0]))
		calls["reasons_for_parcel"] = func() -> void: facade.reasons_for(ref)
		out["reasons_for_parcel_n"] = facade.reasons_for(ref).size()
	var insp: InspectorHost = _scene._inspector
	if insp != null and insp.panel() != null:
		calls["inspector_build_model"] = func() -> void: insp.build_model()
		var ip := insp.panel()
		calls["inspector_panel_refresh"] = func() -> void: ip.refresh()
		calls["inspector_force_rerender"] = func() -> void: ip._render()
	calls["hud_refresh"] = func() -> void: _scene._hud.refresh()
	if res != null and res.results_panel() != null:
		var rp := res.results_panel()
		calls["results_panel_refresh"] = func() -> void: rp.refresh()
	if res != null and res.reason_panel() != null:
		var qp := res.reason_panel()
		calls["reason_panel_refresh"] = func() -> void: qp.refresh()
		out["reason_panel_rows"] = qp.find_roles("").size() if qp.has_method("find_roles") else -1
	for key: String in calls:
		var t0 := Time.get_ticks_usec()
		for _i in 20:
			(calls[key] as Callable).call()
		out[key] = snappedf((Time.get_ticks_usec() - t0) / 20000.0, 0.01)
	return out


func _summ(rows: Array) -> Dictionary:
	var out := {"frames": rows.size()}
	if rows.is_empty():
		return out
	var keys := ["proc_ms", "total_ms", "drive_ms", "poll_ms", "sync_ms", "view_ms", "life_ms"]
	for key in keys:
		var sum := 0.0
		var mx := 0.0
		var cnt := 0
		for r: Dictionary in rows:
			if not r.has(key):
				continue
			sum += float(r[key])
			mx = maxf(mx, float(r[key]))
			cnt += 1
		out["avg_" + key] = snappedf(sum / maxf(cnt, 1), 0.01)
		out["max_" + key] = snappedf(mx, 0.01)
	var ticks := 0
	var events := 0
	var views := 0
	var lbuilds := 0
	for r: Dictionary in rows:
		lbuilds += int(r.get("life_builds", 0))
		ticks += int(r["ticks"])
		events += int(r["events"])
		views += int(r["views"])
	out["ticks"] = ticks
	out["events"] = events
	out["view_builds"] = views
	out["life_builds"] = lbuilds
	out["tick_end"] = int(rows[rows.size() - 1]["tick"])
	out["mon"] = rows[rows.size() - 1].get("mon", {})
	var cal_sum := 0.0
	var cal_max := 0.0
	var cal_n := 0
	for r: Dictionary in rows:
		var m: Dictionary = r.get("mon", {})
		if m.has("cal_ms"):
			cal_sum += float(m["cal_ms"])
			cal_max = maxf(cal_max, float(m["cal_ms"]))
			cal_n += 1
	out["cal_avg_max"] = [snappedf(cal_sum / maxf(cal_n, 1), 0.001), snappedf(cal_max, 0.01)]
	out["t_unix"] = snappedf(Time.get_unix_time_from_system(), 1.0)
	var np_sum := {}
	var np_max := {}
	for r: Dictionary in rows:
		var np: Dictionary = r.get("np", {})
		for key: String in np:
			np_sum[key] = float(np_sum.get(key, 0.0)) + float(np[key])
			np_max[key] = maxf(float(np_max.get(key, 0.0)), float(np[key]))
	if not np_sum.is_empty():
		var rep := {}
		for key: String in np_sum:
			rep[key] = [snappedf(float(np_sum[key]) / rows.size(), 0.01), snappedf(float(np_max[key]), 0.1)]
		out["np_avg_max"] = rep
	return out


func _rounded(d: Dictionary) -> Dictionary:
	var out := {}
	for key: String in d:
		if d[key] is float:
			out[key] = snappedf(float(d[key]), 0.01)
		elif d[key] is Dictionary:
			out[key] = _rounded(d[key])
		else:
			out[key] = d[key]
	return out


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
