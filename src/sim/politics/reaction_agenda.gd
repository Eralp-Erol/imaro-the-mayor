class_name ReactionAgenda
extends RefCounted
## T-042b · Yerinden edilmenin gündem ve medya yolu (D-008/D-011, political-events PE-01/PE-04). Kamulaştırma bir kesimi
## yerinden ettiyse (kesimin `displacement` sinyali veri eşiğinde) PE-01 tipi bir gündem öğesi açılır; tepki basamağı
## (`bloc.react`) şartı aranmaz: yerinden edilme doğrudan nedendir ve oyuncunun görmesi gerekir. Öğenin ateşleme
## gerekçesi `ReactionCause` kaydına bağlıdır (komut, parseller, hane sayısı). Aynı nedenle medya organına haber adayı
## verilir (PE-04 yolu): yayın kararını medya motoru KENDİ kuralıyla verir, burada yayımlanmayı zorlayan bir şey yoktur.
##
## YALNIZ tepki defteri varken çalışır (kamulaştırmasız koşuda durum ve hash değişmez). Silahlanma/bekleme/karşılıklı
## dışlama kapıları olay motorunundur (aynı kapılar). Özel bina yaratmaz (CAN-03): yalnız gündem + haber + gerekçe.
## Sayılar `PoliticsConfig.reactions["agenda"]` (veri). Kesim anahtar sırasıyla gezilir; tarama başına en çok bir öğe.

const SCALE := 1000
const SOURCE := "displacement"


## Haftalık (PoliticsSystem; kesim taraması SONRASI, olay taramasından sonra). Açılan öğe sayısını döner.
@warning_ignore("integer_division")
static func scan(state: GameState, ctx: PoliticsContext) -> int:
	if not PublicWorksState.has_reactions(state):
		return 0
	var cfg: Dictionary = ctx.politics.reactions["agenda"]
	var pol := PoliticsState.data(state)
	var best := ""
	var best_level := 0
	for key in PoliticsState.bloc_keys(state):  # eşitlikte anahtar sırası (ilk gelen kalır)
		var level := int(pol["blocs"][key]["signals"].get("displacement", 0))
		if level >= int(cfg["min_displacement_pm"]) and level > best_level:
			best = key
			best_level = level
	if best.is_empty():
		return 0
	var pressure := clampi(best_level * SCALE / int(cfg["full_displacement_pm"]), 0, SCALE)
	if not EventEngine.can_open_direct(state, ctx, str(cfg["template"]), pressure):
		return 0  # kapılar kapalıyken neden kaydı yazılmaz (kayıt hacmi)
	var bloc: Dictionary = pol["blocs"][best]
	var rows := EconomyQuery.region_stats(state, ctx.economy)
	var cause := ReactionCause.record(state, ctx, best, bloc, BlocEngine.reaction_signals(state, ctx, rows))
	if cause.is_empty():
		return 0
	PoliticsState.count(state, "reason_records")
	var opened := EventEngine.open_direct(state, ctx, str(cfg["template"]), best, pressure, SOURCE,
		PackedInt64Array([cause["id"]]))
	if opened:
		_queue_story(state, best, bloc, pressure, cause)
	return 1 if opened else 0


## Medya haber adayı: konu = kesimin baskın şikâyet konusu; neden = yerinden edilme kaydı.
@warning_ignore("integer_division")
static func _queue_story(state: GameState, key: String, bloc: Dictionary, pressure: int, cause: Dictionary) -> void:
	var actor := ActorStore.actor_ref(state, key)
	var topic := BlocEngine.dominant_topic(actor["salience"], actor["state"].get("grievances", {}))
	var total := 0
	for other in PoliticsState.bloc_keys(state):
		total += int(PoliticsState.data(state)["blocs"][other]["size"])
	MediaEngine.queue_story(state, {
		"kind": "protest", "topic": topic, "subject": key, "conflict": pressure,
		"scale": int(bloc["size"]) * SCALE / maxi(total, 1), "fact": -pressure,
		"parent_ids": [int(cause["id"])], "key": "displacement|%s" % key,
	})
