class_name SimBuildingProjector
extends RefCounted
## Sim aşaması -> BuildingColumns (T-040, B-002; CAN-03, WLD-01). Render tarafı: sim'e YAZMAZ, yalnız `SimFacade` okur
## (`parcel_changes_since`, `parcel_views`, `parcel_ids`). Oyuncu girdisi bu sınıfa hiçbir yoldan ulaşmaz; yapı satırı
## kaynağı yalnız sim'in `ParcelView`'ıdır (`developed_by_sim` + `development` + `use` + `units` + `progress_pm`).
##
## Projeksiyon kuralı: yalnız `developed_by_sim` ve development in {under_construction, built, stalled}.
## vacant/planned/declined için yapı YOK; stalled'da sim'in dondurduğu ilerlemedeki yapı; T0 stoku
## (`developed_by_sim == false`) için satır üretilmez (T0 yapıları zaten T0 BuildingColumns'tadır).
##
## DEĞİŞİM KAYNAĞI (ADR-0005 Ek D, B-002): `SimFacade.parcel_changes_since(tick)`. Olay günlüğüne, onay sayacına ya da
## tam taramaya BAKILMAZ; olay saklama ufku burada hiçbir şey gizleyemez. Protokol (`ParcelChangeFeed`):
##  1. İlk bağlanma: `parcel_changes_since(-1)` TAM ise yalnız o kimlikler okunur (yeni oyun: ~hiç); değilse TEK tam
##     eşitleme (T0 dışı tüm parseller, dilimli).
##  2. Sonra her yeni sim gününde `parcel_changes_since(son_up_to_tick)`: yalnız değişen kimlikler okunur.
##  3. `not feed.complete` ya da `feed.epoch` değişti (kayıt yüklendi / geri sarma / geçmiş bilinmiyor) => TEK tam
##     eşitleme, sonra yine yalnız feed.
## Feed kapsamı DIŞI olan tek alan `progress_pm`dir (aşama içinde her gün ilerler): inşaattaki parseller için kat
## kademesinin değişeceği gün iki okumadan tahmin edilir (`SimBuildingPlacer.next_stage_progress`) ve yalnız o gün
## okunur. Planlı/durmuş parseller yoklanmaz (ilerleme donuk; başlama/durma/devam feed'de).
##
## İş modeli (kare maliyeti, T-040 ölçüt 10): sync bir PENCERE (yeni sim günü) işidir ve küçük DİLİMLERE bölünür; sahne
## her karede `step(bütçe_us)` çağırır, tick'li karede iş yapılmaz (yalnız sonraki kareler). Birden çok gün geride kalan
## pencere TEK pencerede birleşir (feed `son_up_to_tick`ten bugüne birleşik). `sync(exact)` aynı işi bütçesiz bitirir.
## Çıktı yoldan bağımsızdır: parsel kimliğine göre sıralı satırlar; `sync(true)` sonrası aynı sim durumu -> aynı sütun
## (sıfırdan kurulan projector ile bit-bit eşit).
##
## Sığmayan parsel: sim "built/under_construction" dese de yerleşim yoksa SESSİZ DEĞİLDİR: `unplaced_parcel_ids()`,
## `unplaced_count()`, `unplaced_reason(pid)` (HUD "Yapıldı · yapı çizilemedi" diyebilsin).

enum Phase { IDLE, VIEWS }

## Okunmuş parsel dilimi (normal pencere): birim başına parsel.
const VIEW_CHUNK := 16
## Tam eşitleme (süpürme) biriminde okunan parsel sayısı (~1 ms: tick'li karede bile sığar).
const SWEEP_CHUNK := 8
## Süpürmede bir birimde en çok bu kadar ham kimlik taranır (T0 parselleri atlanırken).
const SWEEP_SCAN := 2000
## Okunmuş görünümlerin uygulanması (yerleşim hesabı dahil) birim başına en çok bu kadar µs.
const APPLY_UNIT_US := 700
const EXACT_CHUNK := 400
## İki yoklama arasındaki en uzun aralık (gün): ilerleme hızı kestirimi sapmasına karşı güvenlik ağı.
const MAX_POLL_GAP := 16
## Yoklama gerekmeyen inşaat (son kat kademesi): bir daha asla zamanı gelmez.
const NEVER := 1 << 30

## > 0: bütçeler duvar saati yerine SANAL saatle ölçülür (her iş birimi bu kadar µs sayılır): testler makine
## yükünden bağımsız ve deterministik olur. 0 = gerçek saat.
var virtual_unit_us: int = 0

## Son sync ölçümleri ve sayaçlar (perf_probe / test okur).
var stats: Dictionary = {"syncs": 0, "windows": 0, "changed_windows": 0, "full_syncs": 0, "unplaced": 0,
		"last_ms": 0.0, "last_parcels": 0, "last_feed_ids": 0, "steps": 0, "step_ms_max": 0.0,
		"parcel_reads": 0, "stage_polls": 0, "backlog_max": 0, "units": 0}

var _facade: SimFacade = null
var _placer: SimBuildingPlacer = null
var _t0_occupied: Dictionary = {}
var _last_tick: int = -1
## Son tüketilen feed: `up_to_tick` (-1 = hiç) ve `epoch` (-1 = bilinmiyor).
var _feed_tick: int = -1
var _feed_epoch: int = -1
## pid -> {"use", "units", "plan", "reason"} (nihai yerleşim önbelleği; ilerlemeden bağımsız).
var _plans: Dictionary = {}
## pid -> {"rows": Array[Row], "sig": String, "key": String} (şu an görünen satırlar).
var _shown: Dictionary = {}
## İnşaattaki parseller (kat kademesi zamanlı yoklaması): pid -> true. `_due`: sonraki okuma günü;
## `_sample`: (gün, ilerleme).
var _staged: Dictionary = {}
var _due: Dictionary = {}
var _sample: Dictionary = {}
var _clock: SimBuildingStageClock = SimBuildingStageClock.new()
## Sim "yapıldı/inşaatta" dedi ama yerleşemeyen parseller: pid -> neden (`SimBuildingPlacer.plan_failure`).
var _unplaced: Dictionary = {}
var _columns: BuildingColumns = BuildingColumns.new()
var _version: int = 0
# --- pencere (sürmekte olan sync) durumu ---
var _phase: int = Phase.IDLE
var _w_tick: int = 0
var _w_exact: bool = false
var _w_ids: PackedInt64Array = PackedInt64Array()
var _w_feed: Dictionary = {}
var _w_read: int = 0
var _w_pos: int = 0
var _w_fetched: Array[ParcelView] = []
var _w_fpos: int = 0
var _w_fetch_tick: int = 0
var _w_changed: bool = false
var _w_work_us: int = 0
var _vnow: int = 0


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


## Sim "built/under_construction/stalled" dedi ama yerleşemeyen parseller (parsel -> neden kodu). Salt okunur kullanın.
func unplaced() -> Dictionary:
	return _unplaced


## Yerleşemeyen parsel kimlikleri, artan (HUD "Yapıldı · yapı çizilemedi" için; facade'den bağımsız okuma yüzeyi).
func unplaced_parcel_ids() -> PackedInt32Array:
	var ids: Array = _unplaced.keys()
	ids.sort()
	return PackedInt32Array(ids)


func unplaced_count() -> int:
	return _unplaced.size()


func is_unplaced(parcel_id: int) -> bool:
	return _unplaced.has(parcel_id)


## Yerleşememe nedeni (`SimBuildingPlacer.FAIL_*`); yerleşebiliyorsa/bilinmiyorsa `&""`.
func unplaced_reason(parcel_id: int) -> StringName:
	return StringName(_unplaced.get(parcel_id, &""))


## Neden -> parsel sayısı.
func unplaced_reason_counts() -> Dictionary:
	var out := {}
	for pid: int in _unplaced:
		var r := String(_unplaced[pid])
		out[r] = int(out.get(r, 0)) + 1
	return out


## Sürmekte olan pencere ya da başlamamış iş var mı (yeni sim günü, feed tam değil/epoch değişti).
func busy() -> bool:
	return _phase != Phase.IDLE or _facade.current_tick() != _last_tick \
			or _needs_full(_facade.parcel_changes_since(_feed_tick))


## Projector'ın işlediği son sim günü ile şimdiki gün arasındaki fark (kuyruk derinliği).
func backlog_ticks() -> int:
	return maxi(_facade.current_tick() - maxi(_last_tick, 0), 0)


## BÜTÇELİ ilerleme: en az bir dilim, sonra `budget_us` dolana dek. Dönüş: {worked, busy, ms}.
## Tam eşitleme gerekiyorsa (kayıt yüklendi) pencere açılırken BÜTÇESİZ ve SENKRON yapılır (bkz. `_full_sync`).
func step(budget_us: int) -> Dictionary:
	var t_real := Time.get_ticks_usec()
	var t0 := _now()
	var worked := false
	while true:
		if _phase == Phase.IDLE:
			if not _begin(false):
				break
			worked = true
			if _now() - t0 >= budget_us:
				break   # pencere açılışı bütçeyi bitirdi: dilimler sonraki karede
		_run_unit()
		worked = true
		if _now() - t0 >= budget_us:
			break
	var ms := (Time.get_ticks_usec() - t_real) / 1000.0
	if worked:
		stats["steps"] += 1
		stats["step_ms_max"] = maxf(float(stats["step_ms_max"]), ms)
		stats["backlog_max"] = maxi(int(stats["backlog_max"]), backlog_ticks())
	return {"worked": worked, "busy": _phase != Phase.IDLE, "ms": ms}


## BÜTÇESİZ tam senkron (testler, dev ilerletme, yükleme). Dönüş: {changed, resync, parcels, feed_ids, ms}.
## `exact`: inşaattaki TÜM projelerin ilerlemesini şimdi okur.
func sync(exact: bool = false) -> Dictionary:
	var t0 := Time.get_ticks_usec()
	var v0 := _version
	var report := {"changed": false, "resync": false, "parcels": 0, "feed_ids": 0, "ms": 0.0}
	stats["syncs"] += 1
	var sweeps0 := int(stats["full_syncs"])
	while true:
		if _phase != Phase.IDLE:
			_run_unit()
		elif not _begin(false):
			break
	if exact and _begin(true):
		while _phase != Phase.IDLE:
			_run_unit()
	report["changed"] = _version != v0
	report["parcels"] = int(stats["last_parcels"])
	report["feed_ids"] = int(stats["last_feed_ids"])
	report["resync"] = int(stats["full_syncs"]) > sweeps0
	report["ms"] = (Time.get_ticks_usec() - t0) / 1000.0
	return report


func _now() -> int:
	return _vnow if virtual_unit_us > 0 else Time.get_ticks_usec()


# --- pencere ----------------------------------------------------------------------------------------------------

## Tam eşitleme gerekir mi: geçmiş bilinmiyor (feed eksik), kayıt yüklendi (epoch) ya da geri sarma.
func _needs_full(feed: ParcelChangeFeed) -> bool:
	return not feed.complete or (_feed_epoch >= 0 and feed.epoch != _feed_epoch)


## Yeni pencere açar; yapılacak iş yoksa false.
func _begin(exact: bool) -> bool:
	var tick := _facade.current_tick()
	var feed := _facade.parcel_changes_since(_feed_tick)
	var full := _needs_full(feed)
	if not exact and not full and tick == _last_tick:
		return false
	var t0 := Time.get_ticks_usec()
	_vnow += virtual_unit_us / 4
	_w_tick = tick
	_w_exact = exact
	_w_feed = {}
	_w_read = 0
	_w_pos = 0
	_w_fetched = []
	_w_fpos = 0
	_w_changed = false
	var dirty := {}
	if full:
		_full_sync()   # feed (ids boş/güvenilmez) atlanır; yeni değişimler bundan sonra feed'den gelir
	for id in feed.ids:
		# T0 yapılı parsel de okunur (B-025): yol/yıkımla boşalıp belediye arazisi olarak imara açılan T0 parseli sim
		# yapısı alabilir. T0 stoku `developed_by_sim == false` ile `_apply`da satırsız kalır; feed yalnız değişenleri taşır.
		dirty[int(id)] = true
		_w_feed[int(id)] = true
	for pid: int in _staged:
		if exact or int(_due.get(pid, 0)) <= tick:
			if not dirty.has(pid):
				stats["stage_polls"] += 1
			dirty[pid] = true
	stats["last_feed_ids"] = _w_feed.size()
	var keys: Array = dirty.keys()
	keys.sort()
	_w_ids = PackedInt64Array(keys)
	_feed_tick = feed.up_to_tick
	_feed_epoch = feed.epoch
	_phase = Phase.VIEWS
	_w_work_us = Time.get_ticks_usec() - t0
	_note_max("begin_ms_max", _w_work_us)
	return true


## Bir iş birimi (parsel dilimi okuma / okunmuşları uygulama) yürütür.
func _run_unit() -> void:
	var t0 := Time.get_ticks_usec()
	stats["units"] += 1
	_vnow += virtual_unit_us
	_views_unit()
	_w_work_us += Time.get_ticks_usec() - t0
	_note_max("views_ms_max", Time.get_ticks_usec() - t0)


func _views_unit() -> void:
	if _w_fpos < _w_fetched.size():
		# Okunmuş görünümleri uygula: yerleşim hesabı (plan) pahalı olabilir -> birim başına zaman sınırı.
		var t0 := _now()
		var t_apply := Time.get_ticks_usec()
		while _w_fpos < _w_fetched.size():
			var v := _w_fetched[_w_fpos]
			_w_fpos += 1
			stats["applied"] = int(stats.get("applied", 0)) + 1
			if _w_feed.has(v.id):
				_sample.erase(v.id)   # aşama/karar değişti (durma/devam dahil): hız kestirimi yeniden öğrenilir
			_w_changed = _apply(v, _w_fetch_tick) or _w_changed
			if not _w_exact and _now() - t0 >= APPLY_UNIT_US:
				break
		stats["apply_us"] = int(stats.get("apply_us", 0)) + Time.get_ticks_usec() - t_apply
		if _w_fpos >= _w_fetched.size() and _w_pos >= _w_ids.size():
			_finish_window()
		return
	if _w_pos >= _w_ids.size():
		_finish_window()
		return
	var take := EXACT_CHUNK if _w_exact else VIEW_CHUNK
	var chunk := _w_ids.slice(_w_pos, mini(_w_pos + take, _w_ids.size()))
	_w_pos += chunk.size()
	_w_fetch_tick = _facade.current_tick()
	_w_fetched = _read(chunk)
	_w_fpos = 0
	_w_read += chunk.size()


## Parselleri okur (ölçülü); sim'in tanımadığı kimliklerin izleri silinir.
func _read(chunk: PackedInt64Array) -> Array[ParcelView]:
	var t_read := Time.get_ticks_usec()
	var views := _facade.parcel_views(chunk)
	stats["read_us"] = int(stats.get("read_us", 0)) + Time.get_ticks_usec() - t_read
	stats["parcel_reads"] += chunk.size()
	var seen := {}
	for v in views:
		seen[v.id] = true
	for pid in chunk:
		if not seen.has(int(pid)):
			if _shown.has(int(pid)):
				_w_changed = true
			_forget(int(pid))
	return views


# --- tam eşitleme ------------------------------------------------------------------------------------------------

## Kayıt YÜKLENDİ (epoch) / geri sarma / eksik feed: türetilmiş durum BİR KEZ, HEMEN ve bütçesiz kurulur (yükleme anında
## tek seferlik kısa bekleme; kare dağıtımı yalnız artımlı işler içindir). T0 dışı tüm parseller toplu okunur;
## sim'in artık tanımadığı parsellerin izleri silinir. Süre `stats["full_sync_ms"]`.
## BİLİNEN SINIR (B-025 artığı): T0 yapılı parseller süpürmede ATLANIR (~24 bin ham okuma tasarrufu; gerçek dünyada
## başsız ~1,3 s -> ~3,0 s ölçüldü). Yıkımla boşalıp sim yapısı almış bir T0 parseli YÜKLEME sonrası süpürmeyle geri
## gelmez; canlı oyunda feed yolu doğru (yukarıda). Kalıcı çözüm: bayat T0 kümesini sim'den türetmek (facade sorgusu).
func _full_sync() -> void:
	var t0 := Time.get_ticks_usec()
	stats["full_syncs"] += 1
	var tick := _facade.current_tick()
	var stale := _shown.duplicate()
	_staged = {}
	_due = {}
	_sample = {}
	_clock.reset()
	var all := _facade.parcel_ids()
	var changed := false
	var pos := 0
	while pos < all.size():
		var chunk := PackedInt64Array()
		while chunk.size() < EXACT_CHUNK and pos < all.size():
			var pid := int(all[pos])
			pos += 1
			if not _t0_occupied.has(pid):
				chunk.append(pid)
		for v in _read(chunk):
			stale.erase(v.id)
			changed = _apply(v, tick) or changed
	for pid: int in stale:
		_forget(pid)
		changed = true
	if changed:
		_rebuild_columns()
		stats["changed_windows"] += 1
	stats["full_sync_ms"] = (Time.get_ticks_usec() - t0) / 1000.0


func _finish_window() -> void:
	if _w_changed:
		_rebuild_columns()
		stats["changed_windows"] += 1
	_last_tick = _w_tick
	_phase = Phase.IDLE
	stats["windows"] += 1
	stats["last_ms"] = _w_work_us / 1000.0
	stats["last_parcels"] = _w_read
	_w_ids = PackedInt64Array()
	_w_feed = {}
	_w_fetched = []
	_w_fpos = 0


func _note_max(key: String, usec: int) -> void:
	stats[key] = maxf(float(stats.get(key, 0.0)), usec / 1000.0)


# --- parsel -> satır ---------------------------------------------------------------------------------------------

## Tek parsel görünümünü uygular; satırlar değiştiyse true. `now`: okumanın yapıldığı sim günü.
func _apply(v: ParcelView, now: int) -> bool:
	var pid := v.id
	var building := v.developed_by_sim and v.use != ParcelView.USE_NONE and v.units > 0 \
			and (v.development == ParcelView.DEVELOPMENT_UNDER_CONSTRUCTION \
			or v.development == ParcelView.DEVELOPMENT_BUILT or v.development == ParcelView.DEVELOPMENT_STALLED)
	var constructing := v.developed_by_sim and v.development == ParcelView.DEVELOPMENT_UNDER_CONSTRUCTION
	if not constructing:
		_staged.erase(pid)
		_due.erase(pid)
		_sample.erase(pid)
	if not building:
		_unplaced.erase(pid)
		stats["unplaced"] = _unplaced.size()
		if v.developed_by_sim and v.development == ParcelView.DEVELOPMENT_PLANNED and v.use != ParcelView.USE_NONE \
				and v.units > 0:
			_plan_for(pid, v)   # onaylandı, inşaat ~plan_days sonra başlar: yerleşim şimdiden (kritik yolda değil)
		return _drop_rows(pid)
	var cached := _plan_for(pid, v)
	var plan: SimBuildingPlacer.Plan = cached["plan"]
	if constructing:
		_schedule(pid, v, now, plan)
	if plan == null:
		_unplaced[pid] = cached["reason"]
		stats["unplaced"] = _unplaced.size()
		return _drop_rows(pid)
	_unplaced.erase(pid)
	stats["unplaced"] = _unplaced.size()
	var progress := ParcelView.PROGRESS_FULL if v.development == ParcelView.DEVELOPMENT_BUILT else v.progress_pm
	# Görünen kat kademesi aynıysa satır üretimi atlanır (ilerleme aşama içinde her gün değişir).
	var key := "%s|%d|%s" % [v.use, v.units, _placer.stage_key(plan, progress)]
	if _shown.has(pid) and _shown[pid]["key"] == key:
		return false
	var rows := _placer.rows_for(plan, progress)
	var parts := PackedStringArray()
	for r in rows:
		parts.append(r.signature())
	var sig := ";".join(parts)
	var old: Dictionary = _shown.get(pid, {})
	var unchanged: bool = not old.is_empty() and old["sig"] == sig
	_shown[pid] = {"rows": rows, "sig": sig, "key": key}
	return not unchanged


## Nihai yerleşim (önbellekli; kullanım/birim değişirse yeniden): {"use", "units", "plan", "reason"}.
func _plan_for(pid: int, v: ParcelView) -> Dictionary:
	var cached: Dictionary = _plans.get(pid, {})
	if not cached.is_empty() and cached["use"] == v.use and int(cached["units"]) == v.units:
		return cached
	var t_plan := Time.get_ticks_usec()
	var fresh_plan := _placer.plan(pid, v.use, v.units)
	cached = {"use": v.use, "units": v.units, "plan": fresh_plan,
			"reason": &"" if fresh_plan != null else _placer.plan_failure()}
	var plan_us := Time.get_ticks_usec() - t_plan
	stats["plan_us"] = int(stats.get("plan_us", 0)) + plan_us
	stats["plan_n"] = int(stats.get("plan_n", 0)) + 1
	stats["plan_ms_max"] = maxf(float(stats.get("plan_ms_max", 0.0)), plan_us / 1000.0)
	_plans[pid] = cached
	return cached


## İnşaattaki parselin sonraki okuma günü. Kat kademesi başka değişmeyecekse (tek/son kademe) parsel HİÇ yoklanmaz
## (tamamlanma feed'den gelir). Aksi halde kademenin değişeceği gün `SimBuildingStageClock`tan (iki okumadan öğrenilen
## toplam inşaat süresi); süre bilinmiyorsa iki okumadan hız ÜST sınırıyla (geç kalmaz, gerekirse erken yoklar) ve hız
## hiç bilinmiyorsa ertesi gün (öğrenmek için).
func _schedule(pid: int, v: ParcelView, now: int, plan: SimBuildingPlacer.Plan) -> void:
	_staged[pid] = true
	var smp: Vector2i = _sample.get(pid, Vector2i(-1, 0))
	_sample[pid] = Vector2i(now, v.progress_pm)
	var next_progress := _placer.next_stage_progress(plan, v.progress_pm) if plan != null else ParcelView.PROGRESS_FULL
	if next_progress >= ParcelView.PROGRESS_FULL:
		_due[pid] = NEVER
		return
	var gap := _clock.gap("%s|%d" % [v.use, v.units], smp, now, v.progress_pm, next_progress)
	if gap < 0:
		gap = 1
		if smp.x >= 0 and now > smp.x and v.progress_pm >= smp.y:
			# ‰ = floor(geçen_gün * 1000 / toplam): iki okuma arasındaki artış gerçek hızdan en çok 1 ‰ sapar.
			var dp := v.progress_pm - smp.y
			var need := next_progress - v.progress_pm
			gap = maxi(need - 1, 0) * (now - smp.x) / (dp + 1)
	_due[pid] = now + clampi(gap, 1, MAX_POLL_GAP)


## Satırları kaldırır (yerleşim önbelleği kalır: planlıdan inşaata geçişte tekrar hesaplanmaz). Değiştiyse true.
func _drop_rows(pid: int) -> bool:
	if not _shown.has(pid):
		return false
	_shown.erase(pid)
	return true


## Sim'de artık görünmeyen parsel: tüm izleri sil.
func _forget(pid: int) -> void:
	_staged.erase(pid)
	_due.erase(pid)
	_sample.erase(pid)
	_unplaced.erase(pid)
	_plans.erase(pid)
	stats["unplaced"] = _unplaced.size()
	_drop_rows(pid)


func _rebuild_columns() -> void:
	var cols := BuildingColumns.new()
	for pid in parcel_ids():
		for r: SimBuildingPlacer.Row in _shown[int(pid)]["rows"]:
			cols.add(r.parcel_id, r.module, r.x, r.z, r.yaw, r.floors, r.wall, r.roof, r.accent, r.bright, r.flags,
					r.era)
	_columns = cols
	_version += 1
