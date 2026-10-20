class_name EconomySystem
extends SimSystem
## Ekonomi çekirdeği sistemi (T-013): parsel durumu, bölge talep kohortları, yatırımcı kararı, kademeli gelişme.
## Model ve formüller: design/specs/economy-core-v0.md. CAN-03: özel gelişmeyi yalnız bu sistemin yatırımcı kararı
## yazar; belediye komutu (`zoning.propose`) yalnız koşulu değiştirir. Her karar `state.record_reason` ile gerekçelidir.
##
## Sistem DURUM TUTMAZ: kalıcı veri `state.systems["economy"]` içindedir (EconomyState). Nesnedeki alanlar yalnız
## `ParcelSource`/yapılandırmadan TÜRETİLMİŞ değişmez önbelleklerdir (kurulumda bir kez, tick dışında); aynı dünyayı
## veren kaynakla yeniden kurulunca aynıdır. Rastgelelik yalnız `state.rng.stream(&"economy")`.

const SYSTEM := &"economy"

var _cfg: EconomyConfig
var _stock: ExistingStockSource
var _ids: PackedInt64Array = PackedInt64Array()        # parsel kimlikleri, artan
var _region_of: PackedInt32Array = PackedInt32Array()  # parsel indeksi -> bölge indeksi
var _area: PackedInt32Array = PackedInt32Array()       # m2
var _base_zone: PackedStringArray = PackedStringArray()  # kaynak şablonundaki başlangıç imarı
var _base_land: PackedInt64Array = PackedInt64Array()  # kaynak şablonundaki başlangıç arsa değeri
var _region_codes: PackedStringArray = PackedStringArray()  # bölge indeksi -> kod (sıralı)


## Kurulum sorunu (Türkçe metin) ya da "". Kaynak, yapılandırma ve stok tutarlılığı.
static func setup_problem(parcels: ParcelSource, cfg: EconomyConfig, stock: ExistingStockSource) -> String:
	if parcels == null:
		return "parsel kaynağı yok"
	if cfg == null or not cfg.is_valid():
		return "ekonomi yapılandırması geçersiz: %s" % ("null" if cfg == null else cfg.error)
	if stock == null:
		return ""
	if stock is ListStockSource and not (stock as ListStockSource).is_valid():
		return "stok kaynağı geçersiz: %s" % ", ".join((stock as ListStockSource).errors)
	for id in stock.parcel_ids():
		if not parcels.has_parcel(id):
			return "stok bilinmeyen parseli adlandırıyor: %d" % id
		if EconomyState.use_id(stock.use_of(id)) == EconomyConfig.USE_NONE or stock.units_of(id) < 1:
			return "stok parseli %d geçersiz kullanım/birim" % id
		if stock.owner_of(id) < 0 or stock.owner_of(id) > cfg.investors.size():
			return "stok parseli %d owner yatırımcı havuzu dışında (0..%d)" % [id, cfg.investors.size()]
	return ""


## Sistem; sorunda push_error + null. `stock` null ise stoksuz dünya.
static func create(parcels: ParcelSource, cfg: EconomyConfig, stock: ExistingStockSource = null) -> EconomySystem:
	var problem := setup_problem(parcels, cfg, stock)
	if not problem.is_empty():
		push_error("EconomySystem: %s" % problem)
		return null
	var system := EconomySystem.new()
	system._cfg = cfg
	system._stock = stock if stock != null else EmptyStockSource.new()
	system._cache_static(parcels)
	return system


func system_id() -> StringName:
	return SYSTEM


func on_daily(state: GameState) -> void:
	var d := _ensure_state(state)
	var starts_today := PackedInt32Array()
	starts_today.resize(_region_codes.size())
	_progress_projects(state, d)  # önce ilerlet: bugün onaylanan proje yarın saymaya başlar
	_scan_zone_changes(state, d)
	_run_attention(state, d, starts_today)
	_run_reviews(state, d, starts_today)


func on_monthly(state: GameState) -> void:
	var d := _ensure_state(state)
	_update_cohorts(d)
	_update_land_values(d)
	_collect_rents(d)
	_inject_capital(d)


# --- Kurulum ---

func _cache_static(parcels: ParcelSource) -> void:
	_ids = parcels.parcel_ids()
	var n := _ids.size()
	var codes: Array = []
	var region_names: Array[StringName] = []
	_area.resize(n)
	_base_land.resize(n)
	_base_zone.resize(n)
	for i in n:
		var view := parcels.template(_ids[i])
		_area[i] = view.area_m2
		_base_land[i] = view.land_value
		_base_zone[i] = String(view.zone)
		region_names.append(view.region_code)
		if not codes.has(String(view.region_code)):
			codes.append(String(view.region_code))
	codes.sort()
	_region_codes = PackedStringArray(codes)
	_region_of.resize(n)
	for i in n:
		_region_of[i] = codes.find(String(region_names[i]))


## İlk tick'te (ya da durum yoksa) ekonomi durumunu kurar. Yüklenen kayıtta durum zaten vardır.
func _ensure_state(state: GameState) -> Dictionary:
	var d := EconomyState.data(state)
	if not d.is_empty():
		return d
	d = state.system_data(SYSTEM)
	var n := _ids.size()
	d["version"] = EconomyState.VERSION
	d["parcel_ids"] = _ids.duplicate()
	var stage := PackedByteArray()
	stage.resize(n)
	d["stage"] = stage
	var use := PackedByteArray()
	use.resize(n)
	d["use"] = use
	var units := PackedInt32Array()
	units.resize(n)
	d["units"] = units
	var owner_id := PackedInt32Array()
	owner_id.resize(n)
	d["owner_id"] = owner_id
	d["land_value"] = _base_land.duplicate()
	var days_left := PackedInt32Array()
	days_left.resize(n)
	d["days_left"] = days_left
	var reason_id := PackedInt64Array()
	reason_id.resize(n)
	d["reason_id"] = reason_id
	var last_code := PackedByteArray()
	last_code.resize(n)
	d["last_code"] = last_code
	var last_reason_tick := PackedInt32Array()
	last_reason_tick.resize(n)
	last_reason_tick.fill(-1)
	d["last_reason_tick"] = last_reason_tick
	var next_review := PackedInt32Array()
	next_review.resize(n)
	d["next_review"] = next_review
	d["review_cursor"] = 0
	for key in EconomyState.SPARSE_KEYS:
		d[key] = {}
	d["regions"] = _initial_regions()
	d["investors"] = _initial_investors()
	var totals := {}
	for key in EconomyState.TOTAL_KEYS:
		totals[key] = 0
	d["totals"] = totals
	_apply_stock(d)
	return d


func _initial_regions() -> Dictionary:
	var rn := _region_codes.size()
	var regions := {"codes": _region_codes.duplicate()}
	for column in EconomyState.REGION_COLUMNS:
		var col := PackedInt64Array()
		col.resize(rn)
		regions[column] = col
	for r in rn:
		var params := _cfg.region_params(StringName(_region_codes[r]))
		regions["latent_hh"][r] = params["initial_households"]
		regions["income_pm"][r] = params["income_pm"]
		regions["access_pm"][r] = params["access_pm"]
		regions["service_pm"][r] = params["service_pm"]
		regions["infra_cap"][r] = params["infra_capacity_units"]
	return regions


func _initial_investors() -> Dictionary:
	var capital := PackedInt64Array()
	var shift := PackedInt32Array()
	var inflow := PackedInt64Array()
	for entry in _cfg.investors:
		capital.append(entry["capital"])
		shift.append(entry["threshold_shift"])
		inflow.append(entry["monthly_inflow"])
	return {"capital": capital, "threshold_shift": shift, "monthly_inflow": inflow}


## T0 mevcut stok: parseller `built` doğar (karar kaydı yok; başlangıç durumu). Bölge arzı ve hane talebi buna göre
## kurulur.
## NOT: `(d["x"] as PackedXArray)[i] = v` yazımı kopyaya yazar (etkisiz); yazarken tipli yerel referans kullanılır.
@warning_ignore("integer_division")
func _apply_stock(d: Dictionary) -> void:
	var regions: Dictionary = d["regions"]
	var stage: PackedByteArray = d["stage"]
	var use_col: PackedByteArray = d["use"]
	var units_col: PackedInt32Array = d["units"]
	var owner_col: PackedInt32Array = d["owner_id"]
	var res_built: PackedInt64Array = regions["res_built"]
	var com_built: PackedInt64Array = regions["com_built"]
	for id in _stock.parcel_ids():
		var i := EconomyState.index_of(d, id)
		var use := EconomyState.use_id(_stock.use_of(id))
		var units := _stock.units_of(id)
		stage[i] = EconomyState.STAGE_BUILT
		use_col[i] = use
		units_col[i] = units
		owner_col[i] = _stock.owner_of(id)
		if use == EconomyConfig.USE_RESIDENTIAL:
			res_built[_region_of[i]] += units
		else:
			com_built[_region_of[i]] += units
	var latent: PackedInt64Array = regions["latent_hh"]
	var occupancy := _cfg.p("initial_occupancy_pm")
	for r in _region_codes.size():
		latent[r] += res_built[r] * occupancy / 1000


# --- Aylık kohort akışı (SIM-01) ---

## Hane kohortu: çekim (erişim/hizmet/iş dengesi) -> işaretli aylık büyüme; kesir `growth_frac`'ta birikir.
@warning_ignore("integer_division")
func _update_cohorts(d: Dictionary) -> void:
	var regions: Dictionary = d["regions"]
	var latent: PackedInt64Array = regions["latent_hh"]
	var frac: PackedInt64Array = regions["growth_frac"]
	var res_built: PackedInt64Array = regions["res_built"]
	var com_built: PackedInt64Array = regions["com_built"]
	var access: PackedInt64Array = regions["access_pm"]
	var service: PackedInt64Array = regions["service_pm"]
	var w_access := _cfg.p("w_access")
	var w_service := _cfg.p("w_service")
	var w_jobs := _cfg.p("w_jobs")
	var w_sum := w_access + w_service + w_jobs
	for r in latent.size():
		var housed := mini(latent[r], res_built[r])
		var jobs := com_built[r] * _cfg.p("jobs_per_commercial_unit")
		var needed := housed * _cfg.p("jobs_needed_per_household_pm") / 1000
		var job_balance := 500 if needed <= 0 else mini(1000, EconomyMath.ratio_pm(jobs, needed))
		var pull := (access[r] * w_access + service[r] * w_service + job_balance * w_jobs) / w_sum
		var growth_pm := _cfg.p("growth_base_pm") * (pull - 500) / 500
		var step := EconomyMath.accumulate_pm(latent[r], growth_pm, frac[r])
		latent[r] = maxi(0, latent[r] + step[0])
		frac[r] = step[1]


# --- Değerlendirme zamanlaması (SIM-08) ---

## İmar yürürlüğe girmiş parsellerde (bindirmede yürürlükteki imar değişmiş) yatırımcı dikkatini ve gerekçe sayacını
## sıfırlar. Komut kimliği gerekçenin konusuna girer ("imarımın sonucu ne oldu?").
func _scan_zone_changes(state: GameState, d: Dictionary) -> void:
	var overlay := ParcelZoningSystem.overlay_ref(state)
	if overlay.is_empty():
		return
	var zone_seen: Dictionary = d["zone_seen"]
	var attention: Dictionary = d["attention"]
	var attention_cmd: Dictionary = d["attention_cmd"]
	var stage: PackedByteArray = d["stage"]
	var last_code: PackedByteArray = d["last_code"]
	var last_reason_tick: PackedInt32Array = d["last_reason_tick"]
	var next_review: PackedInt32Array = d["next_review"]
	var ids: Array = overlay.keys()
	ids.sort()
	for id: int in ids:
		var entry: Dictionary = overlay[id]
		var zone: StringName = entry.get("zone", &"")
		if zone == &"":
			continue
		var i := EconomyState.index_of(d, id)
		if i < 0:
			continue
		if StringName(zone_seen.get(i, _base_zone[i])) == zone:
			continue
		zone_seen[i] = String(zone)
		if stage[i] == EconomyState.STAGE_VACANT:
			attention[i] = state.tick + _cfg.p("attention_delay_days")
			attention_cmd[i] = int(entry.get("command_id", 0))
			last_code[i] = EconomyState.CODE_NONE
			last_reason_tick[i] = -1
			next_review[i] = 0


## Vadesi gelen imar-sonrası dikkat değerlendirmeleri (ön eleme yok: oyuncunun kararının sonucu mutlaka görünür).
func _run_attention(state: GameState, d: Dictionary, starts_today: PackedInt32Array) -> void:
	var attention: Dictionary = d["attention"]
	if attention.is_empty():
		return
	var attention_cmd: Dictionary = d["attention_cmd"]
	var stage: PackedByteArray = d["stage"]
	var due: Array = []
	for i: int in attention:
		if int(attention[i]) <= state.tick:
			due.append(i)
	due.sort()
	for i: int in due:
		var command_id: int = attention_cmd.get(i, 0)
		attention.erase(i)
		attention_cmd.erase(i)
		if stage[i] == EconomyState.STAGE_VACANT:
			_evaluate(state, d, i, command_id, starts_today)


## Periyodik tarama: bir imleç boş parselleri sırayla gezer (tick başına n/periyot parsel => her parsel ~`periyot`
## günde bir görülür); yapılanmaya kapalı imar, ölü pazar (izinli kullanımların talebi `prescreen_demand_pm` altı),
## bekleme süresindeki (`next_review`) parsel atlanır; bölge başına günlük başlangıç sınırı ve tick başına azami tam
## değerlendirme (`max_reviews_per_tick`, yatırımcı dikkati kıt) vardır. İmleç durumda saklanır: kesilen tarama kaldığı
## yerden sürer, yüksek indeksli parseller geride kalmaz. Tamamen deterministik (RNG yalnız değerlendirmede).
@warning_ignore("integer_division")
func _run_reviews(state: GameState, d: Dictionary, starts_today: PackedInt32Array) -> void:
	var n := _ids.size()
	if _cfg.p("review_enabled") == 0 or n == 0:
		return
	var period := _cfg.p("review_period_days")
	var scan_budget := (n + period - 1) / period
	var max_reviews := _cfg.p("max_reviews_per_tick")
	var stage: PackedByteArray = d["stage"]
	var next_review: PackedInt32Array = d["next_review"]
	var regions: Dictionary = d["regions"]
	var overlay := ParcelZoningSystem.overlay_ref(state)
	var prescreen := _cfg.p("prescreen_demand_pm")
	var max_starts := _cfg.p("max_starts_per_region_per_day")
	var cursor: int = d["review_cursor"]
	var scanned := 0
	var reviews := 0
	while scanned < scan_budget and reviews < max_reviews:
		var i := cursor
		cursor = (cursor + 1) % n
		scanned += 1
		if stage[i] != EconomyState.STAGE_VACANT or next_review[i] > state.tick:
			continue
		var r := _region_of[i]
		if starts_today[r] >= max_starts:
			continue
		var uses: Array = _cfg.zone_profile(_effective_zone(overlay, i)).get("uses", [])
		var best := 0
		for use: int in uses:
			best = maxi(best, EconomyMath.region_demand_pm(_cfg, regions, r, use, 0))
		if uses.is_empty() or best < prescreen:
			continue
		reviews += 1
		_evaluate(state, d, i, 0, starts_today)
	d["review_cursor"] = cursor


func _effective_zone(overlay: Dictionary, i: int) -> StringName:
	var entry: Variant = overlay.get(_ids[i], null)
	if entry is Dictionary and entry.get("zone", &"") != &"":
		return entry["zone"]
	return StringName(_base_zone[i])


# --- Yatırımcı kararı (SIM-02) ---

func _evaluate(state: GameState, d: Dictionary, i: int, command_id: int, starts_today: PackedInt32Array) -> void:
	var regions: Dictionary = d["regions"]
	var r := _region_of[i]
	var overlay_entry: Variant = ParcelZoningSystem.overlay_ref(state).get(_ids[i], null)
	var zone := _effective_zone(ParcelZoningSystem.overlay_ref(state), i)
	var profile := _cfg.zone_profile(zone)
	var allowed: Array = profile.get("uses", [])
	var use := _best_use(regions, r, allowed)
	var density: int = profile.get("density_pm", 0)
	var max_height := -1
	if overlay_entry is Dictionary:
		if int(overlay_entry.get("density", -1)) >= 0:
			density = int(overlay_entry["density"])
		max_height = int(overlay_entry.get("max_height_m", -1))
	var units := EconomyMath.project_units(_area[i], _cfg.use_param(use, "units_per_1000m2"), density, max_height,
		_cfg.p("storey_m"), _cfg.p("reference_floors"))
	var rng := state.rng.stream(SYSTEM)
	var investors: Dictionary = d["investors"]
	var investor := rng.randi_range(0, (investors["capital"] as PackedInt64Array).size() - 1)
	var sentiment := rng.randi_range(-_cfg.p("sentiment_range"), _cfg.p("sentiment_range"))
	var current_demand := EconomyMath.region_demand_pm(_cfg, regions, r, use, 0)
	var result := InvestorDecision.decide(_cfg, {
		"use": use, "zone_ok": not allowed.is_empty(), "units": units,
		"land_value": (d["land_value"] as PackedInt64Array)[i],
		"capital": (investors["capital"] as PackedInt64Array)[investor],
		"infra_cap": (regions["infra_cap"] as PackedInt64Array)[r],
		"infra_load": EconomyMath.infra_load(_cfg, regions, r),
		"demand_after_pm": EconomyMath.region_demand_pm(_cfg, regions, r, use, units),
		"rent_mult_pm": EconomyMath.rent_mult_pm(current_demand, _cfg.p("rent_floor_pm"), _cfg.p("rent_cap_pm")),
		"sentiment": sentiment, "threshold_shift": (investors["threshold_shift"] as PackedInt32Array)[investor],
	})
	var totals: Dictionary = d["totals"]
	totals["evaluations"] += 1
	if result["positive"]:
		_approve(state, d, i, investor, use, units, result, command_id, starts_today)
	else:
		_decline(state, d, i, investor, use, units, result, command_id)


## Kullanım seçimi: izinli kullanımlardan mevcut talebi en yüksek olan (eşitlikte ilk); izin yoksa referans konut.
func _best_use(regions: Dictionary, r: int, allowed: Array) -> int:
	if allowed.is_empty():
		return EconomyConfig.USE_RESIDENTIAL
	var best_use: int = allowed[0]
	var best_demand := -1
	for use: int in allowed:
		var demand := EconomyMath.region_demand_pm(_cfg, regions, r, use, 0)
		if demand > best_demand:
			best_demand = demand
			best_use = use
	return best_use


func _record(state: GameState, i: int, investor: int, result: Dictionary, command_id: int) -> int:
	var subjects := PackedStringArray([String(SimContract.parcel_ref(_ids[i]))])
	if command_id > 0:
		subjects.append(String(SimContract.ref(SimContract.REF_COMMAND, command_id)))
	return state.record_reason(StringName("actor.investor.%d" % (investor + 1)), &"decision.investor.develop",
		result["factors"], result["threshold"], EconomyState.CODE_NAMES[result["code"]], subjects)


func _approve(state: GameState, d: Dictionary, i: int, investor: int, use: int, units: int, result: Dictionary,
		command_id: int, starts_today: PackedInt32Array) -> void:
	var reason_id := _record(state, i, investor, result, command_id)
	var capital: PackedInt64Array = (d["investors"] as Dictionary)["capital"]
	capital[investor] -= result["outlay"]
	var stage: PackedByteArray = d["stage"]
	var use_col: PackedByteArray = d["use"]
	var units_col: PackedInt32Array = d["units"]
	var owner_col: PackedInt32Array = d["owner_id"]
	var days_left: PackedInt32Array = d["days_left"]
	var reason_col: PackedInt64Array = d["reason_id"]
	var last_code: PackedByteArray = d["last_code"]
	var last_tick: PackedInt32Array = d["last_reason_tick"]
	stage[i] = EconomyState.STAGE_PLANNED
	use_col[i] = use
	units_col[i] = units
	owner_col[i] = investor + 1
	days_left[i] = _cfg.use_param(use, "plan_days")
	reason_col[i] = reason_id
	last_code[i] = EconomyState.CODE_APPROVED
	last_tick[i] = state.tick
	var regions: Dictionary = d["regions"]
	var pipe: PackedInt64Array = regions["res_pipe"] if use == EconomyConfig.USE_RESIDENTIAL else regions["com_pipe"]
	pipe[_region_of[i]] += units
	(d["active"] as Dictionary)[i] = true
	starts_today[_region_of[i]] += 1
	var totals: Dictionary = d["totals"]
	totals["approvals"] += 1
	totals["land_sales"] += (d["land_value"] as PackedInt64Array)[i]
	totals["construction_spend"] += result["build_cost"]
	SimEventLog.emit(state, &"actor.decided", &"event.investor.develop",
		PackedStringArray([String(SimContract.parcel_ref(_ids[i]))]),
		{"use": String(EconomyState.use_name(use)), "units": units}, PackedInt64Array([reason_id]), command_id,
		StringName("actor.investor.%d" % (investor + 1)))


## Olumsuz karar: sessiz değil. Gerekçe yalnız neden değiştiyse ya da tekrarlanabilir neden için pencere dolduysa
## yazılır
## (kayıt taşmasın); yazılmayan tarama `declines - declines_recorded` olarak sayılır.
func _decline(state: GameState, d: Dictionary, i: int, investor: int, use: int, units: int, result: Dictionary,
		command_id: int) -> void:
	var totals: Dictionary = d["totals"]
	totals["declines"] += 1
	var next_review: PackedInt32Array = d["next_review"]
	next_review[i] = state.tick + _cfg.p("decline_backoff_days")
	var code: int = result["code"]
	var last_code: PackedByteArray = d["last_code"]
	var last_tick: PackedInt32Array = d["last_reason_tick"]
	var repeatable := code == EconomyState.CODE_DEMAND or code == EconomyState.CODE_RETURN
	var changed := last_code[i] != code
	var repeat_days := _cfg.p("negative_repeat_days")
	var window_over: bool = repeatable and (last_tick[i] < 0 or state.tick - last_tick[i] >= repeat_days)
	if not changed and not window_over:
		return
	var reason_id := _record(state, i, investor, result, command_id)
	last_code[i] = code
	last_tick[i] = state.tick
	var reason_col: PackedInt64Array = d["reason_id"]
	reason_col[i] = reason_id
	totals["declines_recorded"] += 1
	SimEventLog.emit(state, &"actor.decided", &"event.investor.declined",
		PackedStringArray([String(SimContract.parcel_ref(_ids[i]))]),
		{"code": String(EconomyState.CODE_NAMES[code]), "use": String(EconomyState.use_name(use)), "units": units},
		PackedInt64Array([reason_id]), command_id, StringName("actor.investor.%d" % (investor + 1)))


# --- Kademeli gelişme (SIM-03/08) ---

## `planned` -> `under_construction` -> `built`; her aşama `days_left` gün sürer. İnşaatta bölge altyapı yükü kapasiteyi
## aşarsa (kapasite düşünce; T-014) proje `stalled` olur, süre işlemez; kapasite dönünce sürer. Sıralı indeks
## iterasyonu.
func _progress_projects(state: GameState, d: Dictionary) -> void:
	var active: Dictionary = d["active"]
	if active.is_empty():
		return
	var keys: Array = active.keys()
	keys.sort()
	for i: int in keys:
		match (d["stage"] as PackedByteArray)[i]:
			EconomyState.STAGE_PLANNED:
				_tick_planned(state, d, i)
			EconomyState.STAGE_UNDER_CONSTRUCTION:
				_tick_construction(state, d, i)
			EconomyState.STAGE_STALLED:
				_tick_stalled(state, d, i)


func _headroom(d: Dictionary, i: int) -> int:
	var regions: Dictionary = d["regions"]
	var r := _region_of[i]
	return int((regions["infra_cap"] as PackedInt64Array)[r]) - EconomyMath.infra_load(_cfg, regions, r)


func _tick_planned(state: GameState, d: Dictionary, i: int) -> void:
	var days_left: PackedInt32Array = d["days_left"]
	days_left[i] -= 1
	if days_left[i] > 0:
		return
	var use: int = (d["use"] as PackedByteArray)[i]
	var stage: PackedByteArray = d["stage"]
	stage[i] = EconomyState.STAGE_UNDER_CONSTRUCTION
	days_left[i] = _cfg.use_param(use, "construction_base_days") \
		+ (d["units"] as PackedInt32Array)[i] * _cfg.use_param(use, "construction_days_per_unit")
	_emit_parcel_event(state, d, i, &"event.construction.started", int((d["reason_id"] as PackedInt64Array)[i]))


func _tick_construction(state: GameState, d: Dictionary, i: int) -> void:
	if _headroom(d, i) < 0:
		_change_construction(state, d, i, EconomyState.STAGE_STALLED, &"construction_stalled",
			&"event.construction.stalled", -1000)
		return
	var days_left: PackedInt32Array = d["days_left"]
	days_left[i] -= 1
	if days_left[i] > 0:
		return
	var regions: Dictionary = d["regions"]
	var use: int = (d["use"] as PackedByteArray)[i]
	var units: int = (d["units"] as PackedInt32Array)[i]
	var r := _region_of[i]
	var pipe: PackedInt64Array = regions["res_pipe"] if use == EconomyConfig.USE_RESIDENTIAL else regions["com_pipe"]
	var built: PackedInt64Array = regions["res_built"] if use == EconomyConfig.USE_RESIDENTIAL else regions["com_built"]
	pipe[r] -= units
	built[r] += units
	var stage: PackedByteArray = d["stage"]
	stage[i] = EconomyState.STAGE_BUILT
	(d["active"] as Dictionary).erase(i)
	(d["totals"] as Dictionary)["completions"] += 1
	_emit_parcel_event(state, d, i, &"event.construction.completed", int((d["reason_id"] as PackedInt64Array)[i]))


func _tick_stalled(state: GameState, d: Dictionary, i: int) -> void:
	var headroom := _headroom(d, i)
	if headroom < 0:
		return
	var cap: int = (d["regions"]["infra_cap"] as PackedInt64Array)[_region_of[i]]
	var value := mini(_cfg.p("infra_bonus_max"), EconomyMath.ratio_pm(headroom, cap))
	_change_construction(state, d, i, EconomyState.STAGE_UNDER_CONSTRUCTION, &"construction_resumed",
		&"event.construction.resumed", value)


## Durma/devam kararı: sahibi yatırımcının gerekçeli kararı (eşik 0: altyapı etkeni negatifse devam etmez).
func _change_construction(state: GameState, d: Dictionary, i: int, new_stage: int, code: StringName,
		message_key: StringName, infra_value: int) -> void:
	var reason_col: PackedInt64Array = d["reason_id"]
	var owner_id: int = (d["owner_id"] as PackedInt32Array)[i]
	var parents := PackedInt64Array()
	if reason_col[i] > 0:
		parents.append(reason_col[i])
	var reason_id := state.record_reason(StringName("actor.investor.%d" % owner_id), &"decision.investor.continue",
		[{"name": InvestorDecision.F_INFRA, "value": infra_value, "weight": _cfg.p("w_infrastructure")}], 0, code,
		PackedStringArray([String(SimContract.parcel_ref(_ids[i]))]), parents)
	reason_col[i] = reason_id
	var stage: PackedByteArray = d["stage"]
	stage[i] = new_stage
	if new_stage == EconomyState.STAGE_STALLED:
		(d["totals"] as Dictionary)["stalls"] += 1
	_emit_parcel_event(state, d, i, message_key, reason_id)


func _emit_parcel_event(state: GameState, d: Dictionary, i: int, message_key: StringName, reason_id: int) -> void:
	var owner_id: int = (d["owner_id"] as PackedInt32Array)[i]
	var args := {
		"use": String(EconomyState.use_name((d["use"] as PackedByteArray)[i])),
		"units": (d["units"] as PackedInt32Array)[i],
	}
	SimEventLog.emit(state, &"parcel.changed", message_key,
		PackedStringArray([String(SimContract.parcel_ref(_ids[i]))]), args, PackedInt64Array([reason_id]), 0,
		StringName("actor.investor.%d" % owner_id))


# --- Arsa değeri (SIM-07 aşırı talep -> spekülasyon, kısmi) ve kira geliri ---

## Boş yapılabilir parsellerde aylık: izinli kullanımların en yüksek talebi `speculation_demand_pm` üstündeyse arsa
## değeri
## `speculation_rate_pm` kadar artar (tavan: taban x max_multiplier_pm); `relax_demand_pm` altındaysa taban değere doğru
## `relax_rate_pm` kadar geri çekilir. Yapılı/yapılmakta olan ve yapılanmaya kapalı imarlı parsellere dokunulmaz.
@warning_ignore("integer_division")
func _update_land_values(d: Dictionary) -> void:
	var regions: Dictionary = d["regions"]
	var rn := _region_codes.size()
	var demand_by_use: Array = [PackedInt32Array(), PackedInt32Array(), PackedInt32Array()]
	for use in [EconomyConfig.USE_RESIDENTIAL, EconomyConfig.USE_COMMERCIAL]:
		var col := PackedInt32Array()
		col.resize(rn)
		for r in rn:
			col[r] = EconomyMath.region_demand_pm(_cfg, regions, r, use, 0)
		demand_by_use[use] = col
	var zone_demand := {}  # imar (String) -> bölge başına izinli kullanımların en yüksek talebi (-1 = yapılanmaya kapalı)
	var zone_seen: Dictionary = d["zone_seen"]
	var stage: PackedByteArray = d["stage"]
	var land: PackedInt64Array = d["land_value"]
	var spec_demand := _cfg.p("speculation_demand_pm")
	var spec_rate := _cfg.p("speculation_rate_pm")
	var relax_demand := _cfg.p("relax_demand_pm")
	var relax_rate := _cfg.p("relax_rate_pm")
	var max_mult := _cfg.p("max_multiplier_pm")
	for i in _ids.size():
		if stage[i] != EconomyState.STAGE_VACANT:
			continue
		var zone: String = zone_seen.get(i, _base_zone[i])
		if not zone_demand.has(zone):
			zone_demand[zone] = _zone_demand_by_region(zone, demand_by_use, rn)
		var demand: int = (zone_demand[zone] as PackedInt32Array)[_region_of[i]]
		if demand < 0:
			continue
		var base: int = _base_land[i]
		if demand >= spec_demand:
			land[i] = mini(land[i] + land[i] * spec_rate / 1000, base * max_mult / 1000)
		elif demand <= relax_demand and land[i] > base:
			land[i] -= maxi(1, (land[i] - base) * relax_rate / 1000)


func _zone_demand_by_region(zone: String, demand_by_use: Array, rn: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(rn)
	var uses: Array = _cfg.zone_profile(StringName(zone)).get("uses", [])
	for r in rn:
		var demand := -1 if uses.is_empty() else 0
		for use: int in uses:
			demand = maxi(demand, (demand_by_use[use] as PackedInt32Array)[r])
		out[r] = demand
	return out


## Aylık dış sermaye girdisi (kredi/diğer gelir): her yatırımcının sermayesine `monthly_inflow` eklenir.
func _inject_capital(d: Dictionary) -> void:
	var investors: Dictionary = d["investors"]
	var capital: PackedInt64Array = investors["capital"]
	var inflow: PackedInt64Array = investors["monthly_inflow"]
	var totals: Dictionary = d["totals"]
	for k in capital.size():
		capital[k] += inflow[k]
		totals["capital_inflow"] += inflow[k]


## Yatırımcıya ait yapılı parsellerin aylık kirası: birim x birim kirası x talep kira çarpanı. Finansman geri bildirimi:
## sermaye artar, yeni yatırımlar mümkün olur. Arsa sahibine ait T0 stoku yatırımcı geliri üretmez.
@warning_ignore("integer_division")
func _collect_rents(d: Dictionary) -> void:
	var regions: Dictionary = d["regions"]
	var stage: PackedByteArray = d["stage"]
	var use_col: PackedByteArray = d["use"]
	var units_col: PackedInt32Array = d["units"]
	var owner_col: PackedInt32Array = d["owner_id"]
	var capital: PackedInt64Array = (d["investors"] as Dictionary)["capital"]
	var totals: Dictionary = d["totals"]
	var rent_floor := _cfg.p("rent_floor_pm")
	var rent_cap := _cfg.p("rent_cap_pm")
	var demand_cache := {}
	for i in _ids.size():
		if stage[i] != EconomyState.STAGE_BUILT or owner_col[i] <= 0:
			continue
		var use: int = use_col[i]
		var key := _region_of[i] * 4 + use
		if not demand_cache.has(key):
			demand_cache[key] = EconomyMath.region_demand_pm(_cfg, regions, _region_of[i], use, 0)
		var income: int = units_col[i] * _cfg.use_param(use, "rent_per_unit_month") \
			* EconomyMath.rent_mult_pm(demand_cache[key], rent_floor, rent_cap) / 1000
		capital[owner_col[i] - 1] += income
		totals["rent_income"] += income
