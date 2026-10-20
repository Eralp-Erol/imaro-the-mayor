# gdlint:disable=max-public-methods
class_name WorldNetwork
extends RefCounted
## Tek dünya verisinin AĞ katmanı (T-011; WLD-01, TEK-03, CAN-03/04/05): yol düğümleri/kenarları, kenarlardan türeyen
## bloklar ve bloklardan türeyen parseller. Sim (parsel/mülkiyet/imar), render (yol/yapı) ve oyuncunun yol çizmesi
## yalnız bu sınıfın sorgu API'sini okur. Saf: RefCounted, Node/Time/OS/global rastgelelik yok.
##
## Kıyı/su/yükseklik `world` (WorldData) başvurusundan gelir; ağ KENDİ su/yükseklik kopyasını tutmaz (TEK-03).
## Taban + delta: tohum + kontrol verisi tabanı yeniden üretir (`NetworkGenerator`); oyuncunun yol ekleme/silme
## komutları `delta`da sırayla durur (kayıt = tohum + delta). Ağ parsel SAHİPLİĞİNİ üretmez: `WorldParcel.owner_id`
## boş yuvadır, sim (T-013) doldurur (CAN-03); özel bina oluşturulmaz.
##
## Koordinat: dünya metresi, x = doğu, y = güney (Vector2.y = dünya z'si).

const MODE_ROAD := &"road"
const MODE_RAIL := &"rail"
const MODE_FERRY := &"ferry"
const SCHEMA_VERSION := 1
const NODE_CELL_M := 32.0
const EDGE_CELL_M := 128.0
const BLOCK_CELL_M := 256.0
const PARCEL_CELL_M := 64.0
## Oyuncu yolunun su üstünden geçmediğini örnekleme adımı (m).
const WATER_SAMPLE_STEP_M := 20.0
## Parsel kara denetimi: blok merkezi kıyıdan bu kadar (blok çapı + pay) uzaktaysa tek tek denetim atlanır.
const LAND_FAST_PATH_MARGIN_M := 60.0
## Parsel bölge kodu bloktan alınır (blok bu boyuttan küçükse); aksi halde parsel merkezine göre.
const BLOCK_REGION_MAX_M := 400.0
## Paralel iz (yol yanında ray): ara düğüm ek kaydırma payı (m).
const PARALLEL_CLEARANCE_M := 4.0
## Ofseti geçersiz bir yüz bu alandan büyükse sliver değil parselsiz açık arazi (kama) sayılır.
const OPEN_WEDGE_MIN_AREA_M2 := 20000.0

var world: WorldData = null
var rules: NetworkRules = null
var net_seed: int = 0
var nodes: Dictionary = {}
var edges: Dictionary = {}
var blocks: Dictionary = {}
var parcels: Dictionary = {}
## Düğüm kimliği -> o düğümdeki kenar kimlikleri (PackedInt32Array).
var adjacency: Dictionary = {}
## Doku kimliği (bölge kodu veya T0 saha çıkıntısı kimliği) -> merkez düğüm kimliği (türetilmiş, hash'e girer).
var hubs: Dictionary = {}
var delta: NetworkDelta = NetworkDelta.new()
var base_hash: String = ""
var sealed: bool = false
var graph_version: int = 0

var _node_grid: NetworkSpatialHash = NetworkSpatialHash.new(NODE_CELL_M)
var _edge_grid: NetworkSpatialHash = NetworkSpatialHash.new(EDGE_CELL_M)
var _block_grid: NetworkSpatialHash = NetworkSpatialHash.new(BLOCK_CELL_M)
var _parcel_grid: NetworkSpatialHash = NetworkSpatialHash.new(PARCEL_CELL_M)
var _edge_parcels: Dictionary = {}
var _block_by_sig: Dictionary = {}
var _component_cache: Dictionary = {}
var _next_node_id: int = 1
var _next_edge_id: int = 1
var _next_block_id: int = 1
var _next_parcel_id: int = 1


static func create(p_world: WorldData, p_rules: NetworkRules, p_seed: int) -> WorldNetwork:
	var net := WorldNetwork.new()
	net.world = p_world
	net.rules = p_rules
	net.net_seed = p_seed
	return net


# ---------------------------------------------------------------- ham düzenleme (üreteç + planarizer)

func add_node_raw(pos: Vector2, kind: StringName = &"") -> int:
	var node := WorldRoadNode.new()
	node.id = _next_node_id
	_next_node_id += 1
	node.pos = Vector2(snappedf(pos.x, 0.01), snappedf(pos.y, 0.01))
	node.kind = kind
	nodes[node.id] = node
	adjacency[node.id] = PackedInt32Array()
	_node_grid.insert(node.id, Rect2(node.pos, Vector2.ZERO))
	_touch()
	return node.id


## İki düğüm arasında kenar ekler. Aynı çift arasında kenar varsa YENİSİ açılmaz: sınıf üst sınıfa yükseltilir
## (aynı kipte), genişlik büyük olana çekilir. Dönüş: kenar kimliği.
func add_edge_raw(a: int, b: int, road_class: StringName, width: float, layer: int = 0, is_open: bool = true) -> int:
	var existing := edge_between(a, b)
	if existing >= 0:
		var e: WorldRoadEdge = edges[existing]
		if e.mode() != WorldRoadEdge.mode_of(road_class):
			return _add_parallel_track(a, b, e, road_class, width, layer, is_open)
		if WorldRoadEdge.rank(road_class) > WorldRoadEdge.rank(e.road_class):
			e.road_class = road_class
			e.width = maxf(e.width, width)
			_touch()
		return existing
	var edge := WorldRoadEdge.new()
	edge.id = _next_edge_id
	_next_edge_id += 1
	edge.a = a
	edge.b = b
	edge.road_class = road_class
	edge.width = width
	edge.open = is_open
	edge.layer = layer
	edge.length = node_pos(a).distance_to(node_pos(b))
	edges[edge.id] = edge
	_adjacency_add(a, edge.id)
	_adjacency_add(b, edge.id)
	_edge_grid.insert(edge.id, _edge_rect(edge))
	_touch()
	return edge.id


## Aynı düğüm çifti arasında başka kipte (örn. yol üstüne ray) kenar var: iz paralel yürür; ara düğüm yolun soluna,
## iki genişliğin yarısı + pay kadar kaydırılır. Dönüş: ikinci parça kenarı. Böylece ray yolun üzerinde sessizce
## kaybolmaz.
func _add_parallel_track(a: int, b: int, existing: WorldRoadEdge, road_class: StringName, width: float, layer: int,
		is_open: bool) -> int:
	var pa := node_pos(a)
	var pb := node_pos(b)
	var d := pb - pa
	var normal := Vector2(-d.y, d.x).normalized()
	var offset := (existing.width + width) * 0.5 + PARALLEL_CLEARANCE_M
	var mid := add_node_raw((pa + pb) * 0.5 + normal * offset)
	add_edge_raw(a, mid, road_class, width, layer, is_open)
	return add_edge_raw(mid, b, road_class, width, layer, is_open)


## Düğümü taşır (yalnız tohumlu konum sapması için; topoloji değişmez). Komşu kenar uzunlukları/ızgaralar güncellenir.
func move_node_raw(node_id: int, pos: Vector2) -> void:
	var node: WorldRoadNode = nodes[node_id]
	node.pos = Vector2(snappedf(pos.x, 0.01), snappedf(pos.y, 0.01))
	_node_grid.insert(node_id, Rect2(node.pos, Vector2.ZERO))
	for eid in adjacency[node_id]:
		var e: WorldRoadEdge = edges[eid]
		e.length = node_pos(e.a).distance_to(node_pos(e.b))
		_edge_grid.insert(eid, _edge_rect(e))
	_touch()


func remove_edge_raw(edge_id: int) -> void:
	if not edges.has(edge_id):
		return
	var e: WorldRoadEdge = edges[edge_id]
	_adjacency_remove(e.a, edge_id)
	_adjacency_remove(e.b, edge_id)
	edges.erase(edge_id)
	_edge_grid.remove(edge_id)
	_touch()


func remove_node_raw(node_id: int) -> void:
	nodes.erase(node_id)
	adjacency.erase(node_id)
	_node_grid.remove(node_id)
	_touch()


## Kenarı `node_id` düğümünde böler: eski kenar (a -> node) olur, yeni kenar (node -> b) eklenir. Dönüş: yeni kenar.
func split_edge_raw(edge_id: int, node_id: int) -> int:
	var e: WorldRoadEdge = edges[edge_id]
	var old_b := e.b
	_adjacency_remove(old_b, edge_id)
	e.b = node_id
	e.length = node_pos(e.a).distance_to(node_pos(node_id))
	_adjacency_add(node_id, edge_id)
	_edge_grid.insert(edge_id, _edge_rect(e))
	var new_id := add_edge_raw(node_id, old_b, e.road_class, e.width, e.layer, e.open)
	_touch()
	return new_id


func edge_between(a: int, b: int) -> int:
	for eid in adjacency.get(a, PackedInt32Array()):
		if (edges[eid] as WorldRoadEdge).other(a) == b:
			return eid
	return -1


func node_pos(node_id: int) -> Vector2:
	return (nodes[node_id] as WorldRoadNode).pos


## Yarıçap içindeki EN YAKIN düğüm (eşitlikte küçük kimlik); yoksa -1.
func nearest_node_within(pos: Vector2, radius: float) -> int:
	var best := -1
	var best_d := radius + 1.0e-9
	for nid in _node_grid.query_rect(Rect2(pos, Vector2.ZERO).grow(radius)):
		var d := node_pos(nid).distance_to(pos)
		if d < best_d - 1.0e-12 or (absf(d - best_d) <= 1.0e-12 and best >= 0 and nid < best):
			best_d = d
			best = nid
	return best


func node_ids_in_rect(rect: Rect2) -> PackedInt32Array:
	return _node_grid.query_rect(rect)


func edge_ids_in_rect(rect: Rect2) -> PackedInt32Array:
	return _edge_grid.query_rect(rect)


## Tabanı kurarken çok çizgili yol ekler (delta'ya YAZILMAZ). Dönüş: planarizer raporu.
func author_polyline(points: PackedVector2Array, road_class: StringName, width: float = -1.0) -> Dictionary:
	assert(not sealed, "author_polyline yalnız taban mühürlenmeden önce")
	var w := width if width > 0.0 else rules.width_of(road_class)
	return NetworkPlanarizer.draw(self, points, road_class, w, WorldRoadEdge.LAYER_BASE)


## Tabanı mühürler: blokları/parselleri üretir, taban özetini kaydeder; bundan sonra yalnız delta komutları.
func seal_base() -> void:
	refresh_blocks()
	base_hash = graph_hash()
	delta = NetworkDelta.new()
	delta.base_hash = base_hash
	sealed = true


# ---------------------------------------------------------------- oyuncu komutları (delta; CAN-04)

## Oyuncu yolu ekler (planarize edilir). Su üstünden geçen yol reddedilir (delta'ya yazılmaz). Dönüş: değişiklik
## raporu {ok, error, added_edges, split_edges, removed_edges, added_blocks, removed_blocks, added_parcels,
## removed_parcels}.
func add_road(points: PackedVector2Array, road_class: StringName, width_m: float = -1.0) -> Dictionary:
	var op := {"op": "add_road", "pts_cm": NetworkDelta.encode_points(points), "class": String(road_class),
			"width_dm": int(round((width_m if width_m > 0.0 else rules.width_of(road_class)) * 10.0))}
	return _apply_op(op, true)


func remove_edge(edge_id: int) -> Dictionary:
	return _apply_op({"op": "remove_edge", "edge": edge_id}, true)


func set_edge_open(edge_id: int, is_open: bool) -> Dictionary:
	return _apply_op({"op": "set_open", "edge": edge_id, "open": is_open}, true)


## Delta'yı tabandan itibaren sırayla uygular. Taban özeti uyuşmazsa reddeder. Dönüş: {ok, error, applied}.
func apply_delta(d: NetworkDelta) -> Dictionary:
	if not sealed:
		return {"ok": false, "error": "taban mühürlü değil", "applied": 0}
	if d.base_hash != base_hash:
		return {"ok": false, "error": "taban özeti uyuşmuyor (veri/üreteç değişmiş)", "applied": 0}
	var applied := 0
	for op in d.ops:
		var report := _apply_op(op, true)
		if not bool(report["ok"]):
			return {"ok": false, "error": "op %d: %s" % [applied, str(report["error"])], "applied": applied}
		applied += 1
	return {"ok": true, "error": "", "applied": applied}


func _apply_op(op: Dictionary, record: bool) -> Dictionary:
	var report := _new_report()
	if not sealed:
		report["ok"] = false
		report["error"] = "taban mühürlü değil"
		return report
	match str(op.get("op", "")):
		"add_road":
			_op_add_road(op, report)
		"remove_edge":
			_op_remove_edge(op, report)
		"set_open":
			_op_set_open(op, report)
		_:
			report["ok"] = false
			report["error"] = "bilinmeyen op"
	if not bool(report["ok"]):
		return report
	if record:
		delta.ops.append(op)
	var refreshed := refresh_blocks()
	for key in ["added_blocks", "removed_blocks", "added_parcels", "removed_parcels"]:
		report[key] = refreshed[key]
	return report


func _op_add_road(op: Dictionary, report: Dictionary) -> void:
	var cls := StringName(str(op.get("class", "local")))
	if not WorldRoadEdge.ALL_CLASSES.has(cls) or cls == WorldRoadEdge.CLASS_FERRY:
		report["ok"] = false
		report["error"] = "geçersiz yol sınıfı"
		return
	var points := NetworkDelta.decode_points(op.get("pts_cm", []))
	if points.size() < 2:
		report["ok"] = false
		report["error"] = "en az iki nokta gerekli"
		return
	if not _polyline_on_dry_land(points):
		report["ok"] = false
		report["error"] = "yol su üstünden geçemez"
		return
	var total := 0.0
	for i in range(points.size() - 1):
		total += points[i].distance_to(points[i + 1])
	if total < rules.min_edge_m:
		report["ok"] = false
		report["error"] = "yol çok kısa"
		return
	var drawn := NetworkPlanarizer.draw(self, points, cls, float(op.get("width_dm", 100)) * 0.1,
			WorldRoadEdge.LAYER_DELTA)
	report["added_edges"] = Array(drawn["edges"])
	report["split_edges"] = Array(drawn["split_edges"])


func _op_remove_edge(op: Dictionary, report: Dictionary) -> void:
	var edge_id := int(op.get("edge", -1))
	if not edges.has(edge_id):
		report["ok"] = false
		report["error"] = "kenar yok"
		return
	var e: WorldRoadEdge = edges[edge_id]
	if e.road_class == WorldRoadEdge.CLASS_FERRY:
		report["ok"] = false
		report["error"] = "feribot hattı oyuncu komutuyla silinemez"
		return
	var ends: Array[int] = [e.a, e.b]
	remove_edge_raw(edge_id)
	WorldNetwork.report_add(report, "removed_edges", edge_id)
	for end_id in ends:
		_cleanup_node(end_id, report)


func _op_set_open(op: Dictionary, report: Dictionary) -> void:
	var edge_id := int(op.get("edge", -1))
	if not edges.has(edge_id):
		report["ok"] = false
		report["error"] = "kenar yok"
		return
	(edges[edge_id] as WorldRoadEdge).open = bool(op.get("open", true))
	_touch()


## Kenar silindikten sonra düğüm temizliği: yalnız kalan düğüm silinir (hub değilse); iki kenarlı eşdoğrusal düğüm
## aynı özellikli kenarları birleştirir (ekle + sil taban durumuna döner).
func _cleanup_node(node_id: int, report: Dictionary) -> void:
	if not nodes.has(node_id):
		return
	var node: WorldRoadNode = nodes[node_id]
	var list: PackedInt32Array = adjacency[node_id]
	if list.is_empty():
		if node.kind == WorldRoadNode.KIND_JUNCTION and not hubs.values().has(node_id):
			remove_node_raw(node_id)
		return
	if list.size() != 2 or node.kind != WorldRoadNode.KIND_JUNCTION or hubs.values().has(node_id):
		return
	var e1: WorldRoadEdge = edges[mini(list[0], list[1])]
	var e2: WorldRoadEdge = edges[maxi(list[0], list[1])]
	if e1.road_class != e2.road_class or absf(e1.width - e2.width) > 0.01 or e1.open != e2.open \
			or e1.layer != e2.layer:
		return
	var o1 := node_pos(e1.other(node_id))
	var o2 := node_pos(e2.other(node_id))
	var d1 := o1 - node.pos
	var d2 := o2 - node.pos
	var cross := absf(float(d1.x) * float(d2.y) - float(d1.y) * float(d2.x))
	if cross > 1.0e-3 * d1.length() * d2.length() or float(d1.dot(d2)) >= 0.0:
		return
	var far_end := e2.other(node_id)
	remove_edge_raw(e2.id)
	if e1.b == node_id:
		e1.b = far_end
	else:
		e1.a = far_end
	e1.length = node_pos(e1.a).distance_to(node_pos(e1.b))
	_adjacency_add(far_end, e1.id)
	_adjacency_remove(node_id, e1.id)
	_edge_grid.insert(e1.id, _edge_rect(e1))
	remove_node_raw(node_id)
	WorldNetwork.report_add(report, "removed_edges", e2.id)


func _polyline_on_dry_land(points: PackedVector2Array) -> bool:
	for i in range(points.size() - 1):
		var a := points[i]
		var b := points[i + 1]
		var steps := maxi(1, int(ceil(a.distance_to(b) / WATER_SAMPLE_STEP_M)))
		for s in steps + 1:
			var p := a.lerp(b, float(s) / float(steps))
			if world.is_water(p.x, p.y):
				return false
	return true


## Rapor listesine kimlik ekler (rapor listeleri düz Array'dir: referans tipi, yerinde eklenir, kopyalanmaz).
static func report_add(report: Dictionary, key: String, id: int) -> void:
	(report[key] as Array).append(id)


func _new_report() -> Dictionary:
	return {"ok": true, "error": "", "added_edges": [], "split_edges": [], "removed_edges": [],
			"added_blocks": [], "removed_blocks": [], "added_parcels": [], "removed_parcels": []}


# ---------------------------------------------------------------- bloklar ve parseller

## Yüzleri yeniden türetir; geometri imzası aynı olan bloklar (ve parselleri, mülkiyet yuvaları dahil) KORUNUR,
## değişenler yeniden üretilir. Dönüş: {added_blocks, removed_blocks, added_parcels, removed_parcels}.
func refresh_blocks() -> Dictionary:
	var report := {"added_blocks": [], "removed_blocks": [], "added_parcels": [], "removed_parcels": []}
	var matched := {}
	for face in NetworkBlocks.extract(self):
		var sig: String = face["signature"]
		var old_id := int(_block_by_sig.get(sig, -1))
		if old_id >= 0 and not matched.has(old_id) and blocks.has(old_id):
			matched[old_id] = true
			_update_matched_block(blocks[old_id], face)
			continue
		var block := _build_block(face, report)
		matched[block.id] = true
		WorldNetwork.report_add(report, "added_blocks", block.id)
	for old_id: int in blocks.keys():
		if not matched.has(old_id):
			_remove_block(old_id, report)
			WorldNetwork.report_add(report, "removed_blocks", old_id)
	return report


func _update_matched_block(block: WorldBlock, face: Dictionary) -> void:
	block.outline = face["points"]
	var new_edges: PackedInt32Array = face["edge_ids"]
	if new_edges == block.edge_ids:
		return
	block.edge_ids = new_edges
	for pid in block.parcel_ids:
		var parcel: WorldParcel = parcels[pid]
		var best := -1
		var best_d := INF
		for eid in new_edges:
			var e: WorldRoadEdge = edges[eid]
			if not WorldRoadEdge.is_road_class(e.road_class):
				continue
			var d := NetworkGeometry.distance_point_segment(parcel.front_mid, node_pos(e.a), node_pos(e.b))
			if d < best_d - 1.0e-9:
				best_d = d
				best = eid
		if best >= 0 and best != parcel.frontage_edge:
			_set_frontage(parcel, best)


func _build_block(face: Dictionary, report: Dictionary) -> WorldBlock:
	var block := WorldBlock.new()
	block.id = _next_block_id
	_next_block_id += 1
	block.outline = face["points"]
	block.edge_ids = face["edge_ids"]
	block.signature = face["signature"]
	var center := NetworkGeometry.centroid(block.outline)
	block.region_code = rules.region_code_at(world, center)
	block.fabric = rules.template_at(center)
	var face_area := float(face["area"])
	if bool(face["holed"]):
		block.kind = WorldBlock.KIND_HOLED
	elif face_area > float(rules.template_params(block.fabric).get("max_block_area_m2", rules.max_block_area_m2)):
		block.kind = WorldBlock.KIND_OPEN
	elif world.is_water(center.x, center.y):
		block.kind = WorldBlock.KIND_UNBUILDABLE
	else:
		_parcelize_block(block, face, report)
	blocks[block.id] = block
	_block_by_sig[block.signature] = block.id
	_block_grid.insert(block.id, NetworkGeometry.bounds(block.outline))
	return block


func _parcelize_block(block: WorldBlock, face: Dictionary, report: Dictionary) -> void:
	var offsets := PackedFloat64Array()
	for eid in block.edge_ids:
		offsets.append((edges[eid] as WorldRoadEdge).width * 0.5)
	var inset := NetworkGeometry.inset_polygon(block.outline, offsets)
	if (inset["points"] as PackedVector2Array).is_empty():
		# Ofset geçersiz: küçükse sliver; büyük düzensiz kama (paralel yollar arası) parselsiz açık arazi sayılır.
		block.kind = WorldBlock.KIND_OPEN if float(face["area"]) > OPEN_WEDGE_MIN_AREA_M2 else WorldBlock.KIND_SLIVER
		return
	block.buildable = inset["points"]
	block.area = NetworkGeometry.signed_area(block.buildable)
	if block.area < rules.min_block_area_m2:
		block.kind = WorldBlock.KIND_SLIVER
		return
	var tags := PackedInt32Array()
	for original: int in inset["edge_of"]:
		var tag := -1
		if original >= 0:
			var e: WorldRoadEdge = edges[block.edge_ids[original]]
			if WorldRoadEdge.is_road_class(e.road_class):
				tag = e.id
		tags.append(tag)
	var rng := RandomNumberGenerator.new()
	rng.seed = NetworkRules.stream_seed(net_seed, "parcels:" + block.signature)
	var params := rules.template_params(block.fabric)
	var lots := NetworkParcelizer.subdivide(block.buildable, tags, params, rng)
	var check_land := _needs_land_check(block)
	var block_rect := NetworkGeometry.bounds(block.outline)
	var spurs: PackedInt32Array = face["spurs"]
	block.kind = WorldBlock.KIND_PARCELIZED
	for lot in lots:
		var outline: PackedVector2Array = lot["outline"]
		if check_land and not _outline_on_land(outline):
			continue
		if not spurs.is_empty() and _touches_spur(outline, spurs):
			continue
		var parcel := _make_parcel(block, block_rect, lot, rng)
		WorldNetwork.report_add(report, "added_parcels", parcel.id)


func _make_parcel(block: WorldBlock, block_rect: Rect2, lot: Dictionary, rng: RandomNumberGenerator) -> WorldParcel:
	var parcel := WorldParcel.new()
	parcel.id = _next_parcel_id
	_next_parcel_id += 1
	parcel.block_id = block.id
	parcel.outline = lot["outline"]
	parcel.centroid = NetworkGeometry.average(parcel.outline)
	parcel.area = NetworkGeometry.signed_area(parcel.outline)
	parcel.front_length = float(lot["front_len"])
	parcel.front_mid = lot["front_mid"]
	# Küçük blokta bölge/doku bloktan; büyük (kırsal) blokta parsel merkezine göre (bölge sınırı bloğu kesebilir).
	if block_rect.size.x < BLOCK_REGION_MAX_M and block_rect.size.y < BLOCK_REGION_MAX_M:
		parcel.region_code = block.region_code
		parcel.fabric = block.fabric
	else:
		parcel.region_code = rules.region_code_at(world, parcel.centroid)
		parcel.fabric = rules.template_at(parcel.centroid)
	parcel.detail = rng.randi()
	parcels[parcel.id] = parcel
	block.parcel_ids.append(parcel.id)
	_parcel_grid.insert(parcel.id, NetworkGeometry.bounds(parcel.outline))
	_set_frontage(parcel, int(lot["frontage"]))
	return parcel


func _set_frontage(parcel: WorldParcel, edge_id: int) -> void:
	if parcel.frontage_edge >= 0 and _edge_parcels.has(parcel.frontage_edge):
		var old: PackedInt32Array = _edge_parcels[parcel.frontage_edge]
		var at := old.find(parcel.id)
		if at >= 0:
			old.remove_at(at)
		_edge_parcels[parcel.frontage_edge] = old
	parcel.frontage_edge = edge_id
	var list: PackedInt32Array = _edge_parcels.get(edge_id, PackedInt32Array())
	list.append(parcel.id)
	_edge_parcels[edge_id] = list


func _remove_block(block_id: int, report: Dictionary) -> void:
	var block: WorldBlock = blocks[block_id]
	for pid in block.parcel_ids:
		var parcel: WorldParcel = parcels[pid]
		if _edge_parcels.has(parcel.frontage_edge):
			var list: PackedInt32Array = _edge_parcels[parcel.frontage_edge]
			var at := list.find(pid)
			if at >= 0:
				list.remove_at(at)
			_edge_parcels[parcel.frontage_edge] = list
		parcels.erase(pid)
		_parcel_grid.remove(pid)
		WorldNetwork.report_add(report, "removed_parcels", pid)
	if int(_block_by_sig.get(block.signature, -1)) == block_id:
		_block_by_sig.erase(block.signature)
	blocks.erase(block_id)
	_block_grid.remove(block_id)


## Blok kıyıya yakınsa parseller tek tek kara denetiminden geçer (hızlı yol: iç bölgedeki bloklar).
func _needs_land_check(block: WorldBlock) -> bool:
	var rect := NetworkGeometry.bounds(block.outline)
	var center := rect.get_center()
	var idx := world.world_to_index(center.x, center.y)
	return float(world.shore_distance[idx]) < rect.size.length() * 0.5 + LAND_FAST_PATH_MARGIN_M \
			or world.landmass_ids[idx] != WorldData.LANDMASS_MAINLAND


func _outline_on_land(outline: PackedVector2Array) -> bool:
	for p in outline:
		if world.is_water(p.x, p.y):
			return false
	var c := NetworkGeometry.centroid(outline)
	return not world.is_water(c.x, c.y)


func _touches_spur(outline: PackedVector2Array, spurs: PackedInt32Array) -> bool:
	for eid in spurs:
		if not edges.has(eid):
			continue
		var e: WorldRoadEdge = edges[eid]
		if NetworkGeometry.segment_polygon_distance(node_pos(e.a), node_pos(e.b), outline) <= e.width * 0.5 + 0.5:
			return true
	return false


func _adjacency_add(node_id: int, edge_id: int) -> void:
	var list: PackedInt32Array = adjacency[node_id]
	list.append(edge_id)
	adjacency[node_id] = list


func _adjacency_remove(node_id: int, edge_id: int) -> void:
	var list: PackedInt32Array = adjacency[node_id]
	var at := list.find(edge_id)
	if at >= 0:
		list.remove_at(at)
	adjacency[node_id] = list


func _edge_rect(e: WorldRoadEdge) -> Rect2:
	var a := node_pos(e.a)
	var b := node_pos(e.b)
	return Rect2(a, Vector2.ZERO).expand(b)


func _touch() -> void:
	graph_version += 1
	_component_cache.clear()


# ---------------------------------------------------------------- sorgu API'si (görünüm ve sim yalnız bunu okur)

func node(node_id: int) -> WorldRoadNode:
	return nodes.get(node_id, null)


func edge(edge_id: int) -> WorldRoadEdge:
	return edges.get(edge_id, null)


func block(block_id: int) -> WorldBlock:
	return blocks.get(block_id, null)


func parcel(parcel_id: int) -> WorldParcel:
	return parcels.get(parcel_id, null)


## (x, z) noktasındaki parselin kimliği; yoksa (yol, su, blok dışı) -1.
func parcel_id_at(x: float, z: float) -> int:
	var p := Vector2(x, z)
	for pid in _parcel_grid.query_point(p):
		if NetworkGeometry.point_in_polygon(p, (parcels[pid] as WorldParcel).outline):
			return pid
	return -1


func parcel_at(x: float, z: float) -> WorldParcel:
	return parcels.get(parcel_id_at(x, z), null)


## (x, z) noktasını kapsayan blok yüzü (yol eksenleri arası); yoksa null. Yol ekseninde iki komşudan biri.
func block_at(x: float, z: float) -> WorldBlock:
	var p := Vector2(x, z)
	for bid in _block_grid.query_point(p):
		var b: WorldBlock = blocks[bid]
		if NetworkGeometry.point_in_polygon(p, b.outline):
			return b
	return null


## Noktaya `radius` içindeki kenarlar: (uzaklık, kimlik) sıralı. Kapalı kenarlar da döner (`open` bayrağına bakın).
func edges_near(x: float, z: float, radius: float) -> Array[WorldRoadEdge]:
	var p := Vector2(x, z)
	var scored: Array[Vector2] = []
	for eid in _edge_grid.query_rect(Rect2(p, Vector2.ZERO).grow(radius)):
		var e: WorldRoadEdge = edges[eid]
		var d := NetworkGeometry.distance_point_segment(p, node_pos(e.a), node_pos(e.b))
		if d <= radius:
			scored.append(Vector2(d, eid))
	scored.sort_custom(func(l: Vector2, r: Vector2) -> bool: return l.x < r.x or (l.x == r.x and l.y < r.y))
	var out: Array[WorldRoadEdge] = []
	for s in scored:
		out.append(edges[int(s.y)])
	return out


func region_of_parcel(parcel_id: int) -> StringName:
	var p: WorldParcel = parcels.get(parcel_id, null)
	return &"" if p == null else p.region_code


## Komşu düğümler (sıralı kimlik). `mode` boşsa tüm kipler; kapalı kenarlar yalnız `include_closed` ise.
func neighbors(node_id: int, mode: StringName = &"", include_closed: bool = false) -> PackedInt32Array:
	var out := PackedInt32Array()
	for eid in adjacency.get(node_id, PackedInt32Array()):
		var e: WorldRoadEdge = edges[eid]
		if (mode != &"" and e.mode() != mode) or (not e.open and not include_closed):
			continue
		var other := e.other(node_id)
		if not out.has(other):
			out.append(other)
	out.sort()
	return out


## En kısa yol (A*): `mode` = &"road" | &"rail" | &"ferry" (ayrı kipler; kapalı kenar geçilmez).
## Dönüş {found, nodes, edges, length}.
func shortest_path(from_id: int, to_id: int, mode: StringName = MODE_ROAD, class_scale: Dictionary = {}) -> Dictionary:
	return NetworkPathfinder.shortest_path(self, from_id, to_id, mode, class_scale)


## Dikdörtgenle kesişen parsellerin kimlikleri (sıralı).
func parcels_in_rect(rect: Rect2) -> PackedInt32Array:
	var out := PackedInt32Array()
	for pid in _parcel_grid.query_rect(rect):
		if NetworkGeometry.polygon_intersects_rect((parcels[pid] as WorldParcel).outline, rect):
			out.append(pid)
	return out


func block_parcels(block_id: int) -> PackedInt32Array:
	var b: WorldBlock = blocks.get(block_id, null)
	return PackedInt32Array() if b == null else b.parcel_ids


## Cephesi bu kenara bakan parseller (sıralı değil: üretim sırası).
func edge_parcels(edge_id: int) -> PackedInt32Array:
	return _edge_parcels.get(edge_id, PackedInt32Array())


## `mode` içinde düğüme en yakın düğüm (yalnız o kipte kenarı olan); yoksa -1.
func nearest_node(pos: Vector2, mode: StringName = MODE_ROAD, max_radius: float = 5000.0) -> int:
	var radius := NODE_CELL_M
	while radius <= max_radius * 2.0:
		var best := -1
		var best_d := INF
		for nid in _node_grid.query_rect(Rect2(pos, Vector2.ZERO).grow(radius)):
			if not _has_mode_edge(nid, mode):
				continue
			var d := node_pos(nid).distance_to(pos)
			if d < best_d or (d == best_d and nid < best):
				best_d = d
				best = nid
		if best >= 0 and best_d <= radius:
			return best
		radius *= 2.0
	return -1


func _has_mode_edge(node_id: int, mode: StringName) -> bool:
	for eid in adjacency[node_id]:
		if (edges[eid] as WorldRoadEdge).mode() == mode:
			return true
	return false


## Kipteki bağlı bileşenler (açık kenarlar): bileşen başına sıralı düğüm listesi; bileşenler en küçük düğüm
## kimliğine göre sıralı.
func components(mode: StringName = MODE_ROAD) -> Array[PackedInt32Array]:
	return _component_info(mode)["list"]


## Düğümün `mode` bileşen indeksi (components() sırasında); kipte kenarı yoksa -1.
func component_of(node_id: int, mode: StringName = MODE_ROAD) -> int:
	return int(_component_info(mode)["of"].get(node_id, -1))


func same_component(a: int, b: int, mode: StringName = MODE_ROAD) -> bool:
	var ca := component_of(a, mode)
	return ca >= 0 and ca == component_of(b, mode)


func _component_info(mode: StringName) -> Dictionary:
	if _component_cache.has(mode):
		return _component_cache[mode]
	var of := {}
	var list: Array[PackedInt32Array] = []
	var ids: Array = nodes.keys()
	ids.sort()
	for nid: int in ids:
		if of.has(nid) or not _has_mode_edge(nid, mode):
			continue
		var comp_index := list.size()
		var members := PackedInt32Array()
		var stack: Array[int] = [nid]
		of[nid] = comp_index
		while not stack.is_empty():
			var cur: int = stack.pop_back()
			members.append(cur)
			for eid in adjacency[cur]:
				var e: WorldRoadEdge = edges[eid]
				if not e.open or e.mode() != mode:
					continue
				var other := e.other(cur)
				if not of.has(other):
					of[other] = comp_index
					stack.append(other)
		members.sort()
		list.append(members)
	var info := {"of": of, "list": list}
	_component_cache[mode] = info
	return info


func counts() -> Dictionary:
	var parcelized := 0
	for b: WorldBlock in blocks.values():
		if b.kind == WorldBlock.KIND_PARCELIZED:
			parcelized += 1
	return {"nodes": nodes.size(), "edges": edges.size(), "blocks": blocks.size(),
			"parcelized_blocks": parcelized, "parcels": parcels.size()}


# ---------------------------------------------------------------- özetler (StateHash, TEK-01/02)

## Kanonik durum sözlüğü. Büyük sütunlar ham bayt SHA-256 ile özetlenir. `include_owner = false` mülkiyet yuvasını
## dışarıda bırakır (sim'in alanı; geometri özeti değişmesin).
func state_dict(include_owner: bool = true) -> Dictionary:
	var out := {"schema": SCHEMA_VERSION, "seed": net_seed, "nodes_sha": _sha(_node_columns()),
			"edges_sha": _sha(_edge_columns()), "blocks_sha": _sha(_block_columns()),
			"parcels_sha": _sha(_parcel_columns(include_owner)), "hubs": _hubs_dict()}
	return out


func state_hash(include_owner: bool = true) -> String:
	return StateHash.of(state_dict(include_owner))


## Taban özeti: yalnız graf (düğüm + kenar sütunları, hub'lar, tohum). Bloklar/parseller graftan ve tohumdan TÜRETİLİR;
## delta bu grafın üstüne uygulanır (parsel üretim kodu değişse delta yine uygulanır, parseller yeniden türer).
func graph_hash() -> String:
	return StateHash.of({"schema": SCHEMA_VERSION, "seed": net_seed, "nodes_sha": _sha(_node_columns()),
			"edges_sha": _sha(_edge_columns()), "hubs": _hubs_dict()})


## Yalnız topoloji: düğüm/kenar çiftleri, sınıf, açıklık, bloğun kenar çevrimleri (koordinat ve parsel ayrıntısı YOK).
func topology_hash() -> String:
	var ids: Array = nodes.keys()
	ids.sort()
	var parts := PackedStringArray()
	for nid: int in ids:
		parts.append("n%d:%s" % [nid, String((nodes[nid] as WorldRoadNode).kind)])
	var eids: Array = edges.keys()
	eids.sort()
	for eid: int in eids:
		var e: WorldRoadEdge = edges[eid]
		parts.append("e%d:%d-%d:%s:%d" % [eid, e.a, e.b, String(e.road_class), 1 if e.open else 0])
	var bids: Array = blocks.keys()
	bids.sort()
	for bid: int in bids:
		var b: WorldBlock = blocks[bid]
		var cycle := PackedStringArray()
		for eid in b.edge_ids:
			cycle.append(str(eid))
		parts.append("b%d:%s" % [bid, ",".join(cycle)])
	return StateHash.of({"topology": "\n".join(parts), "hubs": _hubs_dict()})


## Yalnız ayrıntı: düğüm koordinatları + parsel geometrisi/ayrıntı değerleri (tohum bunu değiştirir, topolojiyi
## değil).
func detail_hash() -> String:
	return StateHash.of({"nodes": _sha(_node_columns()), "parcels": _sha(_parcel_columns(false))})


func _hubs_dict() -> Dictionary:
	var out := {}
	for key in hubs:
		out[String(key)] = int(hubs[key])
	return out


func _node_columns() -> PackedByteArray:
	var ids: Array = nodes.keys()
	ids.sort()
	var nums := PackedFloat64Array()
	var text := PackedStringArray()
	for nid: int in ids:
		var n: WorldRoadNode = nodes[nid]
		nums.append_array(PackedFloat64Array([nid, n.pos.x, n.pos.y]))
		text.append(String(n.kind))
	return nums.to_byte_array() + ",".join(text).to_utf8_buffer()


func _edge_columns() -> PackedByteArray:
	var ids: Array = edges.keys()
	ids.sort()
	var nums := PackedFloat64Array()
	var text := PackedStringArray()
	for eid: int in ids:
		var e: WorldRoadEdge = edges[eid]
		nums.append_array(PackedFloat64Array([eid, e.a, e.b, e.width, 1.0 if e.open else 0.0, e.layer]))
		text.append(String(e.road_class))
	return nums.to_byte_array() + ",".join(text).to_utf8_buffer()


func _block_columns() -> PackedByteArray:
	var ids: Array = blocks.keys()
	ids.sort()
	var nums := PackedFloat64Array()
	var text := PackedStringArray()
	for bid: int in ids:
		var b: WorldBlock = blocks[bid]
		nums.append_array(PackedFloat64Array([bid, b.area, b.parcel_ids.size()]))
		text.append("%s|%s|%s|%s" % [String(b.kind), String(b.region_code), String(b.fabric), b.signature])
	return nums.to_byte_array() + ",".join(text).to_utf8_buffer()


func _parcel_columns(include_owner: bool) -> PackedByteArray:
	var ids: Array = parcels.keys()
	ids.sort()
	var nums := PackedFloat64Array()
	var text := PackedStringArray()
	for pid: int in ids:
		var p: WorldParcel = parcels[pid]
		nums.append_array(PackedFloat64Array([pid, p.block_id, p.frontage_edge, p.area, p.front_length, p.detail,
				p.owner_id if include_owner else 0]))
		for v in p.outline:
			nums.append_array(PackedFloat64Array([v.x, v.y]))
		text.append("%s|%s" % [String(p.region_code), String(p.fabric)])
	return nums.to_byte_array() + ",".join(text).to_utf8_buffer()


static func _sha(bytes: PackedByteArray) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(bytes if not bytes.is_empty() else PackedByteArray([0]))
	return ctx.finish().hex_encode()
