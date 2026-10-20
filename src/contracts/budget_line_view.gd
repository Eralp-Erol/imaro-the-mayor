class_name BudgetLineView
extends SimDto
## Belediye bütçesinin bir kalemi. Tutarlar birimsiz tamsayıdır (Q-003); kalem sözlüğü sim yapılandırmasındadır.

## Kalem anahtarı = metin anahtarı (örn. `budget.line.roads`).
var line_key: StringName = &""
## Yürürlükteki (onaylı) tutar ve bekleyen önerideki tutar (öneri yoksa = amount).
var amount: int = 0
var proposed: int = 0
## Dönem içi gerçekleşen harcama/gelir.
var actual: int = 0


static func make(key: StringName, line_amount: int) -> BudgetLineView:
	var l := BudgetLineView.new()
	l.line_key = key
	l.amount = line_amount
	l.proposed = line_amount
	return l


func to_dict() -> Dictionary:
	return {"line_key": line_key, "amount": amount, "proposed": proposed, "actual": actual}


static func from_dict(d: Dictionary) -> BudgetLineView:
	var l := make(SimContract.to_name(d.get("line_key")), SimContract.to_int(d.get("amount")))
	l.proposed = SimContract.to_int(d.get("proposed", l.amount))
	l.actual = SimContract.to_int(d.get("actual"))
	return l
