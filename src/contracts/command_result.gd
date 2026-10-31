class_name CommandResult
extends SimDto
## Komut gönderiminin/ön doğrulamasının sonucu (ADR-0005). Sessiz hata yoktur: ret her zaman gerekçe ANAHTARI taşır.
##
## Yaşam döngüsü: `submit_command` → `queued` (sonraki tick sınırında uygulanacak) ya da `rejected` (hemen).
## Tick sınırında duruma bağlı ret olursa `command.rejected` olayı (aynı command_id) yayımlanır; başarıda
## `command.applied`. `validate_command` (kuru koşu) → `valid` ya da `rejected`, command_id = 0, durum değişmez.

const STATUS_QUEUED := &"queued"
const STATUS_REJECTED := &"rejected"
const STATUS_VALID := &"valid"

const REJECT_UNKNOWN_KIND := &"command.reject.unknown_kind"
## CAN-03: özel bina yaratan/doğrudan geliştiren fiil belediyenin değildir.
const REJECT_NOT_A_MAYOR_VERB := &"command.reject.not_a_mayor_verb"
const REJECT_MISSING_PARAM := &"command.reject.missing_param"
const REJECT_UNKNOWN_PARAM := &"command.reject.unknown_param"
const REJECT_BAD_PARAM_TYPE := &"command.reject.bad_param_type"
const REJECT_INVALID_VALUE := &"command.reject.invalid_value"
## Durum: hedef (parsel, kalem…) yok ya da bu fiile uygun değil.
const REJECT_INVALID_TARGET := &"command.reject.invalid_target"
## Durum: önkoşul tutmuyor (örn. aynı konuda bekleyen oylama var).
const REJECT_PRECONDITION := &"command.reject.precondition"

## v1.3 (ADR-0005 Ek E): yol komutuna özgü ret anahtarı ailesi. Bu önekli anahtar ret anahtarının KENDİSİdir
## (`public_work.reject.{too_short, too_long, water, slope, not_connected, crosses_parcels, duplicate,
## outside_jurisdiction, busy, nothing_to_undo, bad_class}`; kümeyi world hattı büyütebilir, önek sabittir).
const REJECT_PUBLIC_WORK_PREFIX := "public_work.reject."
const REJECT_NOTHING_TO_UNDO := &"public_work.reject.nothing_to_undo"
## v1.5 (ADR-0005 Ek F): kamulaştırmaya özgü ret anahtarları (aynı `public_work.reject.` ailesi, passthrough).
## `protected_structure`: alınacak parsellerde korunan (tarihî/simge/kamu) yapı var; `expropriation_disabled`:
## bayrak/veri
## kapalı ya da bu oturumda dünya kamulaştırmayı sunmuyor; `expropriation_changed`: tick'te dünyanın aldığı küme
## sim'in hesabından farklı çıktı (durum bozulmaz); `economy_not_started`: ilk günlük tick geçmeden etki hesaplanamaz.
const REJECT_PROTECTED_STRUCTURE := &"public_work.reject.protected_structure"
const REJECT_EXPROPRIATION_DISABLED := &"public_work.reject.expropriation_disabled"
const REJECT_EXPROPRIATION_CHANGED := &"public_work.reject.expropriation_changed"
const REJECT_ECONOMY_NOT_STARTED := &"public_work.reject.economy_not_started"

var command_id: int = SimContract.NO_ID
var kind: StringName = &""
var status: StringName = STATUS_REJECTED
var reason_key: StringName = &""
## Metin şablonu argümanları (yalnız ilkel değerler; UI `{param}` gibi yer tutuculara koyar).
var args: Dictionary = {}
## Duruma bağlı retlerde/kararlarda bağlı gerekçe kayıtları (isteğe bağlı).
var reason_ids: PackedInt64Array = PackedInt64Array()
## Gönderildiği tick ve (kuyruktaysa) uygulanacağı tick.
var tick: int = 0
var apply_tick: int = 0
var provenance: StringName = SimContract.PROVENANCE_SIM


func is_rejected() -> bool:
	return status == STATUS_REJECTED


static func rejected(command: SimCommand, key: StringName, reject_args: Dictionary, at_tick: int,
		source: StringName) -> CommandResult:
	var r := CommandResult.new()
	r.kind = command.kind if command != null else &""
	r.status = STATUS_REJECTED
	r.reason_key = key
	r.args = SimContract.to_args(reject_args)
	r.tick = at_tick
	r.apply_tick = at_tick
	r.provenance = source
	return r


static func accepted(command: SimCommand, status_value: StringName, id: int, at_tick: int,
		source: StringName) -> CommandResult:
	var r := CommandResult.new()
	r.command_id = id
	r.kind = command.kind
	r.status = status_value
	r.tick = at_tick
	r.apply_tick = at_tick + 1
	r.provenance = source
	return r


func to_dict() -> Dictionary:
	return {
		"command_id": command_id, "kind": kind, "status": status, "reason_key": reason_key,
		"args": SimContract.to_args(args), "reason_ids": reason_ids, "tick": tick, "apply_tick": apply_tick,
		"provenance": provenance,
	}


static func from_dict(d: Dictionary) -> CommandResult:
	var r := CommandResult.new()
	r.command_id = SimContract.to_int(d.get("command_id"))
	r.kind = SimContract.to_name(d.get("kind"))
	r.status = SimContract.to_name(d.get("status", STATUS_REJECTED))
	r.reason_key = SimContract.to_name(d.get("reason_key", ""))
	r.args = SimContract.to_args(d.get("args", {}))
	r.reason_ids = SimContract.to_int64_array(d.get("reason_ids", []))
	r.tick = SimContract.to_int(d.get("tick"))
	r.apply_tick = SimContract.to_int(d.get("apply_tick"))
	r.provenance = SimContract.to_name(d.get("provenance", SimContract.PROVENANCE_SIM))
	return r
