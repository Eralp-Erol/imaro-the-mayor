class_name LifeLayout
extends RefCounted
## Yaşam örneklerinin (araç, yaya) hücre yerleşimi (T-050). SAF ve deterministik: aynı (ağ, faaliyet, seed) -> aynı
## satırlar. Sayıyı `LifeEdgeActivity` (sim verisi) belirler; bu sınıf yalnız KONUM/FAZ/yön/renk üretir.
## RNG akışı yok: her seçim `ViewHash.hash01(kimlik, tohum)` ile kenar/parça/sıra kimliğinden türer.
##
## Sayı yuvarlaması monotondur: n = floor(beklenen + u), u = (kenar, parça) karması sabit. Beklenen sayı arttıkça n
## ASLA azalmaz ve yeni gelen örnek eskileri YERİNDEN OYNATMAZ (faz = altın oran dizisi, sıraya göre).
##
## Satır biçimi (ROW float, hücre yerel koordinat): ox, oy, oz (parça BAŞLANGICI, yürüme yönünde, yanal ofset dahil),
## yaw (model +Z ekseni yürüme yönüne bakar), scale, len (parça yatay uzunluğu), dy (parça sonu - başı yükseklik),
## bulge (orta nokta yükseklik sapması), packed (faz 10 bit | hız 4 bit | renk satırı 5 bit << 14).

const KIND_CAR := 0
const KIND_NEUTRAL := 1
const KIND_BROAD := 2
const KIND_COUNT := 3
const ROW := 9
const PHASE_BITS := 1024
const GOLDEN := 0.6180339887498949
## Karma kanalları (aynı kimlikten bağımsız seçimler).
const CH_COUNT_CAR := 1
const CH_COUNT_PEOPLE := 2
const CH_PHASE := 3
const CH_SPEED := 4
const CH_COLOR := 5
const CH_DIR := 6
const CH_BODY := 7
const CH_SCALE := 8
const CH_SIDE := 9
const FRONT_YAW_OFFSET := 0.0


## Sınıf -> kaldırım genişliği (m) tablosunu `road_style.json`dan okur (tek kaynak; kopya yok).
static func sidewalk_table(path: String = "res://data/view/road_style.json") -> Dictionary:
	var out: Dictionary = {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary and (parsed as Dictionary).get("classes") is Dictionary:
		for cls in (parsed["classes"] as Dictionary):
			out[String(cls)] = float((parsed["classes"][cls] as Dictionary).get("sidewalk_m", 0.0))
	return out


## Bir hücreyi kurar. `ground`: Callable(x, z) -> dünya yüksekliği (m). `car_rows`: kit palet satırı dizini listesi.
## Dönüş: {rows: Array[PackedFloat32Array] (KIND_COUNT), counts: PackedInt32Array(KIND_COUNT), bounds: AABB (hücre yerel),
## edges: int}. Hiç örnek yoksa counts sıfır.
static func build_cell(act: LifeEdgeActivity, cell: Vector2i, world_seed: int, density: float, ground: Callable,
		car_rows: PackedInt32Array, sidewalks: Dictionary) -> Dictionary:
	var cfg := act.cfg
	var rows: Array = []
	for _k in KIND_COUNT:
		rows.append(PackedFloat32Array())
	var counts := PackedInt32Array([0, 0, 0])
	var origin := Vector2(cell.x, cell.y) * act.cell_m
	# Sınırlar (hücre yerel): [min x, min y, min z, max x, max y, max z]; dizi referansla geçer.
	var bnd := PackedFloat32Array([1.0e9, 1.0e9, 1.0e9, -1.0e9, -1.0e9, -1.0e9])
	var inset := cfg.layout("end_inset_m")
	var max_piece := cfg.layout("max_piece_m")
	var lift := cfg.layout("ground_lift_m")
	var lane_frac := cfg.layout("car_lane_frac")
	var walk_frac := cfg.layout("walker_sidewalk_frac")
	var broad_share := cfg.layout("body_broad_share")
	var jitter := cfg.layout("human_scale_jitter")
	var spread := cfg.movement("speed_spread")
	var edges_used := 0
	for eid_v in act.edges_in_cell(cell):
		var eid := int(eid_v)
		var want := act.expected(eid, density)
		if want.x <= 0.0 and want.y <= 0.0:
			continue
		var e: WorldRoadEdge = act.net.edges.get(eid)
		if e == null:
			continue
		var pa := act.net.node_pos(e.a)
		var pb := act.net.node_pos(e.b)
		var span := pb - pa
		var length := span.length()
		if length < 1.0:
			continue
		var d := span / length
		var ins := minf(inset, length * 0.3)
		var usable := length - 2.0 * ins
		var pieces := maxi(1, ceili(usable / max_piece))
		var plen := usable / float(pieces)
		var share := plen / usable
		var sw := float(sidewalks.get(String(e.road_class), 0.0))
		var half_w := e.width * 0.5
		var base_dir := 1.0 if ViewHash.hash01(eid * 16 + CH_DIR, world_seed) < 0.5 else -1.0
		var used_edge := false
		for j in pieces:
			var s0 := pa + d * (ins + plen * float(j))
			var s1 := s0 + d * plen
			var h0: float = float(ground.call(s0.x, s0.y))
			var h1: float = float(ground.call(s1.x, s1.y))
			var sm := (s0 + s1) * 0.5
			var hm: float = float(ground.call(sm.x, sm.y))
			var bulge := hm - (h0 + h1) * 0.5
			var key := eid * 64 + j
			var n_car := int(floorf(want.x * share + ViewHash.hash01(key * 16 + CH_COUNT_CAR, world_seed)))
			var n_ppl := int(floorf(want.y * share + ViewHash.hash01(key * 16 + CH_COUNT_PEOPLE, world_seed)))
			var u_phase := ViewHash.hash01(key * 16 + CH_PHASE, world_seed)
			for i in n_car:
				var sign_dir := base_dir if i % 2 == 0 else -base_dir
				var row_color := 0
				if car_rows.size() > 0:
					row_color = car_rows[int(ViewHash.hash01((key * 32 + i) * 16 + CH_COLOR, world_seed) * car_rows.size())
							% car_rows.size()]
				var speed_q := int(ViewHash.hash01((key * 32 + i) * 16 + CH_SPEED, world_seed) * 16.0) & 15
				var phase_q := int(fposmod(GOLDEN * float(i + 1) + u_phase, 1.0) * PHASE_BITS) & (PHASE_BITS - 1)
				var packed := phase_q | (speed_q << 10) | ((row_color & 31) << 14)
				_emit(rows[KIND_CAR], origin, s0, s1, h0, h1, bulge, sign_dir, e.width * lane_frac, lift,
						1.0, plen, packed, bnd)
				counts[KIND_CAR] += 1
				used_edge = true
			for i in n_ppl:
				var key_i := (key * 32 + i) * 16
				var side := 1.0 if (i % 2 == 0) == (base_dir > 0.0) else -1.0
				var walk_dir := 1.0 if ViewHash.hash01(key_i + CH_DIR, world_seed) < 0.5 else -1.0
				var kind := KIND_BROAD if ViewHash.hash01(key_i + CH_BODY, world_seed) < broad_share else KIND_NEUTRAL
				var scale := 1.0 + jitter * (ViewHash.hash01(key_i + CH_SCALE, world_seed) * 2.0 - 1.0)
				var speed_q := int(ViewHash.hash01(key_i + CH_SPEED, world_seed) * 16.0) & 15
				var phase_q := int(fposmod(GOLDEN * float(i + 1) + u_phase, 1.0) * PHASE_BITS) & (PHASE_BITS - 1)
				var packed := phase_q | (speed_q << 10)
				var lateral := side * maxf(half_w - sw * walk_frac, 0.5)
				_emit(rows[kind], origin, s0, s1, h0, h1, bulge, walk_dir, lateral, lift, scale, plen, packed, bnd, true)
				counts[kind] += 1
				used_edge = true
		if used_edge:
			edges_used += 1
	var bounds := AABB()
	if bnd[0] <= bnd[3]:
		bounds = AABB(Vector3(bnd[0], bnd[1], bnd[2]), Vector3(bnd[3] - bnd[0], bnd[4] - bnd[1], bnd[5] - bnd[2]))
	return {"rows": rows, "counts": counts, "bounds": bounds, "edges": edges_used}


## Bir satır yazar. `lateral_raw`: araçta yarı genişlik x şerit payı (yürüme yönünün SAĞINA), yayada işaretli ofset
## (kenar sağına +). Yürüme yönü -1 ise parça sonundan başlayıp geriye gider; sağ taraf yürüme yönüne göre alınır.
static func _emit(out: PackedFloat32Array, origin: Vector2, s0: Vector2, s1: Vector2, h0: float, h1: float,
		bulge: float, dir_sign: float, lateral_raw: float, lift: float, scale: float, plen: float, packed: int,
		bnd: PackedFloat32Array, signed_side: bool = false) -> void:
	var from := s0 if dir_sign > 0.0 else s1
	var to := s1 if dir_sign > 0.0 else s0
	var fy := h0 if dir_sign > 0.0 else h1
	var ty := h1 if dir_sign > 0.0 else h0
	var heading := (to - from).normalized()
	# Haritada sağ taraf: yürüme yönü (hx, hz) için sağ = (-hz, hx) (yukarıdan bakışta +x doğu, +z güney).
	var right := Vector2(-heading.y, heading.x)
	# Araç: şerit yürüme yönünün sağında. Yaya: işaretli ofset KENARIN sağına (a->b yönü): yürüme yönü ters ise
	# kenarın sağı yürüme yönünün solu olur; işareti buna göre çevir.
	var off := lateral_raw if not signed_side else lateral_raw * dir_sign
	var p := from + right * off
	var y := fy + lift
	out.append_array(PackedFloat32Array([p.x - origin.x, y, p.y - origin.y, atan2(heading.x, heading.y) + FRONT_YAW_OFFSET,
			scale, plen, ty - fy, bulge, float(packed)]))
	var end := to + right * off
	bnd[0] = minf(bnd[0], minf(p.x, end.x) - origin.x)
	bnd[2] = minf(bnd[2], minf(p.y, end.y) - origin.y)
	bnd[3] = maxf(bnd[3], maxf(p.x, end.x) - origin.x)
	bnd[5] = maxf(bnd[5], maxf(p.y, end.y) - origin.y)
	bnd[1] = minf(bnd[1], minf(fy, ty) - 1.0)
	bnd[4] = maxf(bnd[4], maxf(fy, ty) + 4.0)
