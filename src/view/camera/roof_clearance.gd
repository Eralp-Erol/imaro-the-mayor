class_name RoofClearance
extends RefCounted
## Bina farkında göz açıklığının çatı sağlayıcısı (ADR-0007 Ek c; art-director T-062 madde 3). Arazi açıklığına
## (`CameraMath.clearance_m`) paralel: kamera yalnız SORAR, yapı verisi değişmez.
##
## Kaynak: `BuildingColumns` (sim başlangıç durumu: konum, yaw, modül) + onaylı kit boyutları (`BuildingKit`:
## ayak izi, yükseklik) + `WorldData` zemini. Fizik/raycast ve sahne düğümü okumaz: aynı sütunlar -> aynı çatı
## yükseklikleri (deterministik). Çatı tepesi = ayak izi MERKEZİNDEKİ zemin + modül yüksekliği (kit `height_m`;
## saçak/mahya dahil): gözün altından geçmemesi gereken EN YÜKSEK nokta. Merkez zemini `BuildingGround.base_y`'nin
## (en düşük örnek) altına inmez, yani yamaçta bile tutucudur (gerçek tepe en çok birkaç metre aşağıdadır); 9 örnek
## yerine 1 örnek: 32 bin yapıda başlangıç maliyeti ~9 kat düşük. Su altındaki/dünya dışı yapılar (çizilmez) girmez.
##
## Sorgu `max_roof_y(x, z, radius)`: ayak izi (yaw'lı dikdörtgen) `radius` diskine değen yapıların en yüksek çatı
## tepesi (dünya y, m); yoksa `NO_ROOF`. Izgara dizini (`CELL_M`): yapı, sınırlayıcı karesinin değdiği her
## hücreye girer; sorgu yalnız `radius` karesinin hücrelerini tarar.

const NO_ROOF := -1.0e9
const CELL_M := 64.0

var count: int = 0
var _x: PackedFloat32Array = PackedFloat32Array()
var _z: PackedFloat32Array = PackedFloat32Array()
var _cos: PackedFloat32Array = PackedFloat32Array()
var _sin: PackedFloat32Array = PackedFloat32Array()
var _hw: PackedFloat32Array = PackedFloat32Array()
var _hd: PackedFloat32Array = PackedFloat32Array()
var _top: PackedFloat32Array = PackedFloat32Array()
var _grid: Dictionary = {}


## Gerçek veri: sütunlar + kit + dünya. Su üstünde/dünya dışında kalan (çizilmeyen) yapılar dizine girmez.
func set_from_columns(world: WorldData, cols: BuildingColumns, kit: BuildingKit) -> void:
	clear()
	for i in cols.count:
		var m := cols.module_idx[i]
		if m < 0 or m >= kit.count:
			continue
		var hw := kit.footprint_w[m] * 0.5
		var hd := kit.footprint_d[m] * 0.5
		if not world.contains(cols.x[i], cols.z[i]):
			continue
		var ground := world.height_at(cols.x[i], cols.z[i])
		if ground < world.sea_level:
			continue
		_append(cols.x[i], cols.z[i], cols.yaw[i], hw, hd, ground + kit.height_m[m])
	_index()


## Ham kaynak (test/araç): her yapı için merkez, yaw, yarı genişlik/derinlik ve çatı tepesi (dünya y).
func set_roofs(xs: PackedFloat32Array, zs: PackedFloat32Array, yaws: PackedFloat32Array,
		half_w: PackedFloat32Array, half_d: PackedFloat32Array, tops: PackedFloat32Array) -> void:
	clear()
	for i in xs.size():
		_append(xs[i], zs[i], yaws[i], half_w[i], half_d[i], tops[i])
	_index()


## (x, z) çevresindeki `radius` içine ayak izi değen yapıların en yüksek çatı tepesi (dünya y); yoksa `NO_ROOF`.
func max_roof_y(x: float, z: float, radius: float) -> float:
	if count == 0 or not is_finite(x) or not is_finite(z):
		return NO_ROOF
	var c0 := Vector2i(floori((x - radius) / CELL_M), floori((z - radius) / CELL_M))
	var c1 := Vector2i(floori((x + radius) / CELL_M), floori((z + radius) / CELL_M))
	var best := NO_ROOF
	for cx in range(c0.x, c1.x + 1):
		for cz in range(c0.y, c1.y + 1):
			var cell: Variant = _grid.get(Vector2i(cx, cz))
			if cell == null:
				continue
			for i in cell as PackedInt32Array:
				if _top[i] > best and _distance_to_footprint(i, x, z) <= radius:
					best = _top[i]
	return best


## Yaw'lı dikdörtgen ayak izine en yakın uzaklık (içerideyse 0). Yerel çerçeve: BuildingGround ile aynı dönüş.
func _distance_to_footprint(i: int, x: float, z: float) -> float:
	var dx := x - _x[i]
	var dz := z - _z[i]
	var lx := dx * _cos[i] - dz * _sin[i]
	var lz := dx * _sin[i] + dz * _cos[i]
	var ox := maxf(absf(lx) - _hw[i], 0.0)
	var oz := maxf(absf(lz) - _hd[i], 0.0)
	return sqrt(ox * ox + oz * oz)


## Dizini boşaltır.
func clear() -> void:
	count = 0
	_x = PackedFloat32Array()
	_z = PackedFloat32Array()
	_cos = PackedFloat32Array()
	_sin = PackedFloat32Array()
	_hw = PackedFloat32Array()
	_hd = PackedFloat32Array()
	_top = PackedFloat32Array()
	_grid.clear()


func _append(x: float, z: float, yaw: float, hw: float, hd: float, top: float) -> void:
	_x.append(x)
	_z.append(z)
	_cos.append(cos(yaw))
	_sin.append(sin(yaw))
	_hw.append(hw)
	_hd.append(hd)
	_top.append(top)
	count += 1


## Izgara: bir yapı, ayak izinin sınırlayıcı dairesinin değdiği her hücreye girer (sorgu hücre başına tek arama).
func _index() -> void:
	for i in count:
		var reach := sqrt(_hw[i] * _hw[i] + _hd[i] * _hd[i])
		var c0 := Vector2i(floori((_x[i] - reach) / CELL_M), floori((_z[i] - reach) / CELL_M))
		var c1 := Vector2i(floori((_x[i] + reach) / CELL_M), floori((_z[i] + reach) / CELL_M))
		for cx in range(c0.x, c1.x + 1):
			for cz in range(c0.y, c1.y + 1):
				var key := Vector2i(cx, cz)
				var bucket: PackedInt32Array = _grid.get(key, PackedInt32Array())
				bucket.append(i)
				_grid[key] = bucket
