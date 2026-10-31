class_name AgendaItemView
extends SimDto
## Sim'in açtığı bir AÇIK gündem öğesi (v1.5 isteğe bağlı ekleme, ADR-0005 Ek F; T-042b, D-008 "halk tepki versin"):
## `SimFacade.agenda_items()` satırı. Olay motorunun öğesidir (PE-01 yerinden edilme dahil); sim'in kendi kaydı, uydurma
## yok. Meclis oylamaları BURADA DEĞİLDİR: onlar `SimSnapshot.council` içindedir (UI ikisini birleştirir). Yanıt komutu
## (`agenda.respond`) kataloğa girmediği için seçenek alanı YOKTUR: UI seçenek/ertele düğmesi uydurmaz.
## Metin yok: `title_key` anahtardır; `args` kısa ilkel bağlamdır (`topic`, `stage`).
## `reason_ids`: öğeyi açan ateşleme gerekçesi; zinciri `parent_ids` ile neden kaydına (yerinden edilme: hane sayısı)
## iner.
## `cause_refs`: nedenin konusu olan varlıklar (`command.7`, `parcel.12`; sıralı, yinelemesiz). Toplam skor alanı yok.

const STATUS_OPEN := &"open"
const STATUS_RESOLVED := &"resolved"
const STATUS_EXPIRED := &"expired"
const STATUS_LAPSED := &"lapsed"

var provenance: StringName = SimContract.PROVENANCE_SIM
var item_id: int = SimContract.NO_ID
## Olay şablonu kimliği (`PE-01` mahalle protestosu / yerinden edilme, `PE-04` medya ...) ve teslim düzeyi (`agenda` |
## `decision`).
var template_id: StringName = &""
var delivery: StringName = &"agenda"
var status: StringName = STATUS_OPEN
## Öğenin bölgesi (yoksa &"") ve tetikleyen grup (yoksa null).
var region_code: StringName = &""
var group: ActorRef = null
var opened_tick: int = 0
## Süre dolum tick'i (bu tick'te hâlâ açıksa `expired`).
var deadline_tick: int = 0
var title_key: StringName = &""
var args: Dictionary = {}
var reason_ids: PackedInt64Array = PackedInt64Array()
var cause_refs: PackedStringArray = PackedStringArray()


func ref() -> StringName:
	return SimContract.ref(SimContract.REF_AGENDA, item_id)


func to_dict() -> Dictionary:
	return {
		"provenance": provenance, "item_id": item_id, "template_id": template_id, "delivery": delivery,
		"status": status, "region_code": region_code, "group": ActorRef.to_variant(group),
		"opened_tick": opened_tick, "deadline_tick": deadline_tick, "title_key": title_key,
		"args": SimContract.to_args(args), "reason_ids": reason_ids, "cause_refs": cause_refs,
	}


static func from_dict(d: Dictionary) -> AgendaItemView:
	var v := AgendaItemView.new()
	v.provenance = SimContract.to_name(d.get("provenance", SimContract.PROVENANCE_SIM))
	v.item_id = SimContract.to_int(d.get("item_id"))
	v.template_id = SimContract.to_name(d.get("template_id", ""))
	v.delivery = SimContract.to_name(d.get("delivery", "agenda"))
	v.status = SimContract.to_name(d.get("status", STATUS_OPEN))
	v.region_code = SimContract.to_name(d.get("region_code", ""))
	v.group = ActorRef.from_variant(d.get("group"))
	v.opened_tick = SimContract.to_int(d.get("opened_tick"))
	v.deadline_tick = SimContract.to_int(d.get("deadline_tick"))
	v.title_key = SimContract.to_name(d.get("title_key", ""))
	v.args = SimContract.to_args(d.get("args", {}))
	v.reason_ids = SimContract.to_int64_array(d.get("reason_ids", []))
	v.cause_refs = SimContract.to_string_array(d.get("cause_refs", []))
	return v
