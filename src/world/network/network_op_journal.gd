class_name NetworkOpJournal
extends RefCounted
## Tek delta işleminin (yol ekle/sil/aç-kapa) TERS günlüğü (T-042 adım 1; CAN-04, TEK-01/02). WorldNetwork ham düzenleme
## işlevleri günlüğe "önceki durumu" yazar; `undo` olayları tersten uygulayarak ağı BİT BİT geri getirir: düğüm/kenar
## kimlikleri, komşuluk sıraları, kimlik sayaçları, kaldırılan blokların ve parsellerin KENDİ nesneleri (kimlik ve
## `owner_id` dahil), güncellenen blokların cephe atamaları. Yeniden üretim (refresh) çağrılmaz: parsel kümesi ve
## blok/parsel kimlikleri geri alınca işlemden önceki ile aynıdır. Saf RefCounted.
##
## Olay biçimleri (sıra önemli; ters uygulama sondan başa):
##   [KIND_NODE_ADDED, id] · [KIND_NODE_REMOVED, id, pos, kind] · [KIND_EDGE_ADDED, id]
##   [KIND_EDGE_REMOVED, snapshot] · [KIND_EDGE_SET, snapshot] (alan değişimi öncesi) · [KIND_ADJACENCY, node_id, list]

const KIND_NODE_ADDED := 0
const KIND_NODE_REMOVED := 1
const KIND_EDGE_ADDED := 2
const KIND_EDGE_REMOVED := 3
const KIND_EDGE_SET := 4
const KIND_ADJACENCY := 5

var op: Dictionary = {}
var version_before: int = 0
## İşlemden önce ağ ferry dışı kenarlarla tek bileşen miydi (geri alınca aynen yazılır).
var single_before: bool = false
var events: Array = []
## İşlemden önceki kimlik sayaçları (geri alınca aynen yazılır; yeniden oynatma bit-eşit kalır).
var counters: Dictionary = {}
## Düğüm kimliği -> işlem sırasında komşuluğu değişen düğümün konumu (yerel blok yenilemesi bunu kullanır).
var touched_pos: Dictionary = {}
## Komşuluğu/uç noktası değişen kenarların işlemden ÖNCEki kimlikleri (sınıf değişimi dahil).
var changed_edge_ids: Dictionary = {}
var removed_edge_ids: Dictionary = {}
var added_edge_ids: Dictionary = {}
var added_node_ids: Dictionary = {}
var removed_node_ids: Dictionary = {}
var blocks_added: Array[int] = []
var blocks_removed: Array[WorldBlock] = []
var parcels_removed: Array[WorldParcel] = []
## Güncellenen (eşleşen) blok: {block, outline, edge_ids, signature, frontage: {parcel_id: edge_id}} (ÖNCEki hâl).
var blocks_updated: Array[Dictionary] = []
## `_edge_parcels[edge_id]` ilk dokunuştan önceki liste (PackedInt32Array) ya da null (anahtar yoktu).
var edge_parcels_before: Dictionary = {}
## Bu işlemin yarattığı değişiklik kaydı (WorldNetwork doldurur).
var change: NetworkChange = null
## Yol dışı kenar özellikleri bu işlemde değişti mi (yalnız set_open): bloklar etkilenmez.
var geometry_changed: bool = false
## T-042b kamulaştırmalı işlem: alınan parsel kimlikleri (artan) ve kümesi; havuza alınıp yeni bloklara KİMLİKLERİYLE
## taşınan parseller [parsel, önceki blok, önceki cephe kenarı]; bloğu korunup tek tek alınan parseller; o blokların
## önceki parsel listeleri (blok kimliği -> PackedInt32Array, ilk dokunuştan önce).
var expropriating: bool = false
var taken: PackedInt64Array = PackedInt64Array()
var taken_set: Dictionary = {}
var parcels_moved: Array = []
var parcels_retired: Array[WorldParcel] = []
var block_parcels_before: Dictionary = {}
## İşlemden ÖNCEki bileşen önbelleği kopyası (NetworkComponents.remember; geri alınca geri konur; boş = kopya yok).
var components: Dictionary = {}
## T-066: parsel geri açma işleminin yarattığı klonlar ve değiştirdiği blok sunum geometrisi.
var reactivated_parcels: Array[int] = []
var land_blocks_before: Dictionary = {}


static func begin(net: WorldNetwork, p_op: Dictionary) -> NetworkOpJournal:
	var j := NetworkOpJournal.new()
	j.op = p_op
	j.version_before = net.graph_version
	j.single_before = net._blocks_single_comp
	j.counters = NetworkRestore.counters(net)
	NetworkComponents.remember(net, j)
	return j


# ---------------------------------------------------------------- kayıt (WorldNetwork ham işlevleri çağırır)

func on_node_added(id: int, pos: Vector2) -> void:
	events.append([KIND_NODE_ADDED, id])
	added_node_ids[id] = true
	touched_pos[id] = pos
	geometry_changed = true


func on_node_removed(id: int, pos: Vector2, kind: StringName) -> void:
	events.append([KIND_NODE_REMOVED, id, pos, kind])
	removed_node_ids[id] = true
	touched_pos[id] = pos
	geometry_changed = true


func on_edge_added(id: int) -> void:
	events.append([KIND_EDGE_ADDED, id])
	added_edge_ids[id] = true
	geometry_changed = true


func on_edge_removed(net: WorldNetwork, e: WorldRoadEdge) -> void:
	events.append([KIND_EDGE_REMOVED, _snapshot(net, e)])
	removed_edge_ids[e.id] = true
	geometry_changed = true


## Kenar alanları (uç, sınıf, genişlik, açıklık) değişmeden hemen ÖNCE çağrılır.
func on_edge_set(net: WorldNetwork, e: WorldRoadEdge) -> void:
	events.append([KIND_EDGE_SET, _snapshot(net, e)])
	changed_edge_ids[e.id] = true


func on_adjacency(net: WorldNetwork, node_id: int, old_list: PackedInt32Array) -> void:
	# Packed diziler başvuruyla geçer: günlük kendi kopyasını tutar.
	events.append([KIND_ADJACENCY, node_id, old_list.duplicate()])
	if not touched_pos.has(node_id) and net.nodes.has(node_id):
		touched_pos[node_id] = net.node_pos(node_id)
	geometry_changed = true


func on_block_added(id: int) -> void:
	blocks_added.append(id)


func on_block_removed(block: WorldBlock, parcels: Array[WorldParcel]) -> void:
	blocks_removed.append(block)
	parcels_removed.append_array(parcels)


func on_block_updated(block: WorldBlock, frontage: Dictionary) -> void:
	blocks_updated.append({"block": block, "outline": block.outline.duplicate(), "edge_ids": block.edge_ids.duplicate(),
			"signature": block.signature, "frontage": frontage})


func on_block_parcels(block: WorldBlock) -> void:
	if not block_parcels_before.has(block.id):
		block_parcels_before[block.id] = block.parcel_ids.duplicate()


func on_edge_parcels(edge_id: int, current: Variant) -> void:
	if not edge_parcels_before.has(edge_id):
		edge_parcels_before[edge_id] = null if current == null else (current as PackedInt32Array).duplicate()


## Konumlu kenar özeti: ters uygulamada nesne yeniden kurulur; değişim kaydı eski geometriyi buradan okur.
func _snapshot(net: WorldNetwork, e: WorldRoadEdge) -> Dictionary:
	return {"id": e.id, "a": e.a, "b": e.b, "road_class": e.road_class, "width": e.width, "open": e.open,
			"layer": e.layer, "length": e.length, "pa": net.node_pos(e.a), "pb": net.node_pos(e.b)}


# ---------------------------------------------------------------- sorgular

## Bu işlemden sonra hâlâ var olan ve komşuluğu/ucu değişen düğümler (konumlarıyla): yerel blok yenileme tohumu.
func touched_nodes() -> Dictionary:
	var out := {}
	for ev: Array in events:
		if int(ev[0]) == KIND_EDGE_SET or int(ev[0]) == KIND_EDGE_REMOVED:
			var snap: Dictionary = ev[1]
			out[int(snap["a"])] = snap["pa"]
			out[int(snap["b"])] = snap["pb"]
	for nid: int in touched_pos:
		out[nid] = touched_pos[nid]
	return out


## İşlemden önceki geometri parçaları: [a_pos, b_pos, genişlik] (kaldırılan/değişen kenarlar).
func old_segments() -> Array[Array]:
	var out: Array[Array] = []
	for ev: Array in events:
		var k := int(ev[0])
		if k == KIND_EDGE_SET or k == KIND_EDGE_REMOVED:
			var snap: Dictionary = ev[1]
			out.append([snap["pa"], snap["pb"], float(snap["width"])])
	return out


## Ekleme işlemi bağlantısızlık yaratmadı mı? Tek bileşenli ağa yalnız kenar eklendiyse, işlemin dokunduğu
## düğümlerden en az
## biri ÖNCEDEN vardıysa (zincir sürekli) ağ tek bileşen kalır. (Silme/bölme ayrı hesaplanır.)
func extends_existing_graph(net: WorldNetwork) -> bool:
	for nid: int in touched_nodes():
		if not added_node_ids.has(nid) and net.nodes.has(nid):
			return true
	return false


# ---------------------------------------------------------------- geri alma

## Günlüğü tersten uygular. Dönüş: {removed_blocks, restored_blocks, removed_parcels, restored_parcels}
## (kimlik listeleri: "removed" = işlemin YARATTIĞI ve şimdi silinenler, "restored" = geri gelenler).
func undo(net: WorldNetwork) -> Dictionary:
	var report := {"removed_blocks": [], "restored_blocks": [], "removed_parcels": [], "restored_parcels": []}
	for pid in reactivated_parcels:
		net.parcels.erase(pid)
		net._parcel_grid.remove(pid)
		report["removed_parcels"].append(pid)
	for bid: int in land_blocks_before:
		var block: WorldBlock = net.blocks[bid]
		var saved: Dictionary = land_blocks_before[bid]
		block.kind = saved["kind"]
		block.buildable = saved["buildable"]
		block.area = saved["area"]
	var moved := {}  # kamulaştırma: yeni bloklara taşınan parseller geri alınca "silindi" sayılmaz (geri konur)
	for rec: Array in parcels_moved:
		moved[(rec[0] as WorldParcel).id] = true
	for bid in blocks_added:
		if net.blocks.has(bid):
			var block: WorldBlock = net.blocks[bid]
			for pid in block.parcel_ids:
				if not moved.has(pid):
					report["removed_parcels"].append(pid)
			NetworkRestore.drop_block(net, bid)
			report["removed_blocks"].append(bid)
	var at := events.size() - 1
	while at >= 0:
		_undo_event(net, events[at])
		at -= 1
	for block in blocks_removed:
		NetworkRestore.reinstate_block(net, block)
		report["restored_blocks"].append(block.id)
	for parcel in parcels_removed:
		NetworkRestore.reinstate_parcel(net, parcel)
		report["restored_parcels"].append(parcel.id)
	for rec: Array in parcels_moved:  # aynı nesne, önceki blok ve cephe
		var kept: WorldParcel = rec[0]
		NetworkRestore.reinstate_parcel(net, kept)
		kept.block_id = int(rec[1])
		kept.frontage_edge = int(rec[2])
	for parcel in parcels_retired:
		NetworkRestore.reinstate_parcel(net, parcel)
		report["restored_parcels"].append(parcel.id)
	for bid: int in block_parcels_before:
		if net.blocks.has(bid):
			(net.blocks[bid] as WorldBlock).parcel_ids = block_parcels_before[bid]
	for upd in blocks_updated:
		var block: WorldBlock = upd["block"]
		NetworkRestore.restore_block_geometry(net, block, upd["outline"], upd["edge_ids"], upd["signature"])
		for pid: int in upd["frontage"]:
			if net.parcels.has(pid):
				(net.parcels[pid] as WorldParcel).frontage_edge = int(upd["frontage"][pid])
	for eid: int in edge_parcels_before:
		NetworkRestore.restore_edge_parcels(net, eid, edge_parcels_before[eid])
	NetworkRestore.set_counters(net, counters)
	return report


func _undo_event(net: WorldNetwork, ev: Array) -> void:
	match int(ev[0]):
		KIND_NODE_ADDED:
			NetworkRestore.drop_node(net, int(ev[1]))
		KIND_NODE_REMOVED:
			NetworkRestore.reinstate_node(net, int(ev[1]), ev[2], ev[3])
		KIND_EDGE_ADDED:
			NetworkRestore.drop_edge(net, int(ev[1]))
		KIND_EDGE_REMOVED:
			NetworkRestore.reinstate_edge(net, ev[1])
		KIND_EDGE_SET:
			NetworkRestore.reinstate_edge(net, ev[1])
		KIND_ADJACENCY:
			if net.adjacency.has(int(ev[1])):
				net.adjacency[int(ev[1])] = ev[2]
