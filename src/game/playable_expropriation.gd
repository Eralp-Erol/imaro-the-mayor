class_name PlayableExpropriation
extends RefCounted
## T-042b OYUN KATMANI (CAN-03, WLD-01, D-011): kamulaştırmalı yolun oyunda görünür hale gelmesi. İki iş:
## (1) KURULUM (`attach_port`): sim yol bağlamına gerçek dünya köprüsü (`NetworkExpropriationPort`) ve T0'ın korunan
##     (tarihî/simge/kamu) parselleri takılır. Köprü kayıt yüklemede de takılı olmalı (yoksa `network_mismatch`).
## (2) TAKİP (örnek): ağın parsel kümesi değişince (uygulama: parseller dünyadan ÇIKAR; geri alma: kimlikleriyle GERİ
##     GELİR) T0 yapıları görünümde gizlenir/geri gelir, kent zemini maskesi yerelde yenilenir. Kaynak yalnız dünya
##     verisidir (`net.parcels`): alınan T0 parseli = ağda artık olmayan parsel. Değişim günlüğü (`changes_since`) varsa
##     yalnız ilgili kimlikler yoklanır; günlük eksikse (yükleme/uzun boşluk) T0'ın tüm parselleri bir kez eşitlenir.
## Sim durumuna YAZMAZ; sim yapıları (projector) alınan parseli `development == taken` ile zaten satırsız çizer.
## Kare payı: gizleme anında yalnız plan/özet süzülür (ms); hücre/süper-chunk kurulumu `BuildingView.pump_pending` ile
## `BUDGET_US` dilimlerine bölünür.

## Kamulaştırılamayan T0 yapı bayrakları (WLD-09; Q-017 cevabına dek muhafazakâr: ret).
const PROTECT_FLAGS := BuildingColumns.FLAG_HERITAGE | BuildingColumns.FLAG_LANDMARK | BuildingColumns.FLAG_CIVIC
## Kare başına görünüm kurulumu dilimi (µs): ölçüt <= 8 ms/kare.
const BUDGET_US := 4000

var stats: Dictionary = {}

var _net: WorldNetwork = null
var _cols: BuildingColumns = null
var _view: BuildingView = null
var _occupied: Dictionary = {}
var _terrain: TerrainView = null
var _ring_of: Callable = Callable()
var _t0_pids: Dictionary = {}
var _taken: Dictionary = {}
var _seen_version: int = 0
var _ground_dirty: Rect2 = Rect2()
var _has_ground_dirty: bool = false


## T0 sütunlarının korunan (tarihî/simge/kamu bayraklı) parsel kimlikleri, artan ve tekil.
static func protected_ids(cols: BuildingColumns) -> PackedInt64Array:
	var seen := {}
	if cols != null:
		for i in cols.count:
			if (cols.flags[i] & PROTECT_FLAGS) != 0:
				seen[int(cols.parcel_id[i])] = true
	var ids: Array = seen.keys()
	ids.sort()
	return PackedInt64Array(ids)


## Sim yol bağlamına gerçek köprüyü ve korunan kümeyi takar. Köprü veri kipine bağlıdır (`crossing_parcels`).
static func attach_port(ctx: PublicWorksContext, net: WorldNetwork, rules: RoadDraftRules,
		cols: BuildingColumns) -> void:
	ctx.set_expropriation(NetworkExpropriationPort.new(net, rules))
	ctx.set_protected(protected_ids(cols))


## `occupied`: playable `_t0_occupied` (alınanlar çıkarılır, geri gelenler eklenir; denetçi/imar "yapı var mı" sorgusu).
## `terrain` ve `ring_of` (seçim halkasını döndüren çağrılabilir) isteğe bağlıdır.
static func create(net: WorldNetwork, cols: BuildingColumns, view: BuildingView, occupied: Dictionary,
		terrain: TerrainView = null, ring_of: Callable = Callable()) -> PlayableExpropriation:
	var f := PlayableExpropriation.new()
	f._net = net
	f._cols = cols
	f._view = view
	f._occupied = occupied
	f._terrain = terrain
	f._ring_of = ring_of
	f._seen_version = net.graph_version
	for pid in cols.occupied_parcels():
		f._t0_pids[int(pid)] = true
	if view != null:
		view.prepare_parcel_index()
	if terrain != null:
		terrain.prepare_urban_update(cols)
	return f


## Alınmış (görünümde gizli) T0 parsel sayısı.
func taken_count() -> int:
	return _taken.size()


func is_hidden(parcel_id: int) -> bool:
	return _taken.has(parcel_id)


## Bekleyen görünüm işi var mı (kurulum kuyruğu ya da kent zemini yenilemesi)?
func busy() -> bool:
	return _has_ground_dirty or (_terrain != null and _terrain.urban_update_pending()) \
			or (_view != null and _view.pending_work() > 0)


## Kare başı: ağ değiştiyse eşitler; bekleyen görünüm işini `budget_us` dilimiyle yürütür. Rapor (iş yoksa boş).
func poll(budget_us: int = BUDGET_US) -> Dictionary:
	var t0 := Time.get_ticks_usec()
	var rep := {}
	if _net.graph_version != _seen_version:
		rep = reconcile()
	var left := maxi(budget_us - (Time.get_ticks_usec() - t0), 0)
	if _view != null and _view.pending_work() > 0:
		var pump := _view.pump_pending(left)
		rep["pump"] = pump
		_note("pump_max_ms", float(pump["ms"]))
		stats["pump_units"] = int(stats.get("pump_units", 0)) + int(pump["done"])
	if (_has_ground_dirty or (_terrain != null and _terrain.urban_update_pending())) \
			and (_view == null or _view.pending_work() == 0):
		_update_ground(budget_us)
	if not rep.is_empty():
		rep["ms"] = (Time.get_ticks_usec() - t0) / 1000.0
		_note("poll_max_ms", float(rep["ms"]))
	return rep


## Senkron: ağ eşitlenir ve bekleyen tüm görünüm işi bitirilir (dev/yakalama/test; oyunda kare dilimi kullanılır).
func settle() -> Dictionary:
	var rep := poll(1000000)
	while busy():
		poll(1000000)
	return rep


## Ağ parsel kümesini T0 görünümüyle eşitler (tek seferlik süzme; kurulum kuyruğa girer). Rapor: {hidden, shown, full}.
func reconcile() -> Dictionary:
	var full := not _net.change_log_covers(_seen_version)
	var cand: Dictionary = {}
	if full:
		cand = _t0_pids.duplicate()
		for pid: int in _taken:
			cand[pid] = true
		_mark_ground(Rect2(-1.0e6, -1.0e6, 2.0e6, 2.0e6))
	else:
		for change in _net.changes_since(_seen_version):
			for pid in change.parcels_removed:
				cand[int(pid)] = true
			for pid in change.parcels_added:
				cand[int(pid)] = true
			var blocks_moved := not change.blocks_added.is_empty() or not change.blocks_removed.is_empty()
			if (blocks_moved or change.changes_parcels()) and change.dirty_rect.has_area():
				_mark_ground(change.dirty_rect)
	var hide := PackedInt32Array()
	var show := PackedInt32Array()
	for pid: int in cand:
		if not _t0_pids.has(pid):
			continue
		var gone := not _net.parcels.has(pid)
		if gone and not _taken.has(pid):
			hide.append(pid)
		elif not gone and _taken.has(pid):
			show.append(pid)
	hide.sort()
	show.sort()
	_seen_version = _net.graph_version
	var res_h := _apply(hide, true)
	var res_s := _apply(show, false)
	stats["hidden_total"] = _taken.size()
	var rep := {"hidden": hide.size(), "shown": show.size(), "full": full, "cells_queued": int(res_h.get("cells", 0))
			+ int(res_s.get("cells", 0)), "mask_ms": float(res_h.get("ms", 0.0)) + float(res_s.get("ms", 0.0))}
	_note("reconcile_max_ms", float(rep["mask_ms"]))
	stats["last"] = rep
	return rep


func _apply(ids: PackedInt32Array, hide: bool) -> Dictionary:
	if ids.is_empty():
		return {}
	for pid in ids:
		if hide:
			_taken[int(pid)] = true
			_occupied.erase(int(pid))
		else:
			_taken.erase(int(pid))
			_occupied[int(pid)] = true
	if hide:
		_drop_selection(ids)
	return _view.set_parcels_hidden(ids, hide) if _view != null else {}


## Seçili parsel alındıysa dünya halkası kalkar (kimlik sim/denetçide kalır: "Kamulaştırıldı" gösterir).
func _drop_selection(ids: PackedInt32Array) -> void:
	if not _ring_of.is_valid():
		return
	var ring := _ring_of.call() as ParcelSelectionRing
	if ring != null and ids.has(ring.parcel_id()):
		ring.clear()


func _mark_ground(rect: Rect2) -> void:
	_ground_dirty = _ground_dirty.merge(rect) if _has_ground_dirty else rect
	_has_ground_dirty = true


func _update_ground(budget_us: int) -> void:
	if _terrain == null:
		_has_ground_dirty = false
		_ground_dirty = Rect2()
		return
	var t0 := Time.get_ticks_usec()
	if _has_ground_dirty:
		_has_ground_dirty = false
		var occ_before := _terrain.urban_ready()
		_terrain.begin_urban_update(_net, _cols, _ground_dirty)
		stats["ground_rect"] = [snappedf(_ground_dirty.position.x, 1.0), snappedf(_ground_dirty.position.y, 1.0),
				snappedf(_ground_dirty.size.x, 1.0), snappedf(_ground_dirty.size.y, 1.0), occ_before]
		_ground_dirty = Rect2()
		_note("ground_begin_ms", (Time.get_ticks_usec() - t0) / 1000.0)
	var t1 := Time.get_ticks_usec()
	var rep := _terrain.step_urban_update(_net, budget_us)
	var ms := (Time.get_ticks_usec() - t1) / 1000.0
	_note("ground_finish_ms" if not rep.is_empty() else "ground_paint_step_ms", ms)
	if not rep.is_empty():
		stats["ground"] = rep


func _note(key: String, value: float) -> void:
	stats[key] = snappedf(maxf(float(stats.get(key, 0.0)), value), 0.01)
