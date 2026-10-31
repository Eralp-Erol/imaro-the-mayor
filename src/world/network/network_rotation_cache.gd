class_name NetworkRotationCache
extends RefCounted
## Düğüm DÖNÜŞ SIRASI ve yüz yürüyüşü önbelleği (T-050; tick maliyeti). `NetworkBlocks._rotation_of` sonucunu ve ondan
## türeyen "ardıl yarım kenar" tablosunu işlemler arası tutar; yalnız komşuluğu/konumu değişen düğümler için yeniden
## hesaplar. Sonuçlar her zaman taze hesapla BİT-BİT aynıdır (dönüş sırası (açı, kenar kimliği) toplam sıralamasıdır;
## komşuluk listesi sırasından bağımsız). Gerçek ağda dış yüz yürüyüşü (~1 000 yarım kenar) her yol işleminde yapılır;
## önbelleksiz bu ~13 ms dönüş hesabı + ~7 ms yürüyüş/çokgen demekti.
##
## Yarım kenar kimliği `kenar * 2 + yön` (yön 0: a -> b, yön 1: b -> a), `NetworkBlocks._walk` ile aynı.
##
## Geçersiz kılma `NetworkHashCache.mark` ile aynı işaretlerden beslenir (mühürlü ağda her düğüm/kenar değişimi zaten
## işaretlenir; hash artımlılığı bunu güvenceye alır). İşaretler ertelenir; ilk sorguda `sync` ile çözülür:
##   - kenar işareti: kenarın ESKİ uçları (hesap anındaki `_ends` kaydı) ve ŞİMDİKİ uçları geçersiz olur;
##   - düğüm işareti: düğüm ve şimdiki komşuları geçersiz olur (konum değişimi komşunun açısını etkiler).
## Geçersiz düğümün dönüş sırası ve o düğüme VARAN yarım kenarların tablo kayıtları silinir. Mühürlenmemiş ağda önbellek
## yoktur (NetworkBlocks taze hesaplar). Saf: RefCounted, Node/Time/OS/rastgelelik yok.

## Çevrimi kesin dış yüz saymak için işaretli alan x2 eşiği (m² x2): -2 = -1 m². Eşik, kayan noktalı gürültünün
## (~1e-7) çok üstündedir; bu eşiğin altı hiçbir koşulda pozitif alanlı yüz olamaz.
const OUTER_AREA2_LIMIT := -2.0

## Düğüm kimliği -> PackedInt32Array (ferry hariç kenar kimlikleri, açıya göre artan).
var rot: Dictionary = {}
## Düğüme VARAN yarım kenar -> yüz yürüyüşünde sıradaki yarım kenar.
var _next: Dictionary = {}
## Düğüme VARAN yarım kenar -> çapraz çarpım (kuyruk x başın y - baş x kuyruğun y); yüzün işaretli alanı x2 toplamı.
var _cross: Dictionary = {}
## Hesap anında, önbellekteki bir düğümün komşuluğundaki her kenar için: kenar kimliği -> Vector2i(a, b).
var _ends: Dictionary = {}
var _dirty_nodes: Dictionary = {}
var _dirty_edges: Dictionary = {}


## Ağdaki tüm düğümlerin sırasını önceden hesaplar (mühürde bir kez; ilk yol tick'i soğuk hesap ödemesin).
func warm(net: WorldNetwork) -> void:
	for nid: int in net.nodes:
		rotation(net, nid)


## Düğüm/kenar değişti (NetworkHashCache.NODE / EDGE). Önbellek boşsa geçersiz kılınacak bir şey yoktur.
func mark(kind: int, id: int) -> void:
	if rot.is_empty():
		return
	if kind == NetworkHashCache.NODE:
		_dirty_nodes[id] = true
	else:
		_dirty_edges[id] = true


## `start` yarım kenarından çevrim başa dönene dek yürür (`visited` işaretlenir; `NetworkBlocks._walk` ile aynı çevrim).
## Çevrimin işaretli alanı kesin NEGATİF (dış yüz) ise boş dizi döner (çağıran atlar; orijinal kod da alan <= 0
## yüzü atar).
func walk(net: WorldNetwork, start: int, visited: Dictionary) -> PackedInt32Array:
	sync(net)
	var cycle := PackedInt32Array()
	var area2 := 0.0
	var cur := start
	var guard := 0
	while guard < 1000000:
		guard += 1
		visited[cur] = true
		cycle.append(cur)
		var step: Variant = _next.get(cur, null)
		if step == null:
			var edge: WorldRoadEdge = net.edges[cur >> 1]
			rotation(net, edge.b if (cur & 1) == 0 else edge.a)
			step = _next[cur]
		area2 += float(_cross[cur])
		cur = step
		if cur == start:
			break
	return PackedInt32Array() if area2 < OUTER_AREA2_LIMIT else cycle


## `nid` düğümünün dönüş sırası (taze `NetworkBlocks._rotation_of` ile aynı).
func rotation(net: WorldNetwork, nid: int) -> PackedInt32Array:
	sync(net)
	var hit: Variant = rot.get(nid, null)
	if hit != null:
		return hit
	var order := NetworkBlocks._rotation_of(net, nid)
	for eid in net.adjacency[nid]:
		var e: WorldRoadEdge = net.edges[eid]
		_ends[eid] = Vector2i(e.a, e.b)
	var count := order.size()
	var here: Vector2 = (net.nodes[nid] as WorldRoadNode).pos
	for k in count:
		var arriving: WorldRoadEdge = net.edges[order[k]]
		var leaving_id := order[(k - 1 + count) % count]
		var leaving: WorldRoadEdge = net.edges[leaving_id]
		var h := order[k] * 2 + (0 if arriving.b == nid else 1)
		_next[h] = leaving_id * 2 + (0 if leaving.a == nid else 1)
		var tail: Vector2 = (net.nodes[arriving.other(nid)] as WorldRoadNode).pos
		_cross[h] = float(tail.x) * float(here.y) - float(here.x) * float(tail.y)
	rot[nid] = order
	return order


## Bekleyen işaretleri çözer: etkilenen düğümlerin kayıtlarını siler.
func sync(net: WorldNetwork) -> void:
	if _dirty_nodes.is_empty() and _dirty_edges.is_empty():
		return
	var stale := {}
	for eid: int in _dirty_edges:
		if _ends.has(eid):
			var old: Vector2i = _ends[eid]
			stale[old.x] = true
			stale[old.y] = true
		var e: WorldRoadEdge = net.edges.get(eid, null)
		if e != null:
			stale[e.a] = true
			stale[e.b] = true
	for nid: int in _dirty_nodes:
		stale[nid] = true
		if net.adjacency.has(nid):
			for eid in net.adjacency[nid]:
				stale[(net.edges[eid] as WorldRoadEdge).other(nid)] = true
	for nid: int in stale:
		_drop(nid)
	for eid: int in _dirty_edges:
		if not net.edges.has(eid):
			_ends.erase(eid)
	_dirty_edges.clear()
	_dirty_nodes.clear()


# Düğümün dönüş sırasını ve ona varan yarım kenarların kayıtlarını siler (kenar uçları `_ends` kaydından).
func _drop(nid: int) -> void:
	var old: Variant = rot.get(nid, null)
	if old == null:
		return
	for eid in (old as PackedInt32Array):
		var ends: Vector2i = _ends[eid]
		var h: int = eid * 2 + (0 if ends.y == nid else 1)
		_next.erase(h)
		_cross.erase(h)
	rot.erase(nid)
