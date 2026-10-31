class_name LifeHost
extends Node
## Yaşam belirtisinin sahneye bağlayıcısı (T-050). `scenes/game/playable.tscn` içinde `Playable` düğümünün ÇOCUĞUDUR;
## sahne kökündeki `playable.gd` değişmez (dosya satır sınırı). Ana oyunun nesnelerini (`_facade`, `_net`,
## `_t0_columns`,
## `_view_root`, `_camera`, `_terrain`, `_world`, `_args`) `Object.get` ile OKUR (PlayableRoads ile aynı yöntem); hepsi
## hazır olunca `LifeView` kurar. Sim'e yalnız okuma sorgularıyla bağlıdır (`LifeSimReader`); hiçbir komut göndermez.
##
## Dev argümanları (oynanışı ve sim'i değiştirmez):
##   --no-life            yaşam görünümü kapalı (perf A/B).
##   --life-force         başsız çalışmada da kur (varsayılan: başsızda atlanır; görüntü yok).
##   --life-density=X     profil yoğunluk çarpanı (0..4).    --life-profile=touch  dokunmatik profil değerleri.
##   --life-time=S        yaşam saatini S saniyede SABİTLER (yakalamada tekrarlanabilir kare).
##   --life-settle        menzildeki tüm hücreleri kurulum anında kurar (yakalama; kare başı tavanı beklemez).

var view: LifeView = null
var activity: LifeEdgeActivity = null
var reader: LifeSimReader = null
var config: LifeConfig = null
var stats: Dictionary = {"state": "waiting"}

var _host: Object = null
var _facade: SimFacade = null
var _net: WorldNetwork = null
var _camera: CameraRig = null
var _tick_seen: int = -999999
var _graph_seen: int = -1
var _graph_pending: bool = false
var _args: Dictionary = {}
var _init_per_frame: int = 5000
var _settled: bool = false


func _ready() -> void:
	_host = get_parent()
	set_process(true)


func _process(_delta: float) -> void:
	if view == null:
		if stats["state"] == "waiting":
			_try_start()
		return
	_tick()


func _arg(name: String) -> Variant:
	return _args.get(name)


func _try_start() -> void:
	if _host == null:
		return
	var args: Variant = _host.get(&"_args")
	if args == null:
		return
	_args = args
	if _args.has("no-life"):
		_stop("disabled (--no-life)")
		return
	if DisplayServer.get_name() == "headless" and not _args.has("life-force"):
		_stop("skipped (headless)")
		return
	_facade = _host.get(&"_facade")
	_net = _host.get(&"_net")
	_camera = _host.get(&"_camera")
	var view_root: Node3D = _host.get(&"_view_root")
	var terrain: TerrainView = _host.get(&"_terrain")
	var cols: BuildingColumns = _host.get(&"_t0_columns")
	var world: WorldData = _host.get(&"_world")
	if _facade == null or _net == null or _camera == null or view_root == null or terrain == null or cols == null \
			or world == null:
		return  # ana sahne henüz hazır değil (ilk kare); sonraki karede tekrar
	_start(view_root, terrain, cols, world)


func _stop(state: String) -> void:
	stats["state"] = state
	set_process(false)


func _start(view_root: Node3D, terrain: TerrainView, cols: BuildingColumns, world: WorldData) -> void:
	var t0 := Time.get_ticks_usec()
	var profile := LifeConfig.profile_for(PlatformProfile.current().input_profile)
	if _args.has("life-profile"):
		profile = StringName(str(_args["life-profile"]))
	config = LifeConfig.load_default(profile)
	if not config.valid():
		push_error("life: ayar geçersiz: %s" % "; ".join(config.errors))
		_stop("invalid config")
		return
	if _args.has("life-density"):
		config.data["profiles"][String(profile)]["density"] = clampf(float(str(_args["life-density"])), 0.0, 4.0)
	var assets := LifeAssets.load_default()
	if not assets.ok():
		push_error("life: varlıklar yüklenemedi: %s" % "; ".join(assets.errors))
		_stop("assets failed")
		return
	activity = LifeEdgeActivity.create(_net, config)
	reader = LifeSimReader.create(_facade, activity, _net, PlayableStock.from_columns(cols))
	_init_per_frame = int(config.update_value("init_parcels_per_frame"))
	view = LifeView.new()
	view.name = "Life"
	view_root.add_child(view)
	view.setup(config, assets, activity, world.world_seed, terrain.surface_height_at)
	view.prepare_cell = reader.prepare_cell
	_graph_seen = _net.graph_version
	_tick_seen = _facade.current_tick()
	if _args.has("life-time"):
		view.set_time_fixed(float(str(_args["life-time"])))
		view.set_running(false)
	stats = view.stats
	stats["state"] = "running"
	stats["setup_ms"] = snappedf((Time.get_ticks_usec() - t0) / 1000.0, 0.1)
	stats["profile"] = String(profile)
	stats["asset_ids"] = assets.loaded_ids
	stats["unapproved_ids"] = assets.gate.unapproved_ids.size()
	var build_stats: Variant = _host.get(&"build_stats")
	if build_stats is Dictionary:
		(build_stats as Dictionary)["life"] = stats
	print("LIFE ", JSON.stringify({"setup_ms": stats["setup_ms"], "profile": stats["profile"],
			"edges": activity.stats["edges_eligible"], "ids": assets.loaded_ids, "unapproved": stats["unapproved_ids"]}))


func _tick() -> void:
	var tick := _facade.current_tick()
	var ticked := tick != _tick_seen
	_tick_seen = tick
	# Yol ağı değiştiyse (oyuncu yolu / geri alma): yol görünümü işi bitince kenar dizini ve toplamlar yeniden kurulur.
	if _net.graph_version != _graph_seen:
		_graph_pending = true
	if _graph_pending and not _roads_busy():
		_graph_pending = false
		_graph_seen = _net.graph_version
		activity.index_edges()
		activity.begin_rebuild()
		view.mark_data_changed()
	if activity.is_rebuilding():
		activity.step_rebuild(_init_per_frame)
	reader.poll(ticked)
	if reader.occupancy_changed:
		reader.occupancy_changed = false
		view.mark_data_changed()
	view.set_running(_facade.speed() > 0 and not _args.has("life-time"))
	var cam := _camera.camera.global_position
	view.track_camera(cam, Vector2(cam.x + _camera.rebase_origin.x, cam.z + _camera.rebase_origin.y))
	if _args.has("life-settle") and not _settled and not activity.is_rebuilding():
		_settled = true
		view.settle()
	stats["pending_parcels"] = reader.pending_parcels()
	stats["feed_ids"] = reader.stats["feed_ids"]
	stats["views_read"] = reader.stats["views_read"]
	stats["occupancy_updates"] = reader.stats["occupancy_updates"]


func _roads_busy() -> bool:
	var pr: Variant = _host.get(&"_pr")
	return pr != null and pr.has_method("world_busy") and bool(pr.call("world_busy"))
