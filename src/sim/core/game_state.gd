class_name GameState
extends RefCounted
## Simülasyonun tüm kalıcı durumu (T-002, ADR-0002): state(t+1) = tick(state(t), commands(t)).
## Saf veri: Node/zaman/OS/global rastgelelik yok. Her alan `to_dict()` ile serileştirilir ve `state_hash()`'e girer
## (yeni alan eklenirse ikisine de eklenmeli ve `validate_dict` güncellenmeli).
##
## Alanlar: world_seed, tick (tamamlanan gün sayısı; 1 tick = 1 oyun günü), config (takvim/kapasite; SimConfig.sim),
## rng (sistem başına akışlar), reasons (gerekçe kaydı), systems (sistem kimliği -> o sistemin verisi),
## pending_commands + command_log + next_command_seq (komut kuyruğu/günlüğü; bkz. Commands).

const CONFIG_KEYS: Array[String] = [
	"days_per_month", "months_per_quarter", "reason_log_capacity", "command_log_capacity",
]

var world_seed: int = 0
var tick: int = 0
var config: Dictionary = {}
var rng: RngStreams
var reasons: ReasonLog
var systems: Dictionary = {}  # String -> Dictionary
var pending_commands: Array = []
var command_log: Array = []
var next_command_seq: int = 0


## Yeni oyun durumu; geçersiz yapılandırmada push_error + null.
static func create(world_seed_value: int, sim_config: SimConfig) -> GameState:
	if sim_config == null or not sim_config.is_valid():
		push_error("GameState: invalid SimConfig (%s)" % ("null" if sim_config == null else sim_config.error))
		return null
	var state := GameState.new()
	state.world_seed = world_seed_value
	state.config = sim_config.sim.duplicate(true)
	state.rng = RngStreams.new(world_seed_value)
	state.reasons = ReasonLog.new(int(state.config["reason_log_capacity"]))
	return state


## Sistemin kalıcı veri sözlüğü (yoksa oluşturur). Döndürülen sözlük DOĞRUDAN durumun parçasıdır.
func system_data(id: StringName) -> Dictionary:
	var key := String(id)
	if not systems.has(key):
		systems[key] = {}
	return systems[key]


## Aktör kararının gerekçesini şimdiki tick ile kaydeder (SIM-12); id veya hata için -1 (bkz. ReasonLog.record).
func record_reason(actor: Variant, decision: Variant, factors: Array, threshold: Variant,
		code: StringName = &"") -> int:
	return reasons.record(tick, actor, decision, factors, threshold, code)


# --- Takvim (tick = gün; oranlar config'ten) ---

func days_per_month() -> int:
	return int(config["days_per_month"])


func days_per_quarter() -> int:
	return days_per_month() * int(config["months_per_quarter"])


@warning_ignore("integer_division")
func month_index() -> int:
	return tick / days_per_month()


@warning_ignore("integer_division")
func quarter_index() -> int:
	return tick / days_per_quarter()


## Ayın günü, 1 tabanlı.
func day_of_month() -> int:
	return tick % days_per_month() + 1


## Bu tick bir ay sınırını tamamladı mı (tick > 0 ve ayın sonunda)?
func is_month_boundary() -> bool:
	return tick > 0 and tick % days_per_month() == 0


func is_quarter_boundary() -> bool:
	return tick > 0 and tick % days_per_quarter() == 0


# --- Serileştirme / hash ---

## Tüm durumun bağımsız (derin kopya) sözlük görünümü; kayıt biçiminin gövdesi.
func to_dict() -> Dictionary:
	return {
		"world_seed": world_seed,
		"tick": tick,
		"config": config.duplicate(true),
		"rng": rng.to_dict(),
		"reasons": reasons.to_dict(),
		"systems": systems.duplicate(true),
		"pending_commands": pending_commands.duplicate(true),
		"command_log": command_log.duplicate(true),
		"next_command_seq": next_command_seq,
	}


## Kanonik SHA-256 durum hash'i (T-900 StateHash). Desteklenmeyen içerikte StateHash hata basar ve "" döner;
## çağıranlar (testler, SimSave) boş hash'i başarısızlık sayar.
func state_hash() -> String:
	return StateHash.of({
		"world_seed": world_seed,
		"tick": tick,
		"config": config,
		"rng": rng.to_dict(),
		"reasons": reasons.to_dict_view(),
		"systems": systems,
		"pending_commands": pending_commands,
		"command_log": command_log,
		"next_command_seq": next_command_seq,
	})


## `to_dict()` çıktısından kurar. Önce `validate_dict` ile biçim doğrulanmalıdır; geçersizse null.
static func from_dict(data: Dictionary) -> GameState:
	if not validate_dict(data).is_empty():
		return null
	var state := GameState.new()
	state.world_seed = int(data["world_seed"])
	state.tick = int(data["tick"])
	state.config = (data["config"] as Dictionary).duplicate(true)
	state.rng = RngStreams.from_dict(data["rng"])
	state.reasons = ReasonLog.from_dict(data["reasons"])
	state.systems = (data["systems"] as Dictionary).duplicate(true)
	state.pending_commands = (data["pending_commands"] as Array).duplicate(true)
	state.command_log = (data["command_log"] as Array).duplicate(true)
	state.next_command_seq = int(data["next_command_seq"])
	return state


## Biçim hatası metni (anlaşılır, Türkçe); geçerliyse "".
static func validate_dict(data: Variant) -> String:
	if not (data is Dictionary):
		return "durum bölümü sözlük değil"
	for key in ["world_seed", "tick", "next_command_seq"]:
		if typeof(data.get(key, null)) != TYPE_INT:
			return "durum.%s eksik veya tamsayı değil" % key
	if int(data["tick"]) < 0:
		return "durum.tick negatif"
	var cfg: Variant = data.get("config", null)
	if not (cfg is Dictionary):
		return "durum.config eksik"
	for key in CONFIG_KEYS:
		if typeof(cfg.get(key, null)) != TYPE_INT or int(cfg[key]) < 1:
			return "durum.config.%s eksik veya geçersiz" % key
	var rng_error := RngStreams.validate_dict(data.get("rng", null))
	if not rng_error.is_empty():
		return rng_error
	var reasons_error := ReasonLog.validate_dict(data.get("reasons", null))
	if not reasons_error.is_empty():
		return reasons_error
	if not (data.get("systems", null) is Dictionary):
		return "durum.systems sözlük değil"
	for key in ["pending_commands", "command_log"]:
		var entries: Variant = data.get(key, null)
		if not (entries is Array):
			return "durum.%s dizi değil" % key
		for entry: Variant in entries:
			if not (entry is Dictionary):
				return "durum.%s öğesi sözlük değil" % key
	return ""
