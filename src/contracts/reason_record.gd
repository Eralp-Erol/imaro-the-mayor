class_name ReasonRecord
extends SimDto
## Aktör kararının kaydedilmiş gerekçesi `{aktör, karar, faktörler[{ad,değer,ağırlık}], eşik, tick}`
## (SIM-12, ADR-0002 §7).
##
## Değişmezler (v1.0, `is_consistent()`; sim T-016/T-027 ve mock aynı kurala uyar):
## - `scoring == &"linear"`: `score == Σ factor.contribution()`.
## - `outcome == &"positive"` ⇔ `score >= threshold` (karar_key'deki eylem GERÇEKLEŞTİ: yatırım yaptı, protesto etti…);
##   `outcome == &"negative"` ⇔ `score < threshold` (eylem gerçekleşmedi: yatırım gelmedi — SIM-07).
## Zincir: `parent_ids` bu kararı tetikleyen önceki gerekçeler (UI "neden?" zincirini buradan kurar).

const OUTCOME_POSITIVE := &"positive"
const OUTCOME_NEGATIVE := &"negative"
const SCORING_LINEAR := &"linear"

var id: int = SimContract.NO_ID
var tick: int = 0
var actor: ActorRef = null
## Kararın metin anahtarı (örn. `decision.investor.develop`, `decision.group.protest`).
var decision_key: StringName = &""
var outcome: StringName = OUTCOME_NEGATIVE
var factors: Array[ReasonFactor] = []
var threshold: int = 0
var score: int = 0
var scoring: StringName = SCORING_LINEAR
## Kararın ilgili olduğu varlıklar (referans dizgeleri): `parcel.12`, `vote.1` …
var subjects: PackedStringArray = PackedStringArray()
var parent_ids: PackedInt64Array = PackedInt64Array()
var provenance: StringName = SimContract.PROVENANCE_SIM


func linear_score() -> int:
	var total := 0
	for f in factors:
		total += f.contribution()
	return total


## Puan ve sonuç değişmezleri tutuyor mu? Tutmuyorsa açıklama, tutuyorsa "".
func consistency_error() -> String:
	if scoring != SCORING_LINEAR:
		return "unsupported scoring '%s' (v1.0: linear)" % scoring
	if score != linear_score():
		return "score %d != linear sum %d" % [score, linear_score()]
	if outcome != OUTCOME_POSITIVE and outcome != OUTCOME_NEGATIVE:
		return "unknown outcome '%s'" % outcome
	var expected := OUTCOME_POSITIVE if score >= threshold else OUTCOME_NEGATIVE
	if outcome != expected:
		return "outcome '%s' but score %d vs threshold %d implies '%s'" % [outcome, score, threshold, expected]
	return ""


func is_consistent() -> bool:
	return consistency_error().is_empty()


## Puanı etkenlerden ve sonucu eşikten hesaplar (üreticiler için; değişmezi kurar).
func finalize() -> ReasonRecord:
	score = linear_score()
	outcome = OUTCOME_POSITIVE if score >= threshold else OUTCOME_NEGATIVE
	return self


func is_about(subject_ref: StringName) -> bool:
	return subjects.has(String(subject_ref)) or (actor != null and actor.ref() == subject_ref)


func to_dict() -> Dictionary:
	return {
		"id": id, "tick": tick, "actor": ActorRef.to_variant(actor), "decision_key": decision_key,
		"outcome": outcome, "factors": SimDto.dicts_of(factors), "threshold": threshold, "score": score,
		"scoring": scoring, "subjects": subjects, "parent_ids": parent_ids, "provenance": provenance,
	}


static func from_dict(d: Dictionary) -> ReasonRecord:
	var r := ReasonRecord.new()
	r.id = SimContract.to_int(d.get("id"))
	r.tick = SimContract.to_int(d.get("tick"))
	r.actor = ActorRef.from_variant(d.get("actor"))
	r.decision_key = SimContract.to_name(d.get("decision_key"))
	r.outcome = SimContract.to_name(d.get("outcome", OUTCOME_NEGATIVE))
	for fd: Variant in d.get("factors", []):
		if fd is Dictionary:
			r.factors.append(ReasonFactor.from_dict(fd))
	r.threshold = SimContract.to_int(d.get("threshold"))
	r.score = SimContract.to_int(d.get("score"))
	r.scoring = SimContract.to_name(d.get("scoring", SCORING_LINEAR))
	r.subjects = SimContract.to_string_array(d.get("subjects", []))
	r.parent_ids = SimContract.to_int64_array(d.get("parent_ids", []))
	r.provenance = SimContract.to_name(d.get("provenance", SimContract.PROVENANCE_SIM))
	return r
