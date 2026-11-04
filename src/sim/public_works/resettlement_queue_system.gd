class_name ResettlementQueueSystem
extends SimSystem
## T-067 (D-019 E1) · Yeniden iskân bekleme listesini her gün, ekonomiden SONRA, yeni biten evlere göre işler
## (`ResettlementQueue.serve`). Durum tutmaz: liste yolların kaydındadır, "yeni ev" işareti politika bölümündedir.
## Politika hiç açılmadıysa ya da kimse beklemiyorsa ilk satırlarda döner: sim durumuna ve hash'e tek bayt yazmaz.

var _ctx: PublicWorksContext


func _init(ctx: PublicWorksContext) -> void:
	_ctx = ctx


func system_id() -> StringName:
	return &"public_works.resettlement_queue"


func on_daily(state: GameState) -> void:
	ResettlementQueue.serve(state, _ctx)
