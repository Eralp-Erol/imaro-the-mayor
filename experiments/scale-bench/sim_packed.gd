extends RefCounted
## Disposable: data-oriented daily tick on packed arrays. Work is split into 4 fixed index groups, each with
## its own seeded RNG, so serial and WorkerThreadPool execution produce identical state.
## Threading pattern: groups read shared state via read-only locals, write only their own output slice, and the
## main thread merges slices after the barrier (no shared writes).

const GROUPS := 4

var w := 0
var count := 0
var hh_count := 0
var tick_no := 0
var land_value := PackedFloat32Array()
var zoning := PackedInt32Array()  # 0 none, 1 residential, 2 commercial, 3 industrial
var demand := PackedFloat32Array()
var occupancy := PackedFloat32Array()  # 0..1 built-out fraction
var residents := PackedInt32Array()
var hh_home := PackedInt32Array()
var hh_size := PackedInt32Array()
var hh_income := PackedFloat32Array()
var hh_target := PackedInt32Array()
var rngs: Array[RandomNumberGenerator] = []
var src := PackedFloat32Array([0.0, 0.05, 0.04, 0.03])
var cost := PackedFloat32Array([0.0, 1.5, 2.0, 1.2])
var phase_us := PackedInt64Array([0, 0, 0, 0])
var out_f: Array[PackedFloat32Array] = []  # per-group output slices (2 slots per group)
var out_i: Array[PackedInt32Array] = []


func setup(width: int, height: int, cohorts: int, seed_value: int) -> void:
	w = width
	count = width * height
	hh_count = cohorts
	tick_no = 0
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for arr in [land_value, demand, occupancy]:
		arr.resize(count)
	zoning.resize(count)
	residents.resize(count)
	for i in count:
		land_value[i] = 0.5 + 2.0 * (1.0 - absf(float(i % w) / w - 0.4)) + rng.randf()
		var r := rng.randf()
		zoning[i] = 0 if r < 0.3 else (1 if r < 0.7 else (2 if r < 0.85 else 3))
		demand[i] = rng.randf_range(0.0, 2.0)
		occupancy[i] = 1.0 if (zoning[i] != 0 and rng.randf() < 0.5) else 0.0
	hh_home.resize(cohorts)
	hh_size.resize(cohorts)
	hh_income.resize(cohorts)
	hh_target.resize(cohorts)
	for h in cohorts:
		var p := rng.randi() % count
		while zoning[p] != 1 or occupancy[p] < 0.5:
			p = rng.randi() % count
		hh_home[h] = p
		hh_size[h] = rng.randi_range(1, 5)
		hh_income[h] = rng.randf()
		residents[p] += hh_size[h]
	rngs.clear()
	out_f.clear()
	out_i.clear()
	for g in GROUPS:
		out_f.append_array([PackedFloat32Array(), PackedFloat32Array()])
		out_i.append(PackedInt32Array())
		var r := RandomNumberGenerator.new()
		r.seed = seed_value * 1000 + g
		rngs.append(r)


func tick(parallel: bool) -> void:
	var t0 := Time.get_ticks_usec()
	_run(_diffuse, parallel)
	demand = _merge(0)
	var t1 := Time.get_ticks_usec()
	_run(_invest, parallel)
	occupancy = _merge(0)
	land_value = _merge(1)
	var t2 := Time.get_ticks_usec()
	_run(_decide, parallel)
	hh_target = _merge_i()
	var t3 := Time.get_ticks_usec()
	_apply()
	var t4 := Time.get_ticks_usec()
	phase_us[0] += t1 - t0
	phase_us[1] += t2 - t1
	phase_us[2] += t3 - t2
	phase_us[3] += t4 - t3
	tick_no += 1


func _run(fn: Callable, parallel: bool) -> void:
	if parallel:
		WorkerThreadPool.wait_for_group_task_completion(WorkerThreadPool.add_group_task(fn, GROUPS, GROUPS))
	else:
		for g in GROUPS:
			fn.call(g)


## Concatenate per-group float output slices (slot 0 or 1) into one array; called on the main thread after the barrier.
func _merge(slot: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for g in GROUPS:
		out.append_array(out_f[g * 2 + slot])
		out_f[g * 2 + slot] = PackedFloat32Array()
	return out


func _merge_i() -> PackedInt32Array:
	var out := PackedInt32Array()
	for g in GROUPS:
		out.append_array(out_i[g])
		out_i[g] = PackedInt32Array()
	return out


## Neighbourhood demand diffusion over the 4-neighbour parcel grid. Each group reads shared inputs through
## read-only locals and writes only its own output slice (no shared writes, no COW).
@warning_ignore("integer_division")
func _diffuse(g: int) -> void:
	var lo := g * count / GROUPS
	var hi := (g + 1) * count / GROUPS
	var d := demand
	var lv := land_value
	var zn := zoning
	var oc := occupancy
	var sr := src
	var width := w
	var total := count
	var out := PackedFloat32Array()
	out.resize(hi - lo)
	for i in range(lo, hi):
		var x := i % width
		var s := 0.0
		var c := 0.0
		if x > 0:
			s += d[i - 1]
			c += 1.0
		if x < width - 1:
			s += d[i + 1]
			c += 1.0
		if i >= width:
			s += d[i - width]
			c += 1.0
		if i + width < total:
			s += d[i + width]
			c += 1.0
		out[i - lo] = clampf(0.55 * d[i] + 0.45 * s / c + sr[zn[i]] * lv[i] * (1.0 - oc[i]) - 0.01 * oc[i] * d[i], 0.0, 10.0)
	out_f[g * 2] = out


## Investor feasibility check per vacant zoned parcel, plus slow land value drift. Outputs occupancy (slot 0) and land value (slot 1).
@warning_ignore("integer_division")
func _invest(g: int) -> void:
	var lo := g * count / GROUPS
	var hi := (g + 1) * count / GROUPS
	var rng := rngs[g]
	var d := demand
	var lv := land_value
	var zn := zoning
	var cs := cost
	var occ_out := occupancy.slice(lo, hi)
	var lv_out := land_value.slice(lo, hi)
	for i in range(lo, hi):
		var z := zn[i]
		if z == 0:
			continue
		var occ := occ_out[i - lo]
		if occ < 0.5:
			var feas := d[i] * lv[i] * (1.0 + 0.2 * z) - cs[z]
			if feas > 0.0 and rng.randf() < 0.05 * minf(1.0, feas):
				occ_out[i - lo] = 1.0
		elif d[i] < 0.05 and rng.randf() < 0.01:
			occ_out[i - lo] = 0.0
		lv_out[i - lo] = clampf(lv[i] + 0.002 * (d[i] - 0.5), 0.1, 5.0)
	out_f[g * 2] = occ_out
	out_f[g * 2 + 1] = lv_out


## Household relocation sampling: each cohort may sample 4 random parcels and pick the best (decision only).
@warning_ignore("integer_division")
func _decide(g: int) -> void:
	var lo := g * hh_count / GROUPS
	var hi := (g + 1) * hh_count / GROUPS
	var rng := rngs[g]
	var d := demand
	var lv := land_value
	var zn := zoning
	var oc := occupancy
	var rs := residents
	var hs := hh_size
	var hi_inc := hh_income
	var total := count
	var out := PackedInt32Array()
	out.resize(hi - lo)
	for h in range(lo, hi):
		out[h - lo] = -1
		if rng.randf() >= 0.03:
			continue
		var best := -1
		var best_score := -1e9
		var sz := hs[h]
		for k in 4:
			var p := rng.randi() % total
			if zn[p] != 1 or oc[p] < 0.5 or rs[p] + sz > 40:
				continue
			var score := d[p] * 2.0 - lv[p] * (1.5 - hi_inc[h])
			if score > best_score:
				best_score = score
				best = p
		out[h - lo] = best
	out_i[g] = out


## Serial, index-ordered apply of moves (shared writes live here only).
func _apply() -> void:
	for h in hh_count:
		var t := hh_target[h]
		if t < 0 or residents[t] + hh_size[h] > 40:
			continue
		residents[hh_home[h]] -= hh_size[h]
		residents[t] += hh_size[h]
		hh_home[h] = t


func state_hash() -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	for b in [land_value.to_byte_array(), zoning.to_byte_array(), demand.to_byte_array(), occupancy.to_byte_array(), residents.to_byte_array(), hh_home.to_byte_array()]:
		ctx.update(b)
	return ctx.finish().hex_encode().substr(0, 16)
