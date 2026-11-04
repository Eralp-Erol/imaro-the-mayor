class_name DemolitionPlan
extends RefCounted
## T-042c (D-014 §1) · Duran bir oyuncu yolunu YIKMANIN ağ tarafı. Yolun kenarlarını ağdan siler (`remove_edge`
## işlemleri, her kenar bir ağ işlemi = `PublicWorksState` yıkım satırı); alınan parselleri/binaları GERİ GETİRMEZ
## (yıkım geri alma değildir). Saf statik; ağı yalnız tick sınırında ve ana iş parçacığında değiştirir (kuru koşu
## uygula + geri al).
##
## Hangi kenarlar yolun? Yolun kayıtlı işlemindeki çokgen (`pts_cm`) bilinir; sonraki yollar kenarları bölmüş olabilir
## (yeni kimlikler). Bu yüzden kenar KİMLİĞİ değil GEOMETRİ eşleştirilir: delta katmanında (oyuncu yolu), yolun
## sınıfında, iki ucu ve orta noktası çokgene `snap_m` (planarizerin yapışma payı) içinde olan kenarlar. Başka bir yolun
## kenarı çokgene yalnız kesişim noktasında değer; uçlarından biri uzakta kalır, eşleşmez. Her silmeden sonra eşleşme
## yeniden aranır (düğüm temizliği kenar kimliklerini değiştirebilir). Yıkımdan sonra yolun çokgeni üstünde aynı
## sınıftan bir delta kenarı KALIRSA (örn. başka yolla eşdoğrusal birleşmiş kenar: kısmi yıkım olurdu) işlem başarısız
## sayılır; sessiz kısmi yıkım yok.
##
## Parsel kümesi sim'de SABİTTİR (T-042b seçenek A): silme dünyanın parsellerini yeniden üretirse (`added_parcels`/
## `removed_parcels` boş değil) işlem başarısız sayılır; çağıran ağı geri alır ve yıkımı reddeder. Dünya, `keep_parcels`
## açıkken birleşen bloğu BAŞTAN parsellemez: kalan parseller kimlikleriyle taşınır, kamulaştırılanlar geri dönmez
## (`NetworkExpropriation.active`; öneri 2026-11-01-parsel-kimligi-koruyan-yol-yikimi). Bu denetim güvenlik ağıdır:
## yalnız dünya yine de parsel değiştirirse (anahtar kapalı dünya, bağlantıyı koparan yıkım) devreye girer.

const MAX_EDGES := 64


## Yolun işlemiyle (`op`: add_road) eşleşen kenarları ağdan siler. Dönüş: {ok, error, ops [remove_edge işlemleri],
## hashes [her işlemden sonraki graf özeti; `want_hashes` değilse boş], edges [silinen kimlikler], added_parcels,
## removed_parcels}. `ok` false ise `ops.size()` kadar işlem AĞDA durur: çağıran o kadar `net.undo_last_op()`
## yapmalıdır (`rollback`).
static func run(net: WorldNetwork, op: Dictionary, want_hashes: bool) -> Dictionary:
	var out := {"ok": false, "error": "", "ops": [], "hashes": [], "edges": [], "added_parcels": 0,
		"removed_parcels": 0}
	var points := NetworkDelta.decode_points(op["pts_cm"])
	var road_class := StringName(str(op["class"]))
	while (out["edges"] as Array).size() < MAX_EDGES:
		var id := next_edge(net, points, road_class)
		if id < 0:
			break
		var report := net.remove_edge(id)
		if not bool(report["ok"]):
			out["error"] = str(report["error"])
			return out
		(out["edges"] as Array).append(id)
		(out["ops"] as Array).append(net.peek_last_op())
		out["added_parcels"] = int(out["added_parcels"]) + (report["added_parcels"] as Array).size()
		out["removed_parcels"] = int(out["removed_parcels"]) + (report["removed_parcels"] as Array).size()
		if want_hashes:
			(out["hashes"] as Array).append(net.graph_hash())
	if (out["edges"] as Array).is_empty():
		out["error"] = "yolun kenarı ağda bulunamadı"
	elif has_leftover(net, points, road_class):
		out["error"] = "yolun kenarları tamamen silinemedi"
	elif int(out["added_parcels"]) > 0 or int(out["removed_parcels"]) > 0:
		out["error"] = "yıkım dünyanın parsel kümesini değiştirirdi"
	else:
		out["ok"] = true
	return out


## `run`ın bıraktığı işlemleri geri alır (kuru koşu sonu ve başarısız yıkım). Geri alınamayan işlem sayısını döner.
static func rollback(net: WorldNetwork, ops: Array) -> int:
	var failed := 0
	for _i in ops.size():
		if not bool(net.undo_last_op()["ok"]):
			failed += 1
	return failed


## Çokgenle eşleşen en küçük kimlikli delta kenarı; yoksa -1.
static func next_edge(net: WorldNetwork, points: PackedVector2Array, road_class: StringName) -> int:
	var tolerance := net.rules.snap_m
	var best := -1
	for id: int in net.edges:
		if best >= 0 and id > best:
			continue
		var e: WorldRoadEdge = net.edges[id]
		if e.layer != WorldRoadEdge.LAYER_DELTA or e.road_class != road_class:
			continue
		var a := net.node_pos(e.a)
		var b := net.node_pos(e.b)
		if _distance_to_polyline(a, points) <= tolerance and _distance_to_polyline(b, points) <= tolerance \
				and _distance_to_polyline((a + b) * 0.5, points) <= tolerance:
			best = id
	return best


## Çokgenin üstünde (orta noktası `snap_m` içinde) aynı sınıftan delta kenarı kaldı mı? Ucu çokgen dışına taşan
## (başka yolla birleşmiş) kenar da sayılır.
static func has_leftover(net: WorldNetwork, points: PackedVector2Array, road_class: StringName) -> bool:
	var tolerance := net.rules.snap_m
	for id: int in net.edges:
		var e: WorldRoadEdge = net.edges[id]
		if e.layer == WorldRoadEdge.LAYER_DELTA and e.road_class == road_class \
				and _distance_to_polyline((net.node_pos(e.a) + net.node_pos(e.b)) * 0.5, points) <= tolerance:
			return true
	return false


static func _distance_to_polyline(p: Vector2, points: PackedVector2Array) -> float:
	var best := INF
	for i in range(points.size() - 1):
		best = minf(best, Geometry2D.get_closest_point_to_segment(p, points[i], points[i + 1]).distance_to(p))
	return best
