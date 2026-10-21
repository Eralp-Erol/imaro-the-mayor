extends "res://scenes/dev/world_preview.gd"
## Entegre geliştirme oynanabilir — T-030'un ASGARİ dilimi (2026-10-20, kullanım limiti nedeniyle ana oturumda).
## Commit'li modülleri tek sahnede birleştirir: arazi + gerçek T0 yerleşimi + CameraRig (world_preview),
## gerçek SimFacadeImpl (ekonomi çekirdeği) + HudRoot (gerçek facade verisi). Sahte başarı yok;
## eksikler HUD üstündeki notta.
## T0 sütunları başlangıç stoğu olarak gerçek ekonomi durumuna aktarılır: bu bir karar kaydı değildir. Dünya
## tıklaması parseli imar akışına verir. Sim'in yeni gelişme geometrisi henüz BuildingView'a çevrilmez; bu durum
## yüzeyde açıkça belirtilir, sahte yapı gösterilmez.

const SETTLEMENT_PATH := "res://data/world/ismeral/settlement.json"
const NETWORK_PATH := "res://data/world/ismeral/network.json"
const DEMO_LAND_USE := &"zone.commercial"
const NOTE := "WASD/oklar: kaydır | Q/E: döndür | tekerlek/trackpad: yakınlaş | Boşluk: duraklat/sürdür\n" \
		+ "Tıklama: parseli seç (imar akışı) | Z: seçili/odaktaki parsele imar önerisi\n" \
		+ "T0 stok sim'e aktarıldı. Yeni sim gelişimi henüz BuildingView geometrisine bağlı değil; " \
		+ "HUD/parsel verisinden izlenir."

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
var _t0_columns: BuildingColumns = null
var _decisions: DecisionPanels = null
var _selected_parcel_id: int = -1
var _acc_ms: float = 0.0
var _acc_n: int = 0
var _max_ms: float = 0.0
var _smoke_save_load_checked: bool = false


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
	_t0_columns = cols
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
	var stock := _stock_from_columns(_t0_columns)
	if stock == null or not stock.is_valid():
		push_error("playable: T0 stok adaptörü geçersiz")
		return
	# Integrated playable must use the same Economy + Actors + Politics facade
	# exposed to the HUD; EconomyBootstrap would silently omit the latter two.
	var handle := PoliticsBootstrap.create(_world.world_seed, source, null, stock)
	if handle == null:
		push_error("playable: ekonomi/aktör/siyaset çekirdeği kurulamadı")
		return
	_facade = handle.facade
	_facade.set_speed(3 if _demo else 1)
	sim_stats["sim_parcels"] = source.parcel_count()
	sim_stats["t0_stock_parcels"] = stock.parcel_ids().size()


## `BuildingColumns` her satırını değil, parsel başına başlangıç kullanım/birim toplamını verir. Bu başlangıç
## durumu olduğundan ReasonLog'a karar yazılmaz; yeni yapılar hâlâ EconomySystem yatırımcı kararından doğar.
func _stock_from_columns(cols: BuildingColumns) -> ListStockSource:
	if cols == null:
		return ListStockSource.create([])
	var grouped := {}
	for i in cols.count:
		var pid := int(cols.parcel_id[i])
		var commercial := (int(cols.flags[i]) & (BuildingColumns.FLAG_GROUND_SHOP | BuildingColumns.FLAG_INDUSTRY)) != 0
		var use: StringName = &"commercial" if commercial else &"residential"
		if not grouped.has(pid):
			grouped[pid] = {"residential": 0, "commercial": 0}
		var units := maxi(1, int(cols.floors[i]))
		(grouped[pid] as Dictionary)[String(use)] += units
	var entries: Array = []
	for pid in grouped.keys():
		var uses: Dictionary = grouped[pid]
		# Tek ekonomi parseli tek kullanım taşır; karma parsellerde zemin dükkânı baskınsa ticaret seçilir.
		var use: StringName = &"commercial" if int(uses["commercial"]) > int(uses["residential"]) else &"residential"
		entries.append({"parcel_id": int(pid), "use": use, "units": int(uses[String(use)]), "owner": 0})
	return ListStockSource.create(entries)


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
	# Girdi yönlendirme sözleşmesi (HudRoot üst notu): sahnede TEK InputProfile, olayı/kareyi CameraRig sürer.
	# HUD o örneğe yalnız duraklat/hız/iptal fiillerini bağlar; seçim fiili de aynı örnekten gelir.
	var shared_input := _camera.input_profile
	assert(shared_input != null, "playable: CameraRig girdi profili yok")
	_hud.bind_input(shared_input)
	_hud.setup(_facade, PlatformProfile.current())
	_decisions = DecisionPanels.attach(_hud, _facade)
	shared_input.select_requested.connect(_on_select_requested)
	_status = Label.new()
	# Sol altta, araç çubuğunun üstünde: sağdaki yan panel ve soldaki bildirim şeridiyle çakışmaz.
	_status.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_status.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_status.offset_left = 12.0
	_status.offset_bottom = -96.0
	_status.custom_minimum_size = Vector2(380, 0)
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
	# Başsız T-030 smoke, gerçek facade üzerinde kayıt baytını tekrar içe alıp
	# kanonik hash'in korunduğunu denetler. Bu yalnız --demo ile çalışan bir
	# doğrulama kancasıdır; normal oturumda kayıt durumu veya dosya üretmez.
	if _demo and not _smoke_save_load_checked and _frames >= 60:
		_smoke_save_load_checked = true
		_smoke_save_load()
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
	# Otomatik smoke yalnız kendi Godot sürecini sonlandırabilsin diye sınır açık bir komut satırı
	# seçeneğidir. Normal oynanışta bu anahtar yoktur; sim veya dünya durumuna girmez.
	if _args.has("quit-after") and _frames >= maxi(1, int(str(_args["quit-after"]))):
		print("PLAYABLE_QUIT frames=%d tick=%d" % [_frames, _facade.current_tick()])
		get_tree().quit()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and _facade != null:
		var key := (event as InputEventKey).keycode
		if key == KEY_Z:
			_submit_demo()
			return
	# Boşluk/duraklat InputProfile -> HudRoot fiilidir (tek yönlendirme); burada ikinci bir yol YOK.
	super._unhandled_input(event)


func _on_select_requested(screen_pos: Vector2) -> void:
	if _camera == null or _net == null or _decisions == null:
		return
	var ground := _camera.screen_to_ground(screen_pos)
	if not bool(ground.get("ok", false)):
		return
	var pid := _net.parcel_id_at(float(ground["x"]), float(ground["z"]))
	if pid <= 0:
		_selected_parcel_id = -1
		return
	_selected_parcel_id = pid
	_decisions.open_zoning(PackedInt64Array([pid]))
	print("PLAYABLE_SELECT parcel=%d" % pid)


func _submit_demo() -> void:
	var pid := _selected_parcel_id
	var focus := _camera.current_state()
	if pid <= 0:
		pid = _net.parcel_id_at(focus.focus_x, focus.focus_z)
	if pid <= 0:
		pid = _nearest_parcel(Vector2(focus.focus_x, focus.focus_z))
	if pid <= 0:
		_last_action = "parsel bulunamadı"
		print("PLAYABLE_ACTION ", _last_action)
		return
	var res := _facade.submit_command(SimCommand.zoning_propose(PackedInt64Array([pid]), DEMO_LAND_USE))
	_last_action = "parsel %d → %s: %s" % [pid, String(DEMO_LAND_USE), str(res.get("status"))]
	print("PLAYABLE_ACTION ", _last_action)


func _smoke_save_load() -> void:
	var impl := _facade as SimFacadeImpl
	if impl == null:
		push_error("playable: smoke save/load gerçek SimFacadeImpl gerektirir")
		print("PLAYABLE_SAVE_LOAD FAIL facade")
		return
	var before := impl.state_hash()
	var bytes := impl.export_save()
	var loaded := impl.import_save(bytes)
	var after := impl.state_hash()
	if loaded.ok and not before.is_empty() and before == after:
		print("PLAYABLE_SAVE_LOAD OK tick=%d bytes=%d hash=%s" % [impl.current_tick(), bytes.size(), before])
	else:
		push_error("playable: smoke save/load hash eşitliği sağlanamadı: %s" % loaded.message)
		print("PLAYABLE_SAVE_LOAD FAIL ok=%s before=%s after=%s" % [loaded.ok, before, after])


func _nearest_parcel(at: Vector2) -> int:
	var best := -1
	var best_d := INF
	for v in _views:
		var d := v.center.distance_squared_to(at)
		if d < best_d:
			best_d = d
			best = v.id
	return best
