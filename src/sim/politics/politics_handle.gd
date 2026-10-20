class_name PoliticsHandle
extends RefCounted
## `PoliticsBootstrap.create` sonucu (T-017): siyasi katmanlı facade + sistemler + bağlam (T-022/T-026/QA girişi).

var facade: SimFacadeImpl
var economy: EconomySystem
var actors: ActorSystem
var politics: PoliticsSystem
var context: PoliticsContext


## Facade'ın sim durumu (yalnız app katmanı/testler).
func state() -> GameState:
	return facade.game_state()
