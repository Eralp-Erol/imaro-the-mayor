# gdlint:disable=max-line-length,max-file-lines
extends SceneTree
## T-077 · M3 taban ölçümü (QA, 2026-11-07). Tek kullanımlık ölçüm betiği; oyun/sim kodunu DEĞİŞTİRMEZ.
## Kurulum = oyunun `_start_sim` bağı (gerçek Ismeral + ağ + T0 yerleşimi + PlayableEconomy/PlayablePolitics + yol komutları
## + kamulaştırma köprüsü + gösterge bütçe; `tests/sim/perf/qa_world_support.gd`). SimBuildingProjector TAKILMAZ (görünüm tarafı).
## Duvar saati YALNIZ ölçümdür; sim durumuna girmez.
##
## Çalıştır (tek koşu = tek süreç, tek senaryo; sarmalayıcı: experiments/m3_baseline/run_baseline.sh):
##   tools/godot.sh --headless --path . --script res://experiments/m3_baseline/m3_baseline_probe.gd -- \
##       --mode=player|none [--sim-seed=N] [--years=5] [--out=<yol.json>] [--no-diff] [--profile] [--region=D2] [--jurisdiction-all]
## --mode=player: D2'de betikli oyuncu girdisi (1. yıl 3 yol + 3 imar, sonraki yıllar 1 yol + 1 imar, gün 30 + 360k;
##   yol = RoadDraftCheck geçen, D2 içinde, 150 m içinde en çok boş parselli aday; imar = yola en yakın 8 boş D2 parseli, zone.mixed).
## --mode=none: oyuncu girdisi YOK (olumsuz kontrol).
## --no-diff: günlük next_review farkı (bölge başına değerlendirme sayımı) kapalı = ölçüm yükü en düşük koşu.
## --profile: tick'i sistem sistem zamanlar (`Simulation.step` kopyası; toplam süreyi biraz şişirir).
## Çıktı: `M3_BASE ` + JSON satırı ve --out dosyası.

const Support := preload("res://tests/sim/perf/qa_world_support.gd")
const DAYS_PER_YEAR := 360  # core_config: 12 ay x 30 gün
const DAYS_PER_MONTH := 30
const DAYS_PER_QUARTER := 90
const ACTION_DAY := 30
const NEAR_M := 150.0
const POOL := 300
const MIN_VACANT := 6
const PLAN_N := 8
const KEYS := ["event.investor.develop", "event.investor.declined", "event.construction.started",
	"event.construction.completed", "event.zoning.applied", "event.road.built"]

var _args: Dictionary = {}
var _w: Support.WorldCtx = null
var _s: Support.SimCtx = null
var _facade: SimFacadeImpl = null
var _codes: Array[String] = []
var _region_idx: Dictionary = {}  # bölge kodu -> indeks
var _ref_region: Dictionary = {}  # parsel ref metni -> bölge indeksi
var _idx_region: PackedInt32Array = PackedInt32Array()  # ekonomi sütun indeksi -> bölge indeksi
var _seq: int = 0
var _prev_nr: PackedInt32Array = PackedInt32Array()
var _use_diff: bool = true
var _profile: bool = false
var _player_region: String = "D2"  # --region=Dn (varsayılan D2 = oyunun yetki alanı)
# günlük ölçüm
var _ms: Array[float] = []
var _ms_tick: Array[int] = []
var _evals_day: Array[int] = []
var _cursor_adv: Array[int] = []
var _prev_evals: int = 0
var _prev_cursor: int = 0
var _n_parcels: int = 0
# sayaçlar: [yıl][anahtar][bölge]
var _ev: Dictionary = {}
var _decl_eval: Dictionary = {}  # [yıl][bölge] next_review artışı (= reddedilen değerlendirme)
var _prof: Dictionary = {}  # ad -> [toplam, sayı, maks, maks tick]
var _prof_month: Dictionary = {}
var _commands: Array = []


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	_args = _parse(OS.get_cmdline_user_args())
	var mode := str(_args.get("mode", "player"))
	var years := int(_args.get("years", "5"))
	_use_diff = not _args.has("no-diff")
	_profile = _args.has("profile")
	_player_region = str(_args.get("region", "D2"))
	var out_path := str(_args.get("out", ""))
	var t_setup := Time.get_ticks_usec()
	var control := WorldControlData.load_dir(Support.DATA_DIR)
	var world_seed := int(control["world"]["default_seed"])
	var sim_seed := int(_args.get("sim-seed", str(world_seed)))
	_w = Support.build_world(world_seed)
	_s = Support.new_sim(_w, sim_seed, true)
	if _s == null:
		push_error("m3_baseline: sim kurulamadı")
		quit(2)
		return
	_facade = _s.facade
	if _args.has("jurisdiction-all"):  # NE-OLUR deneyi: yol yetki kısıtı kapalı (oyunun verisi değil; qa_world_support.set_jurisdiction_all)
		_w.set_jurisdiction_all(true)
	var setup_s := (Time.get_ticks_usec() - t_setup) / 1.0e6
	var state := _facade.game_state()
	for v in _w.views:
		var code := String(v.region_code)
		if not _region_idx.has(code):
			_region_idx[code] = _codes.size()
			_codes.append(code)
	_codes.sort()
	_region_idx.clear()
	for k in _codes.size():
		_region_idx[_codes[k]] = k
	for v in _w.views:
		_ref_region[String(SimContract.parcel_ref(v.id))] = _region_idx[String(v.region_code)]
	var out := {
		"task": "T-077", "mode": mode, "world_seed": world_seed, "sim_seed": sim_seed, "years": years,
		"setup_s": snappedf(setup_s, 0.1), "regions": _codes, "sim_parcels": _w.views.size(), "use_diff": _use_diff,
		"profile": _profile, "player_region": _player_region, "jurisdiction_all": _args.has("jurisdiction-all"), "godot": Engine.get_version_info()["string"],
		"max_reviews_per_tick": _s.cfg.p("max_reviews_per_tick"), "review_period_days": _s.cfg.p("review_period_days"),
		"decline_backoff_days": _s.cfg.p("decline_backoff_days"), "unplanned_land_enabled": _s.cfg.p("unplanned_land_enabled"),
		"priority_review_enabled": _s.cfg.p("priority_review_enabled"), "max_starts_per_region_per_day": _s.cfg.p("max_starts_per_region_per_day"),
		"prescreen_demand_pm": _s.cfg.p("prescreen_demand_pm"),
	}
	# 1. tick (ekonomi durumu kurulur; tek seferlik başlatma maliyeti ayrı kaydedilir)
	_day()
	var d := EconomyState.data(state)
	if d.is_empty():
		push_error("m3_baseline: ekonomi durumu ilk tick sonrası boş")
		quit(2)
		return
	var ids: PackedInt64Array = d["parcel_ids"]
	_n_parcels = ids.size()
	_idx_region.resize(_n_parcels)
	for i in _n_parcels:
		_idx_region[i] = _region_idx[String(_w.region_of_parcel[int(ids[i])])]
	_prev_nr = (d["next_review"] as PackedInt32Array).duplicate()
	_prev_evals = int((d["totals"] as Dictionary)["evaluations"])
	_prev_cursor = int(d["review_cursor"])
	out["economy_parcels"] = _n_parcels
	out["census_start"] = _census(d)
	out["region_stats_start"] = _region_rows(state)
	out["parcels_by_region"] = _count_regions()
	# Isınma: ACTION_DAY'e kadar
	while _facade.current_tick() < ACTION_DAY:
		_day()
	if mode == "player":
		out["authority_probe"] = _authority_probe()
		_player_action(3, 0)
	var total_days := years * DAYS_PER_YEAR
	while _facade.current_tick() < total_days:
		var t := _facade.current_tick()
		if mode == "player" and t > ACTION_DAY and (t - ACTION_DAY) % DAYS_PER_YEAR == 0:
			_player_action(1, (t - ACTION_DAY) / DAYS_PER_YEAR)
		_day()
	d = EconomyState.data(state)
	out["end_tick"] = _facade.current_tick()
	out["commands"] = _commands
	out["census_end"] = _census(d)
	out["region_stats_end"] = _region_rows(state)
	out["vacant_last_code_end"] = _vacant_codes(d)
	out["events_by_year"] = _events_summary()
	out["declined_evals_by_year"] = _decl_eval_summary()
	out["totals"] = EconomyQuery.totals(state)
	out["budget"] = _budget_summary()
	out["timing_ms"] = _timing_summary()
	if _profile:
		out["profile_ms"] = _profile_summary()
	out["state_hash"] = _facade.state_hash()
	var text := JSON.stringify(out)
	print("M3_BASE ", text)
	if not out_path.is_empty():
		var f := FileAccess.open(out_path, FileAccess.WRITE)
		if f != null:
			f.store_string(JSON.stringify(out, "  "))
			f.close()
		else:
			push_error("m3_baseline: --out yazılamadı: %s" % out_path)
	quit(0)


# --- Günlük adım ve gözlem ---

func _day() -> void:
	var state := _facade.game_state()
	var t0 := Time.get_ticks_usec()
	if _profile:
		_profiled_step()
	else:
		_facade.advance(1)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	var tick := _facade.current_tick()
	_ms.append(ms)
	_ms_tick.append(tick)
	var year := (tick - 1) / DAYS_PER_YEAR
	var d := EconomyState.data(state)
	if not d.is_empty() and _n_parcels > 0:
		var evals := int((d["totals"] as Dictionary)["evaluations"])
		var cursor := int(d["review_cursor"])
		_evals_day.append(evals - _prev_evals)
		_cursor_adv.append((cursor - _prev_cursor + _n_parcels) % _n_parcels)
		_prev_evals = evals
		_prev_cursor = cursor
		if _use_diff:
			_diff_reviews(d, year)
	for e in _facade.events_since(_seq):
		_seq = maxi(_seq, e.seq)
		var key := String(e.message_key)
		if KEYS.has(key):
			var r := -1
			if e.subjects.size() > 0:
				r = int(_ref_region.get(String(e.subjects[0]), -1))
			_bump(_ev, year, key, r)


func _diff_reviews(d: Dictionary, year: int) -> void:
	var nr: PackedInt32Array = d["next_review"]
	if nr != _prev_nr:
		var bucket: Dictionary = _decl_eval.get(year, {})
		for i in _n_parcels:
			if nr[i] > _prev_nr[i]:
				var r := _idx_region[i]
				bucket[r] = int(bucket.get(r, 0)) + 1
		_decl_eval[year] = bucket
		_prev_nr = nr.duplicate()


func _bump(book: Dictionary, year: int, key: String, region: int) -> void:
	var by_year: Dictionary = book.get(year, {})
	var by_key: Dictionary = by_year.get(key, {})
	by_key[region] = int(by_key.get(region, 0)) + 1
	by_year[key] = by_key
	book[year] = by_year


## `Simulation.step` ile AYNI sıra; yalnız sistem başına süre ölçer.
func _profiled_step() -> void:
	var sim := _facade.simulation()
	var state := _facade.game_state()
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
	if tick <= 1:
		return
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	var book := _prof_month if month else _prof
	var cell: Array = book.get(name, [0.0, 0, 0.0, 0])
	cell[0] = float(cell[0]) + ms
	cell[1] = int(cell[1]) + 1
	if ms > float(cell[2]):
		cell[2] = ms
		cell[3] = tick
	book[name] = cell


# --- Oyuncu betiği (D2) ---

## `n_roads` yol + her yol için 1 imar önerisi. Her komut sonucu `_commands` içine yazılır.
func _player_action(n_roads: int, year: int) -> void:
	var picked: Array = []
	var cands := _road_candidates(year)
	for c: Dictionary in cands:
		if picked.size() >= n_roads:
			break
		var far_enough := true
		for p: Dictionary in picked:
			if (c["mid"] as Vector2).distance_to(p["mid"]) < 250.0:
				far_enough = false
		if far_enough:
			picked.append(c)
	if picked.size() < n_roads:
		_commands.append({"tick": _facade.current_tick(), "note": "aday yetersiz", "wanted": n_roads, "got": picked.size(),
			"candidates": cands.size()})
	for c: Dictionary in picked:
		var pts: PackedVector2Array = c["pts"]
		var rr := _facade.submit_command(SimCommand.public_work_road(Support.points_cm(pts), RoadDrawTool.ROAD_CLASS))
		_commands.append({"tick": _facade.current_tick(), "kind": "road", "status": String(rr.status), "reason": String(rr.reason_key),
			"len_m": snappedf(float(c["len"]), 0.1), "vacant_near": c["count"]})
		_day()
		var plan_ids := _nearest_vacant_d2(pts, PLAN_N)
		if plan_ids.is_empty():
			_commands.append({"tick": _facade.current_tick(), "kind": "zoning", "note": "boş parsel yok"})
			continue
		var pr := _facade.submit_command(SimCommand.zoning_propose(plan_ids, &"zone.mixed"))
		_commands.append({"tick": _facade.current_tick(), "kind": "zoning", "status": String(pr.status), "reason": String(pr.reason_key),
			"parcels": plan_ids.size()})
		_day()


## D2 içinde RoadDraftCheck geçen, 150 m içinde boş parseli en çok olan adaylar (azalan sayı; eşitlikte üretim sırası).
func _road_candidates(year: int) -> Array:
	var vacant := _vacant_centers(_player_region)
	var rng := RandomNumberGenerator.new()
	rng.seed = NetworkRules.stream_seed(_w.world_seed, "m3_baseline_player_%d" % year)
	var ids: Array = _w.net.edges.keys()
	ids.sort()
	var in_region: Array = []
	for eid: int in ids:
		var e: WorldRoadEdge = _w.net.edges[eid]
		if e.mode() != WorldNetwork.MODE_ROAD or e.road_class == WorldRoadEdge.CLASS_FERRY:
			continue
		var mid := (_w.net.node_pos(e.a) + _w.net.node_pos(e.b)) * 0.5
		if String(_w.net.rules.region_code_at(_w.world, mid)) == _player_region:
			in_region.append(eid)
	var out: Array = []
	if in_region.is_empty():
		return out
	for n in POOL:
		var e: WorldRoadEdge = _w.net.edges[in_region[rng.randi() % in_region.size()]]
		var a := _w.net.node_pos(e.a).lerp(_w.net.node_pos(e.b), rng.randf())
		var b := a + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(60.0, 250.0)
		var res := RoadDraftCheck.check(_w.net, PackedVector2Array([a, b]), RoadDrawTool.ROAD_CLASS, _w.road_rules)
		if not bool(res["ok"]):
			continue
		var count := 0
		for p: Vector2 in vacant:
			if _dist_to_segment(p, a, b) <= NEAR_M:
				count += 1
		if count < MIN_VACANT:
			continue
		out.append({"pts": res["points"], "count": count, "len": res["length_m"], "order": n, "mid": (a + b) * 0.5})
	out.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
		if int(x["count"]) != int(y["count"]):
			return int(x["count"]) > int(y["count"])
		return int(x["order"]) < int(y["order"]))
	return out


## Bölgedeki boş (plansız, VACANT) parsel merkezleri.
func _vacant_centers(region: String) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for v in _vacant_views(region):
		out.append(v.center)
	return out


func _vacant_views(region: String) -> Array[ParcelView]:
	var state := _facade.game_state()
	var d := EconomyState.data(state)
	var stage: PackedByteArray = d["stage"]
	var overlay := ParcelZoningSystem.overlay_ref(state)
	var out: Array[ParcelView] = []
	for v in _w.views:
		if String(v.region_code) != region or overlay.has(v.id):
			continue
		var i := EconomyState.index_of(d, v.id)
		if i >= 0 and stage[i] == EconomyState.STAGE_VACANT:
			out.append(v)
	return out


func _nearest_vacant_d2(pts: PackedVector2Array, count: int) -> PackedInt64Array:
	var scored: Array = []
	for v in _vacant_views(_player_region):
		var dist := _dist_to_segment(v.center, pts[0], pts[pts.size() - 1])
		if dist <= NEAR_M:
			scored.append([dist, v.id])
	scored.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0] or (x[0] == y[0] and x[1] < y[1]))
	var out := PackedInt64Array()
	for k in mini(count, scored.size()):
		out.append(int(scored[k][1]))
	return out


## Yetki alanı dışı (D3) komutlar: YALNIZ doğrulanır (`validate_command`), sim durumu değişmez.
func _authority_probe() -> Dictionary:
	var out := {}
	var vac := _vacant_views("D3")
	var ids := PackedInt64Array()
	for k in mini(PLAN_N, vac.size()):
		ids.append(vac[k].id)
	if not ids.is_empty():
		var z := _facade.validate_command(SimCommand.zoning_propose(ids, &"zone.mixed"))
		out["zoning_d3"] = {"status": String(z.status), "reason": String(z.reason_key), "parcels": ids.size()}
	var rng := RandomNumberGenerator.new()
	rng.seed = NetworkRules.stream_seed(_w.world_seed, "m3_baseline_authority")
	var eids: Array = _w.net.edges.keys()
	eids.sort()
	for n in 400:
		var e: WorldRoadEdge = _w.net.edges[eids[rng.randi() % eids.size()]]
		if e.mode() != WorldNetwork.MODE_ROAD or e.road_class == WorldRoadEdge.CLASS_FERRY:
			continue
		var a := _w.net.node_pos(e.a).lerp(_w.net.node_pos(e.b), rng.randf())
		if String(_w.net.rules.region_code_at(_w.world, a)) != "D3":
			continue
		var b := a + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(60.0, 250.0)
		var plain := RoadDraftCheck.check(_w.net, PackedVector2Array([a, b]), RoadDrawTool.ROAD_CLASS, _w.road_rules)
		var v := _facade.validate_command(SimCommand.public_work_road(Support.points_cm(plain.get("points", PackedVector2Array([a, b]))),
				RoadDrawTool.ROAD_CLASS))
		out["road_d3"] = {"status": String(v.status), "reason": String(v.reason_key), "draft_check_ok": bool(plain["ok"]),
			"draft_reason": String(plain.get("reason", ""))}
		break
	return out


# --- Özetler ---

func _census(d: Dictionary) -> Dictionary:
	var stage: PackedByteArray = d["stage"]
	var out := {}
	for c in _codes:
		out[c] = {"vacant": 0, "planned": 0, "under_construction": 0, "built": 0, "stalled": 0, "taken": 0}
	var names := ["vacant", "planned", "under_construction", "built", "stalled", "taken"]
	for i in _n_parcels:
		var row: Dictionary = out[_codes[_idx_region[i]]]
		var nm: String = names[stage[i]]
		row[nm] = int(row[nm]) + 1
	return out


func _vacant_codes(d: Dictionary) -> Dictionary:
	var stage: PackedByteArray = d["stage"]
	var last: PackedByteArray = d["last_code"]
	var out := {}
	for c in _codes:
		out[c] = {}
	for i in _n_parcels:
		if stage[i] != EconomyState.STAGE_VACANT:
			continue
		var nm := String(EconomyState.CODE_NAMES[last[i]])
		if nm.is_empty():
			nm = "(hiç karar yok)"
		var row: Dictionary = out[_codes[_idx_region[i]]]
		row[nm] = int(row.get(nm, 0)) + 1
	return out


func _region_rows(state: GameState) -> Dictionary:
	var out := {}
	for row in EconomyQuery.region_stats(state, _s.cfg):
		var r := {}
		for k: String in ["latent_hh", "housed_hh", "res_built", "res_pipe", "com_built", "com_pipe", "infra_cap", "infra_bonus",
				"infra_load", "access_pm", "service_pm", "demand_res_pm", "demand_com_pm"]:
			r[k] = int(row[k])
		out[String(row["code"])] = r
	return out


func _count_regions() -> Dictionary:
	var out := {}
	for c in _codes:
		out[c] = 0
	for v in _w.views:
		out[String(v.region_code)] = int(out[String(v.region_code)]) + 1
	return out


func _name_of(r: int) -> String:
	return _codes[r] if r >= 0 and r < _codes.size() else "?"


func _events_summary() -> Dictionary:
	var out := {}
	for year: int in _ev:
		var row := {}
		for key: String in _ev[year]:
			var by_r := {}
			for r: int in _ev[year][key]:
				by_r[_name_of(r)] = _ev[year][key][r]
			row[key] = by_r
		out["y%d" % (year + 1)] = row
	return out


func _decl_eval_summary() -> Dictionary:
	var out := {}
	for year: int in _decl_eval:
		var row := {}
		for r: int in _decl_eval[year]:
			row[_name_of(r)] = _decl_eval[year][r]
		out["y%d" % (year + 1)] = row
	return out


func _stats(values: Array) -> Dictionary:
	if values.is_empty():
		return {"n": 0}
	var s := values.duplicate()
	s.sort()
	var sum := 0.0
	for v in s:
		sum += float(v)
	return {"n": s.size(), "mean": snappedf(sum / s.size(), 0.001), "median": snappedf(float(s[s.size() / 2]), 0.001),
		"p95": snappedf(float(s[int(s.size() * 0.95)]), 0.001), "p99": snappedf(float(s[int(s.size() * 0.99)]), 0.001),
		"max": snappedf(float(s[s.size() - 1]), 0.001)}


func _timing_summary() -> Dictionary:
	var all: Array = []
	var plain: Array = []
	var month: Array = []
	var quarter: Array = []
	var per_year: Dictionary = {}
	var order: Array = range(_ms.size())
	for i in _ms.size():
		var t := _ms_tick[i]
		if t <= 1:
			continue
		all.append(_ms[i])
		if t % DAYS_PER_QUARTER == 0:
			quarter.append(_ms[i])
		elif t % DAYS_PER_MONTH == 0:
			month.append(_ms[i])
		else:
			plain.append(_ms[i])
		var y := "y%d" % ((t - 1) / DAYS_PER_YEAR + 1)
		if not per_year.has(y):
			per_year[y] = []
		(per_year[y] as Array).append(_ms[i])
	order.sort_custom(func(x: int, y: int) -> bool: return _ms[x] > _ms[y])
	var slowest: Array = []
	for k in mini(10, order.size()):
		slowest.append({"tick": _ms_tick[order[k]], "ms": snappedf(_ms[order[k]], 0.01)})
	var py := {}
	for y: String in per_year:
		py[y] = _stats(per_year[y])
	var over := 0
	for v in all:
		if float(v) > 8.33:
			over += 1
	return {"first_tick_ms": snappedf(_ms[0], 0.01), "all_excl_first": _stats(all), "plain_day": _stats(plain),
		"month_end_excl_quarter": _stats(month), "quarter_end": _stats(quarter), "per_year": py, "slowest10": slowest,
		"ticks_over_8_33ms": over, "ticks_over_16_6ms": all.filter(func(v: float) -> bool: return v > 16.6).size()}


func _budget_summary() -> Dictionary:
	var cap := int(_s.cfg.p("max_reviews_per_tick"))
	var sum := 0
	var at_cap := 0
	var over_cap := 0
	var zero := 0
	var hist: Dictionary = {}
	for v in _evals_day:
		sum += v
		if v >= cap:
			at_cap += 1
		if v > cap:
			over_cap += 1
		if v == 0:
			zero += 1
		hist[str(v)] = int(hist.get(str(v), 0)) + 1
	var n := maxi(_evals_day.size(), 1)
	var csum := 0
	for v in _cursor_adv:
		csum += v
	var mean_adv := float(csum) / maxi(_cursor_adv.size(), 1)
	return {"cap": cap, "days": _evals_day.size(), "evaluations_total": sum,
		"evaluations_per_day_mean": snappedf(float(sum) / n, 0.001), "usage_pct_of_cap": snappedf(100.0 * float(sum) / (n * maxi(cap, 1)), 0.1),
		"days_at_cap": at_cap, "days_at_cap_pct": snappedf(100.0 * at_cap / n, 0.1), "days_over_cap": over_cap, "days_zero_evals": zero,
		"histogram": hist, "review_cursor_adv_per_day_mean": snappedf(mean_adv, 1.0),
		"implied_full_scan_cycle_days": snappedf(float(_n_parcels) / maxf(mean_adv, 1.0), 0.1),
		"configured_scan_budget_per_tick": (_n_parcels + int(_s.cfg.p("review_period_days")) - 1) / int(_s.cfg.p("review_period_days"))}


func _profile_summary() -> Dictionary:
	var out := {}
	for book: Dictionary in [_prof, _prof_month]:
		for name: String in book:
			var c: Array = book[name]
			if float(c[0]) / maxi(int(c[1]), 1) >= 0.02 or float(c[2]) >= 0.5:
				out[name] = {"mean_ms": snappedf(float(c[0]) / maxi(int(c[1]), 1), 0.001), "n": c[1], "max_ms": snappedf(float(c[2]), 0.01),
					"max_tick": c[3]}
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
