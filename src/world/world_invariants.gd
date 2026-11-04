class_name WorldInvariants
extends RefCounted
## Dünya-kanon değişmezleri (T-001 ölçüt 3; WLD-01/02/03/05, TEK-03). Saf: yalnız WorldData okur.
## Kanon olmayan ÇIKARIMLARI (D1 kuzey/D6 güney, ada kimlikleri/sayısı, sabit koordinat) zorunlu kılmaz: yalnız göreli,
## eksenden bağımsız ilişkiler sınanır (örn. D1 ve D6 karşı kıyılarda, aralarında su).
## Her `check_*` ihlal metinlerinin listesini döndürür (boş = değişmez sağlanıyor). Testler hem sağlıklı veride boşluğu
## hem bilerek bozulmuş veride ihlali doğrular. Hepsi TOPOLOJİ/göreli konum sınar; kesin koordinat sınamaz (F02, F04):
## eşikler kaba ve cömerttir, veriyi düzenlemek bunları kırmamalıdır.
##
## OY yorumu (Referans B): "batıya açılan, üç yanı karayla çevrili su kütlesi" kanon kelimesi DEĞİL, onaylanmış yön
## yorumudur; körfez testi bu yorumu topolojik olarak ölçer (morfolojik kapama ile).

## Körfez tespiti için kapama yarıçapı (m): bu çaptan dar su kütleleri (ağzı dar olan körfezler) "doldurulur".
const BAY_CLOSING_RADIUS_M := 7000.0
const MIN_BAY_AREA_KM2 := 60.0
const MIN_BAY_WATER_FRACTION := 0.85
## D1–D6 arası dar su geçişi (m): ayrılmış ama feribotla aşılabilir (WLD-05).
const MIN_D1_D6_SEPARATION_M := 500.0
const MAX_D1_D6_CROSSING_M := 6000.0
## Kara yolu dolambacı en az bu kat kadar uzun olmalı (aralarında gerçek su var).
const MIN_LAND_DETOUR_RATIO := 2.0
const MIN_COAST_CELLS := 3
const PORT_MAX_SHORE_DISTANCE_M := 2000.0
const D4_MIN_INLAND_M := 3000.0
## T0'da adada bulunmaması gereken saha türleri ve ada etiketleri (WLD-03).
const MAJOR_SITE_KINDS: Array[StringName] = [&"port", &"first_industry", &"industry", &"heavy_industry"]
const FORBIDDEN_ISLAND_TAGS: Array[String] = ["port", "industry", "first_industry", "heavy_industry", "container_port"]
const D4_MAX_MEAN_HEIGHT_M := 120.0
const D4_VS_D5_MAX_HEIGHT_RATIO := 0.35
const D4_VS_D5_MAX_SLOPE_RATIO := 0.5
const D5_MIN_MEAN_HEIGHT_M := 150.0
## Yerleşim sekisi (WLD-04, ÇM): yamaç bölgesinde T0 merkez/çarşı/konut için yerleşilebilir alan.
## Eşikler ölçüm toleransıdır
## (hedef eğim veride, genelde 4-5°); veri düzenlemesi bunları kırmamalıdır.
const TERRACE_REQUIRED_REGIONS: Array[StringName] = [&"D5"]
const TERRACE_MAX_SLOPE_DEG := 8.0
const TERRACE_MIN_GENTLE_SHARE := 0.95
const TERRACE_MIN_LAND_SHARE := 0.6
const TERRACE_MIN_MEASURED_CELLS := 4
## İç körfez batimetrisi: aynı kıyı uzaklığında iç körfez açık denizden bu kadar (m) fazla derin olamaz ("çukur" yok).
const BAY_DEPTH_TOLERANCE_M := 2.0
const BAY_DEPTH_BIN_M := 1000.0
const BAY_DEPTH_MIN_BIN_CELLS := 50


## Tüm değişmezler (tek körfez analizi paylaşılır).
static func check_all(world: WorldData) -> PackedStringArray:
	var bay := analyze_bay(world)
	var out := PackedStringArray()
	out.append_array(check_mask_height_consistency(world))
	out.append_array(check_bay_topology(world, bay))
	out.append_array(check_region_layout(world, bay))
	out.append_array(check_d1_d6_opposite_shores(world, bay))
	out.append_array(check_t0_port_on_mainland_west_of_d4(world))
	out.append_array(check_t0_first_industry_on_mainland_west_of_d4(world))
	out.append_array(check_islands_have_no_t0_port_or_industry(world))
	out.append_array(check_d4_plain_vs_d5_slopes(world))
	out.append_array(check_settlement_terraces(world))
	out.append_array(check_inner_bay_not_deeper_than_open_sea(world, bay))
	return out


## Kara > deniz seviyesi, su < deniz seviyesi (örnek başına): render, maske ve fizik aynı kıyıyı görür.
static func check_mask_height_consistency(world: WorldData) -> PackedStringArray:
	var out := PackedStringArray()
	var bad_land := 0
	var bad_water := 0
	for idx in world.heights.size():
		var h := world.heights[idx]
		if world.land_mask[idx] == 1 and h <= world.sea_level:
			bad_land += 1
		elif world.land_mask[idx] == 0 and h >= world.sea_level:
			bad_water += 1
	if bad_land > 0:
		out.append("mask/height: %d kara örneği deniz seviyesinde veya altında" % bad_land)
	if bad_water > 0:
		out.append("mask/height: %d su örneği deniz seviyesinde veya üstünde" % bad_water)
	return out


# --- Körfez ---

## Ana karanın morfolojik kapamasından körfezi çıkarır. Dönüş:
## {mask: PackedByteArray (en büyük körfez bileşeni), cells, area_km2, bbox: Rect2 (dünya m), centroid: Vector2,
##  water_fraction, mouth_cells, mouth_bbox: Rect2 (ağız hücreleri, dünya m), mouth_west_fraction, mouth_east_count,
##  north_cells, south_cells, east_cells}
@warning_ignore("integer_division")
static func analyze_bay(world: WorldData) -> Dictionary:
	var count := world.width * world.height
	var mainland := PackedByteArray()
	mainland.resize(count)
	for idx in count:
		mainland[idx] = 1 if world.landmass_ids[idx] == WorldData.LANDMASS_MAINLAND else 0
	var closed := WorldGrid.closing(mainland, world.width, world.height, BAY_CLOSING_RADIUS_M / world.cell_size)
	var candidate := PackedByteArray()
	candidate.resize(count)
	for idx in count:
		candidate[idx] = 1 if closed[idx] == 1 and mainland[idx] == 0 else 0
	var comps := WorldGrid.label_components(candidate, world.width, world.height)
	var labels: PackedInt32Array = comps["labels"]
	var areas: PackedInt32Array = comps["areas"]
	var best := 0
	for label in range(1, areas.size()):
		if best == 0 or areas[label] > areas[best]:
			best = label
	var mask := PackedByteArray()
	mask.resize(count)
	var info := {"mask": mask, "cells": 0, "area_km2": 0.0, "bbox": Rect2(), "centroid": Vector2.ZERO,
		"water_fraction": 0.0, "mouth_cells": 0, "mouth_bbox": Rect2(), "mouth_west_fraction": 0.0,
		"mouth_east_count": 0,
		"north_cells": 0, "south_cells": 0, "east_cells": 0}
	if best == 0:
		return info
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	var sum := Vector2.ZERO
	var water := 0
	var n := 0
	for idx in count:
		if labels[idx] != best:
			continue
		mask[idx] = 1
		var p := world.cell_to_world(idx % world.width, idx / world.width)
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
		sum += p
		n += 1
		if world.land_mask[idx] == 0:
			water += 1
	info["cells"] = n
	info["area_km2"] = n * world.cell_size * world.cell_size / 1.0e6
	info["bbox"] = Rect2(lo, hi - lo)
	info["centroid"] = sum / float(n)
	info["water_fraction"] = float(water) / float(n)
	_classify_bay_boundary(world, info, closed, mainland)
	return info


@warning_ignore("integer_division")
static func _classify_bay_boundary(world: WorldData, info: Dictionary, closed: PackedByteArray,
		mainland: PackedByteArray) -> void:
	var mask: PackedByteArray = info["mask"]
	var bbox: Rect2 = info["bbox"]
	var west_limit := bbox.position.x + 0.35 * bbox.size.x
	var east_start := bbox.position.x + 0.5 * bbox.size.x
	var north_limit := bbox.position.y + 0.3 * bbox.size.y
	var south_start := bbox.position.y + 0.7 * bbox.size.y
	var east_land_start := bbox.position.x + 0.75 * bbox.size.x
	var mouth := 0
	var mouth_lo := Vector2(INF, INF)
	var mouth_hi := Vector2(-INF, -INF)
	var mouth_west := 0
	var mouth_east := 0
	var north_cells := 0
	var south_cells := 0
	var east_cells := 0
	for idx in mask.size():
		if mask[idx] == 0:
			continue
		var i := idx % world.width
		var j := idx / world.width
		var p := world.cell_to_world(i, j)
		var touches_open := false
		var touches_land := false
		for nb in _neighbors4(idx, i, j, world.width, world.height):
			if closed[nb] == 0 and world.land_mask[nb] == 0:
				touches_open = true
			if mainland[nb] == 1:
				touches_land = true
		if touches_open:
			mouth += 1
			mouth_lo = Vector2(minf(mouth_lo.x, p.x), minf(mouth_lo.y, p.y))
			mouth_hi = Vector2(maxf(mouth_hi.x, p.x), maxf(mouth_hi.y, p.y))
			if p.x <= west_limit:
				mouth_west += 1
			if p.x >= east_start:
				mouth_east += 1
		if touches_land:
			if p.y <= north_limit:
				north_cells += 1
			if p.y >= south_start:
				south_cells += 1
			if p.x >= east_land_start:
				east_cells += 1
	info["mouth_cells"] = mouth
	if mouth > 0:
		info["mouth_bbox"] = Rect2(mouth_lo, mouth_hi - mouth_lo)
	info["mouth_west_fraction"] = float(mouth_west) / float(maxi(mouth, 1))
	info["mouth_east_count"] = mouth_east
	info["north_cells"] = north_cells
	info["south_cells"] = south_cells
	info["east_cells"] = east_cells


## Körfez: yeterince büyük bir su kütlesi; yalnız batıya (dış denize) açılır;
## kuzey, güney ve doğudan ana karayla çevrili.
## (OY yorumu: "batıya açılan, üç yanı karayla çevrili"; kanon kelimesi değil.)
static func check_bay_topology(world: WorldData, bay: Dictionary = {}) -> PackedStringArray:
	var info := bay if not bay.is_empty() else analyze_bay(world)
	var out := PackedStringArray()
	if float(info["area_km2"]) < MIN_BAY_AREA_KM2:
		out.append("körfez: alan %.1f km² < %.0f km² (körfez yok/dolmuş)" % [info["area_km2"], MIN_BAY_AREA_KM2])
		return out
	if float(info["water_fraction"]) < MIN_BAY_WATER_FRACTION:
		out.append("körfez: su oranı %.2f < %.2f" % [info["water_fraction"], MIN_BAY_WATER_FRACTION])
	if int(info["mouth_cells"]) == 0:
		out.append("körfez: dış denize açılan ağız yok (kapalı göl)")
	else:
		if float(info["mouth_west_fraction"]) < 0.8:
			out.append("körfez: ağzın %%%.0f'i batı üçte birinde (>= %%80 olmalı); batıya açılmıyor" % [
				100.0 * float(info["mouth_west_fraction"])])
		if int(info["mouth_east_count"]) > 0:
			out.append("körfez: doğu yarıda dış denize açık hücre var (%d); üç yan kapalı değil" % info["mouth_east_count"])
	if int(info["north_cells"]) < MIN_COAST_CELLS:
		out.append("körfez: kuzey kıyısında ana kara yok")
	if int(info["south_cells"]) < MIN_COAST_CELLS:
		out.append("körfez: güney kıyısında ana kara yok")
	if int(info["east_cells"]) < MIN_COAST_CELLS:
		out.append("körfez: doğu ucunda ana kara yok")
	return out


# --- Bölgeler ---

static func region_mask(world: WorldData, code: StringName) -> PackedByteArray:
	var mask := PackedByteArray()
	mask.resize(world.width * world.height)
	var region := world.region_by_code(code)
	if region == null:
		return mask
	for idx in mask.size():
		if world.region_ids[idx] == region.id and world.land_mask[idx] == 1:
			mask[idx] = 1
	return mask


## Bölgenin kara hücrelerinden en az biri körfez suyuna 4-komşu mu? (kıyıda). Dönüş: komşu körfez hücreleri indeksleri.
@warning_ignore("integer_division")
static func bay_shore_cells(world: WorldData, bay: Dictionary, code: StringName) -> PackedInt32Array:
	var out := PackedInt32Array()
	var region := world.region_by_code(code)
	if region == null:
		return out
	var bay_mask: PackedByteArray = bay["mask"]
	var seen := {}
	for idx in bay_mask.size():
		if bay_mask[idx] == 0 or world.land_mask[idx] == 1:
			continue
		var i := idx % world.width
		var j := idx / world.width
		for nb in _neighbors4(idx, i, j, world.width, world.height):
			if world.land_mask[nb] == 1 and world.region_ids[nb] == region.id and not seen.has(idx):
				seen[idx] = true
				out.append(idx)
	return out


## D1–D6 var; D3 D4'ün batısında, D4 iç kesim, D2 körfeze değer ve D3'ün doğusunda, D5 doğu/güneydoğu (D3'ün doğusu,
## D4'ün güneyi). D1/D6 için yön (kuzey/güney) ZORUNLU DEĞİL: karşı kıyı ilişkisi `check_d1_d6_opposite_shores`'ta.
static func check_region_layout(world: WorldData, bay: Dictionary = {}) -> PackedStringArray:
	var info := bay if not bay.is_empty() else analyze_bay(world)
	var out := PackedStringArray()
	for code in WorldControlData.REGION_CODES:
		var r := world.region_by_code(StringName(code))
		if r == null or r.cell_count == 0:
			out.append("bölge %s yok veya hiç kara hücresi yok (WLD-02)" % code)
	if not out.is_empty():
		return out
	var d2 := world.region_by_code(&"D2")
	var d3 := world.region_by_code(&"D3")
	var d4 := world.region_by_code(&"D4")
	var d5 := world.region_by_code(&"D5")
	if d2.display_name != WorldControlData.ONLY_NAME:
		out.append("D2 adı '%s' olmalı (CAN-01)" % WorldControlData.ONLY_NAME)
	for r in world.regions:
		if r.code != &"D2" and not r.display_name.is_empty():
			out.append("%s ad taşımamalı (CAN-01): '%s'" % [r.code, r.display_name])
	if not (d3.centroid.x < d4.centroid.x):
		out.append("D3 (x=%.0f) D4'ün (x=%.0f) batısında olmalı" % [d3.centroid.x, d4.centroid.x])
	var d4_mean_shore := mean_shore_distance(world, &"D4")
	if d4_mean_shore < D4_MIN_INLAND_M:
		out.append("D4 iç kesimde olmalı: ortalama kıyı uzaklığı %.0f m < %.0f m" % [d4_mean_shore, D4_MIN_INLAND_M])
	if bay_shore_cells(world, info, &"D2").size() < MIN_COAST_CELLS:
		out.append("D2 körfeze değmiyor (kıyıda olmalı)")
	if not (d5.centroid.x > d3.centroid.x and d5.centroid.y > d4.centroid.y):
		out.append("D5 doğu/güneydoğuda olmalı (D3'ün doğusu, D4'ün güneyi)")
	if not (d2.centroid.x > d3.centroid.x):
		out.append("D2 D3'ün doğusunda olmalı")
	return out


## WLD-05: D1 ve D6 aynı körfezin karşı kıyılarında, aralarında dar ama gerçek su; kara yolu dolambaçlı.
static func check_d1_d6_opposite_shores(world: WorldData, bay: Dictionary = {}) -> PackedStringArray:
	var info := bay if not bay.is_empty() else analyze_bay(world)
	var out := PackedStringArray()
	var d1_mask := region_mask(world, &"D1")
	var d6_mask := region_mask(world, &"D6")
	var d1_shore := bay_shore_cells(world, info, &"D1")
	var d6_shore := bay_shore_cells(world, info, &"D6")
	if d1_shore.size() < MIN_COAST_CELLS or d6_shore.size() < MIN_COAST_CELLS:
		out.append("D1 (%d) ve D6 (%d) aynı körfez kıyısında olmalı (karşı kıyılar)" % [d1_shore.size(), d6_shore.size()])
		return out
	# 1) Ayrılık: iki bölgenin kara hücreleri arası öklid uzaklığı (chamfer).
	var to_d6 := WorldGrid.distance_to_value(d6_mask, world.width, world.height, 1)
	var min_sep := INF
	for idx in d1_mask.size():
		if d1_mask[idx] == 1:
			min_sep = minf(min_sep, float(to_d6[idx]) / WorldGrid.CHAMFER_ORTHO * world.cell_size)
	if min_sep < MIN_D1_D6_SEPARATION_M:
		out.append("D1 ve D6 kara hücreleri %.0f m arayla yakın/bitişik (< %.0f m): ayrı kıyılar değil (WLD-05)" % [
			min_sep, MIN_D1_D6_SEPARATION_M])
	# 2) Su geçişi: D1 kıyısından D6 kıyısına yalnız su hücrelerinden BFS.
	var water := PackedByteArray()
	water.resize(world.land_mask.size())
	for idx in water.size():
		water[idx] = 1 - world.land_mask[idx]
	var steps := WorldGrid.bfs_steps(water, world.width, world.height, d1_shore)
	var crossing := -1
	for idx in d6_shore:
		if steps[idx] >= 0 and (crossing < 0 or steps[idx] < crossing):
			crossing = steps[idx]
	if crossing < 0:
		out.append("D1 kıyısından D6 kıyısına su yolu yok")
	elif (crossing + 1) * world.cell_size > MAX_D1_D6_CROSSING_M:
		out.append("D1–D6 su geçişi %.0f m > %.0f m (dar geçiş değil)" % [
			(crossing + 1) * world.cell_size, MAX_D1_D6_CROSSING_M])
	# 3) Kara dolambacı: ana kara üzerinde D1'den D6'ya yürüyüş, kuş uçuşunun en az MIN_LAND_DETOUR_RATIO katı.
	var mainland := PackedByteArray()
	mainland.resize(world.land_mask.size())
	var sources := PackedInt32Array()
	for idx in mainland.size():
		if world.landmass_ids[idx] == WorldData.LANDMASS_MAINLAND:
			mainland[idx] = 1
			if d1_mask[idx] == 1:
				sources.append(idx)
	var land_steps := WorldGrid.bfs_steps(mainland, world.width, world.height, sources)
	var land_path := -1
	for idx in d6_mask.size():
		if d6_mask[idx] == 1 and land_steps[idx] >= 0 and (land_path < 0 or land_steps[idx] < land_path):
			land_path = land_steps[idx]
	if land_path >= 0 and min_sep < INF and land_path * world.cell_size < MIN_LAND_DETOUR_RATIO * min_sep:
		out.append("D1→D6 kara yolu %.0f m, kuş uçuşu %.0f m: aralarında yeterli su yok (kara dolambacı < %.1fx)" % [
			land_path * world.cell_size, min_sep, MIN_LAND_DETOUR_RATIO])
	return out


# --- T0 liman / ada kuralı (WLD-03) ---

## T0 liman sahası: ana karada (hiçbir adada değil), kıyıda, D4'ün batısında ve D3 içinde.
static func check_t0_port_on_mainland_west_of_d4(world: WorldData) -> PackedStringArray:
	var out := PackedStringArray()
	var port := world.port_site
	if port == null:
		out.append("T0 liman sahası tanımlı değil (WLD-03)")
		return out
	out.append_array(_site_mainland_west_of_d4(world, port, "T0 liman sahası"))
	var idx := world.world_to_index(port.position.x, port.position.y)
	if absf(world.shore_distance[idx]) > PORT_MAX_SHORE_DISTANCE_M:
		out.append("T0 liman sahası kıyıda değil (kıyıya %.0f m)" % absf(world.shore_distance[idx]))
	if world.region_code_at(port.position.x, port.position.y) != &"D3":
		out.append("T0 liman sahası D3'te değil (F02 atlas: batı limanı)")
	return out


## T0 ilk ana sanayi sahası (`first_industry`): ana karada (adada değil) ve D4'ün batısında
## (WLD-03; F02 "Liman/ada kuralı").
static func check_t0_first_industry_on_mainland_west_of_d4(world: WorldData) -> PackedStringArray:
	var out := PackedStringArray()
	var site: WorldSite = null
	for candidate in world.sites:
		if candidate.kind == &"first_industry":
			site = candidate
			break
	if site == null:
		out.append("T0 ilk ana sanayi sahası tanımlı değil (WLD-03)")
		return out
	out.append_array(_site_mainland_west_of_d4(world, site, "T0 ilk ana sanayi sahası (%s)" % site.id))
	return out


## Ortak saha kuralı: su değil, ana karada (ada değil), D4'ün batısında (hem D4 ağırlık merkezi hem en batı hücresi).
@warning_ignore("integer_division")
static func _site_mainland_west_of_d4(world: WorldData, site: WorldSite, label: String) -> PackedStringArray:
	var out := PackedStringArray()
	var idx := world.world_to_index(site.position.x, site.position.y)
	if world.land_mask[idx] == 0:
		out.append("%s suda" % label)
	elif world.landmass_ids[idx] != WorldData.LANDMASS_MAINLAND:
		out.append("%s ana karada değil (kara kütlesi %d; adada olamaz, WLD-03)" % [label, world.landmass_ids[idx]])
	var d4 := world.region_by_code(&"D4")
	if d4 == null:
		out.append("D4 yok: %s 'D4'ün batısı' ölçülemiyor" % label)
		return out
	var d4_min_x := INF
	for k in world.land_mask.size():
		if world.region_ids[k] == d4.id:
			d4_min_x = minf(d4_min_x, world.cell_to_world(k % world.width, k / world.width).x)
	if not (site.position.x < d4.centroid.x and site.position.x < d4_min_x):
		out.append("%s D4'ün batısında değil (x=%.0f, D4 min x=%.0f)" % [label, site.position.x, d4_min_x])
	return out


## T0'da hiçbir adada liman/sanayi etiketi veya sahası yok; en az bir ada var (WLD-03). Ada genişlemesini YASAKLAMAZ,
## yalnız T0 durumunu sınar (F02 "Oyuncu ajansı").
static func check_islands_have_no_t0_port_or_industry(world: WorldData) -> PackedStringArray:
	var out := PackedStringArray()
	var real_islands := 0
	for island in world.islands:
		if island.landmass_id > WorldData.LANDMASS_MAINLAND and island.area_m2 > 0.0:
			real_islands += 1
		else:
			out.append("ada %s ana karaya bitişik veya üretilemedi (landmass %d)" % [island.id, island.landmass_id])
		for tag in island.t0_tags:
			if FORBIDDEN_ISLAND_TAGS.has(tag):
				out.append("ada %s T0'da '%s' etiketi taşıyor (WLD-03)" % [island.id, tag])
	if real_islands < 1:
		out.append("en az 1 ada bekleniyor (WLD-03 adaları var), bulunan: %d" % real_islands)
	for site in world.sites:
		if MAJOR_SITE_KINDS.has(site.kind):
			var lm := world.landmass_at(site.position.x, site.position.y)
			if lm != WorldData.LANDMASS_MAINLAND:
				out.append("%s (%s) ana karada değil: kara kütlesi %d (WLD-03)" % [site.id, site.kind, lm])
	return out


# --- Batimetri: iç körfez açık denizden derin olamaz ---

## Derinlik kıyı uzaklığına bağlıdır; ağzı dar iç körfez AYNI kıyı uzaklığında açık denizden derin ("çukur") olamaz.
## Kıyı uzaklığı kutularında (BAY_DEPTH_BIN_M) ortalama derinlik karşılaştırılır; ayrıca toplam ortalama ve en büyük
## derinlik.
## Yalnız göreli sınar; derinlik sayıları kanon değildir.
static func check_inner_bay_not_deeper_than_open_sea(world: WorldData, bay: Dictionary = {}) -> PackedStringArray:
	var info := bay if not bay.is_empty() else analyze_bay(world)
	var out := PackedStringArray()
	if int(info["cells"]) == 0:
		return out  # körfez yok: ayrı değişmez (check_bay_topology) bildirir
	var bay_mask: PackedByteArray = info["mask"]
	var bins := 0
	var bay_n := PackedInt32Array()
	var open_n := PackedInt32Array()
	var bay_sum := PackedFloat64Array()
	var open_sum := PackedFloat64Array()
	var bay_total := 0.0
	var open_total := 0.0
	var bay_count := 0
	var open_count := 0
	var bay_max := 0.0
	var open_max := 0.0
	for idx in world.heights.size():
		if world.land_mask[idx] == 1:
			continue
		var depth := world.sea_level - world.heights[idx]
		var bin := int(absf(world.shore_distance[idx]) / BAY_DEPTH_BIN_M)
		while bins <= bin:
			bay_n.append(0)
			open_n.append(0)
			bay_sum.append(0.0)
			open_sum.append(0.0)
			bins += 1
		if bay_mask[idx] == 1:
			bay_n[bin] += 1
			bay_sum[bin] += depth
			bay_total += depth
			bay_count += 1
			bay_max = maxf(bay_max, depth)
		else:
			open_n[bin] += 1
			open_sum[bin] += depth
			open_total += depth
			open_count += 1
			open_max = maxf(open_max, depth)
	if open_count == 0:
		return out
	for bin in bins:
		if bay_n[bin] < BAY_DEPTH_MIN_BIN_CELLS or open_n[bin] < BAY_DEPTH_MIN_BIN_CELLS:
			continue
		var bay_mean := bay_sum[bin] / bay_n[bin]
		var open_mean := open_sum[bin] / open_n[bin]
		if bay_mean > open_mean + BAY_DEPTH_TOLERANCE_M:
			out.append("iç körfez kıyıdan %.0f-%.0f m bandında açık denizden derin (%.1f m > %.1f m): çukur" % [
				bin * BAY_DEPTH_BIN_M, (bin + 1) * BAY_DEPTH_BIN_M, bay_mean, open_mean])
	if bay_count > 0 and bay_total / bay_count > open_total / open_count + BAY_DEPTH_TOLERANCE_M:
		out.append("iç körfez ortalama derinliği (%.1f m) açık denizinkinden (%.1f m) fazla" % [
			bay_total / bay_count, open_total / open_count])
	if bay_max > open_max + BAY_DEPTH_TOLERANCE_M:
		out.append("iç körfez en büyük derinliği (%.1f m) açık denizinkinden (%.1f m) fazla" % [bay_max, open_max])
	return out


# --- Ova / yamaç ---

## D4 iç ovası D5 yamaçlarından belirgin biçimde daha düz ve alçak (WLD-02).
static func check_d4_plain_vs_d5_slopes(world: WorldData) -> PackedStringArray:
	var out := PackedStringArray()
	var d4 := region_stats(world, &"D4")
	var d5 := region_stats(world, &"D5")
	if d4.is_empty() or d5.is_empty():
		out.append("D4/D5 bölgeleri yok: ova/yamaç karşılaştırılamıyor")
		return out
	if float(d4["mean_height"]) > D4_MAX_MEAN_HEIGHT_M:
		out.append("D4 ortalama yüksekliği %.0f m > %.0f m (ova değil)" % [d4["mean_height"], D4_MAX_MEAN_HEIGHT_M])
	if float(d5["mean_height"]) < D5_MIN_MEAN_HEIGHT_M:
		out.append("D5 ortalama yüksekliği %.0f m < %.0f m (yamaç değil)" % [d5["mean_height"], D5_MIN_MEAN_HEIGHT_M])
	if float(d4["mean_height"]) > D4_VS_D5_MAX_HEIGHT_RATIO * float(d5["mean_height"]):
		out.append("D4 (%.0f m) D5'ten (%.0f m) belirgin alçak değil" % [d4["mean_height"], d5["mean_height"]])
	if float(d4["mean_slope_deg"]) > D4_VS_D5_MAX_SLOPE_RATIO * float(d5["mean_slope_deg"]):
		out.append("D4 eğimi (%.1f°) D5 eğiminden (%.1f°) belirgin düz değil" % [
			d4["mean_slope_deg"], d5["mean_slope_deg"]])
	return out


## Yerleşim sekileri (WLD-04): gerekli bölgelerde (D5) en az bir seki var; her seki (kapalı olanlar dahil)
## kendi bölgesinde,
## ana karada, çoğunlukla karada; çekirdeğinin kıyı hücresi olmayan örneklerinde eğim ≤ TERRACE_MAX_SLOPE_DEG (en az
## TERRACE_MIN_GENTLE_SHARE payı); yamaç bölgelerinde (TERRACE_REQUIRED_REGIONS) seki bölge ortalamasından
## alçakta (masif
## yukarıda kalır).
static func check_settlement_terraces(world: WorldData) -> PackedStringArray:
	var out := PackedStringArray()
	for code in TERRACE_REQUIRED_REGIONS:
		if world.region_by_code(code) != null and world.terraces_of_region(code).is_empty():
			out.append("%s için yerleşim sekisi tanımlı değil (WLD-04: gerçek merkez/konut alanı)" % code)
	for t in world.terraces:
		var region := world.region_by_code(t.region_code)
		var tag := "seki '%s'" % t.id
		if not t.enabled:
			tag += " (kapalı)"
		var expected := PI * t.radius.x * t.radius.y / (world.cell_size * world.cell_size)
		var land := 0
		var measured := 0
		var gentle := 0
		var sum_slope := 0.0
		var sum_h := 0.0
		for j in world.height:
			for i in world.width:
				if not t.in_core(world.cell_to_world(i, j)):
					continue
				var idx := j * world.width + i
				if world.land_mask[idx] == 0:
					continue
				land += 1
				if world.shore_distance[idx] < 2.0 * world.cell_size:
					continue  # kıyı hücresi: eğim denize bakan komşuyu da içerir, seki ölçümüne girmez
				var slope := _cell_slope_deg(world, i, j)
				measured += 1
				sum_slope += slope
				sum_h += world.heights[idx] - world.sea_level
				if slope <= TERRACE_MAX_SLOPE_DEG:
					gentle += 1
		if region != null and world.landmass_at(t.center.x, t.center.y) != WorldData.LANDMASS_MAINLAND:
			out.append("%s ana karada değil" % tag)
		if region != null and world.region_code_at(t.center.x, t.center.y) != t.region_code:
			out.append("%s merkezi %s bölgesi içinde değil" % [tag, t.region_code])
		if float(land) < TERRACE_MIN_LAND_SHARE * expected:
			out.append("%s çekirdeğinin çoğu su (kara payı %.0f%%)" % [tag, 100.0 * land / maxf(expected, 1.0)])
		if measured < TERRACE_MIN_MEASURED_CELLS:
			continue  # çözünürlük bu seki için eğimi ölçmeye yetmiyor
		var share := float(gentle) / float(measured)
		if share < TERRACE_MIN_GENTLE_SHARE:
			out.append("%s çekirdeğinde eğimi <= %.0f° olan pay %.0f%% < %.0f%% (ort. eğim %.1f°)" % [
				tag, TERRACE_MAX_SLOPE_DEG, 100.0 * share, 100.0 * TERRACE_MIN_GENTLE_SHARE, sum_slope / measured])
		if region != null and t.region_code in TERRACE_REQUIRED_REGIONS:  # yamaç bölgeleri: alt yamaç koşulu
			var stats := region_stats(world, t.region_code)
			if not stats.is_empty() and sum_h / measured >= float(stats["mean_height"]):
				out.append("%s ortalama yüksekliği (%.0f m) bölge ortalamasından (%.0f m) alçak değil: alt yamaç değil" % [
					tag, sum_h / measured, stats["mean_height"]])
	return out


## Bölge başına ortalama yükseklik (m) ve eğim (derece); bölge boşsa boş sözlük.
@warning_ignore("integer_division")
static func region_stats(world: WorldData, code: StringName) -> Dictionary:
	var region := world.region_by_code(code)
	if region == null or region.cell_count == 0:
		return {}
	var sum_h := 0.0
	var sum_s := 0.0
	var n := 0
	for idx in world.region_ids.size():
		if world.region_ids[idx] != region.id or world.land_mask[idx] == 0:
			continue
		sum_h += world.heights[idx] - world.sea_level
		sum_s += _cell_slope_deg(world, idx % world.width, idx / world.width)
		n += 1
	return {"cells": n, "mean_height": sum_h / n, "mean_slope_deg": sum_s / n}


# --- Yardımcılar ---

static func mean_shore_distance(world: WorldData, code: StringName) -> float:
	var region := world.region_by_code(code)
	var sum := 0.0
	var n := 0
	for idx in world.region_ids.size():
		if region != null and world.region_ids[idx] == region.id:
			sum += absf(world.shore_distance[idx])
			n += 1
	return sum / float(maxi(n, 1))


static func _cell_slope_deg(world: WorldData, i: int, j: int) -> float:
	var il := maxi(i - 1, 0)
	var ir := mini(i + 1, world.width - 1)
	var ju := maxi(j - 1, 0)
	var jd := mini(j + 1, world.height - 1)
	var run_x := float(ir - il) * world.cell_size
	var run_z := float(jd - ju) * world.cell_size
	var gx := (world.heights[j * world.width + ir] - world.heights[j * world.width + il]) / run_x
	var gz := (world.heights[jd * world.width + i] - world.heights[ju * world.width + i]) / run_z
	return rad_to_deg(atan(sqrt(gx * gx + gz * gz)))


static func _neighbors4(idx: int, i: int, j: int, width: int, height: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	if i > 0:
		out.append(idx - 1)
	if i < width - 1:
		out.append(idx + 1)
	if j > 0:
		out.append(idx - width)
	if j < height - 1:
		out.append(idx + width)
	return out
