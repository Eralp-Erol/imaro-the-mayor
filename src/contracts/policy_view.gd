class_name PolicyView
extends SimDto
## Belediyenin kalıcı politikalarından birinin güncel durumu (v1.7, ADR-0005 Ek I, T-065, D-016): `SimFacade.policies()`
## satırı. Sim'in kendi kaydıdır (uydurma yok); politika `policy.set` komutuyla açılıp kapanır. Politika bir SEÇİMDİR
## (CAN-10): kapalı olması da meşrudur ve varsayılandır; hiç değiştirilmediyse `changed_tick == -1`.
##
## v1.9 (T-067, D-019 E1; ADR-0005 Ek L) · BEKLEME LİSTESİ verisi (isteğe bağlı; varsayılan "kimse beklemiyor"):
## yol yapılınca ev bulunamayan aileler listeye girer, yatırımcıların sonradan bitirdiği yeni evler önce onlara verilir.
## `waiting_households` şu an bekleyen aile toplamı, `waiting_by_region` bölge kodu -> bekleyen aile (yalnız > 0),
## `served_households` listeden sonradan ev verilmiş toplam aile. Üçü de sim'in kendi kaydıdır (uydurma yok); politika
## kapalıyken de listede bekleyen aile gösterilir (atama durur, aile yerinde kalır).

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
var waiting_households: int = 0
var waiting_by_region: Dictionary = {}
var served_households: int = 0
var provenance: StringName = SimContract.PROVENANCE_SIM


func to_dict() -> Dictionary:
	return {
		"policy_id": policy_id, "enabled": enabled, "changed_tick": changed_tick,
		"changed_by_command": changed_by_command, "waiting_households": waiting_households,
		"waiting_by_region": waiting_by_region.duplicate(), "served_households": served_households,
		"provenance": provenance,
	}


static func from_dict(d: Dictionary) -> PolicyView:
	var v := PolicyView.new()
	v.policy_id = SimContract.to_name(d.get("policy_id", ""))
	v.enabled = SimContract.to_bool(d.get("enabled", false))
	v.changed_tick = SimContract.to_int(d.get("changed_tick", -1))
	v.changed_by_command = SimContract.to_int(d.get("changed_by_command"))
	v.waiting_households = SimContract.to_int(d.get("waiting_households"))
	v.served_households = SimContract.to_int(d.get("served_households"))
	var regions: Variant = d.get("waiting_by_region", {})
	if regions is Dictionary:
		var codes: Array = []
		for code: Variant in regions:
			codes.append(str(code))
		codes.sort()
		for code: String in codes:
			v.waiting_by_region[code] = SimContract.to_int(regions[code])
	v.provenance = SimContract.to_name(d.get("provenance", SimContract.PROVENANCE_SIM))
	return v
