extends GdUnitTestSuite
## T-041 ölçüt 1/3/5 (akış) · Gerçek viewport yayılımıyla (`Viewport.push_input`) dünyada tıklama -> parsel seçimi ->
## denetçi paneli; kamera uzaklığı gerçek `scale_band_changed` sinyaliyle bandı değiştirir, AYNI seçim AYNI veriyi
## sadeleşmiş sunumla gösterir. Kamera + HUD katmanı düğüm sırası ve paylaşılan InputProfile playable.gd ile aynıdır;
## seçim yapıştırıcısı (ekran -> zemin -> `parcel_id_at` -> `InspectorHost`) playable `_on_select_requested` ile aynı üç
## çağrıdır. Gerçek facade: PoliticsBootstrap (m2_render_support). Sentetik olaylar gerçek fare/dokunma DEĞİLDİR.

const VIEWPORT := Vector2(1600.0, 900.0)
const CENTER := Vector2(800.0, 450.0)

var _selected_ids: Array[int] = []


func before_test() -> void:
	InspectorHost.default_interval_msec = 0
	UiText.reset()
	UiText.report_missing = false
	_selected_ids = []


func after_test() -> void:
	UiText.reset()


func _scene() -> Dictionary:
	var fx := M2RenderSupport.fixture()
	# Kamera dünyası: fixture ağıyla AYNI koordinatlar, ama ilçe bandına erişecek kadar geniş (3 km'lik fixture
	# dünyasında zarf uzaklığı 1,5 km'de keser). Parseller/sim fixture'dandır.
	var world := NetworkTestSupport.flat_world(60000.0, 1000.0)
	world.origin = Vector2(-30000.0, -30000.0)
	var net: WorldNetwork = fx["net"]
	var h := M2RenderSupport.handle(M2RenderSupport.ISOLATE)
	var f := h.facade
	var ids := M2RenderSupport.free_parcels(M2RenderSupport.projector(f), 6, true)
	f.advance(2)
	assert_bool(f.submit_command(SimCommand.zoning_propose(ids, &"zone.mixed")).is_rejected()).is_false()
	var rig: CameraRig = auto_free(CameraRig.new())
	rig.input_profile = InputProfile.create(&"desktop")
	rig.viewport_size_override = VIEWPORT
	rig.smoothing_enabled = false
	add_child(rig)
	# Sentetik dünya 3 km: oyundaki kenar payı (K1) odağı ortaya iterdi; test payı küçültür (yalnız bu test).
	rig.envelope.edge_margin_m = 50.0
	rig.set_world(world, func(x: float, z: float) -> float: return maxf(world.height_at(x, z), world.sea_level))
	var layer: CanvasLayer = auto_free(CanvasLayer.new())
	add_child(layer)
	var hud := HudRoot.new()
	hud.set_anchors_preset(Control.PRESET_TOP_LEFT)
	layer.add_child(hud)
	hud.bind_input(rig.input_profile)
	hud.setup(f, UiTestSupport.platform(&"desktop"))
	hud.size = VIEWPORT
	hud.refresh()
	var host := InspectorHost.attach(hud, f)
	host.set_band(rig.scale_band)
	rig.scale_band_changed.connect(host.set_band)
	rig.input_profile.select_requested.connect(func(p: Vector2) -> void:
		var g := rig.screen_to_ground(p)
		if not bool(g.get("ok", false)):
			return
		var pid := net.parcel_id_at(float(g["x"]), float(g["z"]))
		_selected_ids.append(pid)
		host.select_parcel(pid))
	return {"rig": rig, "hud": hud, "host": host, "facade": f, "net": net, "ids": ids}


func _focus(scene: Dictionary, x: float, z: float, distance: float) -> void:
	var rig: CameraRig = scene["rig"]
	var s := rig.target_state()
	s.focus_x = x
	s.focus_z = z
	s.distance = distance
	rig.apply_state(s, true)
	rig._process(0.016)


func _band_distance(rig: CameraRig, band: StringName) -> float:
	for b in rig.envelope.bands:
		if b["name"] == band:
			return float(b["min_m"]) + (float(b["max_m"]) - float(b["min_m"])) * 0.15
	return -1.0


func _click(pos: Vector2) -> void:
	for pressed in [true, false]:
		var e := InputEventMouseButton.new()
		e.button_index = MOUSE_BUTTON_LEFT
		e.pressed = pressed
		e.position = pos
		e.global_position = pos
		get_viewport().push_input(e)


func test_click_on_a_parcel_opens_the_inspector_and_bands_keep_the_same_data() -> void:
	var scene := _scene()
	var rig: CameraRig = scene["rig"]
	var host: InspectorHost = scene["host"]
	var f: SimFacade = scene["facade"]
	var net: WorldNetwork = scene["net"]
	var pid := int((scene["ids"] as PackedInt64Array)[0])
	var wp: WorldParcel = net.parcels[pid]
	# inşaat sürerken (karar + ilerleme görünür olsun)
	for i in 220:
		if f.parcel_views(PackedInt64Array([pid]))[0].development == ParcelView.DEVELOPMENT_UNDER_CONSTRUCTION:
			break
		f.advance(1)
	(scene["hud"] as HudRoot).refresh()
	var v: ParcelView = f.parcel_views(PackedInt64Array([pid]))[0]
	assert_str(String(v.development)).is_equal("under_construction")
	var approved := UiText.t(&"m2.investor.approved", {"date": UiText.tick_date(v.decision_tick)})
	var stage := UiText.t(M2ResultModel.stage_key(v.development))
	var captions := {}
	# Oyuncu sokakta tıklar, sonra uzaklaşır: seçim korunur, yalnız sunum sadeleşir.
	_focus(scene, wp.centroid.x, wp.centroid.y, _band_distance(rig, &"street"))
	_click(CENTER)
	assert_array(_selected_ids.slice(-1)).override_failure_message("tıklama parseli seçmedi").is_equal([pid])
	for band: StringName in [&"street", &"neighborhood", &"district"]:
		_focus(scene, wp.centroid.x, wp.centroid.y, _band_distance(rig, band))
		assert_str(String(rig.scale_band)).override_failure_message("kamera bandı d=%s" % rig.distance()) \
				.is_equal(String(band))
		var panel := host.panel()
		assert_object(panel).override_failure_message("denetçi açılmadı (%s)" % band).is_not_null()
		assert_int(panel.model.parcel_id).is_equal(pid)
		var text := panel.joined_text()
		assert_str(text).contains(approved)
		assert_str(text).contains(stage)
		assert_str(text).contains(UiText.humanize(String(v.ref())))
		captions[band] = text.contains(UiText.t(&"inspector.land_value"))
	# sadeleştirme: arsa değeri satırı yalnız sokakta
	assert_bool(captions[&"street"]).is_true()
	assert_bool(captions[&"neighborhood"]).is_false()
	assert_bool(captions[&"district"]).is_false()
	assert_array(Array(UiText.missing_keys())).is_empty()


func test_band_change_alone_re_renders_the_open_inspector_without_a_new_click() -> void:
	var scene := _scene()
	var rig: CameraRig = scene["rig"]
	var host: InspectorHost = scene["host"]
	var wp: WorldParcel = (scene["net"] as WorldNetwork).parcels[int((scene["ids"] as PackedInt64Array)[0])]
	_focus(scene, wp.centroid.x, wp.centroid.y, _band_distance(rig, &"street"))
	_click(CENTER)
	assert_int(host.panel().model.detail).is_equal(InspectorModel.Detail.PARCEL)
	_focus(scene, wp.centroid.x, wp.centroid.y, _band_distance(rig, &"district"))
	assert_int(host.panel().model.detail).is_equal(InspectorModel.Detail.REGION)
	assert_str(host.panel().joined_text()).contains(UiText.t(&"inspector.zoom_hint"))


func test_clicking_empty_ground_shows_the_empty_state_and_the_hud_keeps_working() -> void:
	var scene := _scene()
	var rig: CameraRig = scene["rig"]
	var host: InspectorHost = scene["host"]
	var f: SimFacade = scene["facade"]
	var wp: WorldParcel = (scene["net"] as WorldNetwork).parcels[int((scene["ids"] as PackedInt64Array)[0])]
	_focus(scene, wp.centroid.x, wp.centroid.y, _band_distance(rig, &"street"))
	_click(CENTER)
	assert_bool(host.is_open()).is_true()
	# dünya köşesi: hiçbir parsel yok
	_focus(scene, 150.0, 150.0, _band_distance(rig, &"street"))
	_click(CENTER)
	assert_int(_selected_ids[-1]).is_less_equal(0)
	assert_str(host.panel().joined_text()).contains(UiText.t(&"inspector.empty_hint"))
	# panel açıkken kamera tuşu ve duraklat çalışır
	var before := rig.current_state().focus_xz()
	var key := InputEventKey.new()
	key.physical_keycode = KEY_W
	key.keycode = KEY_W
	key.pressed = true
	get_viewport().push_input(key)
	for i in 5:
		rig._process(0.1)
	key.pressed = false
	get_viewport().push_input(key)
	assert_float(rig.current_state().focus_xz().distance_to(before)).is_greater(1.0)
	var speed := f.speed()
	var space := InputEventKey.new()
	space.physical_keycode = KEY_SPACE
	space.keycode = KEY_SPACE
	space.pressed = true
	get_viewport().push_input(space)
	assert_int(f.speed()).is_not_equal(speed)
