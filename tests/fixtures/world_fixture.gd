class_name WorldFixture
extends RefCounted
## Küçük, sentetik, deterministik `WorldData` (T-023 ölçüt 4, ADR-0005 §WorldData). Gerçek 100 m Ismeral dünyasını
## üretmeden UI/sim/render testleri için. Kanon DEĞİLDİR: coğrafya, bölge kodları (`F1`, `F2` — bilerek D1–D6 değil)
## ve kimlikler uydurma test verisidir. Kod gerçek dünyada koordinat/bölge kodu gömüyorsa fixture'da kırılır (amaç bu).
##
## Düzen (normalize u = doğu, v = güney, [0,1]): batıda deniz, kıyı u ≈ 0.28–0.34 (hafif kavisli), doğuya hafif
## yükselen ana kara + kuzeydoğuda tepe, batı denizde tek ada. Tohum yalnız küçük yükseklik pürüzünü değiştirir.
## Yalnız temel aritmetik ve `sqrt` (IEEE-754 platformlar arası aynı; transandantal fonksiyon yok, ADR-0004 §2).

const DEFAULT_SEED := 23
const DEFAULT_SIZE_M := 8000.0
const DEFAULT_CELL_M := 200.0
const WORLD_ID := &"fixture.world"
## Dünya kökeni bilerek sıfır değil (kökeni 0 varsayan kod yakalanır).
const ORIGIN := Vector2(-4000.0, -4000.0)
const SEA_LEVEL := 0.0
## |yükseklik − deniz| bundan küçük olmaz: maske ve bilineer kıyı belirsiz kalmaz.
const MIN_ABS_HEIGHT := 0.25
const NOISE_M := 1.5
const ISLAND_CENTER := Vector2(0.12, 0.62)
const ISLAND_RADIUS := 0.06
const HILL_CENTER := Vector2(0.75, 0.35)
const HILL_RADIUS := 0.18
const HILL_HEIGHT_M := 80.0
## Bölgeler: [kod, çapa (u, v), yarıçap (u, v)].
const REGIONS := [
	[&"F1", Vector2(0.45, 0.5), Vector2(0.18, 0.45)],
	[&"F2", Vector2(0.78, 0.4), Vector2(0.18, 0.3)],
]
const PORT_ID := &"fixture_port"


static func build(fixture_seed: int = DEFAULT_SEED, size_m: float = DEFAULT_SIZE_M,
		cell_m: float = DEFAULT_CELL_M) -> WorldData:
	var w := WorldData.new()
	w.world_id = WORLD_ID
	w.world_seed = fixture_seed
	w.origin = ORIGIN
	w.size = Vector2(size_m, size_m)
	w.cell_size = cell_m
	w.width = int(round(size_m / cell_m)) + 1
	w.height = w.width
	w.sea_level = SEA_LEVEL
	_fill_heights(w)
	_label_landmasses(w)
	_assign_regions(w)
	_add_port(w)
	w.shore_distance = _shore_distance(w)
	return w


static func _coast_u(v: float) -> float:
	var t := 2.0 * v - 1.0
	return 0.28 + 0.06 * t * t


## Pürüzsüz tepe: merkezde 1, yarıçapta 0 ((1 − d²/r²)²).
static func _bump(p: Vector2, center: Vector2, radius: float) -> float:
	var q := (p - center).length_squared() / (radius * radius)
	return 0.0 if q >= 1.0 else (1.0 - q) * (1.0 - q)


static func _fill_heights(w: WorldData) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = w.world_seed
	var count := w.width * w.height
	w.heights.resize(count)
	w.land_mask.resize(count)
	for j in w.height:
		for i in w.width:
			var p := Vector2(float(i) / float(w.width - 1), float(j) / float(w.height - 1))
			var coast := _coast_u(p.y)
			var h: float
			if p.x > coast:
				h = 4.0 + 60.0 * (p.x - coast) + HILL_HEIGHT_M * _bump(p, HILL_CENTER, HILL_RADIUS)
			else:
				h = -2.0 - 120.0 * (coast - p.x)
			var island := _bump(p, ISLAND_CENTER, ISLAND_RADIUS)
			if island > 0.0:
				h = maxf(h, -6.0 + 24.0 * island)
			h += rng.randf_range(-NOISE_M, NOISE_M)
			if absf(h) < MIN_ABS_HEIGHT:
				h = MIN_ABS_HEIGHT if h >= 0.0 else -MIN_ABS_HEIGHT
			var idx := j * w.width + i
			w.heights[idx] = SEA_LEVEL + h
			w.land_mask[idx] = 1 if h > 0.0 else 0


## 4-komşulu bağlı kara bileşenleri; alana göre azalan (eşitlikte en küçük indeks önce): 1 = ana kara, 2.. = ada.
@warning_ignore("integer_division")
static func _label_landmasses(w: WorldData) -> void:
	var count := w.width * w.height
	var comp := PackedInt32Array()
	comp.resize(count)
	comp.fill(-1)
	var components: Array = []  # [hücre sayısı, ilk indeks, hücreler]
	for start in count:
		if w.land_mask[start] == 0 or comp[start] >= 0:
			continue
		var cells := PackedInt32Array([start])
		comp[start] = components.size()
		var head := 0
		while head < cells.size():
			var idx := cells[head]
			head += 1
			for n in _neighbors4(idx, w.width, w.height):
				if w.land_mask[n] == 1 and comp[n] < 0:
					comp[n] = components.size()
					cells.append(n)
		components.append([cells.size(), start, cells])
	components.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0] or (a[0] == b[0] and a[1] < b[1]))
	w.landmass_ids.resize(count)
	w.landmass_ids.fill(WorldData.LANDMASS_WATER)
	var cell_area := w.cell_size * w.cell_size
	for k in components.size():
		var cells: PackedInt32Array = components[k][2]
		var peak := -INF
		var sum := Vector2.ZERO
		for idx in cells:
			w.landmass_ids[idx] = k + 1
			peak = maxf(peak, w.heights[idx])
			sum += w.cell_to_world(idx % w.width, idx / w.width)
		if k == 0:
			continue
		var isl := WorldIsland.new()
		isl.id = StringName("FI%d" % k)
		isl.t0_tags = PackedStringArray(["natural"])
		isl.landmass_id = k + 1
		isl.area_m2 = cells.size() * cell_area
		isl.centroid = sum / float(cells.size())
		isl.peak_m = peak - w.sea_level
		isl.basis = "fixture (sentetik, kanon değil)"
		w.islands.append(isl)


## Ana kara hücreleri en küçük normalize eliptik uzaklıklı bölgeye (≤ 1) atanır; diğerleri 0.
@warning_ignore("integer_division")
static func _assign_regions(w: WorldData) -> void:
	for r in REGIONS.size():
		var region := WorldRegion.new()
		region.id = r + 1
		region.code = REGIONS[r][0]
		region.anchor = ORIGIN + (REGIONS[r][1] as Vector2) * w.size
		region.radius = (REGIONS[r][2] as Vector2) * w.size
		region.basis = "fixture (sentetik, kanon değil)"
		w.regions.append(region)
	var count := w.width * w.height
	w.region_ids.resize(count)
	w.region_ids.fill(WorldData.REGION_NONE)
	var sums: Array[Vector2] = []
	sums.resize(w.regions.size())
	sums.fill(Vector2.ZERO)
	for idx in count:
		if w.landmass_ids[idx] != WorldData.LANDMASS_MAINLAND:
			continue
		var pos := w.cell_to_world(idx % w.width, idx / w.width)
		var best := 0
		var best_d := 1.0
		for region in w.regions:
			var d := (pos - region.anchor) / region.radius
			if d.length_squared() <= best_d:
				best_d = d.length_squared()
				best = region.id
		w.region_ids[idx] = best
		if best != WorldData.REGION_NONE:
			w.regions[best - 1].cell_count += 1
			sums[best - 1] += pos
	for region in w.regions:
		if region.cell_count > 0:
			region.centroid = sums[region.id - 1] / float(region.cell_count)


## Liman: orta satırda batıdan ilk ana kara hücresi (kıyıda).
@warning_ignore("integer_division")
static func _add_port(w: WorldData) -> void:
	var j := w.height / 2
	for i in w.width:
		if w.landmass_ids[j * w.width + i] == WorldData.LANDMASS_MAINLAND:
			var site := WorldSite.new()
			site.id = PORT_ID
			site.kind = &"port"
			site.position = w.cell_to_world(i, j)
			site.basis = "fixture (sentetik, kanon değil)"
			w.sites.append(site)
			w.port_site = site
			return


## İşaretli kıyı uzaklığı (m): iki geçişli chamfer (1, √2) ile karşı sınıfın en yakın hücresine uzaklık − ½ hücre.
static func _shore_distance(w: WorldData) -> PackedFloat32Array:
	var to_water := _chamfer(w, 0)
	var to_land := _chamfer(w, 1)
	var out := PackedFloat32Array()
	out.resize(w.width * w.height)
	for idx in out.size():
		if w.land_mask[idx] == 1:
			out[idx] = (to_water[idx] - 0.5) * w.cell_size
		else:
			out[idx] = -(to_land[idx] - 0.5) * w.cell_size
	return out


## `target` sınıfındaki hücrelere hücre cinsinden yaklaşık Öklid uzaklığı.
static func _chamfer(w: WorldData, target: int) -> PackedFloat64Array:
	var diag := sqrt(2.0)
	var big := float(w.width + w.height) * 2.0
	var d := PackedFloat64Array()
	d.resize(w.width * w.height)
	for idx in d.size():
		d[idx] = 0.0 if w.land_mask[idx] == target else big
	for j in w.height:
		for i in w.width:
			var idx := j * w.width + i
			if i > 0:
				d[idx] = minf(d[idx], d[idx - 1] + 1.0)
			if j > 0:
				d[idx] = minf(d[idx], d[idx - w.width] + 1.0)
				if i > 0:
					d[idx] = minf(d[idx], d[idx - w.width - 1] + diag)
				if i < w.width - 1:
					d[idx] = minf(d[idx], d[idx - w.width + 1] + diag)
	for j in range(w.height - 1, -1, -1):
		for i in range(w.width - 1, -1, -1):
			var idx := j * w.width + i
			if i < w.width - 1:
				d[idx] = minf(d[idx], d[idx + 1] + 1.0)
			if j < w.height - 1:
				d[idx] = minf(d[idx], d[idx + w.width] + 1.0)
				if i < w.width - 1:
					d[idx] = minf(d[idx], d[idx + w.width + 1] + diag)
				if i > 0:
					d[idx] = minf(d[idx], d[idx + w.width - 1] + diag)
	return d


@warning_ignore("integer_division")
static func _neighbors4(idx: int, width: int, height: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	var i := idx % width
	var j := idx / width
	if i > 0:
		out.append(idx - 1)
	if i < width - 1:
		out.append(idx + 1)
	if j > 0:
		out.append(idx - width)
	if j < height - 1:
		out.append(idx + width)
	return out
