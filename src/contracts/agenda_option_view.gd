class_name AgendaOptionView
extends SimDto
## Bir gündem öğesine verilebilecek bir yanıt (v1.5 isteğe bağlı ek, ADR-0005 Ek F): `AgendaItemView.options` satırı.
## YALNIZ sim'in gerçekten bir etki üretebildiği seçenekler listelenir (etkisiz seçenek/sahte düğme yok); seçim
## `SimCommand.agenda_respond(item_id, option_id)` ile yapılır. Kilitli seçenek (yetki yok) gizlenmez: `available ==
## false` ve `locked_by` yetki anahtarıdır; komut yine `precondition` / `why = authority.locked` ile reddedilir.
## Bedel alanı YOKTUR: sim bugün seçenek bedelini (bütçe, siyasi sermaye) düşmez, sahte bedel gösterilmez.
## `effects`: veriden türeyen ÖNİZLEME (sahte kesinlik yok: sayısal büyüklük verilmez, yalnız yön/zaman). Her eleman
## `{target, scope, direction (-1|+1: hedef değerin beklenen yönü), delay_days, duration_days, curve}`; yalnız bu
## öğede gerçekten uygulanabilecek etkiler (hedefi/kapsamı olmayan etki listelenmez). `target` kapalı küme:
## `bloc.grievance, bloc.satisfaction, relation.trust, investor.political_risk, media.tone, council.friction`.
## Metin yok: `label_key` anahtardır.

const EFFECT_KEYS: Array[String] = ["target", "scope", "direction", "delay_days", "duration_days", "curve"]

var option_id: StringName = &""
var verb: StringName = &""
var label_key: StringName = &""
var available: bool = false
var locked_by: StringName = &""
var effects: Array = []


func to_dict() -> Dictionary:
	var out: Array = []
	for effect: Variant in effects:
		out.append(SimContract.to_args(effect))
	return {
		"option_id": option_id, "verb": verb, "label_key": label_key, "available": available,
		"locked_by": locked_by, "effects": out,
	}


static func from_dict(d: Dictionary) -> AgendaOptionView:
	var v := AgendaOptionView.new()
	v.option_id = SimContract.to_name(d.get("option_id", ""))
	v.verb = SimContract.to_name(d.get("verb", ""))
	v.label_key = SimContract.to_name(d.get("label_key", ""))
	v.available = SimContract.to_bool(d.get("available", false))
	v.locked_by = SimContract.to_name(d.get("locked_by", ""))
	var raw: Variant = d.get("effects", [])
	if raw is Array:
		for effect: Variant in raw:
			v.effects.append(SimContract.to_args(effect))
	return v
