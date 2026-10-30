class_name CommandReject
extends RefCounted
## Sim ret kodu -> sözleşme ret anahtarı (ADR-0005 §4: `command.reject.*`). Sim işleyicileri kısa makine-okur kod
## döndürür (`CommandHandler.validate`); UI'ya giden anahtar buradan türetilir. Sözleşme kümesinde olmayan kod
## `precondition` olur (kodun kendisi olay argümanı `code` ile korunur, bilgi kaybolmaz).

const PREFIX := "command.reject."
## Sözleşmenin tanıdığı ret son ekleri (CommandResult.REJECT_* ile eşleşir; sözleşme testi denetler).
const CONTRACT_CODES: Array[StringName] = [
	&"unknown_kind", &"not_a_mayor_verb", &"missing_param", &"unknown_param", &"bad_param_type",
	&"invalid_value", &"invalid_target", &"precondition",
]
const FALLBACK_CODE := &"precondition"
## v1.3 (T-042, ADR-0005 Ek E): işleyicinin kendi ret anahtarı ailesi. Bu önekle başlayan kod AYNEN ret anahtarıdır
## (`public_work.reject.water` ...): duruma bağlı, kullanıcıya özel metin taşır, `precondition`a düşürülmez.
const PASSTHROUGH_PREFIXES: Array[String] = ["public_work.reject."]
## Çekirdeğin kendi kodları -> sözleşme son eki.
const ALIASES := {&"unknown_command": &"unknown_kind"}


## Kod sözleşme kümesinde mi (takma ad dahil)?
static func is_contract_code(code: StringName) -> bool:
	return CONTRACT_CODES.has(ALIASES.get(code, code)) or is_passthrough(code)


## Kod, sözleşme ret anahtarının KENDİSİ mi (`public_work.reject.*`)?
static func is_passthrough(code: StringName) -> bool:
	for prefix in PASSTHROUGH_PREFIXES:
		if String(code).begins_with(prefix):
			return true
	return false


static func key_for(code: StringName) -> StringName:
	if is_passthrough(code):
		return code
	var suffix: StringName = ALIASES.get(code, code)
	if not CONTRACT_CODES.has(suffix):
		suffix = FALLBACK_CODE
	return StringName(PREFIX + String(suffix))
