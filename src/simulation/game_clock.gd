class_name GameClock
extends RefCounted
## One game day per two real seconds at 1x. No dropped accumulated time.
const DAY_SECONDS := 2.0
var speed: int = 0
var accumulator: float = 0.0

func advance(delta: float, simulation: CitySimulation) -> void:
	if speed == 0 or delta <= 0: return
	accumulator += delta * speed
	while accumulator + 0.00000001 >= DAY_SECONDS:
		accumulator -= DAY_SECONDS
		simulation.tick()
