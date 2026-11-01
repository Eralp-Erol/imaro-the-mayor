class_name PolicyText
extends RefCounted
## Politika (T-065, D-016) metin yardımcısı: SAF, düğüm yok. Adlar ve durumlar YALNIZ `PolicyView` / `policy.changed`
## olay args'ından gelir; bilinmeyen politika kimliği ham anahtar olarak değil genel adla ("Politika") görünür.

const EVENT_CHANGED := &"event.policy.changed"


## Politikanın okunur adı ("Yeniden iskân"); tanımsız kimlikte genel ad.
static func policy_name(policy_id: Variant) -> String:
	var key := StringName("policy.name.%s" % str(policy_id))
	return UiText.t(key) if UiText.has(key) else UiText.t(&"policy.name.generic")


static func state_text(enabled: bool) -> String:
	return UiText.t(&"policy.state.on" if enabled else &"policy.state.off")


## `policy.changed` olay metni: "Yeniden iskân politikası açıldı" / "... kapatıldı".
static func event_text(event: SimEvent) -> String:
	var key := &"event.policy.enabled" if bool(event.args.get("enabled", false)) else &"event.policy.disabled"
	return UiText.t(key, {"policy": policy_name(event.args.get("policy_id", ""))})


static func handles_event(message_key: StringName) -> bool:
	return message_key == EVENT_CHANGED


## Sim'in `policy.set` ret nedeni (kısa Türkçe): önce `args.why` (`policy.unchanged`, `system.not_built`), sonra
## genel metin.
static func refusal_reason(args: Dictionary) -> String:
	var raw := str(args.get("why", ""))
	var why := StringName("policy.why.%s" % raw.trim_prefix("policy.").trim_prefix("system."))
	if raw != "" and UiText.has(why):
		return UiText.t(why)
	return UiText.t(&"policy.refused_generic")
