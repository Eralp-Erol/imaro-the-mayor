class_name SimTestBase
extends GdUnitTestSuite
## tests/sim ortak taban sınıfı (T-002). Kendi başına test paketi değildir (dosya adı `_test` ile bitmez).
## Yardımcılar: yapılandırma/durum kurucuları, "boş olmayan hash" doğrulayıcısı (T-900 devri: StateHash.of()
## desteklenmeyen türde "" döner; boş string iki durumu yanlışlıkla eşit gösterebilir) ve test sistemleri/işleyicileri.

const SEED := 20261020
const HEX_LEN := 64


## Sistem: her kancayı ortak sıra günlüğüne yazar ("<id>:<d|m|q>@<tick>"). Kanca sırasını ve takvimi doğrulamak için.
class OrderSystem:
	extends SimSystem
	var _id: StringName

	func _init(id: StringName) -> void:
		_id = id

	func system_id() -> StringName:
		return _id

	func on_daily(state: GameState) -> void:
		_note(state, "d")

	func on_monthly(state: GameState) -> void:
		_note(state, "m")

	func on_quarterly(state: GameState) -> void:
		_note(state, "q")

	func _note(state: GameState, tag: String) -> void:
		var data := state.system_data(&"order")
		var calls: Array = data.get("calls", [])
		calls.append("%s:%s@%d" % [_id, tag, state.tick])
		data["calls"] = calls


## Sistem: kendi akışından günlük çekim yapar; toplam (int) ve ortalama benzeri (float) biriktirir.
class DrawSystem:
	extends SimSystem
	## Boş değilse her gün bu İKİNCİ akıştan da çeker (akış yalıtımı testi için).
	var extra_stream: StringName = &""
	var extra_draws: int = 1
	var _id: StringName
	var _stream: StringName

	func _init(id: StringName, stream: StringName) -> void:
		_id = id
		_stream = stream

	func system_id() -> StringName:
		return _id

	func on_daily(state: GameState) -> void:
		var data := state.system_data(_id)
		var rng := state.rng.stream(_stream)
		var rolls: Array = data.get("rolls", [])
		rolls.append(rng.randi_range(0, 999))
		data["rolls"] = rolls
		data["sum"] = int(data.get("sum", 0)) + int(rolls[rolls.size() - 1])
		data["unit"] = float(data.get("unit", 0.0)) + rng.randf()
		if extra_stream != &"":
			var other := state.rng.stream(extra_stream)
			for i in extra_draws:
				other.randi()


## Sistem: günlük karar verir ve gerekçesini kaydeder (SIM-12). roll >= threshold ise "invest", değilse "decline".
class DecisionSystem:
	extends SimSystem
	const THRESHOLD := 500

	func system_id() -> StringName:
		return &"decider"

	func on_daily(state: GameState) -> void:
		var roll := state.rng.stream(&"decider").randi_range(0, 999)
		var decision := &"invest" if roll >= THRESHOLD else &"decline"
		var code := &"roll_above_threshold" if roll >= THRESHOLD else &"roll_below_threshold"
		state.record_reason(&"investor_1", decision, [{"name": &"roll", "value": roll, "weight": 1}], THRESHOLD, code)


## Komut: system_data("cmd")[key] = value. Anahtar String, değer negatif olmayan int olmalı.
class SetValueHandler:
	extends CommandHandler

	func command_type() -> StringName:
		return &"set_value"

	func validate(_state: GameState, params: Dictionary) -> StringName:
		if not (params.get("key", null) is String):
			return &"missing_key"
		if typeof(params.get("value", null)) != TYPE_INT:
			return &"value_not_int"
		if int(params["value"]) < 0:
			return &"value_negative"
		return &""

	func apply(state: GameState, params: Dictionary) -> void:
		state.system_data(&"cmd")[params["key"]] = params["value"]


## Komut: bakiyeden çek. Doğrulama UYGULAMA anındaki durumla yapılır (bakiye ilk çekimle düşer).
class WithdrawHandler:
	extends CommandHandler

	func command_type() -> StringName:
		return &"withdraw"

	func validate(state: GameState, params: Dictionary) -> StringName:
		var balance := int(state.system_data(&"bank").get("balance", 0))
		if int(params.get("amount", 0)) > balance:
			return &"insufficient_funds"
		return &""

	func apply(state: GameState, params: Dictionary) -> void:
		var data := state.system_data(&"bank")
		data["balance"] = int(data.get("balance", 0)) - int(params["amount"])


func new_config() -> SimConfig:
	var cfg := SimConfig.load_default()
	assert_bool(cfg != null and cfg.is_valid()).override_failure_message("varsayılan yapılandırma geçersiz").is_true()
	return cfg


func new_state(world_seed: int = SEED, cfg: SimConfig = null) -> GameState:
	return GameState.create(world_seed, cfg if cfg != null else new_config())


## Durum hash'i; boş/geçersiz hash'i başarısızlık sayar (T-002 ölçüt 7).
func state_hash_of(state: GameState) -> String:
	return assert_hash(state.state_hash())


func assert_hash(h: String) -> String:
	var ok := h.length() == HEX_LEN and h.to_lower() == h and h.hex_decode().size() == HEX_LEN / 2
	assert_bool(ok).override_failure_message("boş/geçersiz SHA-256 hex hash: '%s'" % h).is_true()
	return h


## Sistem seti: iki günlük çekim sistemi + karar sistemi; standart komut işleyicileri.
func new_sim_full() -> Simulation:
	var sim := Simulation.new()
	sim.add_system(DrawSystem.new(&"draw_a", &"stream_a"))
	sim.add_system(DrawSystem.new(&"draw_b", &"stream_b"))
	sim.add_system(DecisionSystem.new())
	sim.add_handler(SetValueHandler.new())
	sim.add_handler(WithdrawHandler.new())
	return sim
