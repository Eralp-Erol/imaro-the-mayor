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
const FOREST := Color(0.19, 0.32, 0.17)
const FOREST_LIGHT := Color(0.26, 0.38, 0.20)
const SCRUB := Color(0.44, 0.42, 0.25)
## Yüksek/dik yamaç makisi: kuru okra-yeşil-zeytin (referans 02 D5 yamaçları). Kaya yalnız dik VE yüksek yerde.
const MAQUIS := Color(0.31, 0.35, 0.19)
const MAQUIS_DRY := Color(0.40, 0.38, 0.22)
const ROCK := Color(0.52, 0.40, 0.27)
const ROCK_HIGH := Color(0.56, 0.50, 0.42)
const SKIRT_EARTH := Color(0.12, 0.11, 0.10)
const FIELD_TONES: Array[Color] = [
	Color(0.58, 0.55, 0.29), Color(0.40, 0.49, 0.25), Color(0.67, 0.60, 0.38),
	Color(0.53, 0.40, 0.27), Color(0.34, 0.44, 0.23), Color(0.62, 0.50, 0.28),
	Color(0.46, 0.52, 0.30), Color(0.72, 0.66, 0.44),
]

## Su: sığ turkuaz kıyı şeridi → orta mavi → okunur lacivert. Sığ şerit HERHANGİ bir kıyıya (ada dahil) uzaklığa
## bağlıdır ve dardır; orta→derin geçişi YALNIZ ana karaya uzaklığa bağlı, geniş ve yumuşaktır. Adalar kendi derin/orta
## "balon halesini" üretmez: ada açık denizde ise etrafı yalnız ince turkuaz kenar + yerel deniz tonudur. En koyu ton
## siyaha yaklaşmaz.
const WATER_SHALLOW := Color(0.17, 0.47, 0.50)
const WATER_MID := Color(0.07, 0.30, 0.43)
const WATER_DEEP := Color(0.055, 0.20, 0.35)
## Sığ→yerel deniz geçişi [başlangıç, bitiş] (en yakın kıyıya uzaklık, m).
const WATER_SHALLOW_EDGE := Vector2(120.0, 400.0)
## Orta→derin geçişi [başlangıç, bitiş] (ANA KARAYA uzaklık, m): geniş ve yumuşak.
const WATER_DEEP_EDGE := Vector2(1400.0, 5600.0)
## Ana karaya uzaklığı dünya konumuna bağlı düşük frekanslı gürültüyle büken genlik (m, ±): kontur dairesi/şeridi
## düzgün eş-uzaklık eğrisi olmaktan çıkar. İki oktav; toplam ≈ ±310 m.
const WATER_WARP_LARGE := Vector2(7000.0, 220.0)
const WATER_WARP_SMALL := Vector2(2600.0, 90.0)
## Sığ şerit kenarının büküm payı (genliğin oranı): turkuaz şerit eşit kalınlıkta olmasın ama kıyıya yapışık kalsın.
const WATER_SHALLOW_WARP_SHARE := 0.15

const FIELD_ROTATION_RAD := 0.41
const FIELD_SIZE_M := Vector2(760.0, 480.0)
const _MASK32 := 0xFFFFFFFF

var _seed_mix: int = 0
## Su köşesi rengi için dünya kopyaları (PackedArray: kopya-yazımda paylaşım, ek bellek yok).
var _shore: PackedFloat32Array = PackedFloat32Array()
var _heights: PackedFloat32Array = PackedFloat32Array()
var _sea_level: float = 0.0
## Ana karaya (landmass 1) uzaklık, m; ada kıyısı hesaba KATILMAZ (balon halesi yok). Karada 0.
var _mainland_dist: PackedFloat32Array = PackedFloat32Array()
## Örnek başına [0, 1] "tarla bölgesi" ağırlığı: FIELD_REGION_CODES maskesinin yumuşatılmışı (sert elips kenarı yok).
var _field_weight: PackedFloat32Array = PackedFloat32Array()


func _init(world: WorldData = null) -> void:
	if world == null:
		return
	_seed_mix = (world.world_seed * 2654435761) & _MASK32
	_shore = world.shore_distance
	_heights = world.heights
	_sea_level = world.sea_level
	_mainland_dist = distance_to_landmass(world, WorldData.LANDMASS_MAINLAND)
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
	# Orman çizgisinin üstü: kuru okra-yeşil-zeytin maki (gri kaya DEĞİL).
	var maquis := MAQUIS.lerp(MAQUIS_DRY, smoothstep(0.3, 0.8, fine))
	c = c.lerp(maquis, smoothstep(430.0, 700.0, e) * 0.9)
	c = c.lerp(ROCK.lerp(ROCK_HIGH, smoothstep(520.0, 820.0, e)), rock_weight(e, slope_deg) * 0.92)
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


## Kaya ağırlığı [0, 1] (satış kuralı: gri kaya yalnız DİK ve YÜKSEK yerde): eğim eşiği yalnız ~650 m üstünde etkindir;
## alçak/orta kotta dik yamaç orman/maki kalır. Zirve (>~800 m) ve çok dik (>~45°) yerler kotundan bağımsız serbesttir.
## `elev` deniz seviyesi üstü m (çağıran gürültüyle kaydırılmış değer verebilir), `slope_deg` derece.
static func rock_weight(elev: float, slope_deg: float) -> float:
	var steep_high := smoothstep(24.0, 36.0, slope_deg) * smoothstep(590.0, 710.0, elev)
	var summit := smoothstep(780.0, 960.0, elev) * 0.85
	var cliff := smoothstep(44.0, 56.0, slope_deg)
	return maxf(maxf(steep_high, summit), cliff)


## Su köşe rengi (tek uzaklık; test/geriye uyum): kıyıdan uzaklığı hem "en yakın kıyı" hem "ana kara" uzaklığı sayar.
## `shore_m` karada +, suda −.
static func water_color(shore_m: float, depth_m: float) -> Color:
	var away := maxf(0.0, -shore_m)
	return water_color_from(away, away, depth_m)


## Su rengi çekirdeği. `near_m` = en yakın kıyıya (ada dahil) uzaklık → ince turkuaz şerit; `main_m` = ANA KARAYA
## uzaklık → orta→derin geçişi. Yerel deniz tonu = orta↔derin (yalnız ana karaya bağlı); sığ şerit ona karışır.
## Derin bant `main_m`'de tekdüzedir: körfez içi aynı uzaklıktaki açık denizden koyu çıkamaz.
static func water_color_from(near_m: float, main_m: float, depth_m: float) -> Color:
	var shallow_t := smoothstep(WATER_SHALLOW_EDGE.x, WATER_SHALLOW_EDGE.y, near_m)
	var deep_t := smoothstep(WATER_DEEP_EDGE.x, WATER_DEEP_EDGE.y, main_m)
	# Çok sığ sulara (kayalık/ada) sığ bandı biraz daha uzat.
	shallow_t *= 1.0 - exp(-maxf(depth_m, 0.0) / 6.0) * 0.5
	var local_sea := WATER_MID.lerp(WATER_DEEP, deep_t)
	return WATER_SHALLOW.lerp(local_sea, shallow_t)


## Su örneğinin (indeks `sample`, dünya konumu x, z) köşe rengi: ana karaya uzaklık dünya konumuna bağlı düşük frekanslı
## gürültüyle bükülür (aynı dünya + tohum → aynı renk; kontur dairesi/şeridi oluşmaz).
func water_color_at(sample: int, x: float, z: float) -> Color:
	var warp := water_warp_m(x, z)
	var near_m := maxf(0.0, -_shore[sample]) + warp * WATER_SHALLOW_WARP_SHARE
	var main_m := _mainland_dist[sample] + warp
	return water_color_from(near_m, main_m, _sea_level - _heights[sample])


## Düşük frekanslı büküm (m, yaklaşık ±310): yalnız dünya konumu + tohum.
func water_warp_m(x: float, z: float) -> float:
	var big := (_value_noise(x / WATER_WARP_LARGE.x, z / WATER_WARP_LARGE.x, 41) - 0.5) * 2.0 * WATER_WARP_LARGE.y
	var small := (_value_noise(x / WATER_WARP_SMALL.x, z / WATER_WARP_SMALL.x, 43) - 0.5) * 2.0 * WATER_WARP_SMALL.y
	return big + small


## Ana karaya (landmass 1) uzaklık, m (örnek merkezlerinden tam Öklid dönüşümü; kıyı hücresi ≈ yarım hücre, karada 0).
## Ana kara yoksa çok büyük sabit.
func main_distance_at(sample: int) -> float:
	return _mainland_dist[sample]


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


## Belirli kara kütlesine (landmass_ids == id) Öklid uzaklığı, m (Felzenszwalb–Huttenlocher, O(n)). Kütle hücresi 0,
## sudaki hücre için merkezler arası uzaklık − yarım hücre (en az 0; shore_distance sözleşmesiyle uyumlu).
static func distance_to_landmass(world: WorldData, landmass_id: int) -> PackedFloat32Array:
	var w := world.width
	var h := world.height
	var inf := 1.0e12
	var grid := PackedFloat64Array()
	grid.resize(w * h)
	for k in w * h:
		grid[k] = 0.0 if world.landmass_ids[k] == landmass_id else inf
	# Satırlar sonra sütunlar: her geçiş kare uzaklığı (hücre²) günceller.
	var line_f := PackedFloat64Array()
	var line_d := PackedFloat64Array()
	for j in h:
		line_f.resize(w)
		for i in w:
			line_f[i] = grid[j * w + i]
		line_d = _edt_1d(line_f, w)
		for i in w:
			grid[j * w + i] = line_d[i]
	for i in w:
		line_f.resize(h)
		for j in h:
			line_f[j] = grid[j * w + i]
		line_d = _edt_1d(line_f, h)
		for j in h:
			grid[j * w + i] = line_d[j]
	var out := PackedFloat32Array()
	out.resize(w * h)
	var cell := world.cell_size
	for k in w * h:
		var d2: float = grid[k]
		out[k] = 0.0 if d2 <= 0.0 else minf(maxf(sqrt(d2) * cell - cell * 0.5, 0.0), 1.0e9)
	return out


## 1B kare-uzaklık dönüşümü (alt zarf parabolleri). `f` örnek başına başlangıç değeri (0 ya da büyük).
static func _edt_1d(f: PackedFloat64Array, n: int) -> PackedFloat64Array:
	var d := PackedFloat64Array()
	d.resize(n)
	var v := PackedInt32Array()
	v.resize(n)
	var z := PackedFloat64Array()
	z.resize(n + 1)
	var k := 0
	v[0] = 0
	z[0] = -1.0e30
	z[1] = 1.0e30
	for q in range(1, n):
		var s := 0.0
		while true:
			var p := v[k]
			s = ((f[q] + float(q * q)) - (f[p] + float(p * p))) / float(2 * q - 2 * p)
			if s <= z[k] and k > 0:
				k -= 1
			else:
				break
		if s <= z[k]:
			# k == 0: yeni parabol ilkinin yerini alır.
			v[0] = q
			z[0] = -1.0e30
			z[1] = 1.0e30
		else:
			k += 1
			v[k] = q
			z[k] = s
			z[k + 1] = 1.0e30
	k = 0
	for q in n:
		while z[k + 1] < float(q):
			k += 1
		var dq := float(q - v[k])
		d[q] = dq * dq + f[v[k]]
	return d
