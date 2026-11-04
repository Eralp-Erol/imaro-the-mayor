class_name VegetationObstacles
extends RefCounted
## Bitki yerleşiminin engel/bağlam sorguları (T-062 B0): bina ayak izi, yol kesiti, kent bloğu maskesi, şehre uzaklık.
## Hepsi T0 verisinden bir kez kurulur (BuildingColumns + modül ayak izi, WorldNetwork kenarları, bloklar, WorldData);
## saf: Node/zaman/OS/rastgelelik yok. Sorgular sıralı/deterministiktir (karma ızgara + dizin sırası).
##
## Bina ayak izi = modül `w x d` (LOD0 sınır kutusu, saçak/balkon dahil, konservatif) yönlü dikdörtgen; yön sözleşmesi
## `SettlementObb` (yerel +X -> (cos yaw, -sin yaw), +Z -> (sin yaw, cos yaw)).

const BUILDING_CELL_M := 32.0
const ROAD_CELL_M := 48.0
const FAR := 1.0e9
const KEY_STRIDE := 8192
const KEY_OFFSET := 2048

## Bu uzaklıktan uzak bina/yol "yok" sayılır (sorgu tavanı; hücre ızgarası bu paya göre dolar).
var cap_m: float = 12.0

var _world: WorldData = null
# Binalar (sütun dizini = BuildingColumns satırı).
var _bx: PackedFloat32Array = PackedFloat32Array()
var _bz: PackedFloat32Array = PackedFloat32Array()
var _bcos: PackedFloat32Array = PackedFloat32Array()
var _bsin: PackedFloat32Array = PackedFloat32Array()
var _bhw: PackedFloat32Array = PackedFloat32Array()
var _bhd: PackedFloat32Array = PackedFloat32Array()
var _bgrid: Dictionary = {}
var _built_area: Dictionary = {}
var _parcel_buildings: Dictionary = {}
# Yol doğru parçaları.
var _ax: PackedFloat32Array = PackedFloat32Array()
var _az: PackedFloat32Array = PackedFloat32Array()
var _ex: PackedFloat32Array = PackedFloat32Array()
var _ez: PackedFloat32Array = PackedFloat32Array()
var _half_full: PackedFloat32Array = PackedFloat32Array()
var _half_car: PackedFloat32Array = PackedFloat32Array()
var _seg_edge: PackedInt32Array = PackedInt32Array()
var _rgrid: Dictionary = {}
var _node_radius: Dictionary = {}
# Şehre uzaklık (dünya hücresi başına, m) ve kent bloğu maskesi.
var _urban_dist: PackedFloat32Array = PackedFloat32Array()
var _mask: PackedByteArray = PackedByteArray()
var _mask_origin: Vector2 = Vector2.ZERO
var _mask_cell: float = 25.0
var _mask_w: int = 0
var _mask_h: int = 0


## `sidewalk`: yol sınıfı -> kaldırım bandı (m, `road_style.json` ile aynı); `junction_pad`: kavşak düğümü boşluk payı.
func build(res: SettlementResult, world: WorldData, sidewalk: Dictionary, p_cap_m: float, junction_pad: float,
		mask_cell_m: float) -> void:
	_world = world
	cap_m = p_cap_m
	_build_buildings(res)
	_build_roads(res.net, sidewalk, junction_pad)
	_build_urban_distance()
	_build_block_mask(res.net, mask_cell_m)


# ---------------------------------------------------------------- sorgular

## En yakın bina ayak izine uzaklık (m); içindeyse 0; `cap_m` ötesi `cap_m`.
func building_distance(px: float, pz: float) -> float:
	var best := cap_m
	var bkey := _cell_key(px, pz, BUILDING_CELL_M)
	if not _bgrid.has(bkey):
		return best
	var list: PackedInt32Array = _bgrid[bkey]
	for i in list:
		var dx := px - _bx[i]
		var dz := pz - _bz[i]
		var lx := dx * _bcos[i] - dz * _bsin[i]
		var lz := dx * _bsin[i] + dz * _bcos[i]
		var ox := maxf(absf(lx) - _bhw[i], 0.0)
		var oz := maxf(absf(lz) - _bhd[i], 0.0)
		var d := sqrt(ox * ox + oz * oz)
		if d < best:
			best = d
	return best


## Yol kesitinin kenarına boşluk (m; yol içindeyse negatif): min(uzaklık - yarım genişlik). `carriageway_only`: yarım
## genişlik kaldırım bandı çıkarılmış araç yolu. `skip_edge` >= 0 ise o kenar sayılmaz. Yol yoksa `FAR`.
func road_gap(px: float, pz: float, carriageway_only: bool, skip_edge: int) -> float:
	var best := FAR
	var rkey := _cell_key(px, pz, ROAD_CELL_M)
	if not _rgrid.has(rkey):
		return best
	var list: PackedInt32Array = _rgrid[rkey]
	for s in list:
		if _seg_edge[s] == skip_edge:
			continue
		var abx := _ex[s] - _ax[s]
		var abz := _ez[s] - _az[s]
		var len2 := abx * abx + abz * abz
		var t := 0.0
		if len2 > 1.0e-9:
			t = clampf(((px - _ax[s]) * abx + (pz - _az[s]) * abz) / len2, 0.0, 1.0)
		var qx := px - (_ax[s] + abx * t)
		var qz := pz - (_az[s] + abz * t)
		var gap := sqrt(qx * qx + qz * qz) - (_half_car[s] if carriageway_only else _half_full[s])
		if gap < best:
			best = gap
	return best


## Düğümün çevresindeki boş yarıçap: bitişik kenarların en büyük yarım genişliği + kavşak payı.
func node_radius(node_id: int) -> float:
	return float(_node_radius.get(node_id, 0.0))


## En yakın bina hücresine uzaklık (m; bina hücresi = 0). Dünya hücre çözünürlüğündedir.
func urban_distance(px: float, pz: float) -> float:
	return _urban_dist[_world.world_to_index(px, pz)]


func urban_distance_at_index(idx: int) -> float:
	return _urban_dist[idx]


## Nokta, kentsel (kırsal olmayan, parsellenmiş) bir bloğun yüzünde mi (yol eksenleri arası, yolun yarısı dahil).
func in_urban_block(px: float, pz: float) -> bool:
	var ix := int(floor((px - _mask_origin.x) / _mask_cell))
	var iz := int(floor((pz - _mask_origin.y) / _mask_cell))
	if ix < 0 or iz < 0 or ix >= _mask_w or iz >= _mask_h:
		return false
	return _mask[iz * _mask_w + ix] != 0


## Parselin yapı ayak izi alanı (m2); yapı yoksa 0.
func built_area_of(parcel_id: int) -> float:
	return float(_built_area.get(parcel_id, 0.0))


## Parselin bina satırları (BuildingColumns dizini); yoksa boş.
func buildings_of(parcel_id: int) -> PackedInt32Array:
	return _parcel_buildings.get(parcel_id, PackedInt32Array())


func building_count() -> int:
	return _bx.size()


func segment_count() -> int:
	return _ax.size()


## Bina `i` dikdörtgeni (test/tanı): [cx, cz, cos, sin, yarım_w, yarım_d].
func building_rect(i: int) -> PackedFloat32Array:
	return PackedFloat32Array([_bx[i], _bz[i], _bcos[i], _bsin[i], _bhw[i], _bhd[i]])


# ---------------------------------------------------------------- kurulum

func _build_buildings(res: SettlementResult) -> void:
	var cols := res.columns
	for i in cols.count:
		var m := res.rules.modules[cols.module_idx[i]]
		var yaw := cols.yaw[i]
		_bx.append(cols.x[i])
		_bz.append(cols.z[i])
		_bcos.append(cos(yaw))
		_bsin.append(sin(yaw))
		_bhw.append(m.w * 0.5)
		_bhd.append(m.d * 0.5)
		var pid := cols.parcel_id[i]
		_built_area[pid] = float(_built_area.get(pid, 0.0)) + m.w * m.d
		var list: PackedInt32Array = _parcel_buildings.get(pid, PackedInt32Array())
		list.append(i)
		_parcel_buildings[pid] = list
		var reach := sqrt(m.w * m.w + m.d * m.d) * 0.5 + cap_m
		_insert(_bgrid, BUILDING_CELL_M, i, cols.x[i] - reach, cols.z[i] - reach, cols.x[i] + reach,
				cols.z[i] + reach)


func _build_roads(net: WorldNetwork, sidewalk: Dictionary, junction_pad: float) -> void:
	var ids := PackedInt32Array(net.edges.keys())
	ids.sort()
	for eid in ids:
		var e: WorldRoadEdge = net.edges[eid]
		if e.road_class == WorldRoadEdge.CLASS_FERRY or e.width <= 0.0:
			continue
		var a := net.node_pos(e.a)
		var b := net.node_pos(e.b)
		var half := e.width * 0.5
		var side := float(sidewalk.get(String(e.road_class), 0.0))
		var s := _ax.size()
		_ax.append(a.x)
		_az.append(a.y)
		_ex.append(b.x)
		_ez.append(b.y)
		_half_full.append(half)
		_half_car.append(maxf(half - side, half * 0.5))
		_seg_edge.append(eid)
		var pad := half + cap_m
		_insert(_rgrid, ROAD_CELL_M, s, minf(a.x, b.x) - pad, minf(a.y, b.y) - pad, maxf(a.x, b.x) + pad,
				maxf(a.y, b.y) + pad)
		for node_id in [e.a, e.b]:
			_node_radius[node_id] = maxf(float(_node_radius.get(node_id, 0.0)), half + junction_pad)


func _build_urban_distance() -> void:
	var w := _world.width
	var h := _world.height
	var n := w * h
	_urban_dist.resize(n)
	_urban_dist.fill(FAR)
	for i in _bx.size():
		_urban_dist[_world.world_to_index(_bx[i], _bz[i])] = 0.0
	var step := _world.cell_size
	var diag := step * 1.41421356
	for j in h:
		for i in w:
			var k := j * w + i
			var d := _urban_dist[k]
			if i > 0:
				d = minf(d, _urban_dist[k - 1] + step)
			if j > 0:
				d = minf(d, _urban_dist[k - w] + step)
				if i > 0:
					d = minf(d, _urban_dist[k - w - 1] + diag)
				if i < w - 1:
					d = minf(d, _urban_dist[k - w + 1] + diag)
			_urban_dist[k] = d
	for j in range(h - 1, -1, -1):
		for i in range(w - 1, -1, -1):
			var k := j * w + i
			var d := _urban_dist[k]
			if i < w - 1:
				d = minf(d, _urban_dist[k + 1] + step)
			if j < h - 1:
				d = minf(d, _urban_dist[k + w] + step)
				if i < w - 1:
					d = minf(d, _urban_dist[k + w + 1] + diag)
				if i > 0:
					d = minf(d, _urban_dist[k + w - 1] + diag)
			_urban_dist[k] = d


func _build_block_mask(net: WorldNetwork, mask_cell_m: float) -> void:
	_mask_cell = mask_cell_m
	_mask_origin = _world.origin
	_mask_w = int(ceil(_world.size.x / _mask_cell))
	_mask_h = int(ceil(_world.size.y / _mask_cell))
	_mask.resize(_mask_w * _mask_h)
	var ids := PackedInt32Array(net.blocks.keys())
	ids.sort()
	for bid in ids:
		var b: WorldBlock = net.blocks[bid]
		if b.kind != WorldBlock.KIND_PARCELIZED or b.fabric == &"rural" or b.outline.size() < 3:
			continue
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for p in b.outline:
			lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
			hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
		var x0 := clampi(int(floor((lo.x - _mask_origin.x) / _mask_cell)), 0, _mask_w - 1)
		var x1 := clampi(int(floor((hi.x - _mask_origin.x) / _mask_cell)), 0, _mask_w - 1)
		var z0 := clampi(int(floor((lo.y - _mask_origin.y) / _mask_cell)), 0, _mask_h - 1)
		var z1 := clampi(int(floor((hi.y - _mask_origin.y) / _mask_cell)), 0, _mask_h - 1)
		for iz in range(z0, z1 + 1):
			for ix in range(x0, x1 + 1):
				var c := _mask_origin + (Vector2(ix, iz) + Vector2(0.5, 0.5)) * _mask_cell
				if Geometry2D.is_point_in_polygon(c, b.outline):
					_mask[iz * _mask_w + ix] = 1


static func _cell_key(px: float, pz: float, cell: float) -> int:
	return (int(floor(px / cell)) + KEY_OFFSET) + (int(floor(pz / cell)) + KEY_OFFSET) * KEY_STRIDE


static func _insert(grid: Dictionary, cell: float, id: int, x0: float, z0: float, x1: float, z1: float) -> void:
	var cx0 := int(floor(x0 / cell))
	var cx1 := int(floor(x1 / cell))
	var cz0 := int(floor(z0 / cell))
	var cz1 := int(floor(z1 / cell))
	for cz in range(cz0, cz1 + 1):
		for cx in range(cx0, cx1 + 1):
			var key := (cx + KEY_OFFSET) + (cz + KEY_OFFSET) * KEY_STRIDE
			var list: PackedInt32Array = grid.get(key, PackedInt32Array())
			list.append(id)
			grid[key] = list
