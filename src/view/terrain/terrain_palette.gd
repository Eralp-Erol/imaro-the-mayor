class_name TerrainPalette
extends RefCounted
## Arazi/su renk kuralları (T-001, VIS-01, F04): kuru-yeşil-zeytin ova, koyu orman, okra-kahve sırt; mat, düşük
## kontrast.
## Girdi YALNIZ WorldData'dan türeyen değerler (yükseklik, eğim, kıyı mesafesi, bölge) + dünya konumu; çıktı sRGB.
## Saf hesap (Node yok, global rastgelelik yok) → iş parçacıklarından çağrılabilir; aynı girdi → aynı renk.
## Ova "tarla mozaiği": dünya konumuna bağlı, dönük dikdörtgen yamalar (tohum + konum hash'i); ayrı doku/harita yok.

## Tarla mozaiğinin tam güçle uygulandığı bölge kodları (veri odaklı ayar; diğer düz alçak alanlarda zayıf).
const FIELD_REGION_CODES: Array[StringName] = [&"D4", &"D2"]
const FIELD_STRENGTH_OTHER := 0.22
const FIELD_BLEND_M := 900.0

const SAND := Color(0.66, 0.60, 0.43)
const MEADOW := Color(0.47, 0.50, 0.27)
const FOREST := Color(0.16, 0.29, 0.15)
const FOREST_LIGHT := Color(0.24, 0.36, 0.18)
const SCRUB := Color(0.44, 0.42, 0.25)
const ROCK := Color(0.52, 0.40, 0.27)
const ROCK_HIGH := Color(0.56, 0.50, 0.42)
const SKIRT_EARTH := Color(0.12, 0.11, 0.10)
const FIELD_TONES: Array[Color] = [
	Color(0.58, 0.55, 0.29), Color(0.40, 0.49, 0.25), Color(0.67, 0.60, 0.38),
	Color(0.53, 0.40, 0.27), Color(0.34, 0.44, 0.23), Color(0.62, 0.50, 0.28),
	Color(0.46, 0.52, 0.30), Color(0.72, 0.66, 0.44),
]

const WATER_SHALLOW := Color(0.17, 0.47, 0.50)
const WATER_MID := Color(0.07, 0.30, 0.43)
const WATER_DEEP := Color(0.025, 0.09, 0.20)

const FIELD_ROTATION_RAD := 0.41
const FIELD_SIZE_M := Vector2(760.0, 480.0)
const _MASK32 := 0xFFFFFFFF

var _seed_mix: int = 0
## Örnek başına [0, 1] "tarla bölgesi" ağırlığı: FIELD_REGION_CODES maskesinin yumuşatılmışı (sert elips kenarı yok).
var _field_weight: PackedFloat32Array = PackedFloat32Array()


func _init(world: WorldData = null) -> void:
	if world == null:
		return
	_seed_mix = (world.world_seed * 2654435761) & _MASK32
	var field_ids := PackedByteArray()
	field_ids.resize(world.regions.size() + 1)
	for region in world.regions:
		if FIELD_REGION_CODES.has(region.code):
			field_ids[region.id] = 1
	var count := world.width * world.height
	var mask := PackedFloat32Array()
	mask.resize(count)
	for k in count:
		mask[k] = float(field_ids[world.region_ids[k]])
	var radius := maxi(1, int(round(FIELD_BLEND_M / world.cell_size)))
	_field_weight = _box_blur(_box_blur(mask, world.width, world.height, radius, true),
			world.width, world.height, radius, false)


## Kara hücresi rengi. `elev` = deniz seviyesi üstü yükseklik (m), `slope_deg`, `shore_m` işaretli kıyı uzaklığı,
## `sample` WorldData örnek indeksi (bölge ağırlığı için), (x, z) dünya metresi.
func land_color(elev: float, slope_deg: float, shore_m: float, sample: int, x: float, z: float) -> Color:
	var broad := _value_noise(x / 1800.0, z / 1800.0, 11)
	var fine := _value_noise(x / 380.0, z / 380.0, 29)
	# Katman eşikleri düşük frekanslı gürültüyle kayar: kontur bantları oluşmaz.
	var e := elev + (broad - 0.5) * 110.0
	var natural := MEADOW.lerp(SCRUB, smoothstep(0.35, 0.8, fine) * 0.55)
	var forest_t := smoothstep(35.0, 150.0, e) * (1.0 - smoothstep(560.0, 760.0, e))
	forest_t = clampf(forest_t + smoothstep(6.0, 15.0, slope_deg) * 0.55, 0.0, 1.0)
	var forest := FOREST.lerp(FOREST_LIGHT, smoothstep(0.3, 0.75, fine))
	var c := natural.lerp(forest, forest_t)
	var rock_t := maxf(smoothstep(560.0, 860.0, e) * 0.85, smoothstep(21.0, 34.0, slope_deg))
	c = c.lerp(ROCK.lerp(ROCK_HIGH, smoothstep(520.0, 820.0, e)), rock_t * 0.92)
	# Ova: düz ve alçaksa tarla mozaiği.
	var flat_t := (1.0 - smoothstep(2.5, 8.0, slope_deg)) * (1.0 - smoothstep(55.0, 170.0, elev))
	if flat_t > 0.0:
		var strength := lerpf(FIELD_STRENGTH_OTHER, 1.0, _field_weight[sample] if sample < _field_weight.size() else 0.0)
		c = c.lerp(_field_tone(x, z, broad), flat_t * strength)
	# Kıyı şeridi: ince kum.
	var sand_t := (1.0 - smoothstep(20.0, 120.0, shore_m)) * (1.0 - smoothstep(6.0, 16.0, slope_deg))
	c = c.lerp(SAND, sand_t * 0.6)
	# Yüz başına çok hafif parlaklık oynaması: düz gölgeleme ile birlikte faset okunur.
	var jitter := 1.0 + (_hash2(int(x / 50.0), int(z / 50.0), 57) - 0.5) * 0.07
	return Color(c.r * jitter, c.g * jitter, c.b * jitter)


## Su köşe rengi: kıyıya yakın sığ turkuaz → orta mavi → açık deniz koyu lacivert. `shore_m` karada +, suda −.
static func water_color(shore_m: float, depth_m: float) -> Color:
	var away := maxf(0.0, -shore_m)
	var near_t := smoothstep(0.0, 1000.0, away)
	var deep_t := smoothstep(500.0, 4800.0, away)
	# Çok sığ sulara (kayalık/ada) ek turkuaz.
	near_t *= 1.0 - exp(-maxf(depth_m, 0.0) / 6.0) * 0.5
	var c := WATER_SHALLOW.lerp(WATER_MID, near_t)
	return c.lerp(WATER_DEEP, deep_t)


func _field_tone(x: float, z: float, broad: float) -> Color:
	var ca := cos(FIELD_ROTATION_RAD)
	var sa := sin(FIELD_ROTATION_RAD)
	var u := (x * ca - z * sa) / FIELD_SIZE_M.x
	var v := (x * sa + z * ca) / FIELD_SIZE_M.y
	var iu := floori(u)
	var iv := floori(v)
	var r := _hash2(iu, iv, 3)
	var tone := FIELD_TONES[int(r * FIELD_TONES.size()) % FIELD_TONES.size()]
	# Geniş ölçekte kuru ↔ yeşil kayma (mevsim/ürün bölgeleri).
	var dry := smoothstep(0.3, 0.75, broad)
	tone = tone.lerp(Color(0.64, 0.57, 0.34), dry * 0.35)
	# Tarla kenarında hafif koyu şerit (sınır/sıra).
	var fu := u - floorf(u)
	var fv := v - floorf(v)
	var edge := minf(minf(fu, 1.0 - fu) * FIELD_SIZE_M.x, minf(fv, 1.0 - fv) * FIELD_SIZE_M.y)
	if edge < 22.0:
		tone = tone.darkened(0.12)
	tone = MEADOW.lerp(tone, 0.7)
	var k := 0.96 + _hash2(iu, iv, 8) * 0.08
	return Color(tone.r * k, tone.g * k, tone.b * k)


func _hash2(ix: int, iz: int, salt: int) -> float:
	var h := (ix * 73856093) ^ (iz * 19349663) ^ (salt * 83492791) ^ _seed_mix
	h = (h ^ (h >> 13)) & _MASK32
	h = (h * 1274126177) & _MASK32
	h = (h ^ (h >> 16)) & _MASK32
	return float(h) / 4294967296.0


func _value_noise(u: float, v: float, salt: int) -> float:
	var iu := floori(u)
	var iv := floori(v)
	var fu := smoothstep(0.0, 1.0, u - float(iu))
	var fv := smoothstep(0.0, 1.0, v - float(iv))
	var a := _hash2(iu, iv, salt)
	var b := _hash2(iu + 1, iv, salt)
	var c := _hash2(iu, iv + 1, salt)
	var d := _hash2(iu + 1, iv + 1, salt)
	return lerpf(lerpf(a, b, fu), lerpf(c, d, fu), fv)


## Ayrılabilir kutu bulanıklığı (kenarlar kenetlenir, kayan toplam O(n)); saf, WorldData'ya dokunmaz.
static func _box_blur(src: PackedFloat32Array, w: int, h: int, radius: int, horizontal: bool) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(src.size())
	var norm := 1.0 / float(2 * radius + 1)
	var lines := h if horizontal else w
	var length := w if horizontal else h
	var stride := 1 if horizontal else w
	var line_step := w if horizontal else 1
	for line in lines:
		var base := line * line_step
		var sum := 0.0
		for d in range(-radius, radius + 1):
			sum += src[base + clampi(d, 0, length - 1) * stride]
		for k in length:
			out[base + k * stride] = sum * norm
			sum += src[base + mini(k + radius + 1, length - 1) * stride]
			sum -= src[base + maxi(k - radius, 0) * stride]
	return out
