extends SceneTree
## Disposable headless simulation micro-benchmark. Run:
##   godot --headless --path experiments/scale-bench --script res://sim_bench.gd

const Packed := preload("res://sim_packed.gd")
const Naive := preload("res://sim_naive.gd")
const TICKS := 100
const REPS := 3  # timing repetitions (machine is noisy); the first rep's hash is the one reported


func _initialize() -> void:
	var out := {"meta": {
		"godot": Engine.get_version_info()["string"], "cpu_threads": OS.get_processor_count(),
		"cpu": OS.get_processor_name(), "os": OS.get_name() + " " + OS.get_version(), "ticks": TICKS,
	}}
	# 60,000 parcels (250x240), 20,000 cohorts
	var serial := _packed(250, 240, 20000, 12345, false)
	var serial_again := _packed(250, 240, 20000, 12345, false)
	var other_seed := _packed(250, 240, 20000, 54321, false)
	var par := _packed(250, 240, 20000, 12345, true)
	var par_again := _packed(250, 240, 20000, 12345, true)
	var par_other := _packed(250, 240, 20000, 54321, true)
	out["packed_60k_serial"] = serial
	out["packed_60k_parallel4"] = par
	out["determinism"] = {
		"serial_same_seed_equal": serial["hash"] == serial_again["hash"],
		"serial_different_seed_differs": serial["hash"] != other_seed["hash"],
		"parallel_same_seed_equal": par["hash"] == par_again["hash"],
		"parallel_different_seed_differs": par["hash"] != par_other["hash"],
		"parallel_equals_serial": par["hash"] == serial["hash"],
		"hashes": {"serial": serial["hash"], "serial_again": serial_again["hash"], "serial_seed2": other_seed["hash"],
			"parallel": par["hash"], "parallel_again": par_again["hash"], "parallel_seed2": par_other["hash"]},
	}
	# 10,000 parcels (100x100), 3,333 cohorts: packed vs naive
	out["packed_10k_serial"] = _packed(100, 100, 3333, 12345, false)
	out["naive_dict_10k"] = _naive(0)
	out["naive_object_10k"] = _naive(1)
	var f := FileAccess.open(ProjectSettings.globalize_path("res://results/sim.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(out, "  "))
	print(JSON.stringify(out, "  "))
	quit()


func _packed(w: int, h: int, cohorts: int, seed_value: int, parallel: bool) -> Dictionary:
	var runs: Array[float] = []
	var hash := ""
	var phases := {}
	for rep in REPS:
		var s := Packed.new()
		s.setup(w, h, cohorts, seed_value)
		var t0 := Time.get_ticks_usec()
		for i in TICKS:
			s.tick(parallel)
		runs.append((Time.get_ticks_usec() - t0) / 1000.0 / TICKS)
		if rep == 0:
			hash = s.state_hash()
			phases = {"diffuse": s.phase_us[0] / 1000.0 / TICKS, "invest": s.phase_us[1] / 1000.0 / TICKS,
				"decide": s.phase_us[2] / 1000.0 / TICKS, "apply": s.phase_us[3] / 1000.0 / TICKS}
		elif s.state_hash() != hash:
			hash = "REPS-DIFFER"
	return {"parcels": w * h, "cohorts": cohorts, "parallel": parallel, "ms_per_tick_runs": _r(runs),
		"ms_per_tick_min": snappedf(runs.min(), 0.001), "ms_per_tick_median": snappedf(_median(runs), 0.001),
		"phase_ms_per_tick_rep0": phases, "hash": hash}


func _naive(mode: int) -> Dictionary:
	var runs: Array[float] = []
	for rep in REPS:
		var s := Naive.new()
		s.setup(100, 100, 3333, 12345, mode)
		var t0 := Time.get_ticks_usec()
		for i in TICKS:
			s.tick()
		runs.append((Time.get_ticks_usec() - t0) / 1000.0 / TICKS)
		s.cleanup()
	return {"parcels": 10000, "cohorts": 3333, "mode": "dictionary" if mode == 0 else "refcounted_object",
		"ms_per_tick_runs": _r(runs), "ms_per_tick_min": snappedf(runs.min(), 0.001), "ms_per_tick_median": snappedf(_median(runs), 0.001)}


func _median(a: Array[float]) -> float:
	var s := a.duplicate()
	s.sort()
	return s[s.size() / 2]


func _r(a: Array[float]) -> Array:
	return a.map(func(v: float) -> float: return snappedf(v, 0.001))
