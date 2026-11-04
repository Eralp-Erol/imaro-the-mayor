class_name BuildingView
extends Node3D
## BuildingColumns -> dünyada yapılar (T-012; VIS-02/03/04, TEK-03, TEK-05). Sim'den YALNIZ okur (BuildingColumns); sim
## durumuna yazmaz. Tek dünya: tüm ölçekler aynı sütunlardan çizer, LOD yalnız temsili değiştirir (WLD-01).
##
## Düğüm yapısı (WorldView altına eklenir: origin rebasing otomatik, ADR-0002 §2): her hücre (chunk) için `Cell_x_z`
## Node3D (dünya konumunda) -> modül başına LOD0 ve LOD1 MultiMeshInstance3D + `HLOD1` (birleşik PROXY mesh);
## süper-chunk başına `Super_x_z` HLOD2 MeshInstance3D. Kademe aralıkları BuildingLod (margin'li, çakışan).
## T-062 A3: modüller onaylı hero tablosundandır (`BuildingKit`, `LibraryGate`); LOD0 kademesi hero LOD1 mesh'i,
## LOD1 kademesi
## dokulu hero PROXY'dir (hero LOD0 çizilmez). Mesh yüzeyinde modülün atlas materyali vardır (`material_override` YOK).
##
## Veri akışı: `set_columns(cols, version)` -> doğrula -> chunk planı -> hücre özetleri -> yalnız DEĞİŞEN hücreler
## (ve içerdikleri süper-chunk'lar) yeniden kurulur. Mesh VERİSİ iş parçacıklarında (BuildingChunkBuilder, saf);
## MultiMesh/ArrayMesh/düğüm kurulumu ana iş parçacığında. Yükseklik `WorldData.height_at`'ten (BuildingGround).
##
## Kaynak: `set_columns()` parametresi; gerçek üretici (`T0Settlement.generate`) ve sim projector'ı AYNI
## `BuildingColumns`
## türünü verir.

signal cells_rebuilt(keys: Array)

const SUPER_PREFIX := "Super_"
## Gizleme/geri koymada eşzamanlı arka plan mesh işi sayısı (`pump_pending`).
const MAX_TASKS := 2
## Dilimli kurulumda HLOD1 mesh'inin tek yüzeyi en çok bu kadar köşe (~3 ms); büyük hücrede birden çok yüzey = birden
## çok draw call (yalnız artımlı yeniden kurulan hücrelerde; ilk kurulum/`set_columns` tek yüzeydir).
const HLOD1_SLICE_VERTS := 30000
const TRIS_META := &"tris"
## MultiMeshInstance3D üstünde modül kimliği (onaylı kimlik denetimi/test için; `drawn_module_ids`).
const MODULE_META := &"module_id"
## Bina farkında göz açıklığı kaynağı (ADR-0007 Ek c): kamera rig'i enjekte edilmediyse bu gruptan bulur.
const ROOF_SOURCE_GROUP := &"eye_roof_clearance_source"

## Son kurulumun ölçümleri (perf_probe / world_preview okur).
var stats: Dictionary = {}
var config: BuildingViewConfig = BuildingViewConfig.new()
## Dilimli kurulumda HLOD1 yüzey boyu (testler küçültür; varsayılan `HLOD1_SLICE_VERTS`; 3'ün katı olmalı).
var hlod1_slice_verts: int = HLOD1_SLICE_VERTS

var _world: WorldData = null
var _kit: BuildingKit = null
var _cols: BuildingColumns = null
var _plan: BuildingChunkPlan = null
var _hashes: Dictionary = {}
var _version: int = -1
var _cell_nodes: Dictionary = {}
var _cell_data: Dictionary = {}
var _dropped: Dictionary = {}
var _super_nodes: Dictionary = {}
var _proxy_mat: ShaderMaterial = null
## T-042b: parsel kimliğiyle gizlenen satırlar (kamulaştırma) ve dilimli yeniden kurulum kuyruğu.
var _mask: BuildingParcelMask = BuildingParcelMask.new()
var _pend_cells: Dictionary = {}
var _pend_supers: Dictionary = {}
var _tasks: Array[Dictionary] = []
## Kare dilimli hücre kurulumu (yol onayı sonrası ölçüm, Intel Mac: tek hücre kurulumu 12-19 ms; modül başına ~0,15 ms,
## HLOD1 mesh'i ~0,1 ms/1000 köşe ve tek yüzeyde bölünmez): {data, cell: Node3D (henüz ağaçta DEĞİL), n: sıradaki birim,
## sliced: HLOD1 yüzeylere bölünür mü, hl_mesh}. Birimler: önce modüller, sonra HLOD1 yüzey dilimleri. Eski hücre yalnız
## BİTİŞTE yer değiştirir (görünüm kareler arasında yarım kalmaz); boşsa iş yok.
var _cell_partial: Dictionary = {}
## `pump_pending` çağrısında ilerleyen iş birimi sayısı (modül, HLOD1 dilimi, süper-chunk, boş hücre).
var _units: int = 0
## Kameranın göz açıklığı için çatı yükseklik dizini (aynı sütunlardan; `set_columns` yeniler, aynı nesne kalır).
var _roofs: RoofClearance = RoofClearance.new()
# iş parçacığı görev girdileri (set_columns sırasında geçerli)
var _job_keys: Array[Vector2i] = []
var _job_cells: Array[BuildingCellData] = []


## Dünya + kit ile hazırlar (mevcut içerik silinir).
func setup(world: WorldData, kit: BuildingKit, p_config: BuildingViewConfig = null) -> void:
	clear()
	_world = world
	_kit = kit
	add_to_group(ROOF_SOURCE_GROUP)
	if p_config != null:
		config = p_config
	_proxy_mat = HeroMeshLoader.flat_color_material()


func clear() -> void:
	_drain_tasks()
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_cell_nodes.clear()
	_cell_data.clear()
	_dropped.clear()
	_super_nodes.clear()
	_hashes = {}
	_plan = null
	_cols = null
	_version = -1
	_roofs.clear()
	_mask = BuildingParcelMask.new()
	_pend_cells.clear()
	_pend_supers.clear()
	stats = {}


## Sütunları gösterir. Yalnız içeriği değişen hücreler yeniden kurulur. `version` >= 0 ve önceki çağrıyla aynı
## (aynı nesne) ise hiçbir şey yapılmaz. Dönüş raporu: {ok, errors, skipped, cells, rebuilt, supers_rebuilt, ...}.
func set_columns(cols: BuildingColumns, version: int = -1) -> Dictionary:
	if _world == null or _kit == null:
		return {"ok": false, "errors": ["BuildingView.setup() çağrılmadı"]}
	var errs := BuildingInputCheck.errors(cols, _kit.count)
	if not errs.is_empty():
		stats["rejected_errors"] = Array(errs)   # günlük çağırana ait; görüntü değişmez
		return {"ok": false, "errors": Array(errs)}
	if version >= 0 and version == _version and cols == _cols:
		return {"ok": true, "skipped": true, "rebuilt": 0, "cells": _cell_nodes.size()}
	var t0 := Time.get_ticks_usec()
	var new_plan := BuildingChunkPlan.build(cols, _world.origin, config.cell_m, config.super_cells)
	_drain_tasks()
	_mask.apply_all(new_plan, cols)
	_pend_cells.clear()
	_pend_supers.clear()
	var new_hashes := new_plan.cell_hashes(cols)
	var changed := BuildingChunkPlan.changed_cells(_hashes, new_hashes)
	var t1 := Time.get_ticks_usec()
	_cols = cols
	_plan = new_plan
	_version = version
	var tr0 := Time.get_ticks_usec()
	_roofs.set_from_columns(_world, cols, _kit)
	stats["roof_index_ms"] = snappedf((Time.get_ticks_usec() - tr0) / 1000.0, 0.1)
	for pid: int in _mask.hidden:
		for r in _mask.rows_of(pid):
			_roofs.set_enabled_at(cols.x[r], cols.z[r], false)
	# değişmeyen hücrelerin sütun indeksleri yeni plana bağlanır
	for k: Vector2i in _cell_data:
		if new_hashes.has(k) and _hashes.get(k, "") == new_hashes[k]:
			(_cell_data[k] as BuildingCellData).rebind(new_plan)
	_hashes = new_hashes
	var supers := _rebuild_cells(changed)
	var t2 := Time.get_ticks_usec()
	_refresh_stats()
	stats["last_plan_ms"] = snappedf((t1 - t0) / 1000.0, 0.1)
	stats["last_build_ms"] = snappedf((t2 - t1) / 1000.0, 0.1)
	stats["last_rebuilt_cells"] = changed.size()
	cells_rebuilt.emit(changed)
	return {"ok": true, "skipped": false, "cells": new_plan.cells.size(), "rebuilt": changed.size(),
			"rebuilt_keys": changed, "supers_rebuilt": supers.size(), "plan_ms": stats["last_plan_ms"],
			"build_ms": stats["last_build_ms"], "errors": []}


## Çatı yükseklik sağlayıcısı (kamera göz açıklığı). Nesne ömür boyu aynıdır; içeriği `set_columns` ile yenilenir.
func roof_clearance() -> RoofClearance:
	return _roofs


## Yükseklik: görünümün kullandığı veri (WorldData.height_at; arazi mesh'i ile aynı kaynak).
func height_at(x: float, z: float) -> float:
	return _world.height_at(x, z) if _world != null else 0.0


## Çizilen (MultiMesh düğümü kurulan) DISTINCT modül kimlikleri, sıralı. Hepsi kapıdan geçmiş kimliklerdir.
func drawn_module_ids() -> PackedStringArray:
	var seen: Dictionary = {}
	for k: Vector2i in _cell_nodes:
		for child in (_cell_nodes[k] as Node3D).get_children():
			if child is MultiMeshInstance3D and child.has_meta(MODULE_META):
				seen[str(child.get_meta(MODULE_META))] = true
	var out := PackedStringArray(seen.keys())
	out.sort()
	return out


func building_count() -> int:
	return _cols.count - _mask.rows_hidden if _cols != null else 0


func plan() -> BuildingChunkPlan:
	return _plan


func cell_keys() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for k: Vector2i in _cell_nodes:
		out.append(k)
	out.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x < b.x or (a.x == b.x and a.y < b.y))
	return out


func cell_node(key: Vector2i) -> Node3D:
	return _cell_nodes.get(key) as Node3D


func super_node(skey: Vector2i) -> MeshInstance3D:
	return _super_nodes.get(skey) as MeshInstance3D


func super_keys() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for k: Vector2i in _super_nodes:
		out.append(k)
	return out


func cell_summary(key: Vector2i) -> BuildingCellData:
	return _cell_data.get(key) as BuildingCellData


## Kamera çocuğu olarak ilk karelerde her gölge/malzeme varyantını çizdirir: shader/gölge hattı açılışta derlenir,
## ilk yakınlaşmada ~0,5 sn takılmaz (T-003 ölçüm bulgusu). Düğümler `frames` kare sonra kendini siler.
func warm_up(camera: Camera3D, frames: int = 3) -> void:
	if _kit == null or camera == null or not is_inside_tree():
		return
	var root := Node3D.new()
	root.name = "BuildingWarmup"
	camera.add_child(root)
	var ahead := -(camera.near + 1.0) * 2.0
	for m in _kit.count:
		if _kit.kinds[m] != "building" or not _kit.has_mid[m] == 1:
			continue
		for tier in [BuildingLod.Tier.LOD0, BuildingLod.Tier.LOD1]:
			var mesh := _kit.tier_mesh(m, tier)
			if mesh == null:
				continue
			var mmi := _make_mmi(mesh, 1)
			mmi.multimesh.set_instance_transform(0, Transform3D(Basis.from_scale(Vector3.ONE * 0.001),
					Vector3(0.0, 0.0, ahead)))
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if tier == BuildingLod.Tier.LOD0 \
					else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(mmi)
		break
	var mi := _make_mesh_instance(PackedVector3Array([Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(1, 0, 0)]),
			PackedVector3Array([Vector3.BACK, Vector3.BACK, Vector3.BACK]),
			PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE]))
	mi.scale = Vector3.ONE * 0.001
	mi.position = Vector3(0.0, 0.0, ahead)
	root.add_child(mi)
	for f in frames:
		await get_tree().process_frame
	if is_instance_valid(root):
		root.queue_free()


## T-042b · Kamulaştırma: parsellerin yapı satırlarını gizler (`hide = true`) ya da geri koyar. Sütunlar ve sim
## DEĞİŞMEZ.
## Plan/özet yalnız etkilenen hücrelerde yenilenir; hücre/süper-chunk yeniden kurulumu KUYRUĞA girer ve `pump_pending`
## ile karelere dilimlenir (tek karede yüzlerce ms olmasın). Çatı dizini (göz açıklığı) hemen güncellenir.
## Dönüş: {ok, rows, cells (özeti değişen hücre sayısı), ms}.
func set_parcels_hidden(ids: PackedInt32Array, hide: bool) -> Dictionary:
	if _plan == null or _cols == null:
		return {"ok": false, "errors": ["set_columns çağrılmadı"]}
	var t0 := Time.get_ticks_usec()
	var res := _mask.set_hidden(_plan, _cols, ids, hide)
	var rows: PackedInt32Array = res["rows"]
	for r in rows:
		_roofs.set_enabled_at(_cols.x[r], _cols.z[r], not hide)
	var queued := 0
	for key: Vector2i in res["cells"]:
		var old: String = _hashes.get(key, "")
		var fresh := _plan.cell_hash(_cols, key) if _plan.cells.has(key) else ""
		if fresh == old:
			continue
		if fresh.is_empty():
			_hashes.erase(key)
		else:
			_hashes[key] = fresh
		_pend_cells[key] = true
		queued += 1
	return {"ok": true, "rows": rows.size(), "cells": queued, "ms": (Time.get_ticks_usec() - t0) / 1000.0}


## parsel -> satır dizinini önceden kurar (ilk gizlemede ~10 ms takılma olmasın).
func prepare_parcel_index() -> void:
	if _cols != null:
		_mask.index(_cols)


## Bekleyen (kuyrukta ya da arka planda hesaplanan) hücre/süper-chunk işi var mı (adet)?
func pending_work() -> int:
	return _pend_cells.size() + _pend_supers.size() + _tasks.size() + (0 if _cell_partial.is_empty() else 1)


## Kuyruktaki hücre ve süper-chunk işini yürütür: mesh VERİSİ (`BuildingChunkBuilder`, `BuildingHlod2`; saf) arka plan
## iş
## parçacığında (en çok `MAX_TASKS`) hesaplanır, ana iş parçacığı yalnız biten işin düğümlerini kurar. Her kurulum
## sonrası
## `budget_us` aşıldıysa durur (en az bir kurulum ilerler). Süper-chunk işi, hücre işi bitince başlar (hücre verisini
## okur). `use_threads = false` ise satır içi çalışır (testler). Dönüş: {done: biten hücre/süper-chunk, units:
## ilerleyen iş birimi (modül/HLOD1 dilimi dahil), left: kalan, ms}.
func pump_pending(budget_us: int) -> Dictionary:
	var t0 := Time.get_ticks_usec()
	var done := 0
	_units = 0
	var keys: Array[Vector2i] = []
	_start_tasks()
	var worked := false
	if not _cell_partial.is_empty():
		worked = true
		done += _advance_partial(budget_us, t0, keys)
	var i := 0
	while i < _tasks.size():
		if not _cell_partial.is_empty():
			break   # bir hücre yarım: bu çağrıda yeni birim başlamaz
		if worked and Time.get_ticks_usec() - t0 >= budget_us:
			break
		var job: Dictionary = _tasks[i]
		if job["id"] >= 0 and not WorkerThreadPool.is_task_completed(job["id"]):
			i += 1
			continue
		if job["id"] >= 0:
			WorkerThreadPool.wait_for_task_completion(job["id"])
		_tasks.remove_at(i)
		var t_inst := Time.get_ticks_usec()
		if job["kind"] == "cell":
			_cell_partial = _begin_cell(job["out"] as BuildingCellData, true)
			if _cell_partial.is_empty():
				keys.append(job["key"])   # hücredeki her yapı atıldı: düğüm yok, kurulum bitti
				done += 1
				_units += 1
			else:
				done += _advance_partial(budget_us, t0, keys)
		else:
			_install_super(job["key"], job["out"] as Dictionary)
			done += 1
			_units += 1
		worked = true
		var inst_ms := (Time.get_ticks_usec() - t_inst) / 1000.0
		stats["mask_install_max_ms"] = snappedf(maxf(float(stats.get("mask_install_max_ms", 0.0)), inst_ms), 0.01)
		stats["mask_build_max_ms"] = snappedf(maxf(float(stats.get("mask_build_max_ms", 0.0)), float(job["ms"])), 0.01)
		_start_tasks()
	if done > 0:
		if pending_work() == 0:
			_refresh_stats()   # tüm hücreleri gezer (~3 ms): yalnız iş bitince, kare dilimini şişirmesin
		cells_rebuilt.emit(keys)
	return {"done": done, "units": _units, "left": pending_work(), "ms": (Time.get_ticks_usec() - t0) / 1000.0}


## Yarım hücreyi bütçe dolana kadar (en az bir modül) ilerletir; biterse 1, bitmezse 0 döner.
func _advance_partial(budget_us: int, t0: int, keys: Array[Vector2i]) -> int:
	var data: BuildingCellData = _cell_partial["data"]
	var finished := _step_cell(_cell_partial, budget_us, t0)
	if not finished:
		return 0
	keys.append(data.key)
	_cell_partial = {}
	return 1


## Boş kalan tüm işçi yuvalarını doldurur (önce hücreler; süper-chunk'lar hücre işi bitince).
func _start_tasks() -> void:
	while _tasks.size() < MAX_TASKS and not _pend_cells.is_empty():
		var k: Vector2i = _pend_cells.keys()[0]
		_pend_cells.erase(k)
		_pend_supers[_plan.super_of(k)] = true
		if not _plan.cells.has(k):
			_remove_cell(k)   # hücredeki son yapı gizlendi
			continue
		var one := BuildingChunkPlan.new()
		one.cell_m = _plan.cell_m
		one.super_cells = _plan.super_cells
		one.origin = _plan.origin
		one.cells = {k: _plan.indices(k)}
		var cols := _cols
		var kit := _kit
		var world := _world
		var cfg := config
		_spawn(k, "cell", func() -> Variant: return BuildingChunkBuilder.build_cell(cols, one, k, kit, world, cfg))
	if not _pend_cells.is_empty() or _has_task_kind("cell") or not _cell_partial.is_empty():
		return
	while _tasks.size() < MAX_TASKS and not _pend_supers.is_empty():
		var sk: Vector2i = _pend_supers.keys()[0]
		_pend_supers.erase(sk)
		if not config.build_hlod2:
			continue
		var members: Array = []
		for ck in _plan.super_groups().get(sk, []):
			if _cell_data.has(ck):
				members.append(_cell_data[ck])
		var cols2 := _cols
		var kit2 := _kit
		var cfg2 := config
		var origin := _plan.super_origin(sk)
		_spawn(sk, "super", func() -> Variant: return BuildingHlod2.build(members, cols2, kit2, cfg2, origin))


## Çalışan arka plan işlerini bekler ve sonuçlarını atar (yeniden kurulum / temizlik öncesi).
func _drain_tasks() -> void:
	for job: Dictionary in _tasks:
		if job["id"] >= 0:
			WorkerThreadPool.wait_for_task_completion(job["id"])
	_tasks.clear()
	_drop_partial()


func _drop_partial() -> void:
	if not _cell_partial.is_empty():
		(_cell_partial["cell"] as Node).free()
		_cell_partial = {}


func _has_task_kind(kind: String) -> bool:
	for job: Dictionary in _tasks:
		if job["kind"] == kind:
			return true
	return false


func _spawn(key: Vector2i, kind: String, work: Callable) -> void:
	var job := {"key": key, "kind": kind, "out": null, "id": -1, "ms": 0.0}
	var run := func() -> void:
		var t := Time.get_ticks_usec()
		job["out"] = work.call()
		job["ms"] = (Time.get_ticks_usec() - t) / 1000.0
	if config.use_threads:
		job["id"] = WorkerThreadPool.add_task(run, false, "building mask %s" % kind)
	else:
		run.call()
	_tasks.append(job)


# --- özel -----------------------------------------------------------------------------------------------------

## Verilen hücreleri (ve içerdikleri süper-chunk'ları) kurar; silinen hücrelerin düğümlerini kaldırır.
## Dönüş: yeniden kurulan süper-chunk anahtarları.
func _rebuild_cells(changed: Array[Vector2i]) -> Array[Vector2i]:
	var affected_supers: Dictionary = {}
	var to_build: Array[Vector2i] = []
	for k in changed:
		affected_supers[_plan.super_of(k)] = true
		if _plan.cells.has(k):
			to_build.append(k)
		else:
			_remove_cell(k)
	_job_keys = to_build
	_job_cells = []
	_job_cells.resize(to_build.size())
	if config.use_threads and to_build.size() > 1:
		var group := WorkerThreadPool.add_group_task(_cell_task, to_build.size(), -1, true, "building cells")
		WorkerThreadPool.wait_for_group_task_completion(group)
	else:
		for n in to_build.size():
			_cell_task(n)
	for n in to_build.size():
		_install_cell(_job_cells[n])
	_job_cells = []
	_job_keys = []
	var supers: Array[Vector2i] = []
	for sk: Vector2i in affected_supers:
		supers.append(sk)
	supers.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x < b.x or (a.x == b.x and a.y < b.y))
	if config.build_hlod2:
		_rebuild_supers(supers)
	return supers


func _cell_task(n: int) -> void:
	_job_cells[n] = BuildingChunkBuilder.build_cell(_cols, _plan, _job_keys[n], _kit, _world, config)


func _rebuild_supers(supers: Array[Vector2i]) -> void:
	# süper-chunk -> hücreler eşlemesi her görevde yeniden hesaplanmasın (salt okunur önbellek)
	var groups := _plan.super_groups()
	var members_by_super: Array = []
	for sk in supers:
		var members: Array = []
		for k in groups.get(sk, []):
			if _cell_data.has(k):
				members.append(_cell_data[k])
		members_by_super.append(members)
	var results: Array = []
	results.resize(supers.size())
	var task := func(n: int) -> void:
		results[n] = BuildingHlod2.build(members_by_super[n], _cols, _kit, config, _plan.super_origin(supers[n]))
	if config.use_threads and supers.size() > 1:
		var group := WorkerThreadPool.add_group_task(task, supers.size(), -1, true, "building hlod2")
		WorkerThreadPool.wait_for_group_task_completion(group)
	else:
		for n in supers.size():
			task.call(n)
	for n in supers.size():
		_install_super(supers[n], results[n] as Dictionary)


func _remove_cell(key: Vector2i) -> void:
	if not _cell_partial.is_empty() and (_cell_partial["data"] as BuildingCellData).key == key:
		_drop_partial()   # yarım kurulan hücre artık gereksiz (içindeki her yapı gizlendi)
	var node: Node = _cell_nodes.get(key)
	if node != null:
		remove_child(node)
		node.queue_free()
	_cell_nodes.erase(key)
	_cell_data.erase(key)
	_dropped.erase(key)


## Senkron hücre kurulumu (tam yeniden kurma yolu): dilimli sürümün tek çağrıda bitmişi.
func _install_cell(data: BuildingCellData) -> void:
	var part := _begin_cell(data)
	if not part.is_empty():
		_step_cell(part, 1 << 40, Time.get_ticks_usec())


## Hücre kurulumunu başlatır: eski hücre YERİNDE kalır; yeni düğüm ağaç dışında modül modül kurulur. Her yapı atılmışsa
## (su) eski düğüm hemen kalkar ve boş sözlük döner.
func _begin_cell(data: BuildingCellData, sliced: bool = false) -> Dictionary:
	_dropped[data.key] = data.dropped
	if data.kept.is_empty():   # hücredeki her yapı atıldı (su): düğüm yok
		var old: Node = _cell_nodes.get(data.key)
		if old != null:
			remove_child(old)
			old.queue_free()
			_cell_nodes.erase(data.key)
		_cell_data.erase(data.key)
		return {}
	var cell := Node3D.new()
	cell.name = "Cell_%d_%d" % [data.key.x, data.key.y]
	cell.position = Vector3(data.origin.x, 0.0, data.origin.y)
	return {"data": data, "cell": cell, "n": 0, "sliced": sliced, "hl_mesh": null}


## Yarım hücreyi ilerletir (birim başına bütçe denetimi, en az bir birim); true = hücre kuruldu ve eskisinin
## yerine geçti.
func _step_cell(part: Dictionary, budget_us: int, t0: int) -> bool:
	var data: BuildingCellData = part["data"]
	var cell: Node3D = part["cell"]
	var n: int = part["n"]
	var modules := data.modules.size()
	var units := modules + _hlod1_slices(data, bool(part["sliced"]))
	var first := n
	while n < units:
		if n > first and Time.get_ticks_usec() - t0 >= budget_us:
			part["n"] = n
			_units += n - first
			return false
		if n < modules:
			_add_cell_module(cell, data, n)
		else:
			_add_hlod1_slice(part, data, n - modules)
		n += 1
	part["n"] = n
	_units += maxi(n - first, 1)
	if part["hl_mesh"] != null:
		var mi := _mesh_instance_of(part["hl_mesh"] as ArrayMesh, data.hlod1_vertices.size() / 3)
		mi.name = "HLOD1"
		config.lod.apply(mi, BuildingLod.Tier.HLOD1)
		cell.add_child(mi)
	var old: Node = _cell_nodes.get(data.key)
	if old != null:
		remove_child(old)
		old.queue_free()
		_cell_nodes.erase(data.key)
	add_child(cell)
	_cell_nodes[data.key] = cell
	data.release_geometry()
	_cell_data[data.key] = data
	return true


## HLOD1 mesh'i kaç yüzey dilimi (0 = HLOD1 yok). Bölünmeyen (senkron) kurulumda tek yüzey.
func _hlod1_slices(data: BuildingCellData, sliced: bool) -> int:
	if not config.build_hlod1 or data.hlod1_vertices.size() == 0:
		return 0
	return ceili(float(data.hlod1_vertices.size()) / float(_slice_size(data.hlod1_vertices.size()))) if sliced else 1


## Dilim başına köşe: `hlod1_slice_verts`, ama bir mesh'te en çok 256 yüzey olabilir (200'le sınırlı), 3'ün katı.
func _slice_size(total: int) -> int:
	return maxi(hlod1_slice_verts, ceili(float(total) / 200.0 / 3.0) * 3)


func _add_hlod1_slice(part: Dictionary, data: BuildingCellData, index: int) -> void:
	if part["hl_mesh"] == null:
		part["hl_mesh"] = ArrayMesh.new()
	var verts := data.hlod1_vertices
	var lo := 0
	var hi := verts.size()
	if bool(part["sliced"]):
		var size := _slice_size(verts.size())
		lo = index * size
		hi = mini(lo + size, verts.size())
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts.slice(lo, hi)
	arrays[Mesh.ARRAY_NORMAL] = data.hlod1_normals.slice(lo, hi)
	arrays[Mesh.ARRAY_COLOR] = data.hlod1_colors.slice(lo, hi)
	(part["hl_mesh"] as ArrayMesh).add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)


func _add_cell_module(cell: Node3D, data: BuildingCellData, n: int) -> void:
	var m := data.modules[n]
	var count := data.counts[n]
	var casts := config.cast_shadows
	var lod1_caster := casts and config.shadow_caster_lod == 1 and _kit.has_mid[m] == 1
	if config.build_lod0:
		var mesh0 := _kit.tier_mesh(m, BuildingLod.Tier.LOD0)
		if mesh0 != null:
			var mmi0 := _make_mmi(mesh0, count)
			mmi0.set_meta(MODULE_META, _kit.ids[m])
			mmi0.multimesh.buffer = data.buffers[n]
			mmi0.name = "L0_%s" % _kit.ids[m]
			mmi0.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if casts and not lod1_caster \
					else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			config.lod.apply(mmi0, BuildingLod.Tier.LOD0)
			cell.add_child(mmi0)
	if (config.build_lod1 or lod1_caster) and _kit.has_mid[m] == 1:
		var mesh1 := _kit.tier_mesh(m, BuildingLod.Tier.LOD1)
		if mesh1 != null:
			var mmi1 := _make_mmi(mesh1, count)
			mmi1.set_meta(MODULE_META, _kit.ids[m])
			mmi1.multimesh.buffer = data.buffers[n]
			if config.build_lod1:
				mmi1.name = "L1_%s" % _kit.ids[m]
				mmi1.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON \
						if casts and config.lod1_casts_shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				config.lod.apply(mmi1, BuildingLod.Tier.LOD1)
				cell.add_child(mmi1)
			if lod1_caster:
				# yalnız-gölge: aynı MultiMesh (hero PROXY mesh'i), LOD0 menzilinde; görsel düğüm değil
				var caster := MultiMeshInstance3D.new()
				caster.multimesh = mmi1.multimesh
				caster.set_meta(MODULE_META, _kit.ids[m])
				caster.name = "S1_%s" % _kit.ids[m]
				caster.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
				# K8 görsel LOD0 menzilinden ayrı: gölgeler 700 m'de biter.
				caster.visibility_range_end = config.shadow_end_m
				caster.visibility_range_end_margin = config.lod.lod0_margin_m
				cell.add_child(caster)
			if not config.build_lod1:
				mmi1.free()   # yalnız MultiMesh kaynağı lazımdı (caster tutuyor)


func _install_super(skey: Vector2i, result: Dictionary) -> void:
	var old: Node = _super_nodes.get(skey)
	if old != null:
		remove_child(old)
		old.queue_free()
		_super_nodes.erase(skey)
	if result.is_empty():
		return
	var mi := _make_mesh_instance(result["vertices"], result["normals"], result["colors"])
	mi.name = "%s%d_%d" % [SUPER_PREFIX, skey.x, skey.y]
	var so := _plan.super_origin(skey)
	mi.position = Vector3(so.x, 0.0, so.y)
	config.lod.apply(mi, BuildingLod.Tier.HLOD2)
	mi.set_meta(&"boxes", int(result["boxes"]))
	add_child(mi)
	_super_nodes[skey] = mi


func _make_mmi(mesh: Mesh, count: int) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = count
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	return mmi


func _make_mesh_instance(verts: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray) \
		-> MeshInstance3D:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return _mesh_instance_of(mesh, verts.size() / 3)


func _mesh_instance_of(mesh: ArrayMesh, tris: int) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _proxy_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.set_meta(TRIS_META, tris)
	return mi


func _refresh_stats() -> void:
	var kept := 0
	var dropped := 0
	var lod0 := 0
	var lod1 := 0
	for k: Vector2i in _cell_data:
		var d: BuildingCellData = _cell_data[k]
		kept += d.kept.size()
		lod0 += d.lod0_tris
		lod1 += d.lod1_tris
	var mmis := 0
	var hlod1_nodes := 0
	var hlod1_tris := 0
	for k: Vector2i in _cell_nodes:
		for child in (_cell_nodes[k] as Node3D).get_children():
			if child is MultiMeshInstance3D:
				mmis += 1
			elif child is MeshInstance3D:
				hlod1_nodes += 1
				hlod1_tris += int(child.get_meta(TRIS_META, 0))
	for k: Vector2i in _dropped:
		dropped += int(_dropped[k])
	var hlod2_tris := 0
	for k: Vector2i in _super_nodes:
		hlod2_tris += int((_super_nodes[k] as MeshInstance3D).get_meta(TRIS_META, 0))
	stats["buildings"] = _cols.count if _cols != null else 0
	stats["approved_modules"] = _kit.count
	stats["unapproved_ids"] = _kit.gate.unapproved_ids.size()
	stats["drawn"] = kept
	stats["dropped_water"] = dropped
	stats["cells"] = _cell_nodes.size()
	stats["supers"] = _super_nodes.size()
	stats["mmi_nodes"] = mmis
	stats["hlod1_nodes"] = hlod1_nodes
	stats["lod0_tris_all"] = lod0
	stats["lod1_tris_all"] = lod1
	stats["hlod1_tris_all"] = hlod1_tris
	stats["hlod2_tris_all"] = hlod2_tris
