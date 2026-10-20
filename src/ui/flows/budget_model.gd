class_name BudgetModel
extends RefCounted
## Bütçe görünümü modeli (ux-flows-v0 §F, T-022): `BudgetView` -> satırlar. Tutarlar birimsiz tamsayıdır (Q-003);
## para simgesi yalnız `UiText.money` ile yapılandırmadan gelir. Pay (gider içindeki oran) tamsayı ve YALNIZ
## kalemlerin gerçek tutarlarından hesaplanır; öngörü/kapasite sim vermedikçe gösterilmez (UI uydurmaz).

var period: int = 0
var status: StringName = BudgetView.STATUS_DRAFT
var revenue: int = 0
var balance: int = 0
var expenses: int = 0
var pending_vote_id: int = SimContract.NO_ID
var reason_ids: PackedInt64Array = PackedInt64Array()
var rows: Array[LineRow] = []


class LineRow:
	extends RefCounted
	var key: StringName = &""
	var amount: int = 0
	var proposed: int = 0
	var actual: int = 0
	## Giderdeki payı, binde.
	var share_permille: int = 0

	func delta() -> int:
		return proposed - amount


@warning_ignore("integer_division")
static func build(view: BudgetView) -> BudgetModel:
	var m := BudgetModel.new()
	m.period = view.period
	m.status = view.status
	m.revenue = view.revenue
	m.balance = view.balance
	m.expenses = view.expenses()
	m.pending_vote_id = view.pending_vote_id
	m.reason_ids = view.reason_ids
	for l in view.lines:
		var r := LineRow.new()
		r.key = l.line_key
		r.amount = l.amount
		r.proposed = l.proposed
		r.actual = l.actual
		r.share_permille = clampi(l.amount * 1000 / m.expenses, 0, 1000) if m.expenses > 0 else 0
		m.rows.append(r)
	return m


func is_debt() -> bool:
	return balance < 0


## Öneri oylamadadır: düzenleme kilitli (sim aynı konuda ikinci öneriyi reddeder).
func is_locked() -> bool:
	return status == BudgetView.STATUS_PROPOSED


func line(key: StringName) -> LineRow:
	for r in rows:
		if r.key == key:
			return r
	return null


## Bekleyen öneri toplamı ile yürürlükteki toplam arasındaki fark (yalnız öneride anlamlı).
func proposed_delta() -> int:
	var total := 0
	for r in rows:
		total += r.delta()
	return total
