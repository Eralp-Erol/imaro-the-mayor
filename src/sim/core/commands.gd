class_name Commands
extends RefCounted
## Komut kuyruğu (T-002 ölçüt 4, TEK-02): oyuncu niyeti yalnız komuttur. Komutlar `submit` ile DURUMDAKİ kuyruğa
## girer (kayda/hash'e dâhil, tekrar oynatılabilir); tick SINIRINDA (`Simulation.step` başı) gönderim sırasıyla
## doğrulanır ve geçerliyse uygulanır; sonuç komut günlüğüne yazılır. Geçersiz komut gerekçe KODU ile reddedilir;
## ret kuyruğun geri kalanını engellemez. Doğrulama gönderimde değil UYGULAMA anındaki durumla yapılır.
##
## Bekleyen kayıt: {seq, issuer, type, params, tick_issued}. Günlük kaydı: bunlara ek
## {tick_applied, status (&"applied"|&"rejected"), reason (ret kodu veya &"")}. Günlük kapasitesi config'te
## (`command_log_capacity`), en eskiler budanır. Parametreler düz veri olmalı (hash/kayıt için).

const STATUS_APPLIED := &"applied"
const STATUS_REJECTED := &"rejected"
const REASON_UNKNOWN := &"unknown_command"
const _MAX_PARAM_DEPTH := 32


## Komutu kuyruğa ekler; seq döndürür. Parametreler düz veri değilse push_error + -1 (eklenmez).
static func submit(state: GameState, type: StringName, params: Dictionary = {},
		issuer: StringName = &"player") -> int:
	if not _is_plain(params, 0):
		push_error("Commands: params not serializable for '%s'" % type)
		return -1
	var seq := state.next_command_seq
	state.next_command_seq += 1
	state.pending_commands.append({
		"seq": seq, "issuer": issuer, "type": type,
		"params": params.duplicate(true), "tick_issued": state.tick,
	})
	return seq


static func pending_count(state: GameState) -> int:
	return state.pending_commands.size()


## Tüm günlük kayıtları (kopya), eskiden yeniye.
static func log_entries(state: GameState) -> Array:
	return state.command_log.duplicate(true)


static func rejected(state: GameState) -> Array:
	var out: Array = []
	for entry: Dictionary in state.command_log:
		if entry["status"] == STATUS_REJECTED:
			out.append(entry.duplicate(true))
	return out


## Bekleyen komutları işler (tick sınırı). `handlers`: komut türü (String) -> CommandHandler.
## İşlem sırasında gönderilen yeni komutlar bir SONRAKİ sınıra kalır.
static func process_pending(state: GameState, handlers: Dictionary) -> void:
	if state.pending_commands.is_empty():
		return
	var batch: Array = state.pending_commands
	state.pending_commands = []
	var capacity := int(state.config["command_log_capacity"])
	for cmd: Dictionary in batch:
		var entry: Dictionary = cmd.duplicate(true)  # işleyici params'ı değiştirse bile günlük özgün komutu tutar
		var handler: CommandHandler = handlers.get(String(cmd["type"]), null)
		var reason: StringName = REASON_UNKNOWN if handler == null else handler.validate(state, cmd["params"])
		if reason == &"":
			handler.apply(state, cmd["params"])
		entry["tick_applied"] = state.tick
		entry["status"] = STATUS_APPLIED if reason == &"" else STATUS_REJECTED
		entry["reason"] = reason
		state.command_log.append(entry)
	while state.command_log.size() > capacity:
		state.command_log.pop_front()


## StateHash'in desteklediği düz veri mi (null/bool/int/float/String/StringName/Array/Dictionary/Packed*)?
static func _is_plain(value: Variant, depth: int) -> bool:
	if depth > _MAX_PARAM_DEPTH:
		return false
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_STRING_NAME:
			return true
		TYPE_PACKED_BYTE_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, \
		TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_STRING_ARRAY:
			return true
		TYPE_ARRAY:
			for item: Variant in value:
				if not _is_plain(item, depth + 1):
					return false
			return true
		TYPE_DICTIONARY:
			for key: Variant in value:
				if not _is_plain(key, depth + 1) or not _is_plain(value[key], depth + 1):
					return false
			return true
	return false
