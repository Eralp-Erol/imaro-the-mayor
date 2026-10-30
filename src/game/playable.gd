extends "res://scenes/dev/world_preview.gd"
## Entegre geliştirme oynanabilir — T-030'un ASGARİ dilimi (2026-10-20, kullanım limiti nedeniyle ana oturumda).
## Commit'li modülleri tek sahnede birleştirir: arazi + gerçek T0 yerleşimi + CameraRig (world_preview),
## gerçek SimFacadeImpl (ekonomi çekirdeği) + HudRoot (gerçek facade verisi). Sahte başarı yok;
## eksikler HUD üstündeki notta.
## T0 sütunları başlangıç stoğu olarak gerçek ekonomi durumuna aktarılır: bu bir karar kaydı değildir. Dünya
## tıklaması parseli imar akışına verir.
## T-040: sim'in yatırımcı kararıyla doğan yapıları (`ParcelView.developed_by_sim`) `SimBuildingProjector` ile
## BuildingColumns satırlarına çevrilir ve T0 görünümünden AYRI, küçük bir ikinci `BuildingView`'da ("SimBuildings",
## aynı dünya/kit/ayar) gösterilir; T0 görünümü yeniden kurulmaz. Oyuncu yapı koymaz (CAN-03): tek kaynak sim.
##
## Dev argümanları (YALNIZ doğrulama/yakalama için; oynanışı ve sim kurallarını değiştirmez):
##   --m2-focus-new   kamera odağını imar önerisi hedefi parsele (en yakın BOŞ, uygun parsel) taşır; --heading/--pitch/
##                    --distance ile kompozisyon ayarlanır.
##   --m2-advance=N   başlangıçta (HUD sonrası) demo imar önerisini verir ve facade.advance(N) ile N gün ilerletir.
##   --m2-batch=N     öneriye en yakın N boş uygun parsel katılır (varsayılan 1).  --m2-skip=K  ilk K adayı atla.
##   --m2-isolate     otonom yatırımcı taraması kapalı: yapı yalnız oyuncunun imar kararından doğar.
##   --demo-zone=Z    demo imar anahtarı (varsayılan zone.mixed).
##   --no-smoke-save-load  --demo'nun kare 60'taki kayıt/yükleme smoke'unu atlar (ölçüm: yükleme sonrası tek
##                    seferlik tam eşitleme sürekli-rejim kare maliyetinden ayrı raporlanabilsin).
##   --no-view-warmup açılış ısınmasını (ViewWarmup: kamera dar bantları örtü altında gezer) kapatır. Dev/yakalama
##                    argümanları (--shot, --quit-after, --preset, --sweep, --heading/--pitch/--distance, --hide,
##                    --m2-advance, --m2-focus-new, --t47-flow) ve başsız çalışma ısınmayı zaten atlar.
##   --no-vegetation  bitki görünümü kapalı (T-062 B1; varsayılan AÇIK: B0 yerleşimi, `VegetationView`). Perf A/B ve
##                    karşılaştırma içindir.  --veg-block: yerleşimi/önbelleği ana iş parçacığında BEKLER
## (yakalama/ölçüm:
##                    ilk karede bitki hazır; oyunda varsayılan değil, arka thread).  --veg-no-cache: disk önbelleği
## kapalı.
##                    --veg-force: başsız çalışmada da kur (varsayılan: başsızda atlanır, yerleşim ~14 sn).
##   --m2-log         her sim yapı senkronunu (süre, hücre) yazdırır.
##   --no-roads  yol görünümü kapalı (karşılaştırmalı ölçüm).
##   --no-sim-buildings  projector kapalı (ölçüm tabanı).
##   --no-far-lod     uzak (metro) görünümde birleşik tek-mesh temsilini kapatır (FarLod; perf A/B).
##   --hide=a,b,..    (yalnız perf A/B) bileşenleri çizimden gizler, veri/sim değişmez: land, water, roads, buildings
##                    (T0 yapıları), simbld, hud, markers. --terrain-simple: arazi gölgelendiricisi yerine düz köşe
##                    rengi malzemesi (gölgelendirici maliyetini ayırmak için).
##   --m2-pause       --m2-advance sonrası sim hızını duraklatır (inşaat ortası yakalama için sabit kare).
##   --t47-flow=built|empty  (yakalama) kamerayı odağa en yakın YAPILI (T0 stoku) ya da BOŞ parsele taşır, parseli
##                    seçer ve imar akışını açıp `--demo-zone` (varsayılan zone.green) kullanımını seçer; göndermez.
##   --t47-send=N     (yakalama) yukarıdaki akışta öneriyi gönderir ve N gün ilerletir (sonuç/durum satırı için).
##   --dev-notes      alt metne geliştirici notlarını (T0 aktarımı, olay sayacı, son eylem) ekler; yoksa yalnız
##                    kısa kontrol yardımı.
##   --inspect-parcel=ID|m2  (yakalama; m2 = --m2-advance demo parseli) parseli seçip denetçiyi açar (T-041);
##                    kamera o parsele odaklanır, bant --distance ile seçilir (sokak/mahalle/ilçe).
##   --m2-open-results  "Döngü sonucu" panelini (HUD) başlangıçta açar (yakalama için).

const SETTLEMENT_PATH := "res://data/world/ismeral/settlement.json"
const NETWORK_PATH := "res://data/world/ismeral/network.json"
## Demo imar önerisi. `zone.mixed` (konut + ticaret): yatırımcı talebi en yüksek kullanımı seçer. T0 stoğunda dükkân
## arzı hane ihtiyacının çok üstünde olduğundan salt ticaret önerisi talep nedeniyle reddedilir (geçerli olumsuz yol);
## yakalamada o yolu görmek için `--demo-zone=zone.commercial`.
const DEMO_LAND_USE := &"zone.mixed"
## Demo hedefi seçerken "bu parsele makul bir yapı sığar mı" sorusunun varsayılan birimi (sim gerçeğini kendisi verir).
const DEMO_PROBE_UNITS := 3
## `--m2-advance` adım uzunluğu (gün): her adımdan sonra projector senkronlanır.
const M2_ADVANCE_STEP_DAYS := 1
## Geliştirici notu (yalnız `--dev-notes`); oyuncu metni `HudHelp`te.
const DEV_NOTE := "T0 stok sim'e aktarıldı. Sim'in yeni gelişimi (inşaat kademesi dahil) ikinci BuildingView'da " \
		+ "yalnız sim aşamasından çizilir; oyuncu yapı koymaz."

## Bekleyen bitki yerleşimi üst sınırı (sn): ısınma bitki hücrelerini de çizmek ister; soğuk önbellekte (~14 sn)
## beklemeyiz, o durumda bitki ilk göründüğünde ısınır (VegetationView.warm_up gölgelendirici hattını zaten kurar).
const WARMUP_VEG_WAIT_S := 4.0
## Isınma bu dev argümanlarından biri varsa atlanır (yakalama/ölçüm kareleri örtü görmesin, kamera oynamasın).
const WARMUP_SKIP_ARGS: Array[String] = ["no-view-warmup", "shot", "quit-after", "preset", "sweep", "heading",
		"pitch", "distance", "hide", "m2-advance", "m2-focus-new", "t47-flow", "inspect-parcel"]


var sim_stats: Dictionary = {}

var _roads: RoadView
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
var _settlement: SettlementResult = null
var _kit: BuildingKit = null
var _sim_buildings: BuildingView = null
var _projector: SimBuildingProjector = null
var _pump: SimBuildingPump = null
var _t0_occupied: Dictionary = {}
var _m2_target: int = -1
var _m2_targets: PackedInt64Array = PackedInt64Array()
var _decisions: DecisionPanels = null
var _m2_results: M2Results = null
var _inspector: InspectorHost = null
var _selected_parcel_id: int = -1
var _acc_ms: float = 0.0
var _acc_n: int = 0
var _max_ms: float = 0.0
var _smoke_save_load_checked: bool = false
var _vegetation: VegetationView = null
var _veg_loader: VegetationLoader = null
var _warmup: ViewWarmup = null
var _warmup_started: bool = false
var _warmup_wait_start_us: int = 0


## Isınma (örtü altında kamera gezisi) sürerken true: ölçüm/yakalama betikleri bunu bekler.
func is_warming_up() -> bool:
	return _warmup != null and is_instance_valid(_warmup) and _warmup.is_active()


## Isınma çalışacak mı (saf karar; pencereli oyuncu yolu).
static func warmup_enabled(args: Dictionary, headless: bool) -> bool:
	if headless:
		return false
	for key in WARMUP_SKIP_ARGS:
		if args.has(key):
			return false
	return true


## perf_probe: kare başına sim günü (tick'li karelerin ayrı raporlanması için); sim yoksa -1.
func perf_tick() -> int:
	return _facade.current_tick() if _facade != null else -1


func _ready() -> void:
	super._ready()
	if _net != null and not _args.has("no-roads"):
		_roads = RoadView.new()
		_roads.name = "Roads"
		_roads.build_far_mesh = not _args.has("no-far-lod")
		_view_root.add_child(_roads)
		_roads.build(_net)
		print("ROADS ", JSON.stringify(_roads.stats))
	_demo = _args.has("demo")
	if _net == null:
		push_error("playable: ağ kurulamadı, sim bağlanmadı")
		return
	var t0 := Time.get_ticks_usec()
	_start_sim()
	_start_hud()
	_on_hud_ready()
	_m2_dev_setup()
	_t47_dev_setup()
	if _args.has("inspect-parcel") and _inspector != null:
		var want := str(_args["inspect-parcel"])
		_dev_inspect(_m2_target if want == "m2" else int(want))
	_start_vegetation()
	_apply_perf_flags()
	sim_stats["sim_setup_ms"] = snappedf((Time.get_ticks_usec() - t0) / 1000.0, 0.1)
	print("PLAYABLE ", JSON.stringify(sim_stats))


func _apply_far_lod(far: bool) -> void:
	super._apply_far_lod(far)
	if _roads != null:
		_roads.set_far_mode(far)


## Yalnız perf A/B bayrakları (--hide=, --terrain-simple): oyuncu yolunda hiçbir etkisi yok.
func _apply_perf_flags() -> void:
	if _args.has("terrain-simple") and _terrain != null:
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.vertex_color_is_srgb = true
		m.roughness = 1.0
		m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
		for node in _terrain.land_nodes():
			node.material_override = m
	if not _args.has("hide"):
		return
	var hidden := str(_args["hide"]).split(",", false)
	if "land" in hidden and _terrain != null:
		for node in _terrain.land_nodes():
			node.visible = false
	if "water" in hidden and _terrain != null:
		for node in _terrain.water_nodes():
			node.visible = false
	if "roads" in hidden and _roads != null:
		_roads.visible = false
	if "buildings" in hidden and _buildings != null:
		_buildings.visible = false
	if "simbld" in hidden and _sim_buildings != null:
		_sim_buildings.visible = false
	if "hud" in hidden and _hud != null:
		_hud.visible = false
	if "markers" in hidden and _markers != null:
		_markers.visible = false
	if "veg" in hidden and _vegetation != null:
		_vegetation.visible = false


func _build_buildings(_control: Dictionary, world_seed: int) -> Dictionary:
	var t0 := Time.get_ticks_usec()
	var net_control: Variant = JSON.parse_string(FileAccess.get_file_as_string(NETWORK_PATH))
	var rules: Variant = JSON.parse_string(FileAccess.get_file_as_string(SETTLEMENT_PATH))
	if not (net_control is Dictionary and rules is Dictionary):
		push_error("playable: network/settlement verisi okunamadı")
		return {}
	_net = NetworkGenerator.generate(_world, net_control, world_seed)
	var t1 := Time.get_ticks_usec()
	# generate() == generate_detailed().columns; ayrıntı (bölge dokusu, meydan, çok parsellileri) projector'a gerekir.
	# T-062 A2/A3: yerleşim ve görünüm AYNI süzülmüş oyun bina tablosunu (onaylı hero, `LibraryGate`) okur: module_idx
	# tablo sırasıdır ve `BuildingKit` dizinleriyle birebir aynıdır.
	var loaded := SettlementTable.load_game_table()
	var game_table: Dictionary = loaded["table"]
	var gate: LibraryGate = loaded["gate"]
	if game_table.is_empty():
		# Fail-closed (LibraryGate kapalı ya da tablo okunamadı): yapı yok, ama oyun çökmez (SettlementTable hatayı logladı).
		push_error("playable: oyun bina tablosu yok/kapı kapalı; yapılar kurulmadı")
		return {"error": "game_table_unavailable"}
	_settlement = T0Settlement.generate_detailed(_world, _net, game_table, world_seed, rules)
	var cols: BuildingColumns = _settlement.columns
	_t0_columns = cols
	for pid in cols.occupied_parcels():
		_t0_occupied[int(pid)] = true
	var t2 := Time.get_ticks_usec()
	var config := BuildingViewConfig.new()
	config.cast_shadows = _shadows_wanted
	_buildings = BuildingView.new()
	_buildings.name = "Buildings"
	_view_root.add_child(_buildings)
	_kit = BuildingKit.from_game_table(game_table, gate)
	if not _kit_matches_settlement():
		push_error("playable: görünüm modül dizini yerleşim tablosuyla uyuşmuyor (module_idx)")
	_buildings.setup(_world, _kit, config)
	var report := _buildings.set_columns(cols, _net.graph_version)
	if not report.get("ok", false):
		push_error("playable: yapı sütunları reddedildi: %s" % str(report.get("errors")))
	var stats := _buildings.stats.duplicate()
	# T-051: kent zemini maskesi (yapılı parsel altı döşeme/toprak; bir kez, yeni draw call yok).
	stats["urban_ground"] = _terrain.apply_urban_ground(_net, cols)
	stats["network_ms"] = snappedf((t1 - t0) / 1000.0, 0.1)
	stats["settlement_ms"] = snappedf((t2 - t1) / 1000.0, 0.1)
	stats["view_ms"] = snappedf((Time.get_ticks_usec() - t2) / 1000.0, 0.1)
	stats["parcels"] = _net.parcels.size()
	stats["buildings"] = cols.count
	stats["unapproved_ids"] = gate.unapproved_ids.size()
	# T-040: sim'in geliştirdiği yapılar için ayrı, başlangıçta BOŞ görünüm (aynı dünya/kit/ayar; kendi sütunları).
	_sim_buildings = BuildingView.new()
	_sim_buildings.name = "SimBuildings"
	_view_root.add_child(_sim_buildings)
	_sim_buildings.setup(_world, _kit, config)
	return stats


## Görünüm kiti ile yerleşim kuralları AYNI modül sırasında mı (module_idx birebir)?
func _kit_matches_settlement() -> bool:
	var modules := _settlement.rules.modules
	if modules.size() != _kit.count:
		return false
	for i in modules.size():
		if modules[i].idx != i or modules[i].id != _kit.ids[i]:
			return false
	return true


## T-062 B1: bitki görünümü. Mesh'ler ve atlas rengi ana iş parçacığında (kapıdan) yüklenir; yerleşim (B0, ~14 sn) arka
## thread'de ya da disk önbelleğinden gelir, hazır olunca `_adopt_vegetation` görünümü kurar. Başsızda varsayılan
## atlanır.
func _start_vegetation() -> void:
	if _args.has("no-vegetation") or _settlement == null or _net == null:
		return
	if DisplayServer.get_name() == "headless" and not _args.has("veg-force"):
		sim_stats["vegetation"] = "skipped (headless)"
		return
	var t0 := Time.get_ticks_usec()
	var config := VegetationViewConfig.load_default()
	if not config.valid():
		push_error("playable: bitki görünüm ayarı geçersiz: %s" % "; ".join(config.errors))
		return
	var species := VegetationSpecies.load_default()
	var rules := VegetationRules.load_path(VegetationRules.PATH, species)
	if species.size() == 0 or not rules.is_valid():
		push_error("playable: bitki tablosu/kuralları geçersiz: %s" % "; ".join(rules.errors))
		return
	_apply_vegetation_overrides(config)
	var look := VegetationLook.load_full(species, config)
	if not look.errors.is_empty():
		push_error("playable: bitki görünüm tablosu eksik: %s" % "; ".join(look.errors))
	_vegetation = VegetationView.new()
	_vegetation.name = "Vegetation"
	_view_root.add_child(_vegetation)
	_vegetation.setup(look, config)
	_vegetation.warm_up(_camera.camera)
	var blocking := _args.has("veg-block")
	_veg_loader = VegetationLoader.start(_settlement, species, rules, _world, blocking, not _args.has("veg-no-cache"))
	sim_stats["vegetation_assets_ms"] = snappedf((Time.get_ticks_usec() - t0) / 1000.0, 0.1)
	if blocking:
		_adopt_vegetation()


## Yalnız ölçüm/A-B bayrakları (oyuncu yolunda etkisiz): kademe eşikleri ve leke/gölge anahtarları.
##   --veg-lod0=M --veg-lod1=M  --veg-no-blob  --veg-no-shadow  --veg-blob-end=M
func _apply_vegetation_overrides(config: VegetationViewConfig) -> void:
	config.lod0_end_m = _arg_float(_args, "veg-lod0", config.lod0_end_m, 10.0, 2000.0)
	config.lod1_end_m = _arg_float(_args, "veg-lod1", config.lod1_end_m, 20.0, 5000.0)
	config.blob_end_m = _arg_float(_args, "veg-blob-end", config.blob_end_m, 100.0, 20000.0)
	if _args.has("veg-no-blob"):
		config.blob_enabled = false
	if _args.has("veg-no-shadow"):
		config.shadow_lod0 = false
	config.palm_proxy_end_m = maxf(config.palm_proxy_end_m, config.lod1_end_m)
	if config.blob_fade_begin_m <= config.lod1_end_m or config.blob_end_m <= config.blob_fade_begin_m:
		config.blob_fade_begin_m = config.lod1_end_m + (config.blob_end_m - config.lod1_end_m) * 0.6
	var problems := config.problems()
	if not problems.is_empty():
		push_error("playable: --veg-* geçersiz: %s" % "; ".join(problems))


## Yerleşim hazırsa görünümü kurar (tek sefer). Hazır değilse hiçbir şey yapmaz.
func _adopt_vegetation() -> void:
	if _veg_loader == null or not _veg_loader.poll():
		if _veg_loader != null and _veg_loader.state == VegetationLoader.State.FAILED:
			push_error("playable: bitki yerleşimi başarısız: %s" % str(_veg_loader.stats.get("error", "?")))
			_veg_loader = null
		return
	var loader := _veg_loader
	_veg_loader = null
	_vegetation.set_layout(loader.layout)
	var cam := _vegetation_camera_position()
	_vegetation.track_camera(cam)
	if _args.has("veg-block"):
		_vegetation.settle()
	sim_stats["vegetation"] = loader.stats
	build_stats["vegetation"] = _vegetation.stats
	print("VEGETATION ", JSON.stringify({"loader": loader.stats, "instances": loader.columns.count,
			"view": _vegetation.stats}))


## Kameranın dünya konumu (rebasing'den bağımsız): LOD kararı dünya koordinatındadır.
func _vegetation_camera_position() -> Vector3:
	var p := _camera.camera.global_position
	return Vector3(p.x + _camera.rebase_origin.x, p.y, p.z + _camera.rebase_origin.y)


func _exit_tree() -> void:
	if _veg_loader != null:
		_veg_loader.wait()


func _start_sim() -> void:
	_views = _parcel_views()
	var source := ListParcelSource.create(&"ismeral", _views)
	if source == null or not source.is_valid():
		push_error("playable: parsel kaynağı geçersiz")
		return
	var stock := PlayableStock.from_columns(_t0_columns)
	if stock == null or not stock.is_valid():
		push_error("playable: T0 stok adaptörü geçersiz")
		return
	# Integrated playable must use the same Economy + Actors + Politics facade
	# exposed to the HUD; EconomyBootstrap would silently omit the latter two.
	# --m2-isolate (dev): periyodik otonom tarama kapalı; yatırımcı yalnız oyuncunun imar kararından sonra değerlendirir.
	var patch := {"decision": {"review_enabled": 0}} if _args.has("m2-isolate") else {}
	var economy_cfg := PlayableEconomy.config_for(_views, stock, patch)
	var handle := PoliticsBootstrap.create(_world.world_seed, source, economy_cfg, stock)
	if handle == null:
		push_error("playable: ekonomi/aktör/siyaset çekirdeği kurulamadı")
		return
	_facade = handle.facade
	_facade.set_speed(3 if _demo else 1)
	_projector = SimBuildingProjector.create(_facade, _settlement, SimBuildingMapping.load_default(), _world.world_seed)
	if _projector == null:
		push_error("playable: SimBuildingProjector kurulamadı; sim yapıları çizilmeyecek")
	else:
		_pump = SimBuildingPump.create(_projector)
	sim_stats["sim_parcels"] = source.parcel_count()
	sim_stats["t0_stock_parcels"] = stock.parcel_ids().size()


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
	# T-047: oynanabilir sahnede yalnız çalışan araçlar kayıtlıdır (İmar önerisi + Döngü sonucu); Bütçe/Meclis/Gündem
	# gerçek sim'de henüz kurulu değil, kaydedilmez. T0 stoku için "parselde yapı var mı" sorgusu dünya verisinden gelir.
	_decisions = DecisionPanels.attach(_hud, _facade, _has_t0_structure, false)
	shared_input.select_requested.connect(_on_select_requested)
	_status = Label.new()
	# Yer `_place_status` ile HUD boş harita dikdörtgeninden hesaplanır (araç çubuğu/panelle çakışmaz).
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_status.add_theme_font_size_override("font_size", 13)
	# Okunabilirlik: 3B sahne üstünde yarı saydam koyu zemin (HUD token'ı değil, yalnız bu yardım etiketi).
	var plate := StyleBoxFlat.new()
	plate.bg_color = Color(0.05, 0.07, 0.10, 0.62)
	plate.set_corner_radius_all(4)
	plate.content_margin_left = 8.0
	plate.content_margin_right = 8.0
	plate.content_margin_top = 4.0
	plate.content_margin_bottom = 4.0
	_status.add_theme_stylebox_override("normal", plate)
	layer.add_child(_status)


## Parselde T0 başlangıç yapısı var mı (ilk günlük tick'ten önce sim bu parselleri `vacant` gösterir).
func _has_t0_structure(parcel_id: int) -> bool:
	return _t0_occupied.has(parcel_id)


## Alt köşe metni (`HudHelp`): oyuncuya kısa kontrol yardımı + sim günü; `--dev-notes` ile geliştirici satırları.
func status_text() -> String:
	var dev := "%s\nolay %d | son eylem: %s" % [DEV_NOTE, _facade.last_event_seq(), _last_action]
	var touch := PlatformProfile.current().input_profile == PlatformProfile.INPUT_TOUCH
	return HudHelp.status_text(_facade.current_tick(), _args.has("dev-notes"), dev, touch)


## Yardım etiketini HUD'un boş harita dikdörtgenine yerleştirir (araç çubuğu/panel dışında).
func _place_status() -> void:
	if _status == null or _hud == null or _hud.layout == null:
		return
	var h := _status.get_combined_minimum_size().y
	var r := HudHelp.status_rect(_hud.free_map_rect(), h)  # genişlik zemin dolgusu dahil
	_status.custom_minimum_size = Vector2(r.size.x, 0.0)
	_status.position = r.position
	_status.size = Vector2(r.size.x, h)
	# Olay şeridinin GÖRÜNÜR satırlarıyla çakışıyorsa gösterme: yardım metni hiçbir öğenin üstüne binmez.
	_status.visible = true
	if _hud.strip != null:
		for row in _hud.strip.get_children():
			var c := row as Control
			if c != null and c.visible and r.intersects(c.get_global_rect()):
				_status.visible = false


## T-040 UI KANCASI: HUD kurulduktan sonra çağrılır. "Döngü sonucu" paneli + gerekçe paneli bağı (UI payı; render/
## projector koduna dokunmaz). `--m2-open-results` (dev) paneli başlangıçta açar.
func _on_hud_ready() -> void:
	_m2_results = M2Results.attach(_hud, _facade, _decisions)
	if _args.has("m2-open-results"):
		_m2_results.open()
	# T-041: haritada seçim parsel/bölge denetçisini açar; imar önerisi denetçideki fiilden (veya Z) açılır.
	_inspector = InspectorHost.attach(_hud, _facade, _m2_results.open_reason, _open_zoning_for)
	_inspector.set_band(_camera.scale_band)
	_camera.scale_band_changed.connect(_inspector.set_band)


## Dev argümanları (üst nota bakın). Yalnız komut satırında verilirse çalışır.
func _m2_dev_setup() -> void:
	if _facade == null:
		return
	if not (_args.has("m2-focus-new") or _args.has("m2-advance")):
		return
	_m2_targets = _pick_demo_parcels(_arg_int(_args, "m2-batch", 1, 1, 64), _arg_int(_args, "m2-skip", 0, 0, 100000))
	_m2_target = int(_m2_targets[0]) if not _m2_targets.is_empty() else -1
	if _args.has("m2-focus-new") and _m2_target > 0:
		var wp: WorldParcel = _net.parcels.get(_m2_target)
		var s := _camera.target_state()
		s.focus_x = wp.centroid.x
		s.focus_z = wp.centroid.y
		_camera.apply_state(s, true)
		_apply_camera_overrides(_args)
	if _args.has("m2-advance"):
		_submit_demo(_m2_targets)
		var days := _arg_int(_args, "m2-advance", 0, 0, 3650)
		var t0 := Time.get_ticks_usec()
		# Küçük adımlarla ilerlet + senkronla: olay günlüğü (1000 kayıt) tek seferde 100 gün taşıyamaz.
		var left := days
		while left > 0:
			var step := mini(left, M2_ADVANCE_STEP_DAYS)
			_facade.advance(step)
			_sync_sim_buildings(true)
			left -= step
		sim_stats["m2_advance_days"] = days
		sim_stats["m2_advance_ms"] = snappedf((Time.get_ticks_usec() - t0) / 1000.0, 0.1)
		if _args.has("m2-pause"):
			_facade.set_speed(SimFacade.SPEED_PAUSED)
		print(_m2_target_report(days))


## `--t47-flow` / `--t47-send` (dev, yakalama): oyuncunun tıklama yolunu taklit eder (parsel seç -> imar akışı).
func _t47_dev_setup() -> void:
	if _facade == null or _decisions == null or not _args.has("t47-flow"):
		return
	var want_built := str(_args["t47-flow"]) != "empty"
	var focus := _camera.current_state()
	var at := Vector2(focus.focus_x, focus.focus_z)
	var best := -1
	var best_d := INF
	if want_built:
		for v in _views:
			if _t0_occupied.has(v.id) and v.center.distance_squared_to(at) < best_d:
				best_d = v.center.distance_squared_to(at)
				best = v.id
	else:
		var pick := _pick_demo_parcels(1, 0)
		best = int(pick[0]) if not pick.is_empty() else -1
	if best <= 0:
		print("PLAYABLE_T47 parsel bulunamadı")
		return
	var wp: WorldParcel = _net.parcels.get(best)
	var st := _camera.target_state()
	st.focus_x = wp.centroid.x
	st.focus_z = wp.centroid.y
	_camera.apply_state(st, true)
	_apply_camera_overrides(_args)
	_selected_parcel_id = best
	_decisions.open_zoning(PackedInt64Array([best]))
	var zone := StringName(str(_args.get("demo-zone", "zone.green")))
	_decisions.zoning_panel().choose_use(zone)
	if _args.has("t47-send"):
		_decisions.zoning_panel().send()
		var left := _arg_int(_args, "t47-send", 0, 0, 3650)
		while left > 0:
			_facade.advance(1)
			left -= 1
		_hud.refresh()
		_facade.set_speed(SimFacade.SPEED_PAUSED)
	print("PLAYABLE_T47 parcel=%d built=%s zone=%s tick=%d" % [best, str(want_built), String(zone),
			_facade.current_tick()])


## `--m2-advance` sonrası hedef parselin sim durumu ve karar gerekçeleri sayımı (konsol; yakalama doğrulaması için).
func _m2_target_report(days: int) -> String:
	var tv: Array[ParcelView] = _facade.parcel_views(PackedInt64Array([_m2_target]))
	var state := "-"
	if not tv.is_empty():
		state = "%s use=%s units=%d progress=%d by_sim=%s" % [tv[0].development, tv[0].use, tv[0].units,
				tv[0].progress_pm, tv[0].developed_by_sim]
	var positive := 0
	var negative := 0
	for r in _facade.reasons_for(SimContract.parcel_ref(_m2_target)):
		if r.decision_key == &"decision.investor.develop":
			if r.outcome == ReasonRecord.OUTCOME_POSITIVE:
				positive += 1
			else:
				negative += 1
	var eo := _facade.economy_outcome()
	var fmt := "PLAYABLE_M2 target=%d days=%d tick=%d rows=%d parcel[%s] decisions(+%d/-%d) "
	fmt += "city(approved=%d declined=%d completed=%d) unplaced=%d"
	return fmt % [_m2_target, days, _facade.current_tick(), _projector.columns().count if _projector != null else -1,
			state, positive, negative, eo.investments_approved, eo.investments_declined, eo.projects_completed,
			_projector.unplaced().size() if _projector != null else -1]


## Sim durumundan türeyen yapıları ikinci görünüme yansıtır. Sim'e yazmaz. İKİ kip:
##  - `full = true` (dev `--m2-advance` adımları): bütçesiz tam senkron + görünüm kurulumu.
##  - `full = false` (kare yolu): iş dağıtımı `SimBuildingPump`ta (testlerle ORTAK kural): tick'li karede iş yok,
##    bekleyen
##    sütun varsa görünüm kurulumu, aksi halde projector'ın bütçeli dilimi; geride kalındıkça bütçe büyür.
##    `--m2-log` her görünüm kurulumunu yazdırır.
func _sync_sim_buildings(full: bool = false, ticked: bool = false) -> void:
	if _projector == null or _sim_buildings == null or _args.has("no-sim-buildings"):
		return
	var t_all := Time.get_ticks_usec()
	var worked := false
	if full:
		_projector.sync()
		if _pump.view_pending():
			_apply_sim_view(_projector.columns(), _projector.version())
			_pump.mark_view_version(_projector.version())
		worked = true
	else:
		worked = bool(_pump.frame(ticked, _apply_sim_view).get("worked", false))
	if not worked:
		return
	var total_ms := (Time.get_ticks_usec() - t_all) / 1000.0
	sim_stats["sync_n"] = int(sim_stats.get("sync_n", 0)) + 1
	sim_stats["sync_ms_sum"] = float(sim_stats.get("sync_ms_sum", 0.0)) + total_ms
	sim_stats["sync_ms_max"] = maxf(float(sim_stats.get("sync_ms_max", 0.0)), total_ms)
	# perf_probe raporu (`scene_build_stats`) için: işli karelerin sayısı/ortalaması/azami süresi (projector dilimi VEYA
	# görünüm kurulumu), görünüm kurulumu ve kuyruk derinliği.
	var vn := maxi(int(sim_stats.get("view_n", 0)), 1)
	build_stats["sim_sync"] = {"n": sim_stats["sync_n"],
			"avg_ms": snappedf(float(sim_stats["sync_ms_sum"]) / int(sim_stats["sync_n"]), 0.01),
			"max_ms": snappedf(float(sim_stats["sync_ms_max"]), 0.01),
			"view_builds": int(sim_stats.get("view_n", 0)),
			"view_avg_ms": snappedf(float(sim_stats.get("view_ms_sum", 0.0)) / vn, 0.01),
			"full_syncs": int(_projector.stats.get("full_syncs", 0)), "rows": _projector.columns().count,
			"stage_polls": int(_projector.stats.get("stage_polls", 0)),
			"unplaced": _projector.unplaced_count(),
			"windows": int(_projector.stats.get("windows", 0)),
			"parcel_reads": int(_projector.stats.get("parcel_reads", 0)),
			"backlog_max": int(_projector.stats.get("backlog_max", 0)),
			"step_max_ms": snappedf(float(_projector.stats.get("step_ms_max", 0.0)), 0.01),
			"begin_max_ms": snappedf(float(_projector.stats.get("begin_ms_max", 0.0)), 0.01),
			"views_unit_max_ms": snappedf(float(_projector.stats.get("views_ms_max", 0.0)), 0.01),
			"read_ms": snappedf(float(_projector.stats.get("read_us", 0)) / 1000.0, 0.1),
			"apply_ms": snappedf(float(_projector.stats.get("apply_us", 0)) / 1000.0, 0.1),
			"plan_n": int(_projector.stats.get("plan_n", 0)),
			"plan_max_ms": snappedf(float(_projector.stats.get("plan_ms_max", 0.0)), 0.01),
			"plan_avg_ms": snappedf(float(_projector.stats.get("plan_us", 0)) / 1000.0
					/ maxi(int(_projector.stats.get("plan_n", 0)), 1), 0.01)}


## Projector sütunlarını ikinci BuildingView'a kurar (`SimBuildingPump` çağırır).
func _apply_sim_view(columns: BuildingColumns, version: int) -> void:
	var t0 := Time.get_ticks_usec()
	var res := _sim_buildings.set_columns(columns, version)
	var view_ms := (Time.get_ticks_usec() - t0) / 1000.0
	sim_stats["sim_buildings"] = columns.count
	sim_stats["view_ms_sum"] = float(sim_stats.get("view_ms_sum", 0.0)) + view_ms
	sim_stats["view_n"] = int(sim_stats.get("view_n", 0)) + 1
	if not bool(res.get("ok", false)):
		push_error("playable: sim yapı sütunları reddedildi: %s" % str(res.get("errors")))
	if _args.has("m2-log"):
		print("PLAYABLE_SIMBLD tick=%d rows=%d rebuilt_cells=%s view_ms=%.2f backlog=%d" % [
				_facade.current_tick(), columns.count, str(res.get("rebuilt", -1)), view_ms,
				_projector.backlog_ticks()])


func _process(delta: float) -> void:
	super._process(delta)
	if _veg_loader != null:
		_adopt_vegetation()
	elif _vegetation != null and _camera != null:
		_vegetation.track_camera(_vegetation_camera_position())
	if _facade == null:
		return
	_frames += 1
	_maybe_start_warmup()
	_acc_ms += delta * 1000.0
	_acc_n += 1
	_max_ms = maxf(_max_ms, delta * 1000.0)
	var tick_before := _facade.current_tick()
	var t_drive := Time.get_ticks_usec()
	# Isınma örtüsü altında sim yalnız İLK tick'e kadar sürer (ilk tick ekonomi durumunu kurar, ~120 ms): oyuncu onu
	# görmez; sonra sim bekler, böylece oyuncu örtü kalktığında "gün 1"de başlar (örtüsüz akıştaki 1. saniye gibi).
	# Sim durumuna dokunulmaz: yalnız zaten yapılacak olan tick'ler sürülür (tick sayısına göre deterministik).
	if not is_warming_up() or tick_before < 1:
		_facade.drive_usec(int(delta * 1000000.0))
	var drive_us := Time.get_ticks_usec() - t_drive
	# Tick'li karede sim zaten ağır: yapı senkronu sonraki karelere yayılır (SimBuildingPump kuralı); kuyruk çok
	# derinleşirse (yavaş kareler) tick'li karede de iş yürür (sonsuz birikme yok).
	_sync_sim_buildings(false, _facade.current_tick() != tick_before)
	if _facade.current_tick() != _seen_tick:
		_seen_tick = _facade.current_tick()
		var t_poll := Time.get_ticks_usec()
		if _hud != null:
			_hud.poll()
		_note_tick_cost(drive_us, Time.get_ticks_usec() - t_poll)
	if _demo and _frames == 10 and not _args.has("m2-advance"):
		_submit_demo()
	# Başsız T-030 smoke, gerçek facade üzerinde kayıt baytını tekrar içe alıp
	# kanonik hash'in korunduğunu denetler. Bu yalnız --demo ile çalışan bir
	# doğrulama kancasıdır; normal oturumda kayıt durumu veya dosya üretmez.
	if _demo and not _smoke_save_load_checked and _frames >= 60 and not _args.has("no-smoke-save-load"):
		_smoke_save_load_checked = true
		_smoke_save_load()
	if _status != null:
		_status.text = status_text()
		_place_status()
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
		var n := int(sim_stats.get("sync_n", 0))
		if n > 0:
			print("PLAYABLE_SIMBLD_SYNC n=%d avg_ms=%.2f max_ms=%.2f rows=%d full_syncs=%d unplaced=%d %s" % [n,
					float(sim_stats["sync_ms_sum"]) / n, float(sim_stats["sync_ms_max"]),
					_projector.columns().count, int(_projector.stats.get("full_syncs", 0)),
					_projector.unplaced_count(), JSON.stringify(_projector.unplaced_reason_counts())])
		print("PLAYABLE_QUIT frames=%d tick=%d" % [_frames, _facade.current_tick()])
		get_tree().quit()


## Isınmayı (tek sefer) başlatır: pencereli oyuncu yolunda, bitki yerleşimi hazır olunca ya da bekleme sınırı dolunca.
func _maybe_start_warmup() -> void:
	if _warmup_started or _camera == null:
		return
	if not warmup_enabled(_args, DisplayServer.get_name() == "headless"):
		_warmup_started = true
		return
	if _warmup_wait_start_us == 0:
		_warmup_wait_start_us = Time.get_ticks_usec()
	var waited_s := (Time.get_ticks_usec() - _warmup_wait_start_us) / 1000000.0
	if _veg_loader != null and waited_s < WARMUP_VEG_WAIT_S:
		return
	_warmup_started = true
	_warmup = ViewWarmup.new()
	_warmup.name = "ViewWarmup"
	add_child(_warmup)
	_warmup.finished.connect(_on_warmup_finished)
	_warmup.begin(_camera, _view_work_pending)
	print("PLAYABLE_WARMUP begin veg_ready=%s waited_s=%.1f" % [str(_veg_loader == null), waited_s])


## Isınma bekleme koşulu: ilk sim tick'i henüz olmadı (örtü altında olsun) ya da bitki hücre kuyruğu dolu.
func _view_work_pending() -> bool:
	if _facade != null and _facade.current_tick() < 1:
		return true
	return _vegetation != null and int(_vegetation.stats.get("queued", 0)) > 0


func _on_warmup_finished() -> void:
	var w := _warmup
	sim_stats["warmup_ms"] = w.duration_ms
	sim_stats["warmup_frames"] = w.frames_held_total
	print("PLAYABLE_WARMUP done ms=%.1f frames=%d poses=%d tick=%d" % [w.duration_ms, w.frames_held_total,
			w.poses_done, _facade.current_tick() if _facade != null else -1])


## Tick'li karenin sim ve HUD payı (perf_probe `scene_build_stats.tick_cost`): sim tick'i ile `hud.poll` ayrı
## raporlanır (ısınma kareleri dahil: ilk tick'ler ekonomi durumunu kurduğu için pahalıdır).
func _note_tick_cost(drive_us: int, poll_us: int) -> void:
	var n := int(sim_stats.get("tick_cost_n", 0)) + 1
	sim_stats["tick_cost_n"] = n
	sim_stats["drive_us_sum"] = int(sim_stats.get("drive_us_sum", 0)) + drive_us
	sim_stats["poll_us_sum"] = int(sim_stats.get("poll_us_sum", 0)) + poll_us
	sim_stats["drive_us_max"] = maxi(int(sim_stats.get("drive_us_max", 0)), drive_us)
	sim_stats["poll_us_max"] = maxi(int(sim_stats.get("poll_us_max", 0)), poll_us)
	build_stats["tick_cost"] = {"ticked_frames": n,
			"sim_drive_avg_ms": snappedf(float(sim_stats["drive_us_sum"]) / n / 1000.0, 0.01),
			"sim_drive_max_ms": snappedf(float(sim_stats["drive_us_max"]) / 1000.0, 0.01),
			"hud_poll_avg_ms": snappedf(float(sim_stats["poll_us_sum"]) / n / 1000.0, 0.01),
			"hud_poll_max_ms": snappedf(float(sim_stats["poll_us_max"]) / 1000.0, 0.01)}


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and _facade != null:
		var key := (event as InputEventKey).keycode
		if key == KEY_Z:
			# Z: imar akışını açar (seçili parselle); öneri onay adımıyla gönderilir, sessizce gönderilmez.
			if _decisions != null:
				_decisions.open_zoning(PackedInt64Array([_selected_parcel_id]) if _selected_parcel_id > 0
						else PackedInt64Array())
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
		if _inspector != null:
			_inspector.select_parcel(-1)
		return
	_selected_parcel_id = pid
	if _inspector != null:
		_inspector.select_parcel(pid)
	print("PLAYABLE_SELECT parcel=%d" % pid)


## Denetçideki "İmar önerisi ver" fiili: imar akışı seçili parselle açılır (öneri yine onay adımıyla gönderilir).
func _open_zoning_for(parcel_id: int) -> void:
	_selected_parcel_id = parcel_id
	_decisions.open_zoning(PackedInt64Array([parcel_id]))


## `--inspect-parcel=<id>` (dev, yakalama): oyuncunun tıklama yolunun sonucunu taklit eder (seçim -> denetçi).
## Kamerayı parsele odaklar; ham yok olan kimlik denetçide "bulunamadı" durumunu gösterir.
func _dev_inspect(parcel_id: int) -> void:
	var wp: WorldParcel = _net.parcels.get(parcel_id)
	if wp != null:
		var st := _camera.target_state()
		st.focus_x = wp.centroid.x
		st.focus_z = wp.centroid.y
		_camera.apply_state(st, true)
		_apply_camera_overrides(_args)
	_selected_parcel_id = parcel_id
	_inspector.select_parcel(parcel_id)
	print("PLAYABLE_INSPECT parcel=%d" % parcel_id)


## Demo imar önerisi: tıklamayla seçili parsel, yoksa `targets` (dev yolu), yoksa en yakın boş uygun parsel.
func _submit_demo(targets: PackedInt64Array = PackedInt64Array()) -> void:
	var pids := PackedInt64Array()
	if _selected_parcel_id > 0:
		pids.append(_selected_parcel_id)
	elif not targets.is_empty():
		pids = targets
	else:
		pids = _pick_demo_parcels(1, 0)
	if pids.is_empty():
		_last_action = "boş uygun parsel bulunamadı"
		print("PLAYABLE_ACTION ", _last_action)
		return
	var zone := _demo_zone()
	var res := _facade.submit_command(SimCommand.zoning_propose(pids, zone))
	_last_action = "parsel %s → %s: %s" % [str(pids), String(zone), str(res.get("status"))]
	if _m2_results != null and not res.is_rejected():
		_m2_results.track_parcels(pids)
	print("PLAYABLE_ACTION ", _last_action)


## Kayıt YÜKLENDİKTEN hemen sonra çağrılır (gerçek yükleme yolu ve `_smoke_save_load`): türetilmiş sim yapıları BİR
## KEZ ve senkron yeniden kurulur (projector tam eşitlemesi; kare bütçesiyle yayılmaz) ve görünüm hemen
## güncellenir. Süre `sim_stats["load_resync_ms"]` ve `PLAYABLE_LOAD_RESYNC` satırında.
func resync_sim_buildings_after_load() -> void:
	if _projector == null or _sim_buildings == null or _args.has("no-sim-buildings"):
		return
	var t0 := Time.get_ticks_usec()
	var rep := _projector.sync()
	if _pump.view_pending():
		_apply_sim_view(_projector.columns(), _projector.version())
		_pump.mark_view_version(_projector.version())
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	sim_stats["load_resync_ms"] = snappedf(ms, 0.1)
	print("PLAYABLE_LOAD_RESYNC ms=%.1f resync=%s rows=%d full_sync_ms=%.1f parcel_reads=%d" % [ms,
			str(rep.get("resync")), _projector.columns().count, float(_projector.stats.get("full_sync_ms", 0.0)),
			int(_projector.stats.get("parcel_reads", 0))])


func _smoke_save_load() -> void:
	var impl := _facade as SimFacadeImpl
	if impl == null:
		push_error("playable: smoke save/load gerçek SimFacadeImpl gerektirir")
		print("PLAYABLE_SAVE_LOAD FAIL facade")
		return
	var before := impl.state_hash()
	var bytes := impl.export_save()
	var loaded := impl.import_save(bytes)
	resync_sim_buildings_after_load()
	var after := impl.state_hash()
	if loaded.ok and not before.is_empty() and before == after:
		print("PLAYABLE_SAVE_LOAD OK tick=%d bytes=%d hash=%s" % [impl.current_tick(), bytes.size(), before])
	else:
		push_error("playable: smoke save/load hash eşitliği sağlanamadı: %s" % loaded.message)
		print("PLAYABLE_SAVE_LOAD FAIL ok=%s before=%s after=%s" % [loaded.ok, before, after])


func _demo_zone() -> StringName:
	return StringName(str(_args.get("demo-zone", String(DEMO_LAND_USE))))


## Demo/Z hedefleri: kamera odağına en yakın BOŞ ve uygun `count` parsel (ilk `skip` aday atlanır; dev). Boş = sim'de
## vacant, bekleyen imar önerisi yok ve T0 yapı stoğunda değil (tick 0'da T0 parselleri sim'de de `vacant` görünür);
## uygun = projector bu kullanım için bir yapı sığdırabilir (aksi halde öneri onaylansa bile çizilecek yapı olmazdı).
## Oyuncu seçimi bu yoldan geçmez. Sıralama (uzaklık, kimlik) deterministiktir.
func _pick_demo_parcels(count: int, skip: int) -> PackedInt64Array:
	var focus := _camera.current_state()
	var at := Vector2(focus.focus_x, focus.focus_z)
	var ranked: Array = []
	for v in _views:
		if not _t0_occupied.has(v.id):
			ranked.append([v.center.distance_squared_to(at), v.id])
	ranked.sort()
	var use: StringName = &"commercial" if _demo_zone() == &"zone.commercial" else &"residential"
	var out := PackedInt64Array()
	var skipped := 0
	var batch := 24
	for start in range(0, mini(ranked.size(), 1920), batch):
		var ids := PackedInt64Array()
		for k in range(start, mini(start + batch, ranked.size())):
			ids.append(int(ranked[k][1]))
		for cur in _facade.parcel_views(ids):
			if cur.development != ParcelView.DEVELOPMENT_VACANT or cur.pending_zone != &"":
				continue
			if _projector != null and not _projector.placer().can_place(cur.id, use, DEMO_PROBE_UNITS):
				continue
			if skipped < skip:
				skipped += 1
				continue
			out.append(cur.id)
			if out.size() >= count:
				return out
	return out
