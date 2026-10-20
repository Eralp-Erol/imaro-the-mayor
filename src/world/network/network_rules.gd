class_name NetworkRules
extends RefCounted
## Ağ katmanının kural/yapılandırma kümesi (T-011): sınıf genişlikleri, parsel şablonları, kentsel ayak izleri.
## `network.json` kontrol verisinden + WorldData'dan türetilir (koordinat gömme yok). WorldNetwork artımlı
## güncellemede
## (oyuncu yolu) parselleri aynı kurallarla yeniden üretir; bu yüzden kurallar ağın içinde yaşar. Saf veri.

const TEMPLATE_RURAL := &"rural"
const _FNV_OFFSET := 2166136261
const _FNV_PRIME := 16777619
const _MASK32 := 0xFFFFFFFF

var control: Dictionary = {}
var class_width: Dictionary = {}
var snap_m: float = 3.0
var min_edge_m: float = 4.0
var max_segment_m: float = 350.0
var max_block_area_m2: float = 4.0e6
var min_block_area_m2: float = 400.0
## Şablon adı -> parametre sözlüğü (lot_width_m, lot_width_jitter, max_depth_m, min_area_m2, min_frontage_m).
var templates: Dictionary = {}
## Öncelik sırası: ilk eşleşen ayak izi kazanır (T0 saha çıkıntısı bölge ayak izinden önce).
var footprints: Array[NetworkFootprint] = []
var _regions: Array[WorldRegion] = []


static func from_control(world: WorldData, net_control: Dictionary) -> NetworkRules:
	var rules := NetworkRules.new()
	rules.control = net_control.duplicate(true)
	rules._regions = world.regions
	var classes: Dictionary = net_control.get("classes", {})
	for cls in WorldRoadEdge.ALL_CLASSES:
		rules.class_width[cls] = float((classes.get(String(cls), {}) as Dictionary).get("width_m", 8.0))
	var geo: Dictionary = net_control.get("geometry", {})
	rules.snap_m = float(geo.get("snap_m", 3.0))
	rules.min_edge_m = float(geo.get("min_edge_m", 4.0))
	rules.max_segment_m = float(geo.get("max_segment_m", 350.0))
	var block_rules: Dictionary = net_control.get("block_rules", {})
	rules.max_block_area_m2 = float(block_rules.get("max_block_area_m2", 4.0e6))
	rules.min_block_area_m2 = float(block_rules.get("min_block_area_m2", 400.0))
	rules.templates = (net_control.get("parcel_templates", {}) as Dictionary).duplicate(true)
	for entry: Dictionary in net_control.get("fabrics", []):
		var fp := _footprint_from_entry(world, entry)
		if fp != null:
			rules.footprints.append(fp)
	return rules


static func _footprint_from_entry(world: WorldData, entry: Dictionary) -> NetworkFootprint:
	var fp := NetworkFootprint.new()
	fp.id = StringName(str(entry["id"]))
	fp.template = StringName(str(entry.get("template", "mixed")))
	fp.lattice = (entry.get("lattice", {}) as Dictionary).duplicate(true)
	if entry.has("sites"):
		var points: Array[Vector2] = []
		for site_id in entry["sites"]:
			var site := world.site_by_id(StringName(str(site_id)))
			if site == null:
				return null
			points.append(site.position)
		fp.shape = NetworkFootprint.SHAPE_CAPSULE
		fp.seg_a = points[0]
		fp.seg_b = points[points.size() - 1]
		fp.pad = float(entry.get("pad_m", 600.0))
		fp.region_code = StringName(str(entry.get("region", "")))
		return fp
	var region := world.region_by_code(StringName(str(entry["region"])))
	if region == null:
		return null
	fp.region_code = region.code
	fp.rotation_rad = deg_to_rad(region.rotation_deg)
	fp.center = region.anchor
	if str(entry.get("center", "anchor")) == "terrace":
		for t in world.terraces_of_region(region.code):
			if t.enabled:
				fp.center = t.center
				break
	if entry.has("offset_norm"):
		var o: Array = entry["offset_norm"]
		fp.center += Vector2(float(o[0]), float(o[1])) * region.radius
	if entry.has("radius_km"):
		var r: Array = entry["radius_km"]
		fp.radii = Vector2(float(r[0]), float(r[1])) * 1000.0
	else:
		fp.radii = region.radius * float(entry.get("radius_norm", 0.5))
	return fp


func footprint_by_id(fabric_id: StringName) -> NetworkFootprint:
	for fp in footprints:
		if fp.id == fabric_id:
			return fp
	return null


## Noktanın şablon adı: ilk eşleşen ayak izi; hiçbirinde değilse kırsal.
func template_at(p: Vector2) -> StringName:
	for fp in footprints:
		if fp.contains(p):
			return fp.template
	return TEMPLATE_RURAL


func template_params(name: StringName) -> Dictionary:
	return templates.get(String(name), templates.get(String(TEMPLATE_RURAL), {}))


func width_of(cls: StringName) -> float:
	return float(class_width.get(cls, 8.0))


## Parsel bölge kodu: WorldData bölge raster'ı; bölge dışındaysa (yeşil kuşak/tarım) en yakın bölge (normalize
## uzaklık).
func region_code_at(world: WorldData, p: Vector2) -> StringName:
	var code := world.region_code_at(p.x, p.y)
	if code != &"":
		return code
	var best := INF
	var best_code: StringName = &""
	for r in _regions:
		var d := p - r.anchor
		var c := cos(deg_to_rad(r.rotation_deg))
		var s := sin(deg_to_rad(r.rotation_deg))
		var ux := (d.x * c + d.y * s) / r.radius.x
		var uy := (-d.x * s + d.y * c) / r.radius.y
		var u := sqrt(ux * ux + uy * uy)
		if u < best:
			best = u
			best_code = r.code
	return best_code


## 32-bit FNV-1a: (tohum, etiket) -> bağımsız RNG akışı tohumu (WorldGenerator ile aynı yöntem; tamsayı, platformdan
## bağımsız).
## Bir akışa çağrı eklemek diğerlerini kaydırmaz.
static func stream_seed(world_seed: int, label: String) -> int:
	var h := _FNV_OFFSET
	for byte in label.to_utf8_buffer():
		h = ((h ^ byte) * _FNV_PRIME) & _MASK32
	for shift in [0, 8, 16, 24, 32, 40, 48, 56]:
		h = ((h ^ ((world_seed >> shift) & 0xFF)) * _FNV_PRIME) & _MASK32
	return h
