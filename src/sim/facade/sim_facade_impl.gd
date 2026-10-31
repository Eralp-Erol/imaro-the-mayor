# gdlint:disable=max-public-methods
class_name SimFacadeImpl
extends SimFacade
## Gerçek simülasyonu ADR-0005 sözleşmesiyle sunan `SimFacade` (T-027). View/UI yalnız `SimFacade` tipini bilir;
## bu sınıf sim çekirdeğini (GameState + Simulation + TickDriver) sarar. SAF: Node/zaman/OS/dosya G/Ç yok (dosya
## G/Ç `src/app/save_slot*`'ta; buraya bayt verilir/alınır).
##
## - Okumalar DEĞER kopyasıdır (her çağrıda yeni DTO); okumalar sim durumunu DEĞİŞTİRMEZ (hash aynı kalır).
## - Yazma yalnız komut: `submit_command` -> ortak şekil denetimi -> işleyici ön doğrulaması -> `Commands.submit`;
##   komut sonraki tick sınırında uygulanır, `command.applied/rejected` olayı üretilir. Sözleşme `command_id` =
##   Commands seq + 1 (kimlikler 1'den); reddedilen komut kimlik tüketmez.
## - CAN-03: katalog beyaz listedir (`zoning.propose`, `budget.propose`; v1.3: `public_work.road`,
##   `public_work.undo_last`); özel bina fiili yoktur ve eklenemez. Yol komutları `attach_public_works` ile takılır
##   (ağ + sim yol listesi + kayıt).
## - Kurulmamış sistemler (bütçe [T-043C: `attach_budget` ile kurulur], meclis, grup tepkileri)
##   `snapshot().extensions["x.sim.available.<bölüm>"] = false` ve varsayılan boş DTO ile görünür; UI bölümü gizler /
##   `*.not_built` yazar. Komutları gerekçeli reddedilir.
## - Hız sim durumu DEĞİLDİR (TickDriver'dadır, hash'e girmez).
## Entegrasyon: yeni sistem/işleyici `create(..., extra_systems, extra_handlers)` ile takılır (T-013/T-014/T-016);
## T-017: `proposal_gate` (öneri meclis oylamasına gider mi) ve `snapshot_provider` (grup/meclis bölümleri) isteğe
## bağlıdır.

## Kurulmamış bölümlerin `extensions` anahtarı öneki (v1.1'de tipli `available` alanına taşınması istenir).
const AVAILABLE_PREFIX := "x.sim.available."
const SECTION_PARCELS := &"parcels"
const SECTION_BUDGET := &"budget"
const SECTION_COUNCIL := &"council"
const SECTION_GROUPS := &"groups"
const SECTION_ECONOMY := &"economy"
const REASON_ECONOMY_NOT_STARTED := &"economy.not_started"
const WORLD_SYSTEM := &"world"

## Senaryo/kampanya kimliği (CAN-09); kayıt yuvası bunu ayrıca saklar. Sim durumunun/hash'in parçası değildir.
var campaign_id: StringName = &""

var _state: GameState
var _sim: Simulation
var _driver: TickDriver
var _parcels: ParcelSource
var _facade_config: FacadeConfig
var _proposal_gate: ProposalGate  # T-043A: plan sorguları için (meclis bayrağı, bekleyen oylama); yoksa meclis yok
var _max_speed_level: int = SPEED_FASTEST
var _driver_speeds: Dictionary = {}  # hız adı (String) -> tick/sn (core_config.json driver.speeds)
var _retained_cache: Dictionary = {}  # {"key": [last_seq, first_reason_id], "start": int}
var _snapshot_provider: SnapshotProvider  # T-017: grup/meclis bölümlerini dolduran sağlayıcı (yoksa kurulmamış)
var _economy: EconomySystem  # T-040: ekonomi kuruluysa salt okunur sorgular (ilerleme, sonuç özeti) buradan beslenir
## T-040: sim-geliştirmeli bitmiş birim önbelleği {"completions": int, "units": Array[PackedInt64Array]}. Türetilmiştir
## (durum/hash dışı); yalnız tamamlanma sayacı değişince yeniden hesaplanır, kayıt yüklenince silinir.
var _sim_units_cache: Dictionary = {}
## T-043C: gösterge bütçe sistemi (`attach_budget` ile takılır); yoksa bölüm kurulmamıştır, durum/hash değişmez.
var _budget: BudgetSystem
## T-042: oyuncu yolu bağlamı (ağ + kurallar + sim verisi); `attach_public_works` ile takılır, yoksa yol komutları
## kayıtsızdır.
var _public_works: PublicWorksContext
## T-045: değişen-parsel sorgusunun durum kuşağı. Kayıt yüklenince artar (halka boşalır); durum/hash dışıdır.
var _change_epoch: int = 0


## Yeni oyun. Geçersiz yapılandırma/kaynak/hız tablosunda push_error + null.
static func create(world_seed: int, parcels: ParcelSource, sim_config: SimConfig = null,
		facade_config: FacadeConfig = null, extra_systems: Array[SimSystem] = [],
		extra_handlers: Array[CommandHandler] = [], proposal_gate: ProposalGate = null,
		snapshot_provider: SnapshotProvider = null) -> SimFacadeImpl:
	var sc := sim_config if sim_config != null else SimConfig.load_default()
	var fc := facade_config if facade_config != null else FacadeConfig.load_default()
	var problem := _setup_problem(parcels, sc, fc)
	if not problem.is_empty():
		push_error("SimFacadeImpl: %s" % problem)
		return null
	var impl := SimFacadeImpl.new()
	impl._state = GameState.create(world_seed, sc)
	impl._parcels = parcels
	impl._facade_config = fc
	impl._sim = Simulation.new()
	impl._sim.add_system(ParcelZoningSystem.new())
	impl._snapshot_provider = snapshot_provider
	impl._proposal_gate = proposal_gate
	impl._sim.add_handler(ZoningProposeHandler.new(parcels, fc, proposal_gate))
	impl._sim.add_handler(UnbuiltCommandHandler.new(SimCommand.KIND_BUDGET_PROPOSE, SECTION_BUDGET))
	for system in extra_systems:
		impl._sim.add_system(system)
		if system is EconomySystem:
			impl._economy = system
	for handler in extra_handlers:
		impl._sim.add_handler(handler)
	impl._driver = TickDriver.new(impl._sim, impl._state, sc.driver)
	impl._driver_speeds = (sc.driver["speeds"] as Dictionary).duplicate()
	var world := impl._state.system_data(WORLD_SYSTEM)
	world["world_id"] = String(parcels.world_id())
	world["parcel_count"] = parcels.parcel_count()
	return impl


## T-042 · Oyuncu yolu komutlarını (`public_work.road`, `public_work.undo_last`) bu facade'a takar: ağ, oyun katmanının
## kurduğu AYNI `WorldNetwork`dur; sim onu yalnız tick sınırında değiştirir. Ağın delta'sı boş olmalı (yol listesi sim
## durumunda yaşar; kayıt yüklemesi ağı ona eşitler). Başarısızsa false (push_error ya da çift kurulum).
func attach_public_works(ctx: PublicWorksContext) -> bool:
	if ctx == null or _public_works != null:
		push_error("SimFacadeImpl: oyuncu yolu bağlamı yok ya da zaten takılı")
		return false
	if not ctx.tracks(_state):
		push_error("SimFacadeImpl: ağın yol işlemleri sim durumundaki yol listesiyle tutarsız (boş olmalı)")
		return false
	for handler in ctx.handlers():
		if not _sim.add_handler(handler):
			return false
	ctx.economy = _economy  # T-042b: kamulaştırma alınan parselin ekonomi sütunlarını okur/yazar (yoksa kapalı)
	if not _sim.add_system(ExpropriationFlushSystem.new(ctx)):  # komut aşamasında alınan parseller halkaya girsin
		return false
	_public_works = ctx
	return true


## T-043C · Gösterge bütçeyi (vergi geliri + yol gideri; kasa YALNIZ gösterge, hiçbir komutu reddetmez) bu facade'a
## takar. Ekonomi kurulu olmalı (kira ve birim maliyeti oradan okunur) ve tick ilerlememiş olmalı.
## `budget.propose` kurulmaz (UnbuiltCommandHandler kalır). Takılmazsa hiçbir şey değişmez (t0/altın hash'ler
## aynı). Başarısızsa false.
func attach_budget(cfg: BudgetConfig) -> bool:
	if _budget != null or _economy == null or _state.tick != 0:
		push_error("SimFacadeImpl: bütçe takılamadı (zaten takılı, ekonomi yok ya da tick ilerlemiş)")
		return false
	var system := BudgetSystem.create(cfg, _economy.config())
	if system == null or not _sim.add_system(system):
		return false
	_budget = system
	return true


## Takılı oyuncu yolu bağlamı (yoksa null). YALNIZ app katmanı/testler.
func public_works_context() -> PublicWorksContext:
	return _public_works


## v1.3 · Ağa eklenmiş oyuncu yolları, eskiden yeniye (sim durumundan; değer kopyası).
func public_works() -> Array[PublicWorkView]:
	var out: Array[PublicWorkView] = []
	var d := PublicWorksState.data(_state)
	if d.is_empty():
		return out
	for work: Dictionary in d["works"]:
		var v := PublicWorkView.new()
		v.provenance = provenance()
		v.work_id = work["id"]
		v.command_id = work["command_id"]
		v.tick = work["tick"]
		v.road_class = StringName(work["road_class"])
		v.length_cm = work["length_cm"]
		v.region_units = SimContract.to_args(work["region_units"])
		if work.has("expropriation"):  # v1.5: sim'in kaydı (uydurma yok)
			var record: Dictionary = work["expropriation"]
			v.expropriated = true
			v.taken_parcel_ids = ExpropriationSummary.sorted_ids(record)
			v.taken_built_parcels = record["built_parcels"]
			v.taken_res_units = record["res_units"]
			v.taken_com_units = record["com_units"]
			v.displaced_households = record["households"]
		out.append(v)
	return out


# --- Kimlik / saat / hız ---

func provenance() -> StringName:
	return SimContract.PROVENANCE_SIM


func current_tick() -> int:
	return _state.tick


func speed() -> int:
	return maxi(_facade_config.speed_levels.find(_driver.speed), 0)


func available_speeds() -> PackedInt32Array:
	var out := PackedInt32Array()
	for level in mini(_max_speed_level, _facade_config.speed_levels.size() - 1) + 1:
		if _driver_speeds.has(String(_facade_config.speed_levels[level])):
			out.append(level)
	return out


func set_speed(level: int) -> bool:
	if not available_speeds().has(level):
		return false
	return _driver.set_speed(_facade_config.speed_levels[level])


## Platform profili sınırı (`max_game_speed`, ADR-0004): daha yüksek seviyeler kapanır; mevcut hız sınırı aşıyorsa
## sınıra çekilir. Hız sim durumu olmadığından hash'i etkilemez.
func set_max_speed_level(level: int) -> void:
	_max_speed_level = clampi(level, SPEED_PAUSED, _facade_config.speed_levels.size() - 1)
	if speed() > _max_speed_level:
		set_speed(_max_speed_level)


## `ticks` tick ilerletir (testler ve tick sürücüsü; senkron).
func advance(ticks: int) -> int:
	var n := maxi(ticks, 0)
	_sim.advance(_state, n)
	return n


## Gerçek süre (tam sayı mikrosaniye) x hız -> tamsayı tick (TickDriver); uygulama düğümü her karede çağırır.
func drive_usec(usec: int) -> int:
	return _driver.advance_usec(usec)


# --- Komutlar ---

func validate_command(command: SimCommand) -> CommandResult:
	var problem := _precheck(command)
	if not problem.is_empty():
		return CommandResult.rejected(command, problem["reason_key"], problem["args"], _state.tick, provenance())
	return _accepted(command, CommandResult.STATUS_VALID, SimContract.NO_ID)


func submit_command(command: SimCommand) -> CommandResult:
	var problem := _precheck(command)
	if problem.is_empty():
		var seq := Commands.submit(_state, command.kind, SimContract.canonical(command.params) as Dictionary)
		if seq >= 0:
			return _accepted(command, CommandResult.STATUS_QUEUED, seq + 1)
		problem = {"reason_key": CommandResult.REJECT_INVALID_VALUE, "args": {}}
	return CommandResult.rejected(command, problem["reason_key"], problem["args"], _state.tick, provenance())


# --- Okumalar ---

func snapshot() -> SimSnapshot:
	var s := SimSnapshot.new()
	s.provenance = provenance()
	s.world_id = _parcels.world_id()
	s.scenario_id = campaign_id
	s.clock.tick = _state.tick
	s.clock.speed = speed()
	s.clock.available_speeds = available_speeds()
	s.last_event_seq = last_event_seq()
	s.parcel_count = _parcels.parcel_count()
	s.extensions = {
		AVAILABLE_PREFIX + String(SECTION_PARCELS): true,
		AVAILABLE_PREFIX + String(SECTION_BUDGET): _budget != null,
		AVAILABLE_PREFIX + String(SECTION_COUNCIL): false,
		AVAILABLE_PREFIX + String(SECTION_GROUPS): false,
		AVAILABLE_PREFIX + String(SECTION_ECONOMY): _economy != null,
	}
	if _snapshot_provider != null:
		_snapshot_provider.fill(_state, s)
	if _budget != null:
		s.budget = _budget.view(_state)  # T-043C: gerçek vergi/yol verisi; yoksa varsayılan boş DTO ("kurulmadı")
	return s


func parcel_ids(region_code: StringName = &"") -> PackedInt64Array:
	return _parcels.parcel_ids(region_code)


func parcel_views(ids: PackedInt64Array) -> Array[ParcelView]:
	var wanted := {}
	for id in ids:
		wanted[String(SimContract.parcel_ref(id))] = true
	var reason_index := _state.reasons.subject_index(wanted, _facade_config.parcel_reason_limit)
	var out: Array[ParcelView] = []
	for id in ids:
		var view := _parcels.template(id)
		if view == null:
			continue
		var overlay := ParcelZoningSystem.overlay_of(_state, id)
		if overlay.get("zone", &"") != &"":
			view.zone = overlay["zone"]
		view.pending_zone = overlay.get("pending_zone", &"")
		view.development = overlay.get("development", view.development)
		# T-013: ekonomi kuruluysa gelişme/arsa değeri/sahip (CAN-03: bunları yalnız aktör kararı yazar)
		EconomyState.decorate_view(_state, view, _economy.config() if _economy != null else null)
		if _economy != null and _economy.hides_template_zone(_state, id):  # D-010: plansız boş parselde imar &""
			view.zone = &""
		view.reason_ids = reason_index.get(String(SimContract.parcel_ref(id)), PackedInt64Array())
		view.provenance = provenance()
		out.append(view)
	return out


## T-040 · Ölçülebilir ekonomik sonuç özeti. SALT OKUNUR; O(bölge) (sim-geliştirmeli birimler tamamlanma sayacına
## bağlı önbellekten gelir). Ekonomi kurulu değilse `economy.not_built`; kurulu ama ilk tick geçmediyse (durum ilk
## günlük tick'te kurulur) `economy.not_started`. Belediye geliri/vergisi sim'de YOK: `municipal_revenue_available`
## false + neden (T-014).
func economy_outcome() -> EconomyOutcomeView:
	if _economy == null:
		return EconomyOutcomeView.unavailable(provenance(), _state.tick, EconomyOutcomeView.REASON_NOT_BUILT)
	if not EconomyState.is_ready(_state):
		return EconomyOutcomeView.unavailable(provenance(), _state.tick, REASON_ECONOMY_NOT_STARTED)
	var o := EconomyOutcomeView.new()
	o.provenance = provenance()
	o.tick = _state.tick
	o.available = true
	o.unavailable_reason_key = &""
	var totals := EconomyQuery.totals(_state)
	o.investments_approved = int(totals.get("approvals", 0))
	o.investments_declined = int(totals.get("declines", 0))
	o.projects_completed = int(totals.get("completions", 0))
	o.projects_stalled = int(totals.get("stalls", 0))
	o.rent_income = int(totals.get("rent_income", 0))
	o.land_sales = int(totals.get("land_sales", 0))
	o.construction_spend = int(totals.get("construction_spend", 0))
	var sim_units := _sim_built_units(int(totals.get("completions", 0)))
	var rows := EconomyQuery.region_stats(_state, _economy.config())
	for r in rows.size():
		var row: Dictionary = rows[r]
		var region := EconomyRegionOutcome.new()
		region.region_code = row["code"]
		region.households = int(row["latent_hh"])
		region.housed_households = int(row["housed_hh"])
		region.residential_units = int(row["res_built"])
		region.commercial_units = int(row["com_built"])
		region.residential_pipeline = int(row["res_pipe"])
		region.commercial_pipeline = int(row["com_pipe"])
		region.sim_residential_units = int(sim_units[0][r])
		region.sim_commercial_units = int(sim_units[1][r])
		region.demand_residential_pm = int(row["demand_res_pm"])
		region.demand_commercial_pm = int(row["demand_com_pm"])
		region.infrastructure_load_pm = int(row["infra_load_pm"])
		region.infra_capacity_units = int(row["infra_cap"])
		region.infra_from_public_works_units = int(row["infra_bonus"])
		o.regions.append(region)
	return o


## T-043A (sözleşme 1.4) · Parselin imar PLANI durumu. SALT OKUNUR; durum `parcels.overlay` kaydından türer
## (`EconomySystem.plan_state`). Bekleyen meclis oylamasını burada çözer (UI siyaset bilmez). Ekonomi kurulu değilse
## ya da bayrak (`decision.unplanned_land_enabled`) kapalıysa `untracked`.
func plan_state(parcel_id: int) -> PlanStateView:
	var view := PlanStateView.new()
	view.provenance = provenance()
	view.parcel_id = parcel_id
	if _economy == null or _parcels.template(parcel_id) == null:
		return view  # kurulu ekonomi yok ya da bilinmeyen parsel: plan kavramı yok (`untracked`)
	var vote_id := _proposal_gate.pending_vote_for_parcel(_state, parcel_id) if _proposal_gate != null else 0
	var raw := _economy.plan_state(_state, parcel_id, vote_id)
	view.state = raw["state"]
	view.zone = raw["zone"]
	view.pending_zone = raw["pending_zone"]
	view.due_tick = raw["due_tick"]
	view.command_id = raw["command_id"]
	view.source_ref = raw["source_ref"]
	view.density = raw["density"]
	view.max_height_m = raw["max_height_m"]
	view.rejected_command_id = raw["rejected_command_id"]
	view.rejected_tick = raw["rejected_tick"]
	view.vote_ref = raw["vote_ref"]
	return view


## T-043A (sözleşme 1.4) · İmar planı önizlemesi: sayılar `EconomySystem.plan_preview` çıktısıdır (yatırımcının
## kullandığı formül; ayrı hesap yok). `max_parcels` = teklif üst sınırı (sim yapılandırması), `council_required` =
## GERÇEK `requires_council.zoning.propose` bayrağı (kapı yoksa false). SALT OKUNUR.
func plan_preview(parcel_ids: PackedInt64Array, land_use: StringName, density: int = -1,
		max_height_m: int = -1) -> PlanPreviewView:
	var council := _proposal_gate != null and _proposal_gate.requires_vote(_state, SimCommand.KIND_ZONING_PROPOSE)
	var limit := _facade_config.plan_max_parcels_per_proposal
	if _economy == null:
		var none := PlanPreviewView.new()
		none.provenance = provenance()
		none.land_use = land_use
		none.max_parcels = limit
		none.council_required = council
		return none
	return PlanPreviewView.from_economy(_economy.plan_preview(_state, parcel_ids, land_use, density, max_height_m),
		provenance(), land_use, limit, council)


## T-045 · `tick`ten sonra (tick, şimdi] değişen parseller; O(değişen), olay/gerekçe ufkundan BAĞIMSIZ (halka:
## `EconomySystem.change_log`, durum DIŞI). Pencereden eski/gelecek `tick` ya da yüklenmiş kayıt: `complete == false`
## (tüketici tam yeniden eşitler); kayıt yüklenince `epoch` artar. Ekonomi kurulu değilse izlenen alanlar hiç değişmez:
## aralık geçerliyse tam ve boştur. SALT OKUNUR.
func parcel_changes_since(tick: int) -> ParcelChangeFeed:
	var feed := ParcelChangeFeed.incomplete(provenance(), _state.tick, _change_epoch)
	if _economy == null:
		feed.complete = tick >= -1 and tick <= _state.tick
		return feed
	var changes := _economy.change_log()
	if not changes.covers(tick, _state.tick):
		return feed
	feed.complete = true
	feed.ids = changes.ids_since(tick)
	return feed


func _sim_built_units(completions: int) -> Array[PackedInt64Array]:
	if _sim_units_cache.get("completions", -1) != completions:
		_sim_units_cache = {"completions": completions, "units": _economy.sim_built_units(_state)}
	return _sim_units_cache["units"]


func events_since(after_seq: int, max_count: int = 0) -> Array[SimEvent]:
	var out: Array[SimEvent] = []
	var start := first_retained_event_seq()
	# Kopyasız okuma: `EventAdapter` DTO'ya kendi kopyasını alır (her kaydı bir kez daha derin kopyalamak gereksiz).
	for rec: Dictionary in SimEventLog.records_after(_state, maxi(after_seq, start - 1), max_count):
		out.append(EventAdapter.to_event(rec))
	return out


func last_event_seq() -> int:
	return SimEventLog.last_seq(_state)


## Olay saklama ufku gerekçe ufkundan uzun olamaz (ADR-0005 §5): budanmış gerekçeye işaret eden olay ve öncesi
## saklanmış sayılmaz; böylece her görünen olayın `reason_ids`'i çözülebilir kalır.
func first_retained_event_seq() -> int:
	var first_reason := _state.reasons.first_id()
	var last := SimEventLog.last_seq(_state)
	var key := [last, first_reason]
	if _retained_cache.get("key", null) != key:
		var start := SimEventLog.first_seq(_state)
		if first_reason > 1:  # gerekçe id'leri 1'den başlar: budama yoksa taranacak bir şey yok
			start = maxi(start, SimEventLog.seq_after_pruned_reasons(_state, first_reason))
		_retained_cache = {"key": key, "start": start}
	return _retained_cache["start"]


func reasons_for(subject_ref: StringName) -> Array[ReasonRecord]:
	var out: Array[ReasonRecord] = []
	var first := _state.reasons.first_id()
	for rec: Dictionary in _state.reasons.find({"subject": String(subject_ref)}):
		out.append(ReasonAdapter.to_record(rec, first))
	return out


func reason(reason_id: int) -> ReasonRecord:
	var rec := _state.reasons.by_id(reason_id)
	return null if rec.is_empty() else ReasonAdapter.to_record(rec, _state.reasons.first_id())


# --- Kayıt / yükleme (bayt; dosya G/Ç src/app/save_slot*) ---

## Tüm sim durumunun kayıt baytları (SimSave). Hız ve kampanya kimliği durumun parçası değildir.
func export_save() -> PackedByteArray:
	return SimSave.encode(_state)


## Kayıttan durumu yükler. Başarısızsa mevcut durum KORUNUR. Kayıt başka bir dünyaya aitse (`world_id`/parsel sayısı
## bu facade'ın parsel kaynağıyla uyuşmuyorsa) `world_mismatch` ile reddedilir (WLD-01: tek dünya).
func import_save(bytes: PackedByteArray) -> SimSave.LoadResult:
	var result := SimSave.decode(bytes)
	if not result.ok:
		return result
	var world: Variant = result.state.systems.get(String(WORLD_SYSTEM), null)
	if not (world is Dictionary) or world.get("world_id", null) != String(_parcels.world_id()) \
			or world.get("parcel_count", null) != _parcels.parcel_count():
		var mismatch := SimSave.LoadResult.new()
		mismatch.error_code = &"world_mismatch"
		mismatch.message = "Kayıt bu dünyaya ait değil (dünya kimliği veya parsel sayısı uyuşmuyor)."
		return mismatch
	var economy_problem := EconomyState.validate_data(result.state.systems.get(EconomyState.KEY, null),
		_parcels.parcel_count())  # T-013: ekonomi bölümü varsa biçimi/boyu denetlenir (yoksa "" döner)
	if economy_problem.is_empty():  # T-042b: ekonomide TAKEN olan parseller = yol kayıtlarındaki alınanlar
		economy_problem = ExpropriationFlow.consistency_problem(result.state)
	if not economy_problem.is_empty():
		var corrupt := SimSave.LoadResult.new()
		corrupt.error_code = &"corrupt"
		corrupt.message = "Kayıt bozuk: %s." % economy_problem
		return corrupt
	var budget_problem := BudgetState.validate_data(result.state.systems.get(BudgetState.KEY, null))
	if not budget_problem.is_empty():  # T-043C: bütçe bölümü varsa biçimi/tutarlılığı denetlenir (yoksa "" döner)
		var broken := SimSave.LoadResult.new()
		broken.error_code = &"corrupt"
		broken.message = "Kayıt bozuk: %s." % budget_problem
		return broken
	var network_problem := _sync_network(result.state)
	if not network_problem.is_empty():
		var mismatch := SimSave.LoadResult.new()
		mismatch.error_code = &"network_mismatch"
		mismatch.message = "Kayıt yol ağıyla eşitlenemedi: %s." % network_problem
		return mismatch
	_state = result.state
	_driver.bind_state(_state)
	_retained_cache = {}
	_sim_units_cache = {}
	_change_epoch += 1  # T-045: halkanın geçmişi artık geçersiz; tüketici tam yeniden eşitler
	if _economy != null:
		_economy.reset_changes(_state.tick)
	return result


## Sim durumunun kanonik SHA-256 hash'i (sim gerçeğinin hash'i; snapshot hash'i değil). Testler/T-009 için.
func state_hash() -> String:
	return _state.state_hash()


## YALNIZ app katmanı/testler: sim çekirdeğine erişim (T-013/T-016 entegrasyonu, test enjeksiyonu). UI `SimFacade`
## tipiyle çalışır ve bunları görmez.
func game_state() -> GameState:
	return _state


func simulation() -> Simulation:
	return _sim


# --- İç ---

## T-042: ağı kayıttaki yol listesine eşitler (`PublicWorksContext.sync_to`). Ağ takılı değilse kayıt yolsuz olmalı.
## Hata metni ya da "". Hata halinde ağ eski durumundadır (eşitleme kendi geri alır).
func _sync_network(target: GameState) -> String:
	if _public_works == null:
		return "" if not PublicWorksState.is_present(target) or PublicWorksState.work_count(target) == 0 \
			else "kayıtta yol var ama bu oturumda yol ağı bağlı değil"
	return _public_works.sync_to(target)


func _accepted(command: SimCommand, status: StringName, id: int) -> CommandResult:
	var result := CommandResult.accepted(command, status, id, _state.tick, provenance())
	var handler := _sim.handler_for(command.kind)
	if handler != null:
		result.args = SimContract.to_args(handler.preview_args(_state, command.params))
		if _budget != null:
			_budget.decorate_preview(_state, command.kind, result.args)  # T-043C: maliyet/iade sim'in kendi hesabı
	return result


## Geçerliyse {}, değilse {"reason_key", "args"}.
func _precheck(command: SimCommand) -> Dictionary:
	if command == null:
		return {"reason_key": CommandResult.REJECT_UNKNOWN_KIND, "args": {}}
	var shape := command.validate_shape()
	if not shape.is_empty():
		return shape
	var handler := _sim.handler_for(command.kind)
	if handler == null:
		return {"reason_key": CommandResult.REJECT_UNKNOWN_KIND, "args": {"kind": String(command.kind)}}
	var code := handler.validate_submit(_state, command.params)
	if code == &"":
		return {}
	var args := handler.reject_args(_state, command.params)
	if not CommandReject.is_contract_code(code):
		args["code"] = code
	return {"reason_key": CommandReject.key_for(code), "args": args}


static func _setup_problem(parcels: ParcelSource, sim_config: SimConfig, facade_config: FacadeConfig) -> String:
	if parcels == null:
		return "parsel kaynağı yok"
	if parcels is ListParcelSource and not (parcels as ListParcelSource).is_valid():
		return "parsel kaynağı geçersiz: %s" % ", ".join((parcels as ListParcelSource).errors)
	if not sim_config.is_valid():
		return "sim yapılandırması geçersiz: %s" % sim_config.error
	if not facade_config.is_valid():
		return "facade yapılandırması geçersiz: %s" % facade_config.error
	if not facade_config.speed_levels.has(StringName(sim_config.driver["default_speed"])):
		return "driver.default_speed hız seviyeleri içinde yok"
	return ""
