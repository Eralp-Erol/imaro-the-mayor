class_name BuildingTestSupport
extends RefCounted
## tests/view/buildings ortak yardımcıları (test paketi değildir): sentetik düz dünya, el yapımı ızgara ağı, kit tablosu
## ve BuildingColumns üreticileri. Başsız (render yok).

const NETWORK_DATA_DIR := "res://data/world/ismeral"

static var _lib: KitLibrary = null
static var _kit: BuildingKit = null


static func library() -> KitLibrary:
	if _lib == null:
		_lib = KitLibrary.load_manifest()
	return _lib


## Manifest + PROXY şablonları (süreç başına bir kez; SALT OKUNUR).
static func kit() -> BuildingKit:
	if _kit == null:
		_kit = BuildingKit.from_library(library())
	return _kit


## Düz kara dünyası (isteğe bağlı su dikdörtgeni): tek bölge D1. Boyut m, hücre m.
static func flat_world(size_m: float = 4000.0, cell: float = 100.0, water: Rect2 = Rect2(),
		land_height: float = 10.0) -> WorldData:
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
			w.heights[idx] = -5.0 if is_water else land_height
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


## (cols x rows) bloklu yerel yol ızgarası; mühürlü, parselli (kentsel şablon).
static func grid_network(world: WorldData, cols: int, rows: int, dx: float, dz: float, origin: Vector2,
		net_seed: int = 7) -> WorldNetwork:
	var control := {
		"classes": {"arterial": {"width_m": 20.0}, "collector": {"width_m": 14.0}, "local": {"width_m": 10.0},
				"field": {"width_m": 6.0}, "rail": {"width_m": 12.0}, "ferry": {"width_m": 0.0}},
		"geometry": {"snap_m": 3.0, "min_edge_m": 4.0},
		"parcel_templates": {
			"urban": {"lot_width_m": 20.0, "lot_width_jitter": 0.1, "max_depth_m": 30.0, "min_area_m2": 100.0,
					"min_frontage_m": 6.0},
			"rural": {"lot_width_m": 150.0, "lot_width_jitter": 0.0, "max_depth_m": 200.0, "min_area_m2": 2000.0,
					"min_frontage_m": 30.0},
		},
		"fabrics": [{"id": "U", "region": "D1", "template": "urban", "radius_norm": 10.0}],
	}
	var net := WorldNetwork.create(world, NetworkRules.from_control(world, control), net_seed)
	for j in rows + 1:
		net.author_polyline(PackedVector2Array([origin + Vector2(0, j * dz), origin + Vector2(cols * dx, j * dz)]),
				WorldRoadEdge.CLASS_LOCAL)
	for i in cols + 1:
		net.author_polyline(PackedVector2Array([origin + Vector2(i * dx, 0), origin + Vector2(i * dx, rows * dz)]),
				WorldRoadEdge.CLASS_LOCAL)
	net.seal_base()
	return net


## Satır sözlüklerinden BuildingColumns: {m, x, z, yaw?, wall?, roof?, accent?, bright?, parcel?}.
static func columns(rows: Array) -> BuildingColumns:
	var cols := BuildingColumns.new()
	for r: Dictionary in rows:
		cols.add(int(r.get("parcel", 1)), int(r["m"]), float(r["x"]), float(r["z"]), float(r.get("yaw", 0.0)), 3,
				int(r.get("wall", 1)), int(r.get("roof", 2)), int(r.get("accent", 3)), int(r.get("bright", 128)), 0,
				BuildingColumns.ERA_MID)
	return cols


## Tek modül, ızgara düzeninde `n x n` yapı (adım `step` m), (x0, z0)'dan başlar.
static func grid_columns(module: int, n: int, step: float, x0: float, z0: float) -> BuildingColumns:
	var rows: Array = []
	for j in n:
		for i in n:
			rows.append({"m": module, "x": x0 + i * step, "z": z0 + j * step, "yaw": 0.3 * float((i + j) % 5),
					"wall": 1 + (i + j) % 6, "roof": 17 + (i * 3 + j) % 4, "accent": 22 + i % 3,
					"bright": (i * 37 + j * 11) % 256, "parcel": 1 + j * n + i})
	return columns(rows)
