class_name SimBuildingProjector
extends RefCounted
## Sim aşaması -> BuildingColumns (T-040; CAN-03, WLD-01). Render tarafı: sim'e YAZMAZ, yalnız `SimFacade` okur
## (`events_since`, `parcel_views`, `economy_outcome`). Oyuncu girdisi bu sınıfa hiçbir yoldan ulaşmaz; yapı satırı
## kaynağı yalnız sim'in `ParcelView`'ıdır (`developed_by_sim` + `development` + `use` + `units` + `progress_pm`).
##
## Projeksiyon kuralı: yalnız `developed_by_sim` ve development in {under_construction, built, stalled}.
## vacant/planned/declined için yapı YOK; stalled'da sim'in dondurduğu ilerlemedeki yapı; T0 stoku
## (`developed_by_sim == false`) için satır üretilmez (T0 yapıları zaten T0 BuildingColumns'tadır).
##
## İş modeli (kare maliyeti, T-040 ölçüt 10): sync bir PENCERE (sim günü) işidir ve küçük DİLİMLERE bölünür; sahne
## her karede `step(bütçe_us)` çağırır, tick'li karede iş yapılmaz (yalnız sonraki karelerde sürer). Dilimler:
## olay okuma (24 olay), parsel okuma (10 parsel), sütun kurma. `sync(exact)` aynı işi bütçesiz bitirir (test/dev).
## Okunacak parseller: onay olayları + zamanı gelen devam eden projeler. Zaman, kat kademesinin değişeceği günden
## tahmin edilir (ilerleme hızı iki okumadan; `SimBuildingPlacer.next_stage_progress`): kademe değişmeden parsel
## okunmaz. Kare yolunda tüm parsellerin taranması YOK; gizlenen onaylar (aşağıda) için dilimli denetim vardır.
## Çıktı yoldan bağımsızdır: parsel kimliğine göre sıralı satırlar; `sync(true)` sonrası aynı sim durumu -> aynı sütun.
##
## Sim'in olay saklama ufku kuralı (ADR-0005 §5): eski gerekçeye işaret eden TAMAMLANMA olayı öncesini gizler; aynı
## penceredeki yeni ONAYLAR da kaybolabilir. Onay sayacı (`economy_outcome().investments_approved`) görülen onay
## olaylarından büyükse eksik kadar parsel dilimli denetim taramasıyla aranır (en çok MAX_AUDIT_PASSES geçiş).

enum Phase { IDLE, EVENTS, VIEWS }

const SUBJECT_PREFIX := "parcel."
const KIND_DECIDED := &"actor.decided"
const KIND_CHANGED := &"parcel.changed"
## Yapı durumunu değiştirmeyen karar olayı (vacant parsel vacant kalır): parsel okunmaz. Günlüğü baskın olay türü.
const MSG_DECLINED := &"event.investor.declined"
const MSG_APPROVED := &"event.investor.develop"
const EVENT_CHUNK := 24
const VIEW_CHUNK := 10
## Okunmuş görünümlerin uygulanması (yerleşim hesabı dahil) birim başına en çok bu kadar µs.
const APPLY_UNIT_US := 700
const EXACT_CHUNK := 400
## Denetim taraması pencere başına en çok bu kadar parsel.
const AUDIT_SLICE := 20
## Eksik onay bulunamazsa en çok bu kadar tam geçiş yapılır.
const MAX_AUDIT_PASSES := 2
## İki yoklama arasındaki en uzun aralık (gün): ilerleme hızı değişirse (durma/devam) güvenlik ağı.
const MAX_POLL_GAP := 10

## Son sync ölçümleri ve sayaçlar (perf_probe / test okur).
var stats: Dictionary = {"syncs": 0, "windows": 0, "changed_windows": 0, "full_scans": 0, "unplaced": 0,
		"last_ms": 0.0, "last_parcels": 0, "last_events": 0, "unresolved_missing": 0, "steps": 0, "step_ms_max": 0.0,
		"parcel_reads": 0, "backlog_max": 0}

var _facade: SimFacade = null
var _placer: SimBuildingPlacer = null
var _mapping: SimBuildingMapping = null
var _t0_occupied: Dictionary = {}
var _cursor: int = 0
var _last_tick: int = -1
## pid -> {"use", "units", "plan"} (nihai yerleşim önbelleği; ilerlemeden bağımsız).
var _plans: Dictionary = {}
## pid -> {"rows": Array[Row], "sig": String, "key": String} (şu an görünen satırlar).
var _shown: Dictionary = {}
## Sim gelişimi sürenler (planlı, inşaatta, durmuş): pid -> true. `_due`: sonraki okuma günü;
## `_sample`: (gün, ilerleme).
var _inflight: Dictionary = {}
var _due: Dictionary = {}
var _sample: Dictionary = {}
var _audit_ids: PackedInt32Array = PackedInt32Array()
var _audit_pos: int = 0
## Sim'in kümülatif onay sayacı; -1 = bilinmiyor.
var _approved_total: int = -1
## Sayaçta görünüp olay olarak görülemeyen (gizlenmiş) onay sayısı: denetim bunları bulana dek sürer.
var _pending_missing: int = 0
## true: geçmiş bilinmiyor (yükleme/geri sarma/ilk bağlanma) -> tüm geçiş; false: eksik onaylar bulunana dek.
var _audit_full: bool = false
var _audit_passes: int = 0
var _unplaced: Dictionary = {}
var _columns: BuildingColumns = BuildingColumns.new()
var _version: int = 0
# --- pencere (sürmekte olan sync) durumu ---
var _phase: int = Phase.IDLE
var _w_tick: int = 0
var _w_seq: int = 0
var _w_approved: int = -1
var _w_exact: bool = false
var _w_counted: bool = false
var _w_seen_approvals: int = 0
var _w_dirty: Dictionary = {}
var _w_event_ids: Dictionary = {}
var _w_fresh: PackedInt32Array = PackedInt32Array()
var _w_ids: Array = []
var _w_pos: int = 0
var _w_fetched: Array[ParcelView] = []
var _w_fpos: int = 0
var _w_fetch_tick: int = 0
var _w_changed: bool = false
var _w_events: int = 0
var _w_work_us: int = 0


static func create(facade: SimFacade, settlement: SettlementResult, mapping: SimBuildingMapping,
		world_seed: int) -> SimBuildingProjector:
	if facade == null:
		return null
	var placer := SimBuildingPlacer.create(settlement, mapping, world_seed)
	if placer == null:
		return null
	var p := SimBuildingProjector.new()
	p._facade = facade
	p._placer = placer
	p._mapping = mapping
	for pid in settlement.columns.occupied_parcels():
		p._t0_occupied[int(pid)] = true
	return p


func placer() -> SimBuildingPlacer:
	return _placer


## Şu anki sütunlar (her değişiklikte YENİ nesne; BuildingView.set_columns ile `version()` birlikte verilir).
func columns() -> BuildingColumns:
	return _columns


func version() -> int:
	return _version


## Görünür satırı olan parsel kimlikleri, artan.
func parcel_ids() -> PackedInt32Array:
	var ids: Array = _shown.keys()
	ids.sort()
	return PackedInt32Array(ids)


## Sim "built/under_construction" dedi ama yerleşemeyen parseller (parsel -> neden).
func unplaced() -> Dictionary:
	return _unplaced


## Denetim taraması bitti mi (bekleyen dilim yok)?
func audit_idle() -> bool:
	return _audit_ids.is_empty()


## Sürmekte olan pencere ya da başlamamış iş var mı (tick/olay ilerlemiş, denetim sürüyor).
func busy() -> bool:
	return _phase != Phase.IDLE or _facade.current_tick() != _last_tick or _facade.last_event_seq() != _cursor \
			or not _audit_ids.is_empty()


## Projector'ın işlediği son sim günü ile şimdiki gün arasındaki fark (kuyruk derinliği).
func backlog_ticks() -> int:
	return maxi(_facade.current_tick() - maxi(_last_tick, 0), 0)


## BÜTÇELİ ilerleme: en az bir dilim, sonra `budget_us` dolana dek. Dönüş: {worked, busy, ms}.
func step(budget_us: int) -> Dictionary:
	var t0 := Time.get_ticks_usec()
	var worked := false
	while true:
		if _phase == Phase.IDLE:
			if not _begin(false):
				break
			worked = true
			if Time.get_ticks_usec() - t0 >= budget_us:
				break   # pencere açılışı (sayaç okuma) bütçeyi bitirdi: dilimler sonraki karede
		_run_unit()
		worked = true
		if Time.get_ticks_usec() - t0 >= budget_us:
			break
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	if worked:
		stats["steps"] += 1
		stats["step_ms_max"] = maxf(float(stats["step_ms_max"]), ms)
		stats["backlog_max"] = maxi(int(stats["backlog_max"]), backlog_ticks())
	return {"worked": worked, "busy": busy(), "ms": ms}


## BÜTÇESİZ tam senkron (testler, dev ilerletme, yükleme). Dönüş: {changed, resync, parcels, events, ms}.
## `exact`: sürmekte olan TÜM projelerin ilerlemesini şimdi okur ve bekleyen denetimi bitirir.
func sync(exact: bool = false) -> Dictionary:
	var t0 := Time.get_ticks_usec()
	var v0 := _version
	var report := {"changed": false, "resync": false, "parcels": 0, "events": 0, "ms": 0.0}
	stats["syncs"] += 1
	while _phase != Phase.IDLE or _begin(false):
		_run_unit()
	if exact and _begin(true):
		while _phase != Phase.IDLE:
			_run_unit()
	report["changed"] = _version != v0
	report["parcels"] = int(stats["last_parcels"])
	report["events"] = int(stats["last_events"])
	report["resync"] = bool(stats.get("last_resync", false))
	report["ms"] = (Time.get_ticks_usec() - t0) / 1000.0
	return report


# --- pencere ----------------------------------------------------------------------------------------------------

## Yeni pencere açar; yapılacak iş yoksa false.
func _begin(exact: bool) -> bool:
	var tick := _facade.current_tick()
	var seq := _facade.last_event_seq()
	if not exact and tick == _last_tick and seq == _cursor and _audit_ids.is_empty():
		return false
	var t0 := Time.get_ticks_usec()
	_w_tick = tick
	_w_seq = seq
	_w_exact = exact
	_w_dirty = {}
	_w_event_ids = {}
	_w_fresh = PackedInt32Array()
	_w_seen_approvals = 0
	_w_events = 0
	_w_changed = false
	_w_fetched = []
	_w_fpos = 0
	_w_pos = 0
	stats["last_resync"] = false
	var outcome := _facade.economy_outcome()
	_w_counted = outcome.available
	_w_approved = outcome.investments_approved if _w_counted else -1
	var rewound := seq < _cursor or tick < _last_tick
	# İlk bağlanma: saklanan olaylar tüm geçmişi kapsıyorsa (budanma yok) denetim gerekmez.
	var first_attach := _last_tick < 0 and tick > 0 and _facade.first_retained_event_seq() > 1
	if rewound or first_attach:
		# Geçmiş bilinmiyor (yükleme/geri sarma/ilk bağlanma): T0 stoku dışındaki tüm parseller DİLİMLİ okunur.
		stats["last_resync"] = true
		_start_audit(true)
		_pending_missing = 0
		for pid: int in _shown:
			_w_dirty[pid] = true
		for pid: int in _inflight:
			_w_dirty[pid] = true
		if rewound:
			_cursor = seq
			_approved_total = -1
	_phase = Phase.EVENTS
	_w_work_us = Time.get_ticks_usec() - t0
	_note_max("begin_ms_max", _w_work_us)
	return true


## Bir iş birimi (olay dilimi / parsel dilimi) yürütür.
func _run_unit() -> void:
	var t0 := Time.get_ticks_usec()
	stats["units"] = int(stats.get("units", 0)) + 1
	var which := "events_ms_max" if _phase == Phase.EVENTS else "views_ms_max"
	if _phase == Phase.EVENTS:
		_events_unit()
	elif _phase == Phase.VIEWS:
		_views_unit()
	_w_work_us += Time.get_ticks_usec() - t0
	_note_max(which, Time.get_ticks_usec() - t0)


func _events_unit() -> void:
	if _cursor >= _w_seq:
		_finish_events()
		return
	var events := _facade.events_since(_cursor, EVENT_CHUNK)
	if events.is_empty():
		_cursor = _w_seq   # saklama ufku dışında kalanlar (gizli); onay sayacı eksiği yakalar
		_finish_events()
		return
	for e in events:
		if e.seq > _w_seq:
			_cursor = _w_seq
			break
		_cursor = e.seq
		_w_events += 1
		if (e.kind != KIND_DECIDED and e.kind != KIND_CHANGED) or e.message_key == MSG_DECLINED:
			continue
		if e.message_key == MSG_APPROVED:
			_w_seen_approvals += 1
		for subject in e.subjects:
			if subject.begins_with(SUBJECT_PREFIX):
				var pid := subject.substr(SUBJECT_PREFIX.length()).to_int()
				_w_dirty[pid] = true
				_w_event_ids[pid] = true
	if _cursor >= _w_seq:
		_finish_events()


## Olaylar bitti: onay sayacı denetimi, zamanı gelen yoklamalar, denetim dilimi -> okunacak parsel listesi.
func _finish_events() -> void:
	if _w_counted:
		if _approved_total >= 0 and _w_approved - _approved_total > _w_seen_approvals:
			_pending_missing += _w_approved - _approved_total - _w_seen_approvals
			stats["last_resync"] = true
		_approved_total = _w_approved
	elif _w_tick - _last_tick > 1 and _last_tick >= 0:
		# Sayaç yok (örn. mock): çok günlük pencerede ufuk kaybı olabilir; güvenli taraf denetimdir.
		_pending_missing = maxi(_pending_missing, 1)
		stats["last_resync"] = true
	if _pending_missing > 0 and _audit_ids.is_empty():
		_start_audit(false)
	if _w_exact:
		for pid: int in _inflight:
			_w_dirty[pid] = true
	else:
		for pid: int in _inflight:
			if int(_due.get(pid, 0)) <= _w_tick:
				_w_dirty[pid] = true
	var slice_end := _audit_ids.size() if _w_exact else mini(_audit_pos + AUDIT_SLICE, _audit_ids.size())
	while _audit_pos < slice_end:
		var pid := _audit_ids[_audit_pos]
		_w_dirty[pid] = true
		if not _shown.has(pid) and not _inflight.has(pid) and not _w_event_ids.has(pid):
			_w_fresh.append(pid)
		_audit_pos += 1
	_w_ids = _w_dirty.keys()
	_w_ids.sort()
	_w_pos = 0
	_phase = Phase.VIEWS


func _views_unit() -> void:
	if _w_fpos < _w_fetched.size():
		# Okunmuş görünümleri uygula: yerleşim hesabı (plan) pahalı olabilir -> birim başına zaman sınırı.
		var t0 := Time.get_ticks_usec()
		while _w_fpos < _w_fetched.size():
			_w_changed = _apply(_w_fetched[_w_fpos], _w_fetch_tick) or _w_changed
			_w_fpos += 1
			if not _w_exact and Time.get_ticks_usec() - t0 >= APPLY_UNIT_US:
				break
		if _w_fpos >= _w_fetched.size() and _w_pos >= _w_ids.size():
			_finish_window()
		return
	if _w_pos >= _w_ids.size():
		_finish_window()
		return
	var chunk_size := EXACT_CHUNK if _w_exact else VIEW_CHUNK
	var chunk := PackedInt64Array()
	for pid in _w_ids.slice(_w_pos, mini(_w_pos + chunk_size, _w_ids.size())):
		chunk.append(int(pid))
	_w_pos += chunk.size()
	_w_fetch_tick = _facade.current_tick()
	var seen := {}
	_w_fetched = _facade.parcel_views(chunk)
	_w_fpos = 0
	stats["parcel_reads"] += chunk.size()
	for v in _w_fetched:
		seen[v.id] = true
	for pid in chunk:
		if not seen.has(int(pid)) and _shown.has(int(pid)):
			_drop(int(pid))
			_w_changed = true


func _finish_window() -> void:
	for pid in _w_fresh:
		if _inflight.has(pid) or _shown.has(pid):
			_pending_missing = maxi(0, _pending_missing - 1)
	if not _audit_ids.is_empty() and not _audit_full and _pending_missing == 0:
		_audit_ids = PackedInt32Array()   # eksik onayların hepsi bulundu: geçiş erken biter
		_audit_pos = 0
	elif _audit_pos >= _audit_ids.size() and not _audit_ids.is_empty():
		_audit_ids = PackedInt32Array()
		_audit_pos = 0
		if _pending_missing > 0:
			_audit_passes += 1
			if _audit_passes >= MAX_AUDIT_PASSES:
				stats["unresolved_missing"] += _pending_missing   # bulunamadı: sonsuz tarama yok, kayda geçer
				_pending_missing = 0
			else:
				_start_audit(false, false)  # geçiş bitti ama hâlâ eksik var: yeni geçiş
	if _w_changed:
		_rebuild_columns()
		stats["changed_windows"] += 1
	_last_tick = _w_tick
	_phase = Phase.IDLE
	stats["windows"] += 1
	stats["last_ms"] = _w_work_us / 1000.0
	stats["last_parcels"] = _w_ids.size()
	stats["last_events"] = _w_events
	_w_dirty = {}
	_w_event_ids = {}
	_w_ids = []
	_w_fetched = []
	_w_fpos = 0


func _note_max(key: String, usec: int) -> void:
	stats[key] = maxf(float(stats.get(key, 0.0)), usec / 1000.0)


func _start_audit(full: bool, new_cycle: bool = true) -> void:
	_audit_full = full
	if new_cycle:
		_audit_passes = 0
	var ids := PackedInt32Array()
	for pid in _facade.parcel_ids():
		if not _t0_occupied.has(int(pid)):
			ids.append(int(pid))
	_audit_ids = ids
	_audit_pos = 0
	stats["full_scans"] += 1


# --- parsel -> satır ---------------------------------------------------------------------------------------------

## Tek parsel görünümünü uygular; satırlar değiştiyse true. `now`: okumanın yapıldığı sim günü.
func _apply(v: ParcelView, now: int) -> bool:
	var pid := v.id
	var building := v.developed_by_sim and v.use != ParcelView.USE_NONE and v.units > 0 \
			and (v.development == ParcelView.DEVELOPMENT_UNDER_CONSTRUCTION \
			or v.development == ParcelView.DEVELOPMENT_BUILT or v.development == ParcelView.DEVELOPMENT_STALLED)
	var in_flight := v.developed_by_sim and (v.development == ParcelView.DEVELOPMENT_PLANNED \
			or v.development == ParcelView.DEVELOPMENT_UNDER_CONSTRUCTION \
			or v.development == ParcelView.DEVELOPMENT_STALLED)
	if not in_flight:
		_inflight.erase(pid)
		_due.erase(pid)
		_sample.erase(pid)
	else:
		_inflight[pid] = true
	if not building:
		if in_flight:
			_schedule(pid, v, now, null)
		return _drop(pid)
	# Sim durumu önceki okumayla aynıysa satır üretimi atlanır.
	var key := "%s|%s|%d|%d" % [v.development, v.use, v.units, v.progress_pm]
	if _shown.has(pid) and _shown[pid]["key"] == key:
		if in_flight:
			_schedule(pid, v, now, (_plans.get(pid, {}) as Dictionary).get("plan"))
		return false
	var cached: Dictionary = _plans.get(pid, {})
	if cached.is_empty() or cached["use"] != v.use or int(cached["units"]) != v.units:
		var t_plan := Time.get_ticks_usec()
		cached = {"use": v.use, "units": v.units, "plan": _placer.plan(pid, v.use, v.units)}
		var plan_ms := (Time.get_ticks_usec() - t_plan) / 1000.0
		stats["plan_n"] = int(stats.get("plan_n", 0)) + 1
		stats["plan_ms_sum"] = float(stats.get("plan_ms_sum", 0.0)) + plan_ms
		stats["plan_ms_max"] = maxf(float(stats.get("plan_ms_max", 0.0)), plan_ms)
		_plans[pid] = cached
	var plan: SimBuildingPlacer.Plan = cached["plan"]
	if in_flight:
		_schedule(pid, v, now, plan)
	if plan == null:
		if not _unplaced.has(pid):
			_unplaced[pid] = "no_fit"
			stats["unplaced"] = _unplaced.size()
		return _drop(pid)
	_unplaced.erase(pid)
	stats["unplaced"] = _unplaced.size()
	var progress := ParcelView.PROGRESS_FULL if v.development == ParcelView.DEVELOPMENT_BUILT else v.progress_pm
	var rows := _placer.rows_for(plan, progress)
	var parts := PackedStringArray()
	for r in rows:
		parts.append(r.signature())
	var sig := ";".join(parts)
	var old: Dictionary = _shown.get(pid, {})
	var unchanged: bool = not old.is_empty() and old["sig"] == sig
	_shown[pid] = {"rows": rows, "sig": sig, "key": key}
	return not unchanged


## Sonraki okuma günü: inşaatta, iki okumadan ilerleme hızı çıkarılır ve kat kademesinin değişeceği güne kurulur
## (tamsayı hesap); hız bilinmiyorsa ertesi gün (hızı öğrenmek için); planlı/durmuş için `progress_poll_days`.
func _schedule(pid: int, v: ParcelView, now: int, plan: SimBuildingPlacer.Plan) -> void:
	var gap := _mapping.progress_poll_days
	if v.development == ParcelView.DEVELOPMENT_UNDER_CONSTRUCTION:
		var smp: Vector2i = _sample.get(pid, Vector2i(-1, 0))
		if plan != null and smp.x >= 0 and now > smp.x and v.progress_pm > smp.y:
			var dp := v.progress_pm - smp.y
			var dt := now - smp.x
			var need := _placer.next_stage_progress(plan, v.progress_pm) - v.progress_pm
			gap = clampi((need * dt + dp - 1) / dp, 1, MAX_POLL_GAP)
		else:
			gap = 1
		_sample[pid] = Vector2i(now, v.progress_pm)
	else:
		_sample.erase(pid)
	_due[pid] = now + gap


func _drop(pid: int) -> bool:
	if not _shown.has(pid):
		return false
	_shown.erase(pid)
	_plans.erase(pid)
	return true


func _rebuild_columns() -> void:
	var cols := BuildingColumns.new()
	for pid in parcel_ids():
		for r: SimBuildingPlacer.Row in _shown[int(pid)]["rows"]:
			cols.add(r.parcel_id, r.module, r.x, r.z, r.yaw, r.floors, r.wall, r.roof, r.accent, r.bright, r.flags,
					r.era)
	_columns = cols
	_version += 1
