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
	_scene.set_process(false)  # kareleri biz süreriz (sabit dt)
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
	_scene._process(dt)
	var proc_us := Time.get_ticks_usec() - t0
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
	}
	_prev = cur
	row["_frame_start_us"] = t0
	_rows.append(row)
	# Önceki karenin toplam süresi (engine payı dahil) bir sonraki satırda tamamlanır.
	if _rows.size() >= 2:
		var p := _rows[_rows.size() - 2]
		p["total_ms"] = (t0 - int(p["_frame_start_us"])) / 1000.0


func _snap() -> Dictionary:
	var s: Dictionary = _scene.sim_stats
	return {
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
	for v in vacant:
		var d := _dist_to_segment(v.center, pts[0], pts[pts.size() - 1])
		if d <= NEAR_M:
			scored.append([d, v.id])
	scored.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0] or (x[0] == y[0] and x[1] < y[1]))
	for k in mini(12, scored.size()):
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
	var keys := ["proc_ms", "total_ms", "drive_ms", "poll_ms", "sync_ms", "view_ms"]
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
	for r: Dictionary in rows:
		ticks += int(r["ticks"])
		events += int(r["events"])
		views += int(r["views"])
	out["ticks"] = ticks
	out["events"] = events
	out["view_builds"] = views
	out["tick_end"] = int(rows[rows.size() - 1]["tick"])
	return out


func _rounded(d: Dictionary) -> Dictionary:
	var out := {}
	for key: String in d:
		out[key] = snappedf(float(d[key]), 0.01) if d[key] is float else d[key]
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
