class_name NetworkTestSupport
extends RefCounted
## tests/world/network ortak yardımcıları (test paketi değildir). Sentetik düz dünya + el yapımı ızgara ağı; gerçek
## Ismeral
## ağı bir kez üretilir ve salt okunur paylaşılır (`default_network`); bozulmuş varyantlar bellekte üretilir.

const NETWORK_DATA_DIR := "res://data/world/ismeral"
const NETWORK_FILE := "network"
## Sentetik testlerde parsel şablonu (kentsel) ve kırsal.
const TEST_TEMPLATES := {
	"urban": {"lot_width_m": 20.0, "lot_width_jitter": 0.1, "max_depth_m": 30.0, "min_area_m2": 100.0,
			"min_frontage_m": 6.0},
	"rural": {"lot_width_m": 150.0, "lot_width_jitter": 0.0, "max_depth_m": 200.0, "min_area_m2": 2000.0,
			"min_frontage_m": 30.0},
}

static var _network_control_cache: Dictionary = {}
static var _default_network: WorldNetwork = null
static var _light_network: WorldNetwork = null


## Düz kara dünyası (isteğe bağlı su dikdörtgeni): tek bölge D1 tüm kara. Boyut m, hücre m.
static func flat_world(size_m: float = 3000.0, cell: float = 100.0, water: Rect2 = Rect2()) -> WorldData:
	var w := WorldData.new()
	w.world_id = &"flat_test"
	w.origin = Vector2.ZERO
	w.size = Vector2(size_m, size_m)
	w.cell_size = cell
	w.width = int(round(size_m / cell)) + 1
	w.height = w.width
	w.sea_level = 0.0
	var count := w.width * w.height
	w.heights.resize(count)
	w.land_mask.resize(count)
	w.region_ids.resize(count)
	w.landmass_ids.resize(count)
	w.shore_distance.resize(count)
	for j in w.height:
		for i in w.width:
			var idx := j * w.width + i
			var p := w.cell_to_world(i, j)
			var is_water := water.has_area() and water.has_point(p)
			w.heights[idx] = -5.0 if is_water else 10.0
			w.land_mask[idx] = 0 if is_water else 1
			w.region_ids[idx] = 0 if is_water else 1
			w.landmass_ids[idx] = 0 if is_water else WorldData.LANDMASS_MAINLAND
			w.shore_distance[idx] = -50.0 if is_water else 99999.0
	var region := WorldRegion.new()
	region.id = 1
	region.code = &"D1"
	region.anchor = w.size * 0.5
	region.radius = w.size
	w.regions.append(region)
	return w


static func test_rules(world: WorldData) -> NetworkRules:
	var control := {
		"classes": {"arterial": {"width_m": 20.0}, "collector": {"width_m": 14.0}, "local": {"width_m": 10.0},
				"field": {"width_m": 6.0}, "rail": {"width_m": 12.0}, "ferry": {"width_m": 0.0}},
		"geometry": {"snap_m": 3.0, "min_edge_m": 4.0},
		"parcel_templates": TEST_TEMPLATES.duplicate(true),
		"fabrics": [{"id": "U", "region": "D1", "template": "urban", "radius_norm": 10.0}],
	}
	return NetworkRules.from_control(world, control)


static func empty_network(world: WorldData, net_seed: int = 7) -> WorldNetwork:
	return WorldNetwork.create(world, test_rules(world), net_seed)


## (cols x rows) bloklu yerel yol ızgarası: (cols+1) x (rows+1) düğüm. Planarizer ile çizilir; mühürlüdür.
static func grid_network(world: WorldData, cols: int, rows: int, dx: float, dz: float, origin: Vector2,
		net_seed: int = 7) -> WorldNetwork:
	var net := empty_network(world, net_seed)
	for j in rows + 1:
		net.author_polyline(PackedVector2Array([origin + Vector2(0, j * dz), origin + Vector2(cols * dx, j * dz)]),
				WorldRoadEdge.CLASS_LOCAL)
	for i in cols + 1:
		net.author_polyline(PackedVector2Array([origin + Vector2(i * dx, 0), origin + Vector2(i * dx, rows * dz)]),
				WorldRoadEdge.CLASS_LOCAL)
	net.seal_base()
	return net


## Ismeral ağ kontrol verisi (derin kopya). Dosya yoksa boş sözlük.
static func network_control() -> Dictionary:
	if _network_control_cache.is_empty():
		var path := "%s/%s.json" % [NETWORK_DATA_DIR, NETWORK_FILE]
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary:
			_network_control_cache = parsed
	return _network_control_cache.duplicate(true)


## Varsayılan dünya (100 m) + varsayılan tohum ile üretilmiş Ismeral ağı; süreç başına bir kez. SALT OKUNUR.
static func default_network() -> WorldNetwork:
	if _default_network == null:
		_default_network = NetworkGenerator.generate(WorldTestSupport.default_world(), network_control(),
				WorldTestSupport.DEFAULT_SEED)
	return _default_network


## Küçültülmüş kentsel ayak izleri (yarıçap x 0,4): ~8x daha az parsel, hızlı üretim. Olumsuz/kayıt testleri bununla
## çalışır;
## topoloji kuralları aynıdır, yalnız yerleşim kümeleri küçüktür.
static func light_control() -> Dictionary:
	var c := network_control()
	for f: Dictionary in c["fabrics"]:
		if f.has("radius_norm"):
			f["radius_norm"] = float(f["radius_norm"]) * 0.4
		if f.has("radius_km"):
			f["radius_km"] = [float(f["radius_km"][0]) * 0.4, float(f["radius_km"][1]) * 0.4]
	return c


## Hafif ağ (varsayılan dünya + `light_control`); süreç başına bir kez. SALT OKUNUR.
static func light_network() -> WorldNetwork:
	if _light_network == null:
		_light_network = NetworkGenerator.generate(WorldTestSupport.default_world(), light_control(),
				WorldTestSupport.DEFAULT_SEED)
	return _light_network


## Hafif ağın YENİ ve değiştirilebilir kopyası (olumsuz testler bozar).
static func fresh_light(control: Dictionary = {}) -> WorldNetwork:
	return NetworkGenerator.generate(WorldTestSupport.default_world(), light_control() if control.is_empty() else control,
			WorldTestSupport.DEFAULT_SEED)


static func generate(control: Dictionary, world_seed: int = WorldTestSupport.DEFAULT_SEED,
		world: WorldData = null) -> WorldNetwork:
	var w := world if world != null else WorldTestSupport.default_world()
	return NetworkGenerator.generate(w, control, world_seed)


## Verideki iki kodlu bağlantı girdisini kaldırır (bozulmuş varyant üretimi).
static func drop_links_touching(control: Dictionary, fabric_id: String) -> void:
	var kept: Array = []
	for link: Dictionary in control.get("links", []):
		if str(link.get("from", "")) != fabric_id and str(link.get("to", "")) != fabric_id:
			kept.append(link)
	control["links"] = kept
