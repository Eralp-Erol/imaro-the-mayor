class_name NetworkInvariants
extends RefCounted
## Ağ katmanı değişmezleri (T-011; WLD-01/03/05, CAN-03, TEK-03). Saf: yalnız WorldNetwork (+ onun WorldData'sı) okur.
## Her `check_*` ihlal metinleri döndürür (boş = sağlanıyor). Testler hem sağlıklı veride boşluğu hem bilerek bozulmuş
## veride ihlali doğrular. Hepsi TOPOLOJİ/göreli ilişki sınar; kesin koordinat sınamaz (koordinatlar AÇIK).

## Parsel alan eşikleri (m²): kentsel şablonlarda en küçük lot ~100 m²; kırsal tarla en çok 40 ha.
const MIN_PARCEL_AREA_M2 := 100.0
const MAX_PARCEL_AREA_M2 := 400000.0
const MIN_FRONT_LENGTH_M := 5.0
## Cephe orta noktası ile yol ekseni arası: yarım genişlik + bu pay.
const FRONTAGE_TOLERANCE_M := 1.5
## Yol/ray kenarı örnekleme adımı (m).
const EDGE_SAMPLE_STEP_M := 40.0
## Feribot: uçlar kıyıya bu kadar yakın kara, aradaki örnekler su olmalı.
const FERRY_MAX_SHORE_GAP_M := 200.0
const FERRY_MIN_LENGTH_M := 500.0
## D1-D6 kara yolu en az bu kat kuş uçuşundan uzun (WorldInvariants.MIN_LAND_DETOUR_RATIO ile aynı ruh).
const MIN_LAND_DETOUR_RATIO := 2.0
const MAX_FERRY_TO_BIRD_RATIO := 1.6
const PORT_MAX_SHORE_DISTANCE_M := 2500.0


static func check_all(net: WorldNetwork) -> PackedStringArray:
	var out := PackedStringArray()
	out.append_array(check_graph_integrity(net))
	out.append_array(check_roads_on_land(net))
	out.append_array(check_ferries_over_water(net))
	out.append_array(check_regions_connected(net))
	out.append_array(check_d1_d6_relation(net))
	out.append_array(check_port_connected(net))
	out.append_array(check_no_island_infrastructure(net))
	out.append_array(check_parcels(net))
	out.append_array(check_port_industry_parcels(net))
	return out


## Yapısal tutarlılık: kenar uçları, komşuluk, blok/parsel çapraz başvuruları.
static func check_graph_integrity(net: WorldNetwork) -> PackedStringArray:
	var out := PackedStringArray()
	var seen_pairs := {}
	for eid: int in net.edges:
		var e: WorldRoadEdge = net.edges[eid]
		if not net.nodes.has(e.a) or not net.nodes.has(e.b):
			out.append("kenar %d: uç düğüm yok" % eid)
			continue
		if e.a == e.b:
			out.append("kenar %d: kendi üzerine döngü" % eid)
		if net.node_pos(e.a).distance_to(net.node_pos(e.b)) < 0.01:
			out.append("kenar %d: sıfır uzunluk" % eid)
		if not WorldRoadEdge.ALL_CLASSES.has(e.road_class):
			out.append("kenar %d: bilinmeyen sınıf %s" % [eid, e.road_class])
		var key := "%d-%d" % [mini(e.a, e.b), maxi(e.a, e.b)]
		if seen_pairs.has(key):
			out.append("kenar %d: yinelenen çift %s" % [eid, key])
		seen_pairs[key] = true
		if not (net.adjacency[e.a] as PackedInt32Array).has(eid) or not (net.adjacency[e.b] as PackedInt32Array).has(eid):
			out.append("kenar %d: komşuluk listesinde yok" % eid)
	for nid: int in net.adjacency:
		if not net.nodes.has(nid):
			out.append("komşuluk: düğüm %d yok" % nid)
			continue
		for eid in net.adjacency[nid]:
			if not net.edges.has(eid) or not _touches(net.edges[eid], nid):
				out.append("komşuluk: düğüm %d kenar %d" % [nid, eid])
	for bid: int in net.blocks:
		var b: WorldBlock = net.blocks[bid]
		for eid in b.edge_ids:
			if not net.edges.has(eid):
				out.append("blok %d: kenar %d yok" % [bid, eid])
		for pid in b.parcel_ids:
			if not net.parcels.has(pid) or (net.parcels[pid] as WorldParcel).block_id != bid:
				out.append("blok %d: parsel %d tutarsız" % [bid, pid])
	for pid: int in net.parcels:
		var p: WorldParcel = net.parcels[pid]
		if not net.blocks.has(p.block_id) or not (net.blocks[p.block_id] as WorldBlock).parcel_ids.has(pid):
			out.append("parsel %d: blok %d tutarsız" % [pid, p.block_id])
	for hub_id in net.hubs:
		if not net.nodes.has(int(net.hubs[hub_id])):
			out.append("hub %s: düğüm yok" % hub_id)
	return out


## Feribot dışındaki tüm kenarlar kara üstünde (örneklenen her nokta kara; su yok) — WLD-03 (suya yol yok).
static func check_roads_on_land(net: WorldNetwork) -> PackedStringArray:
	var out := PackedStringArray()
	for eid: int in net.edges:
		var e: WorldRoadEdge = net.edges[eid]
		if e.road_class == WorldRoadEdge.CLASS_FERRY:
			continue
		var wet := _count_water_samples(net, e)
		if wet > 0:
			out.append("kenar %d (%s): %d örnek suda" % [eid, e.road_class, wet])
	for nid: int in net.nodes:
		var p := net.node_pos(nid)
		if net.world.is_water(p.x, p.y) and not _has_ferry_edge(net, nid):
			out.append("düğüm %d suda" % nid)
	return out


## Feribot hatları suyun üstünden geçer (WLD-05): uçlar kıyıya yakın karada, ara örnekler su.
static func check_ferries_over_water(net: WorldNetwork) -> PackedStringArray:
	var out := PackedStringArray()
	for eid: int in net.edges:
		var e: WorldRoadEdge = net.edges[eid]
		if e.road_class != WorldRoadEdge.CLASS_FERRY:
			continue
		var a := net.node_pos(e.a)
		var b := net.node_pos(e.b)
		if e.length < FERRY_MIN_LENGTH_M:
			out.append("feribot %d: çok kısa (%.0f m)" % [eid, e.length])
		var steps := maxi(2, int(ceil(e.length / 50.0)))
		var water_samples := 0
		var land_in_middle := 0
		for s in range(steps + 1):
			var p := a.lerp(b, float(s) / float(steps))
			var wet := net.world.is_water(p.x, p.y)
			var gap := minf(p.distance_to(a), p.distance_to(b))
			if wet:
				water_samples += 1
			elif gap > FERRY_MAX_SHORE_GAP_M:
				land_in_middle += 1
		if land_in_middle > 0:
			out.append("feribot %d: ortada %d kara örneği (suyun üstünden geçmiyor)" % [eid, land_in_middle])
		if water_samples == 0:
			out.append("feribot %d: hiç su örneği yok" % eid)
		for end_pos in [a, b]:
			if net.world.is_water(end_pos.x, end_pos.y) and _distance_to_land(net, end_pos) > FERRY_MAX_SHORE_GAP_M:
				out.append("feribot %d: uç kıyıdan uzak suda" % eid)
	return out


## D1–D6'nın hepsinin merkez düğümü var ve aynı kara yolu bileşeninde (ana ağa bağlı).
static func check_regions_connected(net: WorldNetwork) -> PackedStringArray:
	var out := PackedStringArray()
	var anchor := -1
	for code in WorldControlData.REGION_CODES:
		var key := StringName(code)
		if not net.hubs.has(key):
			out.append("%s: merkez düğümü yok" % code)
			continue
		var hub := int(net.hubs[key])
		if anchor < 0:
			anchor = hub
			continue
		if not net.same_component(anchor, hub, WorldNetwork.MODE_ROAD):
			out.append("%s ana yol ağına bağlı değil" % code)
	return out


## WLD-05: D1 ve D6 kara yoluyla bağlı ama kuş uçuşundan çok dolambaçlı; feribot hattı bağlar ve çok daha kısa.
static func check_d1_d6_relation(net: WorldNetwork) -> PackedStringArray:
	var out := PackedStringArray()
	if not net.hubs.has(&"D1") or not net.hubs.has(&"D6"):
		return PackedStringArray(["D1/D6 merkez düğümü yok"])
	var d1 := int(net.hubs[&"D1"])
	var d6 := int(net.hubs[&"D6"])
	var bird := net.node_pos(d1).distance_to(net.node_pos(d6))
	var road := net.shortest_path(d1, d6, WorldNetwork.MODE_ROAD)
	if not bool(road["found"]):
		out.append("D1 ↔ D6 kara yolu bağlantısı yok")
	elif float(road["length"]) < MIN_LAND_DETOUR_RATIO * bird:
		out.append("D1 ↔ D6 kara yolu dolambaçlı değil (%.1f km, kuş uçuşu %.1f km)" % [
				float(road["length"]) / 1000.0, bird / 1000.0])
	else:
		for eid in road["edges"]:
			if (net.edges[eid] as WorldRoadEdge).road_class == WorldRoadEdge.CLASS_FERRY:
				out.append("D1 ↔ D6 kara yolu feribot kenarı kullanıyor")
	var ferry := _ferry_between_regions(net, &"D1", &"D6")
	if ferry < 0:
		out.append("D1 ↔ D6 feribot hattı yok")
	else:
		var fe: WorldRoadEdge = net.edges[ferry]
		if fe.length > MAX_FERRY_TO_BIRD_RATIO * bird:
			out.append("D1 ↔ D6 feribot hattı kuş uçuşundan çok uzun")
		# İskeleler kara yoluyla ilgili bölge merkezine bağlı olmalı.
		for pier in [fe.a, fe.b]:
			if not net.same_component(pier, d1, WorldNetwork.MODE_ROAD) and \
					not net.same_component(pier, d6, WorldNetwork.MODE_ROAD):
				out.append("feribot iskelesi kara ağına bağlı değil")
	return out


## T0 liman sahası: liman düğümü ana karada, D4'ün batısında, kıyıya yakın; kara yoluyla D1'e ve rayla bir istasyona
## bağlı.
static func check_port_connected(net: WorldNetwork) -> PackedStringArray:
	var out := PackedStringArray()
	var port_id := _port_node(net)
	if port_id < 0:
		return PackedStringArray(["liman düğümü (kind=port) yok"])
	var pos := net.node_pos(port_id)
	if net.world.landmass_at(pos.x, pos.y) != WorldData.LANDMASS_MAINLAND:
		out.append("liman ana karada değil (WLD-03)")
	var d4 := net.world.region_by_code(&"D4")
	if d4 != null and pos.x >= d4.centroid.x:
		out.append("liman D4'ün batısında değil (WLD-03)")
	var shore := absf(float(net.world.shore_distance[net.world.world_to_index(pos.x, pos.y)]))
	if shore > PORT_MAX_SHORE_DISTANCE_M:
		out.append("liman kıyıdan uzak (%.0f m)" % shore)
	if net.hubs.has(&"D1") and not net.same_component(port_id, int(net.hubs[&"D1"]), WorldNetwork.MODE_ROAD):
		out.append("liman kara yoluyla ana ağa bağlı değil")
	var has_rail := false
	for eid in net.adjacency[port_id]:
		if (net.edges[eid] as WorldRoadEdge).road_class == WorldRoadEdge.CLASS_RAIL:
			has_rail = true
	if not has_rail:
		out.append("liman rayla bağlı değil")
	else:
		var station_found := false
		for nid: int in net.nodes:
			if (net.nodes[nid] as WorldRoadNode).kind == WorldRoadNode.KIND_STATION and \
					net.same_component(port_id, nid, WorldNetwork.MODE_RAIL):
				station_found = true
				break
		if not station_found:
			out.append("liman rayı hiçbir istasyona ulaşmıyor")
	return out


## T0: adalarda yol/ray/düğüm/parsel yok (WLD-03: adada liman/sanayi bağlantısı yok).
static func check_no_island_infrastructure(net: WorldNetwork) -> PackedStringArray:
	var out := PackedStringArray()
	for nid: int in net.nodes:
		var p := net.node_pos(nid)
		var lm := net.world.landmass_at(p.x, p.y)
		if lm > WorldData.LANDMASS_MAINLAND:
			out.append("düğüm %d adada (kara kütlesi %d)" % [nid, lm])
	for eid: int in net.edges:
		var e: WorldRoadEdge = net.edges[eid]
		if e.road_class == WorldRoadEdge.CLASS_FERRY:
			continue
		var mid := (net.node_pos(e.a) + net.node_pos(e.b)) * 0.5
		if net.world.landmass_at(mid.x, mid.y) > WorldData.LANDMASS_MAINLAND:
			out.append("kenar %d adada" % eid)
	for pid: int in net.parcels:
		var c := (net.parcels[pid] as WorldParcel).centroid
		if net.world.landmass_at(c.x, c.y) > WorldData.LANDMASS_MAINLAND:
			out.append("parsel %d adada" % pid)
	return out


## Parseller: kara üstünde, blok içinde, çakışmaz, cephesi bir yola bakar, alan eşikleri, geçerli bölge kodu.
static func check_parcels(net: WorldNetwork) -> PackedStringArray:
	var out := PackedStringArray()
	var codes := {}
	for r in net.world.regions:
		codes[r.code] = true
	for pid: int in net.parcels:
		var p: WorldParcel = net.parcels[pid]
		out.append_array(_check_one_parcel(net, p, codes))
	for bid: int in net.blocks:
		var b: WorldBlock = net.blocks[bid]
		var total := 0.0
		for i in b.parcel_ids.size():
			var pa: WorldParcel = net.parcels[b.parcel_ids[i]]
			total += pa.area
			for j in range(i + 1, b.parcel_ids.size()):
				var pb: WorldParcel = net.parcels[b.parcel_ids[j]]
				if NetworkGeometry.bounds(pa.outline).intersects(NetworkGeometry.bounds(pb.outline), false) and \
						NetworkGeometry.convex_overlap(pa.outline, pb.outline, 0.05):
					out.append("parsel %d ve %d çakışıyor (blok %d)" % [pa.id, pb.id, bid])
		if total > b.area * 1.0001 + 1.0:
			out.append("blok %d: parsel alanları toplamı blok alanını aşıyor" % bid)
	return out


static func _check_one_parcel(net: WorldNetwork, p: WorldParcel, codes: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	if p.area < MIN_PARCEL_AREA_M2 or p.area > MAX_PARCEL_AREA_M2:
		out.append("parsel %d: alan eşik dışı (%.0f m²)" % [p.id, p.area])
	if not codes.has(p.region_code):
		out.append("parsel %d: geçersiz bölge kodu '%s'" % [p.id, p.region_code])
	if not net.edges.has(p.frontage_edge):
		out.append("parsel %d: cephe yolu yok" % p.id)
	else:
		var e: WorldRoadEdge = net.edges[p.frontage_edge]
		if not WorldRoadEdge.is_road_class(e.road_class):
			out.append("parsel %d: cephe kenarı yol değil (%s)" % [p.id, e.road_class])
		var d := NetworkGeometry.distance_point_segment(p.front_mid, net.node_pos(e.a), net.node_pos(e.b))
		if d > e.width * 0.5 + FRONTAGE_TOLERANCE_M:
			out.append("parsel %d: cephe yola bakmıyor (%.1f m)" % [p.id, d])
	if p.front_length < MIN_FRONT_LENGTH_M:
		out.append("parsel %d: cephe çok kısa" % p.id)
	for v in p.outline:
		if net.world.is_water(v.x, v.y):
			out.append("parsel %d: köşe suda" % p.id)
			break
	var b: WorldBlock = net.blocks.get(p.block_id, null)
	if b != null and not NetworkGeometry.point_in_polygon(p.centroid, b.buildable):
		out.append("parsel %d: bloğun dışında" % p.id)
	return out


## T0 liman/sanayi dokusundaki (industrial) parseller ana karada ve D4'ün batısında (WLD-03).
static func check_port_industry_parcels(net: WorldNetwork) -> PackedStringArray:
	var out := PackedStringArray()
	var d4 := net.world.region_by_code(&"D4")
	for pid: int in net.parcels:
		var p: WorldParcel = net.parcels[pid]
		if p.fabric != &"industrial":
			continue
		if net.world.landmass_at(p.centroid.x, p.centroid.y) != WorldData.LANDMASS_MAINLAND:
			out.append("sanayi parseli %d ana karada değil (WLD-03)" % pid)
		if d4 != null and p.centroid.x >= d4.centroid.x:
			out.append("sanayi parseli %d D4'ün batısında değil (WLD-03)" % pid)
	return out


# --- yardımcılar ---

static func _touches(e: WorldRoadEdge, node_id: int) -> bool:
	return e.a == node_id or e.b == node_id


static func _count_water_samples(net: WorldNetwork, e: WorldRoadEdge) -> int:
	var a := net.node_pos(e.a)
	var b := net.node_pos(e.b)
	var steps := maxi(1, int(ceil(e.length / EDGE_SAMPLE_STEP_M)))
	var wet := 0
	for s in range(steps + 1):
		var p := a.lerp(b, float(s) / float(steps))
		if net.world.is_water(p.x, p.y):
			wet += 1
	return wet


static func _has_ferry_edge(net: WorldNetwork, node_id: int) -> bool:
	for eid in net.adjacency[node_id]:
		if (net.edges[eid] as WorldRoadEdge).road_class == WorldRoadEdge.CLASS_FERRY:
			return true
	return false


static func _port_node(net: WorldNetwork) -> int:
	var ids: Array = net.nodes.keys()
	ids.sort()
	for nid: int in ids:
		if (net.nodes[nid] as WorldRoadNode).kind == WorldRoadNode.KIND_PORT:
			return nid
	return -1


static func _distance_to_land(net: WorldNetwork, p: Vector2) -> float:
	var step := 25.0
	for k in range(0, 40):
		var r := k * step
		for dir in 8:
			var q := p + Vector2.from_angle(dir * PI / 4.0) * r
			if not net.world.is_water(q.x, q.y):
				return r
	return INF


## `from_code` ve `to_code` bölgelerinin iskelelerini bağlayan feribot kenarı (kimlik) veya -1.
static func _ferry_between_regions(net: WorldNetwork, from_code: StringName, to_code: StringName) -> int:
	var ids: Array = net.edges.keys()
	ids.sort()
	for eid: int in ids:
		var e: WorldRoadEdge = net.edges[eid]
		if e.road_class != WorldRoadEdge.CLASS_FERRY:
			continue
		var ca := net.rules.region_code_at(net.world, net.node_pos(e.a))
		var cb := net.rules.region_code_at(net.world, net.node_pos(e.b))
		if (ca == from_code and cb == to_code) or (ca == to_code and cb == from_code):
			return eid
	return -1
