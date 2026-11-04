extends SceneTree
## Altyapı kapasitesi (yol) -> SİYASET yan etkisi ölçümü. Oynanabilir Ismeral sim'i (t043b_real_world_probe.gd ile aynı
## kurulum: gerçek dünya + T0 yerleşimi + PlayableEconomy + PlayablePolitics) N gün koşar; yük/kapasite oranı, kesim
## sinyalleri/şikâyet defteri, siyasi olaylar, gündem ve bildirim şeridine düşecek olay akışını sayar.
## Çalıştır (tek koşu = tek süreç):
##   tools/godot.sh --headless --path . --script res://tests/sim/perf/infra_politics_probe.gd -- \
##       [--infra-cap=-1|0] [--flow=none|road_plan] [--days=400] [--sim-seed=N] [--rank=0] [--plan-n=12]
## --infra-cap: `playable_economy.json infra_free_units_max` geçersiz kılma (-1 eski, 0 mevcut); --flow: none = oyuncu
## eylemi yok; road_plan = ısınma sonrası yol + imar planı (D-008). Çıktı: `INFRA_POLITICS ` + JSON satırı.
## Salt ölçüm; kabul kararı yok.

const DATA_DIR := "res://data/world/ismeral"
const NETWORK_PATH := "res://data/world/ismeral/network.json"
const SETTLEMENT_PATH := "res://data/world/ismeral/settlement.json"
const CANDIDATES := 600
const NEAR_M := 150.0
const WARM_DAYS := 30
const MIN_VACANT := 6
const SAMPLE_EVERY := 25

var _args: Dictionary = {}


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	_args = _parse(OS.get_cmdline_user_args())
	var days := int(_args.get("days", "400"))
	var flow := str(_args.get("flow", "none"))
	var rank := int(_args.get("rank", "0"))
	var plan_n := int(_args.get("plan-n", "12"))
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
	var patch := {"decision": {"priority_review_enabled": 1}}
	if _args.has("infra-cap"):
		patch["playable"] = {"infra_free_units_max": int(_args["infra-cap"])}
	if _args.has("decision"):  # deney: --decision=anahtar:değer,...
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
	var ctx := PublicWorksContext.create(net, road_rules, PublicWorksConfig.load_default())
	var attached := facade.attach_public_works(ctx)
	PlayableBudget.attach(facade, attached)
	var projector := SimBuildingProjector.create(facade, settlement, SimBuildingMapping.load_default(), world_seed)
	var pump := SimBuildingPump.create(projector) if projector != null else null
	var occupied := {}
	for pid in stock.parcel_ids():
		occupied[int(pid)] = true
	var vacant: Array[ParcelView] = []
	for v in views:
		if not occupied.has(v.id):
			vacant.append(v)

	var out := {"infra_cap": int(_args.get("infra-cap", "0")), "flow": flow, "days": days, "sim_seed": sim_seed,
		"world_seed": world_seed, "requires_council": PlayablePolitics.config().council["requires_council"]}
	out["t0_regions"] = _regions(facade, cfg)
	var rec := _Rec.new()
	rec.facade = facade
	rec.pump = pump
	rec.handle = handle
	rec.cfg = cfg
	var road_tick := -1
	var plan_tick := -1
	var road_info := {}
	for d in days:
		if d == WARM_DAYS and flow == "road_plan":
			var cands := _candidates(net, road_rules, vacant, world_seed)
			if cands.is_empty() or rank >= cands.size():
				push_error("probe: aday yok")
				quit(2)
				return
			var cand: Dictionary = cands[rank]
			var pts: PackedVector2Array = cand["pts"]
			var near_ids := _nearest_vacant(vacant, pts, plan_n)
			var cm := PackedInt64Array()
			for p in pts:
				cm.append(roundi(p.x * 100.0))
				cm.append(roundi(p.y * 100.0))
			var res := facade.submit_command(SimCommand.public_work_road(cm, RoadDrawTool.ROAD_CLASS))
			road_info = {"status": String(res.status), "region": String(cand["region"]), "len_m": snappedf(cand["len"], 0.1)}
			road_tick = facade.current_tick()
			var res2 := facade.submit_command(SimCommand.zoning_propose(near_ids, &"zone.mixed"))
			road_info["plan_status"] = String(res2.status)
			road_info["plan_parcels"] = near_ids.size()
			plan_tick = facade.current_tick()
		rec.step()
		if d % SAMPLE_EVERY == SAMPLE_EVERY - 1 or d == 0:
			rec.sample(d + 1)
	out["road"] = road_info
	out["road_tick"] = road_tick
	out["plan_tick"] = plan_tick
	out["end_regions"] = _regions(facade, cfg)
	out.merge(rec.summary(days))
	out["state_hash"] = facade.state_hash()
	print("INFRA_POLITICS ", JSON.stringify(out))
	quit(0)


## Bölge satırları: kod, yük, etkin kapasite, oran (pm), aşım günü.
func _regions(facade: SimFacadeImpl, cfg: EconomyConfig) -> Array:
	var out: Array = []
	for row in EconomyQuery.region_stats(facade.game_state(), cfg):
		out.append([String(row["code"]), int(row["infra_load"]), int(row["infra_cap"]), int(row["infra_load_pm"])])
	return out


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
		var res := RoadDraftCheck.check(net, PackedVector2Array([a, b]), RoadDrawTool.ROAD_CLASS, rules)
		if not bool(res["ok"]):
			continue
		var count := 0
		for v in vacant:
			if _dist_to_segment(v.center, a, b) <= NEAR_M:
				count += 1
		if count < MIN_VACANT:
			continue
		out.append({"pts": res["points"], "count": count, "len": res["length_m"], "region": _region_at(vacant, a),
				"order": n})
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


## Olay ve siyaset durumu toplayıcı.
class _Rec:
	extends RefCounted
	var facade: SimFacadeImpl = null
	var pump: SimBuildingPump = null
	var handle: PoliticsHandle = null
	var cfg: EconomyConfig = null
	var by_kind: Dictionary = {}
	var by_key: Dictionary = {}
	var by_prio: Dictionary = {0: 0, 1: 0, 2: 0}
	var strip_total: int = 0
	var unplanned_declines: int = 0
	var political_keys: Dictionary = {}
	var political_timeline: Array = []
	var samples: Array = []
	var max_load_pm: int = 0
	var max_signal: int = 0
	var max_grief: Dictionary = {}
	var max_satis: Dictionary = {}
	var overload_days_max: int = 0
	var agenda_opened: int = 0
	var votes_opened: int = 0
	var group_by_day: Dictionary = {}
	var max_burden: Dictionary = {}
	var _seq: int = 0

	func step() -> void:
		facade.advance(1)
		if pump != null:
			pump.frame(true, Callable(self, "_noop"))
			pump.frame(false, Callable(self, "_noop"))
		for e in facade.events_since(_seq):
			_seq = maxi(_seq, e.seq)
			var kind := String(e.kind)
			var key := String(e.message_key)
			by_kind[kind] = int(by_kind.get(kind, 0)) + 1
			by_key[key] = int(by_key.get(key, 0)) + 1
			if NotificationStrip.is_unplanned_decline(e):
				unplanned_declines += 1
			else:
				strip_total += 1
				by_prio[NotificationStrip.priority(e)] = int(by_prio[NotificationStrip.priority(e)]) + 1
			if kind == "group.reacted" or kind.begins_with("politics.") or kind.begins_with("council."):
				political_keys[key] = int(political_keys.get(key, 0)) + 1
				if political_timeline.size() < 60:
					political_timeline.append([e.tick, kind, key, str(e.args.get("topic", "")), int(e.args.get("intensity", 0)),
						str(e.subjects)])
			if kind == "group.reacted":
				group_by_day[e.tick] = true
			if kind == "politics.agenda_opened":
				agenda_opened += 1
			if kind == "council.vote_opened":
				votes_opened += 1
		_track()

	func _noop(_c: Variant, _v: Variant) -> void:
		pass

	func _track() -> void:
		var state := facade.game_state()
		for row in EconomyQuery.region_stats(state, cfg):
			max_load_pm = maxi(max_load_pm, int(row["infra_load_pm"]))
			max_signal = maxi(max_signal, int(BlocSignals.of_region(row, 0)["infra_stress"]))
		if not PoliticsState.is_initialized(state):
			return
		var pol: Dictionary = PoliticsState.data(state)
		for code: String in pol["service"]["overload_days"]:
			overload_days_max = maxi(overload_days_max, int(pol["service"]["overload_days"][code]))
		for key in PoliticsState.bloc_keys(state):
			var bloc: Dictionary = pol["blocs"][key]
			max_grief[key] = maxi(int(max_grief.get(key, 0)), int(bloc["G"]))
			max_satis[key] = maxi(int(max_satis.get(key, 0)), int(bloc["S"]))
			max_burden[key] = maxi(int(max_burden.get(key, 0)), int(bloc["signals"].get("construction_burden", 0)))

	func sample(day: int) -> void:
		var state := facade.game_state()
		var row_max := 0
		for row in EconomyQuery.region_stats(state, cfg):
			row_max = maxi(row_max, int(row["infra_load_pm"]))
		var blocs := {}
		if PoliticsState.is_initialized(state):
			var pol: Dictionary = PoliticsState.data(state)
			for key in PoliticsState.bloc_keys(state):
				var b: Dictionary = pol["blocs"][key]
				var ev: Dictionary = b["eval"]
				blocs[key] = [int(b["G"]), int(b["S"]), str(ev["reaction"]), str(ev["tier"]), int(ev["intensity"])]
		samples.append([day, row_max, blocs])

	func summary(days: int) -> Dictionary:
		return {
			"events_total": _seq, "events_per_day": snappedf(float(_seq) / maxf(days, 1), 0.01),
			"strip_eligible_total": strip_total, "strip_eligible_per_day": snappedf(float(strip_total) / maxf(days, 1), 0.01),
			"strip_unplanned_declines_hidden": unplanned_declines, "strip_by_priority": by_prio,
			"by_kind": by_kind, "political_event_keys": political_keys,
			"group_reacted_days": group_by_day.size(), "agenda_opened": agenda_opened, "council_votes_opened": votes_opened,
			"max_infra_load_pm": max_load_pm, "max_infra_stress_signal": max_signal,
			"max_service_overload_days": overload_days_max, "max_grievance": max_grief, "max_satisfaction": max_satis,
			"max_construction_burden_signal": max_burden,
			"political_timeline_first60": political_timeline, "samples": samples,
			"politics_counters": PoliticsState.data(facade.game_state()).get("counters", {}),
		}
