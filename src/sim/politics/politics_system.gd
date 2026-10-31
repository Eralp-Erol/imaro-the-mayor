class_name PoliticsSystem
extends SimSystem
## Siyasi aktörler sistemi (T-017): kesim tepkileri, küçük meclis oylaması, medya tonu ve siyasi olaylar. Sıra:
## ekonomi ve aktör sistemlerinden SONRA kayıtlıdır (`PoliticsBootstrap`): aktör durumu ve ekonomi sütunları o gün
## güncelken okunur. Sistem DURUM TUTMAZ: kalıcı veri `state.systems["politics"]` (PoliticsState) ve kesim defterleri
## `state.systems["actors"]` içindedir. Rastgelelik: tohumdan türeyen anahtarlı çekilişler (akış tüketilmez).
##
## Günlük: vadesi gelen medya tonu, meclis oylamaları, olay etkileri/aşamaları. Haftalık (`scan_days`): kesimler,
## medya haberleri, olay tarayıcısı. Siyasi sistem CAN-03'ü korur: yalnız koşulları (imar bekleyen alanı, şikâyet,
## ton, risk) değiştirir; özel bina yaratmaz.

const EVENTS_STREAM := &"events"

var _ctx: PoliticsContext


## Doğrulanmış bağlamla sistem; geçersizde push_error + null.
static func create(ctx: PoliticsContext) -> PoliticsSystem:
	var problem := ctx.problem() if ctx != null else "bağlam yok"
	if not problem.is_empty():
		push_error("PoliticsSystem: %s" % problem)
		return null
	var system := PoliticsSystem.new()
	system._ctx = ctx
	return system


func system_id() -> StringName:
	return StringName(PoliticsState.KEY)


func context() -> PoliticsContext:
	return _ctx


func on_daily(state: GameState) -> void:
	if not PoliticsState.ensure_initialized(state, _ctx):
		return
	state.rng.stream(EVENTS_STREAM)
	BlocEngine.ensure_started(state, _ctx)
	MediaEngine.apply_due(state, _ctx)
	CouncilEngine.resolve_due(state, _ctx)
	EventEngine.step_daily(state, _ctx)
	if state.tick % int(_ctx.politics.cadence["scan_days"]) == 0:
		PoliticsState.count(state, "scans")
		BlocEngine.scan(state, _ctx)
		MediaEngine.scan(state, _ctx)
		EventEngine.scan(state, _ctx)
		ReactionAgenda.scan(state, _ctx)  # T-042b: yerinden edilme gündem maddesi (defter yoksa hiçbir şey yapmaz)
