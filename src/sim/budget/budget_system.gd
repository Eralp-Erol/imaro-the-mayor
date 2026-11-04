class_name BudgetSystem
extends SimSystem
## Gösterge bütçe sistemi (T-043C, D-010 karar 3, CAN-06/SIM-04/SIM-12). Vergi geliri ve yol gideri HESAPLANIR ve
## gösterilir; kasa KISIT DEĞİLDİR: hiçbir komutu reddetmez, hiçbir ekonomi kararını değiştirmez (CAN-03: bu sistem
## ekonomi durumunu yalnız OKUR, hiçbir parsel/bina sütunu yazmaz). `budget.propose` kurulmaz (UnbuiltCommandHandler
## kalır).
##
## - Gelir (ay sonu, `on_monthly`): (bitmiş konut birimi x konut kirası + bitmiş ticaret birimi x ticaret kirası) x
##   tax_rate_pm / 1000, sıfıra doğru kesme. Birimler `EconomyState` bölge sütunlarından (res_built/com_built), kira
##   sayıları ekonomi yapılandırmasından; çoğaltılmaz.
## - Gider (`on_daily`): oyuncu yolu listesi (`PublicWorksState.works`, salt okunur) ile tahsilat listesi eşitlenir:
##   yeni yol = birim x cost_per_unit(kullanım) x public_cost_share_pm / 1000 gider; listeden düşen (geri alınan,
##   LIFO) yol tahsil edildiği tutarla iade. Böylece yol işleyicilerine dokunulmaz; komutlar aynı tick sınırında önce
##   uygulanır, sistem aynı tick'te eşitler.
## - Yol YIKILIRSA (T-042c, D-014 §1; `PublicWorksState.works[i].demolished_by`) yıkım gideri BİR KEZ yazılır: yolun
##   uzunluğu (m) x `road.demolish_cost_per_m`; yapım gideri iade EDİLMEZ, `charged` satırının tutarına eklenir.
## - Yeniden iskân bedeli (T-065; `works[i].expropriation.resettlement.cost` > 0): yolla birlikte BİR KEZ ayrı kalem
##   olarak yazılır (`charged[i].resettlement`, tembel `resettlement_net`); yol geri alınınca iade edilir. Bedel yol
##   kalemine katılmaz ve hiçbir komutu engellemez.
## - Her kalem gerekçe kaydı taşır (`actor.municipality.1`; faktör `budget.factor.amount` tutarı, ağırlığı 0 olan
##   faktörler girdileri gösterir) ve kalem defterine yazılır. Tüm sayılar `BudgetConfig`tedir.
## Sistem DURUM TUTMAZ: kalıcı veri `state.systems["budget"]`; nesnedeki alanlar yalnız değişmez yapılandırmadır.

const SYSTEM := &"budget"
const ACTOR := &"actor.municipality.1"
const DECISION_TAX := &"decision.budget.tax_revenue"
const DECISION_ROAD_COST := &"decision.budget.road_cost"
const DECISION_ROAD_REFUND := &"decision.budget.road_refund"
const DECISION_ROAD_DEMOLISH := &"decision.budget.road_demolish"
const DECISION_RESETTLEMENT := &"decision.budget.resettlement"
const DECISION_RESETTLEMENT_REFUND := &"decision.budget.resettlement_refund"
const LINE_ROADS := &"budget.line.roads"
const FACTOR_AMOUNT := &"budget.factor.amount"
const _EVENT_COMPLETED := "event.construction.completed"
const _EVENT_KIND_PARCEL := "parcel.changed"

var _cfg: BudgetConfig
var _rent_residential: int = 0
var _rent_commercial: int = 0
var _unit_cost: int = 0


## Kurulum sorunu (Türkçe) ya da "".
static func setup_problem(cfg: BudgetConfig, economy: EconomyConfig) -> String:
	if cfg == null or not cfg.is_valid():
		return "bütçe yapılandırması geçersiz: %s" % ("null" if cfg == null else cfg.error)
	if economy == null or not economy.is_valid():
		return "ekonomi yapılandırması yok ya da geçersiz"
	var use := EconomyState.use_id(cfg.road_cost_use)
	if use == EconomyConfig.USE_NONE or not economy.uses.has(use):
		return "road.cost_use '%s' ekonomi yapılandırmasında yok" % cfg.road_cost_use
	return ""


## Sistem; sorunda push_error + null.
static func create(cfg: BudgetConfig, economy: EconomyConfig) -> BudgetSystem:
	var problem := setup_problem(cfg, economy)
	if not problem.is_empty():
		push_error("BudgetSystem: %s" % problem)
		return null
	var system := BudgetSystem.new()
	system._cfg = cfg
	system._rent_residential = economy.use_param(EconomyConfig.USE_RESIDENTIAL, "rent_per_unit_month")
	system._rent_commercial = economy.use_param(EconomyConfig.USE_COMMERCIAL, "rent_per_unit_month")
	system._unit_cost = economy.use_param(EconomyState.use_id(cfg.road_cost_use), "cost_per_unit")
	return system


func system_id() -> StringName:
	return SYSTEM


func config() -> BudgetConfig:
	return _cfg


func on_daily(state: GameState) -> void:
	var d := BudgetState.ensure(state, _cfg.initial_balance)
	_reconcile_roads(state, d)


func on_monthly(state: GameState) -> void:
	_collect_tax(state, BudgetState.ensure(state, _cfg.initial_balance))


# --- Salt okunur sorgular ---

## Yolu yıkma gideri: yol uzunluğu (cm -> m, sıfıra doğru kesme) x metre başına maliyet.
@warning_ignore("integer_division")
func demolish_cost(length_cm: int) -> int:
	return maxi(length_cm, 0) / 100 * _cfg.demolish_cost_per_m


## Yol gideri: eklenen altyapı birimi x cost_per_unit x pay / 1000 (sıfıra doğru kesme).
## Önizleme ve tahsilat AYNI hesap.
@warning_ignore("integer_division")
func road_cost(units_total: int) -> int:
	return maxi(units_total, 0) * _unit_cost * _cfg.public_cost_share_pm / 1000


## `BudgetView` (değer kopyası). Bölüm yoksa (kurulu ama ilk tick geçmedi) başlangıç değerleriyle. Durumu DEĞİŞTİRMEZ.
## `revenue` = son KAPANAN ayın vergi geliri; `balance` = kasa (negatif olabilir); tek gider kalemi `budget.line.roads`
## (tutar = başlangıçtan net yol gideri). `period` = açık ayın sıra numarası. `reason_ids` = en yeni kalemlerin
## gerekçeleri (eskiden yeniye; gerekçe günlüğü budamış olabilir).
func view(state: GameState) -> BudgetView:
	var v := BudgetView.new()
	v.period = state.month_index()
	v.status = BudgetView.STATUS_APPROVED
	var d := BudgetState.data(state)
	var roads := 0
	if d.is_empty():
		v.balance = _cfg.initial_balance
	else:
		v.revenue = int(d["revenue_last"])
		v.balance = int(d["balance"])
		roads = int(d["roads_net"])
		v.reason_ids = BudgetState.recent_reason_ids(state, _cfg.view_reason_limit)
	var line := BudgetLineView.make(LINE_ROADS, roads)
	line.actual = roads
	v.lines.append(line)
	if d.has("resettlement_net"):  # yalnız bedel yazıldıysa (politika hiç bedel doğurmadıysa satır yok)
		var resettlement_line := BudgetLineView.make(BudgetLineView.KEY_RESETTLEMENT, int(d["resettlement_net"]))
		resettlement_line.actual = int(d["resettlement_net"])
		v.lines.append(resettlement_line)
	return v


## Komut önizleme argümanlarına maliyeti ekler (`cost_available`, `cost`; geri almada `refund_available`, `refund`).
## Önizleme sim'in kendi hesabıdır (UI sayı üretmez). `args` yerinde değişir; durumu DEĞİŞTİRMEZ.
func decorate_preview(state: GameState, kind: StringName, args: Dictionary) -> void:
	if kind == SimCommand.KIND_PUBLIC_WORK_ROAD and args.has("units_total"):
		args["cost_available"] = true
		args["cost"] = road_cost(int(args["units_total"]))
		args.erase("cost_reason_key")
	elif kind == SimCommand.KIND_PUBLIC_WORK_DEMOLISH and args.has("length_cm"):
		args["cost_available"] = true
		args["cost"] = demolish_cost(int(args["length_cm"]))
		args.erase("cost_reason_key")
	elif kind == SimCommand.KIND_PUBLIC_WORK_UNDO_LAST and args.has("removed_command_id"):
		var charged := BudgetState.charged_amount(state, int(args["removed_command_id"]))
		if charged >= 0:
			args["refund_available"] = true
			args["refund"] = charged


# --- Yol gideri ---

func _reconcile_roads(state: GameState, d: Dictionary) -> void:
	var works := _works_of(state)
	var charged: Array = d["charged"]
	var common := 0
	while common < charged.size() and common < works.size() \
			and int((charged[common] as Dictionary)["command_id"]) == int((works[common] as Dictionary)["command_id"]):
		common += 1
	while charged.size() > common:  # geri alınan yollar, LIFO iade
		var entry: Dictionary = charged.pop_back()
		_book_road(state, d, int(entry["command_id"]), int(entry["amount"]), true, 0)
		if entry.has("resettlement"):
			_book_resettlement(state, d, int(entry["command_id"]), int(entry["resettlement"]), true)
	for i in common:  # yıkılan yollar: yıkım gideri bir kez
		if (works[i] as Dictionary).has("demolished_by") and not bool((charged[i] as Dictionary).get("demolished", false)):
			_book_demolition(state, d, charged[i], works[i])
	for i in range(common, works.size()):
		var work: Dictionary = works[i]
		var units := PublicWorksState.total_units(work["region_units"])
		var amount := road_cost(units)
		var entry := {"command_id": int(work["command_id"]), "amount": amount}
		charged.append(entry)
		_book_road(state, d, int(work["command_id"]), amount, false, units)
		var cost := PublicWorksState.resettlement_cost(work)
		if cost > 0:
			entry["resettlement"] = cost
			_book_resettlement(state, d, int(work["command_id"]), cost, false)


func _book_demolition(state: GameState, d: Dictionary, entry: Dictionary, work: Dictionary) -> void:
	var cost := demolish_cost(int(work["length_cm"]))
	var ref := String(SimContract.ref(SimContract.REF_COMMAND, int(work["demolished_by"])))
	var factors: Array = [{"name": FACTOR_AMOUNT, "value": cost, "source_ref": ref},
		{"name": &"budget.factor.length_cm", "value": int(work["length_cm"]), "weight": 0},
		{"name": &"budget.factor.demolish_cost_per_m", "value": _cfg.demolish_cost_per_m, "weight": 0}]
	var reason_id := state.record_reason(ACTOR, DECISION_ROAD_DEMOLISH, factors, 0, &"road_demolish",
		PackedStringArray([ref, String(SimContract.ref(SimContract.REF_COMMAND, int(work["command_id"])))]))
	entry["amount"] = int(entry["amount"]) + cost
	entry["demolished"] = true
	d["roads_net"] = int(d["roads_net"]) + cost
	d["balance"] = int(d["balance"]) - cost
	BudgetState.add_ledger(d, state.tick, BudgetState.KIND_ROAD_DEMOLISH, cost, ref, reason_id, _cfg.ledger_max)


## Yeniden iskân bedeli (T-065): ayrı kalem, ayrı gerekçe, `resettlement_net` tembel yaratılır.
func _book_resettlement(state: GameState, d: Dictionary, command_id: int, cost: int, refund: bool) -> void:
	var ref := String(SimContract.ref(SimContract.REF_COMMAND, command_id))
	var factors: Array = [{"name": FACTOR_AMOUNT, "value": cost, "source_ref": ref}]
	var reason_id := state.record_reason(ACTOR, DECISION_RESETTLEMENT_REFUND if refund else DECISION_RESETTLEMENT,
		factors, 0, &"resettlement_refund" if refund else &"resettlement", PackedStringArray([ref]))
	var sign := -1 if refund else 1
	d["resettlement_net"] = int(d.get("resettlement_net", 0)) + sign * cost
	d["balance"] = int(d["balance"]) - sign * cost
	BudgetState.add_ledger(d, state.tick, BudgetState.KIND_RESETTLEMENT_REFUND if refund
		else BudgetState.KIND_RESETTLEMENT, cost, ref, reason_id, _cfg.ledger_max)


func _book_road(state: GameState, d: Dictionary, command_id: int, amount: int, refund: bool,
		units: int) -> void:
	var ref := String(SimContract.ref(SimContract.REF_COMMAND, command_id))
	var factors: Array = [{"name": FACTOR_AMOUNT, "value": amount, "source_ref": ref}]
	if not refund:
		factors.append({"name": &"budget.factor.infra_units", "value": units, "weight": 0,
			"source_ref": ref})
		factors.append({"name": &"budget.factor.unit_cost", "value": _unit_cost, "weight": 0})
		factors.append({"name": &"budget.factor.public_share_pm", "value": _cfg.public_cost_share_pm, "weight": 0})
	var reason_id := state.record_reason(ACTOR, DECISION_ROAD_REFUND if refund else DECISION_ROAD_COST, factors, 0,
		&"road_refund" if refund else &"road_cost", PackedStringArray([ref]))
	var sign := -1 if refund else 1
	d["roads_net"] = int(d["roads_net"]) + sign * amount
	d["balance"] = int(d["balance"]) - sign * amount
	BudgetState.add_ledger(d, state.tick, BudgetState.KIND_ROAD_REFUND if refund else BudgetState.KIND_ROAD_COST,
		amount, ref, reason_id, _cfg.ledger_max)


## Oyuncu YOLU satırları (salt okunur; yıkım satırları hariç; yıkılmış yol satırı yerinde durur; bölüm yoksa boş).
static func _works_of(state: GameState) -> Array:
	var section := PublicWorksState.data(state)
	var out: Array = []
	if section.is_empty():
		return out
	for work: Dictionary in section["works"]:
		if PublicWorksState.is_road_work(work):
			out.append(work)
	return out


# --- Vergi ---

@warning_ignore("integer_division")
func _collect_tax(state: GameState, d: Dictionary) -> void:
	var residential := 0
	var commercial := 0
	var economy := EconomyState.data(state)
	if not economy.is_empty():
		var regions: Dictionary = economy["regions"]
		for units in regions["res_built"] as PackedInt64Array:
			residential += units
		for units in regions["com_built"] as PackedInt64Array:
			commercial += units
	var revenue := (residential * _rent_residential + commercial * _rent_commercial) * _cfg.tax_rate_pm / 1000
	var parcels := _completed_parcels(state, d)
	d["event_cursor"] = SimEventLog.last_seq(state)
	d["revenue_last"] = revenue
	if revenue == 0:
		return
	d["revenue_total"] = int(d["revenue_total"]) + revenue
	d["balance"] = int(d["balance"]) + revenue
	var period_ref := String(SimContract.ref(SimContract.REF_BUDGET, state.month_index()))
	var subjects := PackedStringArray([period_ref])
	subjects.append_array(parcels["refs"])
	var factors: Array = [
		{"name": FACTOR_AMOUNT, "value": revenue},
		{"name": &"budget.factor.residential_units", "value": residential, "weight": 0},
		{"name": &"budget.factor.commercial_units", "value": commercial, "weight": 0},
		{"name": &"budget.factor.tax_rate_pm", "value": _cfg.tax_rate_pm, "weight": 0},
		{"name": &"budget.factor.completed_buildings", "value": int(parcels["count"]), "weight": 0},
	]
	var reason_id := state.record_reason(ACTOR, DECISION_TAX, factors, 0, &"tax_revenue", subjects)
	BudgetState.add_ledger(d, state.tick, BudgetState.KIND_TAX, revenue, period_ref, reason_id, _cfg.ledger_max)


## Son okumadan beri tamamlanan yapıların parsel referansları (en çok `reason_parcel_limit`) ve toplam sayısı.
## Olay günlüğü budanmışsa yalnız saklanan olaylar sayılır (tutar etkilenmez: gelir ekonomi sütunlarından gelir).
func _completed_parcels(state: GameState, d: Dictionary) -> Dictionary:
	var refs := PackedStringArray()
	var count := 0
	for rec: Dictionary in SimEventLog.records_after(state, int(d["event_cursor"])):
		if str(rec["kind"]) != _EVENT_KIND_PARCEL or str(rec["message_key"]) != _EVENT_COMPLETED:
			continue
		count += 1
		if refs.size() < _cfg.reason_parcel_limit and not (rec["subjects"] as PackedStringArray).is_empty():
			refs.append((rec["subjects"] as PackedStringArray)[0])
	return {"refs": refs, "count": count}
