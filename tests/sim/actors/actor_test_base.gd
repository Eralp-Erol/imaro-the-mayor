class_name ActorTestBase
extends SimTestBase
## tests/sim/actors ortak taban sınıfı (T-016). Kendi başına test paketi değildir (dosya adı `_test` ile bitmez).
## Veri dosyalarını ActorConfig'den BAĞIMSIZ okur (FileAccess + JSON), böylece bozuk-veri testleri doğrulayıcının
## kendisine güvenmeden kopya üzerinde düzenleme yapabilir.

const DATA_DIR := "res://data/actors/"
const FILE_NAMES: Array[String] = [
	"traits", "axes", "topics", "kinds", "roster_m2", "relations_init", "memory_params", "decision_tables", "cadence",
]
const COUNCIL_1 := "actor.council.1"
const COUNCIL_2 := "actor.council.2"
const COUNCIL_3 := "actor.council.3"
const COUNCIL_4 := "actor.council.4"
const COUNCIL_5 := "actor.council.5"
const BLOC_1 := "actor.bloc.1"
const BLOC_2 := "actor.bloc.2"
const MEDIA_1 := "actor.media.1"
const PLAYER := "actor.protagonist"


## Veri dosyalarının ham (float'lı) ayrıştırılmış içeriği: {dosya adı: Dictionary}.
static func raw_files() -> Dictionary:
	var out := {}
	for file_name in FILE_NAMES:
		var text := FileAccess.get_file_as_string(DATA_DIR + file_name + ".json")
		var parsed: Variant = JSON.parse_string(text)
		out[file_name] = parsed
	return out


static func raw_text_of_all_files() -> String:
	var all := ""
	for file_name in FILE_NAMES:
		all += FileAccess.get_file_as_string(DATA_DIR + file_name + ".json")
	return all


func config() -> ActorConfig:
	var cfg := ActorConfig.load_default()
	assert_bool(cfg.is_valid()).override_failure_message("varsayılan aktör verisi geçersiz: %s" % cfg.error).is_true()
	return cfg


## Ham dosyaların kopyasına `edit` uygular ve ActorConfig kurar (doğrulama sonucu cfg.error/errors'ta).
func mutated(edit: Callable) -> ActorConfig:
	var files := raw_files()
	edit.call(files)
	return ActorConfig.from_files(files)


## Roster'daki aktör sözlüğü (ham kopyada, anahtara göre).
static func roster_actor(files: Dictionary, key: String) -> Dictionary:
	for a: Dictionary in files["roster_m2"]["actors"]:
		if a["key"] == key:
			return a
	return {}


## Yapılandırma + aktör sistemi başlatılmış oyun durumu.
func new_actor_state(world_seed: int = SEED, cfg: ActorConfig = null) -> GameState:
	var state := new_state(world_seed)
	var use := cfg if cfg != null else config()
	assert_bool(ActorStore.ensure_initialized(state, use)).override_failure_message("başlatılamadı").is_true()
	return state


## Bellek sınırını (K_mem) ve isteğe bağlı başka hafıza parametrelerini ezen geçerli yapılandırma.
func config_with_memory(overrides: Dictionary) -> ActorConfig:
	var cfg := mutated(func(f: Dictionary) -> void:
		for key: String in overrides:
			f["memory_params"][key] = overrides[key])
	assert_bool(cfg.is_valid()).override_failure_message(cfg.error).is_true()
	return cfg


## Olayı uygular ve başarısızsa testi düşürür.
func apply(state: GameState, cfg: ActorConfig, actor_key: String, event: Dictionary) -> Dictionary:
	var result := ActorMemory.apply_event(state, cfg, actor_key, event)
	assert_bool(result["ok"]).override_failure_message(str(result.get("error", ""))).is_true()
	return result


static func event_of(topic: String, valence: int, magnitude: int = 800, target: String = PLAYER,
		extra: Dictionary = {}) -> Dictionary:
	var event := {"topic_id": topic, "valence": valence, "magnitude": magnitude, "attributed_to": target,
		"source_ref": "command.1"}
	event.merge(extra, true)
	return event

