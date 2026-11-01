class_name PolicyView
extends SimDto
## Belediyenin kalıcı politikalarından birinin güncel durumu (v1.7, ADR-0005 Ek I, T-065, D-016): `SimFacade.policies()`
## satırı. Sim'in kendi kaydıdır (uydurma yok); politika `policy.set` komutuyla açılıp kapanır. Politika bir SEÇİMDİR
## (CAN-10): kapalı olması da meşrudur ve varsayılandır; hiç değiştirilmediyse `changed_tick == -1`.

## Kamulaştırmada yeniden iskân yükümlülüğü (D-015/D-016).
const ID_RESETTLEMENT := &"resettlement"
## `policy.set` ret `args.why` değerleri (`command.reject.precondition`): yapılandırmada yok / zaten bu değerde.
const WHY_NOT_BUILT := "system.not_built"
const WHY_UNCHANGED := "policy.unchanged"

var policy_id: StringName = &""
var enabled: bool = false
## Son değişimin tick'i (-1 = hiç değiştirilmedi) ve onu yapan komutun sözleşme kimliği (0 = hiç).
var changed_tick: int = -1
var changed_by_command: int = SimContract.NO_ID
var provenance: StringName = SimContract.PROVENANCE_SIM


func to_dict() -> Dictionary:
	return {
		"policy_id": policy_id, "enabled": enabled, "changed_tick": changed_tick,
		"changed_by_command": changed_by_command, "provenance": provenance,
	}


static func from_dict(d: Dictionary) -> PolicyView:
	var v := PolicyView.new()
	v.policy_id = SimContract.to_name(d.get("policy_id", ""))
	v.enabled = SimContract.to_bool(d.get("enabled", false))
	v.changed_tick = SimContract.to_int(d.get("changed_tick", -1))
	v.changed_by_command = SimContract.to_int(d.get("changed_by_command"))
	v.provenance = SimContract.to_name(d.get("provenance", SimContract.PROVENANCE_SIM))
	return v
