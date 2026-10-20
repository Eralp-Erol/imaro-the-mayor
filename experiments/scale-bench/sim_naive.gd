extends RefCounted
## Disposable: naive implementation of the same daily tick for comparison.
## mode 0 = Array of Dictionary per parcel/cohort, mode 1 = RefCounted objects with neighbour references.
## Same algorithm and work as sim_packed.gd, but not bit-identical (doubles, single RNG).


class Parcel:
	extends RefCounted
	var land_value := 0.0
	var zoning := 0
	var demand := 0.0
	var next_demand := 0.0
	var occupancy := 0.0
	var residents := 0
	var neighbors: Array[Parcel] = []


class Cohort:
	extends RefCounted
	var home: Parcel
	var size := 1
	var income := 0.0
	var target: Parcel


var mode := 0
var w := 0
var count := 0
var parcels: Array = []
var cohorts: Array = []
var rng := RandomNumberGenerator.new()
var src := [0.0, 0.05, 0.04, 0.03]
var cost := [0.0, 1.5, 2.0, 1.2]


func setup(width: int, height: int, n_cohorts: int, seed_value: int, p_mode: int) -> void:
	mode = p_mode
	w = width
	count = width * height
	rng.seed = seed_value
	parcels.clear()
	cohorts.clear()
	for i in count:
		var r := rng.randf()
		var lv := 0.5 + 2.0 * (1.0 - absf(float(i % w) / w - 0.4)) + rng.randf()
		var z := 0 if r < 0.3 else (1 if r < 0.7 else (2 if r < 0.85 else 3))
		var d := rng.randf_range(0.0, 2.0)
		var occ := 1.0 if (z != 0 and rng.randf() < 0.5) else 0.0
		if mode == 0:
			parcels.append({"lv": lv, "z": z, "d": d, "nd": 0.0, "occ": occ, "res": 0, "nb": []})
		else:
			var p := Parcel.new()
			p.land_value = lv
			p.zoning = z
			p.demand = d
			p.occupancy = occ
			parcels.append(p)
	for i in count:  # neighbour links
		var nb: Array = []
		if i % w > 0:
			nb.append(i - 1)
		if i % w < w - 1:
			nb.append(i + 1)
		if i >= w:
			nb.append(i - w)
		if i + w < count:
			nb.append(i + w)
		if mode == 0:
			parcels[i]["nb"] = nb
		else:
			for j in nb:
				parcels[i].neighbors.append(parcels[j])
	for h in n_cohorts:
		var p = parcels[rng.randi() % count]
		while _z(p) != 1 or _occ(p) < 0.5:
			p = parcels[rng.randi() % count]
		var sz := rng.randi_range(1, 5)
		var inc := rng.randf()
		if mode == 0:
			p["res"] += sz
			cohorts.append({"home": p, "size": sz, "income": inc, "target": null})
		else:
			p.residents += sz
			var c := Cohort.new()
			c.home = p
			c.size = sz
			c.income = inc
			cohorts.append(c)


func _z(p) -> int:
	return p["z"] if mode == 0 else p.zoning


func _occ(p) -> float:
	return p["occ"] if mode == 0 else p.occupancy


func tick() -> void:
	if mode == 0:
		_tick_dict()
	else:
		_tick_obj()


func _tick_dict() -> void:
	for p in parcels:
		var s := 0.0
		for j in p["nb"]:
			s += parcels[j]["d"]
		p["nd"] = clampf(0.55 * p["d"] + 0.45 * s / p["nb"].size() + src[p["z"]] * p["lv"] * (1.0 - p["occ"]) - 0.01 * p["occ"] * p["d"], 0.0, 10.0)
	for p in parcels:
		p["d"] = p["nd"]
		var z: int = p["z"]
		if z == 0:
			continue
		if p["occ"] < 0.5:
			var feas: float = p["d"] * p["lv"] * (1.0 + 0.2 * z) - cost[z]
			if feas > 0.0 and rng.randf() < 0.05 * minf(1.0, feas):
				p["occ"] = 1.0
		elif p["d"] < 0.05 and rng.randf() < 0.01:
			p["occ"] = 0.0
		p["lv"] = clampf(p["lv"] + 0.002 * (p["d"] - 0.5), 0.1, 5.0)
	for c in cohorts:
		c["target"] = null
		if rng.randf() >= 0.03:
			continue
		var best = null
		var best_score := -1e9
		for k in 4:
			var p: Dictionary = parcels[rng.randi() % count]
			if p["z"] != 1 or p["occ"] < 0.5 or p["res"] + c["size"] > 40:
				continue
			var score: float = p["d"] * 2.0 - p["lv"] * (1.5 - c["income"])
			if score > best_score:
				best_score = score
				best = p
		c["target"] = best
	for c in cohorts:
		var t = c["target"]
		if t == null or t["res"] + c["size"] > 40:
			continue
		c["home"]["res"] -= c["size"]
		t["res"] += c["size"]
		c["home"] = t


func _tick_obj() -> void:
	for p: Parcel in parcels:
		var s := 0.0
		for q: Parcel in p.neighbors:
			s += q.demand
		p.next_demand = clampf(0.55 * p.demand + 0.45 * s / p.neighbors.size() + src[p.zoning] * p.land_value * (1.0 - p.occupancy) - 0.01 * p.occupancy * p.demand, 0.0, 10.0)
	for p: Parcel in parcels:
		p.demand = p.next_demand
		var z := p.zoning
		if z == 0:
			continue
		if p.occupancy < 0.5:
			var feas: float = p.demand * p.land_value * (1.0 + 0.2 * z) - cost[z]
			if feas > 0.0 and rng.randf() < 0.05 * minf(1.0, feas):
				p.occupancy = 1.0
		elif p.demand < 0.05 and rng.randf() < 0.01:
			p.occupancy = 0.0
		p.land_value = clampf(p.land_value + 0.002 * (p.demand - 0.5), 0.1, 5.0)
	for c: Cohort in cohorts:
		c.target = null
		if rng.randf() >= 0.03:
			continue
		var best: Parcel = null
		var best_score := -1e9
		for k in 4:
			var p: Parcel = parcels[rng.randi() % count]
			if p.zoning != 1 or p.occupancy < 0.5 or p.residents + c.size > 40:
				continue
			var score := p.demand * 2.0 - p.land_value * (1.5 - c.income)
			if score > best_score:
				best_score = score
				best = p
		c.target = best
	for c: Cohort in cohorts:
		var t := c.target
		if t == null or t.residents + c.size > 40:
			continue
		c.home.residents -= c.size
		t.residents += c.size
		c.home = t


func cleanup() -> void:
	for p in parcels:
		if mode == 1:
			p.neighbors.clear()
	for c in cohorts:
		if mode == 1:
			c.home = null
			c.target = null
	parcels.clear()
	cohorts.clear()
