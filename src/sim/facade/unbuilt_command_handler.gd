class_name UnbuiltCommandHandler
extends CommandHandler
## Sözleşme kataloğunda olup sim'de henüz KURULMAMIŞ sistemin komutu için işleyici (T-027 ölçüt 3): komut, sistemin
## kurulu olmadığı gerekçesiyle (`command.reject.precondition`, `why = system.not_built`) reddedilir; sessiz kabul,
## sahte uygulama yok. Sistem (örn. T-014 bütçe) kurulunca bu işleyici gerçeğiyle değiştirilir.

var _command_type: StringName
var _system: StringName


func _init(command_type_value: StringName, system_name: StringName) -> void:
	_command_type = command_type_value
	_system = system_name


func command_type() -> StringName:
	return _command_type


func validate(_state: GameState, _params: Dictionary) -> StringName:
	return &"precondition"


func reject_args(_state: GameState, _params: Dictionary) -> Dictionary:
	return {"why": "system.not_built", "system": String(_system)}
