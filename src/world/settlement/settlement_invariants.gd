class_name SettlementInvariants
extends RefCounted
## T0 yerleşim değişmezleri (T-005; WLD-01/03, CAN-03): her `check_*` ihlal metinleri döndürür (boş = sağlanıyor).
## Testler hem sağlıklı çıktıda boşluğu hem bilerek bozulmuş çıktıda ihlali doğrular. Topolojik/göreli: kesin koordinat
## sınamaz. Saf, statik.

const CORNER_INSET_M := 0.05
const OVERLAP_EPS_M := 0.02
const ORIENT_MAX_DEG := 25.0
const GRID_M := 64.0
const MAX_REPORT := 25


static func check_all(res: SettlementResult) -> PackedStringArray:
	var out := PackedStringArray()
	out.append_array(res.columns.shape_errors())
	if res.rules == null:
		out.append("kural kümesi yok (settlement.json geçersiz)")
		return out
	out.append_array(check_in_parcels(res))
	out.append_array(check_on_land(res))
	out.append_array(check_no_overlap(res))
	out.append_array(check_islands(res))
	out.append_array(check_port_west_of_d4(res))
	out.append_array(check_orientation(res))
	out.append_array(check_tower_present(res))
	return out


static func _cap(out: PackedStringArray, message: String) -> void:
	if out.size() < MAX_REPORT:
		out.append(message)


## Her yapı bir parselde: parsel var, merkez ve köşeler (kule hariç) yapının parseliyle AYNI blokta bir parselin içinde.
static func check_in_parcels(res: SettlementResult) -> PackedStringArray:
	var out := PackedStringArray()
	var net := res.net
	var c := res.columns
	for i in c.count:
		if (c.flags[i] & BuildingColumns.FLAG_LANDMARK) != 0:
			continue
		var host := net.parcel(c.parcel_id[i])
		if host == null:
			_cap(out, "yapı %d: parsel %d yok" % [i, c.parcel_id[i]])
			continue
		var m := res.module_of(i)
		var pts := PackedVector2Array([c.position_of(i)])
		pts.append_array(SettlementObb.shrunk(SettlementObb.corners(c.x[i], c.z[i], c.yaw[i], m.w, m.d), CORNER_INSET_M))
		for q in pts:
			var other := net.parcel_id_at(q.x, q.y)
			if other < 0 or (net.parcel(other) as WorldParcel).block_id != host.block_id:
				_cap(out, "yapı %d: parsel dışında (%s)" % [i, q])
				break
	return out


static func check_on_land(res: SettlementResult) -> PackedStringArray:
	var out := PackedStringArray()
	var world := res.net.world
	var c := res.columns
	for i in c.count:
		var m := res.module_of(i)
		var pts := PackedVector2Array([c.position_of(i)])
		pts.append_array(SettlementObb.corners(c.x[i], c.z[i], c.yaw[i], m.w, m.d))
		for q in pts:
			if world.is_water(q.x, q.y):
				_cap(out, "yapı %d: su üstünde" % i)
				break
	return out


static func check_no_overlap(res: SettlementResult) -> PackedStringArray:
	var out := PackedStringArray()
	var c := res.columns
	var corners: Array[PackedVector2Array] = []
	var grid := {}
	for i in c.count:
		var m := res.module_of(i)
		var cs := SettlementObb.corners(c.x[i], c.z[i], c.yaw[i], m.w, m.d)
		corners.append(cs)
		var box := NetworkGeometry.bounds(cs)
		for gx in range(floori(box.position.x / GRID_M), floori(box.end.x / GRID_M) + 1):
			for gz in range(floori(box.position.y / GRID_M), floori(box.end.y / GRID_M) + 1):
				var key := Vector2i(gx, gz)
				if not grid.has(key):
					grid[key] = []
				(grid[key] as Array).append(i)
	var seen := {}
	for key: Vector2i in grid:
		var list: Array = grid[key]
		for a in list.size():
			for b in range(a + 1, list.size()):
				var i: int = list[a]
				var j: int = list[b]
				var pair := i * 1000003 + j
				if seen.has(pair):
					continue
				seen[pair] = true
				if SettlementObb.overlap(corners[i], corners[j], OVERLAP_EPS_M):
					_cap(out, "yapı %d ve %d çakışıyor" % [i, j])
	return out


## WLD-03: adalarda yapı yok; liman/sanayi bayraklı yapılar ana karada.
static func check_islands(res: SettlementResult) -> PackedStringArray:
	var out := PackedStringArray()
	var world := res.net.world
	var c := res.columns
	for i in c.count:
		if world.landmass_at(c.x[i], c.z[i]) != WorldData.LANDMASS_MAINLAND:
			var port_class := (c.flags[i] & (BuildingColumns.FLAG_PORT_YARD | BuildingColumns.FLAG_INDUSTRY)) != 0
			_cap(out, "yapı %d: ada/su üstünde%s" % [i, " (liman/sanayi sınıfı)" if port_class else ""])
	return out


## WLD-03: T0 liman/ilk sanayi sahası yapıları ana karada ve D4 bölgesinin batısında.
static func check_port_west_of_d4(res: SettlementResult) -> PackedStringArray:
	var out := PackedStringArray()
	var world := res.net.world
	var d4 := world.region_by_code(&"D4")
	var c := res.columns
	for i in c.count:
		if (c.flags[i] & BuildingColumns.FLAG_PORT_YARD) == 0:
			continue
		if d4 == null:
			_cap(out, "liman yapısı %d var ama D4 bölgesi tanımsız" % i)
			continue
		if world.landmass_at(c.x[i], c.z[i]) != WorldData.LANDMASS_MAINLAND:
			_cap(out, "liman yapısı %d ana karada değil" % i)
		if c.x[i] >= d4.centroid.x:
			_cap(out, "liman yapısı %d D4'ün batısında değil" % i)
	return out


## Cephe yönü: modülün +Z yüzü parselin cephe yoluna bakar; uzun ekseni cephe doğrultusuna <= 25 derece paralel.
static func check_orientation(res: SettlementResult) -> PackedStringArray:
	var out := PackedStringArray()
	var net := res.net
	var c := res.columns
	for i in c.count:
		if (c.flags[i] & BuildingColumns.FLAG_LANDMARK) != 0:
			continue
		var p := net.parcel(c.parcel_id[i])
		if p == null or not net.edges.has(p.frontage_edge):
			continue
		var e: WorldRoadEdge = net.edges[p.frontage_edge]
		var a := net.node_pos(e.a)
		var b := net.node_pos(e.b)
		var m := res.module_of(i)
		var face := Vector2(sin(c.yaw[i]), cos(c.yaw[i]))
		var center := c.position_of(i)
		var ahead := NetworkGeometry.distance_point_segment(center + face * (m.d * 0.5 + 2.0), a, b)
		var behind := NetworkGeometry.distance_point_segment(center - face * (m.d * 0.5 + 2.0), a, b)
		var side := Vector2(cos(c.yaw[i]), -sin(c.yaw[i]))
		var cos_angle := absf(float(side.dot((b - a).normalized())))
		if ahead >= behind or cos_angle < cos(deg_to_rad(ORIENT_MAX_DEG)):
			_cap(out, "yapı %d: cephe yönü yola göre yanlış" % i)
	return out


static func check_tower_present(res: SettlementResult) -> PackedStringArray:
	var out := PackedStringArray()
	if bool(res.rules.tower.get("enabled", true)) and res.tower_index < 0:
		out.append("saat kulesi yok (meydan bulunamadı)")
	return out
