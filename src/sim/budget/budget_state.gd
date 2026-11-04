class_name BudgetState
extends RefCounted
## Gösterge bütçe durum bölümü `state.systems["budget"]` (T-043C). Bölüm YALNIZ bütçe sistemi kurulu ve ilk günlük tick
## çalışınca yaratılır; okuma/önizleme bölüm yaratmaz. Bütçesiz yapılandırmada bölüm hiç yoktur, bu yüzden t0 ve altın
## hash'ler (GOLDEN_A/B) bit-bit aynıdır. Para birimsiz tamsayıdır (Q-003); float yok.
##
## Düzen (hepsi düz veri):
##   version           VERSION
##   initial_balance   kasanın başlangıç değeri (veriden kopyalanır; tutarlılık denetimi için saklanır)
##   balance           kasa = initial_balance + revenue_total - roads_net - resettlement_net (negatif olabilir:
##                     GÖSTERGE, kısıt yok)
##   revenue_last      son KAPANAN ayın vergi geliri (ay sonunda yazılır; arada değişmez)
##   revenue_total     başlangıçtan toplanan vergi
##   roads_net         yol gideri - iadeler (başlangıçtan; yol kalemi tutarı)
##   resettlement_net  TEMBEL (T-065; yalnız ilk yeniden iskân bedelinde yaratılır, yoksa 0): başlangıçtan net
##                     yeniden iskân bedeli; yol kalemine KATILMAZ (SIM-07: yanlış kalem gösterilmez)
##   charged           [{command_id, amount, resettlement?, demolished?}] yol listesiyle (PublicWorksState.works, yıkım
##                     satırları hariç) aynı sırada tahsil edilmiş yollar; `amount` yıkılmış yolda yapım + yıkım
##                     gideridir (T-042c); `resettlement` yalnız > 0 iken (T-065)
##   event_cursor      vergi gerekçesinin tamamlanan parselleri için okunan son olay seq'i
##   ledger            [{tick, kind, amount, ref, reason_id}] son `ledger.max_entries` kalem (eskiden yeniye)

const KEY := "budget"
const VERSION := 1
const KIND_TAX := "tax"
const KIND_ROAD_COST := "road_cost"
const KIND_ROAD_REFUND := "road_refund"
const KIND_ROAD_DEMOLISH := "road_demolish"
const KIND_RESETTLEMENT := "resettlement"
const KIND_RESETTLEMENT_REFUND := "resettlement_refund"
const _LEDGER_KINDS: Array[String] = [KIND_TAX, KIND_ROAD_COST, KIND_ROAD_REFUND, KIND_ROAD_DEMOLISH,
	KIND_RESETTLEMENT, KIND_RESETTLEMENT_REFUND]
const _INT_FIELDS: Array[String] = [
	"initial_balance", "balance", "revenue_last", "revenue_total", "roads_net", "event_cursor",
]


## Bölüm (DOĞRUDAN durumun parçası); yoksa boş sözlük. Bölüm yaratmaz.
static func data(state: GameState) -> Dictionary:
	var d: Variant = state.systems.get(KEY, null)
	return d if d is Dictionary and d.has("version") else {}


static func is_present(state: GameState) -> bool:
	return not data(state).is_empty()


## Bölümü ilk kez kurar (bütçe sistemi günlük tick'te çağırır) ve döndürür; varsa mevcut olanı verir.
static func ensure(state: GameState, initial_balance: int) -> Dictionary:
	var d := state.system_data(StringName(KEY))
	if not d.has("version"):
		d["version"] = VERSION
		d["initial_balance"] = initial_balance
		d["balance"] = initial_balance
		d["revenue_last"] = 0
		d["revenue_total"] = 0
		d["roads_net"] = 0
		d["charged"] = []
		d["event_cursor"] = 0
		d["ledger"] = []
	return d


## Kalemi deftere ekler; `max_entries` aşılınca en eskiler budanır.
static func add_ledger(d: Dictionary, tick: int, kind: String, amount: int, ref: String, reason_id: int,
		max_entries: int) -> void:
	var ledger: Array = d["ledger"]
	ledger.append({"tick": tick, "kind": kind, "amount": amount, "ref": ref, "reason_id": reason_id})
	while ledger.size() > max_entries:
		ledger.pop_front()


## Tahsil edilmiş yolun tutarı (komut kimliğine göre); yoksa -1.
static func charged_amount(state: GameState, command_id: int) -> int:
	var d := data(state)
	if d.is_empty():
		return -1
	for entry: Dictionary in d["charged"]:
		if int(entry["command_id"]) == command_id:
			return int(entry["amount"])
	return -1


## En yeni `limit` kalemin geçerli gerekçe kimlikleri (>0), eskiden yeniye.
static func recent_reason_ids(state: GameState, limit: int) -> PackedInt64Array:
	var out := PackedInt64Array()
	var d := data(state)
	if d.is_empty():
		return out
	var ledger: Array = d["ledger"]
	var i := ledger.size() - 1
	var picked: Array[int] = []
	while i >= 0 and picked.size() < limit:
		var rid := int((ledger[i] as Dictionary)["reason_id"])
		if rid > 0:
			picked.append(rid)
		i -= 1
	picked.reverse()
	out.append_array(PackedInt64Array(picked))
	return out


## Bölüm biçim/tutarlılık hatası (Türkçe) ya da "". Bölüm yoksa geçerli.
static func validate_data(value: Variant) -> String:
	if value == null:
		return ""
	if not (value is Dictionary) or value.get("version", null) != VERSION:
		return "durum.systems.budget sürümü geçersiz"
	for field_name in _INT_FIELDS:
		if typeof(value.get(field_name, null)) != TYPE_INT:
			return "durum.systems.budget.%s tamsayı değil" % field_name
	for field_name in ["charged", "ledger"]:
		if not (value.get(field_name, null) is Array):
			return "durum.systems.budget.%s dizi değil" % field_name
	var net := 0
	var resettlement := 0
	for entry: Variant in value["charged"]:
		if not (entry is Dictionary) or typeof(entry.get("command_id", null)) != TYPE_INT \
				or typeof(entry.get("amount", null)) != TYPE_INT or int(entry["command_id"]) < 1 \
				or (entry.has("resettlement") and (typeof(entry["resettlement"]) != TYPE_INT \
				or int(entry["resettlement"]) <= 0)):
			return "durum.systems.budget.charged öğesi geçersiz"
		net += int(entry["amount"])
		resettlement += int(entry.get("resettlement", 0))
	if value.has("resettlement_net") and typeof(value["resettlement_net"]) != TYPE_INT:
		return "durum.systems.budget.resettlement_net tamsayı değil"
	if int(value.get("resettlement_net", 0)) != resettlement:
		return "durum.systems.budget.resettlement_net tahsil edilen bedellerin toplamıyla uyuşmuyor"
	if net != int(value["roads_net"]):
		return "durum.systems.budget.roads_net tahsil edilen yolların toplamıyla uyuşmuyor"
	if int(value["balance"]) != int(value["initial_balance"]) + int(value["revenue_total"]) - net - resettlement:
		return "durum.systems.budget.balance başlangıç + gelir - gider ile uyuşmuyor"
	for entry: Variant in value["ledger"]:
		if not (entry is Dictionary) or not _LEDGER_KINDS.has(str(entry.get("kind", ""))) \
				or typeof(entry.get("tick", null)) != TYPE_INT or typeof(entry.get("amount", null)) != TYPE_INT \
				or typeof(entry.get("reason_id", null)) != TYPE_INT or typeof(entry.get("ref", null)) != TYPE_STRING:
			return "durum.systems.budget.ledger öğesi geçersiz"
	return ""
