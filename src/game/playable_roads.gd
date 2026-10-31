class_name PlayableRoads
extends RefCounted
## Oynanabilir sahnenin yol (oyuncu yolu) bağlaması (T-042 adım 3): (1) facade'e yol komutlarını bağlar (ağ sahnenin
## kurduğu AYNI nesnedir; sim onu yalnız tick sınırında ve ana iş parçacığında değiştirir), (2) ağdaki delta değişimini
## `RoadEditSync` ile 3B'ye yansıtır (tick'li kareden SONRAKİ karede başlayan arka plan işi), (3) "Yol çiz" aracını
## (`RoadDrawController`) kurar. `world_busy()` yol komutu gönderimini `busy` ile reddettirir: bitki yerleşimi ya da yol
## görünümü işi arka thread'de ağı okurken ağ değişmez (veri yarışı yok).

const NETWORK_PATH := "res://data/world/ismeral/network.json"

var sync: RoadEditSync = null
var ctrl: RoadDrawController = null
## true: kullanıcı yolu bu tick'te değişti, görünüm işi bir sonraki karede başlar.
var due: bool = false
## T-042b: kamulaştırma takipçisi (alınan T0 parselleri görünümden süzülür, geri alınca döner); host verilmediyse null.
var follow: PlayableExpropriation = null

var _net: WorldNetwork = null
var _facade: SimFacade = null
var _other_busy: Callable = Callable()
var _cols: BuildingColumns = null
## Yol görünümü kurulduktan sonra bitki koridoru yenilemesi BİR KARE ertelenir (ayrı kare dilimi): 7-30 ms'lik koridor
## hesabı chunk kurulumuyla aynı kareye binmesin. 0 = bekleyen yok, 1 = bu karede bekle, 2 = sonraki karede yap.
var _corridor_wait: int = 0


## `other_busy`: dünya başka bir nedenle meşgul mü (bitki yerleşimi)? Yol komutları bağlanamazsa araç görünmez.
## `host`: playable (T0 sütunları `_t0_columns`, görünüm `_buildings`, `_t0_occupied`, `_terrain`, `_selection_ring`).
static func create(net: WorldNetwork, roads: RoadView, facade: SimFacade, other_busy: Callable,
		host: Object = null) -> PlayableRoads:
	var r := PlayableRoads.new()
	r._net = net
	r._facade = facade
	r._other_busy = other_busy
	if roads != null:
		r.sync = RoadEditSync.create(net, roads)
	if host != null and host.get(&"_t0_columns") != null and host.get(&"_buildings") != null:
		r._cols = host.get(&"_t0_columns")
		r.follow = PlayableExpropriation.create(net, r._cols, host.get(&"_buildings"), host.get(&"_t0_occupied"),
				host.get(&"_terrain"), func() -> Object: return host.get(&"_selection_ring"),
				func() -> Object: return host.get(&"_vegetation"))
	return r


## Yol komutlarını facade'e bağlar; sorun varsa false (araç kaydedilmez).
func attach_commands() -> bool:
	var impl := _facade as SimFacadeImpl
	if impl == null or _net == null:
		return false
	var rules := RoadDraftRules.load_path(NETWORK_PATH)
	var ctx := PublicWorksContext.create(_net, rules, PublicWorksConfig.load_default())
	if ctx == null:
		push_error("playable: yol komutları bağlanamadı; 'Yol çiz' aracı görünmeyecek")
		return false
	ctx.busy_probe = world_busy
	if _cols != null:
		PlayableExpropriation.attach_port(ctx, _net, rules, _cols)  # T-042b: köprü + korunan T0 parselleri
	if not impl.attach_public_works(ctx):
		push_error("playable: attach_public_works reddedildi; 'Yol çiz' aracı görünmeyecek")
		return false
	return true


func start_tool(hud: HudRoot, camera: CameraRig, view_root: Node3D, ground: Callable) -> void:
	if sync == null:
		return
	ctrl = RoadDrawController.attach(hud, camera, _net, _facade, view_root, ground, hud.get_parent() as CanvasLayer)


func world_busy() -> bool:
	return (_other_busy.is_valid() and bool(_other_busy.call())) or (sync != null and sync.world_busy())


## Tick'li kareden hemen sonra: ağ değiştiyse görünüm işi sonraki karede başlar.
func note_tick() -> void:
	if sync != null and sync.pending() and not sync.is_busy():
		due = true
	if ctrl != null:
		ctrl.process()


## Kare başı: bekleyen iş başlar, biten iş düğümlere kurulur. Rapor (boş = bir şey olmadı).
func pump() -> Dictionary:
	if follow != null:
		follow.poll()
	if sync == null:
		return {}
	if due and not sync.is_busy():
		due = false
		sync.begin_async()
	return sync.poll()


## Bitki koridoru yenilemesi zamanı mı? Yol raporundan BİR kare sonra true döner (bir kez); sonra tekrar false.
func corridors_due() -> bool:
	if _corridor_wait == 0:
		return false
	_corridor_wait -= 1
	return _corridor_wait == 0


## Senkron yenileme (dev `--m2-advance` / `--draw-road` döngüleri).
func sync_now() -> Dictionary:
	if follow != null:
		follow.settle()
	if sync == null:
		return {}
	return sync.wait() if sync.is_busy() else sync.sync()


## Rapor satırı + istatistik (`stats`: playable `sim_stats`).
func note_report(rep: Dictionary, stats: Dictionary, tick: int) -> void:
	if follow != null and not follow.stats.is_empty():
		stats["expropriation"] = follow.stats
	if rep.is_empty():
		return
	_corridor_wait = 2
	var ms := float(rep["ms"])
	stats["road_sync_n"] = int(stats.get("road_sync_n", 0)) + 1
	stats["road_sync_ms_last"] = snappedf(ms, 0.1)
	stats["road_sync_ms_max"] = snappedf(maxf(float(stats.get("road_sync_ms_max", 0.0)), ms), 0.1)
	stats["road_sync_chunks"] = int(rep["rebuilt"])
	print("PLAYABLE_ROADS tick=%d graph_version=%d full=%s chunks=%d ms=%.1f" % [tick, _net.graph_version,
			str(rep["full"]), int(rep["rebuilt"]), ms])
