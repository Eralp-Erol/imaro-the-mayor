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
## - CAN-03: katalog beyaz listedir (`zoning.propose`, `budget.propose`); özel bina fiili yoktur ve eklenemez.
## - Kurulmamış sistemler (bütçe, meclis, grup tepkileri) `snapshot().extensions["x.sim.available.<bölüm>"] = false`
##   ve varsayılan boş DTO ile görünür; UI bölümü gizler / `*.not_built` yazar. Komutları gerekçeli reddedilir.
## - Hız sim durumu DEĞİLDİR (TickDriver'dadır, hash'e girmez).
## Entegrasyon: yeni sistem/işleyici `create(..., extra_systems, extra_handlers)` ile takılır (T-013/T-014/T-016).

## Kurulmamış bölümlerin `extensions` anahtarı öneki (v1.1'de tipli `available` alanına taşınması istenir).
const AVAILABLE_PREFIX := "x.sim.available."
const SECTION_PARCELS := &"parcels"
const SECTION_BUDGET := &"budget"
const SECTION_COUNCIL := &"council"
const SECTION_GROUPS := &"groups"
const WORLD_SYSTEM := &"world"

## Senaryo/kampanya kimliği (CAN-09); kayıt yuvası bunu ayrıca saklar. Sim durumunun/hash'in parçası değildir.
var campaign_id: StringName = &""

var _state: GameState
var _sim: Simulation
var _driver: TickDriver
var _parcels: ParcelSource
var _facade_config: FacadeConfig
var _max_speed_level: int = SPEED_FASTEST
var _driver_speeds: Dictionary = {}  # hız adı (String) -> tick/sn (core_config.json driver.speeds)
var _retained_cache: Dictionary = {}  # {"key": [last_seq, first_reason_id], "start": int}


## Yeni oyun. Geçersiz yapılandırma/kaynak/hız tablosunda push_error + null.
static func create(world_seed: int, parcels: ParcelSource, sim_config: SimConfig = null,
		facade_config: FacadeConfig = null, extra_systems: Array[SimSystem] = [],
		extra_handlers: Array[CommandHandler] = []) -> SimFacadeImpl:
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
	impl._sim.add_handler(ZoningProposeHandler.new(parcels, fc))
	impl._sim.add_handler(UnbuiltCommandHandler.new(SimCommand.KIND_BUDGET_PROPOSE, SECTION_BUDGET))
	for system in extra_systems:
		impl._sim.add_system(system)
	for handler in extra_handlers:
		impl._sim.add_handler(handler)
	impl._driver = TickDriver.new(impl._sim, impl._state, sc.driver)
	impl._driver_speeds = (sc.driver["speeds"] as Dictionary).duplicate()
	var world := impl._state.system_data(WORLD_SYSTEM)
	world["world_id"] = String(parcels.world_id())
	world["parcel_count"] = parcels.parcel_count()
	return impl


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
	return CommandResult.accepted(command, CommandResult.STATUS_VALID, SimContract.NO_ID, _state.tick, provenance())


func submit_command(command: SimCommand) -> CommandResult:
	var problem := _precheck(command)
	if problem.is_empty():
		var seq := Commands.submit(_state, command.kind, SimContract.canonical(command.params) as Dictionary)
		if seq >= 0:
			return CommandResult.accepted(command, CommandResult.STATUS_QUEUED, seq + 1, _state.tick, provenance())
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
		AVAILABLE_PREFIX + String(SECTION_BUDGET): false,
		AVAILABLE_PREFIX + String(SECTION_COUNCIL): false,
		AVAILABLE_PREFIX + String(SECTION_GROUPS): false,
	}
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
		EconomyState.decorate_view(_state, view)
		view.reason_ids = reason_index.get(String(SimContract.parcel_ref(id)), PackedInt64Array())
		view.provenance = provenance()
		out.append(view)
	return out


func events_since(after_seq: int, max_count: int = 0) -> Array[SimEvent]:
	var out: Array[SimEvent] = []
	var start := first_retained_event_seq()
	for rec: Dictionary in SimEventLog.since(_state, maxi(after_seq, start - 1), max_count):
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
			for rec: Dictionary in SimEventLog.since(_state, 0):
				for rid in rec["reason_ids"] as PackedInt64Array:
					if rid < first_reason:
						start = maxi(start, int(rec["seq"]) + 1)
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
	if not economy_problem.is_empty():
		var corrupt := SimSave.LoadResult.new()
		corrupt.error_code = &"corrupt"
		corrupt.message = "Kayıt bozuk: %s." % economy_problem
		return corrupt
	_state = result.state
	_driver.bind_state(_state)
	_retained_cache = {}
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
	var code := handler.validate(_state, command.params)
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
