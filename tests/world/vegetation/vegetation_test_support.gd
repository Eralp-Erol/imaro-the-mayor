class_name VegetationTestSupport
extends RefCounted
## tests/world/vegetation ortak yardımcıları (test paketi değildir). Tam Ismeral yerleşimi
## `SettlementTestSupport.full()` ile paylaşılır; bitki yerleşimi süreç başına bir kez üretilir (SALT OKUNUR).
## Determinizm/olumsuz testler hafif ağda (`light`) çalışır.
## Bağımsız doğrulayıcılar (bina/yol uzaklığı) üreteçten AYRI hesaplanır.

const VEG_SEED := 424242

static var _species: VegetationSpecies = null
static var _full: VegetationColumns = null
static var _light: VegetationColumns = null


static func species() -> VegetationSpecies:
	if _species == null:
		_species = VegetationSpecies.load_default()
	return _species


## Kuralların DERİN KOPYASI (çağıran serbestçe bozabilir).
static func control() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(VegetationRules.PATH))
	return (parsed as Dictionary).duplicate(true)


static func rules(control_data: Dictionary = {}) -> VegetationRules:
	return VegetationRules.from_control(control_data if not control_data.is_empty() else control(), species())


## Tam Ismeral: varsayılan dünya + tam ağ + varsayılan yerleşim + varsayılan bitki tohumu.
static func full() -> VegetationColumns:
	if _full == null:
		_full = VegetationPlacement.generate(SettlementTestSupport.full(), species(), rules(), VEG_SEED)
	return _full


## Hafif ağ üzerinde (varsayılan kurallar, varsayılan tohum); süreç başına bir kez.
static func light() -> VegetationColumns:
	if _light == null:
		_light = light_with(VEG_SEED, rules())
	return _light


static func light_with(veg_seed: int, the_rules: VegetationRules, report: bool = false) -> VegetationColumns:
	return VegetationPlacement.generate(SettlementTestSupport.light(), species(), the_rules, veg_seed, report)


static func columns_bytes(c: VegetationColumns) -> Array[PackedByteArray]:
	return [c.species, c.x.to_byte_array(), c.z.to_byte_array(), c.yaw.to_byte_array(), c.scale.to_byte_array(),
			c.layer, c.cell_keys.to_byte_array(), c.cell_start.to_byte_array()]


# ---------------------------------------------------------------- bağımsız geometri (üreteçten ayrı)

## Bina dikdörtgeni indeksi (40 m hücre): hücre anahtarı -> bina dizinleri.
static func building_grid(res: SettlementResult) -> Dictionary:
	var grid := {}
	var cols := res.columns
	for i in cols.count:
		var key := _gk(cols.x[i], cols.z[i])
		if not grid.has(key):
			grid[key] = []
		(grid[key] as Array).append(i)
	return grid


static func _gk(x: float, z: float) -> int:
	return int(floor(x / 40.0)) + 4096 * int(floor(z / 40.0))


## En yakın bina ayak izine uzaklık (m; 0 = içinde); 40 m'den uzaksa 40. Köşe poligonu + nokta-segment uzaklığı.
static func building_distance(res: SettlementResult, grid: Dictionary, p: Vector2) -> float:
	var best := 40.0
	var cx := int(floor(p.x / 40.0))
	var cz := int(floor(p.y / 40.0))
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var key := (cx + dx) + 4096 * (cz + dz)
			if not grid.has(key):
				continue
			for i: int in grid[key]:
				var m := res.module_of(i)
				var corners := SettlementObb.corners(res.columns.x[i], res.columns.z[i], res.columns.yaw[i], m.w, m.d)
				if Geometry2D.is_point_in_polygon(p, corners):
					return 0.0
				for k in 4:
					best = minf(best, NetworkGeometry.distance_point_segment(p, corners[k], corners[(k + 1) % 4]))
	return best


## Yol kesitine boşluk: min(uzaklık - yarım genişlik); kaldırım bandı `sidewalk` ile araç yoluna indirilebilir.
static func road_gap(net: WorldNetwork, p: Vector2, carriageway_only: bool, sidewalk: Dictionary) -> float:
	var best := 1.0e9
	for e in net.edges_near(p.x, p.y, 60.0):
		if e.road_class == WorldRoadEdge.CLASS_FERRY or e.width <= 0.0:
			continue
		var half := e.width * 0.5
		if carriageway_only:
			half = maxf(half - float(sidewalk.get(String(e.road_class), 0.0)), half * 0.5)
		best = minf(best, NetworkGeometry.distance_point_segment(p, net.node_pos(e.a), net.node_pos(e.b)) - half)
	return best
