class_name WorldGenerator
extends RefCounted
## Tohumlu, deterministik dünya üreteci (T-001, WLD-01/02/03, TEK-01/03).
## Kontrol verisi (data/world/<id>/*.json → WorldControlData) + tohum → WorldData.
##
## Saflık: Node/Time/OS/global rastgelelik yok. Her akış kendi `RandomNumberGenerator`'ına sahiptir ve tohumu
## `_stream_seed(world_seed, etiket)` ile türetilir; bir akışa çağrı eklemek diğerlerini kaydırmaz.
## Tohum yalnız KIYI/YÜKSEKLİK DETAYINI değiştirir (kıyı kırıntısı, rölyef gürültüsü); topoloji (körfez, ada ilişkisi,
## bölge yerleşimi) kontrol verisinden gelir (WLD-09). Yükseklik ve bölge mutlak metre uzayında tanımlıdır, dolayısıyla
## hücre boyutu değişse de aynı coğrafya çıkar (yalnız çözünürlük değişir).
##
## Hesap kaynağı notu: yükseklik dokusu için FastNoiseLite (yerel kod) kullanılır; maske/bölge/kıyı yalnız tamsayı ve
## GDScript double aritmetiğidir. Aynı ikili/platformda bit-bit aynıdır; platformlar arası yükseklik eşitliği
## (Intel x86 ↔ ARM) DOĞRULANMADI (rapora bakınız).

const MIN_LAND_M := 0.5
const MIN_WATER_DEPTH_M := 0.5
const _FNV_OFFSET := 2166136261
const _FNV_PRIME := 16777619
const _MASK32 := 0xFFFFFFFF


## Ana giriş. `overrides` (isteğe bağlı): {"cell_size_m": float} — testlerde kaba/hızlı üretim için.
static func generate(control: Dictionary, world_seed: int, overrides: Dictionary = {}) -> WorldData:
	var wcfg: Dictionary = control["world"]
	var data := WorldData.new()
	data.world_id = StringName(str(wcfg.get("id", "world")))
	data.world_seed = world_seed
	data.origin = _vec2(wcfg["origin_m"])
	data.size = _vec2(wcfg["size_km"]) * 1000.0
	data.cell_size = float(overrides.get("cell_size_m", wcfg["cell_size_m"]))
	data.sea_level = float(wcfg.get("sea_level_m", 0.0))
	data.width = int(round(data.size.x / data.cell_size)) + 1
	data.height = int(round(data.size.y / data.cell_size)) + 1
	var count := data.width * data.height
	data.land_mask.resize(count)
	data.region_ids.resize(count)
	data.landmass_ids.resize(count)
	data.heights.resize(count)
	data.shore_distance.resize(count)

	var island_src := _rasterize_coast(data, control["coast"], world_seed)
	_label_landmasses(data)
	_compute_shore_distance(data)
	_build_heights(data, control["terrain"], control["coast"], world_seed, island_src)
	_assign_regions(data, control["regions"])
	_build_islands(data, control["coast"], island_src)
	_build_sites(data, control["sites"])
	return data


# --- Kıyı: kontrol noktaları → eğri → kırıntı → raster ---

static func _rasterize_coast(data: WorldData, coast: Dictionary, world_seed: int) -> PackedByteArray:
	var island_src := PackedByteArray()
	island_src.resize(data.width * data.height)
	var curve: Dictionary = coast.get("curve", {})
	var samples := int(curve.get("samples_per_segment", 10))
	var detail: Dictionary = coast.get("detail", {})
	var levels := int(detail.get("levels", 3))
	var roughness := float(detail.get("roughness", 0.25))

	var mainland: Dictionary = coast["mainland"]
	var rng := RandomNumberGenerator.new()
	rng.seed = _stream_seed(world_seed, "coast:mainland")
	var coast_pts := _control_to_world(mainland["coast_path_km"], data.origin)
	var path := _catmull_rom(coast_pts, false, samples)
	path = _displace(path, false, levels, roughness, rng)
	path.append_array(_control_to_world(mainland["closure_km"], data.origin))
	WorldGrid.fill_polygon(path, data.origin, data.cell_size, data.width, data.height, data.land_mask, 1)

	var islands: Array = coast.get("islands", [])
	for k in islands.size():
		var island: Dictionary = islands[k]
		var irng := RandomNumberGenerator.new()
		irng.seed = _stream_seed(world_seed, "coast:island:%s" % str(island["id"]))
		var pts := _control_to_world(island["outline_km"], data.origin)
		var outline := _catmull_rom(pts, true, samples)
		outline = _displace(outline, true, levels, roughness, irng)
		var cover := PackedByteArray()
		cover.resize(data.land_mask.size())
		WorldGrid.fill_polygon(outline, data.origin, data.cell_size, data.width, data.height, cover, 1)
		for idx in cover.size():
			if cover[idx] == 1 and data.land_mask[idx] == 0:
				data.land_mask[idx] = 1
				island_src[idx] = k + 1
	return island_src


static func _control_to_world(points_km: Array, origin: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p: Array in points_km:
		out.append(origin + Vector2(float(p[0]), float(p[1])) * 1000.0)
	return out


## Düzgün (uniform) Catmull-Rom; `closed` ise halka, değilse uç noktalar çoğaltılır.
static func _catmull_rom(pts: PackedVector2Array, closed: bool, samples: int) -> PackedVector2Array:
	var n := pts.size()
	var out := PackedVector2Array()
	var segments := n if closed else n - 1
	for s in segments:
		var p0 := pts[(s - 1 + n) % n] if closed else pts[maxi(s - 1, 0)]
		var p1 := pts[s]
		var p2 := pts[(s + 1) % n] if closed else pts[s + 1]
		var p3 := pts[(s + 2) % n] if closed else pts[mini(s + 2, n - 1)]
		for k in samples:
			var t := float(k) / float(samples)
			var t2 := t * t
			var t3 := t2 * t
			out.append(0.5 * ((2.0 * p1) + (p2 - p0) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
					+ (3.0 * p1 - p0 - 3.0 * p2 + p3) * t3))
	if not closed:
		out.append(pts[n - 1])
	return out


## Orta nokta kaydırma: her düzeyde her kenarın ortasına kenara dik, uzunlukla orantılı tohumlu sapma ekler.
## Açık yolda uç noktalar sabit kalır.
static func _displace(pts: PackedVector2Array, closed: bool, levels: int, roughness: float,
		rng: RandomNumberGenerator) -> PackedVector2Array:
	var cur := pts
	for _level in levels:
		var n := cur.size()
		var edges := n if closed else n - 1
		var next := PackedVector2Array()
		for e in edges:
			var a := cur[e]
			var b := cur[(e + 1) % n]
			var seg := b - a
			var len := seg.length()
			var normal := Vector2(-seg.y, seg.x) / maxf(len, 0.001)
			var mid := (a + b) * 0.5 + normal * (rng.randf_range(-1.0, 1.0) * roughness * len)
			next.append(a)
			next.append(mid)
		if not closed:
			next.append(cur[n - 1])
		cur = next
	return cur


# --- Kara kütleleri, kıyı uzaklığı ---

static func _label_landmasses(data: WorldData) -> void:
	var result := WorldGrid.label_components(data.land_mask, data.width, data.height)
	var labels: PackedInt32Array = result["labels"]
	var areas: PackedInt32Array = result["areas"]
	# Etiketleri alana göre azalan, eşitlikte ilk hücre sırasına göre yeniden numarala (1 = ana kara).
	var order: Array[int] = []
	for label in range(1, areas.size()):
		order.append(label)
	order.sort_custom(func(a: int, b: int) -> bool: return areas[a] > areas[b] or (areas[a] == areas[b] and a < b))
	var remap := PackedInt32Array()
	remap.resize(areas.size())
	for rank in order.size():
		remap[order[rank]] = mini(rank + 1, 255)
	for idx in labels.size():
		data.landmass_ids[idx] = remap[labels[idx]]


static func _compute_shore_distance(data: WorldData) -> void:
	var dist := WorldGrid.boundary_distance(data.land_mask, data.width, data.height)
	for idx in dist.size():
		var m := (float(dist[idx]) / WorldGrid.CHAMFER_ORTHO + 0.5) * data.cell_size
		data.shore_distance[idx] = m if data.land_mask[idx] == 1 else -m


# --- Yükseklik ---

static func _build_heights(data: WorldData, terrain: Dictionary, coast: Dictionary, world_seed: int,
		island_src: PackedByteArray) -> void:
	var count := data.width * data.height
	var relief := PackedFloat32Array()  # tepe/dağ yığınlarının toplamı (m), yalnız ana kara kullanır
	relief.resize(count)
	var warp_cfg: Dictionary = terrain.get("massif_warp", {})
	var warp_noise := FastNoiseLite.new()
	warp_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	warp_noise.seed = _stream_seed(world_seed, "massif_warp") & 0x7FFFFFFF
	warp_noise.frequency = float(warp_cfg.get("frequency_per_km", 0.09)) / 1000.0
	var warp_amp := float(warp_cfg.get("amplitude", 0.0))
	for massif: Dictionary in terrain.get("massifs", []):
		_add_massif(data, relief, massif, warp_noise, warp_amp)

	var noise_cfg: Dictionary = terrain["relief_noise"]
	var relief_noise := FastNoiseLite.new()
	relief_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	relief_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	relief_noise.seed = _stream_seed(world_seed, "relief") & 0x7FFFFFFF
	relief_noise.frequency = float(noise_cfg["frequency_per_km"]) / 1000.0
	relief_noise.fractal_octaves = int(noise_cfg["octaves"])
	relief_noise.fractal_lacunarity = float(noise_cfg["lacunarity"])
	relief_noise.fractal_gain = float(noise_cfg["gain"])
	var noise_amp := float(noise_cfg["amplitude_m"])
	var min_rf := float(noise_cfg["min_relief_factor"])
	var rf_ref := float(noise_cfg["reference_massif_m"])
	# Sırt katmanı (isteğe bağlı): |gürültü| ile keskin sırt/vadi çizgileri; massif rölyef çarpanı ile ölçeklenir,
	# ova/kıyıda sönümlenir. Yumuşak FBM katmanı "tümsek" üretir; bu katman dağın "dağ gibi" okunmasını sağlar.
	var ridge_cfg: Dictionary = terrain.get("ridge", {})
	var ridge_amp := float(ridge_cfg.get("amplitude_m", 0.0))
	var ridge_center := maxf(float(ridge_cfg.get("crest_abs_noise", 0.25)), 0.01)
	var ridge_noise := FastNoiseLite.new()
	ridge_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	ridge_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	ridge_noise.seed = _stream_seed(world_seed, "ridge") & 0x7FFFFFFF
	ridge_noise.frequency = float(ridge_cfg.get("frequency_per_km", 0.3)) / 1000.0
	ridge_noise.fractal_octaves = int(ridge_cfg.get("octaves", 3))
	ridge_noise.fractal_lacunarity = float(ridge_cfg.get("lacunarity", 2.0))
	ridge_noise.fractal_gain = float(ridge_cfg.get("gain", 0.45))

	var shore: Dictionary = terrain["shore"]
	var plain_cap := float(shore["plain_cap_m"])
	var plain_scale := float(shore["plain_scale_m"])
	var fade_m := float(shore["fade_m"])
	var island_cfg: Dictionary = terrain["island"]
	var island_edge := float(island_cfg["edge_scale_m"])
	var island_noise := float(island_cfg["noise_m"])
	var island_shelf := float(island_cfg.get("shelf_m", 1.5))
	var island_profile := _island_profiles(data, coast, island_cfg, island_src)
	var island_hills := FastNoiseLite.new()
	island_hills.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	island_hills.fractal_type = FastNoiseLite.FRACTAL_FBM
	island_hills.seed = _stream_seed(world_seed, "island_hills") & 0x7FFFFFFF
	island_hills.frequency = float(island_cfg.get("hill_frequency_per_km", 0.6)) / 1000.0
	island_hills.fractal_octaves = 3

	var bathy: Dictionary = terrain["bathymetry"]
	var bathy_noise := FastNoiseLite.new()
	bathy_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	bathy_noise.seed = _stream_seed(world_seed, "bathymetry") & 0x7FFFFFFF
	bathy_noise.frequency = float(bathy["noise_frequency_per_km"]) / 1000.0
	var min_depth := float(bathy["min_depth_m"])
	var rim_depth := float(bathy["rim_depth_m"])
	var rim_scale := float(bathy["rim_scale_m"])
	var open_depth := float(bathy["open_sea_depth_m"])
	var open_scale := float(bathy["open_scale_m"])
	var bathy_amp := float(bathy["noise_m"])
	var q := float(terrain.get("quantize_m", 0.015625))
	var sea := data.sea_level
	var enclosure := _enclosure_factor(data, bathy.get("enclosed_shelf", {}))

	for j in data.height:
		var z := data.origin.y + j * data.cell_size
		for i in data.width:
			var idx := j * data.width + i
			var x := data.origin.x + i * data.cell_size
			var d := absf(data.shore_distance[idx])
			var h: float
			if data.land_mask[idx] == 1:
				var src := island_src[idx]
				if src > 0:
					# Ada: kıyıda ince plaj rafı, iç kesime doğru adanın KENDİ iç derinliğine göre yükselen tepe
					# (düz plato değil); tepe şekli ada başına (tepe yüksekliği, omuz üssü, gürültü payı) değişir.
					var prof: Vector4 = island_profile[src]  # (tepe m, omuz üssü, gürültü payı, iç derinlik m)
					var inland := clampf(d / maxf(prof.w, data.cell_size), 0.0, 1.0)
					var ts_i := d / island_edge
					var bump := maxf(0.0, 1.0 + prof.z * island_hills.get_noise_2d(x, z) * 1.6)
					h = sea + MIN_LAND_M + island_shelf * ts_i / (1.0 + ts_i) + prof.x * pow(inland, prof.y) * bump \
							+ island_noise * relief_noise.get_noise_2d(x, z)
				else:
					var n := relief_noise.get_noise_2d(x, z)
					var rf := min_rf + (1.0 - min_rf) * clampf(relief[idx] / rf_ref, 0.0, 1.0)
					var ts := d / plain_scale
					var fade := smoothstep(0.0, fade_m, d)
					var ridge := 0.0
					if ridge_amp > 0.0:
						ridge = ridge_amp * rf * (ridge_center - absf(ridge_noise.get_noise_2d(x, z))) / ridge_center
					h = sea + MIN_LAND_M + plain_cap * ts / (1.0 + ts) + (relief[idx] + noise_amp * rf * n + ridge) * fade
				h = maxf(h, sea + MIN_LAND_M)
			else:
				var t1 := d / rim_scale
				var t2 := d / open_scale
				# Derinlik kıyı uzaklığına bağlıdır; ağzı dar, kıyılarla çevrili iç körfez ayrıca açık denizden SIĞ
				# tutulur (enclosure: açık denizde 1, iç körfezde inner_factor'a iner).
				var depth := min_depth + rim_depth * t1 / (1.0 + t1) + open_depth * enclosure[idx] * t2 / (1.0 + t2)
				depth += bathy_amp * bathy_noise.get_noise_2d(x, z) * minf(t2, 1.0) * enclosure[idx]
				h = sea - maxf(depth, min_depth)
			data.heights[idx] = snappedf(h, q)

	for plain: Dictionary in terrain.get("plains", []):
		_flatten_plain(data, plain, island_src, relief_noise, q)
	# Nicem (snappedf) sonrası ada/kara-su değişmezini garanti et.
	for idx in count:
		if data.land_mask[idx] == 1:
			data.heights[idx] = maxf(data.heights[idx], sea + MIN_LAND_M)
		else:
			data.heights[idx] = minf(data.heights[idx], sea - MIN_WATER_DEPTH_M)


## Ada başına tepe profili: island_src değeri (k + 1) ile indekslenir; Vector4(tepe m, omuz üssü, gürültü payı,
## adanın en iç kıyı uzaklığı m). `coast.islands[k]`: peak_m, shoulder, hill_noise (yoksa terrain.island varsayılanı).
## Omuz üssü < 1 yuvarlak/geniş tepe, > 1 sivri tepe; gürültü payı tepenin düzensizliği (adalar aynı olmasın).
static func _island_profiles(data: WorldData, coast: Dictionary, island_cfg: Dictionary,
		island_src: PackedByteArray) -> Array[Vector4]:
	var list: Array = coast.get("islands", [])
	var out: Array[Vector4] = []
	out.resize(list.size() + 1)
	out[0] = Vector4.ZERO
	for k in list.size():
		var cfg: Dictionary = list[k]
		out[k + 1] = Vector4(float(cfg.get("peak_m", 15.0)),
				float(cfg.get("shoulder", island_cfg.get("shoulder_default", 1.0))),
				float(cfg.get("hill_noise", island_cfg.get("hill_noise_default", 0.3))), 0.0)
	var depth := PackedFloat32Array()
	depth.resize(list.size() + 1)
	for idx in island_src.size():
		var src := island_src[idx]
		if src > 0:
			depth[src] = maxf(depth[src], absf(data.shore_distance[idx]))
	for k in list.size():
		out[k + 1].w = depth[k + 1]
	return out


## Su hücresi başına "açık deniz = 1 ... kapalı iç körfez = inner_factor" derinlik çarpanı. Kapalı su = ana karanın
## morfolojik kapamasının doldurduğu su; açık denizden uzaklaştıkça (ramp_m üzerinde yumuşak) inner_factor'a iner.
## `cfg` boşsa her yerde 1 (eski davranış). Yalnız tamsayı chamfer işlemleri → deterministik.
static func _enclosure_factor(data: WorldData, cfg: Dictionary) -> PackedFloat32Array:
	var count := data.width * data.height
	var factor := PackedFloat32Array()
	factor.resize(count)
	factor.fill(1.0)
	if cfg.is_empty():
		return factor
	var inner := float(cfg.get("inner_factor", 1.0))
	var ramp := maxf(float(cfg.get("ramp_m", 4000.0)), data.cell_size)
	var mainland := PackedByteArray()
	mainland.resize(count)
	for idx in count:
		mainland[idx] = 1 if data.landmass_ids[idx] == 1 else 0
	var closed := WorldGrid.closing(mainland, data.width, data.height,
			float(cfg.get("closing_radius_m", 7000.0)) / data.cell_size)
	var open_water := PackedByteArray()
	open_water.resize(count)
	for idx in count:
		open_water[idx] = 1 if closed[idx] == 0 and data.land_mask[idx] == 0 else 0
	var to_open := WorldGrid.distance_to_value(open_water, data.width, data.height, 1)
	for idx in count:
		if closed[idx] == 1 and data.land_mask[idx] == 0:
			var away := float(to_open[idx]) / WorldGrid.CHAMFER_ORTHO * data.cell_size
			factor[idx] = lerpf(1.0, inner, smoothstep(0.0, ramp, away))
	return factor


static func _add_massif(data: WorldData, relief: PackedFloat32Array, massif: Dictionary,
		warp_noise: FastNoiseLite, warp_amp: float) -> void:
	var center := data.origin + _vec2(massif["center_km"]) * 1000.0
	var radius := _vec2(massif["radius_km"]) * 1000.0
	var peak := float(massif["peak_m"])
	# Alan bozulması u²'yu küçültebilir; kutuyu buna göre genişlet (kutu kenarında kesilme olmasın).
	var reach := 1.0 / sqrt(maxf(0.04, 1.0 - warp_amp))
	var box := _bbox(data, center, radius * reach)
	for j in range(box.position.y, box.end.y):
		var dz := (data.origin.y + j * data.cell_size - center.y) / radius.y
		for i in range(box.position.x, box.end.x):
			var dx := (data.origin.x + i * data.cell_size - center.x) / radius.x
			var u2 := dx * dx + dz * dz
			if warp_amp > 0.0 and u2 < 4.0:
				# Alan bozulması: dairesel yığınlar yerine doğal, dalgalı sınırlar.
				var wx := data.origin.x + i * data.cell_size
				var wz := data.origin.y + j * data.cell_size
				u2 *= 1.0 + warp_amp * warp_noise.get_noise_2d(wx, wz)
			if u2 < 1.0:
				var b := 1.0 - u2
				relief[j * data.width + i] += peak * b * b


static func _flatten_plain(data: WorldData, plain: Dictionary, island_src: PackedByteArray,
		noise: FastNoiseLite, q: float) -> void:
	var center := data.origin + _vec2(plain["center_km"]) * 1000.0
	var radius := _vec2(plain["radius_km"]) * 1000.0
	var target := float(plain["target_m"])
	var flatten := float(plain["flatten"])
	var micro := float(plain.get("micro_relief_m", 2.0))
	var box := _bbox(data, center, radius)
	for j in range(box.position.y, box.end.y):
		var z := data.origin.y + j * data.cell_size
		var dz := (z - center.y) / radius.y
		for i in range(box.position.x, box.end.x):
			var idx := j * data.width + i
			if data.land_mask[idx] == 0 or island_src[idx] > 0:
				continue
			var x := data.origin.x + i * data.cell_size
			var dx := (x - center.x) / radius.x
			var u := sqrt(dx * dx + dz * dz)
			if u >= 1.0:
				continue
			var t := clampf((1.0 - u) / 0.5, 0.0, 1.0)
			var w := flatten * t * t * (3.0 - 2.0 * t)
			var flat := data.sea_level + target + micro * noise.get_noise_2d(x * 3.0, z * 3.0)
			data.heights[idx] = snappedf(lerpf(data.heights[idx], flat, w), q)


## [i0, j0, i1, j1) olarak örnek kutusu (Rect2i: position + size); merkez ± yarıçap (m) kapsar, sınıra kenetlenir.
static func _bbox(data: WorldData, center: Vector2, radius_m: Vector2) -> Rect2i:
	var i0 := clampi(int(floor((center.x - radius_m.x - data.origin.x) / data.cell_size)), 0, data.width)
	var i1 := clampi(int(ceil((center.x + radius_m.x - data.origin.x) / data.cell_size)) + 1, 0, data.width)
	var j0 := clampi(int(floor((center.y - radius_m.y - data.origin.y) / data.cell_size)), 0, data.height)
	var j1 := clampi(int(ceil((center.y + radius_m.y - data.origin.y) / data.cell_size)) + 1, 0, data.height)
	return Rect2i(i0, j0, i1 - i0, j1 - j0)


# --- Bölgeler ---

static func _assign_regions(data: WorldData, regions_cfg: Dictionary) -> void:
	var max_u := float(regions_cfg.get("assignment", {}).get("max_normalized_distance", 1.0))
	var best := PackedFloat32Array()
	best.resize(data.width * data.height)
	best.fill(INF)
	var list: Array = regions_cfg["regions"]
	for k in list.size():
		var cfg: Dictionary = list[k]
		var region := WorldRegion.new()
		region.id = k + 1
		region.code = StringName(str(cfg["code"]))
		region.display_name = str(cfg.get("name", ""))
		region.anchor = data.origin + _vec2(cfg["anchor_km"]) * 1000.0
		region.radius = _vec2(cfg["radius_km"]) * 1000.0
		region.rotation_deg = float(cfg.get("rotation_deg", 0.0))
		region.basis = str(cfg.get("basis", ""))
		var rot := deg_to_rad(region.rotation_deg)
		var cs := cos(rot)
		var sn := sin(rot)
		var reach := maxf(region.radius.x, region.radius.y) * max_u
		var box := _bbox(data, region.anchor, Vector2(reach, reach))
		for j in range(box.position.y, box.end.y):
			var dz0 := data.origin.y + j * data.cell_size - region.anchor.y
			for i in range(box.position.x, box.end.x):
				var idx := j * data.width + i
				if data.land_mask[idx] == 0:
					continue
				var dx0 := data.origin.x + i * data.cell_size - region.anchor.x
				var ux := (dx0 * cs + dz0 * sn) / region.radius.x
				var uz := (-dx0 * sn + dz0 * cs) / region.radius.y
				var u := sqrt(ux * ux + uz * uz)
				if u <= max_u and u < best[idx]:
					best[idx] = u
					data.region_ids[idx] = region.id
		data.regions.append(region)
	# Sayım ve ağırlık merkezi, atama bittikten sonra (komşu bölge hücre çalmış olabilir).
	var sums: Array[Vector2] = []
	for _r in data.regions:
		sums.append(Vector2.ZERO)
	for j in data.height:
		for i in data.width:
			var rid := data.region_ids[j * data.width + i]
			if rid != WorldData.REGION_NONE:
				data.regions[rid - 1].cell_count += 1
				sums[rid - 1] += data.cell_to_world(i, j)
	for k in data.regions.size():
		var region: WorldRegion = data.regions[k]
		region.centroid = sums[k] / float(maxi(region.cell_count, 1))


# --- Adalar, T0 sahaları ---

static func _build_islands(data: WorldData, coast: Dictionary, island_src: PackedByteArray) -> void:
	var list: Array = coast.get("islands", [])
	var sums: Array[Vector2] = []
	var counts := PackedInt32Array()
	var landmass := PackedInt32Array()
	for _k in list.size():
		sums.append(Vector2.ZERO)
		counts.append(0)
		landmass.append(0)
	for j in data.height:
		for i in data.width:
			var idx := j * data.width + i
			var src := island_src[idx]
			if src > 0:
				sums[src - 1] += data.cell_to_world(i, j)
				counts[src - 1] += 1
				landmass[src - 1] = data.landmass_ids[idx]
	for k in list.size():
		var cfg: Dictionary = list[k]
		var island := WorldIsland.new()
		island.id = StringName(str(cfg["id"]))
		for tag in cfg.get("t0_tags", []):
			island.t0_tags.append(str(tag))
		island.landmass_id = landmass[k]
		island.area_m2 = counts[k] * data.cell_size * data.cell_size
		island.centroid = sums[k] / float(maxi(counts[k], 1))
		island.peak_m = float(cfg.get("peak_m", 0.0))
		island.basis = str(cfg.get("basis", ""))
		data.islands.append(island)


static func _build_sites(data: WorldData, sites_cfg: Dictionary) -> void:
	for cfg: Dictionary in sites_cfg.get("sites", []):
		var site := WorldSite.new()
		site.id = StringName(str(cfg["id"]))
		site.kind = StringName(str(cfg["kind"]))
		site.position = data.origin + _vec2(cfg["pos_km"]) * 1000.0
		site.basis = str(cfg.get("basis", ""))
		data.sites.append(site)
		if data.port_site == null and site.kind == &"port":
			data.port_site = site


# --- Yardımcılar ---

static func _vec2(pair: Variant) -> Vector2:
	var a: Array = pair
	return Vector2(float(a[0]), float(a[1]))


## 32-bit FNV-1a: (tohum, etiket) → bağımsız RNG akışı tohumu. Platform/sürümden bağımsız (tamsayı).
static func _stream_seed(world_seed: int, label: String) -> int:
	var h := _FNV_OFFSET
	for byte in label.to_utf8_buffer():
		h = ((h ^ byte) * _FNV_PRIME) & _MASK32
	for shift in [0, 8, 16, 24, 32, 40, 48, 56]:
		h = ((h ^ ((world_seed >> shift) & 0xFF)) * _FNV_PRIME) & _MASK32
	return h
