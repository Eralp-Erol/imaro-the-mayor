class_name BudgetView
extends SimDto
## Belediye bütçesinin değer kopyası (ADR-0005). Tutarlar birimsiz tamsayı (Q-003): para adı/simgesi yalnız
## yapılandırmadan (`economy.currency_name`, `economy.currency_symbol`; geçici gösterim `¤`) biçimlenir.
## Bütçe önerisi meclis oylamasından geçer (SIM-05): `status == proposed` iken `pending_vote_id` oylamayı gösterir.

const STATUS_DRAFT := &"draft"
const STATUS_PROPOSED := &"proposed"
const STATUS_APPROVED := &"approved"
const STATUS_REJECTED := &"rejected"

## Bütçe dönemi sıra numarası (takvim eşlemesi yapılandırmadadır, ÇM).
var period: int = 0
var status: StringName = STATUS_DRAFT
var revenue: int = 0
## Kasa/rezerv (negatif olabilir: borç).
var balance: int = 0
var lines: Array[BudgetLineView] = []
var pending_vote_id: int = SimContract.NO_ID
var reason_ids: PackedInt64Array = PackedInt64Array()


func expenses() -> int:
	var total := 0
	for l in lines:
		total += l.amount
	return total


func proposed_expenses() -> int:
	var total := 0
	for l in lines:
		total += l.proposed
	return total


func line(key: StringName) -> BudgetLineView:
	for l in lines:
		if l.line_key == key:
			return l
	return null


func to_dict() -> Dictionary:
	return {
		"period": period, "status": status, "revenue": revenue, "balance": balance,
		"lines": SimDto.dicts_of(lines), "pending_vote_id": pending_vote_id, "reason_ids": reason_ids,
	}


static func from_dict(d: Dictionary) -> BudgetView:
	var b := BudgetView.new()
	b.period = SimContract.to_int(d.get("period"))
	b.status = SimContract.to_name(d.get("status", STATUS_DRAFT))
	b.revenue = SimContract.to_int(d.get("revenue"))
	b.balance = SimContract.to_int(d.get("balance"))
	for ld: Variant in d.get("lines", []):
		if ld is Dictionary:
			b.lines.append(BudgetLineView.from_dict(ld))
	b.pending_vote_id = SimContract.to_int(d.get("pending_vote_id"))
	b.reason_ids = SimContract.to_int64_array(d.get("reason_ids", []))
	return b
