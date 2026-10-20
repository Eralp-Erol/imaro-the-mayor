class_name GroupReactionView
extends SimDto
## Bir seçmen/çıkar grubunun güncel tutumu ve tepkisi (ADR-0005, SIM-09). Grup başına AYRI tutulur; sözleşmede
## tek bir toplam "mutluluk/onay %" alanı YOKTUR ve eklenmez (sözleşme testi denetler).

const REACTION_NEUTRAL := &"neutral"
const REACTION_SUPPORT := &"support"
const REACTION_OPPOSE := &"oppose"
const REACTION_PROTEST := &"protest"

var group: ActorRef = null
## Grubun ağırlıklı bulunduğu bölge kodu (yoksa &"").
var region_code: StringName = &""
## Oyuncu yönetimine tutum: sabit nokta, −FIXED_SCALE … +FIXED_SCALE.
var stance: int = 0
## Son tepkiyle tutumdaki değişim (sabit nokta).
var stance_delta: int = 0
var reaction: StringName = REACTION_NEUTRAL
## Tepki yoğunluğu: 0 … FIXED_SCALE.
var intensity: int = 0
## Tepkinin konusu olan varlıklar (`parcel.12`, `command.3` …) ve gerekçeleri.
var cause_refs: PackedStringArray = PackedStringArray()
var reason_ids: PackedInt64Array = PackedInt64Array()
var tick: int = 0


func to_dict() -> Dictionary:
	return {
		"group": ActorRef.to_variant(group), "region_code": region_code, "stance": stance,
		"stance_delta": stance_delta, "reaction": reaction, "intensity": intensity, "cause_refs": cause_refs,
		"reason_ids": reason_ids, "tick": tick,
	}


static func from_dict(d: Dictionary) -> GroupReactionView:
	var g := GroupReactionView.new()
	g.group = ActorRef.from_variant(d.get("group"))
	g.region_code = SimContract.to_name(d.get("region_code", ""))
	g.stance = SimContract.to_int(d.get("stance"))
	g.stance_delta = SimContract.to_int(d.get("stance_delta"))
	g.reaction = SimContract.to_name(d.get("reaction", REACTION_NEUTRAL))
	g.intensity = SimContract.to_int(d.get("intensity"))
	g.cause_refs = SimContract.to_string_array(d.get("cause_refs", []))
	g.reason_ids = SimContract.to_int64_array(d.get("reason_ids", []))
	g.tick = SimContract.to_int(d.get("tick"))
	return g
