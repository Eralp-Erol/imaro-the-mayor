class_name VegetationLoader
extends RefCounted
## Bitki yerleşimini oyunu DONDURMADAN hazırlar (T-062 B1, dünya yükleme). B0 yerleşimi ~14 sn sürer (headless ölçüm);
## burada: (1) girdi anahtarıyla disk önbelleği (`VegetationCache`) -> isabette ms; (2) isabetsizlikte
## `WorkerThreadPool`
## görevi, ana iş parçacığı oyunu çizer, `poll()` hazır olunca görünüm kurulur. `blocking=true` aynı işi ana iş
## parçacığında bekler (yakalama/ölçüm: ilk karede bitki hazır olsun). DETERMİNİZM: üretici saf ve seed'li; önbellek
## aynı
## girdi anahtarı dışında kullanılmaz. Çıktı `VegetationColumns` (B0, bire bir) + `VegetationLayout`.
## Yerleşim sonucu/dünya YALNIZ OKUNUR (iş parçacığı sırasında ana iş parçacığı bunları değiştirmemeli: oyun açılışında
## değiştirmez; sim okur).

enum State { IDLE, RUNNING, READY, FAILED }

var state: State = State.IDLE
var columns: VegetationColumns = null
var layout: VegetationLayout = null
## Tanı: cache ("hit"/"miss"/"off"), key_ms, generate_ms, layout_ms, total_ms, error.
var stats: Dictionary = {}

var _task: int = -1
var _settlement: SettlementResult = null
var _species: VegetationSpecies = null
var _rules: VegetationRules = null
var _world: WorldData = null
var _use_cache: bool = true
var _cache_dir_override: String = ""


## Yerleşim sonucu + bitki tablosu + kurallarla işi başlatır. `cache_dir`: boş = `user://cache` (testler geçici dizin
## verir).
static func start(settlement: SettlementResult, species: VegetationSpecies, rules: VegetationRules, world: WorldData,
		blocking: bool = false, use_cache: bool = true, cache_dir: String = "") -> VegetationLoader:
	var loader := VegetationLoader.new()
	loader._settlement = settlement
	loader._species = species
	loader._rules = rules
	loader._world = world
	loader._use_cache = use_cache
	loader._cache_dir_override = cache_dir
	loader.state = State.RUNNING
	if blocking:
		loader._work()
	else:
		loader._task = WorkerThreadPool.add_task(loader._work, false, "vegetation placement")
	return loader


## Hazır mı (görev bittiyse sonucu sahiplenir). Ana iş parçacığında her karede çağrılabilir; ucuz.
func poll() -> bool:
	if state == State.RUNNING and _task >= 0 and WorkerThreadPool.is_task_completed(_task):
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
	return state == State.READY


func is_running() -> bool:
	return state == State.RUNNING


## Görev bitene kadar bekler (kapanış/test).
func wait() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1


## Girdi anahtarı parçaları (önbellek anahtarı). Ana iş parçacığında da iş parçacığında da güvenli (yalnız okur).
static func key_parts(settlement: SettlementResult, species: VegetationSpecies, rules: VegetationRules,
		world: WorldData) -> Dictionary:
	return {
		"seed": VegetationPlacement.default_seed(world),
		"rules_sha": StateHash.of(rules.cfg),
		"species_ids": Array(species.ids),
		"plants_sha": FileAccess.get_sha256("res://data/library/game_plants.json"),
		"world_hash": world.state_hash(),
		"columns_hash": settlement.columns.state_hash(),
		"net_hash": settlement.net.state_hash(),
		"topology_hash": settlement.topology_hash(),
	}


func _work() -> void:
	var t0 := Time.get_ticks_usec()
	var cols: VegetationColumns = null
	var key := ""
	var path := ""
	if _use_cache:
		var tk := Time.get_ticks_usec()
		key = VegetationCache.key_of(key_parts(_settlement, _species, _rules, _world))
		path = VegetationCache.path_for(key)
		if not _cache_dir_override.is_empty():
			path = "%s/%s" % [_cache_dir_override, path.get_file()]
		stats["key_ms"] = snappedf((Time.get_ticks_usec() - tk) / 1000.0, 0.1)
		cols = VegetationCache.load_path(path, key)
	stats["cache"] = "off" if not _use_cache else ("hit" if cols != null else "miss")
	if cols == null:
		var tg := Time.get_ticks_usec()
		cols = VegetationPlacement.generate(_settlement, _species, _rules, VegetationPlacement.default_seed(_world), false)
		stats["generate_ms"] = snappedf((Time.get_ticks_usec() - tg) / 1000.0, 0.1)
		if cols.stats.has("error"):
			stats["error"] = str(cols.stats["error"])
			state = State.FAILED
			return
		if _use_cache and not VegetationCache.save(path, cols, key):
			stats["cache_write"] = "failed"
	var tl := Time.get_ticks_usec()
	var has_proxy := PackedByteArray()
	for i in _species.size():
		has_proxy.append(1 if _species.has_proxy(i) else 0)
	var built := VegetationLayout.build(cols, _world, _species.height_m, has_proxy)
	stats["layout_ms"] = snappedf((Time.get_ticks_usec() - tl) / 1000.0, 0.1)
	stats["total_ms"] = snappedf((Time.get_ticks_usec() - t0) / 1000.0, 0.1)
	columns = cols
	layout = built
	state = State.READY
