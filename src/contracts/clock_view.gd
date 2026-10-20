class_name ClockView
extends SimDto
## Oyun saati görünümü. Tick = 1 oyun günü (ADR-0002 §4); takvim (yıl/gün) eşlemesi UI yapılandırmasındadır (ÇM).
## Hız SİM DURUMU DEĞİLDİR (determinizmi etkilemez, komut günlüğüne girmez); `available_speeds` profil sınırını
## (`max_game_speed`, ADR-0004) yansıtır. Hız seviyesi → gün/sn eşlemesi tick sürücüsü yapılandırmasındadır (ÇM).

var tick: int = 0
var speed: int = 0
var available_speeds: PackedInt32Array = PackedInt32Array()


func is_paused() -> bool:
	return speed == SimFacade.SPEED_PAUSED


func to_dict() -> Dictionary:
	return {"tick": tick, "speed": speed, "available_speeds": available_speeds}


static func from_dict(d: Dictionary) -> ClockView:
	var c := ClockView.new()
	c.tick = SimContract.to_int(d.get("tick"))
	c.speed = SimContract.to_int(d.get("speed"))
	c.available_speeds = SimContract.to_int32_array(d.get("available_speeds", []))
	return c
