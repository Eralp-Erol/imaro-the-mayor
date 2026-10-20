class_name PoliticsSnapshot
extends SnapshotProvider
## Snapshot sağlayıcısı (T-017 ölçüt 5): `groups` ve `council` bölümlerini gerçek siyasi durumdan doldurur ve
## `x.sim.available.<bölüm>` bayraklarını açar. Gündem öğeleri sözleşme v1.0'da tipli bölüm DEĞİLDİR (AgendaItemView
## v1.1 isteği): açık öğe sayısı ve bekleyen oylama tahminleri `extensions` içinde ilkel değerlerle taşınır
## (anahtar öneki `x.sim.`; "satisfaction/approval" gibi toplam-skor anahtarları kullanılmaz, SIM-09).

const GROUPS_FLAG := "x.sim.available.groups"
const COUNCIL_FLAG := "x.sim.available.council"
const AGENDA_FLAG := "x.sim.available.agenda"
const OPEN_ITEMS := "x.sim.agenda.open"
const FORECAST_PREFIX := "x.sim.council.forecast."

var _ctx: PoliticsContext


func _init(ctx: PoliticsContext) -> void:
	_ctx = ctx


func fill(state: GameState, snapshot: SimSnapshot) -> void:
	if not PoliticsState.is_initialized(state):
		return
	snapshot.group_reactions = PoliticsQuery.group_views(state)
	snapshot.council = PoliticsQuery.council_view(state, _ctx)
	snapshot.extensions[GROUPS_FLAG] = true
	snapshot.extensions[COUNCIL_FLAG] = true
	snapshot.extensions[AGENDA_FLAG] = true
	snapshot.extensions[OPEN_ITEMS] = PoliticsQuery.agenda(state, _ctx).size()
	var forecasts := PoliticsQuery.forecasts(state, _ctx)
	var ids: Array = forecasts.keys()
	ids.sort()
	for id: int in ids:
		var forecast: Dictionary = forecasts[id]
		for field_name in ["yes", "no", "abstain", "swing"]:
			snapshot.extensions["%s%s.%d" % [FORECAST_PREFIX, field_name, id]] = int(forecast[field_name])
