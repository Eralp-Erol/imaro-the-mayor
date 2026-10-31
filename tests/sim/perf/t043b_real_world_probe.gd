extends SceneTree
## T-043B GERÇEK dünya ölçümü: oynanabilir Ismeral sim'i (playable.gd `_start_sim` ile aynı kurulum: gerçek dünya + ağ
## + T0 yerleşimi + PlayableEconomy/PlayablePolitics + yol komutları + gösterge bütçe + SimBuildingProjector)
## başsız kurulur;
## yol çiz (public_work.road), çevre boş parsellere imar öner (zoning.propose), plan yürürlüğe girince günleri say.
## Duvar saati yalnız ölçümdür (makineye bağlı; kabul kararı değil). Render yok: kare süresi ölçülmez, yalnız sim tick'i
## (+ projector dilimi).
## Çalıştır (tek koşu = tek süreç; Godot başına tek koşu):
##   tools/godot.sh --headless --path . --script res://tests/sim/perf/t043b_real_world_probe.gd -- \
##       [--queue=1|0] [--rank=0] [--plan-n=12] [--order=road_first|plan_first|plan_only|road_only] [--sim-seed=N]
##       [--days=260] [--profile] [--list]
## --queue: decision.priority_review_enabled (varsayılan 1 = oynanabilir veri); --rank: aday yol sırası (0 = en çok boş
## parsel); --plan-n: tek imar teklifindeki parsel sayısı (yola en yakın boş parseller); --order: plan_only = yol yok,
## road_only = plan yok (kontrol); --profile: tick'i sistem sistem zamanlar (aynı adımlar, `Simulation.step` kopyası);
## --list: yalnız aday yolları yazar.
## Çıktı: `T043B_REAL ` + JSON satırı.

const DATA_DIR := "res://data/world/ismeral"
const NETWORK_PATH := "res://data/world/ismeral/network.json"
const SETTLEMENT_PATH := "res://data/world/ismeral/settlement.json"
const CANDIDATES := 600
const NEAR_M := 150.0
const WARM_DAYS := 30
const AFTER_PLAN_DAYS := 5
const MIN_VACANT := 6
const KEY_APPLIED := &"event.zoning.applied"
const KEY_STARTED := &"event.construction.started"
const KEY_COMPLETED := &"event.construction.completed"
const KEY_ROAD := &"event.road.built"
const SECS_PER_DAY_AT_4 := 0.25

var _args: Dictionary = {}


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	_args = _parse(OS.get_cmdline_user_args())
	var queue_on := int(_args.get("queue", "1")) != 0
	var rank := int(_args.get("rank", "0"))
	var plan_n := int(_args.get("plan-n", "12"))
	var days := int(_args.get("days", "260"))
	var order := str(_args.get("order", "road_first"))
	var t_setup := Time.get_ticks_usec()
	var control := WorldControlData.load_dir(DATA_DIR)
	var world_seed := int(control["world"]["default_seed"])
	var sim_seed := int(_args.get("sim-seed", str(world_seed)))
	var world := WorldGenerator.generate(control, world_seed, {})
	var net_control: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(NETWORK_PATH))
	var rules: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SETTLEMENT_PATH))
	var net := NetworkGenerator.generate(world, net_control, world_seed)
	var loaded := SettlementTable.load_game_table()
	var settlement := T0Settlement.generate_detailed(world, net, loaded["table"], world_seed, rules)
	var views := _views(net)
	var source := ListParcelSource.create(&"ismeral", views)
	var stock := PlayableStock.from_columns(settlement.columns)
	var patch := {"decision": {"priority_review_enabled": 1 if queue_on else 0}}
	if _args.has("infra-cap"):  # `infra_free_units_max` geçersiz kılma (-1 = sınırsız = eski davranış)
		patch["playable"] = {"infra_free_units_max": int(_args["infra-cap"])}
	if _args.has("decision"):  # deney: --decision=anahtar:değer,anahtar:değer (ekonomi karar yaması)
		for pair in str(_args["decision"]).split(","):
			var kv := pair.split(":")
			(patch["decision"] as Dictionary)[kv[0]] = int(kv[1])
	var cfg := PlayableEconomy.config_for(views, stock, patch)
	var handle := PoliticsBootstrap.create(sim_seed, source, cfg, stock, null, PlayablePolitics.config())
	if handle == null:
		push_error("probe: sim kurulamadı")
		quit(2)
		return
	var facade := handle.facade as SimFacadeImpl
	var road_rules := RoadDraftRules.load_path(NETWORK_PATH)
	var works_cfg := PublicWorksConfig.load_default()
	if _args.has("km-units"):  # deney: yol sınıfı başına km birim katsayısı
		works_cfg = PublicWorksConfig.from_dict({"classes": {"local": {"infra_units_per_km": int(_args["km-units"])}}})
	var ctx := PublicWorksContext.create(net, road_rules, works_cfg)
	var attached := facade.attach_public_works(ctx)
	var budget := PlayableBudget.attach(facade, attached)
	var projector := SimBuildingProjector.create(facade, settlement, SimBuildingMapping.load_default(), world_seed)
	var pump := SimBuildingPump.create(projector) if projector != null else null
	var setup_ms := (Time.get_ticks_usec() - t_setup) / 1000.0
	var occupied := {}
	for pid in stock.parcel_ids():
		occupied[int(pid)] = true
	var vacant: Array[ParcelView] = []
	for v in views:
		if not occupied.has(v.id):
			vacant.append(v)
	var cands := _candidates(net, road_rules, vacant, world_seed)
	if _args.has("list"):
		for k in mini(cands.size(), 15):
			var c: Dictionary = cands[k]
			print("CAND rank=%d vacant_near=%d region=%s len=%.0f pts=%s" % [k, c["count"], c["region"], c["len"],
					str(c["pts"])])
		quit(0)
		return
	if cands.is_empty() or rank >= cands.size():
		push_error("probe: aday yok (rank=%d, aday=%d)" % [rank, cands.size()])
		quit(2)
		return
	var cand: Dictionary = cands[rank]
	var pts: PackedVector2Array = cand["pts"]
	var near_ids := _nearest_vacant(vacant, pts, plan_n)
	var out := {
		"task": "T-043B-real", "queue": queue_on, "rank": rank, "order": order, "world_seed": world_seed,
		"sim_seed": sim_seed, "parcels": views.size(), "t0_stock_parcels": stock.parcel_ids().size(),
		"vacant_parcels": vacant.size(),
		"setup_ms": snappedf(setup_ms, 0.1), "roads_attached": attached, "budget_attached": budget,
		"road_region": String(cand["region"]), "road_len_m": snappedf(float(cand["len"]), 0.1),
		"vacant_within_150m": cand["count"], "plan_parcels": near_ids.size(),
		"max_reviews_per_tick": cfg.p("max_reviews_per_tick"),
		"priority_review_enabled": cfg.p("priority_review_enabled"),
	}
	var h0 := Time.get_ticks_usec()
	net.graph_hash()
	out["graph_hash_ms"] = snappedf((Time.get_ticks_usec() - h0) / 1000.0, 0.1)
	var cm := PackedInt64Array()
	for p in pts:
		cm.append(roundi(p.x * 100.0))
		cm.append(roundi(p.y * 100.0))
	var rec := _Recorder.new()
	rec.facade = facade
	rec.pump = pump
	rec.profile = _args.has("profile")
	# 1) ısınma (T0 stoku ile yaşayan dünya)
	for _d in WARM_DAYS:
		rec.step("warm")
	out["infra_before"] = _infra_rows(facade, cfg, cand["region"], near_ids)
	var tick_road := -1
	var tick_plan_sent := -1
	if order == "road_first":
		tick_road = _send_road(rec, cm, out)
		tick_plan_sent = _send_plan(rec, near_ids, out)
	elif order == "plan_only":
		tick_plan_sent = _send_plan(rec, near_ids, out)
	elif order == "road_only":
		tick_road = _send_road(rec, cm, out)
	else:
		tick_plan_sent = _send_plan(rec, near_ids, out)
		# planın yürürlüğe girmesini bekle, sonra yol
		var guard := 0
		while rec.first_tick(KEY_APPLIED) < 0 and guard < 120:
			rec.step("wait_plan")
			guard += 1
		tick_road = _send_road(rec, cm, out)
	# 2) plan parsellerinin hepsi tamamlanana (ya da `days`) kadar
	var finish_extra := 0
	for _d in days:
		rec.step("run")
		if not near_ids.is_empty() and rec.completed_in(near_ids) >= near_ids.size():
			finish_extra += 1
			if finish_extra >= AFTER_PLAN_DAYS:
				break
	var applied := rec.first_tick(KEY_APPLIED)
	var road_ev := rec.first_tick(KEY_ROAD)
	var enabling := maxi(applied, road_ev)  # ikisi de tamamlanınca zincir kurulu (yol+plan)
	if order == "plan_only":
		enabling = applied
	elif order == "road_only":
		enabling = road_ev
	var started := rec.first_tick_in(KEY_STARTED, near_ids, enabling)
	var completed := rec.first_tick_in(KEY_COMPLETED, near_ids, enabling)
	out["plan_started_days"] = rec.days_in(KEY_STARTED, near_ids, enabling)
	out["plan_completed_days"] = rec.days_in(KEY_COMPLETED, near_ids, enabling)
	out["any_started_days_global"] = rec.days_any(KEY_STARTED, enabling).slice(0, 12)
	out["tick_road_sent"] = tick_road
	out["tick_plan_sent"] = tick_plan_sent
	out["tick_road_event"] = road_ev
	out["tick_plan_applied"] = applied
	out["tick_enabling"] = enabling
	out["first_construction_started_tick"] = started
	out["first_building_completed_tick"] = completed
	out["days_to_first_construction"] = started - enabling if started >= 0 else -1
	out["days_to_first_building"] = completed - enabling if completed >= 0 else -1
	out["real_seconds_at_4_days_per_sec"] = {
		"first_construction": snappedf((started - enabling) * SECS_PER_DAY_AT_4, 0.01) if started >= 0 else -1.0,
		"first_building": snappedf((completed - enabling) * SECS_PER_DAY_AT_4, 0.01) if completed >= 0 else -1.0,
	}
	out["infra_after"] = _infra_rows(facade, cfg, cand["region"], near_ids)
	out["plan_detail"] = _plan_detail(facade, near_ids)
	out["events_total"] = rec.counts
	out["plan_parcel_started"] = rec.started_in(near_ids)
	out["plan_parcel_completed"] = rec.completed_in(near_ids)
	out["profile"] = rec.profile_summary()
	out["economy_totals"] = EconomyQuery.totals(facade.game_state())
	out["timing_ms"] = rec.timing_summary()
	out["trigger_ticks_ms"] = rec.trigger_ms
	out["end_tick"] = facade.current_tick()
	out["state_hash"] = facade.state_hash()
	print("T043B_REAL ", JSON.stringify(out))
	quit(0)


## Yol bölgesinin altyapı satırı (etkin kapasite, bonus, yük) + planın sim önizlemesi (toplam altyapı birimi).
func _infra_rows(facade: SimFacadeImpl, cfg: EconomyConfig, region: StringName,
		plan_ids: PackedInt64Array) -> Dictionary:
	var out := {}
	for row in EconomyQuery.region_stats(facade.game_state(), cfg):
		if row["code"] == region:
			out = {"infra_cap": row["infra_cap"], "infra_bonus": row["infra_bonus"], "infra_load": row["infra_load"]}
	var preview := facade.plan_preview(plan_ids, &"zone.mixed")
	if preview != null and preview.ok:
		out["plan_total_infra_units"] = preview.total_infra_units
		out["plan_total_units"] = preview.total_units
	return out


## Plan parsellerinin son kararı (gerekçe kaydı: karar anahtarı + sonuç) ve potansiyel birimi.
func _plan_detail(facade: SimFacadeImpl, ids: PackedInt64Array) -> Array:
	var preview := facade.plan_preview(ids, &"zone.mixed")
	var units := {}
	if preview != null and preview.ok:
		for row: Dictionary in preview.parcels:
			units[int(row["id"])] = int(row["units"])
	var out: Array = []
	for id in ids:
		var recs := facade.reasons_for(SimContract.parcel_ref(int(id)))
		var last := ""
		if not recs.is_empty():
			var r: ReasonRecord = recs[recs.size() - 1]
			last = "%s/%s" % [String(r.decision_key), String(r.outcome)]
		out.append([int(id), int(units.get(int(id), 0)), last])
	return out


func _send_road(rec: _Recorder, cm: PackedInt64Array, out: Dictionary) -> int:
	var t0 := Time.get_ticks_usec()
	var res := rec.facade.submit_command(SimCommand.public_work_road(cm, RoadDrawTool.ROAD_CLASS))
	var submit_ms := (Time.get_ticks_usec() - t0) / 1000.0
	out["road_status"] = String(res.status)
	out["road_reason"] = String(res.reason_key)
	out["road_submit_ms"] = snappedf(submit_ms, 0.01)
	var sent := rec.facade.current_tick()
	rec.step("trigger_road")
	return sent


func _send_plan(rec: _Recorder, ids: PackedInt64Array, out: Dictionary) -> int:
	var t0 := Time.get_ticks_usec()
	var res := rec.facade.submit_command(SimCommand.zoning_propose(ids, &"zone.mixed"))
	out["plan_status"] = String(res.status)
	out["plan_reason"] = String(res.reason_key)
	out["plan_submit_ms"] = snappedf((Time.get_ticks_usec() - t0) / 1000.0, 0.01)
	var sent := rec.facade.current_tick()
	rec.step("trigger_plan")
	return sent


## Oynanabilir parsel görünümleri (`playable.gd _parcel_views` ile aynı kural).
func _views(net: WorldNetwork) -> Array[ParcelView]:
	var out: Array[ParcelView] = []
	var src: Variant = net.parcels
	var items: Array = src.values() if src is Dictionary else Array(src)
	for item in items:
		var wp := item as WorldParcel
		if wp == null or wp.region_code == &"":
			continue
		var v := ParcelView.new()
		v.id = wp.id
		v.region_code = wp.region_code
		v.center = wp.centroid
		v.area_m2 = int(wp.area)
		v.zone = &"zone.residential"
		out.append(v)
	return out


## Aday yollar: ağ kenarından başlayan 60-250 m taslaklar; RoadDraftCheck geçerli olanlar, 150 m içindeki BOŞ parsel
## sayısına göre sıralı (eşitlikte üretim sırası). Ağı değiştirmez.
func _candidates(net: WorldNetwork, rules: RoadDraftRules, vacant: Array[ParcelView], world_seed: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = NetworkRules.stream_seed(world_seed, "t043b_real_probe")
	var ids: Array = net.edges.keys()
	ids.sort()
	var out: Array = []
	for n in CANDIDATES:
		var e: WorldRoadEdge = net.edges[ids[rng.randi() % ids.size()]]
		var a := net.node_pos(e.a).lerp(net.node_pos(e.b), rng.randf())
		var b := a + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(60.0, 250.0)
		var pts := PackedVector2Array([a, b])
		var res := RoadDraftCheck.check(net, pts, RoadDrawTool.ROAD_CLASS, rules)
		if not bool(res["ok"]):
			continue
		var count := 0
		for v in vacant:
			if _dist_to_segment(v.center, a, b) <= NEAR_M:
				count += 1
		if count < MIN_VACANT:
			continue
		var region := _region_at(vacant, a)
		out.append({"pts": res["points"], "count": count, "len": res["length_m"], "region": region, "order": n})
	out.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
		if int(x["count"]) != int(y["count"]):
			return int(x["count"]) > int(y["count"])
		return int(x["order"]) < int(y["order"]))
	return out


func _region_at(vacant: Array[ParcelView], p: Vector2) -> StringName:
	var best := &""
	var best_d := INF
	for v in vacant:
		var d := v.center.distance_squared_to(p)
		if d < best_d:
			best_d = d
			best = v.region_code
	return best


func _nearest_vacant(vacant: Array[ParcelView], pts: PackedVector2Array, count: int) -> PackedInt64Array:
	var scored: Array = []
	for v in vacant:
		var d := _dist_to_segment(v.center, pts[0], pts[pts.size() - 1])
		if d <= NEAR_M:
			scored.append([d, v.id])
	scored.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0] or (x[0] == y[0] and x[1] < y[1]))
	var out := PackedInt64Array()
	for k in mini(count, scored.size()):
		out.append(int(scored[k][1]))
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


## Tick sürelerini ve olayları toplar.
class _Recorder:
	extends RefCounted
	const KEY_STARTED_S := "event.construction.started"
	const KEY_COMPLETED_S := "event.construction.completed"
	var facade: SimFacadeImpl = null
	var pump: SimBuildingPump = null
	var profile: bool = false
	var all_ms: Array[float] = []
	var all_ticks: Array[int] = []
	var all_labels: Array[String] = []
	var trigger_ms: Dictionary = {}
	var counts: Dictionary = {}
	var _seq: int = 0
	var _events: Dictionary = {}
	var _proj_ms: Array[float] = []
	var _sys_max: Dictionary = {}
	var _sys_month_max: Dictionary = {}

	func step(label: String) -> void:
		var t0 := Time.get_ticks_usec()
		if profile:
			_profiled_step()
		else:
			facade.advance(1)
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		all_ms.append(ms)
		all_ticks.append(facade.current_tick())
		all_labels.append(label)
		if label.begins_with("trigger"):
			trigger_ms[label] = snappedf(ms, 0.01)
		if pump != null:
			var t1 := Time.get_ticks_usec()
			pump.frame(true, Callable(self, "_noop"))
			pump.frame(false, Callable(self, "_noop"))
			_proj_ms.append((Time.get_ticks_usec() - t1) / 1000.0)
		for e in facade.events_since(_seq):
			_seq = maxi(_seq, e.seq)
			var key := String(e.message_key)
			counts[key] = int(counts.get(key, 0)) + 1
			if not _events.has(key):
				_events[key] = []
			(_events[key] as Array).append([e.tick, String(e.subjects[0]) if e.subjects.size() > 0 else ""])

	## `Simulation.step` ile AYNI sıra (komutlar, günlük, aylık, üç aylık); yalnız sistem başına süre ölçer.
	func _profiled_step() -> void:
		var sim := facade.simulation()
		var state := facade.game_state()
		var t0 := Time.get_ticks_usec()
		Commands.process_pending(state, sim._handlers)
		_note("commands", t0, state.tick + 1, false)
		state.tick += 1
		for system: SimSystem in sim._systems:
			var t1 := Time.get_ticks_usec()
			system.on_daily(state)
			_note("%s.daily" % system.system_id(), t1, state.tick, false)
		if state.is_month_boundary():
			for system: SimSystem in sim._systems:
				var t2 := Time.get_ticks_usec()
				system.on_monthly(state)
				_note("%s.monthly" % system.system_id(), t2, state.tick, true)
		if state.is_quarter_boundary():
			for system: SimSystem in sim._systems:
				var t3 := Time.get_ticks_usec()
				system.on_quarterly(state)
				_note("%s.quarterly" % system.system_id(), t3, state.tick, true)

	func _note(name: String, t0: int, tick: int, month: bool) -> void:
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		var book := _sys_month_max if month else _sys_max
		if tick > 1 and ms > float((book.get(name, [0.0, 0])[0])):
			book[name] = [ms, tick]

	func profile_summary() -> Dictionary:
		var out := {}
		for book: Dictionary in [_sys_max, _sys_month_max]:
			for name: String in book:
				if float(book[name][0]) >= 0.5:
					out[name] = {"max_ms": snappedf(float(book[name][0]), 0.01), "tick": book[name][1]}
		return out

	func _noop(_columns: Variant, _version: Variant) -> void:
		pass

	func first_tick(key: StringName) -> int:
		var list: Array = _events.get(String(key), [])
		return int(list[0][0]) if not list.is_empty() else -1

	## `key` olayının `ids` parsellerindeki ilk tick'i (>= from_tick); ids boşsa tüm parseller. Yoksa -1.
	func first_tick_in(key: StringName, ids: PackedInt64Array, from_tick: int) -> int:
		var ticks := _ticks_in(String(key), ids, from_tick)
		return ticks[0] if not ticks.is_empty() else -1

	func days_in(key: StringName, ids: PackedInt64Array, from_tick: int) -> Array:
		var out: Array = []
		for t in _ticks_in(String(key), ids, from_tick):
			out.append(t - from_tick)
		return out

	func days_any(key: StringName, from_tick: int) -> Array:
		return days_in(key, PackedInt64Array(), from_tick)

	func started_in(ids: PackedInt64Array) -> int:
		return _ticks_in(KEY_STARTED_S, ids, 0).size()

	func completed_in(ids: PackedInt64Array) -> int:
		return _ticks_in(KEY_COMPLETED_S, ids, 0).size()

	func _ticks_in(key: String, ids: PackedInt64Array, from_tick: int) -> Array[int]:
		var wanted := {}
		for id in ids:
			wanted[String(SimContract.parcel_ref(int(id)))] = true
		var out: Array[int] = []
		for item: Array in _events.get(key, []):
			if int(item[0]) >= from_tick and (ids.is_empty() or wanted.has(String(item[1]))):
				out.append(int(item[0]))
		return out

	func timing_summary() -> Dictionary:
		var s := all_ms.duplicate()
		s.sort()
		var sum := 0.0
		for v in s:
			sum += v
		var p := _proj_ms.duplicate()
		p.sort()
		var psum := 0.0
		for v in p:
			psum += v
		var order: Array = range(all_ms.size())
		order.sort_custom(func(x: int, y: int) -> bool: return all_ms[x] > all_ms[y])
		var slowest: Array = []
		for k in mini(8, order.size()):
			var i: int = order[k]
			slowest.append({"tick": all_ticks[i], "ms": snappedf(all_ms[i], 0.01), "label": all_labels[i]})
		var steady: Array[float] = []
		for i in all_ms.size():
			if all_ticks[i] > 1:  # ilk tick (tek seferlik başlatma) hariç
				steady.append(all_ms[i])
		steady.sort()
		var steady_sum := 0.0
		for v in steady:
			steady_sum += v
		return {
			"ticks": s.size(), "mean_ms": snappedf(sum / s.size(), 0.01), "median_ms": snappedf(s[s.size() / 2], 0.01),
			"p95_ms": snappedf(s[int(s.size() * 0.95)], 0.01), "max_ms": snappedf(s[s.size() - 1], 0.01),
			"slowest": slowest, "over_16_6": s.filter(func(v: float) -> bool: return v > 16.6).size(),
			"steady_mean_ms": snappedf(steady_sum / steady.size(), 0.01),
			"steady_max_ms": snappedf(steady[steady.size() - 1], 0.01),
			"steady_p95_ms": snappedf(steady[int(steady.size() * 0.95)], 0.01),
			"steady_over_16_6": steady.filter(func(v: float) -> bool: return v > 16.6).size(),
			"projector_pair_mean_ms": snappedf(psum / maxf(p.size(), 1.0), 0.01),
			"projector_pair_max_ms": snappedf(p[p.size() - 1], 0.01) if not p.is_empty() else 0.0,
		}
