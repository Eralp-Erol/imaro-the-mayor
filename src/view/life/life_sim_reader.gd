class_name LifeSimReader
extends RefCounted
## Yaşam görünümünün SİM OKUYUCUSU (T-050): yalnız `SimFacade` okuma sorguları; `submit_command`/yazma YOK, sim
## durumu ve `state_hash` etkilenmez (okumalar değer kopyası, sim sözleşmesi). Okunanlar:
##  - T0 başlangıç stoğu (sim'e verilen `ListStockSource`; oynanabilir sahnede `PlayableStock.from_columns`);
##  - `parcel_changes_since` (ADR-0005 Ek D protokolü) -> değişen parsellerin `ParcelView`ü (kullanım, birim, inşaat);
##  - `economy_outcome()` -> bölge doluluğu (housed_households / residential_units).
## Maliyet: bir `ParcelView` okuması ~90 us (ölçüldü, 40k parselde tam okuma ~3,6 sn), bu yüzden tam okuma YAPILMAZ:
## başlangıç stoğu yerel sütunlardan gelir, sonrası yalnız değişen kimlikler ve kare başına tavanlı kuyruktur. Kayıt
## yüklenince (epoch değişir / akış eksik) parsel durumu yalnız KAMERA YAKININDAKİ hücreler için, kare başına tavanla
## yeniden okunur.

var facade: SimFacade = null
var activity: LifeEdgeActivity = null
var net: WorldNetwork = null
## Kare başına en çok bu kadar parsel okunur (~90 us/parsel); tick'li karede okunmaz.
var parcels_per_frame: int = 30
## Doluluk güncellemesi arası en az tick (yerleşim fırtınasını önler) ve eşik.
var occupancy_min_interval_ticks: int = 7
var occupancy_threshold: float = 0.02
var stats: Dictionary = {"views_read": 0, "feed_ids": 0, "full_resyncs": 0, "occupancy_updates": 0,
		"economy_reads": 0, "queue_max": 0}
## true: doluluk değişti, çağıran tüm hücreleri yenilemeli (çağıran okur ve sıfırlar).
var occupancy_changed: bool = false

var _seen_tick: int = -999999
var _feed_tick: int = -1
var _epoch: int = -1
var _stale: bool = false
var _queue: PackedInt64Array = PackedInt64Array()
var _queue_pos: int = 0
var _cell_pending: Dictionary = {}
var _cell_ready: Dictionary = {}
var _cell_ids: Dictionary = {}
var _cell_order: Array = []
var _occ_tick: int = -999999


static func create(p_facade: SimFacade, p_activity: LifeEdgeActivity, p_net: WorldNetwork,
		stock: ExistingStockSource) -> LifeSimReader:
	var r := LifeSimReader.new()
	r.facade = p_facade
	r.activity = p_activity
	r.net = p_net
	r._load_stock(stock)
	return r


## Parsel görünümünden faaliyet birimleri (res, com, con). `built` -> konut/ticaret birimi; `under_construction` ->
## inşaat birimi (şantiye faaliyeti). `planned`/`stalled`/`vacant`/`taken` -> 0 (henüz/artık faaliyet yok).
static func state_of(v: ParcelView) -> Vector3i:
	if v == null or v.units <= 0:
		return Vector3i.ZERO
	if v.development == ParcelView.DEVELOPMENT_BUILT:
		if v.use == ParcelView.USE_RESIDENTIAL:
			return Vector3i(v.units, 0, 0)
		if v.use == ParcelView.USE_COMMERCIAL:
			return Vector3i(0, v.units, 0)
	elif v.development == ParcelView.DEVELOPMENT_UNDER_CONSTRUCTION:
		return Vector3i(0, 0, v.units)
	return Vector3i.ZERO


func _load_stock(stock: ExistingStockSource) -> void:
	if stock == null:
		return
	for id in stock.parcel_ids():
		var units := stock.units_of(int(id))
		if units <= 0:
			continue
		var use := stock.use_of(int(id))
		activity.parcel_state[int(id)] = Vector3i(units, 0, 0) if use == &"residential" else Vector3i(0, units, 0)
	activity.begin_rebuild()


## Hücre sim durumuyla güncel mi? Kayıt yükleme sonrası eski hücreler önce yeniden okunur; hazır değilse false.
func prepare_cell(cell: Vector2i) -> bool:
	if not _stale or _cell_ready.has(cell):
		return true
	if not _cell_pending.has(cell):
		var ids := PackedInt64Array()
		for eid in activity.edges_in_cell(cell):
			for pid in net.edge_parcels(int(eid)):
				ids.append(int(pid))
		_cell_ids[cell] = ids
		_cell_pending[cell] = 0
		_cell_order.append(cell)
		if ids.is_empty():
			_cell_ready[cell] = true
	return _cell_ready.has(cell)


## Her karede çağrılır. `ticked`: bu karede sim tick'i oldu (iş yapılmaz, ağır kare).
func poll(ticked: bool) -> void:
	var tick := facade.current_tick()
	if tick != _seen_tick:
		_seen_tick = tick
		_on_tick(tick)
	if ticked:
		return
	_pump()


func _on_tick(tick: int) -> void:
	var feed := facade.parcel_changes_since(_feed_tick)
	if not feed.complete or (_epoch >= 0 and feed.epoch != _epoch):
		# Eksik akış / yüklenmiş durum: tam okuma yok; kamera yakını hücreler lazy yeniden okunur.
		_stale = true
		_cell_ready.clear()
		_cell_pending.clear()
		_cell_ids.clear()
		_cell_order.clear()
		_queue = PackedInt64Array()
		_queue_pos = 0
		stats["full_resyncs"] = int(stats["full_resyncs"]) + 1
	else:
		stats["feed_ids"] = int(stats["feed_ids"]) + feed.ids.size()
		_queue.append_array(feed.ids)
		stats["queue_max"] = maxi(int(stats["queue_max"]), _queue.size() - _queue_pos)
	_feed_tick = feed.up_to_tick
	_epoch = feed.epoch
	if tick - _occ_tick >= occupancy_min_interval_ticks:
		var out := facade.economy_outcome()
		stats["economy_reads"] = int(stats["economy_reads"]) + 1
		if out.available:
			_occ_tick = tick
			if activity.set_occupancy_from(out, occupancy_threshold):
				occupancy_changed = true
				stats["occupancy_updates"] = int(stats["occupancy_updates"]) + 1


func _pump() -> void:
	var budget := parcels_per_frame
	# 1) Kayıt sonrası bayat hücreler (kamera yakını).
	while budget > 0 and not _cell_order.is_empty():
		var cell: Vector2i = _cell_order[0]
		var ids: PackedInt64Array = _cell_ids[cell]
		var pos := int(_cell_pending[cell])
		var take := mini(budget, ids.size() - pos)
		if take > 0:
			_apply_ids(ids.slice(pos, pos + take))
			budget -= take
			pos += take
			_cell_pending[cell] = pos
		if pos >= ids.size():
			_cell_ready[cell] = true
			_cell_order.pop_front()
			_cell_ids.erase(cell)
			activity.mark_cell_dirty(cell)
	# 2) Değişim akışı.
	if budget > 0 and _queue_pos < _queue.size():
		var take := mini(budget, _queue.size() - _queue_pos)
		_apply_ids(_queue.slice(_queue_pos, _queue_pos + take))
		_queue_pos += take
		if _queue_pos >= _queue.size():
			_queue = PackedInt64Array()
			_queue_pos = 0


func _apply_ids(ids: PackedInt64Array) -> void:
	if ids.is_empty():
		return
	for v in facade.parcel_views(ids):
		activity.set_parcel(v.id, state_of(v))
	stats["views_read"] = int(stats["views_read"]) + ids.size()


func pending_parcels() -> int:
	var n := _queue.size() - _queue_pos
	for cell in _cell_order:
		n += (_cell_ids[cell] as PackedInt64Array).size() - int(_cell_pending[cell])
	return n
