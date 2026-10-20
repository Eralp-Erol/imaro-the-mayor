class_name SimEvent
extends SimDto
## Simülasyonda olan bir şeyin kaydı (ADR-0005). Tüketiciler `events_since(after_seq)` ile ÇEKER (sinyal yok):
## `seq` 1'den başlayan, boşluksuz, artan sıra numarasıdır; aynı tick'te birden çok olay olabilir.
## Olay türleri açık uçludur (StringName); v1.0'da tanımlı olanlar aşağıdadır. Yeni tür = MINOR artış.

const KIND_COMMAND_APPLIED := &"command.applied"
const KIND_COMMAND_REJECTED := &"command.rejected"
## Bir aktör karar verdi (yatırım yaptı/yapmadı…); `reason_ids` gerekçeyi gösterir.
const KIND_ACTOR_DECIDED := &"actor.decided"
const KIND_GROUP_REACTED := &"group.reacted"
const KIND_PARCEL_CHANGED := &"parcel.changed"
const KIND_BUDGET_CHANGED := &"budget.changed"
const KIND_COUNCIL_VOTE_OPENED := &"council.vote_opened"
const KIND_COUNCIL_VOTE_RESOLVED := &"council.vote_resolved"

var seq: int = SimContract.NO_ID
var tick: int = 0
var kind: StringName = &""
var actor: ActorRef = null
## İlgili varlıkların referans dizgeleri (`parcel.12`, `vote.1` …).
var subjects: PackedStringArray = PackedStringArray()
## Bildirim metni anahtarı ve argümanları (gömülü metin yok).
var message_key: StringName = &""
var args: Dictionary = {}
var reason_ids: PackedInt64Array = PackedInt64Array()
## Olayı tetikleyen oyuncu komutu (yoksa 0).
var command_id: int = SimContract.NO_ID
var provenance: StringName = SimContract.PROVENANCE_SIM


func to_dict() -> Dictionary:
	return {
		"seq": seq, "tick": tick, "kind": kind, "actor": ActorRef.to_variant(actor), "subjects": subjects,
		"message_key": message_key, "args": SimContract.to_args(args), "reason_ids": reason_ids,
		"command_id": command_id, "provenance": provenance,
	}


static func from_dict(d: Dictionary) -> SimEvent:
	var e := SimEvent.new()
	e.seq = SimContract.to_int(d.get("seq"))
	e.tick = SimContract.to_int(d.get("tick"))
	e.kind = SimContract.to_name(d.get("kind"))
	e.actor = ActorRef.from_variant(d.get("actor"))
	e.subjects = SimContract.to_string_array(d.get("subjects", []))
	e.message_key = SimContract.to_name(d.get("message_key", ""))
	e.args = SimContract.to_args(d.get("args", {}))
	e.reason_ids = SimContract.to_int64_array(d.get("reason_ids", []))
	e.command_id = SimContract.to_int(d.get("command_id"))
	e.provenance = SimContract.to_name(d.get("provenance", SimContract.PROVENANCE_SIM))
	return e
