class_name Simulation
extends RefCounted
## Sistem zamanlayıcısı + tick adımı (T-002 ölçüt 1, TEK-01/02): state(t+1) = step(state(t), komutlar(t)).
## `step(state)` DELTA ALMAZ; gerçek zaman -> tamsayı tick dönüşümü `src/app/tick_driver.gd`'dedir.
##
## Bir adımın sabit sırası:
##   1. Komut sınırı: bekleyen komutlar gönderim sırasıyla doğrulanıp uygulanır (Commands.process_pending).
##   2. tick += 1 (1 tick = 1 oyun günü).
##   3. Tüm sistemlerin on_daily (kayıt sırası); sonra tick ay sınırındaysa tüm on_monthly; sonra çeyrek
##      sınırındaysa tüm on_quarterly (aşama-öncelikli, her aşamada kayıt sırası).
## Takvim oranları state.config'ten gelir (data/sim/core_config.json).

var _systems: Array[SimSystem] = []
var _system_ids: Dictionary = {}
var _handlers: Dictionary = {}  # komut türü (String) -> CommandHandler


## Sistemi çalışma sırasının SONUNA ekler. Kimlik tekrarında push_error + false.
func add_system(system: SimSystem) -> bool:
	var key := String(system.system_id())
	if _system_ids.has(key):
		push_error("Simulation: duplicate system id '%s'" % key)
		return false
	_system_ids[key] = true
	_systems.append(system)
	return true


## Komut işleyicisini kaydeder. Tür tekrarında push_error + false.
func add_handler(handler: CommandHandler) -> bool:
	var key := String(handler.command_type())
	if key.is_empty() or _handlers.has(key):
		push_error("Simulation: invalid or duplicate command type '%s'" % key)
		return false
	_handlers[key] = handler
	return true


func system_count() -> int:
	return _systems.size()


## Komut türünün işleyicisi (kayıtlı değilse null). Facade ön doğrulaması (`validate_command`) bunu kullanır.
func handler_for(command_type: StringName) -> CommandHandler:
	return _handlers.get(String(command_type), null)


## Tek tick ilerletir.
func step(state: GameState) -> void:
	Commands.process_pending(state, _handlers)
	state.tick += 1
	for system in _systems:
		system.on_daily(state)
	if state.is_month_boundary():
		for system in _systems:
			system.on_monthly(state)
	if state.is_quarter_boundary():
		for system in _systems:
			system.on_quarterly(state)


## `ticks` kez `step`.
func advance(state: GameState, ticks: int) -> void:
	for i in ticks:
		step(state)
