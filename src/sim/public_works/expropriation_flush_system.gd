class_name ExpropriationFlushSystem
extends SimSystem
## T-042b · Komut aşamasında alınan/geri verilen parsellerin değişim halkasına (T-045) yazılması. Halka tick'in
## günlük adımında `begin_tick` ile açılır; komut aşaması bundan ÖNCE çalıştığı için orada yazılan not kaybolurdu.
## Bu sistem ekonomiden SONRA kayıtlıdır ve bekleyen notları o tick'in sınırına yazar. Durum tutmaz (not kuyruğu
## çalışma bağlamındadır, kayda girmez: yükleme halkayı zaten sıfırlar).

var _ctx: PublicWorksContext


func _init(ctx: PublicWorksContext) -> void:
	_ctx = ctx


func system_id() -> StringName:
	return &"public_works.expropriation_flush"


func on_daily(_state: GameState) -> void:
	if _ctx.pending_notes.is_empty():
		return
	if _ctx.economy != null:
		for id in _ctx.pending_notes:
			_ctx.economy.change_log().note(id)
	_ctx.pending_notes = PackedInt64Array()
