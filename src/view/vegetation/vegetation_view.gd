class_name VegetationView
extends Node3D
## B0 bitki sütunları -> dünyada ağaç/çalı/çit (T-062 B1; VIS-01/02/03/05, WLD-01, TEK-03). Sim'den YALNIZ okur
## (VegetationColumns/Layout); simülasyon durumuna yazmaz, sim hash'ine dokunmaz. Tek dünya: her ölçek aynı sütunlardan
## çizer, kademe yalnız temsili değiştirir.
##
## Zincir (T-057 Karar 5, eşikler `data/view/vegetation_view.json`, ÖLÇÜLMEMİŞ çalışma değeri):
##   LOD0 (< 120 m) -> LOD1 (< 400 m) -> [bireysel proxy YOK] -> HÜCRE LEKESİ (blob; 400 m ötesi).
##   Palmiye (kayıtta PROXY'si olan): LOD1 ile palm_proxy_end_m arası 40 üçgenlik PROXY.
## Mesh'ler yalnız `LibraryGate` onaylı oyun tablosundan (`VegetationLook`); onaysız kimlik yüklenmez.
##
## Ağaç düğümleri: kamera çevresindeki 256 m hücreler için `Cell_k` Node3D (hücre köşesinde) -> tür koşusu başına
## kademe MultiMeshInstance3D'ler (LOD0/LOD1/PROXY). Kademe seçimi ÖRNEK BAŞINA kamera uzaklığıyla (visibility_range
## hücre merkezine göre ölçtüğünden 256 m hücrede ±181 m hata verirdi); hücre tümüyle tek kademedeyse tamponlar
## DEĞİŞMEZ (yalnız görünürlük), sınır hücreleri bölünür. Kamera `step_m` kadar hareket edince yeniden hesaplanır
## (her karede 6366 hücre taraması YOK: yalnız kamera çevresindeki ızgara). Kare başına iş tavanı vardır.
## Lekeler: `chunk_cells`² hücrelik parça başına tek birleşik mesh (iş parçacığında kurulur), kamera çevresindeki
## parçalar açılır/kapanır. Leke gölgelendiricisi 400 m'den yakın fragmanı atar (kademe sınırı hücreye bağlı değil).
##
## Kullanım: `setup(look, config)`, `set_layout(layout)`, her karede `track_camera(dünya_konumu)`. `settle()`
## bekleyen işi bitirir (test/yakalama).

signal window_changed(opened: PackedInt32Array, closed: PackedInt32Array)

const SPECIES_META := &"species_id"
const TIER_META := &"tier"
const TRIS_META := &"tris"
const BLOB_SHADER := "res://assets/shaders/mat_vegetation_blob.gdshader"
const TIER_NAMES: Array[String] = ["L0", "L1", "P"]

## Son durum ölçümleri (perf_probe / world_preview okur).
var stats: Dictionary = {}
var config: VegetationViewConfig = null
var look: VegetationLook = null
var layout: VegetationLayout = null
var lod: VegetationLod = VegetationLod.new()

var _cells: Dictionary = {}   # k -> _Cell
var _dirty: Dictionary = {}   # k -> true
var _open_queue: PackedInt32Array = PackedInt32Array()
var _blob_active: Dictionary = {}   # Vector2i -> MeshInstance3D
var _blob_jobs: Dictionary = {}   # Vector2i -> _BlobJob
var _blob_queue: Array[Vector2i] = []
## Koridor maskesi değişen ve YENİ lekesi hazır olana dek eskisi görünür kalan parçalar (Vector2i -> true).
var _blob_replace: Dictionary = {}
## true: sonraki `track_camera` kamera hareket etmese de pencereyi yeniden hesaplar (maske değişti).
var _force_window: bool = false
## Son uygulanan gizli satır kümesi (aynı küme tekrar gelirse iş yapılmaz: işçileri bekletmeyiz).
var _mask_rows: PackedInt32Array = PackedInt32Array()
var _blob_mat: ShaderMaterial = null
var _cam: Vector3 = Vector3.ZERO
var _last_cam: Vector3 = Vector3.ZERO
var _has_cam: bool = false
var _unlimited: bool = false
var _update_ms_total: float = 0.0
var _update_count: int = 0
var _update_ms_max: float = 0.0
var _phase_us: PackedInt64Array = PackedInt64Array([0, 0, 0])


class _Run:
	extends RefCounted
	var species: int = 0
	var lo: int = 0
	var hi: int = 0
	var mmis: Array[MultiMeshInstance3D] = [null, null, null]
	## 1: bu MMI şu an hücrenin TAM (canonical) tamponunu taşıyor.
	var canonical: PackedByteArray = PackedByteArray([0, 0, 0])
	## Son bölünmüş tamponlar (aynıysa GPU'ya yeniden yazılmaz).
	var last: Array[PackedFloat32Array] = [PackedFloat32Array(), PackedFloat32Array(), PackedFloat32Array()]
	## -2: henüz uygulanmadı; VegetationLod.Tier (0..3) tek kademe; VegetationLod.MIXED bölünmüş.
	var tier: int = -2


class _Cell:
	extends RefCounted
	var k: int = 0
	var key: int = 0
	var node: Node3D = null
	var origin: Vector2 = Vector2.ZERO
	var runs: Array[_Run] = []


class _BlobJob:
	extends RefCounted
	var key: Vector2i = Vector2i.ZERO
	var task: int = -1
	var result: Dictionary = {}
	## Ana iş parçacığı yazar (kamera uzaklaştı): sonuç atılır. Çalışan görev `result`a yazar, bu bayrağa yazmaz.
	var stale: bool = false
	## true: görev beklendi (kimlik artık geçersiz; tekrar sorgulanmaz).
	var finished: bool = false

	func join() -> void:
		if not finished and task >= 0:
			WorkerThreadPool.wait_for_task_completion(task)
		finished = true

	func is_done() -> bool:
		return finished or task < 0 or WorkerThreadPool.is_task_completed(task)

	func run(p_layout: VegetationLayout, p_look: VegetationLook, p_config: VegetationViewConfig) -> void:
		result = VegetationBlobBuilder.build_chunk(p_layout, p_look, p_config, key.x, key.y)


## Görünüm tablosu + ayarlarla hazırlar (mevcut içerik silinir). `look` mesh'li ya da (testler) mesh'siz olabilir.
func setup(p_look: VegetationLook, p_config: VegetationViewConfig) -> void:
	clear()
	look = p_look
	config = p_config
	lod = VegetationLod.from_config(p_config)
	_blob_mat = ShaderMaterial.new()
	_blob_mat.resource_name = "mat_vegetation_blob"
	_blob_mat.shader = load(BLOB_SHADER)
	_blob_mat.set_shader_parameter("begin_m", p_config.lod1_end_m)
	_blob_mat.set_shader_parameter("fade_begin_m", p_config.blob_fade_begin_m)
	_blob_mat.set_shader_parameter("end_m", p_config.blob_end_m)


func clear() -> void:
	_join_blob_jobs()
	_blob_jobs.clear()
	_blob_queue.clear()
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_cells.clear()
	_dirty.clear()
	_open_queue = PackedInt32Array()
	_blob_active.clear()
	_blob_replace.clear()
	_force_window = false
	_mask_rows = PackedInt32Array()
	_has_cam = false
	layout = null
	stats = {}


func _exit_tree() -> void:
	_join_blob_jobs()
	_blob_jobs.clear()


func _join_blob_jobs() -> void:
	for job: _BlobJob in _blob_jobs.values():
		job.join()


## Yerleşim + düzeni verir (örnek başına zemin yüksekliği hazır). Önceki içerik silinir.
func set_layout(p_layout: VegetationLayout) -> void:
	var keep_look := look
	var keep_config := config
	clear()
	look = keep_look
	config = keep_config
	layout = p_layout
	stats["instances"] = p_layout.cols.count
	stats["cells_total"] = p_layout.cell_count()


## T-042 · Yeni (oyuncu) yol koridorlarındaki bitkileri gizler/geri getirir (`VegetationCorridor.from_network`).
## Maske her çağrıda BAŞTAN kurulur (geri alınan yolun bitkisi geri gelir). Etkilenen açık hücreler ve leke
## parçaları yerelde yenilenir; sütunlara ve sim'e yazılmaz. Dönüş: maskesi değişen hücre sayısı.
func set_corridors(corridors: Array) -> int:
	if layout == null:
		return 0
	return set_hidden_rows(VegetationCorridor.rows_inside(layout, corridors))


func set_hidden_rows(rows: PackedInt32Array) -> int:
	if layout == null or rows == _mask_rows:
		return 0
	_mask_rows = rows
	# Leke işçileri `layout.hidden`i okur: yazmadan önce hepsi biter (yarış yok).
	# Değişmeyen parçaların sonuçları geçerli kalır.
	_join_blob_jobs()
	var changed := layout.set_hidden(rows)
	stats["hidden_instances"] = layout.hidden_count
	if changed.is_empty():
		return 0
	var cc := config.blob_chunk_cells
	for k in changed:
		var cell: _Cell = _cells.get(k)
		if cell != null:
			for run in cell.runs:
				run.tier = -2
				run.canonical = PackedByteArray([0, 0, 0])
				for t in 3:
					run.last[t] = PackedFloat32Array()
			_dirty[k] = true
		var key := layout.cols.cell_keys[k]
		var chunk := Vector2i(floori(float(layout.cell_cx(key)) / float(cc)), floori(float(layout.cell_cz(key)) / float(cc)))
		var job: _BlobJob = _blob_jobs.get(chunk)
		if job != null:
			job.stale = true   # eski maskeyle kuruldu: atılır, pencere yeniden hesabı yeniden kuyruğa alır
		if _blob_active.has(chunk):
			_blob_replace[chunk] = true
	_force_window = true
	return changed.size()


## Kameranın DÜNYA konumu (view_root yerel; rebasing'den bağımsız). Her karede çağrılır; iş yalnız kamera `step_m`
## hareket edince ya da bekleyen kuyruk varken yapılır.
func track_camera(cam: Vector3) -> void:
	if layout == null or look == null:
		return
	var t0 := Time.get_ticks_usec()
	_cam = cam
	var worked := _poll_blobs()
	var t1 := Time.get_ticks_usec()
	if not _has_cam or _force_window or cam.distance_to(_last_cam) >= config.step_m:
		_force_window = false
		_recompute_window(cam)
		worked = true
	var t2 := Time.get_ticks_usec()
	if not _open_queue.is_empty() or not _dirty.is_empty() or not _blob_queue.is_empty():
		_process_queues()
		worked = true
	var t3 := Time.get_ticks_usec()
	_phase_us[0] += t1 - t0
	_phase_us[1] += t2 - t1
	_phase_us[2] += t3 - t2
	if worked:
		_refresh_stats()   # lekeler arka thread'den geldiğinde de sayaçlar güncel
	if worked:
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		_update_ms_total += ms
		_update_count += 1
		_update_ms_max = maxf(_update_ms_max, ms)
		stats["update_ms_last"] = snappedf(ms, 0.01)
		stats["update_ms_max"] = snappedf(_update_ms_max, 0.01)
		stats["update_ms_avg"] = snappedf(_update_ms_total / float(_update_count), 0.01)
		stats["updates"] = _update_count
		stats["phase_ms_blob_poll"] = snappedf(_phase_us[0] / 1000.0, 0.1)
		stats["phase_ms_window"] = snappedf(_phase_us[1] / 1000.0, 0.1)
		stats["phase_ms_apply"] = snappedf(_phase_us[2] / 1000.0, 0.1)


## Kamera çocuğu olarak ilk karelerde her malzeme/gölge varyantını (LOD0 gölgeli, LOD1, PROXY, leke) bir kez çizdirir:
## gölgelendirici hattı açılışta derlenir, ağaçlar ilk göründüğünde (arka thread yerleşimi hazır olunca) takılma olmaz
## (BuildingView.warm_up kalıbı). Düğümler `frames` kare sonra kendini siler.
func warm_up(camera: Camera3D, frames: int = 3) -> void:
	if look == null or config == null or camera == null or not is_inside_tree():
		return
	var root := Node3D.new()
	root.name = "VegetationWarmup"
	camera.add_child(root)
	var ahead := -(camera.near + 1.0) * 2.0
	var sp := 0
	for i in look.count:
		if look.mesh_lod0[i] != null and look.has_proxy[i] == 0:
			sp = i
			break
	for t in 3:
		var mesh: Mesh = [look.mesh_lod0[sp], look.mesh_lod1[sp], look.mesh_proxy[look.has_proxy.find(1)] \
				if look.has_proxy.has(1) else null][t]
		if mesh == null:
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = 1
		mm.set_instance_transform(0, Transform3D(Basis.from_scale(Vector3.ONE * 0.001), Vector3(0.0, 0.0, ahead)))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if t == 0 \
				else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mmi)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(1, 0, 0)])
	arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.BACK, Vector3.BACK, Vector3.BACK])
	arrays[Mesh.ARRAY_COLOR] = PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE])
	var blob := ArrayMesh.new()
	blob.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.mesh = blob
	mi.material_override = _blob_mat
	mi.scale = Vector3.ONE * 0.001
	mi.position = Vector3(0.0, 0.0, ahead)
	root.add_child(mi)
	for f in frames:
		await get_tree().process_frame
	if is_instance_valid(root):
		root.queue_free()


## Bekleyen tüm işi (hücre açma/kapama, bölme, leke parçaları) bitirir. Testler ve yakalama için.
func settle(max_rounds: int = 400) -> void:
	if layout == null:
		return
	_unlimited = true
	for round_n in max_rounds:
		var pending := not _open_queue.is_empty() or not _dirty.is_empty() or not _blob_queue.is_empty() \
				or not _blob_jobs.is_empty() or _force_window
		if not pending:
			break
		_join_blob_jobs()
		track_camera(_cam)
	_unlimited = false
	_refresh_stats()


## Açık ağaç hücresi anahtarları (artan).
func open_cell_keys() -> PackedInt32Array:
	var out := PackedInt32Array()
	for k: int in _cells:
		out.append(layout.cols.cell_keys[k])
	out.sort()
	return out


func cell_node(key: int) -> Node3D:
	var k := layout.index_of_key(key) if layout != null else -1
	return (_cells[k] as _Cell).node if _cells.has(k) else null


func blob_keys() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for key: Vector2i in _blob_active:
		out.append(key)
	out.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
	return out


func blob_node(key: Vector2i) -> MeshInstance3D:
	return _blob_active.get(key) as MeshInstance3D


## Çizilen (görünür MultiMesh'i olan) DISTINCT bitki kimlikleri, sıralı. Hepsi kapıdan geçmiş kimliklerdir.
func drawn_species_ids() -> PackedStringArray:
	var seen: Dictionary = {}
	for cell: _Cell in _cells.values():
		for run in cell.runs:
			for mmi in run.mmis:
				if mmi != null and mmi.visible:
					seen[str(mmi.get_meta(SPECIES_META))] = true
	var out := PackedStringArray(seen.keys())
	out.sort()
	return out


## Görünür örnek sayısı kademe başına: Vector3i(LOD0, LOD1, PROXY).
func visible_instances() -> Vector3i:
	var n := [0, 0, 0]
	for cell: _Cell in _cells.values():
		for run in cell.runs:
			for t in 3:
				var mmi := run.mmis[t]
				if mmi != null and mmi.visible:
					n[t] += mmi.multimesh.instance_count
	return Vector3i(n[0], n[1], n[2])


## Görünür MultiMesh düğümü (draw call) sayısı.
func visible_mmi_count() -> int:
	var n := 0
	for cell: _Cell in _cells.values():
		for run in cell.runs:
			for mmi in run.mmis:
				if mmi != null and mmi.visible:
					n += 1
	return n


# --- pencere ----------------------------------------------------------------------------------------------------

func _recompute_window(cam: Vector3) -> void:
	_last_cam = cam
	_has_cam = true
	var closed := VegetationWindow.cells_to_close(layout, lod, cam, config.unload_margin_m, _cells)
	for k in closed:
		_close_cell(k)
	var opened := VegetationWindow.cells_to_open(layout, lod, cam, config.load_margin_m, _cells)
	_open_queue = _sorted_by_distance(opened, cam)
	for k: int in _cells:
		_dirty[k] = true
	if config.blob_enabled:
		_recompute_blob_window(cam)
	if not opened.is_empty() or not closed.is_empty():
		window_changed.emit(opened, closed)


func _recompute_blob_window(cam: Vector3) -> void:
	var begin_m := config.lod1_end_m
	var cc := config.blob_chunk_cells
	for key in VegetationWindow.chunks_to_close(layout, cam, begin_m, config.blob_end_m, config.blob_unload_margin_m,
			cc, _blob_active):
		_close_blob(key)
	var wanted := VegetationWindow.chunks_to_open(layout, cam, begin_m, config.blob_end_m, config.blob_load_margin_m,
			cc, _blob_active)
	var fresh: Array[Vector2i] = []
	for key in wanted:
		if not _blob_jobs.has(key):
			fresh.append(key)
	fresh.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return _chunk_distance(a, cam) < _chunk_distance(b, cam) \
				or (_chunk_distance(a, cam) == _chunk_distance(b, cam) and (a.y < b.y or (a.y == b.y and a.x < b.x))))
	for key: Vector2i in _blob_replace:
		if not _blob_jobs.has(key) and not fresh.has(key):
			fresh.append(key)
	_blob_queue = fresh
	# kuyruktaki ama artık gerekmeyen işler (kamera uzaklaştı) düşer; çalışanlar tamamlanınca atılır
	for key: Vector2i in _blob_jobs:
		if not VegetationWindow.chunk_needed(layout, key.x, key.y, cam, begin_m, config.blob_end_m,
				config.blob_unload_margin_m, cc):
			(_blob_jobs[key] as _BlobJob).stale = true


func _chunk_distance(key: Vector2i, cam: Vector3) -> float:
	var box := layout.chunk_box(key.x, key.y, config.blob_chunk_cells)
	return VegetationLod.box_distance_range(cam, box.position, box.end).x


func _sorted_by_distance(ks: PackedInt32Array, cam: Vector3) -> PackedInt32Array:
	var items: Array[Vector2] = []
	for k in ks:
		var box := layout.cell_box(k)
		items.append(Vector2(VegetationLod.box_distance_range(cam, box.position, box.end).x, float(k)))
	items.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x or (a.x == b.x and a.y < b.y))
	var out := PackedInt32Array()
	for it in items:
		out.append(int(it.y))
	return out


# --- iş kuyrukları -----------------------------------------------------------------------------------------------

func _process_queues() -> void:
	var budget := 1 << 30 if _unlimited else config.max_instances_per_frame
	var max_cells := 1 << 30 if _unlimited else config.max_cells_built_per_update
	var built := 0
	while not _open_queue.is_empty() and built < max_cells:
		var k := _open_queue[0]
		_open_queue.remove_at(0)
		if _cells.has(k):
			continue
		_open_cell(k)
		_dirty[k] = true
		built += 1
	if not _dirty.is_empty():
		var order: Array[Vector2] = []
		for k: int in _dirty:
			var box := layout.cell_box(k)
			order.append(Vector2(VegetationLod.box_distance_range(_cam, box.position, box.end).x, float(k)))
		order.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x or (a.x == b.x and a.y < b.y))
		for it in order:
			var k := int(it.y)
			if budget <= 0:
				break
			if not _cells.has(k):
				_dirty.erase(k)
				continue
			budget -= _apply_cell(_cells[k] as _Cell)
			_dirty.erase(k)
	_start_blob_jobs()
	_refresh_stats()


func _open_cell(k: int) -> void:
	var cols := layout.cols
	var cell := _Cell.new()
	cell.k = k
	cell.key = cols.cell_keys[k]
	cell.origin = layout.cell_origin(cell.key)
	cell.node = Node3D.new()
	cell.node.name = "Cell_%d" % cell.key
	cell.node.position = Vector3(cell.origin.x, 0.0, cell.origin.y)
	for v in VegetationCellBuilder.species_runs(cols, k):
		var run := _Run.new()
		run.species = v.x
		run.lo = v.y
		run.hi = v.z
		cell.runs.append(run)
	add_child(cell.node)
	_cells[k] = cell


func _close_cell(k: int) -> void:
	var cell: _Cell = _cells.get(k)
	if cell == null:
		return
	remove_child(cell.node)
	cell.node.queue_free()
	_cells.erase(k)
	_dirty.erase(k)


## Hücrenin her koşusu için kademe uygular. Dönüş: harcanan örnek sayısı (bölme maliyeti).
func _apply_cell(cell: _Cell) -> int:
	var box := layout.cell_box(cell.k)
	var range_m := VegetationLod.box_distance_range(_cam, box.position, box.end)
	var spent := 0
	for run in cell.runs:
		var has_proxy := look.has_proxy[run.species] == 1
		var uniform := lod.uniform_tier(range_m, has_proxy)
		if uniform != VegetationLod.MIXED:
			if run.tier != uniform:
				_show_uniform(cell, run, uniform)
		else:
			spent += run.hi - run.lo
			_show_partition(cell, run, has_proxy)
	return spent


func _show_uniform(cell: _Cell, run: _Run, tier: int) -> void:
	for t in 3:
		if t == tier:
			var mmi := _ensure_mmi(cell, run, t)
			if mmi == null:
				continue
			if run.canonical[t] != 1:
				var buf := VegetationCellBuilder.canonical_buffer(layout, run.lo, run.hi, cell.origin, config.sink_m)
				# koridor maskesi: örnek sayısı hi - lo'dan az olabilir (tampon boyutundan)
				mmi.multimesh.instance_count = floori(float(buf.size()) / float(VegetationCellBuilder.FLOATS_PER_INSTANCE))
				mmi.multimesh.buffer = buf
				run.canonical[t] = 1
			mmi.visible = true
		elif run.mmis[t] != null:
			run.mmis[t].visible = false
	run.tier = tier


func _show_partition(cell: _Cell, run: _Run, has_proxy: bool) -> void:
	var part := VegetationCellBuilder.partition(layout, run.lo, run.hi, cell.origin, config.sink_m, _cam, lod, has_proxy)
	var bufs: Array = part["buffers"]
	var counts: PackedInt32Array = part["counts"]
	for t in 3:
		var buf: PackedFloat32Array = bufs[t]
		if counts[t] == 0:
			if run.mmis[t] != null:
				run.mmis[t].visible = false
			run.last[t] = PackedFloat32Array()
			run.canonical[t] = 0
			continue
		var mmi := _ensure_mmi(cell, run, t)
		if mmi == null:
			continue
		if run.tier != VegetationLod.MIXED or run.canonical[t] == 1 or run.last[t] != buf:
			mmi.multimesh.instance_count = counts[t]
			mmi.multimesh.buffer = buf
			run.last[t] = buf
			run.canonical[t] = 0
		mmi.visible = true
	run.tier = VegetationLod.MIXED


## Kademe MMI'ı yoksa kurar (mesh yoksa null: mesh'siz görünüm testleri). Örnek sayısı çağıranda ayarlanır.
func _ensure_mmi(cell: _Cell, run: _Run, t: int) -> MultiMeshInstance3D:
	if run.mmis[t] != null:
		return run.mmis[t]
	var mesh: Mesh = null
	match t:
		0:
			mesh = look.mesh_lod0[run.species]
		1:
			mesh = look.mesh_lod1[run.species]
		_:
			mesh = look.mesh_proxy[run.species]
	if mesh == null:
		# Mesh yüklenmemiş (başsız mantık testi): boş mesh ile düğüm kurulur, böylece kademe/sayım denetlenebilir.
		mesh = ArrayMesh.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.name = "%s_%s" % [TIER_NAMES[t], look.keys[run.species]]
	mmi.set_meta(SPECIES_META, look.ids[run.species])
	mmi.set_meta(TIER_META, t)
	var casts := config.shadow_lod0 if t == 0 else (config.shadow_lod1 if t == 1 else config.shadow_proxy)
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if casts \
			else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.visible = false
	cell.node.add_child(mmi)
	run.mmis[t] = mmi
	return mmi


# --- leke parçaları ----------------------------------------------------------------------------------------------

func _start_blob_jobs() -> void:
	var max_new := 1 << 30 if _unlimited else config.blob_max_chunks_per_frame
	var started := 0
	while not _blob_queue.is_empty() and started < max_new:
		var key: Vector2i = _blob_queue[0]
		_blob_queue.remove_at(0)
		if (_blob_active.has(key) and not _blob_replace.has(key)) or _blob_jobs.has(key):
			continue
		var job := _BlobJob.new()
		job.key = key
		job.task = WorkerThreadPool.add_task(job.run.bind(layout, look, config), false, "vegetation blob")
		_blob_jobs[key] = job
		started += 1


## Biten iş parçacığı görevlerini yükler. Dönüş: bir şey yapıldı mı.
func _poll_blobs() -> bool:
	var done: Array[Vector2i] = []
	for key: Vector2i in _blob_jobs:
		var job: _BlobJob = _blob_jobs[key]
		if job.is_done():
			done.append(key)
	for key in done:
		var job: _BlobJob = _blob_jobs[key]
		job.join()
		_blob_jobs.erase(key)
		if not job.stale and int(job.result.get("tris", 0)) > 0 \
				and VegetationWindow.chunk_needed(layout, key.x, key.y, _cam, config.lod1_end_m, config.blob_end_m,
				config.blob_unload_margin_m, config.blob_chunk_cells):
			_install_blob(key, job.result)
		elif not job.stale and _blob_replace.has(key):
			_close_blob(key)   # yeni maskeyle parçada çizilecek bitki kalmadı (ya da parça artık gerekmiyor)
		if not job.stale:
			_blob_replace.erase(key)
	return not done.is_empty()


func _install_blob(key: Vector2i, built: Dictionary) -> void:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = built["vertices"]
	arrays[Mesh.ARRAY_NORMAL] = built["normals"]
	arrays[Mesh.ARRAY_COLOR] = built["colors"]
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _blob_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.name = "Blob_%d_%d" % [key.x, key.y]
	mi.set_meta(TRIS_META, int(built["tris"]))
	mi.set_meta(&"clumps", int(built["clumps"]))
	mi.set_meta(&"trees", int(built["trees"]))
	var o := layout.chunk_origin(key.x, key.y, config.blob_chunk_cells)
	mi.position = Vector3(o.x, 0.0, o.y)
	_close_blob(key)   # maske yenilemesi: eskisini değiştirir
	add_child(mi)
	_blob_active[key] = mi


func _close_blob(key: Vector2i) -> void:
	var mi: MeshInstance3D = _blob_active.get(key)
	if mi == null:
		return
	remove_child(mi)
	mi.queue_free()
	_blob_active.erase(key)


func _refresh_stats() -> void:
	var vis := visible_instances()
	stats["cells_open"] = _cells.size()
	stats["lod0_instances"] = vis.x
	stats["lod1_instances"] = vis.y
	stats["proxy_instances"] = vis.z
	stats["tree_mmi_visible"] = visible_mmi_count()
	var blob_tris := 0
	for mi: MeshInstance3D in _blob_active.values():
		blob_tris += int(mi.get_meta(TRIS_META, 0))
	stats["blob_chunks"] = _blob_active.size()
	stats["blob_tris_all"] = blob_tris
	stats["blob_jobs"] = _blob_jobs.size()
	stats["queued"] = _open_queue.size() + _dirty.size() + _blob_queue.size()
	stats["unapproved_ids"] = look.gate.unapproved_ids.size() if look != null and look.gate != null else 0
