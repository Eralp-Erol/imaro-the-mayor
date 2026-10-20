class_name ReasonLog
extends RefCounted
## Gerekçe kaydı altyapısı (T-002, SIM-12, ADR-0002 Karar 7). Her aktör kararı {aktör, karar, faktörler, eşik}
## kaydı üretir; UI ve testler buradan okur. Sim'e özgü tür; sözleşme DTO'suna (ReasonRecord) uyum adaptörü T-027'dedir.
##
## Kayıt alanları: id (artan, budanınca da tekrar kullanılmaz), tick, actor (String/StringName/int), decision
## (String/StringName), factors [{name, value, weight}] (value/weight int veya float; weight yoksa 1),
## threshold (int veya float), code (kısa makine-okur gerekçe kodu, boş olabilir; ör. &"yield_below_threshold").
## Kapasite aşılınca en eski kayıtlar budanır (kapasite `GameState.config.reason_log_capacity`, kayıtla taşınır).

var _records: Array = []
var _next_id: int = 0
var _capacity: int = 1


func _init(capacity: int = 1) -> void:
	_capacity = maxi(1, capacity)


func size() -> int:
	return _records.size()


## Kaydı ekler ve id'sini döndürür; geçersiz girdide push_error + -1 (kayıt eklenmez).
func record(tick: int, actor: Variant, decision: Variant, factors: Array, threshold: Variant,
		code: StringName = &"") -> int:
	var error := _validate(actor, decision, factors, threshold)
	if not error.is_empty():
		push_error("ReasonLog: %s" % error)
		return -1
	var normalized: Array = []
	for factor: Dictionary in factors:
		normalized.append({
			"name": factor["name"],
			"value": factor["value"],
			"weight": factor.get("weight", 1),
		})
	var id := _next_id
	_next_id += 1
	_records.append({
		"id": id, "tick": tick, "actor": actor, "decision": decision,
		"factors": normalized, "threshold": threshold, "code": code,
	})
	while _records.size() > _capacity:
		_records.pop_front()
	return id


## Kayıt kopyası; yoksa (veya budanmışsa) boş sözlük.
func by_id(id: int) -> Dictionary:
	for i in range(_records.size() - 1, -1, -1):
		var rec: Dictionary = _records[i]
		if rec["id"] == id:
			return rec.duplicate(true)
		if rec["id"] < id:
			break
	return {}


## Süzgeç anahtarları (hepsi isteğe bağlı, VE ile birleşir): actor, decision, code, from_tick, to_tick (dahil).
## Sonuç eskiden yeniye sıralı KOPYALAR dizisidir.
func find(filter: Dictionary) -> Array:
	var out: Array = []
	for rec: Dictionary in _records:
		if _matches(rec, filter):
			out.append(rec.duplicate(true))
	return out


## `find` ile eşleşen en yeni kayıt; yoksa boş sözlük.
func latest(filter: Dictionary) -> Dictionary:
	for i in range(_records.size() - 1, -1, -1):
		if _matches(_records[i], filter):
			return (_records[i] as Dictionary).duplicate(true)
	return {}


func to_dict() -> Dictionary:
	return {"capacity": _capacity, "next_id": _next_id, "records": _records.duplicate(true)}


## Hash için kopyasız görünüm (salt okunur kullanın).
func to_dict_view() -> Dictionary:
	return {"capacity": _capacity, "next_id": _next_id, "records": _records}


static func from_dict(data: Dictionary) -> ReasonLog:
	var result := ReasonLog.new(int(data["capacity"]))
	result._next_id = int(data["next_id"])
	result._records = (data["records"] as Array).duplicate(true)
	return result


## Biçim hatası metni; geçerliyse "".
static func validate_dict(data: Variant) -> String:
	if not (data is Dictionary):
		return "reasons bölümü sözlük değil"
	for key in ["capacity", "next_id"]:
		if typeof(data.get(key, null)) != TYPE_INT:
			return "reasons.%s int değil" % key
	if not (data.get("records", null) is Array):
		return "reasons.records dizi değil"
	for rec: Variant in data["records"]:
		if not (rec is Dictionary):
			return "reasons.records öğesi sözlük değil"
		for key in ["id", "tick"]:
			if typeof(rec.get(key, null)) != TYPE_INT:
				return "reasons kaydında %s int değil" % key
		for key in ["actor", "decision", "factors", "threshold", "code"]:
			if not rec.has(key):
				return "reasons kaydında %s yok" % key
	return ""


func _matches(rec: Dictionary, filter: Dictionary) -> bool:
	if filter.has("actor") and not _same(rec["actor"], filter["actor"]):
		return false
	if filter.has("decision") and not _same(rec["decision"], filter["decision"]):
		return false
	if filter.has("code") and not _same(rec["code"], filter["code"]):
		return false
	if filter.has("from_tick") and rec["tick"] < int(filter["from_tick"]):
		return false
	if filter.has("to_tick") and rec["tick"] > int(filter["to_tick"]):
		return false
	return true


## String ile StringName eşit sayılır; int yalnız int ile; türler uyuşmazsa false (Variant != hata vermesin).
static func _same(a: Variant, b: Variant) -> bool:
	var a_text := typeof(a) == TYPE_STRING or typeof(a) == TYPE_STRING_NAME
	var b_text := typeof(b) == TYPE_STRING or typeof(b) == TYPE_STRING_NAME
	if a_text and b_text:
		return str(a) == str(b)
	if typeof(a) == TYPE_INT and typeof(b) == TYPE_INT:
		return a == b
	return false


static func _is_name(value: Variant) -> bool:
	return (typeof(value) == TYPE_STRING or typeof(value) == TYPE_STRING_NAME) and not str(value).is_empty()


static func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT


static func _validate(actor: Variant, decision: Variant, factors: Array, threshold: Variant) -> String:
	if not (_is_name(actor) or typeof(actor) == TYPE_INT):
		return "actor must be a non-empty String/StringName or an int"
	if not _is_name(decision):
		return "decision must be a non-empty String/StringName"
	if not _is_number(threshold):
		return "threshold must be int or float"
	for i in factors.size():
		var factor: Variant = factors[i]
		if not (factor is Dictionary) or not _is_name(factor.get("name", null)):
			return "factor[%d] needs a non-empty 'name'" % i
		if not _is_number(factor.get("value", null)):
			return "factor[%d] 'value' must be int or float" % i
		if factor.has("weight") and not _is_number(factor["weight"]):
			return "factor[%d] 'weight' must be int or float" % i
	return ""
