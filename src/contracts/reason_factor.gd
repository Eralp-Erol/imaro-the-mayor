class_name ReasonFactor
extends SimDto
## Gerekçe etkeni `{ad, değer, ağırlık}` (SIM-12). Değer ve ağırlık sabit noktalı tamsayıdır (SimContract.FIXED_SCALE).
## Katkı = contribution(value, weight); ReasonRecord.score bu katkıların toplamıdır (v1.0 "linear" puanlama).

## Etken adının metin anahtarı (örn. `reason.factor.land_value`).
var name_key: StringName = &""
var value: int = 0
var weight: int = 0
## Etken bir tahmin mi (UI `reason.estimate` ile etiketler)?
var is_estimate: bool = false
## Etkenin geldiği varlık (isteğe bağlı): `parcel.12`, `actor.group.2` …
var source_ref: StringName = &""


static func make(key: StringName, factor_value: int, factor_weight: int) -> ReasonFactor:
	var f := ReasonFactor.new()
	f.name_key = key
	f.value = factor_value
	f.weight = factor_weight
	return f


func contribution() -> int:
	return SimContract.contribution(value, weight)


func to_dict() -> Dictionary:
	return {
		"name_key": name_key, "value": value, "weight": weight, "is_estimate": is_estimate,
		"source_ref": source_ref,
	}


static func from_dict(d: Dictionary) -> ReasonFactor:
	var f := make(SimContract.to_name(d.get("name_key")), SimContract.to_int(d.get("value")),
		SimContract.to_int(d.get("weight")))
	f.is_estimate = SimContract.to_bool(d.get("is_estimate", false))
	f.source_ref = SimContract.to_name(d.get("source_ref", ""))
	return f
