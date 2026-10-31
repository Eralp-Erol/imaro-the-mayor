class_name LifeEdgeActivity
extends RefCounted
## Yol parçası (kenar) başına SİM KAYNAKLI faaliyet (T-050). Saf veri katmanı: node/zaman/RNG yok, sim'e YAZMAZ.
##
## Girdi (hepsi sim'in verdiği/okunduğu veri):
##  - parsel durumu `pid -> Vector3i(res, com, con)`: biten konut birimi, biten ticaret birimi, inşaat halindeki birim
##    (T0 stoku = sim'e verilen başlangıç stoğu; sonrası `parcel_changes_since` ile okunan `ParcelView`);
##  - bölge doluluğu `region -> 0..1` (`economy_outcome`: housed_households / residential_units);
##  - ağ (`WorldNetwork`): parselin cephe kenarı, kenar uzunluğu/sınıfı/genişliği, düğüm komşuluğu.
## Çıktı: kenar başına beklenen araç/yaya sayısı (gerçek sayı; yuvarlama yerleşim katmanında, kenar kimliği
## karmasıyla ve sayı arttıkça ASLA azalmayacak biçimde). Seed yalnız konum/faz üretir; SAYI sim verisinden gelir.

var cfg: LifeConfig = null
var net: WorldNetwork = null
## pid -> Vector3i(res, com, con). Sim'den gelen tek gerçek kaynak (bu sınıf sahibi değil, kopyasını tutar).
var parcel_state: Dictionary = {}
## Bölge kodu -> doluluk 0..1 (boş = 1,0: ekonomi henüz kurulmadı).
var occupancy: Dictionary = {}
## Kenar -> Vector3i(res, com, con) toplamı.
var edge_units: Dictionary = {}
## Yaşam taşıyabilir kenarlar: eid -> true. Kenar -> hücre ve bölge.
var eligible: Dictionary = {}
## Hücre kenarı (m); `layout.cell_m`.
var cell_m: float = 256.0
var stats: Dictionary = {"edges_eligible": 0, "parcels_mapped": 0, "rebuilds": 0}

## pid -> [eid, Vector3i]: şu an kenar toplamlarına eklenmiş katkı.
var _placed: Dictionary = {}
var _edge_cell: Dictionary = {}
var _edge_region: Dictionary = {}
var _cell_edges: Dictionary = {}
var _dirty_cells: Dictionary = {}
var _rebuild_keys: Array = []
var _rebuild_i: int = 0
var _rebuilding: bool = false


static func create(p_net: WorldNetwork, p_cfg: LifeConfig) -> LifeEdgeActivity:
	var a := LifeEdgeActivity.new()
	a.net = p_net
	a.cfg = p_cfg
	a.cell_m = p_cfg.layout("cell_m")
	a.index_edges()
	return a


## Hücre anahtarı (dünya xz -> tamsayı hücre).
func cell_of(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / cell_m), floori(p.y / cell_m))


## Kenar dizinini baştan kurar (grafik değişince). Tüm hücreler kirlenir.
func index_edges() -> void:
	eligible.clear()
	_edge_cell.clear()
	_edge_region.clear()
	_cell_edges.clear()
	var lists: Dictionary = {}
	var min_len := cfg.layout("min_edge_len_m")
	var min_w := cfg.layout("min_open_width_m")
	for eid in net.edges:
		var e: WorldRoadEdge = net.edges[eid]
		if e.mode() != WorldNetwork.MODE_ROAD or not e.open:
			continue
		var row := cfg.class_row(e.road_class)
		if row.is_empty() or (float(row["cars_cap_per_100m"]) <= 0.0 and float(row["people_cap_per_100m"]) <= 0.0):
			continue
		if e.length < min_len or e.width < min_w:
			continue
		var pa := net.node_pos(e.a)
		var pb := net.node_pos(e.b)
		var mid := (pa + pb) * 0.5
		var cell := cell_of(mid)
		eligible[int(eid)] = true
		_edge_cell[int(eid)] = cell
		_edge_region[int(eid)] = net.world.region_code_at(mid.x, mid.y) if net.world != null else &""
		if not lists.has(cell):
			lists[cell] = []
		(lists[cell] as Array).append(int(eid))
	for cell in lists:
		var arr: Array = lists[cell]
		arr.sort()
		_cell_edges[cell] = PackedInt32Array(arr)
		_dirty_cells[cell] = true
	stats["edges_eligible"] = eligible.size()


## Parsel -> kenar eşlemesini ve kenar toplamlarını `parcel_state`ten baştan kurar (kare dilimli: `step_rebuild`).
func begin_rebuild() -> void:
	edge_units.clear()
	_placed.clear()
	_rebuild_keys = parcel_state.keys()
	_rebuild_keys.sort()
	_rebuild_i = 0
	_rebuilding = true
	stats["rebuilds"] = int(stats["rebuilds"]) + 1


func is_rebuilding() -> bool:
	return _rebuilding


## Kalan işi `per_call` parsel kadar yürütür; bitince true (ve tüm hücreler kirli).
func step_rebuild(per_call: int) -> bool:
	if not _rebuilding:
		return true
	var end_i := mini(_rebuild_i + maxi(1, per_call), _rebuild_keys.size())
	while _rebuild_i < end_i:
		var pid := int(_rebuild_keys[_rebuild_i])
		_rebuild_i += 1
		_replace(pid, false)
	if _rebuild_i >= _rebuild_keys.size():
		_rebuilding = false
		_rebuild_keys = []
		for cell in _cell_edges:
			_dirty_cells[cell] = true
		stats["parcels_mapped"] = _placed.size()
		return true
	return false


## Tek parselin durumunu günceller (sim değişim akışı). Sıfırsa kaydı siler. Yeniden kurulum sürerken de güvenlidir.
func set_parcel(pid: int, state: Vector3i) -> void:
	if state == Vector3i.ZERO:
		parcel_state.erase(pid)
	else:
		parcel_state[pid] = state
	_replace(pid, true)


## Parselin eski katkısını çıkarır, güncel durumu cephe kenarına ekler (idempotent).
func _replace(pid: int, mark: bool) -> void:
	if _placed.has(pid):
		var prev: Array = _placed[pid]
		_placed.erase(pid)
		_add_units(int(prev[0]), -(prev[1] as Vector3i), mark)
	var state: Vector3i = parcel_state.get(pid, Vector3i.ZERO)
	if state == Vector3i.ZERO:
		return
	var parcel: WorldParcel = net.parcels.get(pid)
	if parcel == null or parcel.frontage_edge < 0 or not eligible.has(parcel.frontage_edge):
		return
	_placed[pid] = [parcel.frontage_edge, state]
	_add_units(parcel.frontage_edge, state, mark)


func _add_units(eid: int, delta: Vector3i, mark: bool) -> void:
	var cur: Vector3i = edge_units.get(eid, Vector3i.ZERO) + delta
	if cur == Vector3i.ZERO:
		edge_units.erase(eid)
	else:
		edge_units[eid] = cur
	if mark:
		mark_edge_dirty(eid)


## Kenar (ve spill nedeniyle komşuları) hangi hücrelerde kirli.
func mark_edge_dirty(eid: int) -> void:
	if _edge_cell.has(eid):
		_dirty_cells[_edge_cell[eid]] = true
	var e: WorldRoadEdge = net.edges.get(eid)
	if e == null:
		return
	for node_id in [e.a, e.b]:
		for n in net.adjacency.get(node_id, PackedInt32Array()):
			if _edge_cell.has(int(n)):
				_dirty_cells[_edge_cell[int(n)]] = true


func take_dirty_cells() -> Array:
	var out: Array = _dirty_cells.keys()
	_dirty_cells.clear()
	return out


func mark_cell_dirty(cell: Vector2i) -> void:
	if _cell_edges.has(cell):
		_dirty_cells[cell] = true


func mark_all_dirty() -> void:
	for cell in _cell_edges:
		_dirty_cells[cell] = true


func edges_in_cell(cell: Vector2i) -> PackedInt32Array:
	return _cell_edges.get(cell, PackedInt32Array())


func cells() -> Array:
	return _cell_edges.keys()


## Kendi faaliyeti (aktivite birimi): biten konut x doluluk x w_res + ticaret x w_com + inşaat x w_con.
func own_activity(eid: int) -> float:
	var u: Vector3i = edge_units.get(eid, Vector3i.ZERO)
	if u == Vector3i.ZERO:
		return 0.0
	var occ := float(occupancy.get(_edge_region.get(eid, &""), 1.0))
	return float(u.x) * occ * cfg.weight("res") + float(u.y) * cfg.weight("com") + float(u.z) * cfg.weight("con")


## Kendi + komşu kenarların `spill_share` payı (aynı uç düğümlerde buluşan diğer kenarlar).
func activity(eid: int) -> float:
	var total := own_activity(eid)
	var e: WorldRoadEdge = net.edges.get(eid)
	if e == null:
		return total
	var spill := 0.0
	for node_id in [e.a, e.b]:
		for n in net.adjacency.get(node_id, PackedInt32Array()):
			if int(n) != eid:
				spill += own_activity(int(n))
	return total + cfg.spill_share() * spill


## Beklenen {cars, people} (gerçek sayı, `density` ve sınıf tavanı uygulanmış). Ağda olmayan kenar -> sıfır.
func expected(eid: int, density: float) -> Vector2:
	var e: WorldRoadEdge = net.edges.get(eid)
	if e == null or not eligible.has(eid):
		return Vector2.ZERO
	var row := cfg.class_row(e.road_class)
	if row.is_empty():
		return Vector2.ZERO
	var act := activity(eid)
	if act <= 0.0:
		return Vector2.ZERO
	var per100 := e.length / 100.0
	var cars := minf(act * float(row["cars_per_activity"]) * density, float(row["cars_cap_per_100m"]) * per100)
	var people := minf(act * float(row["people_per_activity"]) * density, float(row["people_cap_per_100m"]) * per100)
	return Vector2(cars, people)


## Bölge doluluğu: housed/units (units 0 ise 1,0). `outcome`: `EconomyOutcomeView` (available false ise değişmez).
## Dönüş: doluluk değişti mi (yerleşimi tazelemek için).
func set_occupancy_from(outcome: EconomyOutcomeView, threshold: float = 0.005) -> bool:
	if outcome == null or not outcome.available:
		return false
	var changed := false
	for r in outcome.regions:
		var occ := 1.0
		if r.residential_units > 0:
			occ = clampf(float(r.housed_households) / float(r.residential_units), 0.0, 1.0)
		var prev := float(occupancy.get(r.region_code, -1.0))
		if absf(prev - occ) > threshold:
			occupancy[r.region_code] = occ
			changed = true
	return changed


## Yaşam taşıyan toplam beklenen sayılar (test/ölçüm).
func totals(density: float) -> Vector2:
	var t := Vector2.ZERO
	for eid in eligible:
		t += expected(int(eid), density)
	return t
