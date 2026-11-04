class_name NetworkComponents
extends RefCounted
## Kip başına BAĞLI BİLEŞEN önbelleği (WorldNetwork.components/component_of; T-050 tick maliyeti, T-051 geri alma).
## Her kip için `info = {of, list, memo, pe, pn}`:
##   list: bileşen başına sıralı düğüm listesi, bileşenler en küçük düğüm kimliğine göre sıralı (yerinde DEĞİŞTİRİLMEZ,
##         yama yeni dizi üretir; anlık görüntüler paylaşır);
##   of:   PackedInt32Array, düğüm kimliği -> `list` indeksi (kipte kenarı olan düğümler; yoksa -1; kenarı yalnız
##         kapalı olan düğüm tek başına bileşendir);
##   memo: PackedInt32Array, kenar kimliği e için [3e, 3e+1, 3e+2] = (a, b, açık 0/1) kenarın önbellek anındaki hâli
##         (a = -1: kipte değil);
##   pe/pn: önbellekten sonra değişen (işaretli) kenar / düğüm kimlikleri (NetworkHashCache.mark iletir).
## Godot 4.7'de Packed*Array atama/argüman geçirmede PAYLAŞILIR (yazma her yerde görünür): anlık görüntü
## `duplicate()` ister.
##
## Geri alma (T-051): `NetworkOpJournal.begin` işlemden ÖNCEki önbelleği ucuz kopyalar (`remember`: iki Packed dizi
## memcpy, ~0,03 ms), `undo_last_op` ağ işlemden önceki ile BİREBİR aynı olduğundan o kopyayı geri koyar (`restore`);
## bileşen sorgusu tam hesap (~30 ms) yerine yamasız önbellekten gelir. Bellek için yalnız son `UNDO_SNAPSHOTS` işlemde
## kopya tutulur; daha eskisi geri alınırsa önbellek temizlenir (eski davranış, doğru ama yavaş).
##
## Sorguda işaretler varsa önbellek YAMALANIR; sonuç `build` (tam hesap) ile BİT-BİT aynıdır (liste, sıra, indeksler).
## Yama yalnız şu durumda geçerlidir: silinen düğüm yok, kipte kenarını yitiren düğüm yok ve kaybolan her AÇIK bağlantı
## (a, b) değişen kenarların şimdiki hâliyle (ör. bölünmüş kenar a-n-b) yeniden köprülenmiş (kenar bölme, ekleme, sınıf
## yükseltme). Aksi halde (silme, kapatma, kopma) tam hesaba düşer. Mühürsüz ağda WorldNetwork her değişimde sözlüğü
## temizler (tam hesap). Saf; WorldNetwork'ün `_`-önekli üyelerine bilerek erişir (arkadaş sınıf).

## Bileşen önbelleği kopyası tutulan son geri alınabilir işlem sayısı (bellek: işlem başına ~0,1 MB / kip).
const UNDO_SNAPSHOTS := 8

## Ölçüm/test sayaçları (durum değildir, hash'e girmez).
static var patched: int = 0
static var rebuilt: int = 0
static var restored: int = 0


## Kipin bileşen bilgisi; işaretler varsa yamalar, yamalanamıyorsa baştan kurar.
static func info(net: WorldNetwork, mode: StringName) -> Dictionary:
	var cache: Dictionary = net._component_cache
	if not cache.has(mode):
		cache[mode] = build(net, mode)
	else:
		var cur: Dictionary = cache[mode]
		if not (cur["pe"] as Dictionary).is_empty() or not (cur["pn"] as Dictionary).is_empty():
			if _patch(net, mode, cur):
				patched += 1
			else:
				cache[mode] = build(net, mode)
	return cache[mode]


## Önbellekteki kiplere düğüm/kenar değişimini bildirir (NetworkHashCache.mark çağırır).
static func mark(cache: Dictionary, kind: int, id: int) -> void:
	for mode: StringName in cache:
		var info_dict: Dictionary = cache[mode]
		var pending: Dictionary = info_dict["pn"] if kind == NetworkHashCache.NODE else info_dict["pe"]
		pending[id] = true


## Düğümün bileşen indeksi (`list` sırasında); kipte kenarı yoksa -1.
static func index_of(info_dict: Dictionary, nid: int) -> int:
	var of: PackedInt32Array = info_dict["of"]
	return of[nid] if nid >= 0 and nid < of.size() else -1


## İşlem başlarken (NetworkOpJournal.begin) önbelleğin kopyasını günlüğe yazar; daha eski günlüklerin kopyasını bırakır.
static func remember(net: WorldNetwork, journal: NetworkOpJournal) -> void:
	var stack: Array[NetworkOpJournal] = net._undo_stack
	if stack.size() >= UNDO_SNAPSHOTS:
		stack[stack.size() - UNDO_SNAPSHOTS].components = {}
	var saved := {}
	for mode: StringName in net._component_cache:
		var cur: Dictionary = net._component_cache[mode]
		saved[mode] = {"of": (cur["of"] as PackedInt32Array).duplicate(), "list": cur["list"],
				"memo": (cur["memo"] as PackedInt32Array).duplicate(), "pe": (cur["pe"] as Dictionary).duplicate(),
				"pn": (cur["pn"] as Dictionary).duplicate()}
	journal.components = saved


## Geri almadan sonra (ağ işlemden önceki ile aynı) önbelleği işlem öncesi kopyaya döndürür. Kopya yoksa dokunmaz
## (çağıran zaten temizlemiş olmalı). Sözlük YERİNDE doldurulur: NetworkHashCache aynı nesneyi tutar.
static func restore(net: WorldNetwork, saved: Dictionary) -> void:
	if saved.is_empty():
		return
	var cache: Dictionary = net._component_cache
	cache.clear()
	for mode: StringName in saved:
		cache[mode] = saved[mode]
	restored += 1


## Tam hesap (referans): kenarlar üzerinden birleşim-bulma (düğüm kimliği indeksli dizi); bileşenler kimliğe göre sıralı
## düğümlerden ilk görülme sırasıyla numaralanır (= en küçük üye sırası), üyeler zaten artan sıralıdır.
static func build(net: WorldNetwork, mode: StringName) -> Dictionary:
	rebuilt += 1
	var ids: Array = net.nodes.keys()
	ids.sort()
	var parent := PackedInt32Array()
	parent.resize((int(ids[-1]) if not ids.is_empty() else 0) + 1)
	parent.fill(-1)  # -1 = kipte kenarı yok (bileşen üyesi değil)
	var memo := PackedInt32Array()
	_fit(memo, 3 * net._next_edge_id, -1)
	for eid: int in net.edges:
		var e: WorldRoadEdge = net.edges[eid]
		if WorldRoadEdge.mode_of(e.road_class) != mode:
			continue
		_memo_put(memo, eid, e.a, e.b, e.open)
		if parent[e.a] < 0:
			parent[e.a] = e.a
		if parent[e.b] < 0:
			parent[e.b] = e.b
		if e.open:
			var ra := _root(parent, e.a)
			var rb := _root(parent, e.b)
			if ra != rb:
				parent[maxi(ra, rb)] = mini(ra, rb)
	var of := PackedInt32Array()
	of.resize(parent.size())
	of.fill(-1)
	var list: Array[PackedInt32Array] = []
	var index_of_root := {}
	for nid: int in ids:
		if parent[nid] < 0:
			continue
		var root := _root(parent, nid)
		if not index_of_root.has(root):
			index_of_root[root] = list.size()
			list.append(PackedInt32Array())
		var idx: int = index_of_root[root]
		of[nid] = idx
		var members := list[idx]
		members.append(nid)
		list[idx] = members
	return {"of": of, "list": list, "memo": memo, "pe": {}, "pn": {}}


## `arr`yi en az `size` uzunluğa getirir; yeni yuvalar `fill` ile dolar (resize 0 doldurur).
static func _fit(arr: PackedInt32Array, size: int, fill: int) -> void:
	var old := arr.size()
	if size > old:
		arr.resize(size)
		for i in range(old, size):
			arr[i] = fill


static func _memo_put(memo: PackedInt32Array, eid: int, a: int, b: int, is_open: bool) -> void:
	_fit(memo, 3 * eid + 3, -1)
	memo[3 * eid] = a
	memo[3 * eid + 1] = b
	memo[3 * eid + 2] = 1 if is_open else 0


static func _root(parent: PackedInt32Array, nid: int) -> int:
	var cur := nid
	while parent[cur] != cur:
		parent[cur] = parent[parent[cur]]
		cur = parent[cur]
	return cur


## Yama; false = uygulanamaz (çağıran tam hesaba düşer).
static func _patch(net: WorldNetwork, mode: StringName, info_dict: Dictionary) -> bool:
	var of: PackedInt32Array = info_dict["of"]
	for nid: int in info_dict["pn"]:
		if _has(of, nid) and not net.nodes.has(nid):
			return false
	var scan := _scan(net, mode, info_dict)
	if scan.is_empty():
		return false
	var groups := _groups(info_dict, scan)
	var list: Array[PackedInt32Array] = info_dict["list"]
	var out: Array[PackedInt32Array] = []
	var order: Array = groups.values()
	order.sort_custom(func(x: Dictionary, y: Dictionary) -> bool: return x["members"][0] < y["members"][0])
	var gi := 0
	var out_groups: Array = []  # out ile aynı hizada: grup sözlüğü ya da null (değişmemiş eski bileşen)
	var removed: Dictionary = scan["removed"]
	for k in list.size():
		if removed.has(k):
			continue
		while gi < order.size() and int(order[gi]["members"][0]) < list[k][0]:
			out.append(order[gi]["members"])
			out_groups.append(order[gi])
			gi += 1
		out.append(list[k])
		out_groups.append(null)
	while gi < order.size():
		out.append(order[gi]["members"])
		out_groups.append(order[gi])
		gi += 1
	_reindex(of, list, out, out_groups)
	info_dict["list"] = out
	(info_dict["pe"] as Dictionary).clear()
	(info_dict["pn"] as Dictionary).clear()
	return true


## İşaretli kenarları şimdiki hâliyle tarar. Dönüş: {} = yama uygulanamaz; aksi halde {nodes: düğüm DSU'su (köprü
## denetimi), keys: bileşen/yeni-düğüm DSU'su (birleşme), removed: birleşen eski bileşen indeksleri}.
static func _scan(net: WorldNetwork, mode: StringName, info_dict: Dictionary) -> Dictionary:
	var of: PackedInt32Array = info_dict["of"]
	var memo: PackedInt32Array = info_dict["memo"]
	var nodes_dsu := {}
	var keys_dsu := {}
	var lost: Array[Vector2i] = []
	var orphans: Array[int] = []
	for eid: int in info_dict["pe"]:
		var cur: WorldRoadEdge = net.edges.get(eid, null)
		var valid := cur != null and cur.mode() == mode
		if 3 * eid + 2 < memo.size() and memo[3 * eid] >= 0:
			var oa := memo[3 * eid]
			var ob := memo[3 * eid + 1]
			var same_ends := valid and ((cur.a == oa and cur.b == ob) or (cur.a == ob and cur.b == oa))
			if not same_ends:
				orphans.append(oa)
				orphans.append(ob)
			if memo[3 * eid + 2] == 1 and not (same_ends and cur.open):
				lost.append(Vector2i(oa, ob))
		if not valid:
			if 3 * eid + 2 < memo.size():
				memo[3 * eid] = -1
			continue
		_memo_put(memo, eid, cur.a, cur.b, cur.open)
		_reg(keys_dsu, _key(of, cur.a))
		_reg(keys_dsu, _key(of, cur.b))
		if cur.open:
			_union(keys_dsu, _key(of, cur.a), _key(of, cur.b))
			_union(nodes_dsu, cur.a, cur.b)
	for x in orphans:
		if net.nodes.has(x) and not net._has_mode_edge(x, mode):
			return {}
	for conn in lost:
		if _find(nodes_dsu, conn.x) != _find(nodes_dsu, conn.y):
			return {}
	var removed := {}
	for key: int in keys_dsu:
		if key >= 0:
			removed[key] = true
	return {"keys": keys_dsu, "removed": removed}


## Birleşme gruplarını kurar: kök anahtar -> {members (sıralı), olds: eski indeksler, fresh: yeni üyeler}.
static func _groups(info_dict: Dictionary, scan: Dictionary) -> Dictionary:
	var list: Array[PackedInt32Array] = info_dict["list"]
	var keys_dsu: Dictionary = scan["keys"]
	var members_of := {}
	var olds_of := {}
	var fresh_of := {}
	for key: int in keys_dsu:
		var root := _find(keys_dsu, key)
		if not members_of.has(root):
			members_of[root] = PackedInt32Array()
			olds_of[root] = []
			fresh_of[root] = []
		var members: PackedInt32Array = members_of[root]
		if key >= 0:
			members.append_array(list[key])
			(olds_of[root] as Array).append(key)
		else:
			members.append(-key)
			(fresh_of[root] as Array).append(-key)
		members_of[root] = members
	var groups := {}
	for root: int in members_of:
		var sorted_members: PackedInt32Array = members_of[root]
		sorted_members.sort()
		groups[root] = {"members": sorted_members, "olds": olds_of[root], "fresh": fresh_of[root]}
	return groups


## `of` indekslerini yeni sıraya göre günceller: yeni/birleşen gruplar ve kayan eski bileşenler yazılır.
static func _reindex(of: PackedInt32Array, old_list: Array[PackedInt32Array], out: Array[PackedInt32Array],
		out_groups: Array) -> void:
	var old_at := {}  # eski bileşenin ilk üyesi -> eski indeks (değişmemiş bileşenleri tanımak için)
	for k in old_list.size():
		old_at[old_list[k][0]] = k
	for idx in out.size():
		var g: Variant = out_groups[idx]
		if g == null:
			var first := out[idx][0]
			if int(old_at.get(first, -1)) != idx:
				for nid in out[idx]:
					of[nid] = idx
			continue
		for old_index: int in g["olds"]:
			if old_index != idx:
				for nid in old_list[old_index]:
					of[nid] = idx
		for nid: int in g["fresh"]:
			_fit(of, nid + 1, -1)
			of[nid] = idx


# Bileşen anahtarı: eski üye -> bileşen indeksi (>= 0); yeni üye -> -düğüm kimliği.
static func _key(of: PackedInt32Array, nid: int) -> int:
	return of[nid] if _has(of, nid) else -nid


static func _has(of: PackedInt32Array, nid: int) -> bool:
	return nid >= 0 and nid < of.size() and of[nid] >= 0


static func _reg(dsu: Dictionary, key: int) -> void:
	if not dsu.has(key):
		dsu[key] = key


static func _find(dsu: Dictionary, key: int) -> int:
	if not dsu.has(key):
		return key
	var root := key
	while int(dsu[root]) != root:
		root = int(dsu[root])
	var walk := key
	while int(dsu[walk]) != root:
		var next := int(dsu[walk])
		dsu[walk] = root
		walk = next
	return root


static func _union(dsu: Dictionary, a: int, b: int) -> void:
	_reg(dsu, a)
	_reg(dsu, b)
	var ra := _find(dsu, a)
	var rb := _find(dsu, b)
	if ra != rb:
		dsu[maxi(ra, rb)] = mini(ra, rb)
