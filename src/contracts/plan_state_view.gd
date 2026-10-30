class_name PlanStateView
extends SimDto
## Parselin İMAR PLANI durumu (v1.4, ADR-0005 Ek G, T-043A/D-010): `SimFacade.plan_state(parcel_id)`. Sim'in kendi
## türetmesidir (`ParcelPlanning.describe`); UI durumu ve yürürlük gününü uydurmaz. Değer kopyası, salt okunur.
## `state`: `untracked` (plan kavramı kapalı ya da kaynak sunmuyor: mock dahil) | `unplanned` (Plansız) | `proposed`
## (Teklif verildi; `due_tick` yürürlük günü, meclis oylaması sürerken -1 ve `vote_ref` dolu) | `planned` (Planlı) |
## `plan_rejected` (meclis yolu açıkken oylama reddetti; yeniden teklif edilebilir) | `existing` (T0'dan yapılı: plan
## akışı yok). Metin yok: UI etiketi `state` anahtarından kurar.

const STATE_UNTRACKED := &"untracked"
const STATE_UNPLANNED := &"unplanned"
const STATE_PROPOSED := &"proposed"
const STATE_PLANNED := &"planned"
const STATE_REJECTED := &"plan_rejected"
const STATE_EXISTING := &"existing"
## Yok değeri (`due_tick`, `rejected_tick`, `density`, `max_height_m`): -1.
const NONE := -1

var provenance: StringName = SimContract.PROVENANCE_SIM
var parcel_id: int = SimContract.NO_ID
var state: StringName = STATE_UNTRACKED
## Yürürlükteki plan kullanımı (`zone.*`; yoksa boş) ve bekleyen teklifin kullanımı.
var zone: StringName = &""
var pending_zone: StringName = &""
## Yürürlük günü (tick); meclis oylaması sürerken ya da teklif yokken -1.
var due_tick: int = NONE
## Durumu doğuran komut (teklif / yürürlükteki plan / reddedilen teklif; yoksa 0) ve `command.N` başvurusu.
var command_id: int = SimContract.NO_ID
var source_ref: StringName = &""
## Planın içeriği: yoğunluk (‰) ve en çok yükseklik (m); -1 = imar varsayılanı / sınır yok.
var density: int = NONE
var max_height_m: int = NONE
## Son reddedilen teklif (meclis yolu): komut ve tick; yoksa 0 / -1.
var rejected_command_id: int = SimContract.NO_ID
var rejected_tick: int = NONE
## Sürmekte olan meclis oylaması (`vote.N`; yoksa boş).
var vote_ref: StringName = &""


func to_dict() -> Dictionary:
	return {
		"provenance": provenance, "parcel_id": parcel_id, "state": state, "zone": zone, "pending_zone": pending_zone,
		"due_tick": due_tick, "command_id": command_id, "source_ref": source_ref, "density": density,
		"max_height_m": max_height_m, "rejected_command_id": rejected_command_id, "rejected_tick": rejected_tick,
		"vote_ref": vote_ref,
	}


static func from_dict(d: Dictionary) -> PlanStateView:
	var v := PlanStateView.new()
	v.provenance = SimContract.to_name(d.get("provenance", SimContract.PROVENANCE_SIM))
	v.parcel_id = SimContract.to_int(d.get("parcel_id"))
	v.state = SimContract.to_name(d.get("state", STATE_UNTRACKED))
	v.zone = SimContract.to_name(d.get("zone", ""))
	v.pending_zone = SimContract.to_name(d.get("pending_zone", ""))
	v.due_tick = SimContract.to_int(d.get("due_tick", NONE), NONE)
	v.command_id = SimContract.to_int(d.get("command_id"))
	v.source_ref = SimContract.to_name(d.get("source_ref", ""))
	v.density = SimContract.to_int(d.get("density", NONE), NONE)
	v.max_height_m = SimContract.to_int(d.get("max_height_m", NONE), NONE)
	v.rejected_command_id = SimContract.to_int(d.get("rejected_command_id"))
	v.rejected_tick = SimContract.to_int(d.get("rejected_tick", NONE), NONE)
	v.vote_ref = SimContract.to_name(d.get("vote_ref", ""))
	return v
