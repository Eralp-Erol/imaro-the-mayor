class_name RoadDraftCheck
extends RefCounted
## Oyuncu yolu taslağı denetimi (T-042 adım 1; CAN-04, D-009, ADR-0005 Ek E). SAF ve deterministik: girdi = nokta
## listesi + sınıf (+ ağ, kurallar); çıktı = geçerli ya da 10 ret nedeninden biri (kodlu) + UI anahtarı. Render/sim'den
## bağımsız;
## önizleme (UI/view) ve komut doğrulaması (sim) AYNI kodu çağırır, sayı ya da metin üretmez.
##
## v0 (aşama 1) kuralı: yol yalnız AÇIK arazide çizilir, ana yol bileşenine bağlanır, parselli bloğun içine girmez
## (`crosses_parcels`); geçerli bir taslak hiçbir parseli silmez/eklemez. Parselli bloğa giriş veri güdümlüdür
## (`RoadDraftRules.crossing_parcels`): aşama 2'de açılabilir, burada KAPALI/ret.
##
## Ret anahtarları (UI metni `data/ui/strings.tr.json`, ui-engineer): `public_work.reject.<neden>`.

const KEY_PREFIX := "public_work.reject."
const REASON_TOO_SHORT := &"too_short"
const REASON_TOO_LONG := &"too_long"
const REASON_WATER := &"water"
const REASON_SLOPE := &"slope"
const REASON_NOT_CONNECTED := &"not_connected"
const REASON_CROSSES_PARCELS := &"crosses_parcels"
const REASON_DUPLICATE := &"duplicate"
const REASON_OUTSIDE_JURISDICTION := &"outside_jurisdiction"
const REASON_BUSY := &"busy"
const REASON_NOTHING_TO_UNDO := &"nothing_to_undo"
## Planın 10 nedeninin dışında: sınıf izinli değil (sim `validate_shape` bunu normalde önceden yakalar).
const REASON_BAD_CLASS := &"bad_class"
## Yalnız `apply`: denetim geçti ama parsel kümesi değişti (olmamalı; işlem geri alınır).
const REASON_PARCELS_CHANGED := &"parcels_changed"
const ALL_REASONS: Array[StringName] = [REASON_TOO_SHORT, REASON_TOO_LONG, REASON_WATER, REASON_SLOPE,
		REASON_NOT_CONNECTED, REASON_CROSSES_PARCELS, REASON_DUPLICATE, REASON_OUTSIDE_JURISDICTION, REASON_BUSY,
		REASON_NOTHING_TO_UNDO]
## Bölge/eğim/su örnek adımı (m); `WorldNetwork` su denetimiyle aynı.
const SAMPLE_STEP_M := WorldNetwork.WATER_SAMPLE_STEP_M


static func key_of(reason: StringName) -> String:
	return "" if reason == &"" else KEY_PREFIX + String(reason)


## `points_cm` = [x0, z0, x1, z1, ...] santimetre tamsayı (komut biçimi) -> metre noktaları.
static func points_from_cm(points_cm: PackedInt64Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	var i := 0
	while i + 1 < points_cm.size():
		out.append(Vector2(float(points_cm[i]) * 0.01, float(points_cm[i + 1]) * 0.01))
		i += 2
	return out


## Taslağı denetler; AĞI DEĞİŞTİRMEZ. `busy`: dünya meşgul (çağıran bilir: iş parçacıklı yol/bitki kurulumu sürüyor).
## Dönüş: {ok, reason (&"" ise geçerli), key, length_m, min_length_m, max_length_m,
## points (cm'ye yuvarlanmış: add_road'un
## göreceği), regions {kod: m}, connections (ana ağla temas sayısı), at (Vector2: reddin konumu), has_at}.
static func check(net: WorldNetwork, points: PackedVector2Array, road_class: StringName, rules: RoadDraftRules,
		busy: bool = false) -> Dictionary:
	var pts := NetworkDelta.decode_points(NetworkDelta.encode_points(_finite(points)))
	var result := {"ok": false, "reason": &"", "key": "", "length_m": _length(pts), "min_length_m": rules.min_length_m,
			"max_length_m": rules.max_length_m, "points": pts, "regions": {}, "connections": 0, "at": Vector2.ZERO,
			"has_at": false}
	if busy:
		return _reject(result, REASON_BUSY)
	if not rules.allowed_classes.has(road_class):
		return _reject(result, REASON_BAD_CLASS)
	if pts.size() < 2 or float(result["length_m"]) < rules.min_length_m:
		return _reject(result, REASON_TOO_SHORT)
	if float(result["length_m"]) > rules.max_length_m:
		return _reject(result, REASON_TOO_LONG)
	var samples := _samples(pts, SAMPLE_STEP_M)
	for p in samples:
		if not net.world.contains(p.x, p.y):
			return _reject(result, REASON_OUTSIDE_JURISDICTION, p)
	for p in samples:
		if net.world.is_water(p.x, p.y):
			return _reject(result, REASON_WATER, p)
	for p in samples:
		if not rules.allows_region(net.rules.region_code_at(net.world, p)):
			return _reject(result, REASON_OUTSIDE_JURISDICTION, p)
	for p in samples:
		if net.world.slope_degrees_at(p.x, p.y) > rules.max_slope_deg:
			return _reject(result, REASON_SLOPE, p)
	if _is_duplicate(net, pts, rules):
		return _reject(result, REASON_DUPLICATE)
	var connections := count_connections(net, pts)
	result["connections"] = connections
	if connections == 0:
		return _reject(result, REASON_NOT_CONNECTED)
	if rules.crossing_parcels != RoadDraftRules.CROSSING_ALLOW:
		var hit := first_parcel_hit(net, pts, rules, net.rules.width_of(road_class) * 0.5)
		if bool(hit["found"]):
			return _reject(result, REASON_CROSSES_PARCELS, hit["at"])
	result["regions"] = region_lengths(net, pts)
	result["ok"] = true
	return result


## Denetle + uygula: geçerliyse `net.add_road` (cm'ye yuvarlanmış noktalarla), yoksa ağa dokunmaz. Parsel kümesi
## değişirse (v0'da olmamalı) işlem GERİ ALINIR ve REASON_PARCELS_CHANGED döner.
## Dönüş: `check` sonucu + {applied, report, change}.
static func apply(net: WorldNetwork, points: PackedVector2Array, road_class: StringName, rules: RoadDraftRules,
		busy: bool = false) -> Dictionary:
	return apply_checked(net, check(net, points, road_class, rules, busy), road_class, rules)


## `apply`ın uygulama yarısı: ÖNCEDEN hesaplanmış `check` sonucunu (aynı ağ sürümünde alınmış olmalı) yeniden
## denetlemeden uygular. Girdi sözlüğü DEĞİŞTİRİLMEZ (sığ kopya üstünde çalışılır); dönüş `apply` ile aynıdır.
static func apply_checked(net: WorldNetwork, checked: Dictionary, road_class: StringName, rules: RoadDraftRules) \
		-> Dictionary:
	var result := checked.duplicate()
	result["applied"] = false
	result["report"] = {}
	result["change"] = null
	if not bool(result["ok"]):
		return result
	var report := net.add_road(result["points"], road_class)
	result["report"] = report
	if not bool(report["ok"]):
		result["ok"] = false
		result["reason"] = REASON_TOO_SHORT
		result["key"] = key_of(REASON_TOO_SHORT)
		return result
	if rules.crossing_parcels != RoadDraftRules.CROSSING_ALLOW and \
			(not (report["added_parcels"] as Array).is_empty() or not (report["removed_parcels"] as Array).is_empty()):
		net.undo_last_op()
		result["ok"] = false
		result["reason"] = REASON_PARCELS_CHANGED
		result["key"] = key_of(REASON_PARCELS_CHANGED)
		return result
	result["applied"] = true
	result["change"] = report["change"]
	return result


## Son delta işlemini geri alır; yoksa `nothing_to_undo`. Dönüş: {ok, reason, key, change}.
static func undo(net: WorldNetwork) -> Dictionary:
	var undone := net.undo_last_op()
	if not bool(undone["ok"]):
		return {"ok": false, "reason": REASON_NOTHING_TO_UNDO, "key": key_of(REASON_NOTHING_TO_UNDO), "change": null}
	return {"ok": true, "reason": &"", "key": "", "change": undone["change"]}


# ---------------------------------------------------------------- parçalar

## Taslağın ana yol bileşeniyle temas sayısı: köşelerin düğüme/kenara yapışması + ana bileşen kenarlarını kesme.
## (Planarizer kesişimleri düğüme çevirdiği için kesişim de bağlantıdır.) Kapalı kenar ve ray/feribot sayılmaz.
static func count_connections(net: WorldNetwork, pts: PackedVector2Array) -> int:
	var main := _main_component(net)
	if main < 0:
		return 0
	var snap := net.rules.snap_m
	var count := 0
	for p in pts:
		var nid := net.nearest_node_within(p, snap)
		if nid >= 0 and net.component_of(nid, WorldNetwork.MODE_ROAD) == main:
			count += 1
			continue
		for e in net.edges_near(p.x, p.y, snap):
			if e.mode() == WorldNetwork.MODE_ROAD and e.open and net.component_of(e.a, WorldNetwork.MODE_ROAD) == main:
				count += 1
				break
	for i in range(pts.size() - 1):
		var box := Rect2(pts[i], Vector2.ZERO).expand(pts[i + 1]).grow(snap)
		for eid in net.edge_ids_in_rect(box):
			var e2: WorldRoadEdge = net.edges[eid]
			if e2.mode() != WorldNetwork.MODE_ROAD or not e2.open \
					or net.component_of(e2.a, WorldNetwork.MODE_ROAD) != main:
				continue
			var t := NetworkGeometry.segment_params(pts[i], pts[i + 1], net.node_pos(e2.a), net.node_pos(e2.b))
			if not is_inf(t.x) and t.x >= 0.0 and t.x <= 1.0 and t.y >= 0.0 and t.y <= 1.0:
				count += 1
	return count


## Çizgi (ve yarı genişlik kadar yanal örnekleri) parselli bir bloğun içine giriyor mu? Mevcut yol şeridi içindeki
## örnekler (uç yapışması ve kesişimler) atlanır. Dönüş: {found, at}.
static func first_parcel_hit(net: WorldNetwork, pts: PackedVector2Array, rules: RoadDraftRules,
		half_width_m: float) -> Dictionary:
	if pts.size() < 2:
		return {"found": false, "at": Vector2.ZERO}
	var scan := RoadDraftParcelScan.create(net, RoadDraftParcelScan.sample_box(pts, half_width_m))
	if scan.is_empty():
		return {"found": false, "at": Vector2.ZERO}
	for i in range(pts.size() - 1):
		var a := pts[i]
		var b := pts[i + 1]
		var d := b - a
		var normal := Vector2(-d.y, d.x).normalized() * half_width_m
		var steps := maxi(1, int(ceil(d.length() / rules.parcel_sample_step_m)))
		for s in steps + 1:
			var p := a.lerp(b, float(s) / float(steps))
			for probe in [p, p + normal, p - normal]:
				if scan.covers(probe) and _in_parcelized_block(net, probe):
					return {"found": true, "at": probe}
	return {"found": false, "at": Vector2.ZERO}


## Bölge kodu başına yol uzunluğu (m): her parça, orta noktasının bölgesine yazılır (yetki alanı hesabıyla aynı işlev).
static func region_lengths(net: WorldNetwork, pts: PackedVector2Array) -> Dictionary:
	var out := {}
	for i in range(pts.size() - 1):
		var a := pts[i]
		var b := pts[i + 1]
		var steps := maxi(1, int(ceil(a.distance_to(b) / SAMPLE_STEP_M)))
		for s in steps:
			var p0 := a.lerp(b, float(s) / float(steps))
			var p1 := a.lerp(b, float(s + 1) / float(steps))
			var code := String(net.rules.region_code_at(net.world, (p0 + p1) * 0.5))
			out[code] = float(out.get(code, 0.0)) + p0.distance_to(p1)
	return out


## Parsel kümesinin özeti (kimlik, blok, alan, bölge, çokgen; cephe kenarı ve mülkiyet HARİÇ): v0 değişmezi
## "yol parsel kümesini değiştirmez" için önce/sonra karşılaştırılır. Cephe kenarı hariçtir çünkü cepheli bir yolu bölen
## bağlantı, parselin hangi kenar PARÇASINA baktığını yeniden atayabilir (parsel aynı kalır).
static func parcel_set_hash(net: WorldNetwork) -> String:
	var ids: Array = net.parcels.keys()
	ids.sort()
	var nums := PackedFloat64Array()
	var text := PackedStringArray()
	for pid: int in ids:
		var p: WorldParcel = net.parcels[pid]
		nums.append_array(PackedFloat64Array([pid, p.block_id, p.area, p.front_length, p.detail]))
		for v in p.outline:
			nums.append_array(PackedFloat64Array([v.x, v.y]))
		text.append("%s|%s" % [String(p.region_code), String(p.fabric)])
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(nums.to_byte_array() + ",".join(text).to_utf8_buffer() + PackedByteArray([0]))
	return ctx.finish().hex_encode()


## `parcel_set_hash` kimliklerden BAĞIMSIZ sürümü (yerel/tam yenileme gibi kimlik atama sırası farklı olabilen
## yollar için): parsel çokgenleri sıralı özetlenir.
static func parcel_set_hash_ignoring_ids(net: WorldNetwork) -> String:
	var rows := PackedStringArray()
	for pid: int in net.parcels:
		var p: WorldParcel = net.parcels[pid]
		var parts := PackedStringArray([String(p.region_code), String(p.fabric), "%.4f" % p.area, str(p.detail)])
		for v in p.outline:
			parts.append("%.2f,%.2f" % [v.x, v.y])
		rows.append(",".join(parts))
	rows.sort()
	return "\n".join(rows).md5_text()


static func _reject(result: Dictionary, reason: StringName, at: Variant = null) -> Dictionary:
	result["ok"] = false
	result["reason"] = reason
	result["key"] = key_of(reason)
	if at != null:
		result["at"] = at
		result["has_at"] = true
	return result


static func _finite(points: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in points:
		if is_finite(p.x) and is_finite(p.y):
			out.append(p)
	return out


static func _length(pts: PackedVector2Array) -> float:
	var total := 0.0
	for i in range(pts.size() - 1):
		total += pts[i].distance_to(pts[i + 1])
	return total


## Her parçada `step` aralıklı örnekler (uçlar dahil, `WorldNetwork._polyline_on_dry_land` ile AYNI noktalar).
static func _samples(pts: PackedVector2Array, step: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(pts.size() - 1):
		var a := pts[i]
		var b := pts[i + 1]
		var steps := maxi(1, int(ceil(a.distance_to(b) / step)))
		for s in steps + 1:
			out.append(a.lerp(b, float(s) / float(steps)))
	return out


static func _is_duplicate(net: WorldNetwork, pts: PackedVector2Array, rules: RoadDraftRules) -> bool:
	for p in _samples(pts, rules.parcel_sample_step_m):
		var near := false
		for e in net.edges_near(p.x, p.y, rules.duplicate_tolerance_m):
			if e.mode() == WorldNetwork.MODE_ROAD:
				near = true
				break
		if not near:
			return false
	return true


static func _main_component(net: WorldNetwork) -> int:
	var best := -1
	var best_size := 0
	var list := net.components(WorldNetwork.MODE_ROAD)
	for i in list.size():
		if list[i].size() > best_size:
			best_size = list[i].size()
			best = i
	return best


## Nokta mevcut bir yol/ray şeridinin içinde mi (yarı genişlik + pay ya da yakalama yarıçapı)? Parseller dışarıdadır.
static func _on_road_strip(net: WorldNetwork, p: Vector2) -> bool:
	for e in net.edges_near(p.x, p.y, 12.0):
		if e.mode() == WorldNetwork.MODE_FERRY:
			continue
		var d := NetworkGeometry.distance_point_segment(p, net.node_pos(e.a), net.node_pos(e.b))
		if d <= maxf(e.width * 0.5 + 0.5, net.rules.snap_m):
			return true
	return false


static func _in_parcelized_block(net: WorldNetwork, p: Vector2) -> bool:
	if _on_road_strip(net, p):
		return false
	var block := net.block_at(p.x, p.y)
	return block != null and not block.parcel_ids.is_empty()
