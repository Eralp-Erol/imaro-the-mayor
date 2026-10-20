extends "res://scenes/dev/world_preview.gd"
## Entegre geliştirme oynanabilir — T-030'un ASGARİ dilimi (2026-10-20, kullanım limiti nedeniyle ana oturumda).
## Commit'li modülleri tek sahnede birleştirir: arazi + gerçek T0 yerleşimi + CameraRig (world_preview),
## gerçek SimFacadeImpl (ekonomi çekirdeği) + HudRoot (gerçek facade verisi). Sahte başarı yok; eksikler HUD üstündeki notta.
## Kısıtlar: T0 yapıları sim durumuna İÇE AKTARILMADI (ExistingStockSource adaptörü yok), imar akışı paneli
## dünyadan parsel seçimine bağlı değil; eylem klavyeyle (Z). Bütçe/meclis/siyaset sim'de kurulu değil.

const SETTLEMENT_PATH := "res://data/world/ismeral/settlement.json"
const NETWORK_PATH := "res://data/world/ismeral/network.json"
const DEMO_LAND_USE := &"zone.commercial"
const NOTE := "Z: odaktaki parsele imar önerisi (zone.commercial) | boşluk: duraklat/sürdür\n" \
		+ "Entegrasyon notu: T0 yapıları render'da; sim parselleri BOŞ başlar (T0 stoku sim'e aktarılmadı). " \
		+ "Bütçe/meclis/siyaset: henüz kurulmadı."

var sim_stats: Dictionary = {}

var _net: WorldNetwork
var _facade: SimFacade
var _hud: HudRoot
var _seen_tick: int = -1
var _frames: int = 0
var _demo: bool = false
var _last_action: String = "-"
var _status: Label
var _views: Array[ParcelView] = []
var _acc_ms: float = 0.0
var _acc_n: int = 0
var _max_ms: float = 0.0


func _ready() -> void:
	super._ready()
	_demo = _args.has("demo")
	if _net == null:
		push_error("playable: ağ kurulamadı, sim bağlanmadı")
		return
	var t0 := Time.get_ticks_usec()
	_start_sim()
	_start_hud()
	sim_stats["sim_setup_ms"] = snappedf((Time.get_ticks_usec() - t0) / 1000.0, 0.1)
	print("PLAYABLE ", JSON.stringify(sim_stats))


func _build_buildings(_control: Dictionary, world_seed: int) -> Dictionary:
	var t0 := Time.get_ticks_usec()
	var net_control: Variant = JSON.parse_string(FileAccess.get_file_as_string(NETWORK_PATH))
	var rules: Variant = JSON.parse_string(FileAccess.get_file_as_string(SETTLEMENT_PATH))
	if not (net_control is Dictionary and rules is Dictionary):
		push_error("playable: network/settlement verisi okunamadı")
		return {}
	_net = NetworkGenerator.generate(_world, net_control, world_seed)
	var t1 := Time.get_ticks_usec()
	var lib := KitLibrary.load_manifest()
	var cols: BuildingColumns = T0Settlement.generate(_world, _net, lib.manifest, world_seed, rules)
	var t2 := Time.get_ticks_usec()
	var config := BuildingViewConfig.new()
	config.cast_shadows = _shadows_wanted
	_buildings = BuildingView.new()
	_buildings.name = "Buildings"
	_view_root.add_child(_buildings)
	_buildings.setup(_world, BuildingKit.from_library(lib), config)
	var report := _buildings.set_columns(cols, _net.graph_version)
	if not report.get("ok", false):
		push_error("playable: yapı sütunları reddedildi: %s" % str(report.get("errors")))
	var stats := _buildings.stats.duplicate()
	stats["network_ms"] = snappedf((t1 - t0) / 1000.0, 0.1)
	stats["settlement_ms"] = snappedf((t2 - t1) / 1000.0, 0.1)
	stats["view_ms"] = snappedf((Time.get_ticks_usec() - t2) / 1000.0, 0.1)
	stats["parcels"] = _net.parcels.size()
	stats["buildings"] = cols.count
	return stats


func _start_sim() -> void:
	_views = _parcel_views()
	var source := ListParcelSource.create(&"ismeral", _views)
	if source == null or not source.is_valid():
		push_error("playable: parsel kaynağı geçersiz")
		return
	var handle := EconomyBootstrap.create(_world.world_seed, source)
	if handle == null:
		push_error("playable: ekonomi çekirdeği kurulamadı")
		return
	_facade = handle.facade
	_facade.set_speed(3 if _demo else 1)
	sim_stats["sim_parcels"] = source.parcel_count()


func _parcel_views() -> Array[ParcelView]:
	var out: Array[ParcelView] = []
	var src: Variant = _net.parcels
	var items: Array = src.values() if src is Dictionary else Array(src)
	for item in items:
		var wp := item as WorldParcel
		if wp == null or wp.region_code == &"":
			continue
		var v := ParcelView.new()
		v.id = wp.id
		v.region_code = wp.region_code
		v.center = wp.centroid
		v.area_m2 = int(wp.area)
		v.zone = &"zone.residential"  # yer tutucu: T0 imar durumu sim'e aktarılmadı
		out.append(v)
	return out


func _start_hud() -> void:
	if _facade == null:
		return
	var layer := CanvasLayer.new()
	layer.name = "HudLayer"
	add_child(layer)
	_hud = HudRoot.new()
	_hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(_hud)
	_hud.setup(_facade, PlatformProfile.current())
	_status = Label.new()
	_status.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_status.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_status.position = Vector2(-12, 60)
	_status.custom_minimum_size = Vector2(560, 0)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_status.add_theme_font_size_override("font_size", 13)
	layer.add_child(_status)


func _process(delta: float) -> void:
	super._process(delta)
	if _facade == null:
		return
	_frames += 1
	_acc_ms += delta * 1000.0
	_acc_n += 1
	_max_ms = maxf(_max_ms, delta * 1000.0)
	_facade.drive_usec(int(delta * 1000000.0))
	if _facade.current_tick() != _seen_tick:
		_seen_tick = _facade.current_tick()
		if _hud != null:
			_hud.poll()
	if _demo and _frames == 10:
		_submit_demo()
	if _status != null:
		_status.text = "%s\nsim: gün %d | olay %d | son eylem: %s" % [
				NOTE, _facade.current_tick(), _facade.last_event_seq(), _last_action]
	if _frames % 120 == 0:
		print("PLAYABLE_SMOKE tick=%d events=%d frames=%d avg_frame_ms=%.1f max_frame_ms=%.1f" % [
				_facade.current_tick(), _facade.last_event_seq(), _frames, _acc_ms / maxf(_acc_n, 1), _max_ms])
		_acc_ms = 0.0
		_acc_n = 0
		_max_ms = 0.0
	if _args.has("shot") and _frames == int(str(_args["shot"])):
		get_viewport().get_texture().get_image().save_png(str(_args.get("shot-path", "user://playable.png")))
		print("PLAYABLE_SHOT ", _args.get("shot-path", "user://playable.png"))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and _facade != null:
		var key := (event as InputEventKey).keycode
		if key == KEY_Z:
			_submit_demo()
			return
		if key == KEY_SPACE:
			_facade.set_speed(0 if _facade.speed() != 0 else 1)
			return
	super._unhandled_input(event)


func _submit_demo() -> void:
	var st := _camera.current_state()
	var pid := _net.parcel_id_at(st.focus_x, st.focus_z)
	if pid <= 0:
		pid = _nearest_parcel(Vector2(st.focus_x, st.focus_z))
	if pid <= 0:
		_last_action = "parsel bulunamadı"
		print("PLAYABLE_ACTION ", _last_action)
		return
	var res := _facade.submit_command(SimCommand.zoning_propose(PackedInt64Array([pid]), DEMO_LAND_USE))
	_last_action = "parsel %d → %s: %s" % [pid, String(DEMO_LAND_USE), str(res.get("status"))]
	print("PLAYABLE_ACTION ", _last_action)


func _nearest_parcel(at: Vector2) -> int:
	var best := -1
	var best_d := INF
	for v in _views:
		var d := v.center.distance_squared_to(at)
		if d < best_d:
			best_d = d
			best = v.id
	return best
