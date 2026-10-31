class_name NetworkHashCache
extends RefCounted
## `WorldNetwork.graph_hash()` için ARTIMLI önbellek (T-049; tick maliyeti). Hash DEĞERİ tam hesapla
## (`NetworkColumns.nodes/edges` + `NetworkColumns.sha`) BİT-BİT aynıdır; değişen yalnız bayt akışının kuruluşudur.
##
## Düğüm/kenar sütunları kimliğe göre SIRALI paralel dizilerdir (kimlik, sayısal kayıtlar, metin). Mühürlü ağda her
## düğüm/kenar değişimi `mark` ile kirli işaretlenir (`WorldNetwork._touch`, `NetworkRestore`); hash isteğinde yalnız
## kirli kimlikler kaynak sözlükten yeniden okunup yerinde güncellenir (ekleme sona, ortaya ekleme/silme dilimle). Kirli
## yoksa o sütunun SHA-256'sı önbellekten gelir. Dışarıdan, `_touch`/`mark` kullanmadan düğüm/kenar alanı yazan kod
## önbelleği bayatlatır: mühürlü ağda bu yasaktır (sim yalnız WorldNetwork API'si ve geri alma ile değiştirir).
## Saf: RefCounted, Node/Time/OS/global rastgelelik yok.

const NODE := 1
const EDGE := 2
const _NODE_STRIDE := 3
const _EDGE_STRIDE := 6

var _node_ids := PackedInt32Array()
var _node_nums := PackedFloat64Array()
var _node_text := PackedStringArray()
var _edge_ids := PackedInt32Array()
var _edge_nums := PackedFloat64Array()
var _edge_text := PackedStringArray()
var _dirty_nodes: Dictionary = {}
var _dirty_edges: Dictionary = {}
var _node_sha: String = ""
var _edge_sha: String = ""


## Tüm sütunları ağdan baştan kurar (mühürde bir kez).
static func build(net: WorldNetwork) -> NetworkHashCache:
	var cache := NetworkHashCache.new()
	var ids: Array = net.nodes.keys()
	ids.sort()
	for nid: int in ids:
		cache._node_ids.append(nid)
		cache._node_nums.append_array(_node_record(net.nodes[nid]))
		cache._node_text.append(String((net.nodes[nid] as WorldRoadNode).kind))
	ids = net.edges.keys()
	ids.sort()
	for eid: int in ids:
		cache._edge_ids.append(eid)
		cache._edge_nums.append_array(_edge_record(net.edges[eid]))
		cache._edge_text.append(String((net.edges[eid] as WorldRoadEdge).road_class))
	return cache


## Önbellek varsa kimliği kirli işaretler (geri alma yardımcıları `_touch` çağırmadığı için ayrı giriş).
static func mark_on(net: WorldNetwork, kind: int, id: int) -> void:
	if net._hash_cache != null:
		net._hash_cache.mark(kind, id)


func mark(kind: int, id: int) -> void:
	if kind == NODE:
		_dirty_nodes[id] = true
	else:
		_dirty_edges[id] = true


## Düğüm sütununun SHA-256'sı (`NetworkColumns.sha(NetworkColumns.nodes(net))` ile aynı).
func nodes_sha(net: WorldNetwork) -> String:
	if not _dirty_nodes.is_empty() or _node_sha.is_empty():
		for nid: int in _dirty_nodes:
			var rec := PackedFloat64Array()
			var text := ""
			var node: WorldRoadNode = net.nodes.get(nid, null)
			if node != null:
				rec = _node_record(node)
				text = String(node.kind)
			_apply(_node_ids, _node_nums, _node_text, _NODE_STRIDE, nid, node != null, rec, text)
		_dirty_nodes.clear()
		_node_sha = NetworkColumns.sha(_node_nums.to_byte_array() + ",".join(_node_text).to_utf8_buffer())
	return _node_sha


## Kenar sütununun SHA-256'sı (`NetworkColumns.sha(NetworkColumns.edges(net))` ile aynı).
func edges_sha(net: WorldNetwork) -> String:
	if not _dirty_edges.is_empty() or _edge_sha.is_empty():
		for eid: int in _dirty_edges:
			var rec := PackedFloat64Array()
			var text := ""
			var edge: WorldRoadEdge = net.edges.get(eid, null)
			if edge != null:
				rec = _edge_record(edge)
				text = String(edge.road_class)
			_apply(_edge_ids, _edge_nums, _edge_text, _EDGE_STRIDE, eid, edge != null, rec, text)
		_dirty_edges.clear()
		_edge_sha = NetworkColumns.sha(_edge_nums.to_byte_array() + ",".join(_edge_text).to_utf8_buffer())
	return _edge_sha


# `NetworkColumns.nodes` ile aynı sayısal kayıt: [kimlik, x, y] (float64).
static func _node_record(n: WorldRoadNode) -> PackedFloat64Array:
	return PackedFloat64Array([n.id, n.pos.x, n.pos.y])


# `NetworkColumns.edges` ile aynı sayısal kayıt: [kimlik, a, b, genişlik, açık, katman] (float64).
static func _edge_record(e: WorldRoadEdge) -> PackedFloat64Array:
	return PackedFloat64Array([e.id, e.a, e.b, e.width, 1.0 if e.open else 0.0, e.layer])


# Sıralı sütunlarda `id` kaydını yerinde günceller / araya ekler / siler.
static func _apply(ids: PackedInt32Array, nums: PackedFloat64Array, text: PackedStringArray, stride: int, id: int,
		exists: bool, rec: PackedFloat64Array, label: String) -> void:
	var pos := ids.bsearch(id)
	var present := pos < ids.size() and ids[pos] == id
	if exists and present:
		for k in stride:
			nums[pos * stride + k] = rec[k]
		text[pos] = label
	elif exists:
		if pos == ids.size():
			ids.append(id)
			nums.append_array(rec)
			text.append(label)
		else:
			ids.insert(pos, id)
			text.insert(pos, label)
			for k in stride:
				nums.insert(pos * stride + k, rec[k])
	elif present:
		ids.remove_at(pos)
		text.remove_at(pos)
		for k in stride:
			nums.remove_at(pos * stride)
