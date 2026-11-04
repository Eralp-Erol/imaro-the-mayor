class_name AgendaOptions
extends RefCounted
## Gündem öğesinin YANITLANABİLİR seçenekleri (sözleşme `AgendaOptionView`, komut `agenda.respond`; political-events
## §8). Seçenekler `data/politics/events/*.json` verisinden gelir; burada yalnız "bu öğede gerçekten bir etki
## üretebilir mi" süzgeci vardır: etkinin hedefi/kapsamı bu öğede boşsa (örn. konusuz öğede şikâyet etkisi, bölgesiz
## öğede yatırımcı riski, destekleyen kesimi olmayan `beneficiary_blocs`) etki ölüdür, ÖNİZLEMEDE LİSTELENMEZ; hiç
## canlı etkisi olmayan seçenek (örn. `defer`) listelenmez ve komutla da reddedilir (sahte düğme yok). Süzgeç
## `EventEngine.respond`un uygulayacağı kapsam çözümünün AYNISINI kullanır; sorgu salt okunurdur (durum/hash yok).

const REJECT_NO_EFFECT := "option.no_effect"


## Öğenin seçenek görünümleri (şablon sırası). Kilitli seçenek (yetki yok) canlı etkisi varsa gizlenmez.
static func views(state: GameState, ctx: PoliticsContext, item: Dictionary) -> Array[AgendaOptionView]:
	var out: Array[AgendaOptionView] = []
	for option: Dictionary in ctx.politics.template(item["template"])["options"]:
		var live := live_effects(state, ctx, item, option)
		if live.is_empty():
			continue
		var authority := str(option["requires"].get("authority", ""))
		var locked := not authority.is_empty() and not ctx.politics.is_granted(authority)
		var view := AgendaOptionView.new()
		view.option_id = StringName(option["id"])
		view.verb = StringName(option["verb"])
		view.label_key = StringName(option["label_key"])
		view.available = not locked
		view.locked_by = StringName(authority) if locked else &""
		for effect in live:
			view.effects.append(preview(effect))
		out.append(view)
	return out


## Seçenek bu öğede en az bir canlı etki üretir mi? (Komut doğrulaması.) Bilinmeyen seçenek: false.
static func has_live_effect(state: GameState, ctx: PoliticsContext, item: Dictionary, option_id: String) -> bool:
	for option: Dictionary in ctx.politics.template(item["template"])["options"]:
		if option["id"] == option_id:
			return not live_effects(state, ctx, item, option).is_empty()
	return false


## Seçeneğin bu öğede uygulanabilecek etkileri (şablon sırası).
static func live_effects(state: GameState, ctx: PoliticsContext, item: Dictionary, option: Dictionary) -> Array:
	var out: Array = []
	for effect: Dictionary in option["effects"]:
		if _is_live(state, ctx, item, effect):
			out.append(effect)
	return out


## Etki önizlemesi: büyüklük verilmez (sahte kesinlik yok), yalnız hedef, kapsam, yön ve zaman.
static func preview(effect: Dictionary) -> Dictionary:
	return {
		"target": effect["target"], "scope": effect["scope"], "direction": signi(int(effect["magnitude"])),
		"delay_days": int(effect["delay_days"]), "duration_days": int(effect["duration_days"]),
		"curve": effect["curve"],
	}


static func _is_live(state: GameState, ctx: PoliticsContext, item: Dictionary, effect: Dictionary) -> bool:
	if int(effect["magnitude"]) == 0 or int(effect["attribution"]) == 0:
		return false
	var has_topic := not str(item["topic"]).is_empty()
	match effect["target"]:
		"bloc.grievance", "bloc.satisfaction":
			return has_topic and not EventEngine.scope_of(state, ctx, item, effect)["blocs"].is_empty()
		"relation.trust":
			var scope := EventEngine.scope_of(state, ctx, item, effect)
			var targets: Array = (scope["blocs"] as Array) + (scope["members"] as Array)
			return not targets.is_empty() and not ActorStore.protagonist_key(state, ctx.actors).is_empty()
		"investor.political_risk":
			return not str(item["region"]).is_empty()
		"media.tone":
			return has_topic
	return true
