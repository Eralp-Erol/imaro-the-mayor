extends GdUnitTestSuite
## T-041 · Seçili parsel halkası: seçince düğüm var, kaldırınca yok, bant/uzaklıkla kalınlık, olmayan parsel hatasız,
## geometri parseli çevreler ve zemine oturur, tek yüzey (<= 1 çizim çağrısı). Başsız: gerçek ekran görüntüsü DEĞİL.

const VIEWPORT := Vector2(1600.0, 900.0)
const GROUND_Y := 5.0

var _world: WorldData


func before() -> void:
	_world = WorldTestSupport.coarse(WorldTestSupport.control())


static func _parcel(pid: int, cx: float, cz: float, half: float) -> WorldParcel:
	var p := WorldParcel.new()
	p.id = pid
	p.outline = PackedVector2Array([Vector2(cx - half, cz - half), Vector2(cx + half, cz - half),
			Vector2(cx + half, cz + half), Vector2(cx - half, cz + half)])
	p.centroid = Vector2(cx, cz)
	p.area = (2.0 * half) * (2.0 * half)
	return p


func _ring() -> ParcelSelectionRing:
	var ring: ParcelSelectionRing = auto_free(ParcelSelectionRing.new())
	add_child(ring)
	ring.bind(null, func(_x: float, _z: float) -> float: return GROUND_Y)
	return ring


func _rig() -> CameraRig:
	var rig: CameraRig = auto_free(CameraRig.new())
	rig.input_profile = InputProfile.create(&"desktop")
	rig.viewport_size_override = VIEWPORT
	rig.smoothing_enabled = false
	add_child(rig)
	rig.set_world(_world, func(x: float, z: float) -> float: return maxf(_world.height_at(x, z), _world.sea_level))
	rig.apply_preset("district:D4")
	return rig


func test_select_creates_node_and_clear_removes_it() -> void:
	var ring := _ring()
	assert_bool(ring.has_mark()).is_false()
	assert_int(ring.get_child_count()).is_equal(0)
	ring.set_band(&"street")
	ring.select(_parcel(7, 100.0, 100.0, 15.0))
	assert_bool(ring.has_mark()).is_true()
	assert_int(ring.parcel_id()).is_equal(7)
	assert_int(ring.get_child_count()).is_equal(1)
	ring.clear()
	assert_bool(ring.has_mark()).is_false()
	assert_int(ring.get_child_count()).is_equal(0)
	assert_int(ring.parcel_id()).is_equal(-1)


func test_selecting_another_parcel_replaces_the_mark() -> void:
	var ring := _ring()
	ring.set_band(&"street")
	ring.select(_parcel(1, 100.0, 100.0, 15.0))
	ring.select(_parcel(2, 500.0, 500.0, 15.0))
	assert_int(ring.get_child_count()).is_equal(1)
	assert_int(ring.parcel_id()).is_equal(2)
	var aabb := ring.mark_node().mesh.get_aabb()
	assert_float(aabb.get_center().x).is_between(480.0, 520.0)


func test_missing_parcel_is_harmless() -> void:
	var ring := _ring()
	ring.select(null)
	assert_bool(ring.has_mark()).is_false()
	ring.select(_parcel(3, 0.0, 0.0, 10.0))
	ring.select(null)  # olmayan kimlik oyuncu yolunda null olur
	assert_bool(ring.has_mark()).is_false()
	assert_int(ring.get_child_count()).is_equal(0)
	var degenerate := WorldParcel.new()
	degenerate.id = 9
	ring.select(degenerate)  # çokgensiz parsel
	assert_bool(ring.has_mark()).is_false()


func test_geometry_surrounds_parcel_and_sits_on_ground() -> void:
	var ring := _ring()
	ring.set_band(&"street")
	ring.select(_parcel(5, 200.0, 300.0, 15.0))
	var mesh := ring.mark_node().mesh as ArrayMesh
	assert_int(mesh.get_surface_count()).is_equal(1)  # tek yüzey = en çok 1 çizim çağrısı
	var verts: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var half := ring.width_m() * 0.5
	var minx := INF
	var maxx := -INF
	var minz := INF
	var maxz := -INF
	for v in verts:
		minx = minf(minx, v.x)
		maxx = maxf(maxx, v.x)
		minz = minf(minz, v.z)
		maxz = maxf(maxz, v.z)
		assert_float(v.y).is_between(GROUND_Y, GROUND_Y + 1.0)
	# Şerit sınırın iki yanına yayılır: parselin dış kutusunu ~yarım kalınlık kadar aşar, içe de girer.
	assert_float(minx).is_equal_approx(185.0 - half * 1.0, half * 0.6)
	assert_float(maxx).is_equal_approx(215.0 + half * 1.0, half * 0.6)
	assert_float(minz).is_equal_approx(285.0 - half * 1.0, half * 0.6)
	assert_float(maxz).is_equal_approx(315.0 + half * 1.0, half * 0.6)
	var inner := verts.size() / 2
	assert_int(inner).is_greater(8)


func test_plan_street_is_thin_far_bands_scale_with_distance() -> void:
	var near := ParcelSelectionRing.plan(&"street", 0.08, 25.0)
	assert_bool(near["marker"]).is_false()
	assert_float(near["width_m"]).is_equal_approx(ParcelSelectionRing.MIN_WIDTH_M, 0.001)  # dünya tabanı
	var mid := ParcelSelectionRing.plan(&"neighborhood", 1.0, 400.0)
	var far := ParcelSelectionRing.plan(&"district", 4.0, 400.0)
	assert_float(mid["width_m"] / 1.0).is_greater_equal(2.0)  # en az ~2 px etkisi
	assert_float(far["width_m"] / 4.0).is_greater_equal(2.0)
	assert_float(far["width_m"]).is_greater(mid["width_m"])  # uzaklıkla ölçeklenir
	# Kalınlık parsele orantılı üst sınırı aşmaz.
	var capped := ParcelSelectionRing.plan(&"district", 4.0, 58.0)  # parsel 14,5 px: 3 px çizgi sınırı aşar
	assert_bool(capped["marker"]).is_false()
	assert_float(capped["width_m"]).is_equal_approx(ParcelSelectionRing.MAX_WIDTH_FRACTION * 58.0, 0.0001)


func test_plan_small_parcel_becomes_marker_and_metro_is_hidden() -> void:
	var tiny := ParcelSelectionRing.plan(&"district", 5.0, 25.0)  # parsel 5 px
	assert_bool(tiny["marker"]).is_true()
	assert_float(tiny["radius_m"]).is_equal_approx(ParcelSelectionRing.MARKER_RADIUS_PX * 5.0, 0.001)
	assert_bool(ParcelSelectionRing.plan(&"metro", 20.0, 25.0)["visible"]).is_false()
	# Yarıçap >= çizgi kalınlığı: halka dolu disk olmaz.
	assert_float(tiny["radius_m"]).is_greater(tiny["width_m"])


func test_band_change_updates_width_and_metro_hides_mark() -> void:
	var rig := _rig()
	var ring := _ring()
	ring.bind(rig, func(_x: float, _z: float) -> float: return GROUND_Y)
	var c := rig.focus_xz()
	var parcel := _parcel(11, c.x, c.y, 15.0)
	var st := rig.target_state()
	st.distance = 120.0
	rig.apply_state(st, true)
	ring.set_band(&"street")
	ring.select(parcel)
	var street_w := ring.width_m()
	assert_bool(ring.has_mark()).is_true()
	st = rig.target_state()
	st.distance = 1100.0
	rig.apply_state(st, true)
	ring.set_band(&"neighborhood")
	var hood_w := ring.width_m()
	assert_float(hood_w).is_greater(street_w)
	assert_float(street_w).is_less(1.0)  # sokakta ince çizgi
	ring.set_band(&"metro")
	assert_bool(ring.has_mark()).is_false()
	ring.set_band(&"street")
	assert_bool(ring.has_mark()).is_true()  # seçim bantla birlikte kaybolmadı
	ring.clear()
	assert_int(ring.get_child_count()).is_equal(0)


func test_uses_existing_focus_token_color() -> void:
	var ring := _ring()
	assert_bool(ring.color.is_equal_approx(UiTokens.load_default().color("focus"))).is_true()


func test_district_marker_is_at_least_60_px_across_and_has_a_dark_halo_surface() -> void:
	var tiny := ParcelSelectionRing.plan(&"district", 5.0, 25.0)
	assert_bool(tiny["marker"]).is_true()
	assert_float(tiny["radius_m"] / 5.0 * 2.0).is_greater_equal(60.0)   # dış çap (px) >= 60
	assert_float(tiny["halo_m"]).is_greater(0.0)
	# açık halka koyu halenin ÜSTÜNDE ve halenin içinde kalır: hale halkadan geniş
	assert_float(tiny["width_m"] + 2.0 * tiny["halo_m"]).is_greater(tiny["width_m"])
	# koyu hale rengi token'dan ve odak renginden farklı
	var ring := ParcelSelectionRing.new()
	auto_free(ring)
	assert_bool(ring.halo_color.is_equal_approx(ring.color)).is_false()
	assert_float(ring.halo_color.get_luminance()).is_less(ring.color.get_luminance())
