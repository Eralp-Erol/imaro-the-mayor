class_name WorldData
extends RefCounted
## Tek fiziksel dünya verisi: yükseklik alanı + kara/su maskesi + bölge raster'ı (T-001, WLD-01, TEK-03).
## Görünüm katmanı (chunk'lı arazi, su, kamera) ve simülasyon YALNIZ bu API'yi okur;
## ölçeğe göre ayrı kıyı çizgisi yoktur.
##
## Koordinat sözleşmesi (TEKNİK, kanon değil): dünya metresi, x = doğu, z = güney (kuzey = -z), y = yükseklik.
## Örnek noktası (i, j) dünya konumu `origin + Vector2(i, j) * cell_size` (hücre KÖŞESİ); `width` x `height` örnek.
## Raster'lar satır-büyük düz dizilerdir: indeks = j * width + i. Üretim: `WorldGenerator.generate()`.

const REGION_NONE := 0
const LANDMASS_WATER := 0
const LANDMASS_MAINLAND := 1

var world_id: StringName = &""
var world_seed: int = 0
## Metro sınırının kuzeybatı köşesi ve boyutu (dünya metresi).
var origin: Vector2 = Vector2.ZERO
var size: Vector2 = Vector2.ZERO
var cell_size: float = 100.0
var width: int = 0
var height: int = 0
var sea_level: float = 0.0

## Örnek başına yükseklik (m, deniz seviyesine göre değil dünya y'si). Kara > sea_level, su < sea_level (değişmez).
var heights: PackedFloat32Array = PackedFloat32Array()
## 1 = kara, 0 = su.
var land_mask: PackedByteArray = PackedByteArray()
## WorldRegion.id (0 = bölge dışı: kırsal/doğal alan, yeşil kuşak; su hücreleri de 0).
var region_ids: PackedByteArray = PackedByteArray()
## 0 = su, 1 = ana kara (en büyük kütle), 2.. = adalar (alana göre azalan).
var landmass_ids: PackedByteArray = PackedByteArray()
## İşaretli kıyı uzaklığı (m): karada +, suda −; kıyıya bitişik hücre ≈ ±yarım hücre. Su derinliği/renk geçişi için.
var shore_distance: PackedFloat32Array = PackedFloat32Array()

var regions: Array[WorldRegion] = []
var islands: Array[WorldIsland] = []
var sites: Array[WorldSite] = []
## Yerleşim sekileri (terrace): kapalı (enabled = false) olanlar da ayak iziyle listelenir;
## arazi yalnız açık olanlarda değişir.
var terraces: Array[WorldTerrace] = []
## T0 liman sahası işareti (sites içindeki ilk &"port"); yoksa null.
var port_site: WorldSite = null


## Metro sınırı (dünya metresi).
func bounds() -> Rect2:
	return Rect2(origin, size)


func contains(x: float, z: float) -> bool:
	return x >= origin.x and z >= origin.y and x <= origin.x + size.x and z <= origin.y + size.y


## Hücre köşesi indeksi (i, j) → dünya konumu.
func cell_to_world(i: int, j: int) -> Vector2:
	return origin + Vector2(i, j) * cell_size


## Dünya konumu → en yakın örnek indeksi (sınıra kenetlenir).
func world_to_index(x: float, z: float) -> int:
	var i := clampi(int(round((x - origin.x) / cell_size)), 0, width - 1)
	var j := clampi(int(round((z - origin.y) / cell_size)), 0, height - 1)
	return j * width + i


## Bilineer yükseklik (m); sınır dışı konumlar kenara kenetlenir.
func height_at(x: float, z: float) -> float:
	var fx := clampf((x - origin.x) / cell_size, 0.0, float(width - 1))
	var fz := clampf((z - origin.y) / cell_size, 0.0, float(height - 1))
	var i0 := mini(int(fx), width - 2)
	var j0 := mini(int(fz), height - 2)
	var tx := fx - i0
	var tz := fz - j0
	var idx := j0 * width + i0
	var top := lerpf(heights[idx], heights[idx + 1], tx)
	var bottom := lerpf(heights[idx + width], heights[idx + width + 1], tx)
	return lerpf(top, bottom, tz)


## Görünür kıyı çizgisi: bilineer yükseklik deniz seviyesinin altındaysa su (render ile aynı tanım).
func is_water(x: float, z: float) -> bool:
	return height_at(x, z) < sea_level


## Su derinliği (m, ≥ 0); karada 0.
func depth_at(x: float, z: float) -> float:
	return maxf(0.0, sea_level - height_at(x, z))


## En yakın örneğin bölge kimliği (0 = bölge dışı/su).
func region_at(x: float, z: float) -> int:
	return region_ids[world_to_index(x, z)]


func region_code_at(x: float, z: float) -> StringName:
	var rid := region_at(x, z)
	return &"" if rid == REGION_NONE else regions[rid - 1].code


## En yakın örneğin kara kütlesi (0 su, 1 ana kara, 2.. ada).
func landmass_at(x: float, z: float) -> int:
	return landmass_ids[world_to_index(x, z)]


## Eğim (derece), merkezî farklarla.
func slope_degrees_at(x: float, z: float) -> float:
	var d := cell_size
	var gx := (height_at(x + d, z) - height_at(x - d, z)) / (2.0 * d)
	var gz := (height_at(x, z + d) - height_at(x, z - d)) / (2.0 * d)
	return rad_to_deg(atan(sqrt(gx * gx + gz * gz)))


## Kodla bölge (&"D1" …); yoksa null.
func region_by_code(code: StringName) -> WorldRegion:
	for r in regions:
		if r.code == code:
			return r
	return null


## Bölge koduna ait yerleşim sekileri (açık/kapalı fark etmez).
func terraces_of_region(code: StringName) -> Array[WorldTerrace]:
	var out: Array[WorldTerrace] = []
	for t in terraces:
		if t.region_code == code:
			out.append(t)
	return out


func site_by_id(site_id: StringName) -> WorldSite:
	for s in sites:
		if s.id == site_id:
			return s
	return null


## Kanonik durum sözlüğü (StateHash'e girer). Büyük raster'lar yerel SHA-256 ile (ham bayt) özetlenir; böylece
## `state_hash()` 160k örnekte bile milisaniyeler sürer. `shore_distance` türevdir, dahil değildir.
func state_dict() -> Dictionary:
	var region_state: Array = []
	for r in regions:
		region_state.append(r.state_dict())
	var island_state: Array = []
	for isl in islands:
		island_state.append(isl.state_dict())
	var site_state: Array = []
	for s in sites:
		site_state.append(s.state_dict())
	var terrace_state: Array = []
	for t in terraces:
		terrace_state.append(t.state_dict())
	return {
		"world_id": world_id, "seed": world_seed, "origin": [origin.x, origin.y], "size": [size.x, size.y],
		"cell_size": cell_size, "width": width, "height": height, "sea_level": sea_level,
		"heights_sha256": _sha256_hex(heights.to_byte_array()),
		"land_mask_sha256": _sha256_hex(land_mask),
		"region_ids_sha256": _sha256_hex(region_ids),
		"landmass_ids_sha256": _sha256_hex(landmass_ids),
		"regions": region_state, "islands": island_state, "sites": site_state,
		"terraces": terrace_state,
	}


## Dünya özetinin SHA-256 hex'i: aynı kontrol verisi + tohum + hücre boyutu → aynı hash (TEK-01/02).
func state_hash() -> String:
	return StateHash.of(state_dict())


static func _sha256_hex(bytes: PackedByteArray) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(bytes)
	return ctx.finish().hex_encode()
