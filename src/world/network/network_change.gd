class_name NetworkChange
extends RefCounted
## Tek delta işleminin (uygulama ya da geri alma) DEĞİŞİM KAYDI (T-042 adım 1): görünüm yalnız etkilenen yol
## chunk'larını yeniden kurar (`RoadView.rebuild_chunks`), sim parsel kümesinin değişmediğini denetler. Durum DEĞİLDİR
## (hash'e girmez, kayda yazılmaz); WorldNetwork bellekte sınırlı bir günlük tutar. Saf RefCounted.

const KIND_APPLY := &"apply"
const KIND_UNDO := &"undo"
## Kavşak kırpması komşu kenarları da etkiler: segment kutuları ek bu pay kadar büyütülür (m).
const JUNCTION_MARGIN_M := 24.0

var kind: StringName = KIND_APPLY
var op_name: String = ""
## Uygulamada: delta.ops içindeki sıra. Geri almada: kaldırılan işlemin eski sırası.
var op_index: int = -1
## Değişimden SONRAKİ WorldNetwork.graph_version ve değişimden ÖNCEKİ sürüm (`changes_since` kapsama denetimi).
var graph_version: int = 0
var version_before: int = 0
## Yönlü kimlikler: "added" = bu değişimle ağda ARTIK VAR olan (geri almada: geri gelen), "removed" = artık yok.
var edges_added: PackedInt32Array = PackedInt32Array()
var edges_removed: PackedInt32Array = PackedInt32Array()
var edges_changed: PackedInt32Array = PackedInt32Array()
var nodes_added: PackedInt32Array = PackedInt32Array()
var nodes_removed: PackedInt32Array = PackedInt32Array()
## Blok/parsel yenilemesi raporu (parsel kümesi değişmezi için: v0'da ikisi de BOŞ olmalı).
var blocks_added: PackedInt32Array = PackedInt32Array()
var blocks_removed: PackedInt32Array = PackedInt32Array()
var parcels_added: PackedInt32Array = PackedInt32Array()
var parcels_removed: PackedInt32Array = PackedInt32Array()
## Eski ve yeni geometri parçaları + dokunulan düğümlerin komşu kenarları: [a: Vector2, b: Vector2, genişlik: float].
var segments: Array[Array] = []
## `segments` kutularının birleşimi (genişlik + kavşak payı ile büyütülmüş); boşsa Rect2() ve `is_empty`.
var dirty_rect: Rect2 = Rect2()
var is_empty: bool = true


## Parsel kümesi bu değişimle değişti mi (v0 değişmezi ihlali)?
func changes_parcels() -> bool:
	return not parcels_added.is_empty() or not parcels_removed.is_empty()


## Kenar kümesi (topoloji/sınıf/genişlik) değişti mi? false: yalnız aç/kapa gibi geometri dışı değişim.
func changes_graph() -> bool:
	return not (edges_added.is_empty() and edges_removed.is_empty() and edges_changed.is_empty() \
			and nodes_added.is_empty() and nodes_removed.is_empty())


## `RoadChunkPlan` ile aynı ızgarada (anahtar = floor((p - origin) / chunk_m)) etkilenen hücreler, sıralı ve tekil.
## `margin_m` ek pay. Görünüm bu kümeyi eski+yeni plan anahtarlarıyla birleştirir; bu yalnız dünya tarafı tahminidir.
func chunk_keys(origin: Vector2, chunk_m: float, margin_m: float = 0.0) -> Array[Vector2i]:
	var seen := {}
	var out: Array[Vector2i] = []
	for seg in segments:
		var rect := _segment_rect(seg, margin_m)
		var first := Vector2i(((rect.position - origin) / chunk_m).floor())
		var last := Vector2i(((rect.end - origin) / chunk_m).floor())
		for cy in range(first.y, last.y + 1):
			for cx in range(first.x, last.x + 1):
				var key := Vector2i(cx, cy)
				if not seen.has(key):
					seen[key] = true
					out.append(key)
	out.sort_custom(func(l: Vector2i, r: Vector2i) -> bool: return l.y < r.y or (l.y == r.y and l.x < r.x))
	return out


func to_dict() -> Dictionary:
	return {"kind": String(kind), "op": op_name, "op_index": op_index, "graph_version": graph_version,
			"edges_added": Array(edges_added), "edges_removed": Array(edges_removed),
			"edges_changed": Array(edges_changed), "nodes_added": Array(nodes_added),
			"nodes_removed": Array(nodes_removed), "blocks_added": Array(blocks_added),
			"blocks_removed": Array(blocks_removed), "parcels_added": Array(parcels_added),
			"parcels_removed": Array(parcels_removed), "dirty_rect": [dirty_rect.position.x, dirty_rect.position.y,
			dirty_rect.size.x, dirty_rect.size.y]}


## İşlem günlüğünden kayıt. `prior` yalnız geri almada: uygulama kaydı (yönler ters, parçalar birleşir).
static func from_journal(net: WorldNetwork, j: NetworkOpJournal, p_kind: StringName, refresh: Dictionary,
		prior: NetworkChange = null) -> NetworkChange:
	var c := NetworkChange.new()
	c.kind = p_kind
	c.op_name = str(j.op.get("op", ""))
	c.graph_version = net.graph_version
	if prior == null:
		c.edges_added = _existing(net, j.added_edge_ids)
		c.edges_removed = _missing(net, j.removed_edge_ids)
		c.edges_changed = _existing(net, j.changed_edge_ids, j.added_edge_ids)
		c.nodes_added = _node_existing(net, j.added_node_ids)
		c.nodes_removed = _node_missing(net, j.removed_node_ids)
		c.blocks_added = PackedInt32Array(refresh.get("added_blocks", []))
		c.blocks_removed = PackedInt32Array(refresh.get("removed_blocks", []))
		c.parcels_added = PackedInt32Array(refresh.get("added_parcels", []))
		c.parcels_removed = PackedInt32Array(refresh.get("removed_parcels", []))
	else:
		c.edges_added = prior.edges_removed
		c.edges_removed = prior.edges_added
		c.edges_changed = prior.edges_changed
		c.nodes_added = prior.nodes_removed
		c.nodes_removed = prior.nodes_added
		c.blocks_added = PackedInt32Array(refresh.get("restored_blocks", []))
		c.blocks_removed = PackedInt32Array(refresh.get("removed_blocks", []))
		c.parcels_added = PackedInt32Array(refresh.get("restored_parcels", []))
		c.parcels_removed = PackedInt32Array(refresh.get("removed_parcels", []))
		c.segments.append_array(prior.segments)
	c.segments.append_array(j.old_segments())
	var seen_edges := {}
	for nid: int in j.touched_nodes():
		if not net.adjacency.has(nid):
			continue
		for eid in net.adjacency[nid]:
			if seen_edges.has(eid):
				continue
			seen_edges[eid] = true
			var e: WorldRoadEdge = net.edges[eid]
			c.segments.append([net.node_pos(e.a), net.node_pos(e.b), e.width])
	for eid: int in j.changed_edge_ids:
		if net.edges.has(eid) and not seen_edges.has(eid):
			var e2: WorldRoadEdge = net.edges[eid]
			c.segments.append([net.node_pos(e2.a), net.node_pos(e2.b), e2.width])
	c._finish()
	return c


func _finish() -> void:
	is_empty = segments.is_empty()
	var first := true
	for seg in segments:
		var rect := _segment_rect(seg, JUNCTION_MARGIN_M)
		dirty_rect = rect if first else dirty_rect.merge(rect)
		first = false


static func _segment_rect(seg: Array, margin_m: float) -> Rect2:
	var a: Vector2 = seg[0]
	var b: Vector2 = seg[1]
	return Rect2(a, Vector2.ZERO).expand(b).grow(float(seg[2]) * 0.5 + margin_m)


static func _existing(net: WorldNetwork, ids: Dictionary, skip: Dictionary = {}) -> PackedInt32Array:
	var out := PackedInt32Array()
	for id: int in ids:
		if net.edges.has(id) and not skip.has(id):
			out.append(id)
	out.sort()
	return out


static func _missing(net: WorldNetwork, ids: Dictionary) -> PackedInt32Array:
	var out := PackedInt32Array()
	for id: int in ids:
		if not net.edges.has(id):
			out.append(id)
	out.sort()
	return out


static func _node_existing(net: WorldNetwork, ids: Dictionary) -> PackedInt32Array:
	var out := PackedInt32Array()
	for id: int in ids:
		if net.nodes.has(id):
			out.append(id)
	out.sort()
	return out


static func _node_missing(net: WorldNetwork, ids: Dictionary) -> PackedInt32Array:
	var out := PackedInt32Array()
	for id: int in ids:
		if not net.nodes.has(id):
			out.append(id)
	out.sort()
	return out
