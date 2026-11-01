class_name UndoWindow
extends RefCounted
## T-042c (D-014 §1) · Yol yapımında KLASİK GERİ AL penceresi: başka bir yol parçası (ya da yıkım) yapılana kadar son
## yol "hiç yapılmamış gibi" geri alınabilir. Saf, durumsuz; durum `PublicWorksState` bölümündeki `undo` alanındadır.
##
## Pencere AÇIK iken şunlar birlikte doğrudur:
##  1. Geri alınacak yol, en son yapılan eylemdir (arkasında başka yol/yıkım yok) ve henüz geri alınmamıştır.
##  2. Yolun halk tepkisi (tepki defteri satırları) siyaset katmanının haftalık taramasına GİRMEMİŞTİR: girdiyse kesim
##     durumu (şikâyet/memnuniyet), gündem öğesi ve haber ondan etkilenmiş olur ve geri sarılamaz; yarım geri alma
##     yapmak yerine pencere KAPANIR (`reaction_recorded`). Tepki defterinde satırı olmayan yolda (düz yol) tarama
##     pencereyi kapatmaz. (B-013 / Q-030: D-014 §1 sözü "başka yol yapılana kadar" ile bu kısıt arasındaki fark
##     kullanıcı kararını bekliyor; tarama izleri geri sarılamadığı için kural, karar gelene dek DEĞİŞMEDİ.)
## Tepki katmanı kendi kuralını `PublicWorksContext.reaction_consumed` ile ekleyebilir (örn. gündem öğesi açıldı).

const CAUSE_NONE := &""
const CAUSE_NOTHING := &"nothing"
const CAUSE_SUPERSEDED := &"superseded"
const CAUSE_REACTION := &"reaction_recorded"
## Siyaset sistemi durum anahtarı ve sayaç adı (`PoliticsState.KEY`, `counters.scans`): sınıf bağımlılığı olmadan
## okunur.
const _POLITICS_KEY := "politics"
const _SCANS := "scans"


## Siyasetin haftalık tarama sayacı (siyaset yoksa 0). Yol uygulanırken pencereye yazılır.
static func scans(state: GameState) -> int:
	var politics: Variant = state.systems.get(_POLITICS_KEY, null)
	if politics is Dictionary and (politics as Dictionary).get("counters", null) is Dictionary:
		return int(politics["counters"].get(_SCANS, 0))
	return 0


## {open: bool, cause: StringName (open ise &""), command_id: geri alınacak yolun komut kimliği (yoksa 0)}.
static func status(ctx: PublicWorksContext, state: GameState) -> Dictionary:
	var d := PublicWorksState.data(state)
	if d.is_empty() or PublicWorksState.standing_roads(state).is_empty():
		return _closed(CAUSE_NOTHING, 0)
	var works: Array = d["works"]
	var last: Dictionary = works[works.size() - 1]
	var command_id := int(last["command_id"])
	if not PublicWorksState.is_standing_road(last):
		return _closed(CAUSE_SUPERSEDED, 0)  # son eylem bir yıkım
	var window: Dictionary = d["undo"] if d.has("undo") else {"command_id": command_id, "scans": -1}  # eski kayıt: açık
	if window.is_empty() or int(window["command_id"]) != command_id:
		return _closed(CAUSE_SUPERSEDED, 0)  # başka yol yapıldı ya da geri alma yığılmaz
	if reaction_consumed(ctx, state, command_id, int(window["scans"])):
		return _closed(CAUSE_REACTION, command_id)
	return {"open": true, "cause": CAUSE_NONE, "command_id": command_id}


## Yolun halk tepkisi siyaset katmanınca işlenmiş mi? `scans_at_build` < 0: tarama sayacı bilinmiyor (eski kayıt).
static func reaction_consumed(ctx: PublicWorksContext, state: GameState, command_id: int,
		scans_at_build: int) -> bool:
	if ctx != null and ctx.reaction_consumed.is_valid() and bool(ctx.reaction_consumed.call(state, command_id)):
		return true
	return scans_at_build >= 0 and scans(state) != scans_at_build \
		and PublicWorksState.has_reaction_rows(state, command_id)


static func _closed(cause: StringName, command_id: int) -> Dictionary:
	return {"open": false, "cause": cause, "command_id": command_id}
