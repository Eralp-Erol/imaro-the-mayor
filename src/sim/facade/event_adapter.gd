class_name EventAdapter
extends RefCounted
## SimEventLog kaydı (sim) -> sözleşme `SimEvent` (T-027 ölçüt 2). Kayıpsız dönüşüm; DTO bir DEĞER kopyasıdır.


static func to_event(rec: Dictionary) -> SimEvent:
	var e := SimEvent.new()
	e.seq = rec["seq"]
	e.tick = rec["tick"]
	e.kind = rec["kind"]
	e.actor = ReasonAdapter.actor_of(rec["actor"])
	e.subjects = (rec["subjects"] as PackedStringArray).duplicate()
	e.message_key = rec["message_key"]
	e.args = SimContract.to_args(rec["args"])
	e.reason_ids = (rec["reason_ids"] as PackedInt64Array).duplicate()
	e.command_id = rec["command_id"]
	e.provenance = SimContract.PROVENANCE_SIM
	return e
