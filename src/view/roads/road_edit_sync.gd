class_name RoadEditSync
extends RefCounted
## T-042 adım 3 · Oyuncu yolunun 3B'ye yansıması: `WorldNetwork` delta değişimini (`NetworkChange`) okur ve
## `RoadView`'ın YALNIZ etkilenen 2 km'lik chunk'larını yeniden kurar (uygulama ve geri alma aynı yoldan). Aynı ağ
## verisi okunur (WLD-01): ikinci kopya, sim'e yazma yok.
##
## Maliyet (dev Mac, başsız, gerçek Ismeral ağı 7191 şerit; production/log/2026-10-30-T-042-yol-olcum.md ek notu):
## ilk sürümde tam plan yeniden kurma ~350 ms + chunk meshi ~135 ms = ~500-700 ms tek karede. Bu yüzden (1) plan DEĞİŞİM
## tabanlı güncellenir (`RoadChunkPlan.apply_changes`, O(değişim)), (2) chunk mesh verisi ARKA PLAN iş parçacığında
## hesaplanır (`begin_async` / `poll`), ana iş parçacığı yalnız düğümleri kurar. Arka plan işi sürerken (ve ağ değişmiş
## ama iş başlamamışken) `world_busy()` true döner: playable bunu `PublicWorksContext.busy_probe`a bağlar, yeni yol
## komutu `busy` ile reddedilir; böylece ağ, işçi iş parçacığı okurken değişmez (veri yarışı yok). `sync()` aynı işi
## senkron yapar (dev `--m2-advance` döngüsü, testler).
##
## Etkilenen anahtarlar: planın dokunduğu hücreler (eski+yeni `edge_keys` ve `junction_keys`) ∪ değişimin
## `chunk_keys`i (segment kutuları + kavşak payı). Günlük eksikse (`change_log_covers`) tüm yollar yeniden kurulur.

var stats: Dictionary = {}
## B-020: arka plan işi sürerken ağ sürümü değişen iş sayısı (0 olmalı; bkz. `_check_net_unchanged`).
var mutated_during_job: int = 0

var _net: WorldNetwork = null
var _roads: RoadView = null
var _seen_version: int = 0
var _task: int = -1
var _job: Dictionary = {}
## true: işçi bitti, düğümler `RoadView.step_install` ile kare dilimlerinde kuruluyor (`poll`).
var _installing: bool = false


static func create(net: WorldNetwork, roads: RoadView) -> RoadEditSync:
	var sync := RoadEditSync.new()
	sync._net = net
	sync._roads = roads
	sync._seen_version = net.graph_version
	return sync


## Görünüme henüz yansımamış ağ değişimi var mı (ucuz: bir tamsayı karşılaştırması).
func pending() -> bool:
	return _net != null and _roads != null and _net.graph_version != _seen_version


## Arka plan işi sürüyor mu (işçi hesabı ya da dilimli düğüm kurulumu)?
func is_busy() -> bool:
	return _task >= 0 or _installing


## Ağ, yol görünümü işi yüzünden DEĞİŞTİRİLMEMELİ mi (iş sürüyor ya da başlamayı bekliyor)?
func world_busy() -> bool:
	return is_busy() or pending()


## Bekleyen değişimi görünüme SENKRON yansıtır. Dönüş: {rebuilt, full, ms, keys}; iş yoksa boş.
func sync() -> Dictionary:
	if is_busy():
		return {}
	if not pending():
		return {}
	var started := Time.get_ticks_usec()
	var prep := _prepare()
	if bool(prep["full"]):
		return _finish_full(started)
	_roads.rebuild_chunks(prep["keys"], prep["plan"])
	_seen_version = _net.graph_version
	return _report(prep["keys"], false, started)


## Bekleyen değişim için arka plan işini başlatır (plan güncellemesi ana iş parçacığında ~ms, mesh verisi işçide).
## Tam yeniden kurma gerekirse (günlük eksik) senkron yapılır ve kısa rapor `poll` yerine burada döner.
## Dönüş: true = iş başladı ya da tamamlandı (rapor için `poll`/`take_report`).
func begin_async() -> bool:
	if is_busy() or not pending():
		return false
	var started := Time.get_ticks_usec()
	var prep := _prepare()
	if bool(prep["full"]):
		_job = {"report": _finish_full(started)}
		return true
	var keys: Array[Vector2i] = prep["keys"]
	var plan: RoadChunkPlan = prep["plan"]
	var roads := _roads
	_job = {"keys": keys, "plan": plan, "version": _net.graph_version, "started": started, "meshes": {}}
	var job := _job
	_task = WorkerThreadPool.add_task(func() -> void: job["meshes"] = roads.compute_chunk_data(keys, plan),
			false, "RoadEditSync chunk verisi")
	return true


## Her kare: iş bittiyse düğümleri ana iş parçacığında KARE DİLİMLERİNDE kurar (`RoadView.step_install`, her çağrıda en
## çok `budget_us` + bir chunk) ve kurulum bitince raporu döner (bitmediyse/iş yoksa boş). Kurulum biterken sonraki
## karelerde uzak mesh de dilimli yenilenir (`step_far`; ölçüm: tek yüzeyli tam yenileme ~40 ms tek karede).
## Kurulum sürerken `world_busy()` true kalır (yeni yol komutu `busy` ile reddedilir).
func poll(budget_us: int = RoadView.INSTALL_BUDGET_US) -> Dictionary:
	if _job.has("report"):
		var report: Dictionary = _job["report"]
		_job = {}
		return report
	if not _installing:
		if _task < 0 or not WorkerThreadPool.is_task_completed(_task):
			_roads.step_far(budget_us)
			return {}
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		_check_net_unchanged(int(_job["version"]))
		_roads.begin_install(_job["keys"], _job["plan"], _job["meshes"], int(_job["started"]))
		_installing = true
	if not _roads.step_install(budget_us):
		return {}
	var job := _job
	_job = {}
	_installing = false
	_seen_version = int(job["version"])
	return _report(job["keys"], false, int(job["started"]))


## B-020 · `world_busy()` sözleşmesi: işçi iş parçacığı ağı okurken ağ YAZILMAZ. İş bitince ağ sürümü iş başladığındaki
## ile aynı olmalı; değilse ağı biri meşgulken değiştirmiştir ve işçi, yarı değişmiş ağdan (silinmiş kenar/düğüm
## kimliği: "Out of bounds get index" `road_junction.gd`/`road_mesh_builder.gd`) bozuk ya da eksik mesh verisi
## üretmiş olabilir.
## Sessizce yutulmaz: hata günlüğe düşer ve sayaç `mutated_during_job` artar (sonuç yine de kurulur; ağ
## sürümü farklı kaldığından `pending()` true olur ve sonraki iş değişen bölgeyi yeniden kurar).
func _check_net_unchanged(job_version: int) -> void:
	if _net.graph_version == job_version:
		return
	mutated_during_job += 1
	push_error(mutation_message(job_version, _net.graph_version))


static func mutation_message(job_version: int, now_version: int) -> String:
	return ("RoadEditSync: ağ, yol görünümü arka plan işi sürerken değişti (graph_version %d -> %d); işçi iş parçacığı "
			+ "tutarsız ağ okumuş olabilir. Meşgulken ağa yazan kod (örn. yıkım kuru koşusu) world_busy() sözleşmesini "
			+ "çiğniyor: production/bugs/B-020.md") % [job_version, now_version]


## Tamamlanmasını bekler (testler/kapanış/dev döngüsü): kurulum ve uzak mesh sonuna kadar yürür. İş yoksa boş.
func wait() -> Dictionary:
	# `wait_for_task_completion` görev kimliğini serbest bırakır; sonra `poll`un `is_task_completed`i yanlış okurdu.
	while _task >= 0 and not WorkerThreadPool.is_task_completed(_task):
		OS.delay_msec(1)
	var report := poll(1 << 40)
	_roads.settle_far()
	return report


## Saf birleşim: planın dokunduğu hücreler + değişimlerin `chunk_keys`i (sıralı, tekil).
static func keys_for(changes: Array[NetworkChange], touched: Array[Vector2i], plan: RoadChunkPlan) -> Array[Vector2i]:
	var seen := {}
	for key in touched:
		seen[key] = true
	for change in changes:
		for key in change.chunk_keys(plan.origin, plan.cell_m):
			seen[key] = true
	var out: Array[Vector2i] = []
	for key: Vector2i in seen:
		out.append(key)
	out.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x < b.x or (a.x == b.x and a.y < b.y))
	return out


## {full: bool, keys, plan}: günlük yeterliyse planı yerinde günceller (eski+yeni hücreler `touched`ta toplanır).
func _prepare() -> Dictionary:
	var plan := _roads.plan()
	if plan == null or not _net.change_log_covers(_seen_version):
		return {"full": true}
	var changes := _net.changes_since(_seen_version)
	var touched := plan.apply_changes(_net, _roads.style, changes)
	return {"full": false, "plan": plan, "keys": keys_for(changes, touched, plan)}


func _finish_full(started: int) -> Dictionary:
	_roads.build(_net, _roads.style)
	_seen_version = _net.graph_version
	return _report(_roads.plan().keys(), true, started)


func _report(keys: Array[Vector2i], full: bool, started: int) -> Dictionary:
	var report := {"rebuilt": keys.size(), "full": full, "keys": keys,
			"ms": (Time.get_ticks_usec() - started) / 1000.0}
	var count := int(stats.get("syncs", 0)) + 1
	stats = report.duplicate()
	stats["syncs"] = count
	return report
