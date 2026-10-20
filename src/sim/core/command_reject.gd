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
## Çekirdeğin kendi kodları -> sözleşme son eki.
const ALIASES := {&"unknown_command": &"unknown_kind"}


## Kod sözleşme kümesinde mi (takma ad dahil)?
static func is_contract_code(code: StringName) -> bool:
	return CONTRACT_CODES.has(ALIASES.get(code, code))


static func key_for(code: StringName) -> StringName:
	var suffix: StringName = ALIASES.get(code, code)
	if not CONTRACT_CODES.has(suffix):
		suffix = FALLBACK_CODE
	return StringName(PREFIX + String(suffix))
