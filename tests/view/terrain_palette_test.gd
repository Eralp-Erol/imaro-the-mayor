extends GdUnitTestSuite
## T-001 AD son kapı · M2 su (balon/kontur halesi yok, derin geçiş geniş-yumuşak, bükülmüş), M1 kaya kuralı (yalnız dik
## VE yüksek), D5 yamaç preset'i. Saf palet hesabı + kamera preset konumu (render gerektirmez; görsel kanıt capture
## ile).

const WATER_NEIGHBOUR_MAX_JUMP := 0.03  # komşu su örnekleri arası (400 m kaba hücre) en çok kanal farkı
const RIM_FREE_M := 800.0  # ince turkuaz kıyı şeridinin (≤ ~400 m) dışı

var _world: WorldData
var _palette: TerrainPalette


func before() -> void:
	_world = WorldTestSupport.coarse(WorldTestSupport.control())
	_palette = TerrainPalette.new(_world)


# --- M2: su ---

func test_water_has_no_island_halo_colour_beyond_the_thin_rim_depends_on_mainland_distance_only() -> void:
	# Ada çevresinde 400 m ötesinde renk yalnız ana karaya uzaklığa bağlıdır: yakın-ada mesafesi 0.6, 1.5, 2.2 km olsa da
	# aynı ton (eski palet: 1.4-2.2 km'de orta→derin sert geçişle ada çevresinde balon dairesi çiziyordu).
	var ref := TerrainPalette.water_color_from(3000.0, 4000.0, 40.0)
	for near in [600.0, 900.0, 1500.0, 2200.0]:
		assert_object(TerrainPalette.water_color_from(near, 4000.0, 40.0)).is_equal(ref)
	# Olumsuz: kıyıya yapışık şerit farklıdır (turkuaz kenar kalır).
	var rim := TerrainPalette.water_color_from(60.0, 4000.0, 3.0)
	assert_float(rim.g).is_greater(ref.g + 0.1)
	assert_float(rim.g / rim.b).is_greater(0.85)


func test_every_water_sample_beyond_the_rim_matches_the_mainland_only_model_and_islands_are_covered() -> void:
	var islands_checked := 0
	var island_dist := _island_distance()
	var differs_from_legacy := 0
	var w := _world.width
	for j in _world.height:
		for i in w:
			var idx := j * w + i
			if _world.land_mask[idx] == 1 or -_world.shore_distance[idx] < RIM_FREE_M:
				continue
			var p := _world.cell_to_world(i, j)
			var warp := _palette.water_warp_m(p.x, p.y)
			var main_m := _palette.main_distance_at(idx) + warp
			var expect := TerrainPalette.water_color_from(RIM_FREE_M * 4.0, main_m, _world.sea_level - _world.heights[idx])
			var got := _palette.water_color_at(idx, p.x, p.y)
			assert_float(got.r).is_equal_approx(expect.r, 0.0005)
			assert_float(got.g).is_equal_approx(expect.g, 0.0005)
			assert_float(got.b).is_equal_approx(expect.b, 0.0005)
			# Ada çevresindeki (ana karadan uzak) örnekler: eski kıyı-uzaklığı paleti burada halka çizerdi.
			if island_dist[idx] < 3000.0 and _palette.main_distance_at(idx) > 2.0 * island_dist[idx]:
				islands_checked += 1
				var legacy := TerrainPalette.water_color(_world.shore_distance[idx], 40.0)
				if absf(legacy.g - got.g) > 0.03:
					differs_from_legacy += 1
	assert_int(islands_checked).is_greater(20)  # test boş geçmez: ada çevresinde gerçekten örnek var
	assert_int(differs_from_legacy).is_greater(5)  # ...ve eski paletten ayrışıyor (duyarlılık)


func test_neighbouring_water_samples_never_jump_in_colour_away_from_the_rim() -> void:
	# Keskin kontur yok: komşu iki su örneği (kıyı şeridi dışı) arasında renk sıçraması sınırlı. Eski palet (800 m'de
	# 0→1 derin geçişi) 400 m hücrede 0.03'ü aşıyordu.
	var w := _world.width
	var worst := 0.0
	var checked := 0
	for j in _world.height - 1:
		for i in w - 1:
			var a := j * w + i
			if _world.land_mask[a] == 1 or -_world.shore_distance[a] < RIM_FREE_M:
				continue
			var pa := _world.cell_to_world(i, j)
			var ca := _palette.water_color_at(a, pa.x, pa.y)
			for other in [a + 1, a + w]:
				if _world.land_mask[other] == 1 or -_world.shore_distance[other] < RIM_FREE_M:
					continue
				var po := _world.cell_to_world(other % w, other / w)
				var co := _palette.water_color_at(other, po.x, po.y)
				worst = maxf(worst, maxf(absf(ca.r - co.r), maxf(absf(ca.g - co.g), absf(ca.b - co.b))))
				checked += 1
	assert_int(checked).is_greater(1000)
	assert_float(worst).is_less(WATER_NEIGHBOUR_MAX_JUMP)


func test_neighbour_jump_check_is_sensitive_the_legacy_narrow_band_would_exceed_it() -> void:
	# Olumsuz kontrol: dar (800 m) geçişli eski tipte bir bant, aynı 400 m komşu aralığında eşiği aşar.
	var worst := 0.0
	for k in range(1400, 2200, 100):
		var a := _narrow_deep(float(k))
		var b := _narrow_deep(float(k) + 400.0)
		worst = maxf(worst, absf(a.g - b.g))
	assert_float(worst).is_greater(WATER_NEIGHBOUR_MAX_JUMP)


func test_deep_transition_is_wide_and_smooth_and_the_bay_never_darker_than_open_sea() -> void:
	var edge := TerrainPalette.WATER_DEEP_EDGE
	assert_float(edge.y - edge.x).is_greater_equal(3000.0)  # geniş
	_assert_color_near(TerrainPalette.water_color_from(2000.0, edge.x, 1000.0), TerrainPalette.WATER_MID)
	_assert_color_near(TerrainPalette.water_color_from(2000.0, edge.y + 1.0, 1000.0), TerrainPalette.WATER_DEEP)
	var middle := TerrainPalette.water_color_from(2000.0, (edge.x + edge.y) * 0.5, 40.0)
	assert_float(middle.g).is_between(TerrainPalette.WATER_DEEP.g + 0.02, TerrainPalette.WATER_MID.g - 0.02)
	# Tekdüze: ana karadan uzaklaştıkça yalnız koyulaşır → körfez içi (daha yakın) açık denizden (daha uzak) koyu olamaz.
	var previous := 2.0
	for m in range(0, 9000, 100):
		var lum := TerrainPalette.water_color_from(2000.0, float(m), 40.0).get_luminance()
		assert_float(lum).is_less_equal(previous + 0.0001)
		previous = lum
	assert_float(previous).is_greater(0.12)  # en koyu ton siyaha yaklaşmaz


func test_main_distance_is_zero_on_the_mainland_and_exact_euclid_on_a_tiny_world() -> void:
	var tiny := _tiny_world()
	var p := TerrainPalette.new(tiny)
	var cell := tiny.cell_size
	# Ana kara hücresi (2, 3); id 2 (ada) hücresi (7, 1) HESABA katılmaz.
	assert_float(p.main_distance_at(3 * tiny.width + 2)).is_equal(0.0)
	assert_float(p.main_distance_at(3 * tiny.width + 5)).is_equal_approx(3.0 * cell - cell * 0.5, 0.01)
	assert_float(p.main_distance_at(7 * tiny.width + 5)).is_equal_approx(5.0 * cell - cell * 0.5, 0.01)  # (3,4) → 5
	assert_float(p.main_distance_at(1 * tiny.width + 7)).is_equal_approx(sqrt(29.0) * cell - cell * 0.5, 0.01)
	# Olumsuz: tüm kara ada ise ana kara yok → çok büyük (derin) uzaklık, sıfır değil.
	tiny.landmass_ids[3 * tiny.width + 2] = 2
	assert_float(TerrainPalette.new(tiny).main_distance_at(3 * tiny.width + 5)).is_greater(1.0e6)


func test_water_warp_is_bounded_low_frequency_deterministic_and_seed_dependent() -> void:
	var total_abs := 0.0
	var peak := 0.0
	var n := 0
	for k in 400:
		var x := 1000.0 + k * 97.0
		var z := 500.0 + k * 61.0
		var v := _palette.water_warp_m(x, z)
		assert_float(v).is_equal(_palette.water_warp_m(x, z))
		peak = maxf(peak, absf(v))
		total_abs += absf(v)
		n += 1
	assert_float(peak).is_less_equal(TerrainPalette.WATER_WARP_LARGE.y + TerrainPalette.WATER_WARP_SMALL.y + 0.01)
	assert_float(total_abs / n).is_greater(40.0)  # gerçekten büküyor (±~300 m mertebesi)
	# Düşük frekans: 100 m aralıkta büküm 20 m'den fazla değişmez.
	assert_float(absf(_palette.water_warp_m(10000.0, 10000.0) - _palette.water_warp_m(10100.0, 10000.0))).is_less(20.0)
	var other := TerrainPalette.new(WorldTestSupport.coarse(WorldTestSupport.control(), 99))
	var differs := false
	for k in 20:
		var x := 1000.0 + k * 500.0
		if not is_equal_approx(other.water_warp_m(x, 7000.0), _palette.water_warp_m(x, 7000.0)):
			differs = true
	assert_bool(differs).is_true()


# --- M1: kaya ---

func test_rock_needs_steep_and_high_or_summit_or_cliff() -> void:
	# Alçak/orta kotta (<450 m) hiçbir (cliff altı) eğimde kaya ağırlığı yok: sırtlar maki/orman.
	for elev in range(0, 451, 50):
		for slope in range(0, 41, 4):
			assert_float(TerrainPalette.rock_weight(float(elev), float(slope))).is_equal(0.0)
	# Dik ama alçak/orta: kaya yok (eski kural 21-34° eşiğinde boyuyordu).
	assert_float(TerrainPalette.rock_weight(300.0, 32.0)).is_less(0.02)
	assert_float(TerrainPalette.rock_weight(520.0, 34.0)).is_less(0.02)
	# Yüksek ama yumuşak eğim: kaya değil (maki).
	assert_float(TerrainPalette.rock_weight(700.0, 12.0)).is_less(0.05)
	# Dik VE yüksek (>~650 m): kaya.
	assert_float(TerrainPalette.rock_weight(760.0, 34.0)).is_greater(0.8)
	# Zirve ve en dik yer: kotundan/eğiminden biri yetmeli.
	assert_float(TerrainPalette.rock_weight(960.0, 8.0)).is_greater(0.7)
	assert_float(TerrainPalette.rock_weight(200.0, 58.0)).is_greater(0.9)


func test_steep_mid_elevation_slope_is_green_not_grey_and_high_steep_is_rock() -> void:
	var steep_mid := _palette.land_color(300.0, 30.0, 4000.0, 0, 20000.0, 20000.0)
	assert_float(steep_mid.g).is_greater(steep_mid.r)  # orman/maki yeşili
	var high_gentle := _palette.land_color(780.0, 10.0, 9000.0, 0, 33000.0, 27000.0)
	assert_float(high_gentle.g).is_greater(high_gentle.r - 0.02)  # zeytin maki, kahverengi kaya değil
	var high_steep := _palette.land_color(820.0, 38.0, 9000.0, 0, 33000.0, 27000.0)
	assert_float(high_steep.r).is_greater(high_steep.g)  # okra/gri kaya
	assert_float(high_steep.get_luminance()).is_greater(steep_mid.get_luminance())


func test_rock_is_a_minor_share_of_the_land_in_the_world() -> void:
	var land := 0
	var rocky := 0
	var w := _world.width
	for j in range(1, _world.height - 1):
		for i in range(1, w - 1):
			var idx := j * w + i
			if _world.land_mask[idx] == 0:
				continue
			var p := _world.cell_to_world(i, j)
			land += 1
			if TerrainPalette.rock_weight(_world.heights[idx] - _world.sea_level, _world.slope_degrees_at(p.x, p.y)) > 0.5:
				rocky += 1
	assert_int(land).is_greater(1000)
	assert_float(float(rocky) / float(land)).is_less(0.12)  # eski kural: sırtların neredeyse tamamı gri


# D5 yamaç preset'i testleri T-003 ile tests/view/camera_presets_test.gd'ye taşındı (CameraPresets).


# --- Yardımcılar ---

func _assert_color_near(actual: Color, expected: Color) -> void:
	for ch in 3:
		assert_float(actual[ch]).is_equal_approx(expected[ch], 0.0005)


## Eski tip dar geçiş: 800 m'de 0→1 (kıyı uzaklığı 1400→2200).
func _narrow_deep(away: float) -> Color:
	return TerrainPalette.WATER_MID.lerp(TerrainPalette.WATER_DEEP, smoothstep(1400.0, 2200.0, away))


## Örnek başına en yakın ADA (landmass >= 2) uzaklığı, m.
func _island_distance() -> PackedFloat32Array:
	var best := PackedFloat32Array()
	best.resize(_world.width * _world.height)
	best.fill(1.0e9)
	for island in _world.islands:
		var d := TerrainPalette.distance_to_landmass(_world, island.landmass_id)
		for k in best.size():
			best[k] = minf(best[k], d[k])
	return best


## 9 x 9 mikro dünya: ana kara (id 1) hücresi (2, 3), ada (id 2) hücresi (7, 1), kalan su.
func _tiny_world() -> WorldData:
	var t := WorldData.new()
	t.width = 9
	t.height = 9
	t.cell_size = 100.0
	t.sea_level = 0.0
	var count := t.width * t.height
	t.heights.resize(count)
	t.heights.fill(-10.0)
	t.land_mask.resize(count)
	t.region_ids.resize(count)
	t.landmass_ids.resize(count)
	t.shore_distance.resize(count)
	t.shore_distance.fill(-100.0)
	t.landmass_ids[3 * t.width + 2] = WorldData.LANDMASS_MAINLAND
	t.landmass_ids[1 * t.width + 7] = 2
	return t
