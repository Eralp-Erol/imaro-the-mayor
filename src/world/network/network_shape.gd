class_name NetworkShape
extends RefCounted
## Organik kentsel sınır alanı (T-049 A): bir elips ayak izini "daire damgası"ndan çıkarır. Her ayak izi için `warp`
## alanı (ölçek çarpanı; > 1 = sınır dışarı yayılır, < 1 = geri çekilir) 80 m civarı bir raster'a pişirilir:
##   warp = 1 + gürültü(layout_seed) + düzlük/eğim terimi + kıyı şeridi terimi + arter şerit (ribbon) lobları.
## `NetworkFootprint.norm_dist = elips_uzaklığı / warp`: yol ağı ızgarası, router cezası ve yerleşim `t` değeri aynı
## alanı kullanır (tek kaynak, WLD-01).
## Koordinat gömme yok (Q-015): her şey kontrol verisinden (`network.json` organic + links), bölge merkezlerinden ve
## WorldData'dan (eğim, kıyı uzaklığı) türer; tohum yalnız `layout_seed`'dir (topoloji `world_seed`'den bağımsız kalır).
## Saf; RefCounted.

const DEFAULT_CELL_M := 80.0
const REACH_PAD_CELLS := 2
## `organic` verisinden ızgara ayarına (fp.lattice) geçen anahtarlar (T-049 A2): bend = ızgara bükülmesi (twist/disp),
## pockets = boşluk/park cepleri, keep_component_min_nodes = uydu mahalle bileşen eşiği. Bkz NetworkLattice/Frame.
const LATTICE_KEYS := ["bend", "pockets", "keep_component_min_nodes"]


## Tüm elips ayak izlerini pişirir. `control` = network.json; `organic` yoksa/devre dışıysa ayak izleri saf elips kalır.
static func bake_all(world: WorldData, footprints: Array[NetworkFootprint], control: Dictionary) -> void:
	var organic: Dictionary = control.get("organic", {})
	if organic.is_empty() or not bool(organic.get("enabled", true)):
		return
	var layout_seed := int(control.get("layout_seed", 0))
	var defaults: Dictionary = organic.get("defaults", {})
	var overrides: Dictionary = organic.get("fabrics", {})
	var centers := {}
	for fp in footprints:
		centers[fp.id] = fp.center if fp.shape == NetworkFootprint.SHAPE_ELLIPSE else (fp.seg_a + fp.seg_b) * 0.5
	for fp in footprints:
		if fp.shape != NetworkFootprint.SHAPE_ELLIPSE:
			continue
		var cfg := _merged(defaults, overrides.get(String(fp.id), {}))
		var dirs := _link_directions(control.get("links", []), fp, centers)
		for key in LATTICE_KEYS:
			if cfg.has(key):
				fp.lattice[key] = (cfg[key].duplicate(true) if cfg[key] is Dictionary else cfg[key])
		_bake(world, fp, cfg, dirs, NetworkRules.stream_seed(layout_seed, "shape:" + String(fp.id)))


static func _merged(defaults: Dictionary, over: Dictionary) -> Dictionary:
	var cfg := defaults.duplicate(true)
	for key: String in over:
		if cfg.get(key) is Dictionary and over[key] is Dictionary:
			(cfg[key] as Dictionary).merge(over[key], true)
		else:
			cfg[key] = over[key]
	return cfg


## `links`: kontrol verisi bağlantıları; bu ayak izine bağlanan her ortağın merkezine doğru birim yön.
static func _link_directions(links: Array, fp: NetworkFootprint, centers: Dictionary) -> Array[Vector2]:
	var dirs: Array[Vector2] = []
	for link: Dictionary in links:
		var a := StringName(str(link.get("from", "")))
		var b := StringName(str(link.get("to", "")))
		var other := &""
		if a == fp.id:
			other = b
		elif b == fp.id:
			other = a
		if other == &"" or not centers.has(other):
			continue
		var d: Vector2 = (centers[other] as Vector2) - fp.center
		if d.length() > 1.0:
			dirs.append(d.normalized())
	return dirs


static func _bake(world: WorldData, fp: NetworkFootprint, cfg: Dictionary, dirs: Array[Vector2],
		noise_seed: int) -> void:
	var cell := float(cfg.get("cell_m", DEFAULT_CELL_M))
	var noise: Dictionary = cfg.get("noise", {})
	var cells: Array = noise.get("cell_m", [])
	var amps: Array = noise.get("amp", [])
	var terrain: Dictionary = cfg.get("terrain", {})
	var shore: Dictionary = cfg.get("shore", {})
	var ribbon: Dictionary = cfg.get("ribbon", {})
	var scale_min := float(cfg.get("scale_min", 0.4))
	var scale_max := float(cfg.get("scale_max", 2.0))
	var amp_sum := 0.0
	for a in amps:
		amp_sum += absf(float(a))
	var reach := minf(1.0 + amp_sum + float(terrain.get("flat_gain", 0.0)) + float(shore.get("gain", 0.0)) \
			+ float(ribbon.get("gain", 0.0)), scale_max)
	var half := maxf(fp.radii.x, fp.radii.y) * reach + cell * float(REACH_PAD_CELLS)
	var w := int(ceil(2.0 * half / cell)) + 1
	var origin := fp.center - Vector2(half, half)
	var lo := float(terrain.get("slope_lo_deg", 2.0))
	var hi := float(terrain.get("slope_hi_deg", 8.0))
	var flat_gain := float(terrain.get("flat_gain", 0.0))
	var steep_cut := float(terrain.get("steep_cut", 0.0))
	var shore_lo := float(shore.get("near_m", 150.0))
	var shore_hi := float(shore.get("far_m", 900.0))
	var shore_gain := float(shore.get("gain", 0.0))
	var r_gain := float(ribbon.get("gain", 0.0))
	var r_sigma := maxf(float(ribbon.get("sigma_m", 300.0)), 1.0)
	var r_start := float(ribbon.get("start_norm", 0.4))
	var r_ref := maxf(minf(fp.radii.x, fp.radii.y), 1.0)
	var grid := PackedFloat32Array()
	grid.resize(w * w)
	for j in w:
		for i in w:
			var p := origin + Vector2(float(i), float(j)) * cell
			var s := 1.0 + NetworkNoise.fbm(noise_seed, p, cells, amps)
			var slope := world.slope_degrees_at(p.x, p.y)
			s += flat_gain * (1.0 - smoothstep(0.0, lo, slope))
			s -= steep_cut * smoothstep(lo, hi, slope)
			var sd := float(world.shore_distance[world.world_to_index(p.x, p.y)])
			s += shore_gain * (1.0 - smoothstep(shore_lo, shore_hi, sd)) * smoothstep(0.0, shore_lo, sd)
			var best := 0.0
			for dir in dirs:
				var rel := p - fp.center
				var along := rel.dot(dir)
				var across := absf(rel.x * dir.y - rel.y * dir.x)
				var ramp := smoothstep(0.0, r_start * r_ref, along)
				best = maxf(best, ramp * exp(-(across * across) / (r_sigma * r_sigma)))
			s += r_gain * best
			grid[j * w + i] = clampf(s, scale_min, scale_max)
	fp.set_warp(grid, origin, cell, w)
