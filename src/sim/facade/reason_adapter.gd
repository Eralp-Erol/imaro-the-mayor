class_name ReasonAdapter
extends RefCounted
## ReasonLog kaydı (sim) -> sözleşme `ReasonRecord` (T-027 ölçüt 1-2). ReasonLog zaten ADR-0005 biçiminde tamsayıdır;
## dönüşüm KAYIPSIZDIR, tek istisna: `parent_ids` içinde artık saklanmayan (budanmış) gerekçeler elenir
## (sözleşme: zincir çözümlenebilir olmalı, `SimContractChecks.check_reason_id`).

const ACTOR_PREFIX := "actor."


## `actor.<tür>.<n>` -> ActorRef (ad anahtarı yer tutucu `actor.<tür>.<n>.name`, ADR-0005 §9); boş/geçersiz -> null.
static func actor_of(ref: StringName) -> ActorRef:
	var text := String(ref)
	if text.is_empty() or not text.begins_with(ACTOR_PREFIX):
		return null
	var parsed := SimContract.parse_ref(ref)
	var kind := String(parsed["kind"]).trim_prefix(ACTOR_PREFIX)
	if kind.is_empty() or int(parsed["id"]) < 1:
		return null
	return ActorRef.make(StringName(kind), int(parsed["id"]), StringName(text + ".name"))


## `first_retained_id`: ReasonLog'da hâlâ saklanan en eski id (daha eski ebeveynler elenir).
static func to_record(rec: Dictionary, first_retained_id: int) -> ReasonRecord:
	var r := ReasonRecord.new()
	r.id = rec["id"]
	r.tick = rec["tick"]
	r.actor = actor_of(rec["actor"])
	r.decision_key = rec["decision"]
	r.outcome = rec["outcome"]
	for fd: Dictionary in rec["factors"]:
		var f := ReasonFactor.make(fd["name"], fd["value"], fd["weight"])
		f.is_estimate = fd["is_estimate"]
		f.source_ref = fd["source_ref"]
		r.factors.append(f)
	r.threshold = rec["threshold"]
	r.score = rec["score"]
	r.scoring = ReasonRecord.SCORING_LINEAR
	r.subjects = (rec["subjects"] as PackedStringArray).duplicate()
	for parent in rec["parent_ids"] as PackedInt64Array:
		if parent >= first_retained_id:
			r.parent_ids.append(parent)
	r.provenance = SimContract.PROVENANCE_SIM
	return r
