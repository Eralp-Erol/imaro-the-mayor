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
## Ön eleme önbelleğinde "bu imarda kullanım yok" işareti (talep değeri hiçbir zaman bu kadar küçük değildir).
const PRESCREEN_NO_USE := -2147483648
## T-043A: `unplanned_land_enabled` iken yürürlükte oyuncu planı olmayan boş parselin "imarı" (gerçek bir imar anahtarı
## değildir; profil yoktur). `_run_reviews` ön elemesi ve `_evaluate` bunu ayrı ele alır.
const UNPLANNED_ZONE := &"#unplanned"
## Plansız parselin başvuru projesi için bakılan kullanımlar (hangi pazarın canlı olduğu): konut, ticaret.
const REFERENCE_USES: Array[int] = [EconomyConfig.USE_RESIDENTIAL, EconomyConfig.USE_COMMERCIAL]

var _cfg: EconomyConfig
var _stock: ExistingStockSource
var _ids: PackedInt64Array = PackedInt64Array()        # parsel kimlikleri, artan
var _region_of: PackedInt32Array = PackedInt32Array()  # parsel indeksi -> bölge indeksi
var _area: PackedInt32Array = PackedInt32Array()       # m2
var _base_zone: PackedStringArray = PackedStringArray()  # kaynak şablonundaki başlangıç imarı
var _base_land: PackedInt64Array = PackedInt64Array()  # kaynak şablonundaki başlangıç arsa değeri
var _region_codes: PackedStringArray = PackedStringArray()  # bölge indeksi -> kod (sıralı)
## T-045: değişen parsel halkası. DURUM DEĞİL (kayda/hash'e girmez); sınırlı, türetilmiş, yüklemede boşalır.
var _changes: ParcelChangeLog
## T-043A: `decision.unplanned_land_enabled` (kurulumda bir kez; yapılandırma değişmez). Kapalıyken
## bütün yollar eskisiyle
## bit-eşittir.
var _unplanned_on: bool = false
## T-043B: öncelikli değerlendirme kuyruğu (`decision.priority_review_enabled` ve `unplanned_land_enabled` ikisi 1).
## Kapalıyken hiçbir yeni yol çalışmaz (bit-eşit). Yarıçap cm^2 ve K önbelleğidir (yapılandırma değişmez).
var _priority_on: bool = false
var _priority_radius2_cm: int = 0
var _priority_max_parcels: int = 0
var _center_x_cm: PackedInt64Array = PackedInt64Array()  # parsel indeksi -> merkez x (cm), kaynak şablonundan
var _center_z_cm: PackedInt64Array = PackedInt64Array()
var _stock_cols: Dictionary = {}  # T-050: T0 stok sütunları (EconomyStockColumns); stok statik, kurulumda türetilir
## T-078: yan sınıflar (`_cache_static`ten sonra kurulur): proje yaşam döngüsü ve aylık akış. Durum tutmazlar.
var _projects: EconomyProjects
var _monthly: EconomyMonthly


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
	system._changes = ParcelChangeLog.new(cfg.p("change_window_ticks"))
	system._unplanned_on = cfg.p("unplanned_land_enabled") == 1
	system._priority_on = system._unplanned_on and cfg.p("priority_review_enabled") == 1
	var radius_cm := cfg.p("priority_radius_m") * 100
	system._priority_radius2_cm = radius_cm * radius_cm
	system._priority_max_parcels = cfg.p("priority_max_parcels")
	system._stock = stock if stock != null else EmptyStockSource.new()
	system._cache_static(parcels)
	system._stock_cols = EconomyStockColumns.build(system._ids, system._region_of, system._region_codes.size(),
			system._stock)
	system._projects = EconomyProjects.new(cfg, system._ids, system._region_codes, system._region_of, system._changes)
	system._monthly = EconomyMonthly.new(cfg, system._ids, system._region_of, system._region_codes, system._base_land,
			system._base_zone, system._unplanned_on)
	return system


func system_id() -> StringName:
	return SYSTEM


## T-045 · Değişen parsel halkası (salt okunur sorgu; facade `parcel_changes_since` okur). Durum DEĞİLDİR.
func change_log() -> ParcelChangeLog:
	return _changes


## T-042b · Statik parsel sütunları (kaynaktan türer, durum DEĞİL; salt okunur): kamulaştırma etkisi ve yakınlık için.
func static_columns() -> Dictionary:
	return {"region_of": _region_of, "center_x": _center_x_cm, "center_z": _center_z_cm, "codes": _region_codes}


## T-078 · Bölge değiştirici kapısı: dış sistemlerin (komşu belediyeler, makro; M3) ekonomi bölge sütunlarına
## girdiği TEK nokta (`EconomyRegionGate`). Başarıda "", aksi halde ret kodu (durum DEĞİŞMEZ). Çağıran gerekçesini
## kendi kaydeder.
func apply_region_modifier(state: GameState, region_code: StringName, column: StringName, amount: int) -> StringName:
	return EconomyRegionGate.apply(EconomyState.data(state), region_code, column, amount)


## T-045 · Kayıt yüklendi: halkanın geçmişi bilinmiyor; `tick` yüklenen durumun tick'idir.
func reset_changes(tick: int) -> void:
	_changes.reset(tick)


## Yapılandırma (salt okunur sorgular için: ilerleme ‰ süre toplamını buradan hesaplar). Değiştirmeyin.
func config() -> EconomyConfig:
	return _cfg


## Yalnız sim kararıyla geliştirilmiş (T0 stoku olmayan: `last_code == approved`) ve BİTMİŞ birimler, bölge sırasıyla
## (`regions.codes`): [konut, ticaret] PackedInt64Array. SALT OKUNUR; O(parsel) — çağıran (facade) tamamlanma
## sayacına bağlı önbellek tutar, her tick çağırmaz. Ekonomi durumu yoksa boş diziler.
func sim_built_units(state: GameState) -> Array[PackedInt64Array]:
	var res := PackedInt64Array()
	var com := PackedInt64Array()
	res.resize(_region_codes.size())
	com.resize(_region_codes.size())
	var d := EconomyState.data(state)
	if not d.is_empty():
		var stage: PackedByteArray = d["stage"]
		var use_col: PackedByteArray = d["use"]
		var units_col: PackedInt32Array = d["units"]
		var last_code: PackedByteArray = d["last_code"]
		for i in stage.size():
			if stage[i] != EconomyState.STAGE_BUILT or last_code[i] != EconomyState.CODE_APPROVED:
				continue
			if use_col[i] == EconomyConfig.USE_RESIDENTIAL:
				res[_region_of[i]] += units_col[i]
			else:
				com[_region_of[i]] += units_col[i]
	return [res, com]


## T-043A · Parselin PLAN DURUMU (UI sorgusu; SALT OKUNUR). Bayrak kapalıysa `untracked`. `pending_vote_id`: parsel için
## sürmekte olan meclis oylaması (yoksa 0; çağıran siyasetten bulur). Düzen: `ParcelPlanning.describe`.
func plan_state(state: GameState, parcel_id: int, pending_vote_id: int = 0, municipal_free: bool = false) -> Dictionary:
	return ParcelPlanning.describe(ParcelZoningSystem.overlay_of(state, parcel_id),
		municipal_free or _is_vacant(state, parcel_id), _unplanned_on, pending_vote_id)


## T-043B ek · Görünüm katmanı için: parselin `ParcelView.zone` değeri şablondaki placeholder'dan (T0 başlangıç imarı)
## mi geliyor, yoksa gösterilmemeli mi? Bayrak açıkken boş parselde YÜRÜRLÜKTE oyuncu planı yoksa placeholder imar
## görünmez (`plan_state` ile aynı kural; ekonomi durumu henüz kurulmadıysa T0 stoğuna bakılır). Bayrak kapalıysa false.
func hides_template_zone(state: GameState, parcel_id: int) -> bool:
	if not _unplanned_on or not _is_vacant(state, parcel_id):
		return false
	var entry: Variant = ParcelZoningSystem.overlay_ref(state).get(parcel_id, null)
	return not (entry is Dictionary) or entry.get("zone", &"") == &""


## T-043A · İmar planı ÖNİZLEMESİ: oyuncu seçili parsellere `land_use` (+ isteğe bağlı yoğunluk/yükseklik) teklif ederse
## yatırımcı karar fonksiyonunun kullanacağı AYNI formülle (`EconomyMath.project_units`, `_best_use`)
## potansiyel birim ve
## altyapı yükü. Sonucu ZORLAMAZ: yatırımcı yine getiri/talep/kapasiteye göre karar verir. SALT OKUNUR,
## uydurma sayı yok.
## `density` < 0: imar varsayılanı; `max_height_m` < 0: sınır yok (komut parametreleriyle aynı anlam).
## Dönüş: {ok, reason, parcels: [{id, region, use, units, infra_units}], total_units, total_infra_units,
## regions: [{code, added_units, added_infra_units, capacity_units, load_units, headroom_units, fits}]}.
## `ok` false: reason `economy.not_started` | `plan.unknown_land_use` | `plan.unknown_parcel`.
func plan_preview(state: GameState, parcel_ids: PackedInt64Array, land_use: StringName, density: int = -1,
		max_height_m: int = -1) -> Dictionary:
	var out := {"ok": false, "reason": &"", "parcels": [], "total_units": 0, "total_infra_units": 0, "regions": []}
	var d := EconomyState.data(state)
	if d.is_empty():
		out["reason"] = &"economy.not_started"
		return out
	var profile := _cfg.zone_profile(land_use)
	if profile.is_empty():
		out["reason"] = &"plan.unknown_land_use"
		return out
	var density_pm := density if density >= 0 else int(profile["density_pm"])
	var allowed: Array = profile["uses"]
	var regions: Dictionary = d["regions"]
	var added_units := {}
	var added_infra := {}
	for id in parcel_ids:
		var i := EconomyState.index_of(d, id)
		if i < 0:
			out["reason"] = &"plan.unknown_parcel"
			(out["parcels"] as Array).clear()
			return out
		var r := _region_of[i]
		var use := _best_use(regions, r, allowed)
		var units := 0
		if not allowed.is_empty():
			units = EconomyMath.project_units(_area[i], _cfg.use_param(use, "units_per_1000m2"), density_pm,
				max_height_m, _cfg.p("storey_m"), _cfg.p("reference_floors"))
		var infra_units := units * (_cfg.use_param(use, "infra_per_unit") if units > 0 else 0)
		(out["parcels"] as Array).append({"id": id, "region": StringName(_region_codes[r]),
			"use": EconomyState.use_name(use) if units > 0 else &"", "units": units, "infra_units": infra_units})
		added_units[r] = int(added_units.get(r, 0)) + units
		added_infra[r] = int(added_infra.get(r, 0)) + infra_units
		out["total_units"] += units
		out["total_infra_units"] += infra_units
	var touched: Array = added_units.keys()
	touched.sort()
	for r: int in touched:
		var capacity := _projects.effective_cap(state, regions, r)
		var load := EconomyMath.infra_load(_cfg, regions, r)
		(out["regions"] as Array).append({"code": StringName(_region_codes[r]), "added_units": added_units[r],
			"added_infra_units": added_infra[r], "capacity_units": capacity, "load_units": load,
			"headroom_units": capacity - load, "fits": capacity - load - int(added_infra[r]) >= 0})
	out["ok"] = true
	return out


func on_daily(state: GameState) -> void:
	_changes.begin_tick(state.tick)
	var d := _ensure_state(state)
	var starts_today := PackedInt32Array()
	starts_today.resize(_region_codes.size())
	_projects.progress(state, d)  # önce ilerlet: bugün onaylanan proje yarın saymaya başlar
	_scan_zone_changes(state, d)
	_scan_road_triggers(state, d)
	_run_attention(state, d, starts_today)
	var priority_reviews := _run_priority_queue(state, d, starts_today)  # önce kuyruk: bütçeyi tarama değil kuyruk yer
	_run_reviews(state, d, starts_today, priority_reviews)


func on_monthly(state: GameState) -> void:
	_monthly.run(_ensure_state(state))  # kohort -> arsa değeri -> kira -> sermaye girdisi (`EconomyMonthly`)


## Parsel boş mu? Ekonomi durumu kuruluysa aşamaya, kurulmadıysa T0 stoğuna bakar.
func _is_vacant(state: GameState, parcel_id: int) -> bool:
	var d := EconomyState.data(state)
	if d.is_empty():
		return _stock.units_of(parcel_id) < 1
	var i := EconomyState.index_of(d, parcel_id)
	return i >= 0 and (d["stage"] as PackedByteArray)[i] == EconomyState.STAGE_VACANT


# --- Kurulum ---

func _cache_static(parcels: ParcelSource) -> void:
	_ids = parcels.parcel_ids()
	var n := _ids.size()
	var codes: Array = []
	var region_names: Array[StringName] = []
	_area.resize(n)
	_base_land.resize(n)
	_base_zone.resize(n)
	_center_x_cm.resize(n)
	_center_z_cm.resize(n)
	for i in n:
		var view := parcels.template(_ids[i])
		_center_x_cm[i] = roundi(view.center.x * 100.0)
		_center_z_cm[i] = roundi(view.center.y * 100.0)
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
## kurulur. Sütunlar kurulumda önceden türetilir (`EconomyStockColumns`, T-050); burada yalnız kopyalanır.
@warning_ignore("integer_division")
func _apply_stock(d: Dictionary) -> void:
	var regions: Dictionary = d["regions"]
	if _stock_cols.is_empty():
		_stock_cols = EconomyStockColumns.build(_ids, _region_of, _region_codes.size(), _stock)
	d["stage"] = (_stock_cols["stage"] as PackedByteArray).duplicate()
	d["use"] = (_stock_cols["use"] as PackedByteArray).duplicate()
	d["units"] = (_stock_cols["units"] as PackedInt32Array).duplicate()
	d["owner_id"] = (_stock_cols["owner"] as PackedInt32Array).duplicate()
	var res_built: PackedInt64Array = (_stock_cols["res_built"] as PackedInt64Array).duplicate()
	regions["res_built"] = res_built
	regions["com_built"] = (_stock_cols["com_built"] as PackedInt64Array).duplicate()
	var latent: PackedInt64Array = regions["latent_hh"]
	var occupancy := _cfg.p("initial_occupancy_pm")
	for r in _region_codes.size():
		latent[r] += res_built[r] * occupancy / 1000


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
	var fresh_plans: Array = []  # T-043B: [parsel indeksi, plan komutu] (öncelik modunda yönlendirilecek)
	for id: int in ids:
		var entry: Dictionary = overlay[id]
		var zone: StringName = entry.get("zone", &"")
		if zone == &"":
			continue
		var i := EconomyState.index_of(d, id)
		if i < 0:
			continue
		if _seen_zone(zone_seen, i) == zone:
			continue
		zone_seen[i] = String(zone)
		if stage[i] == EconomyState.STAGE_VACANT:
			if last_code[i] != EconomyState.CODE_NONE:  # görünür karar özeti sıfırlanıyor
				_changes.note(_ids[i])
			if _priority_on:
				fresh_plans.append([i, int(entry.get("command_id", 0))])
			else:
				attention[i] = state.tick + _cfg.p("attention_delay_days")
				attention_cmd[i] = int(entry.get("command_id", 0))
			last_code[i] = EconomyState.CODE_NONE
			last_reason_tick[i] = -1
			next_review[i] = 0
	if not fresh_plans.is_empty():
		_route_fresh_plans(state, d, fresh_plans)


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
func _run_reviews(state: GameState, d: Dictionary, starts_today: PackedInt32Array, used_reviews: int = 0) -> void:
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
	var reviews := used_reviews  # T-043B: öncelikli kuyruk aynı günlük değerlendirme bütçesinden yemiştir
	# Ön eleme talebi yalnız (bölge, imar) çiftine bağlıdır, parsele değil: aynı çift için tekrar hesaplanmaz.
	# `_evaluate` bölge durumunu (boru hattı/talep) değiştirdiğinden her değerlendirmeden sonra önbellek sıfırlanır;
	# sonuçlar önbelleksiz hesapla birebir aynıdır (sıra, RNG ve kayıt değişmez).
	var demand_cache: Dictionary = {}
	while scanned < scan_budget and reviews < max_reviews:
		var i := cursor
		cursor = (cursor + 1) % n
		scanned += 1
		if stage[i] != EconomyState.STAGE_VACANT or next_review[i] > state.tick:
			continue
		var r := _region_of[i]
		if starts_today[r] >= max_starts:
			continue
		var zone := _effective_zone(overlay, i)
		var by_zone: Dictionary = demand_cache.get(r, {})
		if by_zone.is_empty():
			demand_cache[r] = by_zone
		var best: int = by_zone.get(zone, PRESCREEN_NO_USE)
		if best == PRESCREEN_NO_USE and not by_zone.has(zone):
			var uses: Array = REFERENCE_USES if zone == UNPLANNED_ZONE else _cfg.zone_profile(zone).get("uses", [])
			if not uses.is_empty():
				best = 0
				for use: int in uses:
					best = maxi(best, EconomyMath.region_demand_pm(_cfg, regions, r, use, 0))
			by_zone[zone] = best
		if best == PRESCREEN_NO_USE or best < prescreen:
			continue
		reviews += 1
		_evaluate(state, d, i, 0, starts_today)
		demand_cache.clear()
	d["review_cursor"] = cursor


# --- Öncelikli değerlendirme (T-043B, D-010 karar 1; durum/geometri yardımcıları `PriorityReview`) ---
## Tetikleyici: bölgenin hem erişimi (oyuncu yolu) hem planı tamamlandığı SON olay. İki olay vardır: yol onayı (bu tick
## `public_works.works`e eklenen yol) ve plan yürürlüğü (`_scan_zone_changes`). Her tetikte olayın etkilediği,
## YÜRÜRLÜKTE
## planlı + oyuncu yoluna bağlı (yarıçap R içinde) + boş parseller en yakından başlayarak en çok K tane
## `attention_delay_days` sonra `d["priority"]` kuyruğuna girer (parsel indeksi -> vade günü; `priority_cmd`:
## tetikleyici
## komut). Kuyruk yalnız ilk girişte yaratılır (kayıt sürümü `VERSION_PRIORITY`); boşken durum yazılmaz. Ön eleme
## yoktur.
## Karar yine yatırımcı kararıdır (CAN-03): kuyruk yalnız BAKIŞI öne çeker.

## Bu tick onaylanan yollar için komşu planlı parselleri kuyruğa alır.
func _scan_road_triggers(state: GameState, d: Dictionary) -> void:
	if not _priority_on:
		return
	var roads := PriorityReview.new_roads(state)
	if roads.is_empty():
		return
	var overlay := ParcelZoningSystem.overlay_ref(state)
	var plan_ids: Array = overlay.keys()
	plan_ids.sort()
	var stage: PackedByteArray = d["stage"]
	var attention: Dictionary = d["attention"]
	var due := state.tick + _cfg.p("attention_delay_days")
	for road: Dictionary in roads:
		var candidates: Array = []
		for id: int in plan_ids:
			var i := EconomyState.index_of(d, id)
			if i < 0 or stage[i] != EconomyState.STAGE_VACANT or attention.has(i) or not _is_planned_buildable(overlay[id]):
				continue
			var dist2 := PriorityReview.dist2_to_polyline(_center_x_cm[i], _center_z_cm[i], road["pts"])
			if dist2 <= _priority_radius2_cm:
				candidates.append([dist2, i])
		PriorityReview.enqueue(d, candidates, _priority_max_parcels, due, int(road["command_id"]), false)


## Bu tick yürürlüğe giren planların boş parselleri: oyuncu yoluna bağlı olanlar (en çok K, plan komutu başına, yola en
## yakın önce) kuyruğa; kalanı (bağlı değil ya da K'yı aşan) eski dikkat yoluna (`attention`) gider: zorunlu
## değerlendirme
## HİÇBİR plan parselinde kaybolmaz.
func _route_fresh_plans(state: GameState, d: Dictionary, fresh_plans: Array) -> void:
	var attention: Dictionary = d["attention"]
	var attention_cmd: Dictionary = d["attention_cmd"]
	var due := state.tick + _cfg.p("attention_delay_days")
	var roads := PriorityReview.road_polylines(state)
	var overlay := ParcelZoningSystem.overlay_ref(state)
	var by_command: Dictionary = {}  # plan komutu -> [[dist2, i]...]
	var fallback: Array = []
	for pair: Array in fresh_plans:
		var i: int = pair[0]
		var dist2 := -1
		if _is_planned_buildable(overlay[_ids[i]]):
			dist2 = PriorityReview.dist2_to_roads(_center_x_cm[i], _center_z_cm[i], roads)
		if dist2 >= 0 and dist2 <= _priority_radius2_cm:
			if not by_command.has(pair[1]):
				by_command[pair[1]] = []
			(by_command[pair[1]] as Array).append([dist2, i])
		else:
			fallback.append(pair)
	var commands: Array = by_command.keys()
	commands.sort()
	for command_id: int in commands:
		fallback.append_array(PriorityReview.enqueue(d, by_command[command_id], _priority_max_parcels, due, command_id, true))
	for pair: Array in fallback:
		attention[pair[0]] = due
		attention_cmd[pair[0]] = pair[1]
		if d.has("priority"):  # parsel kuyruktaysa eski girişi düşer: tek zorunlu değerlendirme
			(d["priority"] as Dictionary).erase(pair[0])
			(d["priority_cmd"] as Dictionary).erase(pair[0])


## Vadesi gelen kuyruk girişleri, (vade, indeks) sırasıyla, günlük değerlendirme bütçesi (`max_reviews_per_tick`) kadar.
## Bölgenin günlük başlangıç sınırı dolmuşsa giriş ertesi güne kalır (bütçe harcamaz); parsel artık boş değilse sessizce
## düşer. Kullanılan değerlendirme sayısını döndürür (periyodik tarama kalan bütçeyi kullanır).
func _run_priority_queue(state: GameState, d: Dictionary, starts_today: PackedInt32Array) -> int:
	var due := PriorityReview.due_keys(d, state.tick)
	if due.is_empty():
		return 0
	var queue: Dictionary = d["priority"]
	var cmds: Dictionary = d["priority_cmd"]
	var stage: PackedByteArray = d["stage"]
	var max_reviews := _cfg.p("max_reviews_per_tick")
	var max_starts := _cfg.p("max_starts_per_region_per_day")
	var used := 0
	for key: int in due:
		if used >= max_reviews:
			break
		var i := PriorityReview.index_of_key(key)
		if stage[i] != EconomyState.STAGE_VACANT:
			queue.erase(i)
			cmds.erase(i)
			continue
		if starts_today[_region_of[i]] >= max_starts:
			continue
		var command_id: int = cmds.get(i, 0)
		queue.erase(i)
		cmds.erase(i)
		_evaluate(state, d, i, command_id, starts_today)
		used += 1
	return used


## Yürürlükteki plan yatırıma açık bir imar mı? (izinli kullanımı olan; `zone.green` gibi kapalı imar değil)
func _is_planned_buildable(entry: Dictionary) -> bool:
	var zone: StringName = entry.get("zone", &"")
	return zone != &"" and not (_cfg.zone_profile(zone).get("uses", []) as Array).is_empty()


func _effective_zone(overlay: Dictionary, i: int) -> StringName:
	var entry: Variant = overlay.get(_ids[i], null)
	if entry is Dictionary and entry.get("zone", &"") != &"":
		return entry["zone"]
	if _unplanned_on:  # D-010: boş arazinin imarı kaynak şablondaki placeholder'dan TÜREMEZ
		return UNPLANNED_ZONE
	return StringName(_base_zone[i])


## Parselin görülen imarı (`zone_seen`; kural `EconomyState.seen_zone`).
func _seen_zone(zone_seen: Dictionary, i: int) -> StringName:
	return EconomyState.seen_zone(zone_seen, i, _unplanned_on, _base_zone)


# --- Yatırımcı kararı (SIM-02) ---

func _evaluate(state: GameState, d: Dictionary, i: int, command_id: int, starts_today: PackedInt32Array) -> void:
	var regions: Dictionary = d["regions"]
	var r := _region_of[i]
	var overlay_entry: Variant = ParcelZoningSystem.overlay_ref(state).get(_ids[i], null)
	var zone := _effective_zone(ParcelZoningSystem.overlay_ref(state), i)
	var unplanned := zone == UNPLANNED_ZONE
	# Plansız parsel: başvuru projesi (konut/ticaretten talebi yüksek olan, taban yoğunluk, yükseklik sınırı yok);
	# böylece kapasite/talep etkenleri de dürüstçe gösterilir ve engel yalnız imar (plan) olur.
	var profile := {} if unplanned else _cfg.zone_profile(zone)
	var allowed: Array = REFERENCE_USES if unplanned else profile.get("uses", [])
	var use := _best_use(regions, r, allowed)
	var density: int = EconomyMath.SCALE if unplanned else profile.get("density_pm", 0)
	var max_height := -1
	var zoning_source := &""
	if overlay_entry is Dictionary and not unplanned:
		if int(overlay_entry.get("density", -1)) >= 0:
			density = int(overlay_entry["density"])
		max_height = int(overlay_entry.get("max_height_m", -1))
		if _unplanned_on and int(overlay_entry.get("command_id", 0)) > 0:  # gerekçede plan komutu (SIM-12)
			zoning_source = SimContract.ref(SimContract.REF_COMMAND, int(overlay_entry["command_id"]))
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
		"infra_cap": _projects.effective_cap(state, regions, r),
		"infra_source": PublicWorksState.infra_source(state, _region_codes[r]),
		"infra_load": EconomyMath.infra_load(_cfg, regions, r),
		"demand_after_pm": EconomyMath.region_demand_pm(_cfg, regions, r, use, units),
		"rent_mult_pm": EconomyMath.rent_mult_pm(current_demand, _cfg.p("rent_floor_pm"), _cfg.p("rent_cap_pm")),
		"sentiment": sentiment, "threshold_shift": (investors["threshold_shift"] as PackedInt32Array)[investor],
		"unplanned": unplanned, "zoning_source": zoning_source,
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
	_changes.note(_ids[i])
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
	_changes.note(_ids[i])
	totals["declines_recorded"] += 1
	SimEventLog.emit(state, &"actor.decided", &"event.investor.declined",
		PackedStringArray([String(SimContract.parcel_ref(_ids[i]))]),
		{"code": String(EconomyState.CODE_NAMES[code]), "use": String(EconomyState.use_name(use)), "units": units},
		PackedInt64Array([reason_id]), command_id, StringName("actor.investor.%d" % (investor + 1)))
