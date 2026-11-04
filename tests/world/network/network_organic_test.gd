extends GdUnitTestSuite
## T-049 A · Organik şehir sınırı: ayak izi saf elips değil; sınır gürültüyle bükülür, arter yönünde şerit (ribbon)
## uzantısı verir, dik yamaçta geri çekilir, deterministiktir ve koordinat gömmez (WLD-01/04, Q-015).
## Ayak izi alanı (`NetworkShape`) ağ üretilmeden ölçülür (hızlı); ağ düzeyi kanıt `default_network` ile.

const RAYS := 72
const STEP := 0.01
const MAX_R := 3.0
## Elips-normalize yarıçap değişim katsayısı (CV): saf elips 0; organik sınır bunun belirgin üstünde.
const MIN_CV := 0.08
const MIN_RIBBON_RATIO := 1.25
const URBAN := ["core", "compact", "mixed"]

var _world: WorldData
var _control: Dictionary
var _rules: NetworkRules


func before() -> void:
	_world = WorldTestSupport.default_world()
	_control = NetworkTestSupport.network_control()
	_rules = NetworkRules.from_control(_world, _control)


static func _ellipses(rules: NetworkRules) -> Array[NetworkFootprint]:
	var out: Array[NetworkFootprint] = []
	for fp in rules.footprints:
		if fp.shape == NetworkFootprint.SHAPE_ELLIPSE:
			out.append(fp)
	return out


## Işın boyunca elips-normalize en dış yarıçap (1.0 = saf elips sınırı).
static func _ray_radius(fp: NetworkFootprint, angle: float) -> float:
	var dir := Vector2.from_angle(angle)
	var unit := Vector2(dir.x * fp.radii.x, dir.y * fp.radii.y)
	var best := 0.0
	var r := STEP
	while r < MAX_R:
		if fp.norm_dist(fp.center + unit * r) <= 1.0:
			best = r
		r += STEP
	return best


static func _radii(fp: NetworkFootprint) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for k in RAYS:
		out.append(_ray_radius(fp, TAU * float(k) / float(RAYS)))
	return out


static func _cv(values: PackedFloat32Array) -> float:
	var mean := 0.0
	for v in values:
		mean += v
	mean /= float(values.size())
	var acc := 0.0
	for v in values:
		acc += (v - mean) * (v - mean)
	return sqrt(acc / float(values.size())) / maxf(mean, 1.0e-6)


## Bağlantı (links) yönlerindeki ışın yarıçaplarının ortalaması; ortak merkezler kontrol verisi + ayak izlerinden.
static func _link_ray_mean(rules: NetworkRules, control: Dictionary, fp: NetworkFootprint) -> float:
	var centers := {}
	for other in rules.footprints:
		centers[other.id] = other.center if other.shape == NetworkFootprint.SHAPE_ELLIPSE \
				else (other.seg_a + other.seg_b) * 0.5
	var sum := 0.0
	var count := 0
	for link: Dictionary in control.get("links", []):
		var a := StringName(str(link["from"]))
		var b := StringName(str(link["to"]))
		var other := b if a == fp.id else (a if b == fp.id else &"")
		if other == &"" or not centers.has(other):
			continue
		sum += _ray_radius(fp, ((centers[other] as Vector2) - fp.center).angle())
		count += 1
	return sum / float(maxi(count, 1))


func _legacy_rules() -> NetworkRules:
	var c := NetworkTestSupport.network_control()
	c["organic"]["enabled"] = false
	return NetworkRules.from_control(_world, c)


# --- Sınır biçimi ---

func test_organic_boundary_is_not_an_ellipse_for_any_region_centre() -> void:
	var fps := _ellipses(_rules)
	assert_int(fps.size()).is_equal(6)
	for fp in fps:
		assert_int(fp.warp_size).is_greater(0)
		var cv := _cv(_radii(fp))
		assert_float(cv).override_failure_message("%s radyal CV %.3f" % [fp.id, cv]).is_greater(MIN_CV)


func test_disabled_organic_data_gives_the_pure_ellipse_negative() -> void:
	for fp in _ellipses(_legacy_rules()):
		assert_int(fp.warp_size).is_equal(0)
		assert_float(_cv(_radii(fp))).override_failure_message("%s" % fp.id).is_less(0.02)


func test_boundary_is_noise_bent_not_only_lobes() -> void:
	# Gürültü kapatılırsa (ribbon/terrain kalsın) sınır belirgin biçimde sadeleşir: gürültü gerçekten kullanılıyor.
	var c := NetworkTestSupport.network_control()
	c["organic"]["defaults"]["noise"]["amp"] = [0.0, 0.0]
	for code in ["D1", "D6"]:
		c["organic"]["fabrics"][code]["noise"]["amp"] = [0.0, 0.0]
	var quiet := NetworkRules.from_control(_world, c)
	var d1 := _rules.footprint_by_id(&"D1")
	var d6 := _rules.footprint_by_id(&"D6")
	var q1 := quiet.footprint_by_id(&"D1")
	var q6 := quiet.footprint_by_id(&"D6")
	assert_bool(_radii(d1) != _radii(q1)).is_true()
	assert_bool(_radii(d6) != _radii(q6)).is_true()


# --- Arter şerit uzantısı ---

func test_footprints_extend_along_the_links_toward_neighbour_centres() -> void:
	var ratios := PackedFloat32Array()
	for fp in _ellipses(_rules):
		var r := _link_ray_mean(_rules, _control, fp)
		ratios.append(r)
		assert_float(r).override_failure_message("%s link yönü yarıçapı %.2f" % [fp.id, r]).is_greater(1.0)
	var mean := 0.0
	for v in ratios:
		mean += v
	mean /= float(ratios.size())
	assert_float(mean).override_failure_message("ortalama link yönü yarıçapı %.2f" % mean) \
			.is_greater(MIN_RIBBON_RATIO)


func test_ribbon_extension_vanishes_without_ribbon_gain_negative() -> void:
	var c := NetworkTestSupport.network_control()
	c["organic"]["defaults"]["ribbon"]["gain"] = 0.0
	for code in c["organic"]["fabrics"]:
		c["organic"]["fabrics"][code]["ribbon"] = {"gain": 0.0}
	var flat := NetworkRules.from_control(_world, c)
	var with_sum := 0.0
	var without_sum := 0.0
	for fp in _ellipses(_rules):
		with_sum += _link_ray_mean(_rules, _control, fp)
		without_sum += _link_ray_mean(flat, c, flat.footprint_by_id(fp.id))
	assert_float(without_sum).is_less(with_sum * 0.85)


# --- Arazi etkisi ---

func test_steep_ground_pulls_the_boundary_back_and_flat_ground_spreads_it() -> void:
	var c := NetworkTestSupport.network_control()
	var t: Dictionary = c["organic"]["defaults"]["terrain"]
	t["steep_cut"] = 0.0
	t["flat_gain"] = 0.0
	var neutral := NetworkRules.from_control(_world, c)
	var steep_delta := 0.0
	var flat_delta := 0.0
	var steep_n := 0
	var flat_n := 0
	for fp in _ellipses(_rules):
		var base := neutral.footprint_by_id(fp.id)
		for j in range(0, fp.warp_size, 2):
			for i in range(0, fp.warp_size, 2):
				var p := fp.warp_origin + Vector2(float(i), float(j)) * fp.warp_cell
				var slope := _world.slope_degrees_at(p.x, p.y)
				var d := fp.warp_at(p) - base.warp_at(p)
				if slope >= 8.0:
					steep_delta += d
					steep_n += 1
				elif slope <= 1.0:
					flat_delta += d
					flat_n += 1
	assert_int(steep_n).is_greater(50)
	assert_int(flat_n).is_greater(50)
	assert_float(steep_delta / float(steep_n)).is_less(-0.3)
	assert_float(flat_delta / float(flat_n)).is_greater(0.0)


# --- Determinizm / veri-odaklılık ---

func test_same_control_same_warp_and_layout_seed_changes_it() -> void:
	var again := NetworkRules.from_control(_world, NetworkTestSupport.network_control())
	for fp in _ellipses(_rules):
		assert_bool(again.footprint_by_id(fp.id).warp == fp.warp).override_failure_message(String(fp.id)).is_true()
	var c := NetworkTestSupport.network_control()
	c["layout_seed"] = int(c["layout_seed"]) + 1
	var other := NetworkRules.from_control(_world, c)
	var differs := 0
	for fp in _ellipses(_rules):
		if other.footprint_by_id(fp.id).warp != fp.warp:
			differs += 1
	assert_int(differs).is_equal(6)


func test_organic_data_contains_no_coordinates_and_footprint_state_is_data_derived() -> void:
	var organic: Dictionary = _control["organic"]
	var text := JSON.stringify(organic)
	for key in ["anchor_km", "pos_km", "center_km", "outline_km", "coast_path_km", "position"]:
		assert_bool(text.contains(key)).is_false()
	assert_bool(organic["fabrics"].keys().size() >= 6).is_true()


# --- Ağ düzeyi kanıt ---

func test_generated_network_extends_beyond_the_pure_ellipse() -> void:
	var net := NetworkTestSupport.default_network()
	var legacy := _legacy_rules()
	var outside := 0
	var urban := 0
	for pid: int in net.parcels:
		var p: WorldParcel = net.parcels[pid]
		if not URBAN.has(String(p.fabric)):
			continue
		var fp := legacy.footprint_by_id(p.region_code)
		if fp == null:
			continue
		urban += 1
		if fp.norm_dist(p.centroid) > 1.0:
			outside += 1
	assert_int(urban).is_greater(10000)
	assert_float(float(outside) / float(urban)).override_failure_message("elips dışı kentsel parsel payı").is_greater(0.05)
