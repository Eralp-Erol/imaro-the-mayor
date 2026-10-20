class_name CouncilVoteView
extends SimDto
## Bir meclis oylaması (SIM-05). Oylama açıkken oyun akar (duraklatma yok); sonuç tick'te çözülür.
## Sayılar oy (koltuk) sayısıdır; sonuç `passed` ⇔ yes > no (eşitlik kuralı sim yapılandırmasındadır, ÇM).

const STATUS_PENDING := &"pending"
const STATUS_PASSED := &"passed"
const STATUS_FAILED := &"failed"

var vote_id: int = SimContract.NO_ID
## Oylanan şeyin referansı (`budget.3`, `command.7` …) ve başlık anahtarı.
var subject_ref: StringName = &""
var title_key: StringName = &""
var opened_tick: int = 0
## Sonucun beklendiği / çözüldüğü tick.
var closes_tick: int = 0
var status: StringName = STATUS_PENDING
var yes: int = 0
var no: int = 0
var abstain: int = 0
var positions: Array[CouncilBlocView] = []
var reason_ids: PackedInt64Array = PackedInt64Array()


func ref() -> StringName:
	return SimContract.ref(SimContract.REF_VOTE, vote_id)


func to_dict() -> Dictionary:
	return {
		"vote_id": vote_id, "subject_ref": subject_ref, "title_key": title_key, "opened_tick": opened_tick,
		"closes_tick": closes_tick, "status": status, "yes": yes, "no": no, "abstain": abstain,
		"positions": SimDto.dicts_of(positions), "reason_ids": reason_ids,
	}


static func from_dict(d: Dictionary) -> CouncilVoteView:
	var v := CouncilVoteView.new()
	v.vote_id = SimContract.to_int(d.get("vote_id"))
	v.subject_ref = SimContract.to_name(d.get("subject_ref", ""))
	v.title_key = SimContract.to_name(d.get("title_key", ""))
	v.opened_tick = SimContract.to_int(d.get("opened_tick"))
	v.closes_tick = SimContract.to_int(d.get("closes_tick"))
	v.status = SimContract.to_name(d.get("status", STATUS_PENDING))
	v.yes = SimContract.to_int(d.get("yes"))
	v.no = SimContract.to_int(d.get("no"))
	v.abstain = SimContract.to_int(d.get("abstain"))
	for pd: Variant in d.get("positions", []):
		if pd is Dictionary:
			v.positions.append(CouncilBlocView.from_dict(pd))
	v.reason_ids = SimContract.to_int64_array(d.get("reason_ids", []))
	return v
